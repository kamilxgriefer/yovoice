// Synthetic ISO-BMFF cases for the Yeel rotation scanner (ADR-235), shared by
// the VM suite (reel_video_orientation_test.dart) and the Chrome-platform
// suite (reel_video_orientation_browser_test.dart), so dart2js runs exactly
// the 64-bit, version-1 and malformed shapes the VM does. No dart:io here.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/reels/data/services/reel_video_orientation.dart';

import 'reel_iso_bmff_builder.dart';

Future<ReelVideoOrientationScan> scanBytes(Uint8List bytes) =>
    scanReelVideoOrientation(bytesRangeReader(bytes));

/// Offset of the (only) video matrix in [simpleMovie]-shaped [moovBytes]
/// placed at [moovOffset]: moov header, mvhd, trak header, tkhd header,
/// then the tkhd payload offset.
int matrixOffsetIn(
  int moovOffset, {
  int mvhdLength = 108,
  int tkhdVersion = 0,
}) => moovOffset + 8 + mvhdLength + 8 + 8 + (tkhdVersion == 1 ? 52 : 40);

void defineSyntheticOrientationCases() {
  group('synthetic ISO-BMFF shapes', () {
    test('the ftyp check and the first box header share one read', () async {
      final reader = CountingRangeReader(simpleMovie());
      final starts = <int>[];
      final scan = await scanReelVideoOrientation(
        _RecordingReader(reader, starts),
      );
      expect(scan.orientation, isNotNull);
      expect(starts.where((offset) => offset == 0), hasLength(1));
    });

    test('a plain moov-first movie scans with its matrix offset', () async {
      final bytes = simpleMovie();
      final orientation = (await scanBytes(bytes)).orientation!;
      final track = orientation.tracks.single;
      expect(track.handler, 'vide');
      expect(track.tkhdVersion, 0);
      expect(track.quarterTurns, 0);
      expect(track.matrixOffset, matrixOffsetIn(24));
      expect(track.widthFixed, 64 * isoOne);
      expect(track.heightFixed, 36 * isoOne);
      expect(orientation.length, bytes.length);
    });

    test('largesize (size32 = 1) mdat and moov walk exactly', () async {
      final movie = moov(traks: <List<int>>[trak()]);
      final bytes = concat(<List<int>>[
        ftyp(),
        largeBox('mdat', Uint8List(40)),
        largeBox('moov', movie.sublist(8)),
      ]);
      final orientation = (await scanBytes(bytes)).orientation!;
      // moov at 24 + 56, with a 16-byte header instead of 8.
      expect(
        orientation.tracks.single.matrixOffset,
        matrixOffsetIn(24 + 56) + 8,
      );
    });

    test(
      'a largesize with a non-zero high word reaches the moov past 4 GB',
      () async {
        for (final high in const <int>[1, 0x1FFFFF]) {
          const lowPayload = 16;
          final head = concat(<List<int>>[
            ftyp(),
            // size = high·2³² + 16: the 16-byte header, then high·2³² bytes.
            concat(<List<int>>[
              u32(1),
              fourCc('mdat'),
              u32(high),
              u32(lowPayload),
            ]),
          ]);
          final movie = moov(
            traks: <List<int>>[trak(matrixBytes: rotationMatrix(1))],
          );
          final tailOffset = 24 + high * 0x100000000 + lowPayload;
          final reader = SparseRangeReader(
            head: head,
            tail: movie,
            tailOffset: tailOffset,
          );
          final scan = await scanReelVideoOrientation(reader);
          final track = scan.orientation!.tracks.single;
          expect(track.matrixOffset, matrixOffsetIn(tailOffset));
          expect(track.quarterTurns, 1);
          final plan = planReelVideoRotation(scan.orientation!, 1);
          expect(plan.single.offset, matrixOffsetIn(tailOffset));
          expect(plan.single.bytes, rotationMatrix(2));
        }
      },
    );

    test('a size-0 last box runs to the end of the file', () async {
      final bytes = concat(<List<int>>[
        ftyp(),
        moov(traks: <List<int>>[trak()]),
        concat(<List<int>>[u32(0), fourCc('mdat'), Uint8List(100)]),
      ]);
      expect((await scanBytes(bytes)).orientation, isNotNull);
    });

    test('a uuid box is skipped, never interpreted', () async {
      final bytes = concat(<List<int>>[
        ftyp(),
        box('uuid', concat(<List<int>>[Uint8List(16), fourCc('moov')])),
        moov(traks: <List<int>>[trak()]),
        box('mdat', Uint8List(8)),
      ]);
      final orientation = (await scanBytes(bytes)).orientation!;
      expect(orientation.tracks.single.matrixOffset, matrixOffsetIn(24 + 28));
    });

    test('tkhd v1 keeps its matrix at payload +52', () async {
      final bytes = simpleMovie(tkhdVersion: 1, matrixBytes: rotationMatrix(3));
      final track = (await scanBytes(bytes)).orientation!.tracks.single;
      expect(track.tkhdVersion, 1);
      expect(track.matrixOffset, matrixOffsetIn(24, tkhdVersion: 1));
      expect(track.quarterTurns, 3);
      expect(
        Uint8List.sublistView(
          bytes,
          track.matrixOffset,
          track.matrixOffset + 36,
        ),
        rotationMatrix(3),
      );
    });

    test('mvhd v1 is read at payload +48', () async {
      final bytes = simpleMovie(mvhdVersion: 1);
      final track = (await scanBytes(bytes)).orientation!.tracks.single;
      expect(track.matrixOffset, matrixOffsetIn(24, mvhdLength: 120));
    });

    test('Android-style 90° (tx = ty = 0) is recognised as one turn', () async {
      final bytes = simpleMovie(
        matrixBytes: matrix(a: 0, b: isoOne, c: -isoOne, d: 0),
      );
      expect(
        (await scanBytes(bytes)).orientation!.tracks.single.quarterTurns,
        1,
      );
    });

    test('non-video tracks are listed but never patched', () async {
      final bytes = concat(<List<int>>[
        ftyp(),
        moov(
          traks: <List<int>>[
            trak(),
            trak(handler: 'soun'),
            trak(
              handler: 'tmcd',
              matrixBytes: matrix(a: 2 * isoOne),
            ),
          ],
        ),
        box('mdat', Uint8List(8)),
      ]);
      final orientation = (await scanBytes(bytes)).orientation!;
      expect(orientation.tracks.map((t) => t.handler), <String>[
        'vide',
        'soun',
        'tmcd',
      ]);
      expect(orientation.tracks.last.quarterTurns, isNull);
      final plan = planReelVideoRotation(orientation, 1);
      expect(plan.map((p) => p.offset), <int>[
        orientation.tracks.first.matrixOffset,
      ]);
    });
  });

  group('synthetic files that are not rotatable', () {
    Future<void> expectReason(
      Uint8List bytes,
      ReelOrientationUnsupported reason,
    ) async {
      final scan = await scanBytes(bytes);
      expect(scan.orientation, isNull);
      expect(scan.reason, reason);
    }

    test('WebM has no track matrix', () async {
      await expectReason(
        concat(<List<int>>[
          <int>[0x1a, 0x45, 0xdf, 0xa3, 0x9f, 0x42, 0x86, 0x81],
          Uint8List(64),
        ]),
        ReelOrientationUnsupported.notIsoBmff,
      );
    });

    test('a compressed movie header', () async {
      await expectReason(
        concat(<List<int>>[ftyp(), box('moov', box('cmov', Uint8List(16)))]),
        ReelOrientationUnsupported.compressedMoov,
      );
    });

    test('two moov boxes, or none', () async {
      final one = moov(traks: <List<int>>[trak()]);
      await expectReason(
        concat(<List<int>>[ftyp(), one, one]),
        ReelOrientationUnsupported.moovCount,
      );
      await expectReason(
        concat(<List<int>>[ftyp(), box('mdat', Uint8List(64))]),
        ReelOrientationUnsupported.moovCount,
      );
    });

    test('mirrored, scaled and non-canonical u/v/w matrices', () async {
      for (final bad in <Uint8List>[
        matrix(a: 0, b: isoOne, c: isoOne, d: 0),
        matrix(a: 0x8000, d: 0x8000),
        matrix(u: 1),
        matrix(v: 1),
        matrix(w: 0x20000000),
        matrix(a: isoOne, b: isoOne),
      ]) {
        await expectReason(
          simpleMovie(matrixBytes: bad),
          ReelOrientationUnsupported.unsupportedMatrix,
        );
      }
    });

    test('a video track header without a width or height', () async {
      // A rotation's translation is built from them; tx = ty = 0 would put
      // the frame outside its bounds for players that apply it as written.
      for (final (width, height) in const <(int, int)>[(0, 36), (64, 0)]) {
        await expectReason(
          concat(<List<int>>[
            ftyp(),
            moov(
              traks: <List<int>>[trak(width: width, height: height)],
            ),
          ]),
          ReelOrientationUnsupported.unsupportedMatrix,
        );
      }
      // A 0×0 sound track is ordinary and stays untouched.
      final scan = await scanBytes(
        concat(<List<int>>[
          ftyp(),
          moov(
            traks: <List<int>>[
              trak(),
              trak(handler: 'soun', width: 0, height: 0),
            ],
          ),
        ]),
      );
      expect(scan.orientation!.videoTracks, hasLength(1));
    });

    test('a non-identity movie matrix', () async {
      final bytes = concat(<List<int>>[
        ftyp(),
        moov(
          movieHeader: mvhd(matrixBytes: rotationMatrix(1)),
          traks: <List<int>>[trak()],
        ),
      ]);
      await expectReason(bytes, ReelOrientationUnsupported.movieMatrix);
    });

    test('audio only', () async {
      await expectReason(
        concat(<List<int>>[
          ftyp(),
          moov(traks: <List<int>>[trak(handler: 'soun')]),
        ]),
        ReelOrientationUnsupported.noVideoTrack,
      );
    });

    test('a box overrunning the file', () async {
      final bytes = simpleMovie();
      final truncated = Uint8List.sublistView(bytes, 0, bytes.length - 4);
      await expectReason(
        Uint8List.fromList(truncated),
        ReelOrientationUnsupported.malformed,
      );
      final overrun = Uint8List.fromList(bytes);
      ByteData.sublistView(overrun).setUint32(24, 0x7fffffff);
      await expectReason(overrun, ReelOrientationUnsupported.malformed);
    });

    test('a walk that does not end at the file length', () async {
      await expectReason(
        concat(<List<int>>[
          simpleMovie(),
          <int>[0, 0, 0, 0],
        ]),
        ReelOrientationUnsupported.malformed,
      );
    });

    test('a duplicated tkhd or a trak without mdia', () async {
      await expectReason(
        concat(<List<int>>[
          ftyp(),
          moov(
            traks: <List<int>>[
              box('trak', concat(<List<int>>[tkhd(), tkhd()])),
            ],
          ),
        ]),
        ReelOrientationUnsupported.malformed,
      );
    });

    test('a largesize at or beyond 2^53', () async {
      final head = concat(<List<int>>[
        ftyp(),
        concat(<List<int>>[u32(1), fourCc('mdat'), u32(0x200000), u32(16)]),
      ]);
      final reader = SparseRangeReader(
        head: head,
        tail: Uint8List(0),
        tailOffset: head.length + 64,
      );
      final scan = await scanReelVideoOrientation(reader);
      expect(scan.reason, ReelOrientationUnsupported.malformed);
    });

    test('a pathological box chain stops within its budget', () async {
      final free = box('free', Uint8List(0));
      final bytes = concat(<List<int>>[
        ftyp(),
        for (var index = 0; index < reelOrientationBoxBudget + 50; index++)
          free,
        moov(traks: <List<int>>[trak()]),
      ]);
      final reader = CountingRangeReader(bytes);
      final scan = await scanReelVideoOrientation(reader);
      expect(scan.reason, ReelOrientationUnsupported.budget);
      expect(reader.reads, lessThanOrEqualTo(reelOrientationBoxBudget + 2));
      expect(
        reader.bytesRead,
        lessThanOrEqualTo(16 * (reelOrientationBoxBudget + 2)),
      );
    });

    test('more than 16 tracks', () async {
      await expectReason(
        concat(<List<int>>[
          ftyp(),
          moov(traks: <List<int>>[for (var i = 0; i < 17; i++) trak()]),
        ]),
        ReelOrientationUnsupported.budget,
      );
    });
  });

  group('matrix model', () {
    test('canonical bytes are Apple\'s standardized transforms', () {
      const w = 1920 * isoOne, h = 1080 * isoOne;
      ByteData data(int turns) =>
          ByteData.sublistView(reelRotationMatrixBytes(turns, w, h));
      List<int> fields(int turns) => <int>[
        for (var index = 0; index < 9; index += 1)
          data(turns).getInt32(index * 4),
      ];
      expect(fields(0), <int>[isoOne, 0, 0, 0, isoOne, 0, 0, 0, isoW]);
      expect(fields(1), <int>[0, isoOne, 0, -isoOne, 0, 0, h, 0, isoW]);
      expect(fields(2), <int>[-isoOne, 0, 0, 0, -isoOne, 0, w, h, isoW]);
      expect(fields(3), <int>[0, -isoOne, 0, isoOne, 0, 0, 0, w, isoW]);
      expect(
        reelRotationMatrixBytes(5, w, h),
        reelRotationMatrixBytes(1, w, h),
      );
    });

    test('(a, b, c, d) are ExoPlayer parseTkhd\'s 90/180/270 tuples', () {
      // AtomParsers.parseTkhd: a == 0 && b == 65536 && c == -65536 && d == 0
      // → 90; a == 0 && b == -65536 && c == 65536 && d == 0 → 270;
      // a == -65536 && b == 0 && c == 0 && d == -65536 → 180.
      const exo = <int, List<int>>{
        90: <int>[0, isoOne, -isoOne, 0],
        180: <int>[-isoOne, 0, 0, -isoOne],
        270: <int>[0, -isoOne, isoOne, 0],
      };
      for (final entry in exo.entries) {
        final m = ByteData.sublistView(
          reelRotationMatrixBytes(entry.key ~/ 90, 64 * isoOne, 36 * isoOne),
        );
        expect(
          <int>[m.getInt32(0), m.getInt32(4), m.getInt32(12), m.getInt32(16)],
          entry.value,
          reason: '${entry.key}°',
        );
        expect(reelMatrixQuarterTurns(m), entry.key ~/ 90);
      }
    });

    test('a whole number of turns plans no write', () async {
      final orientation = (await scanBytes(simpleMovie())).orientation!;
      expect(planReelVideoRotation(orientation, 0), isEmpty);
      expect(planReelVideoRotation(orientation, 4), isEmpty);
      expect(planReelVideoRotation(orientation, 8), isEmpty);
    });

    test('patch round-trip composes turns clockwise', () async {
      final source = simpleMovie(matrixBytes: rotationMatrix(1));
      for (var taps = 1; taps <= 4; taps += 1) {
        final bytes = Uint8List.fromList(source);
        final orientation = (await scanBytes(bytes)).orientation!;
        applyReelMatrixPatches(bytes, planReelVideoRotation(orientation, taps));
        expect(bytes.length, source.length);
        final after = (await scanBytes(bytes)).orientation!;
        expect(after.tracks.single.quarterTurns, (1 + taps) % 4);
      }
    });
  });
}

/// Records the offset of every read it forwards.
class _RecordingReader implements ReelByteRangeReader {
  _RecordingReader(this._inner, this.offsets);

  final ReelByteRangeReader _inner;
  final List<int> offsets;

  @override
  int get length => _inner.length;

  @override
  Future<Uint8List> read(int offset, int count) {
    offsets.add(offset);
    return _inner.read(offset, count);
  }
}
