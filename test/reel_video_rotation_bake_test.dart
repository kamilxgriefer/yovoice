// Baking the composer's "Obróć" into the upload (ADR-235): a local copy whose
// video track matrices are turned, streamed exactly like the pick, on io; the
// same patch in memory on web and wherever no real file exists.
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:yovoice/features/reels/data/services/reel_upload.dart';
import 'package:yovoice/features/reels/data/services/reel_video_orientation.dart';
import 'package:yovoice/features/reels/data/services/reel_video_rotation_bake.dart';
import 'package:yovoice/features/reels/data/services/reel_video_rotation_bake_bytes.dart';

const _dir = 'test/fixtures/reels';

Future<ReelUploadPayload> _picked(String path) =>
    ReelUploadPayload.fromXFile(XFile(path), durationMs: 1000);

Future<List<int>> _videoTurns(ReelByteRangeReader reader) async {
  final orientation = (await scanReelVideoOrientation(reader)).orientation!;
  return <int>[
    for (final track in orientation.videoTracks) track.quarterTurns!,
  ];
}

void main() {
  late Directory temp;
  late Directory sources;
  late ReelTemporaryDirectoryProvider provider;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('yeel-bake-test');
    sources = Directory('${temp.path}/picked')..createSync();
    provider = () async => temp.path;
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  String copyFixture(String name) {
    final target = '${sources.path}/$name';
    File('$_dir/$name').copySync(target);
    return target;
  }

  List<File> rotationCopies() {
    final directory = Directory('${temp.path}/$reelRotationDirectoryName');
    if (!directory.existsSync()) return const <File>[];
    return directory.listSync().whereType<File>().toList();
  }

  group('io bake', () {
    test(
      'streams a same-size copy whose only change is the matrices',
      () async {
        final path = copyFixture('reel_landscape_av_moovlast.mp4');
        final sourceHash = sha256.convert(File(path).readAsBytesSync());
        final source = await _picked(path);
        expect(source.isStreamed, isTrue);

        final baked = await bakeReelVideoRotation(
          source,
          3,
          temporaryDirectory: provider,
        );

        expect(baked.isStreamed, isTrue);
        expect(baked.size, source.size);
        expect(baked.contentType, source.contentType);
        expect(baked.durationMs, source.durationMs);
        expect(baked.sourcePath, isNot(path));
        expect(
          baked.sourcePath,
          startsWith('${temp.path}/$reelRotationDirectoryName/'),
        );
        expect(baked.sourcePath, endsWith('.mp4'));
        expect(
          File(baked.sourcePath!).readAsBytesSync(),
          File('$_dir/reel_landscape_av_moovlast.rot3.mp4').readAsBytesSync(),
        );
        expect(await _videoTurns(await xFileRangeReader(baked.file!)), <int>[
          3,
        ]);
        expect(
          sha256.convert(File(path).readAsBytesSync()),
          sourceHash,
          reason: 'the picked file is never written',
        );

        await discardBakedReelVideo(baked);
        expect(File(baked.sourcePath!).existsSync(), isFalse);
        expect(File(path).existsSync(), isTrue);
      },
    );

    test('a QuickTime pick keeps its .mov and turns 90° into 180°', () async {
      final path = copyFixture('reel_iphone_rot90.mov');
      final baked = await bakeReelVideoRotation(
        await _picked(path),
        1,
        temporaryDirectory: provider,
      );
      expect(baked.contentType, 'video/quicktime');
      expect(baked.sourcePath, endsWith('.mov'));
      expect(
        File(baked.sourcePath!).readAsBytesSync(),
        File('$_dir/reel_iphone_rot90.rot1.mov').readAsBytesSync(),
      );
    });

    test('whole turns return the source itself', () async {
      final source = await _picked(copyFixture('reel_landscape_faststart.mp4'));
      expect(
        identical(
          await bakeReelVideoRotation(source, 4, temporaryDirectory: provider),
          source,
        ),
        isTrue,
      );
      expect(rotationCopies(), isEmpty);
    });

    test('a source resized before the bake is sourceChanged', () async {
      final path = copyFixture('reel_landscape_faststart.mp4');
      final source = await _picked(path);
      File(path).writeAsBytesSync(<int>[0], mode: FileMode.append);
      await expectLater(
        bakeReelVideoRotation(source, 1, temporaryDirectory: provider),
        throwsA(
          isA<ReelVideoRotationException>().having(
            (error) => error.reason,
            'reason',
            ReelVideoRotationFailure.sourceChanged,
          ),
        ),
      );
      expect(rotationCopies(), isEmpty);
    });

    test('a missing source is sourceMissing', () async {
      final path = copyFixture('reel_landscape_faststart.mp4');
      final source = await _picked(path);
      File(path).deleteSync();
      await expectLater(
        bakeReelVideoRotation(source, 1, temporaryDirectory: provider),
        throwsA(
          isA<ReelVideoRotationException>().having(
            (error) => error.reason,
            'reason',
            ReelVideoRotationFailure.sourceMissing,
          ),
        ),
      );
      expect(rotationCopies(), isEmpty);
    });

    test('a non-rotatable file is unsupported and leaves no copy', () async {
      // A valid ftyp header over a body with no moov.
      final path = '${sources.path}/no_moov.mp4';
      final ftyp = File(
        '$_dir/reel_landscape_faststart.mp4',
      ).readAsBytesSync().sublist(0, 28);
      final mdat = BytesBuilder()
        ..add((ByteData(4)..setUint32(0, 208)).buffer.asUint8List())
        ..add('mdat'.codeUnits)
        ..add(Uint8List(200));
      File(path).writeAsBytesSync(<int>[...ftyp, ...mdat.takeBytes()]);
      final source = await _picked(path);
      await expectLater(
        bakeReelVideoRotation(source, 1, temporaryDirectory: provider),
        throwsA(
          isA<ReelVideoRotationException>().having(
            (error) => error.reason,
            'reason',
            ReelVideoRotationFailure.unsupported,
          ),
        ),
      );
      expect(rotationCopies(), isEmpty);
    });

    test('an unexpected failure is still a rotation failure', () async {
      // A raw error (a missing plugin, a revoked handle, the copy removed
      // mid-scan) must reach the composer as a ReelVideoRotationException,
      // never as a generic media error.
      final path = copyFixture('reel_landscape_faststart.mp4');
      final source = await _picked(path);
      await expectLater(
        bakeReelVideoRotation(
          source,
          1,
          temporaryDirectory: () async =>
              throw StateError('no temporary directory on this platform'),
        ),
        throwsA(
          isA<ReelVideoRotationException>().having(
            (error) => error.reason,
            'reason',
            ReelVideoRotationFailure.sourceChanged,
          ),
        ),
      );
      expect(File(path).existsSync(), isTrue);
    });

    test('a copy is intact until it is removed or truncated', () async {
      final path = copyFixture('reel_landscape_faststart.mp4');
      final source = await _picked(path);
      final baked = await bakeReelVideoRotation(
        source,
        1,
        temporaryDirectory: provider,
      );
      expect(await isBakedReelVideoIntact(baked), isTrue);
      final copy = File(baked.sourcePath!);
      copy.writeAsBytesSync(copy.readAsBytesSync().sublist(0, 100));
      expect(await isBakedReelVideoIntact(baked), isFalse);
      copy.deleteSync();
      expect(await isBakedReelVideoIntact(baked), isFalse);
      // Not ours, or resident: nothing to check.
      expect(await isBakedReelVideoIntact(source), isTrue);
      expect(
        await isBakedReelVideoIntact(
          ReelUploadPayload(
            bytes: Uint8List(256),
            contentType: 'video/mp4',
            durationMs: 1000,
          ),
        ),
        isTrue,
      );
    });

    test('discard never touches a file that is not a baked copy', () async {
      final path = copyFixture('reel_landscape_faststart.mp4');
      await discardBakedReelVideo(await _picked(path));
      expect(File(path).existsSync(), isTrue);
    });

    test(
      'the sweep removes copies older than 24 h and keeps fresh ones',
      () async {
        final path = copyFixture('reel_landscape_faststart.mp4');
        final fresh = await bakeReelVideoRotation(
          await _picked(path),
          1,
          temporaryDirectory: provider,
        );
        final stale = await bakeReelVideoRotation(
          await _picked(path),
          2,
          temporaryDirectory: provider,
        );
        File(stale.sourcePath!).setLastModifiedSync(
          DateTime.now().subtract(const Duration(hours: 25)),
        );
        await sweepStaleReelRotationCopies(temporaryDirectory: provider);
        expect(File(stale.sourcePath!).existsSync(), isFalse);
        expect(File(fresh.sourcePath!).existsSync(), isTrue);
      },
    );

    test('XFile.fromData (no real file) bakes in memory', () async {
      final bytes = File(
        '$_dir/reel_landscape_faststart.mp4',
      ).readAsBytesSync();
      final source = await ReelUploadPayload.fromXFile(
        XFile.fromData(bytes, path: 'kot.mp4', mimeType: 'video/mp4'),
        durationMs: 1000,
      );
      final baked = await bakeReelVideoRotation(
        source,
        1,
        temporaryDirectory: provider,
      );
      expect(baked.isStreamed, isFalse);
      expect(
        baked.bytes,
        File('$_dir/reel_landscape_faststart.rot1.mp4').readAsBytesSync(),
      );
      expect(rotationCopies(), isEmpty);
    });
  });

  group('bytes bake (web path, run on the VM)', () {
    test('a resident payload equal to the golden, header unchanged', () async {
      final original = File('$_dir/reel_iphone_rot90.mov').readAsBytesSync();
      final source = ReelUploadPayload(
        bytes: Uint8List.fromList(original),
        contentType: 'video/quicktime',
        durationMs: 1000,
      );
      final baked = await bakeReelVideoRotationBytes(source, 1);
      expect(baked.isStreamed, isFalse);
      expect(baked.size, source.size);
      expect(baked.contentType, source.contentType);
      expect(baked.durationMs, source.durationMs);
      expect(
        baked.bytes,
        File('$_dir/reel_iphone_rot90.rot1.mov').readAsBytesSync(),
      );
      expect(
        sniffReelContentType(baked.bytes.sublist(0, reelHeaderProbeBytes)),
        sniffReelContentType(original.sublist(0, reelHeaderProbeBytes)),
      );
      expect(source.bytes, original, reason: 'the source is never mutated');
    });

    test('a size mismatch is sourceChanged', () async {
      final original = File(
        '$_dir/reel_landscape_faststart.mp4',
      ).readAsBytesSync();
      final source = await ReelUploadPayload.fromXFile(
        XFile.fromData(original, path: 'x.mp4'),
        durationMs: 1000,
      );
      final shorter = ReelUploadPayload.pickedFile(
        pickedFile: XFile.fromData(original.sublist(0, original.length - 1)),
        size: source.size,
        contentType: source.contentType,
        durationMs: source.durationMs,
      );
      await expectLater(
        bakeReelVideoRotationBytes(shorter, 1),
        throwsA(
          isA<ReelVideoRotationException>().having(
            (error) => error.reason,
            'reason',
            ReelVideoRotationFailure.sourceChanged,
          ),
        ),
      );
    });

    test('a WebM is unsupported', () async {
      final webm = Uint8List.fromList(<int>[
        0x1a, 0x45, 0xdf, 0xa3, //
        ...List<int>.filled(300, 0),
      ]);
      await expectLater(
        bakeReelVideoRotationBytes(
          ReelUploadPayload(
            bytes: webm,
            contentType: 'video/webm',
            durationMs: 1000,
          ),
          1,
        ),
        throwsA(
          isA<ReelVideoRotationException>().having(
            (error) => error.reason,
            'reason',
            ReelVideoRotationFailure.unsupported,
          ),
        ),
      );
    });
  });

  group('pick-time scan', () {
    test('a rotatable video scans; a photo and a WebM do not', () async {
      final video = await _picked(copyFixture('reel_landscape_faststart.mp4'));
      expect(
        (await scanReelUploadOrientation(video))!.tracks.single.quarterTurns,
        0,
      );
      expect(
        await scanReelUploadOrientation(
          ReelUploadPayload(
            bytes: Uint8List.fromList(<int>[
              0x1a, 0x45, 0xdf, 0xa3, ...List<int>.filled(300, 0), //
            ]),
            contentType: 'video/webm',
            durationMs: 1000,
          ),
        ),
        isNull,
      );
      expect(
        await scanReelUploadOrientation(
          ReelUploadPayload(
            bytes: Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 0, 0]),
            contentType: 'image/jpeg',
            durationMs: 0,
          ),
        ),
        isNull,
      );
    });
  });
}
