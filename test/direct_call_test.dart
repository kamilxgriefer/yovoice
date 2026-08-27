import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/calls/data/models/direct_call.dart';
import 'package:yovoice/features/calls/data/models/voice_connection_info.dart';
import 'package:yovoice/features/calls/data/services/direct_call_service.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/calls/presentation/screens/direct_call_screen.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

void main() {
  late PublicIdentityRepository originalIdentityRepository;

  setUp(() {
    originalIdentityRepository = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'me', displayName: 'Me'),
      ),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentityRepository;
  });

  testWidgets('incoming call can be answered, muted and ended', (tester) async {
    final gateway = _FakeDirectCallGateway(
      _call(status: DirectCallStatus.ringing),
    );
    final voice = _FakeVoiceCallService();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: DirectCallScreen(
          callId: 'call-1',
          callService: gateway,
          voiceService: voice,
          currentUserId: 'callee',
          participantName: 'Callee',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Incoming voice call'), findsOneWidget);
    expect(find.text('Answer'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);

    await tester.tap(find.byTooltip('Answer'));
    await tester.pump();
    await tester.pump();

    expect(gateway.acceptCalls, 1);
    expect(voice.joinCalls, 1);
    expect(voice.lastContactName, 'Caller');
    expect(find.text('Mute'), findsOneWidget);

    await tester.tap(find.byTooltip('Mute'));
    await tester.pump();
    expect(voice.isMuted, true);
    expect(find.text('Unmute'), findsOneWidget);

    await tester.tap(find.byTooltip('End'));
    await tester.pump();
    expect(gateway.endCalls, 1);
    expect(voice.disconnectCalls, 1);
  });

  testWidgets('outgoing ringing call exposes a real cancel action', (
    tester,
  ) async {
    final gateway = _FakeDirectCallGateway(
      _call(status: DirectCallStatus.ringing),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DirectCallScreen(
          callId: 'call-1',
          callService: gateway,
          voiceService: _FakeVoiceCallService(),
          currentUserId: 'caller',
          participantName: 'Caller',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Calling…'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Answer'), findsNothing);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();
    expect(gateway.cancelCalls, 1);
  });

  testWidgets('call screen stays usable at narrow 200% text and desktop', (
    tester,
  ) async {
    for (final size in const [Size(320, 680), Size(1440, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final gateway = _FakeDirectCallGateway(
        _call(status: DirectCallStatus.ringing),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(2),
            ),
            child: DirectCallScreen(
              callId: 'call-1',
              callService: gateway,
              voiceService: _FakeVoiceCallService(),
              currentUserId: 'callee',
              participantName: 'Callee',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'surface $size');
      expect(find.text('Answer'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
    }
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });

  testWidgets('chat phone button starts signaling and opens ringing screen', (
    tester,
  ) async {
    final calls = _FakeDirectCallGateway(
      _call(status: DirectCallStatus.ringing),
    );
    final messages = _StubMessageService();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'caller', displayName: 'Caller'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: ChatScreen(
          conversationId: 'conversation-1',
          otherUserId: 'callee',
          otherDisplayName: 'Callee',
          otherEmail: '',
          otherPhotoUrl: '',
          messageService: messages,
          directCallService: calls,
          auth: auth,
        ),
      ),
    );
    messages.emit(const []);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Start voice call'));
    await tester.pump();
    await tester.pump();

    expect(calls.startCalls, 1);
    expect(calls.lastCalleeId, 'callee');
    expect(calls.lastConversationId, 'conversation-1');
    expect(find.text('Calling…'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });
}

DirectCall _call({required DirectCallStatus status}) {
  return DirectCall(
    id: 'call-1',
    callerId: 'caller',
    calleeId: 'callee',
    caller: const DirectCallIdentity(
      userId: 'caller',
      displayName: 'Caller',
      photoUrl: null,
    ),
    callee: const DirectCallIdentity(
      userId: 'callee',
      displayName: 'Callee',
      photoUrl: null,
    ),
    status: status,
    createdAt: DateTime(2026, 8, 27, 20),
    expiresAt: DateTime(2026, 8, 27, 20, 1),
    answeredAt: status == DirectCallStatus.active
        ? DateTime.now().subtract(const Duration(seconds: 5))
        : null,
    conversationId: 'conversation-1',
  );
}

class _FakeDirectCallGateway implements DirectCallGateway {
  _FakeDirectCallGateway(this.current);

  DirectCall current;
  final StreamController<DirectCall> _changes =
      StreamController<DirectCall>.broadcast();
  int startCalls = 0;
  int acceptCalls = 0;
  int declineCalls = 0;
  int cancelCalls = 0;
  int endCalls = 0;
  String? lastCalleeId;
  String? lastConversationId;

  void _emit(DirectCallStatus status) {
    current = _call(status: status);
    _changes.add(current);
  }

  @override
  Stream<DirectCall> watchCall(String callId) async* {
    yield current;
    yield* _changes.stream;
  }

  @override
  Future<DirectCall?> getCall(String callId) async => current;

  @override
  Stream<List<IncomingDirectCallSignal>> watchIncomingCalls() =>
      const Stream.empty();

  @override
  Future<String> startCall({
    required String calleeId,
    required String conversationId,
  }) async {
    startCalls++;
    lastCalleeId = calleeId;
    lastConversationId = conversationId;
    return current.id;
  }

  @override
  Future<void> accept(String callId) async {
    acceptCalls++;
    _emit(DirectCallStatus.active);
  }

  @override
  Future<void> decline(String callId) async {
    declineCalls++;
    _emit(DirectCallStatus.declined);
  }

  @override
  Future<void> cancel(String callId) async {
    cancelCalls++;
    _emit(DirectCallStatus.cancelled);
  }

  @override
  Future<void> end(String callId) async {
    endCalls++;
    _emit(DirectCallStatus.ended);
  }

  @override
  Future<VoiceConnectionInfo> createJoinToken(String callId) {
    throw UnimplementedError();
  }
}

class _FakeVoiceCallService extends VoiceCallService {
  _FakeVoiceCallService() : super.forTesting();

  VoiceCallStatus _testStatus = VoiceCallStatus.disconnected;
  String? _testDirectCallId;
  bool _testMuted = false;
  int joinCalls = 0;
  int disconnectCalls = 0;
  String? lastContactName;

  @override
  VoiceCallStatus get status => _testStatus;

  @override
  String? get directCallId => _testDirectCallId;

  @override
  bool get isDirectCall => _testDirectCallId != null;

  @override
  bool get isConnected => _testStatus == VoiceCallStatus.connected;

  @override
  bool get isMuted => _testMuted;

  @override
  bool get muteChangeInProgress => false;

  @override
  String? get errorMessage => null;

  @override
  Future<void> joinDirectCall({
    required String callId,
    required String contactName,
    required String participantName,
    bool playSound = true,
  }) async {
    joinCalls++;
    lastContactName = contactName;
    _testDirectCallId = callId;
    _testStatus = VoiceCallStatus.connected;
    notifyListeners();
  }

  @override
  Future<void> toggleMute() async {
    _testMuted = !_testMuted;
    notifyListeners();
  }

  @override
  Future<void> disconnect({bool playSound = true}) async {
    disconnectCalls++;
    _testStatus = VoiceCallStatus.disconnected;
    _testDirectCallId = null;
    notifyListeners();
  }
}

class _StubMessageService extends MessageService {
  _StubMessageService()
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'caller'),
        ),
      );

  final StreamController<List<Message>> _messages =
      StreamController<List<Message>>.broadcast();

  void emit(List<Message> messages) => _messages.add(messages);

  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      _messages.stream;

  @override
  Stream<bool> watchTyping({
    required String conversationId,
    required String otherUserId,
  }) => const Stream<bool>.empty();

  @override
  Stream<ChatPresence> watchUserPresence(String userId) =>
      Stream<ChatPresence>.value(
        const ChatPresence(isOnline: true, lastSeen: null),
      );

  @override
  Future<void> markConversationRead(String conversationId) async {}

  @override
  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) async {}
}
