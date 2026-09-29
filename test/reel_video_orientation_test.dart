// The Yeel rotation scanner and tkhd patcher (ADR-235) against the committed
// AVAssetWriter fixtures, the real Chromium MediaRecorder fMP4 and the
// synthetic shapes shared with the Chrome-platform suite.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/reels/data/services/reel_upload.dart';
import 'package:yovoice/features/reels/data/services/reel_video_orientation.dart';

import 'reel_iso_bmff_builder.dart';
import 'reel_video_orientation_cases.dart';

const _dir = 'test/fixtures/reels';
const _chromium =
    'functions/test/fixtures/chromium_mediarecorder_fragmented.mp4';

Uint8List _read(String path) => File(path).readAsBytesSync();

typedef _Track = ({
  String handler,
  int version,
  int matrixOffset,
  int? turns,
  int width,
  int height,
});

const Map<String, List<_Track>> _expected = <String, List<_Track>>{
  // The "Pixel pointed down" shape: ftyp, moov, mdat; identity.
  '$_dir/reel_landscape_faststart.mp4': <_Track>[
    (
      handler: 'vide',
      version: 0,
      matrixOffset: 200,
      turns: 0,
      width: 64,
      height: 36,
    ),
  ],
  // ftyp, mdat, moov; video + AAC.
  '$_dir/reel_landscape_av_moovlast.mp4': <_Track>[
    (
      handler: 'vide',
      version: 0,
      matrixOffset: 675,
      turns: 0,
      width: 64,
      height: 36,
    ),
    (
      handler: 'soun',
      version: 0,
      matrixOffset: 1307,
      turns: 0,
      width: 0,
      height: 0,
    ),
  ],
  // 'qt  '; ftyp, wide, mdat, moov; the iPhone 90° matrix + AAC.
  '$_dir/reel_iphone_rot90.mov': <_Track>[
    (
      handler: 'vide',
      version: 0,
      matrixOffset: 667,
      turns: 1,
      width: 64,
      height: 36,
    ),
    (
      handler: 'soun',
      version: 0,
      matrixOffset: 1407,
      turns: 0,
      width: 0,
      height: 0,
    ),
  ],
  '$_dir/reel_two_video_tracks.mp4': <_Track>[
    (
      handler: 'vide',
      version: 0,
      matrixOffset: 200,
      turns: 0,
      width: 64,
      height: 36,
    ),
    (
      handler: 'vide',
      version: 0,
      matrixOffset: 836,
      turns: 0,
      width: 64,
      height: 36,
    ),
  ],
  // Chromium fMP4 (VP9): tkhd v1, the moov's matrix is authoritative.
  _chromium: <_Track>[
    (
      handler: 'vide',
      version: 1,
      matrixOffset: 232,
      turns: 0,
      width: 160,
      height: 120,
    ),
  ],
};

const Map<String, (String, int)> _goldens = <String, (String, int)>{
  '$_dir/reel_landscape_faststart.rot1.mp4': (
    '$_dir/reel_landscape_faststart.mp4',
    1,
  ),
  '$_dir/reel_iphone_rot90.rot1.mov': ('$_dir/reel_iphone_rot90.mov', 1),
  '$_dir/reel_landscape_av_moovlast.rot3.mp4': (
    '$_dir/reel_landscape_av_moovlast.mp4',
    3,
  ),
  '$_dir/chromium_mediarecorder_fragmented.rot1.mp4': (_chromium, 1),
};

Future<Uint8List> _patched(Uint8List source, int taps) async {
  final bytes = Uint8List.fromList(source);
  final orientation = (await scanBytes(bytes)).orientation!;
  applyReelMatrixPatches(bytes, planReelVideoRotation(orientation, taps));
  return bytes;
}

