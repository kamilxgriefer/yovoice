import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/shared_media_screen.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_voice_playback_source.dart';
import 'package:yovoice/features/messages/presentation/widgets/message_bubble.dart';

void main() {
  Widget host(
    Stream<List<Message>> stream, {
    required Future<Uint8List?> Function(String? reference, int maxBytes)
    loader,
    AudioPlayer Function()? playerFactory,
    DirectVoiceSourcePreparer? sourcePreparer,
  }) => MaterialApp(
    theme: AppTheme.darkTheme,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: SharedMediaScreen(
      conversationId: 'conversation',
      messagesStream: stream,
      privateMediaLoader: loader,
      audioPlayerFactory: playerFactory,
      voiceSourcePreparer: sourcePreparer,
    ),
  );

  testWidgets('tabs filter real photo, video and voice history', (
    tester,
  ) async {
    final loaded = <String>[];
    final players = <_FakeAudioPlayer>[];
    final prepared = <String>[];
    await tester.pumpWidget(
      host(
        Stream.value([
          _message('photo-gs', MessageType.image, _photoGs),
          _message('photo-https', MessageType.image, _photoHttps),
          _message('video-gs', MessageType.video, _videoGs, duration: 18),
          _message('voice-gs', MessageType.voice, _voiceGs, duration: 8),
          _message('voice-https', MessageType.voice, _voiceHttps, duration: 12),
          _message('deleted-photo', MessageType.image, _photoGs, deleted: true),
        ]),
        loader: (reference, _) async {
          loaded.add(reference ?? '');
          return reference == _photoGs
              ? _onePixelPng
              : Uint8List.fromList([1, 2, 3]);
        },
        playerFactory: () {
          final player = _FakeAudioPlayer();
          players.add(player);
          return player;
        },
        sourcePreparer: (bytes, messageId) async {
          prepared.add(messageId);
          return PreparedDirectVoiceSource(
            source: DeviceFileSource('/tmp/$messageId.m4a'),
            dispose: () async {},
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Videos'), findsOneWidget);
    expect(find.text('Voice'), findsOneWidget);
    expect(find.bySemanticsLabel('Shared photo'), findsNWidgets(2));
    expect(loaded, contains(_photoGs));
    expect(loaded, isNot(contains(_photoHttps)));

    await tester.tap(find.text('Videos'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('Shared video')), findsOneWidget);
    expect(find.byKey(const ValueKey('direct-video-video-gs')), findsOneWidget);

    await tester.tap(find.text('Voice'));
    await tester.pumpAndSettle();
    expect(find.byType(DirectMessageMediaPreview), findsNWidgets(2));
    expect(find.byIcon(Icons.play_arrow_rounded), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.play_arrow_rounded).first);
    await tester.pump();
    expect(loaded, contains(_voiceGs));
    expect(prepared, ['voice-gs']);
    expect(players.first.lastSource, isA<DeviceFileSource>());

    await tester.tap(find.byIcon(Icons.play_arrow_rounded).last);
    await tester.pump();
    expect(players.last.lastSource, isA<UrlSource>());
    expect((players.last.lastSource! as UrlSource).url, _voiceHttps);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading, error and retry states are explicit', (tester) async {
    final controller = StreamController<List<Message>>();
    addTearDown(controller.close);
    await tester.pumpWidget(
      host(controller.stream, loader: (_, _) async => null),
    );
    await tester.pump();
    expect(find.bySemanticsLabel('Loading shared media'), findsOneWidget);

    controller.addError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load shared media.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('older shared media can be loaded without a hidden history cap', (
    tester,
  ) async {
    final cursor = Object();
    final first = _message('new-photo', MessageType.image, _photoGs);
    final older = Message(
      id: 'older-photo',
      conversationId: 'conversation',
      senderId: 'bob',
      type: MessageType.image,
      content: '',
      mediaUrl: _photoGs,
      sentAt: DateTime.utc(2025, 1, 1),
      readBy: const [],
      reactions: const {},
    );
    var pageLoads = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: SharedMediaScreen(
          conversationId: 'conversation',
          firstPageWatcher: (type) => Stream.value(
            SharedMediaPage(
              messages: type == MessageType.image ? [first] : const [],
              cursor: type == MessageType.image ? cursor : null,
              hasMore: type == MessageType.image,
            ),
          ),
          pageLoader: (type, requestedCursor) async {
            expect(type, MessageType.image);
            expect(identical(requestedCursor, cursor), isTrue);
            pageLoads += 1;
            return SharedMediaPage(
              messages: [older],
              cursor: null,
              hasMore: false,
            );
          },
          privateMediaLoader: (_, _) async => _onePixelPng,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Shared photo'), findsOneWidget);
    await tester.tap(find.text('Load older media'));
    await tester.pumpAndSettle();

    expect(pageLoads, 1);
    expect(find.bySemanticsLabel('Shared photo'), findsNWidgets(2));
    expect(find.text('Load older media'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a soft-deleted first-page item is not resurrected from cache', (
    tester,
  ) async {
    final controller = StreamController<SharedMediaPage>();
    addTearDown(controller.close);
    final first = _message('photo-to-delete', MessageType.image, _photoGs);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: SharedMediaScreen(
          conversationId: 'conversation',
          firstPageWatcher: (type) => type == MessageType.image
              ? controller.stream
              : const Stream<SharedMediaPage>.empty(),
          pageLoader: (_, _) async =>
              const SharedMediaPage(messages: [], cursor: null, hasMore: false),
          privateMediaLoader: (_, _) async => _onePixelPng,
        ),
      ),
    );

    controller.add(
      SharedMediaPage(messages: [first], cursor: Object(), hasMore: true),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Shared photo'), findsOneWidget);

    controller.add(
      const SharedMediaPage(
        messages: [],
        cursor: null,
        hasMore: false,
        hiddenMessageIds: {'photo-to-delete'},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Shared photo'), findsNothing);
    expect(find.text('No shared photos yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery reflows at 320, 768 and 1440 px with 200% text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    for (final width in <double>[320, 768, 1440]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        host(
          Stream.value([
            _message('photo-$width-a', MessageType.image, _photoGs),
            _message('photo-$width-b', MessageType.image, _photoGs),
            _message('video-$width', MessageType.video, _videoGs, duration: 15),
          ]),
          loader: (_, _) async => _onePixelPng,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'shared media overflowed at ${width.toInt()}px / 200%',
      );
      await tester.tap(find.text('Videos'));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('direct-video-video-$width')), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'video gallery overflowed at ${width.toInt()}px / 200%',
      );
    }
    await tester.binding.setSurfaceSize(null);
  });
}

const _photoGs =
    'gs://private/message_attachments/alice/conversation/photo.jpg';
const _photoHttps = 'https://example.test/photo.jpg';
const _voiceGs =
    'gs://private/message_attachments/alice/conversation/voice.m4a';
const _voiceHttps = 'https://example.test/voice.m4a';
const _videoGs =
    'gs://private/message_attachments/alice/conversation/video.mp4';

final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

Message _message(
  String id,
  MessageType type,
  String mediaUrl, {
  int? duration,
  bool deleted = false,
}) => Message(
  id: id,
  conversationId: 'conversation',
  senderId: 'alice',
  type: type,
  content: '',
  mediaUrl: mediaUrl,
  durationSeconds: duration,
  sentAt: DateTime.utc(2026, 9, 2),
  readBy: const [],
  reactions: const {},
  isDeleted: deleted,
);

class _FakeAudioPlayer implements AudioPlayer {
  final StreamController<PlayerState> _states =
      StreamController<PlayerState>.broadcast();
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
    lastSource = source;
    _states.add(PlayerState.playing);
  }

  @override
  Future<void> pause() async => _states.add(PlayerState.paused);

  @override
  Future<void> resume() async => _states.add(PlayerState.playing);

  @override
  Future<void> stop() async => _states.add(PlayerState.stopped);

  @override
  Future<void> dispose() async => _states.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
