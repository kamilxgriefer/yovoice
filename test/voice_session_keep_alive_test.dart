import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/calls/data/services/voice_session_keep_alive.dart';

void main() {
  group('Android foreground service declaration', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    test('declares the permissions a connected voice session needs', () {
      // Without these a backgrounded process is silenced and then frozen,
      // which dropped calls once both parties minimised the app.
      for (final permission in const [
        'android.permission.FOREGROUND_SERVICE',
        'android.permission.FOREGROUND_SERVICE_MICROPHONE',
        'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK',
        'android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION',
        'android.permission.POST_NOTIFICATIONS',
        'android.permission.RECORD_AUDIO',
      ]) {
        expect(
          manifest,
          contains('android:name="$permission"'),
          reason: '$permission must stay declared',
        );
      }
    });

    test('registers a non-exported service with audio and screen-capture '
        'types', () {
      expect(manifest, contains('android:name=".VoiceSessionService"'));
      expect(
        manifest,
        contains(
          'android:foregroundServiceType='
          '"microphone|mediaPlayback|mediaProjection"',
        ),
      );
      final service = manifest.substring(
        manifest.indexOf('.VoiceSessionService'),
      );
      expect(
        service.substring(0, service.indexOf('/>')),
        contains('android:exported="false"'),
      );
    });

    test('screen capture is typed in-process and never stops a live '
        'service', () {
      final service = File(
        'android/app/src/main/kotlin/app/yovoice/VoiceSessionService.kt',
      ).readAsStringSync();
      final activity = File(
        'android/app/src/main/kotlin/app/yovoice/MainActivity.kt',
      ).readAsStringSync();

      // The type is only ever the union of what the session is doing now.
      expect(
        service,
        contains(
          'if (screenShareActive) type = type or '
          'ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION',
        ),
      );
      // A refused type update on an already-foreground call or Server session
      // must keep the proven microphone/mediaPlayback service alive.
      expect(service, contains('if (!foregroundStarted) stopSelf()'));
      // No Intent path can race the in-process update or restart a stopped
      // service just to change its type.
      expect(service, isNot(contains('ACTION_SCREEN_SHARE')));
      expect(service, contains('fun setScreenShareActive(active: Boolean)'));
      final startCommand = service.substring(
        service.indexOf('override fun onStartCommand'),
        service.indexOf('private fun startInForeground'),
      );
      expect(
        startCommand,
        isNot(contains('screenShareActive')),
        reason:
            'ACTION_START must never add the mediaProjection type before '
            'MediaProjection consent.',
      );

      // The reply follows startForeground on the running service; there is
      // exactly one startForegroundService call and it is the START path.
      expect(activity, contains('"setScreenShareActive"'));
      expect(activity, contains('VoiceSessionService.running'));
      expect('startForegroundService('.allMatches(activity), hasLength(1));
      // On API <= 30 the audio mode is process-global: a chat video must not
      // reset a telephony call that belongs to another party.
      expect(activity, contains('AudioManager.MODE_IN_CALL'));
    });

    test('the service and its channel strings exist', () {
      final service = File(
        'android/app/src/main/kotlin/app/yovoice/VoiceSessionService.kt',
      );
      expect(service.existsSync(), isTrue);
      expect(service.readAsStringSync(), startsWith('package app.yovoice'));
      final strings = File(
        'android/app/src/main/res/values/strings.xml',
      ).readAsStringSync();
      for (final name in const [
        'voice_session_channel_name',
        'voice_session_channel_description',
        'voice_session_title',
        'voice_session_body',
      ]) {
        expect(strings, contains('name="$name"'));
      }
    });

    test(
      'manifest components resolve to the one active application package',
      () {
        expect(gradle, contains('namespace = "app.yovoice"'));
        expect(gradle, contains('applicationId = "app.yovoice"'));
        expect(manifest, contains('android:name=".MainActivity"'));
        expect(manifest, contains('android:name=".VoiceSessionService"'));

        final kotlinRoot = Directory('android/app/src/main/kotlin');
        final mainActivities = kotlinRoot
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('/MainActivity.kt'))
            .toList(growable: false);
        expect(
          mainActivities,
          hasLength(1),
          reason:
              'A second MainActivity can satisfy the manifest while silently '
              'dropping the voice-session MethodChannel.',
        );
        final activity = mainActivities.single.readAsStringSync();
        expect(activity, startsWith('package app.yovoice'));
        expect(activity, contains('override fun configureFlutterEngine'));
        expect(activity, contains('app.yo_voice/voice_session'));
        expect(activity, contains('VoiceSessionService::class.java'));
      },
    );
  });

  group('iOS background audio', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();

    test('keeps the audio background mode', () {
      expect(plist, contains('UIBackgroundModes'));
      expect(plist, contains('<string>audio</string>'));
    });

    test('does not claim voip without CallKit', () {
      // A voip background mode obliges every PushKit push to be reported to
      // CallKit; there is no CallKit or PushKit code in ios/Runner, so
      // declaring it would be an App Store rejection and a runtime kill.
      expect(plist, isNot(contains('<string>voip</string>')));
      final runner = Directory('ios/Runner')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.swift'))
          .map((file) => file.readAsStringSync())
          .join('\n');
      expect(runner, isNot(contains('CallKit')));
      expect(runner, isNot(contains('PushKit')));
    });
  });

  group('keep-alive channel', () {
    const channel = MethodChannel('app.yo_voice/voice_session');
    final calls = <MethodCall>[];

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('start carries the title, body and publish capability', () async {
      const keepAlive = AndroidVoiceSessionKeepAlive();
      await keepAlive.start(
        title: 'Evening talks',
        body: 'Connected',
        canPublish: true,
      );
      expect(calls.single.method, 'start');
      expect(calls.single.arguments, <String, Object?>{
        'title': 'Evening talks',
        'body': 'Connected',
        'canPublish': true,
      });
      await keepAlive.stop();
      expect(calls.last.method, 'stop');
    });

    test('a refused platform call never throws into the call path', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'denied');
          });
      const keepAlive = AndroidVoiceSessionKeepAlive();
      await expectLater(
        keepAlive.start(title: 'Room', body: 'Connected', canPublish: false),
        completes,
      );
      await expectLater(keepAlive.stop(), completes);
    });

    test('the no-op implementation is inert', () async {
      const keepAlive = NoopVoiceSessionKeepAlive();
      await keepAlive.start(title: 'x', body: 'y', canPublish: true);
      await keepAlive.stop();
      expect(calls, isEmpty);
    });
  });
}
