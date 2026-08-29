import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/presentation/widgets/message_bubble.dart';

void main() {
  for (final entry in <String, ThemeData>{
    'dark': AppTheme.darkTheme,
    'light': AppTheme.lightTheme,
  }.entries) {
    testWidgets('${entry.key} voice loading and failure stay readable', (
      tester,
    ) async {
      final load = Completer<Uint8List?>();
      await _pumpBubble(
        tester,
        _voiceMessage(id: 'voice-${entry.key}', mediaUrl: _voiceOne),
        loader: (_, _) => load.future,
        playerFactory: _FakeAudioPlayer.new,
        theme: entry.value,
      );

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();
      final palette = entry.value.extension<AppPalette>()!;
      final loading = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(loading.color, palette.textPrimary);

      load.complete(null);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${entry.key} image loading and error expose retry', (
      tester,
    ) async {
      final load = Completer<Uint8List?>();
      await _pumpBubble(
        tester,
        _imageMessage(id: 'image-${entry.key}', mediaUrl: _imageOne),
        loader: (_, _) => load.future,
        theme: entry.value,
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      load.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('Photo unavailable — retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('paused voice resumes from the same source and a new message '
      'drops cached bytes before playback', (tester) async {
    final player = _FakeAudioPlayer();
    final loadedReferences = <String>[];

    Future<Uint8List?> loader(String? reference, int maxBytes) async {
      loadedReferences.add(reference ?? '');
      return Uint8List.fromList(reference == _voiceOne ? [1, 2, 3] : [4, 5, 6]);
    }

    await _pumpBubble(
      tester,
      _voiceMessage(id: 'voice-1', mediaUrl: _voiceOne),
      loader: loader,
      playerFactory: () => player,
    );

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(player.playCount, 1);
    expect(player.resumeCount, 0);
    expect(loadedReferences, [_voiceOne]);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    expect(player.pauseCount, 1);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(
      player.playCount,
      1,
      reason: 'play(source) restarts from position 0',
    );
    expect(player.resumeCount, 1);
    expect(loadedReferences, [_voiceOne]);

    await _pumpBubble(
      tester,
      _voiceMessage(id: 'voice-2', mediaUrl: _voiceTwo),
      loader: loader,
      playerFactory: () => player,
    );
    await tester.pump();
    expect(player.stopCount, 1);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(loadedReferences, [_voiceOne, _voiceTwo]);
    expect(player.playCount, 2);
    expect(player.lastSource, isA<BytesSource>());
  });

  testWidgets('a changed image id/source never renders the previous image '
      'while the new private object is loading', (tester) async {
    final second = Completer<Uint8List?>();
    final loadedReferences = <String>[];

    Future<Uint8List?> loader(String? reference, int maxBytes) {
      loadedReferences.add(reference ?? '');
      if (reference == _imageTwo) return second.future;
      return Future<Uint8List?>.value(_onePixelPng);
    }

    await _pumpBubble(
      tester,
      _imageMessage(id: 'image-1', mediaUrl: _imageOne),
      loader: loader,
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);

    await _pumpBubble(
      tester,
      _imageMessage(id: 'image-2', mediaUrl: _imageTwo),
      loader: loader,
    );
    await tester.pump();

    expect(loadedReferences, [_imageOne, _imageTwo]);
    expect(
      find.byType(Image),
      findsNothing,
      reason: 'the first attachment must not appear under the second message',
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    second.complete(_onePixelPng);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('voice bubble stays inside 320–1440 px at 200% text scale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    for (final width in [320.0, 390.0, 768.0, 1440.0]) {
      await tester.binding.setSurfaceSize(Size(width, 844));
      await _pumpBubble(
        tester,
        _voiceMessage(id: 'voice-$width', mediaUrl: _voiceOne),
        loader: (_, _) async => Uint8List.fromList([1, 2, 3]),
        playerFactory: _FakeAudioPlayer.new,
      );
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'voice bubble overflowed at ${width.toInt()} px / 200%',
      );
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('reaction pill stays below voice duration at 200% text scale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    for (final width in [320.0, 390.0, 768.0, 1440.0]) {
      await tester.binding.setSurfaceSize(Size(width, 844));
      await _pumpBubble(
        tester,
        _voiceMessage(
          id: 'reacted-$width',
          mediaUrl: _voiceOne,
          durationSeconds: 47,
          reactions: const {'first': '🔥', 'second': '🔥'},
        ),
        loader: (_, _) async => Uint8List.fromList([1, 2, 3]),
        playerFactory: _FakeAudioPlayer.new,
      );
      await tester.pump();

      final durationRect = tester.getRect(find.text('0:47'));
      final reactionRect = tester.getRect(find.text('🔥 2'));
      expect(
        durationRect.overlaps(reactionRect),
        isFalse,
        reason: 'reaction covered duration at ${width.toInt()} px / 200%',
      );
      expect(
        reactionRect.top,
        greaterThanOrEqualTo(durationRect.bottom),
        reason: 'reaction was not laid out below media at ${width.toInt()} px',
      );
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(null);
  });
}

const _voiceOne = 'gs://private/message_attachments/a/c/voice-1.m4a';
const _voiceTwo = 'gs://private/message_attachments/a/c/voice-2.m4a';
const _imageOne = 'gs://private/message_attachments/a/c/image-1.jpg';
const _imageTwo = 'gs://private/message_attachments/a/c/image-2.jpg';

final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

Message _voiceMessage({
  required String id,
  required String mediaUrl,
  int durationSeconds = 7,
  Map<String, String> reactions = const {},
}) {
  return Message(
    id: id,
    conversationId: 'conversation',
    senderId: 'sender',
    type: MessageType.voice,
    content: '',
    mediaUrl: mediaUrl,
    durationSeconds: durationSeconds,
    sentAt: DateTime.utc(2026, 8, 17),
    readBy: const [],
    reactions: reactions,
  );
}

Message _imageMessage({required String id, required String mediaUrl}) {
  return Message(
    id: id,
    conversationId: 'conversation',
    senderId: 'sender',
    type: MessageType.image,
    content: '',
    mediaUrl: mediaUrl,
    sentAt: DateTime.utc(2026, 8, 17),
    readBy: const [],
    reactions: const {},
  );
}

Future<void> _pumpBubble(
  WidgetTester tester,
  Message message, {
  required Future<Uint8List?> Function(String? reference, int maxBytes) loader,
  AudioPlayer Function()? playerFactory,
  ThemeData? theme,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      home: Scaffold(
        body: MessageBubble(
          message: message,
          currentUserId: 'viewer',
          onLongPress: () {},
          privateMediaLoader: loader,
          audioPlayerFactory: playerFactory,
        ),
      ),
    ),
  );
}

class _FakeAudioPlayer implements AudioPlayer {
  final StreamController<PlayerState> _states =
      StreamController<PlayerState>.broadcast();

  int playCount = 0;
  int pauseCount = 0;
  int resumeCount = 0;
  int stopCount = 0;
  Source? lastSource;

  @override
  Stream<PlayerState> get onPlayerStateChanged => _states.stream;

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    playCount += 1;
    lastSource = source;
    _states.add(PlayerState.playing);
  }

  @override
  Future<void> pause() async {
    pauseCount += 1;
    _states.add(PlayerState.paused);
  }

  @override
  Future<void> resume() async {
    resumeCount += 1;
    _states.add(PlayerState.playing);
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    _states.add(PlayerState.stopped);
  }

  @override
  Future<void> dispose() async {
    await _states.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
