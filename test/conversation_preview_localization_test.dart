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
import 'package:yovoice/features/home/presentation/widgets/shared/recent_chats.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/messages_screen.dart';

/// R-08 — the Chats list printed the server's English tombstone verbatim
/// while the thread it opened printed the Polish one. Every surface that
/// previews a conversation's last message now goes through the single
/// [conversationPreview] helper, so the list and the thread agree.
void main() {
  const currentUserId = 'me-uid';
  const otherUserId = 'them-uid';
  const conversationId = 'me-uid_them-uid';

  Conversation conversation({
    required String lastMessage,
    MessageType type = MessageType.text,
    String senderId = currentUserId,
  }) => Conversation(
    id: conversationId,
    participantIds: const <String>[currentUserId, otherUserId],
    participantNames: const <String, String>{
      currentUserId: 'Me',
      otherUserId: 'Them',
    },
    participantEmails: const <String, String>{},
    participantPhotoUrls: const <String, String>{},
    unreadCounts: const <String, int>{currentUserId: 0, otherUserId: 0},
    lastMessage: lastMessage,
    lastMessageType: type,
    lastMessageSenderId: senderId,
    updatedAt: DateTime.utc(2026, 9, 18, 12),
    createdAt: DateTime.utc(2026, 9, 18, 11),
    archivedBy: const <String>[],
    mutedBy: const <String>[],
  );

  Widget host({required Locale locale, required Widget child}) => MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: AppTheme.darkTheme,
    home: child,
  );

  void usePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  group('Chats list', () {
    Future<void> pumpChats(
      WidgetTester tester, {
      required Locale locale,
      required Conversation seed,
    }) async {
      usePhone(tester);
      await tester.pumpWidget(
        host(
          locale: locale,
          child: MessagesScreen(
            messageService: _FixedConversationService(<Conversation>[seed]),
            friendService: _EmptyFriendService(),
            auth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: currentUserId),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the deletion tombstone is Polish in the Polish list', (
      tester,
    ) async {
      await pumpChats(
        tester,
        locale: const Locale('pl'),
        seed: conversation(lastMessage: 'Message deleted'),
      );

      expect(find.text('Ty: Wiadomość usunięta'), findsOneWidget);
      expect(find.textContaining('Message deleted'), findsNothing);
    });

    testWidgets('the deletion tombstone stays English in the English list', (
      tester,
    ) async {
      await pumpChats(
        tester,
        locale: const Locale('en'),
        seed: conversation(lastMessage: 'Message deleted'),
      );

      expect(find.text('You: Message deleted'), findsOneWidget);
    });

    testWidgets('ordinary message bodies are never translated', (tester) async {
      await pumpChats(
        tester,
        locale: const Locale('pl'),
        seed: conversation(
          lastMessage: 'Message deleted yesterday',
          senderId: otherUserId,
        ),
      );

      expect(find.text('Message deleted yesterday'), findsOneWidget);
    });
  });

  group('Home recent chats', () {
    Future<void> pumpRecentChats(
      WidgetTester tester, {
      required Locale locale,
      required Conversation seed,
    }) async {
      usePhone(tester);
      await tester.pumpWidget(
        host(
          locale: locale,
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: RecentChats(
                snapshot: AsyncSnapshot<List<Conversation>>.withData(
                  ConnectionState.active,
                  <Conversation>[seed],
                ),
                currentUserId: currentUserId,
                onOpenConversation: (_) {},
                onFindFriends: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('the card matches the Polish thread', (tester) async {
      await pumpRecentChats(
        tester,
        locale: const Locale('pl'),
        seed: conversation(lastMessage: 'Message deleted'),
      );

      expect(find.text('Ty: Wiadomość usunięta'), findsOneWidget);
      expect(find.textContaining('Message deleted'), findsNothing);
    });

    testWidgets('an empty thread uses the Polish call to action', (
      tester,
    ) async {
      await pumpRecentChats(
        tester,
        locale: const Locale('pl'),
        seed: conversation(lastMessage: ''),
      );

      expect(find.text('Rozpocznij rozmowę'), findsOneWidget);
      expect(find.text('Start a conversation'), findsNothing);
    });

    testWidgets('the English card is unchanged', (tester) async {
      await pumpRecentChats(
        tester,
        locale: const Locale('en'),
        seed: conversation(lastMessage: 'Message deleted'),
      );

      expect(find.text('You: Message deleted'), findsOneWidget);
    });
  });

  group('conversationPreview', () {
    test('maps only the exact tombstone, never a body that contains it', () {
      const polish = AppLocalizations(Locale('pl'));

      expect(
        conversationPreview(
          conversation(lastMessage: 'Message deleted'),
          currentUserId,
          polish,
        ),
        'Ty: Wiadomość usunięta',
      );
      expect(
        conversationPreview(
          conversation(
            lastMessage: 'Message deleted?',
            senderId: otherUserId,
          ),
          currentUserId,
          polish,
        ),
        'Message deleted?',
      );
      expect(
        conversationPreview(
          conversation(lastMessage: 'x', type: MessageType.voice),
          currentUserId,
          polish,
        ),
        'Ty: Wiadomość głosowa',
      );
    });
  });
}

class _FixedConversationService extends MessageService {
  _FixedConversationService(this.conversations)
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
  Stream<ChatPresence> watchUserPresence(String userId) =>
      Stream<ChatPresence>.value(
        const ChatPresence(isOnline: false, lastSeen: null),
      );
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
