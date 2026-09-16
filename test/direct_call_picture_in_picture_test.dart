import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/calls/data/services/direct_call_picture_in_picture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.yovoice/test_direct_call_pip');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  // Delivers a native PiP mode change. The reply is null when no Dart handler
  // is registered for the channel.
  Future<ByteData?> nativePictureInPictureChanged(bool active) =>
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('pictureInPictureChanged', active),
        ),
        null,
      );

  DirectCallPictureInPictureController supportedController() {
    final controller = DirectCallPictureInPictureController(
      channel: channel,
      platformSupportedOverride: true,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test(
    'arms one native remote-video source and mirrors PiP mode changes',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      final controller = DirectCallPictureInPictureController(
        channel: channel,
        platformSupportedOverride: true,
      );
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      expect(
        await controller.armRemoteVideo(
          trackId: '  remote-track-1  ',
          participantName: '  Alicja  ',
          width: -1,
          height: 0,
        ),
        isTrue,
      );
      expect(controller.isArmed, isTrue);
      expect(controller.isInPictureInPicture, isFalse);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'setActive');
      expect(calls.single.arguments, <String, Object>{
        'active': true,
        'trackId': 'remote-track-1',
        'participantName': 'Alicja',
        'width': 16,
        'height': 9,
      });

      // Rebuilding the call UI must not repeatedly re-arm the same renderer.
      expect(
        await controller.armRemoteVideo(
          trackId: 'remote-track-1',
          participantName: 'Alicja',
        ),
        isTrue,
      );
      expect(calls, hasLength(1));

      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('pictureInPictureChanged', true),
        ),
        null,
      );
      expect(controller.isInPictureInPicture, isTrue);
      expect(notifications, 2);

      await controller.disarm();
      expect(controller.isArmed, isFalse);
      expect(controller.isInPictureInPicture, isFalse);
      expect(calls.last.arguments, const <String, Object>{'active': false});
    },
  );

  test('a late native arm result cannot revive a disarmed call', () async {
    final pendingArm = Completer<bool>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      final values = call.arguments! as Map<Object?, Object?>;
      if (values['active'] == true) return pendingArm.future;
      return true;
    });
    final controller = DirectCallPictureInPictureController(
      channel: channel,
      platformSupportedOverride: true,
    );
    addTearDown(controller.dispose);

    final result = controller.armRemoteVideo(
      trackId: 'remote-track-1',
      participantName: 'Alicja',
    );
    await controller.disarm();
    pendingArm.complete(true);

    expect(await result, isFalse);
    expect(controller.isArmed, isFalse);
    expect(controller.isInPictureInPicture, isFalse);
  });

  test(
    'unsupported platforms and missing tracks never call native code',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      final unsupported = DirectCallPictureInPictureController(
        channel: channel,
        platformSupportedOverride: false,
      );
      addTearDown(unsupported.dispose);

      expect(
        await unsupported.armRemoteVideo(
          trackId: 'remote-track-1',
          participantName: 'Alicja',
        ),
        isFalse,
      );
      expect(calls, isEmpty);

      final supported = DirectCallPictureInPictureController(
        channel: channel,
        platformSupportedOverride: true,
      );
      addTearDown(supported.dispose);
      expect(
        await supported.armRemoteVideo(
          trackId: '   ',
          participantName: 'Alicja',
        ),
        isFalse,
      );
      expect(calls, isEmpty);
    },
  );

  test(
    'a never-armed controller cannot deafen or disarm the native PiP owner',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      // A call route's exit transition disposes the previous screen after the
      // next screen has already created its controller and armed PiP.
      final previousScreen = supportedController();
      final currentScreen = supportedController();

      expect(
        await currentScreen.armRemoteVideo(
          trackId: 'remote-track-b',
          participantName: 'Bartek',
        ),
        isTrue,
      );
      expect(calls, hasLength(1));

      previousScreen.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(calls, hasLength(1), reason: 'it never armed native PiP');

      expect(await nativePictureInPictureChanged(true), isNotNull);
      expect(currentScreen.isInPictureInPicture, isTrue);
      expect(previousScreen.isInPictureInPicture, isFalse);

      currentScreen.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(calls, hasLength(2));
      expect(calls.last.arguments, const <String, Object>{'active': false});
      expect(
        await nativePictureInPictureChanged(false),
        isNull,
        reason: 'the last controller removes the shared native handler',
      );
    },
  );

  test('only the most recent native owner hears and disarms PiP', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    final superseded = supportedController();
    final owner = supportedController();

    expect(
      await superseded.armRemoteVideo(
        trackId: 'remote-track-a',
        participantName: 'Alicja',
      ),
      isTrue,
    );
    expect(
      await owner.armRemoteVideo(
        trackId: 'remote-track-b',
        participantName: 'Bartek',
      ),
      isTrue,
    );
    expect(calls, hasLength(2));

    await nativePictureInPictureChanged(true);
    expect(owner.isInPictureInPicture, isTrue);
    expect(superseded.isInPictureInPicture, isFalse);

    // The native bridge now renders the owner's track. The superseded
    // controller resets itself without closing the owner's window.
    await superseded.disarm();
    expect(superseded.isArmed, isFalse);
    expect(calls, hasLength(2));
    expect(owner.isArmed, isTrue);
    expect(owner.isInPictureInPicture, isTrue);

    await owner.disarm();
    expect(calls, hasLength(3));
    expect(calls.last.arguments, const <String, Object>{'active': false});

    // Disarming twice, or disposing afterwards, never repeats the native call.
    await owner.disarm();
    owner.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(calls, hasLength(3));
  });

  test('a pending arm is always cancelled natively by its sender', () async {
    final pendingArm = Completer<bool>();
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final values = call.arguments! as Map<Object?, Object?>;
      if (values['active'] == true) return pendingArm.future;
      return true;
    });
    final controller = supportedController();

    final result = controller.armRemoteVideo(
      trackId: 'remote-track-1',
      participantName: 'Alicja',
    );
    controller.dispose();
    pendingArm.complete(true);

    expect(await result, isFalse);
    expect(calls, hasLength(2));
    expect(calls.last.arguments, const <String, Object>{'active': false});
    expect(await nativePictureInPictureChanged(true), isNull);
  });

  test('native failures remain a safe no-PiP state', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'activity_unavailable');
    });
    final controller = DirectCallPictureInPictureController(
      channel: channel,
      platformSupportedOverride: true,
    );
    addTearDown(controller.dispose);

    expect(
      await controller.armRemoteVideo(
        trackId: 'remote-track-1',
        participantName: 'Alicja',
      ),
      isFalse,
    );
    expect(controller.isArmed, isFalse);
    expect(controller.isInPictureInPicture, isFalse);
  });
}
