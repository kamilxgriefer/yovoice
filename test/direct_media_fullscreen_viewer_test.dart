import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
// The installed video_player plugin owns this test-only decoder seam.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_media_fullscreen_viewer.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_video_playback_source.dart';
import 'package:yovoice/features/messages/presentation/widgets/message_bubble.dart';

void main() {
  late VideoPlayerPlatform originalVideoPlatform;
  late _VideoPlatform videoPlatform;

  setUp(() {
    originalVideoPlatform = VideoPlayerPlatform.instance;
    videoPlatform = _VideoPlatform();
    VideoPlayerPlatform.instance = videoPlatform;
  });

  tearDown(() {
    VideoPlayerPlatform.instance = originalVideoPlatform;
  });

  testWidgets(
    'private photo opens from cached authenticated bytes and closes',
    (tester) async {
      var loads = 0;
      await _pumpBubble(
        tester,
        _message(id: 'photo', type: MessageType.image, mediaUrl: _privatePhoto),
        loader: (_, maxBytes) async {
          loads += 1;
          expect(maxBytes, 8 * 1024 * 1024);
          return _onePixelPng;
        },
      );
      await tester.pumpAndSettle();

      final thumbnail = tester.widget<Image>(find.byType(Image));
      expect(thumbnail.image, isA<MemoryImage>());
      expect(loads, 1);

      await tester.tap(find.byKey(const ValueKey('direct-image-photo')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.byType(DirectImageFullscreenViewer), findsOneWidget);
      expect(
        find.byKey(const ValueKey('direct-image-fullscreen-pan-zoom')),
        findsOneWidget,
      );
      final fullscreen = tester.widget<Image>(
        find.byKey(const ValueKey('direct-image-fullscreen-image-0')),
      );
      expect(identical(fullscreen.image, thumbnail.image), isTrue);
      expect(loads, 1, reason: 'opening must not download private bytes again');

      await tester.tap(
        find.byKey(const ValueKey('direct-media-fullscreen-close')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DirectImageFullscreenViewer), findsNothing);
    },
  );

  testWidgets('open private photo is hidden when the account owner changes', (
    tester,
  ) async {
    final owner = ValueNotifier<String>('account-a');
    addTearDown(owner.dispose);
    final message = _message(
      id: 'same-photo',
      type: MessageType.image,
      mediaUrl: _privatePhoto,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: ValueListenableBuilder<String>(
            valueListenable: owner,
            builder: (context, ownerId, _) => MessageBubble(
              message: message,
              currentUserId: ownerId,
              onLongPress: () {},
              privateMediaLoader: (_, _) async => _onePixelPng,
              videoAudioPreparer: _prepareVideoAudio,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('direct-image-same-photo')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.byKey(const ValueKey('direct-image-fullscreen-image-0')),
      findsOneWidget,
    );

    owner.value = 'account-b';
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('direct-image-fullscreen-image-0')),
      findsNothing,
    );
    expect(find.text('This photo is no longer available.'), findsOneWidget);
  });

  testWidgets(
    'private video full screen reuses one byte load, source and controller',
    (tester) async {
      var loads = 0;
      var prepares = 0;
      var sourceDisposals = 0;
      VideoPlayerController? preparedController;

      await _pumpBubble(
        tester,
        _message(id: 'video', type: MessageType.video, mediaUrl: _privateVideo),
        loader: (_, maxBytes) async {
          loads += 1;
          expect(maxBytes, 64 * 1024 * 1024);
          return Uint8List.fromList([1, 2, 3]);
        },
        videoSourcePreparer: (_, messageId, mediaReference) async {
          prepares += 1;
          expect(messageId, 'video');
          expect(mediaReference, _privateVideo);
          return _PreparedVideoSource(
            onCreate: (controller) => preparedController = controller,
            onDispose: () => sourceDisposals += 1,
          );
        },
      );

      await tester.tap(
        find.byKey(const ValueKey('direct-video-fullscreen-video')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.byType(DirectVideoFullscreenViewer), findsOneWidget);
      expect(loads, 1);
      expect(prepares, 1);
      expect(preparedController, isNotNull);
      expect(videoPlatform.engines, hasLength(1));
      expect(videoPlatform.engines.single.playing, isTrue);

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 420);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pump();
      expect(videoPlatform.engines, hasLength(1));
      expect(preparedController, isNotNull);

      await tester.tap(
        find.byKey(const ValueKey('direct-video-fullscreen-toggle')),
      );
      await tester.pump();
      expect(videoPlatform.engines.single.playing, isFalse);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(DirectVideoFullscreenViewer), findsNothing);
      expect(loads, 1);
      expect(prepares, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(sourceDisposals, 1);
      expect(videoPlatform.engines.single.disposed, isTrue);
    },
  );

  testWidgets('open private video is revoked when the account owner changes', (
    tester,
  ) async {
    final owner = ValueNotifier<String>('account-a');
    addTearDown(owner.dispose);
    final message = _message(
      id: 'same-video',
      type: MessageType.video,
      mediaUrl: _privateVideo,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: ValueListenableBuilder<String>(
            valueListenable: owner,
            builder: (context, ownerId, _) => MessageBubble(
              message: message,
              currentUserId: ownerId,
              onLongPress: () {},
              privateMediaLoader: (_, _) async => Uint8List.fromList([1, 2, 3]),
              videoSourcePreparer: (_, _, _) async =>
                  _PreparedVideoSource(onCreate: (_) {}, onDispose: () {}),
              videoAudioPreparer: _prepareVideoAudio,
            ),
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('direct-video-fullscreen-same-video')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(videoPlatform.engines.single.playing, isTrue);
    expect(
      find.byKey(const ValueKey('direct-video-fullscreen-toggle')),
      findsOneWidget,
    );

    owner.value = 'account-b';
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(videoPlatform.engines.single.playing, isFalse);
    expect(videoPlatform.engines.single.disposed, isTrue);
    expect(
      find.byKey(const ValueKey('direct-video-fullscreen-toggle')),
      findsNothing,
    );
    expect(find.text('Could not play this video.'), findsOneWidget);
  });

  for (final scenario in <({String label, String first, String second})>[
    (
      label: 'private',
      first: _privateVideo,
      second:
          'gs://private/message_attachments/friend/conversation/video-2.mp4',
    ),
    (
      label: 'https',
      first: 'https://example.test/video-1.mp4',
      second: 'https://example.test/video-2.mp4',
    ),
  ]) {
    testWidgets(
      'late ${scenario.label} tile play is paused after message replacement',
      (tester) async {
        final playGate = videoPlatform.blockNextPlay();
        await _pumpBubble(
          tester,
          _message(
            id: 'video-one',
            type: MessageType.video,
            mediaUrl: scenario.first,
          ),
          loader: (_, _) async => Uint8List.fromList([1]),
          videoSourcePreparer: (_, _, _) async =>
              _PreparedVideoSource(onCreate: (_) {}, onDispose: () {}),
        );
        await tester.tap(find.byKey(const ValueKey('direct-video-video-one')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(videoPlatform.playStarted.isCompleted, isTrue);
        expect(videoPlatform.engines, hasLength(1));

        await _pumpBubble(
          tester,
          _message(
            id: 'video-two',
            type: MessageType.video,
            mediaUrl: scenario.second,
          ),
          loader: (_, _) async => Uint8List.fromList([2]),
          videoSourcePreparer: (_, _, _) async =>
              _PreparedVideoSource(onCreate: (_) {}, onDispose: () {}),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('direct-video-video-two')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        playGate.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump();

        expect(videoPlatform.engines, hasLength(2));
        final oldEngine = videoPlatform.engines.first;
        final newEngine = videoPlatform.engines.last;
        expect(oldEngine.playing, isFalse);
        expect(oldEngine.disposed, isTrue);
        expect(newEngine.playing, isTrue);
        final oldPlayComplete = videoPlatform.commands.indexOf(
          'play-1:complete',
        );
        expect(oldPlayComplete, greaterThanOrEqualTo(0));
        expect(
          videoPlatform.commands.skip(oldPlayComplete + 1),
          contains('pause-1'),
          reason: 'the old decoder must be paused after its late play returns',
        );
      },
    );
  }

  testWidgets(
    'replacement bounds cleanup when old video play and pause both stall',
    (tester) async {
      final playGate = videoPlatform.blockNextPlay();
      await _pumpBubble(
        tester,
        _message(
          id: 'video-one',
          type: MessageType.video,
          mediaUrl: _privateVideo,
        ),
        loader: (_, _) async => Uint8List.fromList([1]),
        videoSourcePreparer: (_, _, _) async =>
            _PreparedVideoSource(onCreate: (_) {}, onDispose: () {}),
      );
      await tester.tap(find.byKey(const ValueKey('direct-video-video-one')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(videoPlatform.playStarted.isCompleted, isTrue);

      final pauseGate = videoPlatform.blockNextPause();
      await _pumpBubble(
        tester,
        _message(
          id: 'video-two',
          type: MessageType.video,
          mediaUrl:
              'gs://private/message_attachments/friend/conversation/video-2.mp4',
        ),
        loader: (_, _) async => Uint8List.fromList([2]),
        videoSourcePreparer: (_, _, _) async =>
            _PreparedVideoSource(onCreate: (_) {}, onDispose: () {}),
      );
      await tester.pump();
      expect(videoPlatform.engines.single.disposed, isFalse);

      await tester.tap(find.byKey(const ValueKey('direct-video-video-two')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(videoPlatform.engines, hasLength(2));
      expect(videoPlatform.engines.last.playing, isTrue);

      await tester.pump(const Duration(milliseconds: 2100));
      await tester.pump();

      expect(
        videoPlatform.engines.first.disposed,
        isFalse,
        reason: 'dispose must wait for play to avoid a late player timer',
      );

      playGate.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(videoPlatform.engines.first.playing, isFalse);
      expect(videoPlatform.engines.first.disposed, isTrue);
      expect(videoPlatform.engines.last.playing, isTrue);

      pauseGate.complete();
      await tester.pump();
    },
  );

  testWidgets(
    'full-screen late play is revoked when its message changes underneath',
    (tester) async {
      final message = ValueNotifier<Message>(
        _message(
          id: 'video-one',
          type: MessageType.video,
          mediaUrl: _privateVideo,
        ),
      );
      addTearDown(message.dispose);
      final playGate = videoPlatform.blockNextPlay();
      var loads = 0;
      var prepares = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ValueListenableBuilder<Message>(
              valueListenable: message,
              builder: (context, value, _) => MessageBubble(
                message: value,
                currentUserId: 'viewer',
                onLongPress: () {},
                privateMediaLoader: (_, _) async {
                  loads += 1;
                  return Uint8List.fromList([1, 2, 3]);
                },
                videoSourcePreparer: (_, _, _) async {
                  prepares += 1;
                  return _PreparedVideoSource(
                    onCreate: (_) {},
                    onDispose: () {},
                  );
                },
                videoAudioPreparer: _prepareVideoAudio,
              ),
            ),
          ),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('direct-video-fullscreen-video-one')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(DirectVideoFullscreenViewer), findsOneWidget);
      expect(videoPlatform.playStarted.isCompleted, isTrue);

      message.value = _message(
        id: 'video-two',
        type: MessageType.video,
        mediaUrl:
            'gs://private/message_attachments/friend/conversation/video-2.mp4',
      );
      await tester.pump();
      expect(loads, 1);
      expect(prepares, 1);

      playGate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(videoPlatform.engines.single.playing, isFalse);
      expect(videoPlatform.engines.single.disposed, isTrue);
      expect(find.text('Could not play this video.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('direct-video-fullscreen-toggle')),
        findsNothing,
      );
      expect(loads, 1, reason: 'revocation must not redownload private bytes');
      expect(prepares, 1);

      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Try again'),
          )
          .onPressed!();
      await tester.pump();
      await tester.pump();

      expect(find.text('Could not play this video.'), findsOneWidget);
      expect(
        loads,
        1,
        reason: 'retry must stay bound to the message that opened the route',
      );
      expect(prepares, 1);
    },
  );

  testWidgets('full-screen close does not wait for a stalled pause', (
    tester,
  ) async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse('https://example.test/video.mp4'),
    );
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDirectVideoFullscreenViewer(
              context,
              controllerLoader: () async => controller,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(DirectVideoFullscreenViewer), findsOneWidget);

    final pauseGate = videoPlatform.blockNextPause();
    tester
        .widget<IconButton>(
          find.byKey(const ValueKey('direct-media-fullscreen-close')),
        )
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byType(DirectVideoFullscreenViewer),
      findsNothing,
      reason: 'a native pause stall must not trap the user in full screen',
    );
    pauseGate.complete();
    await tester.pump();
  });

  testWidgets('full-screen controls cannot restart a revoked controller', (
    tester,
  ) async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse('https://example.test/video.mp4'),
    );
    await controller.initialize();
    var isCurrent = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDirectVideoFullscreenViewer(
              context,
              controllerLoader: () async => controller,
              controllerIsCurrent: (_) => isCurrent,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump();
    expect(
      videoPlatform.commands.where((entry) => entry.startsWith('play-')),
      hasLength(2),
    );

    await controller.pause();
    await tester.pump();
    final staleToggle = tester
        .widget<IconButton>(
          find.byKey(const ValueKey('direct-video-fullscreen-toggle')),
        )
        .onPressed!;
    isCurrent = false;
    staleToggle();
    await tester.pump();
    await tester.pump();

    expect(
      videoPlatform.commands.where((entry) => entry.startsWith('play-')),
      hasLength(2),
      reason: 'the captured control must revalidate before every play',
    );
    expect(find.text('Could not play this video.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('direct-video-fullscreen-toggle')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('video viewer reports loading and failure before system back', (
    tester,
  ) async {
    final load = Completer<VideoPlayerController>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDirectVideoFullscreenViewer(
              context,
              controllerLoader: () => load.future,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump();
    expect(find.bySemanticsLabel('Loading full-screen video'), findsOneWidget);

    load.completeError(StateError('private detail must remain hidden'));
    await tester.pumpAndSettle();
    expect(find.text('Could not play this video.'), findsOneWidget);
    expect(find.textContaining('private detail'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(DirectVideoFullscreenViewer), findsNothing);
  });
}

Future<void> _pumpBubble(
  WidgetTester tester,
  Message message, {
  required Future<Uint8List?> Function(String? reference, int maxBytes) loader,
  String currentUserId = 'viewer',
  DirectVideoSourcePreparer? videoSourcePreparer,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: MessageBubble(
          message: message,
          currentUserId: currentUserId,
          onLongPress: () {},
          privateMediaLoader: loader,
          videoSourcePreparer: videoSourcePreparer,
          videoAudioPreparer: _prepareVideoAudio,
        ),
      ),
    ),
  );
}

Future<void> _prepareVideoAudio() async {}

Message _message({
  required String id,
  required MessageType type,
  required String mediaUrl,
}) {
  return Message(
    id: id,
    conversationId: 'conversation',
    senderId: 'friend',
    type: type,
    content: type == MessageType.image ? 'Photo' : 'Video',
    mediaUrl: mediaUrl,
    durationSeconds: type == MessageType.video ? 30 : null,
    sentAt: DateTime.utc(2026, 9, 13),
    readBy: const [],
    reactions: const {},
  );
}

class _PreparedVideoSource implements PreparedDirectVideoSource {
  _PreparedVideoSource({required this.onCreate, required this.onDispose});

  final ValueChanged<VideoPlayerController> onCreate;
  final VoidCallback onDispose;

  @override
  VideoPlayerController createController() {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse('https://decoder-boundary.invalid/video'),
    );
    onCreate(controller);
    return controller;
  }

  @override
  Future<void> dispose() async => onDispose();
}

class _VideoEngine {
  _VideoEngine() : events = StreamController<VideoEvent>(onCancel: () async {});

  final StreamController<VideoEvent> events;
  bool playing = false;
  bool disposed = false;
  Duration position = Duration.zero;
}

class _VideoPlatform extends VideoPlayerPlatform {
  final List<_VideoEngine> engines = [];
  final List<String> commands = [];
  Completer<void> playStarted = Completer<void>();
  Completer<void>? _nextPlayGate;
  Completer<void>? _nextPauseGate;

  Completer<void> blockNextPlay() {
    final gate = Completer<void>();
    _nextPlayGate = gate;
    playStarted = Completer<void>();
    return gate;
  }

  Completer<void> blockNextPause() {
    final gate = Completer<void>();
    _nextPauseGate = gate;
    return gate;
  }

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final engine = _VideoEngine();
    engines.add(engine);
    engine.events.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 30),
        size: const Size(1920, 1080),
      ),
    );
    return engines.length;
  }

  _VideoEngine _engine(int playerId) => engines[playerId - 1];

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      _engine(playerId).events.stream;

  @override
  Future<void> dispose(int playerId) async {
    final engine = _engine(playerId);
    engine.playing = false;
    engine.disposed = true;
    commands.add('dispose-$playerId');
    await engine.events.close();
  }

  @override
  Future<void> play(int playerId) async {
    commands.add('play-$playerId:start');
    if (!playStarted.isCompleted) playStarted.complete();
    final gate = _nextPlayGate;
    _nextPlayGate = null;
    await gate?.future;
    final engine = _engine(playerId);
    if (!engine.disposed) engine.playing = true;
    commands.add('play-$playerId:complete');
  }

  @override
  Future<void> pause(int playerId) async {
    commands.add('pause-$playerId:start');
    final gate = _nextPauseGate;
    _nextPauseGate = null;
    await gate?.future;
    _engine(playerId).playing = false;
    commands.add('pause-$playerId');
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    _engine(playerId).position = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      _engine(playerId).position;

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => ColoredBox(
    key: ValueKey('test-video-view-${options.playerId}'),
    color: Colors.deepPurple,
  );
}

const _privatePhoto =
    'gs://private/message_attachments/friend/conversation/photo.jpg';
const _privateVideo =
    'gs://private/message_attachments/friend/conversation/video.mp4';

final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
