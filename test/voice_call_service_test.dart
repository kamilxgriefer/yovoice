import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/calls/data/services/voice_call_service.dart';

void main() {
  test(
    'late microphone disable hard-stops the captured track after room cleanup',
    () async {
      final service = VoiceCallService.forTesting(
        microphoneTeardownWaiter: (_, _) async => false,
      );
      final microphoneOff = Completer<void>();
      final lateCleanup = Completer<void>();
      final capturedMicrophone = Object();
      final publishedTracks = <Object>[capturedMicrophone];
      final events = <String>[];

      await service.guardDeferredCaptureTeardownForTesting<Object>(
        pendingDisable: microphoneOff.future,
        capturedTracks: <Object>[capturedMicrophone],
        stopCapturedTrack: (track) async {
          expect(track, same(capturedMicrophone));
          events.add('stop-captured');
        },
        stopCurrentCapture: () async {
          events.add('scan-${publishedTracks.length}');
          if (publishedTracks.isEmpty && !lateCleanup.isCompleted) {
            lateCleanup.complete();
          }
        },
      );

      // Simulate Room._cleanUp removing the publication while LiveKit's
      // restartTrack/getUserMedia Future is still pending.
      expect(events, <String>['scan-1']);
      publishedTracks.clear();
      microphoneOff.complete();
      await lateCleanup.future;

      expect(events, <String>['scan-1', 'stop-captured', 'scan-0']);
    },
  );
}
