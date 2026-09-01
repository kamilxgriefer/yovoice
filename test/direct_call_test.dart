import 'dart:async';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/calls/data/models/direct_call.dart';
import 'package:yovoice/features/calls/data/models/voice_connection_info.dart';
import 'package:yovoice/features/calls/data/services/direct_call_service.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/calls/presentation/direct_call_route_registry.dart';
import 'package:yovoice/features/calls/presentation/widgets/direct_call_coordinator.dart';
import 'package:yovoice/core/audio/ui_sound_service.dart';
import 'package:yovoice/features/calls/presentation/screens/direct_call_screen.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/active_conversation_registry.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

void main() {
  late PublicIdentityRepository originalIdentityRepository;

  setUp(() {
    ActiveConversationRegistry.instance.clear();
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
    ActiveConversationRegistry.instance.clear();
    PublicIdentityRepository.instance = originalIdentityRepository;
  });

  test(
    'direct-call media type is server-compatible and defaults to audio',
    () async {
      final firestore = FakeFirebaseFirestore();
      final legacy = firestore.collection('directCalls').doc('legacy');
      final video = firestore.collection('directCalls').doc('video');
      final base = <String, Object?>{
        'callerId': 'caller',
        'calleeId': 'callee',
        'caller': <String, Object?>{
          'userId': 'caller',
          'displayName': 'Caller',
        },
        'callee': <String, Object?>{
          'userId': 'callee',
          'displayName': 'Callee',
        },
        'status': 'ringing',
      };
      await legacy.set(base);
      await video.set(<String, Object?>{...base, 'mediaType': 'video'});

      expect(
        DirectCall.fromFirestore(await legacy.get()).mediaType,
        DirectCallMediaType.audio,
      );
      expect(
        DirectCall.fromFirestore(await video.get()).mediaType,
        DirectCallMediaType.video,
      );
    },
  );

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

  testWidgets('active audio call starts private and exposes output routing', (
    tester,
  ) async {
    final gateway = _FakeDirectCallGateway(
      _call(status: DirectCallStatus.active),
    );
    final voice = _FakeVoiceCallService(supportsSpeakerSwitch: true);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: DirectCallScreen(
          callId: 'call-1',
          callService: gateway,
          voiceService: voice,
          currentUserId: 'caller',
          participantName: 'Caller',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(voice.isSpeakerPreferred, isFalse);
    expect(find.byTooltip('Speaker'), findsOneWidget);
    await tester.tap(find.byTooltip('Speaker'));
    await tester.pump();
    expect(voice.isSpeakerPreferred, isTrue);
    expect(find.byTooltip('Earpiece'), findsOneWidget);
  });

  testWidgets('End stops local media before a slow backend transition', (
    tester,
  ) async {
    final events = <String>[];
    final gateway = _FakeDirectCallGateway(
      _call(status: DirectCallStatus.active),
      events: events,
    );
    final endGate = Completer<void>();
    gateway.endGate = endGate;
    final voice = _FakeVoiceCallService(events: events);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: DirectCallScreen(
          callId: 'call-1',
          callService: gateway,
          voiceService: voice,
          currentUserId: 'caller',
          participantName: 'Caller',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(voice.isConnected, isTrue);

    await tester.tap(find.byTooltip('End'));
    await tester.pump();

    expect(events.take(2).toList(), <String>['disconnect', 'end']);
    expect(voice.isConnected, isFalse);
    expect(gateway.endCalls, 1);

    endGate.complete();
    await tester.pump();
    await tester.pump();
  });

  testWidgets(
    'incoming video call is explicit and enables camera after answer',
    (tester) async {
      final gateway = _FakeDirectCallGateway(
        _call(
          status: DirectCallStatus.ringing,
          mediaType: DirectCallMediaType.video,
        ),
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

      expect(find.text('Incoming video call'), findsOneWidget);
      expect(find.byIcon(Icons.videocam_rounded), findsOneWidget);

      await tester.tap(find.byTooltip('Answer video'));
      await tester.pump();
      await tester.pump();

      expect(gateway.acceptCalls, 1);
      expect(voice.lastEnableCamera, isTrue);
      expect(
        find.byKey(const ValueKey('active-video-call-stage')),
        findsOneWidget,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(voice.pauseCameraCalls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    },
  );

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

  testWidgets('active video call fits an iPhone landscape surface', (
    tester,
  ) async {
    const size = Size(844, 390);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final gateway = _FakeDirectCallGateway(
      _call(
        status: DirectCallStatus.active,
        mediaType: DirectCallMediaType.video,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: MediaQuery(
          data: const MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(2),
          ),
          child: DirectCallScreen(
            callId: 'call-1',
            callService: gateway,
            voiceService: _FakeVoiceCallService(),
            currentUserId: 'caller',
            participantName: 'Caller',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('active-video-call-stage')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('video controls announce actual media state and next action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final gateway = _FakeDirectCallGateway(
      _call(
        status: DirectCallStatus.active,
        mediaType: DirectCallMediaType.video,
      ),
    );
    final voice = _FakeVoiceCallService(supportsSpeakerSwitch: true);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: DirectCallScreen(
          callId: 'call-1',
          callService: gateway,
          voiceService: voice,
          currentUserId: 'caller',
          participantName: 'Caller',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    ui.SemanticsFlags flags(String label) => tester
        .getSemantics(find.bySemanticsLabel(label))
        .getSemanticsData()
        .flagsCollection;
    String hint(String label) => tester
        .getSemantics(find.bySemanticsLabel(label))
        .getSemanticsData()
        .hint;

    expect(flags('Microphone').isToggled, ui.Tristate.isTrue);
    expect(hint('Microphone'), 'Double tap to mute');
    expect(flags('Camera').isToggled, ui.Tristate.isTrue);
    expect(hint('Camera'), 'Double tap to turn camera off');
    expect(flags('Speakerphone').isToggled, ui.Tristate.isTrue);
    expect(hint('Speakerphone'), 'Double tap to use earpiece');

    await tester.tap(find.byTooltip('Mute'));
    await tester.tap(find.byTooltip('Camera off'));
    await tester.tap(find.byTooltip('Use earpiece'));
    await tester.pump();

    expect(flags('Microphone').isToggled, ui.Tristate.isFalse);
    expect(hint('Microphone'), 'Double tap to unmute');
    expect(flags('Camera').isToggled, ui.Tristate.isFalse);
    expect(hint('Camera'), 'Double tap to turn camera on');
    expect(flags('Speakerphone').isToggled, ui.Tristate.isFalse);
    expect(hint('Speakerphone'), 'Double tap to use speaker');
    semantics.dispose();
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
    expect(calls.lastMediaType, DirectCallMediaType.audio);
    expect(find.text('Calling…'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('chat video button requests a video call', (tester) async {
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

    await tester.tap(find.byTooltip('Start video call'));
    await tester.pump();
    await tester.pump();

    expect(calls.startCalls, 1);
    expect(calls.lastMediaType, DirectCallMediaType.video);
    expect(find.text('Video calling…'), findsOneWidget);
  });

  testWidgets('a fullscreen direct call makes the covered chat notification '
      'eligible, then restores suppression after return', (tester) async {
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
    expect(
      ActiveConversationRegistry.instance.contains('conversation-1'),
      true,
    );

    await tester.tap(find.byTooltip('Start voice call'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Calling…'), findsOneWidget);
    expect(
      shouldSuppressForegroundNotification(
        type: NotificationType.directMessage,
        targetId: 'conversation-1',
        activeConversations: ActiveConversationRegistry.instance,
      ),
      false,
      reason: 'the call route covers the chat, so its DM must still alert',
    );

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Calling…'), findsNothing);
    expect(
      ActiveConversationRegistry.instance.contains('conversation-1'),
      true,
    );
  });

  testWidgets('incoming-call listener resubscribes after a stream failure', (
    tester,
  ) async {
    final gateway = _RetryingIncomingGateway();
    addTearDown(gateway.dispose);
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'callee', displayName: 'Callee'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DirectCallCoordinator(
          callService: gateway,
          auth: auth,
          voiceService: _FakeVoiceCallService(),
          incomingRetryDelay: (_) => Duration.zero,
          child: const Scaffold(body: Text('home')),
        ),
      ),
    );
    await tester.pump();
    expect(gateway.watchCount, 1);

    gateway.emitError(StateError('listener interrupted'));
    await tester.pump();
    await tester.pump(Duration.zero);

    expect(gateway.watchCount, 2);
    expect(find.text('home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an old-account signal cannot navigate after auth changes', (
    tester,
  ) async {
    final gateway = _RetryingIncomingGateway();
    addTearDown(gateway.dispose);
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'old-callee', displayName: 'Old account'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DirectCallCoordinator(
          callService: gateway,
          auth: auth,
          voiceService: _FakeVoiceCallService(),
          child: const Scaffold(body: Text('home')),
        ),
      ),
    );
    await tester.pump();

    gateway.emitSignal(
      IncomingDirectCallSignal(
        callId: 'old-account-call',
        callerId: 'caller',
        callerName: 'Caller',
        callerPhotoUrl: null,
        status: DirectCallStatus.ringing,
        expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      ),
    );
    await auth.signOut();
    await tester.pump();
    await tester.pump();

    expect(find.text('home'), findsOneWidget);
    expect(find.text('Incoming voice call'), findsNothing);
    expect(DirectCallRouteRegistry.claim('old-account-call'), isTrue);
    DirectCallRouteRegistry.release('old-account-call');
  });

  testWidgets('an active alert claim expires without another claim', (
    tester,
  ) async {
    DirectCallAlertRegistry.configureForTesting(
      clock: DateTime.now,
      activeClaimTimeout: const Duration(seconds: 30),
    );
    addTearDown(DirectCallAlertRegistry.resetTestingConfiguration);
    final owner = DirectCallAlertRegistry.claim(
      'hung-alert',
      DirectCallAlertOwner.coordinator,
    );
    final waiter = DirectCallAlertRegistry.claim(
      'hung-alert',
      DirectCallAlertOwner.push,
    );
    expect(owner.ownsAlert, isTrue);
    expect(waiter.ownsAlert, isFalse);
    bool? result;
    unawaited(waiter.result.then((value) => result = value));

    await tester.pump(const Duration(seconds: 29));
    expect(result, isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(result, isFalse);
    expect(DirectCallAlertRegistry.debugEntryCount, 0);

    final fallback = DirectCallAlertRegistry.claim(
      'hung-alert',
      DirectCallAlertOwner.push,
    );
    expect(fallback.ownsAlert, isTrue);
    DirectCallAlertRegistry.complete(fallback, presented: true);
  });

  testWidgets('an old alert timer cannot evict a replacement token', (
    tester,
  ) async {
    DirectCallAlertRegistry.configureForTesting(
      clock: DateTime.now,
      activeClaimTimeout: const Duration(seconds: 5),
    );
    addTearDown(DirectCallAlertRegistry.resetTestingConfiguration);
    final oldOwner = DirectCallAlertRegistry.claim(
      'reused-alert',
      DirectCallAlertOwner.coordinator,
    );
    await tester.pump(const Duration(seconds: 4));
    DirectCallAlertRegistry.release('reused-alert');
    expect(await oldOwner.result, isFalse);

    final replacement = DirectCallAlertRegistry.claim(
      'reused-alert',
      DirectCallAlertOwner.push,
    );
    bool? replacementResult;
    unawaited(replacement.result.then((value) => replacementResult = value));
    await tester.pump(const Duration(seconds: 1));
    expect(replacementResult, isNull);
    expect(DirectCallAlertRegistry.debugEntryCount, 1);

    await tester.pump(const Duration(seconds: 4));
    expect(replacementResult, isFalse);
    expect(DirectCallAlertRegistry.debugEntryCount, 0);
  });

  testWidgets('silent coordinator releases call alert for FCM fallback', (
    tester,
  ) async {
    final gateway = _RetryingIncomingGateway();
    addTearDown(gateway.dispose);
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'callee', displayName: 'Callee'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DirectCallCoordinator(
          callService: gateway,
          auth: auth,
          voiceService: _FakeVoiceCallService(),
          soundService: UiSoundService(enabled: () => false),
          child: const Scaffold(body: Text('home')),
        ),
      ),
    );
    await tester.pump();

    gateway.emitSignal(
      IncomingDirectCallSignal(
        callId: 'silent-call',
        callerId: 'caller',
        callerName: 'Caller',
        callerPhotoUrl: null,
        status: DirectCallStatus.ringing,
        expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      ),
    );
    await tester.pump();
    await tester.pump();

    final fallback = DirectCallAlertRegistry.claim(
      'silent-call',
      DirectCallAlertOwner.push,
    );
    expect(fallback.ownsAlert, isTrue);
    DirectCallAlertRegistry.complete(fallback, presented: true);
  });
}

DirectCall _call({
  required DirectCallStatus status,
  DirectCallMediaType mediaType = DirectCallMediaType.audio,
}) {
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
    mediaType: mediaType,
  );
}

class _FakeDirectCallGateway implements DirectCallGateway {
  _FakeDirectCallGateway(this.current, {this.events});

  DirectCall current;
  final List<String>? events;
  final StreamController<DirectCall> _changes =
      StreamController<DirectCall>.broadcast();
  int startCalls = 0;
  int acceptCalls = 0;
  int declineCalls = 0;
  int cancelCalls = 0;
  int endCalls = 0;
  String? lastCalleeId;
  String? lastConversationId;
  DirectCallMediaType? lastMediaType;
  Completer<void>? endGate;

  void _emit(DirectCallStatus status) {
    current = _call(status: status, mediaType: current.mediaType);
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
    DirectCallMediaType mediaType = DirectCallMediaType.audio,
  }) async {
    startCalls++;
    lastCalleeId = calleeId;
    lastConversationId = conversationId;
    lastMediaType = mediaType;
    current = _call(status: DirectCallStatus.ringing, mediaType: mediaType);
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
    events?.add('end');
    await endGate?.future;
    _emit(DirectCallStatus.ended);
  }

  @override
  Future<VoiceConnectionInfo> createJoinToken(String callId) {
    throw UnimplementedError();
  }
}

class _RetryingIncomingGateway implements DirectCallGateway {
  final StreamController<List<IncomingDirectCallSignal>> _incoming =
      StreamController<List<IncomingDirectCallSignal>>.broadcast();
  int watchCount = 0;

  void emitError(Object error) => _incoming.addError(error);

  void emitSignal(IncomingDirectCallSignal signal) => _incoming.add([signal]);

  Future<void> dispose() => _incoming.close();

  @override
  Stream<List<IncomingDirectCallSignal>> watchIncomingCalls() {
    watchCount++;
    return _incoming.stream;
  }

  @override
  Future<DirectCall?> getCall(String callId) async => null;

  @override
  Stream<DirectCall> watchCall(String callId) => const Stream.empty();

  @override
  Future<String> startCall({
    required String calleeId,
    required String conversationId,
    DirectCallMediaType mediaType = DirectCallMediaType.audio,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> accept(String callId) async {}

  @override
  Future<void> decline(String callId) async {}

  @override
  Future<void> cancel(String callId) async {}

  @override
  Future<void> end(String callId) async {}

  @override
  Future<VoiceConnectionInfo> createJoinToken(String callId) {
    throw UnimplementedError();
  }
}

class _FakeVoiceCallService extends VoiceCallService {
  _FakeVoiceCallService({this.events, this.supportsSpeakerSwitch = false})
    : super.forTesting();

  final List<String>? events;
  final bool supportsSpeakerSwitch;
  VoiceCallStatus _testStatus = VoiceCallStatus.disconnected;
  String? _testDirectCallId;
  bool _testMuted = false;
  bool _testVideoCall = false;
  bool _testCameraEnabled = false;
  bool _testSpeakerPreferred = false;
  int joinCalls = 0;
  int disconnectCalls = 0;
  int pauseCameraCalls = 0;
  String? lastContactName;
  bool? lastEnableCamera;

  @override
  VoiceCallStatus get status => _testStatus;

  @override
  String? get directCallId => _testDirectCallId;

  @override
  bool get isDirectCall => _testDirectCallId != null;

  @override
  bool get isVideoCall => _testVideoCall;

  @override
  bool get isCameraEnabled => _testCameraEnabled;

  @override
  bool get cameraChangeInProgress => false;

  @override
  String? get cameraIssue => null;

  @override
  bool get isConnected => _testStatus == VoiceCallStatus.connected;

  @override
  bool get isMuted => _testMuted;

  @override
  bool get muteChangeInProgress => false;

  @override
  bool get canSwitchSpeakerphone => supportsSpeakerSwitch;

  @override
  bool get isSpeakerPreferred => _testSpeakerPreferred;

  @override
  bool get speakerChangeInProgress => false;

  @override
  String? get errorMessage => null;

  @override
  Future<void> joinDirectCall({
    required String callId,
    required String contactName,
    required String participantName,
    bool enableCamera = false,
    bool playSound = true,
  }) async {
    joinCalls++;
    lastContactName = contactName;
    lastEnableCamera = enableCamera;
    _testVideoCall = enableCamera;
    _testCameraEnabled = enableCamera;
    _testSpeakerPreferred = enableCamera;
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
  Future<void> toggleSpeaker() async {
    _testSpeakerPreferred = !_testSpeakerPreferred;
    notifyListeners();
  }

  @override
  Future<void> toggleCamera() async {
    _testCameraEnabled = !_testCameraEnabled;
    notifyListeners();
  }

  @override
  Future<void> pauseCameraForBackground() async {
    pauseCameraCalls++;
  }

  @override
  Future<void> disconnect({bool playSound = true}) async {
    disconnectCalls++;
    events?.add('disconnect');
    _testStatus = VoiceCallStatus.disconnected;
    _testDirectCallId = null;
    _testVideoCall = false;
    _testCameraEnabled = false;
    _testSpeakerPreferred = false;
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
