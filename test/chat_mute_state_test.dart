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

/// Mute was a local boolean that started at `false` on every open, so a
/// thread the account had already muted offered "Mute" — and the tap
/// UN-muted it. `Conversation.mutedBy` has always carried the truth; the
/// screen simply never read the document it belongs to.
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

  Future<void> seedConversation({required List<String> mutedBy}) =>
      firestore.collection('conversations').doc(conversationId).set({
        'participantIds': <String>[currentUserId, otherUserId],
        'mutedBy': mutedBy,
        'archivedBy': <String>[],
      });

  Widget host(
    _MuteMessageService service, {
    Locale locale = const Locale('en'),
  }) => MaterialApp(
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
      conversationId: conversationId,
      otherUserId: otherUserId,
      otherDisplayName: 'Them',
      otherEmail: '',
      otherPhotoUrl: '',
      messageService: service,
      auth: auth,
      profileService: ProfileService(firestore: firestore, auth: auth),
      relationshipStatusResolver: (_) =>
          Future<FriendRelationshipStatus>.value(FriendRelationshipStatus.none),
    ),
  );

  testWidgets('an already-muted thread offers Unmute, in EN and PL', (
    tester,
  ) async {
    await seedConversation(mutedBy: const <String>[currentUserId]);
    final service = _MuteMessageService(firestore, auth);

    for (final testCase in const <({Locale locale, String label})>[
      (locale: Locale('en'), label: 'Unmute'),
      (locale: Locale('pl'), label: 'Włącz powiadomienia'),
    ]) {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpWidget(host(service, locale: testCase.locale));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byTooltip(
          testCase.locale.languageCode == 'pl'
              ? 'Opcje rozmowy'
              : 'Conversation options',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(testCase.label),
        findsOneWidget,
        reason: 'the document says this account muted the thread',
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a thread nobody muted still offers Mute', (tester) async {
    await seedConversation(mutedBy: const <String>[otherUserId]);
    final service = _MuteMessageService(firestore, auth);
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Conversation options'));
    await tester.pumpAndSettle();

    expect(
      find.text('Mute'),
      findsOneWidget,
      reason: 'the OTHER participant muting says nothing about this account',
    );
  });

  testWidgets('a mute the server refuses does not stick', (tester) async {
    await seedConversation(mutedBy: const <String>[]);
    final service = _MuteMessageService(firestore, auth, refuseMute: true);
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Conversation options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mute'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Conversation options'));
    await tester.pumpAndSettle();
    expect(
      find.text('Mute'),
      findsOneWidget,
      reason: 'an optimistic toggle must roll back when the write fails',
    );
  });
}

/// The real service over a fake Firestore: `watchConversation` is exercised
/// for real, which is the whole point.
class _MuteMessageService extends MessageService {
  _MuteMessageService(
    FakeFirebaseFirestore firestore,
    MockFirebaseAuth auth, {
    this.refuseMute = false,
  }) : super(firestore: firestore, auth: auth);

  final bool refuseMute;

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

  @override
  Future<void> setConversationMuted({
    required String conversationId,
    required bool muted,
  }) async {
    if (refuseMute) throw StateError('the server refused');
    return super.setConversationMuted(
      conversationId: conversationId,
      muted: muted,
    );
  }
}
