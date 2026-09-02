import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/permissions/data/permission_readiness_service.dart';

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

  test('media status gate never requests a permission', () async {
    final platform = _VoicePermissionPlatform();
    final service = VoiceCallService.forTesting(
      permissionReadiness: PermissionReadinessService(platform: platform),
    );

    final snapshot = await service.mediaPermissionStatus(includeCamera: true);

    expect(snapshot[AppPermissionKind.microphone], AppPermissionAccess.denied);
    expect(snapshot[AppPermissionKind.camera], AppPermissionAccess.denied);
    expect(platform.requests, isEmpty);
  });

  test('voice errors never expose callable or exception internals', () {
    final service = VoiceCallService.forTesting();
    final callable = service.friendlyErrorForTesting(
      FirebaseFunctionsException(
        code: 'internal',
        message: 'SQLSTATE 42P01 at private_table',
      ),
    );
    final permission = service.friendlyErrorForTesting(
      const VoicePermissionRequiredException(
        AppPermissionKind.microphone,
        AppPermissionAccess.denied,
      ),
    );

    expect(callable, 'Live audio is unavailable right now. Try again.');
    expect(callable, isNot(contains('SQLSTATE')));
    expect(permission, contains('Microphone access'));
    expect(permission, isNot(contains('VoicePermissionRequiredException')));
  });
}

final class _VoicePermissionPlatform implements AppPermissionPlatformGateway {
  final List<AppPermissionKind> requests = <AppPermissionKind>[];

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<AppPermissionAccess> requestFromUserGesture(
    AppPermissionKind permission,
  ) async {
    requests.add(permission);
    return AppPermissionAccess.granted;
  }

  @override
  Future<AppPermissionAccess> status(AppPermissionKind permission) async =>
      AppPermissionAccess.denied;
}
