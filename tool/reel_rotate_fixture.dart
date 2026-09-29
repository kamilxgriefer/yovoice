// Produces a rotated golden with the app's own tkhd patcher (ADR-235).
//
//   dart run tool/reel_rotate_fixture.dart <in> <taps> <out>
//
// e.g. dart run tool/reel_rotate_fixture.dart \
//   test/fixtures/reels/reel_landscape_faststart.mp4 1 \
//   test/fixtures/reels/reel_landscape_faststart.rot1.mp4
//
// Uses exactly the library the composer bakes with, so a golden can never
// drift from what the app uploads. Prints the tracks before and after.
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:yovoice/features/reels/data/services/reel_video_orientation.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3 || int.tryParse(arguments[1]) == null) {
    stderr.writeln(
      'usage: dart run tool/reel_rotate_fixture.dart <in> <taps> <out>',
    );
    exitCode = 64;
    return;
  }
  final source = Uint8List.fromList(await File(arguments[0]).readAsBytes());
  final taps = int.parse(arguments[1]);
  final scan = await scanReelVideoOrientation(bytesRangeReader(source));
  final orientation = scan.orientation;
  if (orientation == null) {
    stderr.writeln('${arguments[0]}: not rotatable (${scan.reason?.name})');
    exitCode = 65;
    return;
  }
  _describe(arguments[0], orientation);
  final patched = Uint8List.fromList(source);
  applyReelMatrixPatches(patched, planReelVideoRotation(orientation, taps));
  final after = (await scanReelVideoOrientation(
    bytesRangeReader(patched),
  )).orientation!;
  await File(arguments[2]).writeAsBytes(patched, flush: true);
  var changed = 0;
  for (var index = 0; index < source.length; index += 1) {
    if (source[index] != patched[index]) changed += 1;
  }
  _describe(arguments[2], after);
  print('  $changed bytes changed, length ${patched.length}');
}

void _describe(String path, ReelVideoOrientation orientation) {
  print(path);
  for (final track in orientation.tracks) {
    print(
      '  ${track.handler} tkhd v${track.tkhdVersion} '
      'matrix@${track.matrixOffset} turns=${track.quarterTurns} '
      '${track.widthFixed / 65536}x${track.heightFixed / 65536}',
    );
  }
}
