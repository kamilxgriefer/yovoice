import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/media/data/models/gif_asset.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_media_fullscreen_viewer.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

/// Owner report, 2026-09-18: "w czatach znajomych, na wiadomość możesz dodać
/// reakcję a na zdjęcie i filmy nie można".
///
/// A text bubble is plain content, so a touch long-press reaches the bubble's
/// context action. A photo bubble wraps its tap target in a Tooltip
/// ("View photo"), a video bubble's full-screen control carries one too, and
/// a Tooltip claims every touch long-press for itself — so the sheet with the
/// reaction row never opened. These tests drive the real gesture through the
/// arena rather than calling the bubble's `onOpen`, because the arena is
/// where the defect lived.
void main() {
  const currentUserId = 'me';
  const otherUserId = 'them';
  const reactions = ['❤️', '😂', '🔥', '😮', '😢', '👍'];
  late PublicIdentityRepository originalIdentityRepository;
  late MockFirebaseAuth auth;
  late FakeFirebaseFirestore firestore;

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: currentUserId),
    );
    firestore = FakeFirebaseFirestore();
    originalIdentityRepository = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: auth,
      fetchOverride: (uids) async => {
        for (final uid in uids) uid: {'uid': uid, 'role': 'user', 'vip': false},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentityRepository;
  });

  Widget host(_ReactionMessageService service) => MaterialApp(
    theme: AppTheme.darkTheme,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: ChatScreen(
      conversationId: 'conversation',
      otherUserId: otherUserId,
      otherDisplayName: 'Them',
      otherEmail: '',
      otherPhotoUrl: '',
      messageService: service,
      auth: auth,
      profileService: ProfileService(firestore: firestore, auth: auth),
    ),
  );

  Message incoming(
    String id,
    MessageType type, {
    String content = '',
    String? mediaUrl,
    int? durationSeconds,
    GifAsset? gif,
  }) => Message(
    id: id,
    conversationId: 'conversation',
    senderId: otherUserId,
    type: type,
    content: content,
    mediaUrl: mediaUrl,
    durationSeconds: durationSeconds,
    gif: gif,
    sentAt: DateTime.utc(2026, 9, 18, 12),
    readBy: const <String>[],
    reactions: const <String, String>{},
  );

  Future<void> expectActionsSheet(WidgetTester tester, String subject) async {
    for (final emoji in reactions) {
      expect(
        find.text(emoji),
        findsOneWidget,
        reason: 'the reaction row must open from $subject',
      );
    }
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Report message'), findsOneWidget);
  }

  Future<void> dismissSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Reply'), findsNothing);
  }

  testWidgets('a long-press on a photo bubble opens the reaction row', (
    tester,
  ) async {
    final service = _ReactionMessageService(
      firestore,
      auth,
      messages: [
        incoming(
          'm-photo',
          MessageType.image,
          mediaUrl: 'https://example.invalid/photo.jpg',
        ),
      ],
    );
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    final photo = find.byKey(const ValueKey('direct-image-m-photo'));
    expect(photo, findsOneWidget);
    await tester.longPress(photo);
    await tester.pumpAndSettle();

    expect(
      find.text('View photo'),
      findsNothing,
      reason: 'the photo tooltip must not swallow the long-press',
    );
    await expectActionsSheet(tester, 'a photo bubble');

    await tester.tap(find.text('❤️'));
    await tester.pumpAndSettle();
    expect(service.reactions, [
      (conversationId: 'conversation', messageId: 'm-photo', emoji: '❤️'),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long-press on a video bubble opens the reaction row from the '
      'full-screen control and from the play control', (tester) async {
    final service = _ReactionMessageService(
      firestore,
      auth,
      messages: [
        incoming(
          'm-video',
          MessageType.video,
          content: 'Video',
          mediaUrl: 'fixture://m-video',
          durationSeconds: 9,
        ),
      ],
    );
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    final fullscreen = find.byKey(
      const ValueKey('direct-video-fullscreen-m-video'),
    );
    expect(fullscreen, findsOneWidget);
    await tester.longPress(fullscreen);
    await tester.pumpAndSettle();
    expect(find.text('Open video full screen'), findsNothing);
    expect(find.byType(DirectVideoFullscreenViewer), findsNothing);
    await expectActionsSheet(tester, "a video bubble's full-screen control");
    await dismissSheet(tester);

    await tester.longPress(find.byKey(const ValueKey('direct-video-m-video')));
    await tester.pumpAndSettle();
    await expectActionsSheet(tester, "a video bubble's play control");

    await tester.tap(find.text('🔥'));
    await tester.pumpAndSettle();
    expect(service.reactions, [
      (conversationId: 'conversation', messageId: 'm-video', emoji: '🔥'),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long-press on a voice bubble opens the reaction row', (
    tester,
  ) async {
    final service = _ReactionMessageService(
      firestore,
      auth,
      messages: [
        incoming(
          'm-voice',
          MessageType.voice,
          mediaUrl: 'fixture://m-voice',
          durationSeconds: 4,
        ),
      ],
    );
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('direct-voice-m-voice')));
    await tester.pumpAndSettle();
    await expectActionsSheet(tester, 'a voice bubble');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a long-press on a GIF that failed to load opens the reaction row',
    (tester) async {
      final service = _ReactionMessageService(
        firestore,
        auth,
        messages: [
          incoming(
            'm-gif',
            MessageType.gif,
            content: 'GIF: Hello',
            gif: const GifAsset(
              provider: 'giphy',
              id: 'hello',
              title: 'Hello',
              rating: 'g',
              previewUrl: 'https://example.invalid/hello-preview.gif',
              url: 'https://example.invalid/hello.gif',
              width: 200,
              height: 160,
            ),
          ),
        ],
      );
      await tester.pumpWidget(host(service));
      await tester.pump();

      // The network image fails under flutter_test, which is exactly the
      // state that wraps the GIF in its "Retry" tooltip.
      final retry = find.byKey(const ValueKey('gif-view-retry'));
      for (var i = 0; i < 30 && retry.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(retry, findsOneWidget);

      await tester.longPress(retry);
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
      await expectActionsSheet(tester, 'a GIF bubble');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a tap on the photo still opens it full screen', (tester) async {
    final service = _ReactionMessageService(
      firestore,
      auth,
      messages: [
        incoming(
          'm-photo',
          MessageType.image,
          mediaUrl: 'https://example.invalid/photo.jpg',
        ),
      ],
    );
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('direct-image-m-photo')));
    await tester.pumpAndSettle();
    expect(find.byType(DirectImageFullscreenViewer), findsOneWidget);
    expect(find.text('Reply'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'with a mouse the photo tooltip still shows on hover and a right-click '
    'opens the reaction row',
    (tester) async {
      final service = _ReactionMessageService(
        firestore,
        auth,
        messages: [
          incoming(
            'm-photo',
            MessageType.image,
            mediaUrl: 'https://example.invalid/photo.jpg',
          ),
        ],
      );
      await tester.pumpWidget(host(service));
      await tester.pumpAndSettle();

      final photo = find.byKey(const ValueKey('direct-image-m-photo'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(photo));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('View photo'), findsOneWidget);

      await tester.tap(
        photo,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await expectActionsSheet(tester, 'a right-click on a photo bubble');
      expect(tester.takeException(), isNull);
    },
  );
}

class _ReactionMessageService extends MessageService {
  _ReactionMessageService(
    FakeFirebaseFirestore firestore,
    MockFirebaseAuth auth, {
    required List<Message> messages,
  }) : _messages = messages,
       super(firestore: firestore, auth: auth);

  final List<Message> _messages;
  final List<({String conversationId, String messageId, String emoji})>
  reactions = [];

  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      Stream.value(_messages);

  @override
  Stream<bool> watchTyping({
    required String conversationId,
    required String otherUserId,
  }) => Stream.value(false);

  @override
  Stream<ChatPresence> watchUserPresence(String userId) =>
      Stream.value(const ChatPresence(isOnline: false, lastSeen: null));

  @override
  Future<void> markConversationRead(String conversationId) async {}

  @override
  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) async {}

  @override
  Future<void> toggleReaction({
    required String conversationId,
    required String messageId,
    required String emoji,
  }) async {
    reactions.add((
      conversationId: conversationId,
      messageId: messageId,
      emoji: emoji,
    ));
  }
}
