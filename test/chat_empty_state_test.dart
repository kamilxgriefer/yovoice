import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/active_conversation_registry.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

/// "You are friends on YO Voice" was hard-coded into the empty thread.
///
/// DM privacy defaults to `everyone` and `profile_preview_sheet.dart` opens
/// a thread straight from a stranger's profile, so the claim was routinely
/// false — a fabricated statement about a real relationship, which is
/// exactly what CLAUDE.md forbids. State it only when it was read and came
/// back `friends`; say nothing when it is unknown; never claim the negative.
void main() {
  const currentUserId = 'me-uid';
  const otherUserId = 'them-uid';
  const conversationId = 'me-uid_them-uid';

  late PublicIdentityRepository originalIdentityRepository;
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;

  setUp(() {
    ActiveConversationRegistry.instance.clear();
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: currentUserId),
    );
    originalIdentityRepository = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: auth,
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentityRepository;
    ActiveConversationRegistry.instance.clear();
  });

  Future<void> pumpEmptyThread(
    WidgetTester tester, {
    required RelationshipStatusInvoker resolve,
    Locale locale = const Locale('en'),
    Key? key,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ChatScreen(
          key: key,
          conversationId: conversationId,
          otherUserId: otherUserId,
          otherDisplayName: 'Them',
          otherEmail: '',
          otherPhotoUrl: '',
          messageService: _EmptyThreadService(firestore, auth),
          auth: auth,
          profileService: ProfileService(firestore: firestore, auth: auth),
          relationshipStatusResolver: resolve,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a thread with a stranger claims no friendship', (tester) async {
    var lookups = 0;
    await pumpEmptyThread(
      tester,
      resolve: (_) async {
        lookups += 1;
        return FriendRelationshipStatus.none;
      },
    );

    expect(find.text('Say hello 👋'), findsOneWidget);
    expect(find.text('You are friends on YO Voice'), findsNothing);
    expect(
      find.textContaining('not friends'),
      findsNothing,
      reason: 'the negative is a claim too, and is never drawn',
    );
    expect(lookups, 1, reason: 'resolved once, when the thread rendered empty');
  });

  testWidgets('a friend is named as one, in EN and PL', (tester) async {
    for (final testCase in const <({Locale locale, String line})>[
      (locale: Locale('en'), line: 'You are friends on YO Voice'),
      (locale: Locale('pl'), line: 'Jesteście znajomymi w YO Voice'),
    ]) {
      await pumpEmptyThread(
        tester,
        locale: testCase.locale,
        key: ValueKey<String>('chat-${testCase.locale.languageCode}'),
        resolve: (_) async => FriendRelationshipStatus.friends,
      );
      expect(find.text(testCase.line), findsOneWidget);
    }
  });

  testWidgets('a failed lookup says nothing rather than guessing', (
    tester,
  ) async {
    await pumpEmptyThread(
      tester,
      resolve: (_) async => throw StateError('the relationship read failed'),
    );

    expect(find.text('Say hello 👋'), findsOneWidget);
    expect(find.text('You are friends on YO Voice'), findsNothing);
    expect(find.textContaining('relationship read failed'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _EmptyThreadService extends MessageService {
  _EmptyThreadService(FakeFirebaseFirestore firestore, MockFirebaseAuth auth)
    : super(firestore: firestore, auth: auth);

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
  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) async {}
}
