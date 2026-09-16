import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  test(
    'Android registers native PiP and gates automatic entry to an armed call',
    () {
      final manifest = source('android/app/src/main/AndroidManifest.xml');
      final activity = source(
        'android/app/src/main/kotlin/app/yovoice/MainActivity.kt',
      );
      final controller = source(
        'android/app/src/main/kotlin/app/yovoice/'
        'DirectCallPictureInPictureController.kt',
      );

      expect(manifest, contains('android:supportsPictureInPicture="true"'));
      expect(manifest, contains('android:resizeableActivity="true"'));
      expect(activity, contains('app.yovoice/direct_call_pip'));
      expect(activity, contains('onUserLeaveHint'));
      expect(activity, contains('onPictureInPictureModeChanged'));
      expect(controller, contains('Build.VERSION_CODES.O'));
      expect(controller, contains('.setAutoEnterEnabled(active)'));
      expect(controller, contains('if (!active || !isSupported()) return'));
      expect(controller, contains('trackId.isEmpty()'));
      expect(controller, contains('if (inPictureInPicture)'));
      expect(controller, contains('activity.moveTaskToBack(false)'));
    },
  );

  test(
    'iOS uses the system video-call PiP API without raising iOS 15 target',
    () {
      final appDelegate = source('ios/Runner/AppDelegate.swift');
      final controller = source(
        'ios/Runner/DirectCallPictureInPictureController.swift',
      );
      final project = source('ios/Runner.xcodeproj/project.pbxproj');
      final pubspec = source('pubspec.yaml');

      expect(appDelegate, contains('app.yovoice/direct_call_pip'));
      expect(controller, contains('AVPictureInPictureVideoCallViewController'));
      expect(
        controller,
        contains('canStartPictureInPictureAutomaticallyFromInline = true'),
      );
      expect(controller, contains('remoteTrack(forId: trackId)'));
      expect(controller, contains('RTCMTLVideoView'));
      expect(
        project,
        contains('DirectCallPictureInPictureController.swift in Sources'),
      );
      expect(project, contains('IPHONEOS_DEPLOYMENT_TARGET = 15.0;'));
      expect(pubspec, isNot(contains('livekit_pip:')));
    },
  );

  test('Flutter only arms PiP for a connected active direct video call', () {
    final screen = source(
      'lib/features/calls/presentation/screens/direct_call_screen.dart',
    );
    final syncStart = screen.indexOf('void _syncPictureInPicture()');
    final syncEnd = screen.indexOf('void _schedulePictureInPictureSync()');
    expect(syncStart, greaterThanOrEqualTo(0));
    expect(syncEnd, greaterThan(syncStart));
    // Compare tokens, not the formatter's line breaks.
    final sync = screen
        .substring(syncStart, syncEnd)
        .replaceAll(RegExp(r'\s+'), ' ');

    expect(sync, contains('call?.status == DirectCallStatus.active'));
    expect(sync, contains('call?.isVideo == true'));
    expect(sync, contains('status == VoiceCallStatus.connected'));
    // A network handover keeps an already-armed PiP window; only terminal
    // states make the call ineligible and disarm it.
    expect(
      sync,
      contains(
        'status == VoiceCallStatus.reconnecting && '
        '_pictureInPicture.isArmed',
      ),
    );
    expect(sync, isNot(contains('_voice.isConnected')));
    expect(sync, contains('_voice.directCallId == widget.callId'));
    expect(sync, contains('_pictureInPicture.disarm()'));
    expect(screen, contains('pauseCameraForBackground()'));
  });
}
