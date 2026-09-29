// The Yeel rotation scanner and patch planner compiled by dart2js (ADR-235).
//
//   flutter test --platform chrome test/reel_video_orientation_browser_test.dart
//
// The web composer bakes a rotation in memory with this exact code. dart2js
// has no getUint64 and truncates shifts to int32, so the 64-bit largesize
// walk (including a moov past 4 GB and one just under 2^53), tkhd/mvhd v1,
// the patch plan and the canonical bytes all run here as well as on the VM.
//
// It also proves how a web pick is READ: image_picker_for_web hands out an
// XFile over an object URL with no bytes, and cross_file re-downloads that
// whole URL on every `openRead`. The scan and the header read must instead
// cost range requests only — or, where a browser ignores `Range`, a single
// whole-object fetch per scan.
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:web/web.dart' as web;
import 'package:yovoice/features/reels/data/services/reel_picked_file_range_web.dart';
import 'package:yovoice/features/reels/data/services/reel_upload.dart';
import 'package:yovoice/features/reels/data/services/reel_video_rotation_bake.dart';

import 'reel_iso_bmff_builder.dart';
import 'reel_video_orientation_cases.dart';

/// A Chrome-MediaRecorder-like file: moov first, then [fragments] moof/mdat
/// pairs — the shape whose top-level walk costs the most reads.
Uint8List _fragmentedMovie(int fragments) => concat(<List<int>>[
  ftyp(),
  moov(traks: <List<int>>[trak()]),
  for (var index = 0; index < fragments; index += 1) ...<List<int>>[
    box('moof', Uint8List(24)),
    box('mdat', Uint8List(4096)),
  ],
]);

/// A pick exactly as image_picker_for_web makes it: an object URL, a length,
/// and no bytes.
XFile _pick(Uint8List bytes) {
  final url = web.URL.createObjectURL(
    web.Blob(
      <JSUint8Array>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'video/mp4'),
    ),
  );
  addTearDown(() => web.URL.revokeObjectURL(url));
  return XFile(url, length: bytes.length, mimeType: 'video/mp4', name: 'k.mp4');
}

ReelUploadPayload _payload(XFile file, int size) =>
    ReelUploadPayload.pickedFile(
      pickedFile: file,
      size: size,
      contentType: 'video/mp4',
      durationMs: 1000,
    );

void main() {
  defineSyntheticOrientationCases();

  group('reading a web pick', () {
    setUp(() {
      debugReelBlobRangeRequests = 0;
      debugReelBlobWholeFetches = 0;
      debugReelBlobIgnoreRange = false;
    });
    tearDown(() => debugReelBlobIgnoreRange = false);

    test('the scan costs range requests, never a whole-file copy', () async {
      final bytes = _fragmentedMovie(60);
      final orientation = await scanReelUploadOrientation(
        _payload(_pick(bytes), bytes.length),
      );
      expect(orientation, isNotNull);
      expect(orientation!.videoTracks.single.quarterTurns, 0);
      expect(debugReelBlobWholeFetches, 0);
      // One request per top-level header (the walk) plus the moov window.
      expect(debugReelBlobRangeRequests, greaterThan(100));
    });

    test(
      'a browser that ignores Range costs ONE whole fetch per scan',
      () async {
        debugReelBlobIgnoreRange = true;
        final bytes = _fragmentedMovie(60);
        final orientation = await scanReelUploadOrientation(
          _payload(_pick(bytes), bytes.length),
        );
        expect(orientation, isNotNull);
        expect(debugReelBlobWholeFetches, 1);
        expect(debugReelBlobRangeRequests, 0);
      },
    );

    test('the header read is one range request', () async {
      final bytes = _fragmentedMovie(4);
      final header = await readReelHeader(_pick(bytes));
      expect(header, bytes.sublist(0, reelHeaderProbeBytes));
      expect(sniffReelContentType(header), 'video/mp4');
      expect(debugReelBlobRangeRequests, 1);
      expect(debugReelBlobWholeFetches, 0);
    });

    test('ranges read exactly what a resident copy holds', () async {
      final bytes = _fragmentedMovie(8);
      final reader = await xFileRangeReader(_pick(bytes));
      expect(reader.length, bytes.length);
      for (final (offset, count) in const <(int, int)>[
        (0, 16),
        (28, 8),
        (1000, 4096),
      ]) {
        expect(
          await reader.read(offset, count),
          bytes.sublist(offset, offset + count),
        );
      }
      await expectLater(
        reader.read(bytes.length - 4, 8),
        throwsA(isA<RangeError>()),
      );
      expect(debugReelBlobWholeFetches, 0);
    });

    test('XFile.fromData keeps working through its own blob URL', () async {
      final bytes = _fragmentedMovie(2);
      final file = XFile.fromData(bytes, mimeType: 'video/mp4');
      final orientation = await scanReelUploadOrientation(
        _payload(file, bytes.length),
      );
      expect(orientation, isNotNull);
      expect(debugReelBlobWholeFetches, 0);
    });
  });
}