void main() {
  group('committed fixtures', () {
    for (final entry in _expected.entries) {
      test('scans ${entry.key.split('/').last}', () async {
        final bytes = _read(entry.key);
        final scan = await scanBytes(bytes);
        expect(scan.reason, isNull);
        final tracks = scan.orientation!.tracks;
        expect(tracks, hasLength(entry.value.length));
        for (var index = 0; index < tracks.length; index += 1) {
          final want = entry.value[index];
          final got = tracks[index];
          expect(got.handler, want.handler);
          expect(got.tkhdVersion, want.version);
          expect(got.matrixOffset, want.matrixOffset);
          expect(got.quarterTurns, want.turns);
          expect(got.widthFixed, want.width * isoOne);
          expect(got.heightFixed, want.height * isoOne);
        }
      });

      test('patches ${entry.key.split('/').last} for taps 1–4', () async {
        final source = _read(entry.key);
        final before = (await scanBytes(source)).orientation!;
        final windows = <(int, int)>[
          for (final track in before.videoTracks)
            (track.matrixOffset, track.matrixOffset + 36),
        ];
        for (var taps = 1; taps <= 4; taps += 1) {
          final patched = await _patched(source, taps);
          expect(patched.length, source.length, reason: 'taps $taps');
          expect(patched.sublist(0, 64), source.sublist(0, 64));
          expect(
            sniffReelContentType(patched.sublist(0, 64)),
            sniffReelContentType(source.sublist(0, 64)),
          );
          for (var index = 0; index < source.length; index += 1) {
            if (source[index] == patched[index]) continue;
            expect(
              windows.any((w) => index >= w.$1 && index < w.$2),
              isTrue,
              reason: 'byte $index changed outside a video matrix (taps $taps)',
            );
          }
          final after = (await scanBytes(patched)).orientation!;
          for (var index = 0; index < before.tracks.length; index += 1) {
            final was = before.tracks[index];
            final now = after.tracks[index];
            if (!was.isVideo) {
              expect(now.quarterTurns, was.quarterTurns);
              expect(
                patched.sublist(was.matrixOffset, was.matrixOffset + 44),
                source.sublist(was.matrixOffset, was.matrixOffset + 44),
                reason: 'the ${was.handler} tkhd is byte-identical',
              );
              continue;
            }
            final turns = (was.quarterTurns! + taps) % 4;
            expect(now.quarterTurns, turns);
            if (taps % 4 != 0) {
              expect(
                patched.sublist(was.matrixOffset, was.matrixOffset + 36),
                reelRotationMatrixBytes(turns, was.widthFixed, was.heightFixed),
              );
            }
          }
          if (taps == 4) expect(patched, source);
        }
      });
    }
  });

  test(
    'iPhone 90° composes: +1 is 180°, +3 is identity, +4 is the original',
    () async {
      final source = _read('$_dir/reel_iphone_rot90.mov');
      final plus1 = await _patched(source, 1);
      final plus3 = await _patched(source, 3);
      final plus4 = await _patched(source, 4);
      final m1 = ByteData.sublistView(plus1, 667, 667 + 36);
      expect(reelMatrixQuarterTurns(m1), 2);
      final m3 = ByteData.sublistView(plus3, 667, 667 + 36);
      expect(reelMatrixQuarterTurns(m3), 0);
      expect(m3.getInt32(24), 0, reason: 'tx');
      expect(m3.getInt32(28), 0, reason: 'ty');
      expect(plus4, source);
      // The iPhone's own 90° matrix is exactly the canonical one: tx = H.
      expect(
        source.sublist(667, 667 + 36),
        reelRotationMatrixBytes(1, 64 * isoOne, 36 * isoOne),
      );
    },
  );

  test('only 6–12 bytes change and the first 64 never do', () async {
    for (final entry in _goldens.entries) {
      final source = _read(entry.value.$1);
      final golden = _read(entry.key);
      var changed = 0;
      for (var index = 0; index < source.length; index += 1) {
        if (source[index] != golden[index]) changed += 1;
      }
      expect(changed, inInclusiveRange(6, 12), reason: entry.key);
      expect(golden.sublist(0, 64), source.sublist(0, 64));
    }
  });

  for (final entry in _goldens.entries) {
    test('golden ${entry.key.split('/').last} is the library output', () async {
      final source = _read(entry.value.$1);
      expect(await _patched(source, entry.value.$2), _read(entry.key));
    });
  }

  test('the Chromium fMP4 golden is rotated on its tkhd v1 at 232', () async {
    final golden = _read('$_dir/chromium_mediarecorder_fragmented.rot1.mp4');
    final track = (await scanBytes(golden)).orientation!.tracks.single;
    expect(track.tkhdVersion, 1);
    expect(track.matrixOffset, 232);
    expect(track.quarterTurns, 1);
  });

  defineSyntheticOrientationCases();
}
