import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
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
import 'package:yovoice/shared/identity/public_identity_repository.dart';

void main() {
  const currentUserId = 'me-uid';
  const otherUserId = 'them-uid';
  const conversationId = 'me-uid_them-uid';
  const phone = Size(390, 844);

  late PublicIdentityRepository originalIdentityRepository;

  Widget host(Widget child) => MaterialApp(
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

  MockFirebaseAuth auth() =>
      MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: currentUserId));

  Conversation conversation({required bool archived}) => Conversation(
    id: conversationId,
    participantIds: const <String>[currentUserId, otherUserId],
    participantNames: const <String, String>{
      currentUserId: 'Me',
      otherUserId: 'Them',
    },
    participantEmails: const <String, String>{
      currentUserId: '',
      otherUserId: '',
    },
    participantPhotoUrls: const <String, String>{
      currentUserId: '',
      otherUserId: '',
    },
    unreadCounts: const <String, int>{currentUserId: 0, otherUserId: 0},
    archivedBy: archived ? const <String>[currentUserId] : const <String>[],
    mutedBy: const <String>[],
    lastMessage: 'See you soon',
    lastMessageType: MessageType.text,
    lastMessageSenderId: otherUserId,
    createdAt: DateTime.utc(2026, 9, 1, 11),
    updatedAt: DateTime.utc(2026, 9, 1, 12),
  );

  void usePhone(WidgetTester tester) {
    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpMessages(
    WidgetTester tester,
    _BlockingPreferenceService service, {
    bool reduceMotion = false,
  }) async {
    usePhone(tester);
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: MessagesScreen(
              messageService: service,
              friendService: _EmptyFriendService(),
              auth: auth(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpChat(
    WidgetTester tester,
    _BlockingPreferenceService service, {
    bool reduceMotion = false,
  }) async {
    usePhone(tester);
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => ChatScreen(
                  conversationId: conversationId,
                  otherUserId: otherUserId,
                  otherDisplayName: 'Them',
                  otherEmail: '',
                  otherPhotoUrl: '',
                  messageService: service,
                  auth: auth(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openListActions(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Conversation actions for Them'));
    await tester.pumpAndSettle();
  }

  Future<void> startChatArchive(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Conversation options'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-archive-action')));
    await tester.pump(const Duration(milliseconds: 350));
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    originalIdentityRepository = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: auth(),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids)
          uid: <String, Object?>{'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentityRepository;
  });

  group('MessagesScreen preference progress', () {
    testWidgets('archive is visible, disabled, single-flight and succeeds', (
      tester,
    ) async {
      final service = _BlockingPreferenceService(
        conversations: <Conversation>[conversation(archived: false)],
      );
      await pumpMessages(tester, service);
      await openListActions(tester);

      final action = find.byKey(const ValueKey('conversation-archive-action'));
      final actionCenter = tester.getCenter(action);
      await tester.tapAt(actionCenter);
      await tester.tapAt(actionCenter);
      await tester.pump();

      expect(service.archiveCalls, 1);
      final busy = find.byKey(
        const ValueKey('conversation-preference-busy-me-uid_them-uid'),
      );
      expect(busy, findsOneWidget);
      expect(tester.getSemantics(busy).label, 'Archiving conversation');
      expect(
        find.byKey(
          const ValueKey('conversation-preference-progress-me-uid_them-uid'),
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Conversation actions for Them'), findsNothing);

      await tester.tap(busy);
      await tester.tap(busy);
      expect(service.archiveCalls, 1);

      service.archiveGate.complete();
      await tester.pumpAndSettle();

      expect(find.text('Conversation archived.'), findsOneWidget);
      expect(busy, findsNothing);
      expect(find.byTooltip('Conversation actions for Them'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'unarchive failure restores controls and Reduce Motion stays static',
      (tester) async {
        final service = _BlockingPreferenceService(
          conversations: <Conversation>[conversation(archived: true)],
          unarchiveFailure: FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'Permanent refusal.',
          ),
        );
        await pumpMessages(tester, service, reduceMotion: true);
        await tester.tap(find.byTooltip('Show archived conversations'));
        await tester.pumpAndSettle();
        await openListActions(tester);
        await tester.tap(
          find.byKey(const ValueKey('conversation-archive-action')),
        );
        await tester.pump();

        expect(service.unarchiveCalls, 1);
        final busy = find.byKey(
          const ValueKey('conversation-preference-busy-me-uid_them-uid'),
        );
        expect(tester.getSemantics(busy).label, 'Restoring conversation');
        expect(
          find.byKey(
            const ValueKey('conversation-preference-static-me-uid_them-uid'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const ValueKey('conversation-preference-progress-me-uid_them-uid'),
          ),
          findsNothing,
        );

        service.unarchiveGate.complete();
        await tester.pumpAndSettle();

        expect(
          find.text('Could not restore this conversation.'),
          findsOneWidget,
        );
        expect(find.byTooltip('Conversation actions for Them'), findsOneWidget);
        expect(service.unarchiveCalls, 1);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('ChatScreen archive progress', () {
    testWidgets('archive is disabled single-flight and closes after success', (
      tester,
    ) async {
      final service = _BlockingPreferenceService();
      await pumpChat(tester, service);
      await startChatArchive(tester);

      expect(service.archiveCalls, 1);
      final busy = find.byKey(const ValueKey('chat-archive-busy'));
      expect(busy, findsOneWidget);
      final busySemantics = tester.widget<Semantics>(busy).properties;
      expect(busySemantics.label, 'Archiving conversation');
      expect(busySemantics.liveRegion, isTrue);
      expect(busySemantics.enabled, isFalse);
      expect(
        find.byKey(const ValueKey('chat-archive-progress')),
        findsOneWidget,
      );
      expect(find.byTooltip('Conversation options'), findsNothing);

      await tester.tap(busy);
      await tester.tap(busy);
      expect(service.archiveCalls, 1);

      service.archiveGate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(ChatScreen), findsNothing);
      expect(service.archiveCalls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'permanent failure restores options and reduced motion is static',
      (tester) async {
        final service = _BlockingPreferenceService(
          archiveFailure: FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'Permanent refusal.',
          ),
        );
        await pumpChat(tester, service, reduceMotion: true);
        await startChatArchive(tester);

        expect(service.archiveCalls, 1);
        expect(find.byKey(const ValueKey('chat-archive-static')), findsOne);
        expect(
          find.byKey(const ValueKey('chat-archive-progress')),
          findsNothing,
        );

        service.archiveGate.complete();
        await tester.pumpAndSettle();

        expect(find.byType(ChatScreen), findsOneWidget);
        expect(
          find.text('Could not archive this conversation.'),
          findsOneWidget,
        );
        expect(find.byTooltip('Conversation options'), findsOneWidget);
        expect(service.archiveCalls, 1);
        expect(tester.takeException(), isNull);
      },
    );
  });
}

class _BlockingPreferenceService extends MessageService {
  _BlockingPreferenceService({
    this.conversations = const <Conversation>[],
    this.archiveFailure,
    this.unarchiveFailure,
  }) : super(
         firestore: FakeFirebaseFirestore(),
         auth: MockFirebaseAuth(
           signedIn: true,
           mockUser: MockUser(uid: 'me-uid'),
         ),
       );

  final List<Conversation> conversations;
  final Object? archiveFailure;
  final Object? unarchiveFailure;
  final Completer<void> archiveGate = Completer<void>();
  final Completer<void> unarchiveGate = Completer<void>();
  int archiveCalls = 0;
  int unarchiveCalls = 0;

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

  @override
  Future<void> archiveConversation(String conversationId) async {
    archiveCalls++;
    await archiveGate.future;
    final failure = archiveFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> unarchiveConversation(String conversationId) async {
    unarchiveCalls++;
    await unarchiveGate.future;
    final failure = unarchiveFailure;
    if (failure != null) throw failure;
  }
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
