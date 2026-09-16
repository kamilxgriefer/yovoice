import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// The installed video_player plugin owns this test-only decoder seam.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'package:yovoice/core/audio/realtime_audio_session_registry.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_media_fullscreen_viewer.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_video_audio_playback.dart';
import 'package:yovoice/features/messages/presentation/widgets/message_bubble.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android DM video requests a normal audible media route', () async {
    var nativePreparations = 0;

    final configured = await configureDirectVideoAudioPlayback(
      platform: TargetPlatform.android,
      audioSessions: RealtimeAudioSessionRegistry(),
      prepareNativeAudioSession: () async => nativePreparations += 1,
    );

    expect(configured, isTrue);
    expect(nativePreparations, 1);
  });

  test(
    'iOS DM video uses the atomic native category and mode bridge',
    () async {
      var nativePreparations = 0;

      final configured = await configureDirectVideoAudioPlayback(
        platform: TargetPlatform.iOS,
        audioSessions: RealtimeAudioSessionRegistry(),
        prepareNativeAudioSession: () async => nativePreparations += 1,
      );

      expect(configured, isTrue);
      expect(nativePreparations, 1);
    },
  );

  test(
    'DM video never replaces an active Server realtime audio route',
    () async {
      final registry = RealtimeAudioSessionRegistry();
      final serverLease = await registry.acquire(
        owner: Object(),
        kind: RealtimeAudioSessionOwnerKind.serverConversation,
      );
      addTearDown(serverLease.release);
      var contextWrites = 0;

      final configured = await configureDirectVideoAudioPlayback(
        platform: TargetPlatform.android,
        audioSessions: registry,
        prepareNativeAudioSession: () async => contextWrites += 1,
      );

      expect(configured, isFalse);
      expect(contextWrites, 0);
    },
  );

  test(
    'audio-route recovery failure leaves video playback available',
    () async {
      final configured = await configureDirectVideoAudioPlayback(
        platform: TargetPlatform.iOS,
        audioSessions: RealtimeAudioSessionRegistry(),
        prepareNativeAudioSession: () async =>
            throw StateError('platform unavailable'),
      );

      expect(configured, isFalse);
    },
  );

  group('message video playback', () {
    late VideoPlayerPlatform originalPlatform;
    late _TracingVideoPlatform platform;

    setUp(() {
      originalPlatform = VideoPlayerPlatform.instance;
      platform = _TracingVideoPlatform();
      VideoPlayerPlatform.instance = platform;
    });

    tearDown(() {
      VideoPlayerPlatform.instance = originalPlatform;
    });

    testWidgets('preview restores audio and full volume before every play', (
      tester,
    ) async {
      var audioPreparations = 0;
      await _pumpVideo(
        tester,
        videoAudioPreparer: () async {
          audioPreparations += 1;
          platform.commands.add('audio-route-$audioPreparations');
        },
      );
      // The preview deliberately creates its decoder lazily on the first tap.
      expect(platform.commands, isEmpty);

      final play = find.byKey(const ValueKey('direct-video-video'));
      await tester.tap(play);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // DM video keeps video_player's default audio focus (no mixWithOthers).
      expect(platform.commands, contains('mix-false'));
      expect(platform.commands, isNot(contains('mix-true')));
      expect(audioPreparations, 1);
      _expectAudiblePlayOrder(platform.commands, occurrence: 1);

      await tester.tap(play); // pause
      await tester.pump();
      await tester.tap(play); // resume
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(audioPreparations, 2);
      _expectAudiblePlayOrder(platform.commands, occurrence: 2);
    });

    testWidgets('full-screen start uses the same audible playback gate', (
      tester,
    ) async {
      var audioPreparations = 0;
      await _pumpVideo(
        tester,
        videoAudioPreparer: () async {
          audioPreparations += 1;
          platform.commands.add('audio-route-$audioPreparations');
        },
      );

      await tester.tap(
        find.byKey(const ValueKey('direct-video-fullscreen-video')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(find.byType(DirectVideoFullscreenViewer), findsOneWidget);
      expect(audioPreparations, 1);
      _expectAudiblePlayOrder(platform.commands, occurrence: 1);
    });

    testWidgets('a failed injected route repair still starts the video', (
      tester,
    ) async {
      await _pumpVideo(
        tester,
        videoAudioPreparer: () async => throw StateError('route rejected'),
      );

      await tester.tap(find.byKey(const ValueKey('direct-video-video')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(platform.commands, contains('volume-1-1.0'));
      expect(platform.commands, contains('play-1'));
      expect(tester.takeException(), isNull);
    });
  });
}

void _expectAudiblePlayOrder(List<String> commands, {required int occurrence}) {
  final route = commands.indexOf('audio-route-$occurrence');
  final nextRoute = commands.indexOf('audio-route-${occurrence + 1}');
  final upperBound = nextRoute < 0 ? commands.length : nextRoute;
  final volume = commands.indexWhere(
    (command) => command == 'volume-1-1.0',
    route + 1,
  );
  final play = commands.indexWhere((command) => command == 'play-1', route + 1);
  expect(route, greaterThanOrEqualTo(0));
  expect(volume, inInclusiveRange(route + 1, upperBound - 1));
  expect(play, inInclusiveRange(volume + 1, upperBound - 1));
}

Future<void> _pumpVideo(
  WidgetTester tester, {
  required DirectVideoAudioPreparer videoAudioPreparer,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: MessageBubble(
          message: Message(
            id: 'video',
            conversationId: 'conversation',
            senderId: 'friend',
            type: MessageType.video,
            content: 'Video',
            mediaUrl: 'https://example.test/video-with-audio.mp4',
            durationSeconds: 8,
            sentAt: DateTime.utc(2026, 9, 14),
            readBy: const <String>[],
            reactions: const <String, String>{},
          ),
          currentUserId: 'viewer',
          onLongPress: () {},
          videoAudioPreparer: videoAudioPreparer,
        ),
      ),
    ),
  );
  // Controller creation and the platform initialization event both complete
  // asynchronously. Waiting here keeps the assertions about audio ordering
  // deterministic instead of relying on unrelated work to advance the loop.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

class _TracingVideoPlatform extends VideoPlayerPlatform {
  final List<String> commands = <String>[];
  final Map<int, StreamController<VideoEvent>> _events =
      <int, StreamController<VideoEvent>>{};
  var _nextId = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = ++_nextId;
    final events = StreamController<VideoEvent>();
    _events[id] = events;
    events.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 8),
        size: const Size(1920, 1080),
      ),
    );
    commands.add('create-$id');
    commands.add('mix-${options.videoPlayerOptions?.mixWithOthers ?? false}');
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    commands.add('dispose-$playerId');
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> play(int playerId) async => commands.add('play-$playerId');

  @override
  Future<void> pause(int playerId) async => commands.add('pause-$playerId');

  @override
  Future<void> seekTo(int playerId, Duration position) async =>
      commands.add('seek-$playerId-${position.inMilliseconds}');

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> setVolume(int playerId, double volume) async =>
      commands.add('volume-$playerId-$volume');

  @override
  Future<void> setLooping(int playerId, bool looping) async =>
      commands.add('loop-$playerId-$looping');

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => ColoredBox(
    color: Colors.black,
    key: ValueKey('video-${options.playerId}'),
  );
}
