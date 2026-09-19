import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/messages/presentation/screens/messages_screen.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';

/// T-4 — a conversation row's avatar used to be swallowed by the row's own
/// InkWell, so tapping the person's photo opened the thread and there was no
/// way to look at the photo at all. The avatar is now its own target that
/// opens the canonical profile preview, while the row body and the row's
/// long-press actions keep working exactly as before.
void main() {
  const currentUserId = 'me-uid';
  const otherUserId = 'them-uid';
  const conversationId = 'me-uid_them-uid';
  const avatarTooltip = 'Open Them profile';

  late FakeFirebaseFirestore firestore;

  MockFirebaseAuth auth() =>
      MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: currentUserId));

  Conversation conversation() => Conversation(
    id: conversationId,
    participantIds: const <String>[currentUserId, otherUserId],
    participantNames: const <String, String>{
      currentUserId: 'Me',
      otherUserId: 'Them',
    },
    participantEmails: const <String, String>{},
    participantPhotoUrls: const <String, String>{},
    unreadCounts: const <String, int>{currentUserId: 0, otherUserId: 0},
    lastMessage: 'See you soon',
    lastMessageType: MessageType.text,
    lastMessageSenderId: otherUserId,
    updatedAt: DateTime.utc(2026, 9, 18, 12),
    createdAt: DateTime.utc(2026, 9, 18, 11),
    archivedBy: const <String>[],
    mutedBy: const <String>[],
  );

  Future<void> pumpChats(
    WidgetTester tester, {
    Size size = const Size(360, 780),
    double textScaleFactor = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.darkTheme,
        home: MessagesScreen(
          messageService: _RowService(<Conversation>[conversation()]),
          friendService: _EmptyFriendService(),
          auth: auth(),
          firestore: firestore,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    firestore = FakeFirebaseFirestore();
  });

  // 1.0 is the ordinary Row branch; 1.6 crosses into the enlarged-text
  // Column branch, which builds a second _ConversationAvatar call site.
  for (final textScaleFactor in <double>[1, 1.6]) {
    final scaleLabel = 'at ${textScaleFactor}x text';

    testWidgets('tapping the avatar opens the profile preview $scaleLabel', (
      tester,
    ) async {
      await pumpChats(tester, textScaleFactor: textScaleFactor);

      expect(find.byTooltip(avatarTooltip), findsOneWidget);
      await tester.tap(find.byTooltip(avatarTooltip));
      await tester.pumpAndSettle();

      expect(find.byType(ProfilePreviewSheet), findsOneWidget);
      expect(
        find.byType(ChatScreen),
        findsNothing,
        reason: 'the photo is a door to the person, not to the thread',
      );
    });

    testWidgets('tapping the row body still opens the conversation '
        '$scaleLabel', (tester) async {
      await pumpChats(tester, textScaleFactor: textScaleFactor);

      await tester.tap(find.text('See you soon'));
      await tester.pumpAndSettle();

      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.byType(ProfilePreviewSheet), findsNothing);
    });

    testWidgets('long-pressing the avatar still opens the row actions '
        '$scaleLabel', (tester) async {
      await pumpChats(tester, textScaleFactor: textScaleFactor);

      await tester.longPress(find.byTooltip(avatarTooltip));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('conversation-archive-action')),
        findsOneWidget,
        reason: 'a nested tap target must not swallow the row long-press',
      );
      expect(find.byType(ProfilePreviewSheet), findsNothing);
    });
  }

  // The row is laid out inside ResponsiveContentFrame, so the avatar keeps
  // its own fixed target at every width; these prove it rather than assume.
  for (final size in const <Size>[Size(600, 900), Size(1280, 900)]) {
    testWidgets('the avatar stays its own target at ${size.width.toInt()} px', (
      tester,
    ) async {
      await pumpChats(tester, size: size);

      await tester.tap(find.byTooltip(avatarTooltip));
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePreviewSheet), findsOneWidget);
      expect(find.byType(ChatScreen), findsNothing);

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      await tester.tap(find.text('See you soon'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);
    });
  }

  testWidgets('the avatar announces one button node carrying presence', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpChats(tester);

    final node = find.bySemanticsLabel('Open Them profile, offline');
    expect(node, findsOneWidget);
    expect(
      tester.getSemantics(node).getSemanticsData().flagsCollection.isButton,
      isTrue,
      reason: 'the photo must announce one button, not a nested image',
    );
    expect(
      tester.getSize(find.byTooltip(avatarTooltip)).height,
      greaterThanOrEqualTo(48),
      reason: 'the photo target must stay at least a comfortable tap size',
    );
    semantics.dispose();
  });
}

class _RowService extends MessageService {
  _RowService(this.conversations)
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'me-uid'),
        ),
      );

  final List<Conversation> conversations;

  @override
  Stream<List<Conversation>> watchConversations({
    bool includeArchived = false,
  }) => Stream<List<Conversation>>.value(conversations);

  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      Stream<List<Message>>.value(const <Message>[]);

  @override
  Stream<bool> watchTyping({
    required String conversationId,
    required String otherUserId,
  }) => Stream<bool>.value(false);

  @override
  Stream<ChatPresence> watchUserPresence(String userId) =>
      Stream<ChatPresence>.value(
        const ChatPresence(isOnline: false, lastSeen: null),
      );

  @override
  Future<void> markConversationRead(String conversationId) async {}
}

class _EmptyFriendService extends FriendService {
  _EmptyFriendService()
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'me-uid'),
        ),
      );

  @override
  Stream<List<FriendUser>> watchFriends() =>
      Stream<List<FriendUser>>.value(const <FriendUser>[]);
}
