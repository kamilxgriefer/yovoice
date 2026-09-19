import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

class _StubMessageService extends MessageService {
  _StubMessageService(FakeFirebaseFirestore firestore, MockFirebaseAuth auth)
    : super(firestore: firestore, auth: auth);

  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      Stream<List<Message>>.value(const <Message>[]);

  @override
  Stream<bool> watchTyping({
    required String conversationId,
    required String otherUserId,
  }) => const Stream<bool>.empty();

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

void main() {
  late PublicIdentityRepository originalIdentity;
  late MockFirebaseAuth auth;
  late FakeFirebaseFirestore firestore;

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me'));
    firestore = FakeFirebaseFirestore();
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: auth,
      fetchOverride: (uids) async => {
        for (final uid in uids) uid: {'uid': uid, 'role': 'user'},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() => PublicIdentityRepository.instance = originalIdentity);

  Future<int> presenterCalls(
    WidgetTester tester,
    ChatLaunchAction action,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: ChatScreen(
          conversationId: 'conversation',
          otherUserId: 'them',
          otherDisplayName: 'Them',
          otherEmail: '',
          otherPhotoUrl: '',
          messageService: _StubMessageService(firestore, auth),
          auth: auth,
          profileService: ProfileService(firestore: firestore, auth: auth),
          relationshipStatusResolver: (_) async => throw StateError('n/a'),
          voiceRecorderPresenter: (_) async => calls++,
          initialAction: action,
        ),
      ),
    );
    for (var pump = 0; pump < 6; pump++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // A rebuild must not replay the launch action.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: ChatScreen(
          conversationId: 'conversation',
          otherUserId: 'them',
          otherDisplayName: 'Them',
          otherEmail: '',
          otherPhotoUrl: '',
          messageService: _StubMessageService(firestore, auth),
          auth: auth,
          profileService: ProfileService(firestore: firestore, auth: auth),
          relationshipStatusResolver: (_) async => throw StateError('n/a'),
          voiceRecorderPresenter: (_) async => calls++,
          initialAction: action,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final result = calls;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    return result;
  }

  testWidgets('recordVoice opens the recorder exactly once', (tester) async {
    expect(await presenterCalls(tester, ChatLaunchAction.recordVoice), 1);
  });

  testWidgets('the default launch action opens nothing', (tester) async {
    expect(await presenterCalls(tester, ChatLaunchAction.none), 0);
  });
}
