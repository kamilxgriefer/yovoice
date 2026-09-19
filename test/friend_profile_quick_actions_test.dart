import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/audio/call_tone_service.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/calls/data/models/direct_call.dart';
import 'package:yovoice/features/calls/data/services/direct_call_service.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/calls/presentation/screens/direct_call_screen.dart';
import 'package:yovoice/features/creator/data/services/creator_pinned_post_service.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/friends/presentation/screens/friend_profile_screen.dart';
import 'package:yovoice/features/messages/data/services/active_conversation_registry.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/moderation/data/services/report_service.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/permissions/data/permission_readiness_service.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_header.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

const _me = 'current-user';
const _friendId = 'friend-user';
const _name = 'Ola Nowak';

class _EmptyGraph implements SocialGraphService {
  @override
  Future<MutualFriendsSummary> getMutualFriends(String targetUserId) async =>
      MutualFriendsSummary.empty;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingMessageService extends MessageService {
  _RecordingMessageService({
    required super.firestore,
    required super.auth,
    required super.notificationService,
    required this.events,
  });

  final List<String> events;
  Object? openError;
  int opens = 0;

  @override
  Future<String> openOrCreateConversation({
    required String otherUserId,
    required String otherDisplayName,
    required String otherEmail,
    required String otherPhotoUrl,
  }) async {
    opens++;
    events.add('open:$otherUserId');
    if (openError case final error?) throw error;
    return 'conversation-1';
  }
}

class _FakeVoice extends VoiceCallService {
  _FakeVoice({
    required this.events,
    this.cameraGranted = true,
    this.busy = false,
  }) : super.forTesting();

  final List<String> events;
  final bool cameraGranted;
  final bool busy;
  Completer<void>? permissionGate;

  @override
  VoiceCallStatus get status =>
      busy ? VoiceCallStatus.connected : VoiceCallStatus.disconnected;

  @override
  Future<PermissionReadinessSnapshot> prepareMediaPermissionsFromUserGesture({
    bool includeCamera = false,
  }) async {
    events.add('permissions:$includeCamera');
    await permissionGate?.future;
    return PermissionReadinessSnapshot(<AppPermissionKind, AppPermissionAccess>{
      AppPermissionKind.microphone: AppPermissionAccess.granted,
      if (includeCamera)
        AppPermissionKind.camera: cameraGranted
            ? AppPermissionAccess.granted
            : AppPermissionAccess.denied,
    });
  }
}

DirectCall _ringing(DirectCallMediaType mediaType) => DirectCall(
  id: 'call-1',
  callerId: _me,
  calleeId: _friendId,
  caller: const DirectCallIdentity(
    userId: _me,
    displayName: 'Me',
    photoUrl: null,
  ),
  callee: const DirectCallIdentity(
    userId: _friendId,
    displayName: _name,
    photoUrl: null,
  ),
  status: DirectCallStatus.ringing,
  createdAt: DateTime(2026, 9, 19, 20),
  expiresAt: DateTime(2026, 9, 19, 20, 1),
  answeredAt: null,
  conversationId: 'conversation-1',
  mediaType: mediaType,
);

class _FakeCalls implements DirectCallGateway {
  _FakeCalls({required this.events, this.startErrors = const []});

  final List<String> events;
  final List<Object> startErrors;
  int starts = 0;
  String? lastConversationId;
  DirectCallMediaType? lastMediaType;

  @override
  Future<String> startCall({
    required String calleeId,
    required String conversationId,
    DirectCallMediaType mediaType = DirectCallMediaType.audio,
  }) async {
    starts++;
    events.add('start:${mediaType.name}');
    lastConversationId = conversationId;
    lastMediaType = mediaType;
    if (starts <= startErrors.length) throw startErrors[starts - 1];
    return 'call-1';
  }

  @override
  Stream<DirectCall> watchCall(String callId) =>
      Stream<DirectCall>.value(_ringing(lastMediaType!));

  @override
  Future<DirectCall?> getCall(String callId) async => _ringing(lastMediaType!);

  @override
  Future<void> cancel(String callId) async {}

  @override
  Future<void> end(String callId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeReports extends ReportService {
  _FakeReports()
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      );

  final calls = <(ReportTargetType, String, String, String?)>[];

  @override
  Future<void> report({
    required ReportTargetType targetType,
    required String targetId,
    required String reportedUserId,
    required ReportReason reason,
    String note = '',
    String? contextPath,
  }) async {
    calls.add((targetType, targetId, reportedUserId, contextPath));
  }
}

class _NoServers implements ServerRepository {
  @override
  Stream<List<Server>> watchMyServers() => Stream.value(const <Server>[]);

  @override
  Stream<ServerMemberRole?> watchMyRole(String serverId) => Stream.value(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  late List<String> events;
  late CallToneService tones;
  late PublicIdentityRepository originalIdentity;

  setUp(() async {
    ActiveConversationRegistry.instance.clear();
    tones = CallToneService(enabled: () => false);
    debugCallToneServiceOverride = tones;
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
    events = <String>[];
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: _me, email: 'me@yovoice.app', displayName: 'Me'),
    );
    await db.collection('users').doc(_me).set({
      'uid': _me,
      'displayName': 'Me',
      'email': 'me@yovoice.app',
    });
    await db.collection('publicProfiles').doc(_friendId).set({
      'uid': _friendId,
      'displayName': _name,
      'username': 'ola',
      'bio': 'Poranne spacery i dobre podcasty.',
      'friendCount': 12,
      'followerCount': 40,
      'followingCount': 8,
      'accountType': 'creator',
      'premiumIdentity': true,
      'creatorAgeVerified': true,
      'creatorAudienceEnabled': true,
      'creatorAudienceVisible': true,
    });
  });

  tearDown(() {
    ActiveConversationRegistry.instance.clear();
    PublicIdentityRepository.instance = originalIdentity;
    debugCallToneServiceOverride = null;
    unawaited(tones.dispose());
  });

  Future<
    ({_RecordingMessageService messages, _FakeCalls calls, _FakeVoice voice})
  >
  pumpProfile(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1,
    bool pearl = false,
    bool polish = false,
    bool isFriend = true,
    RelationshipStatusInvoker? resolver,
    _FakeVoice? voice,
    _FakeCalls? calls,
    ReportService? reports,
    ServerRepository? servers,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final notifications = NotificationService(firestore: db, auth: auth);
    final messages = _RecordingMessageService(
      firestore: db,
      auth: auth,
      notificationService: notifications,
      events: events,
    );
    final fakeCalls = calls ?? _FakeCalls(events: events);
    final fakeVoice = voice ?? _FakeVoice(events: events);
    await tester.pumpWidget(
      MaterialApp(
        theme: pearl ? AppTheme.lightTheme : AppTheme.darkTheme,
        locale: polish ? const Locale('pl') : const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: FriendProfileScreen(
            key: ValueKey('$size-$textScale-$pearl-$isFriend'),
            friend: const FriendUser(
              id: _friendId,
              displayName: _name,
              email: '',
              photoUrl: null,
              isOnline: false,
              lastSeen: null,
            ),
            firestore: db,
            auth: auth,
            friendService: FriendService(
              firestore: db,
              auth: auth,
              notificationService: notifications,
            ),
            messageService: messages,
            profileService: ProfileService(firestore: db, auth: auth),
            followService: FollowService(firestore: db, auth: auth),
            socialGraphService: _EmptyGraph(),
            creatorPinnedPostService: CreatorPinnedPostService(
              firestore: db,
              auth: auth,
            ),
            isFriend: isFriend,
            relationshipStatusResolver: resolver,
            directCallService: fakeCalls,
            voiceCallService: fakeVoice,
            reportService: reports,
            serverRepository: servers,
          ),
        ),
      ),
    );
    for (var pump = 0; pump < 8; pump++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    return (messages: messages, calls: fakeCalls, voice: fakeVoice);
  }

  Finder key(String value) => find.byKey(ValueKey(value));

  // The profile keeps an indeterminate loader alive (pinned Moment), so a
  // bounded pump replaces pumpAndSettle.
  Future<void> settle(WidgetTester tester) async {
    for (var pump = 0; pump < 10; pump++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  bool enabled(WidgetTester tester, String value) =>
      tester.widget<ButtonStyleButton>(key(value)).onPressed != null;

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  group('calls from the profile', () {
    testWidgets('a friend gets all four slots and Zadzwoń runs permissions, '
        'then opens the DM, then starts an audio call', (tester) async {
      final fakes = await pumpProfile(tester);
      for (final slot in const [
        'friend-profile-call-button',
        'friend-profile-video-button',
        'friend-profile-message-button',
      ]) {
        expect(key(slot), findsOneWidget, reason: slot);
        expect(enabled(tester, slot), isTrue, reason: slot);
      }
      expect(key('friend-profile-more-button'), findsOneWidget);
      expect(key('friend-profile-call-unavailable'), findsNothing);

      await tester.tap(key('friend-profile-call-button'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(events, ['permissions:false', 'open:$_friendId', 'start:audio']);
      expect(fakes.calls.lastConversationId, 'conversation-1');
      expect(find.byType(DirectCallScreen), findsOneWidget);
      await cleanUp(tester);
    });

    testWidgets('Wideo asks for the camera and starts a video call', (
      tester,
    ) async {
      final fakes = await pumpProfile(tester);
      await tester.tap(key('friend-profile-video-button'));
      await tester.pump();
      await tester.pump();
      expect(events.first, 'permissions:true');
      expect(fakes.calls.lastMediaType, DirectCallMediaType.video);
      await cleanUp(tester);
    });

    testWidgets('a denied camera falls back to audio with the snackbar', (
      tester,
    ) async {
      final fakes = await pumpProfile(
        tester,
        voice: _FakeVoice(events: events, cameraGranted: false),
      );
      await tester.tap(key('friend-profile-video-button'));
      await tester.pump();
      await tester.pump();
      expect(fakes.calls.lastMediaType, DirectCallMediaType.audio);
      expect(
        find.text('Camera access is off. The call will start with audio only.'),
        findsOneWidget,
      );
      await cleanUp(tester);
    });

    testWidgets('a live voice session refuses before any backend call', (
      tester,
    ) async {
      final fakes = await pumpProfile(
        tester,
        voice: _FakeVoice(events: events, busy: true),
      );
      await tester.tap(key('friend-profile-call-button'));
      await tester.pump();
      expect(
        find.text('Leave your current voice session before starting a call.'),
        findsOneWidget,
      );
      expect(fakes.messages.opens, 0);
      expect(fakes.calls.starts, 0);
    });

    testWidgets('single flight: a double tap starts one call and Message is '
        'disabled while it starts, with a Connecting label', (tester) async {
      final voice = _FakeVoice(events: events)..permissionGate = Completer();
      final fakes = await pumpProfile(tester, voice: voice);
      await tester.tap(key('friend-profile-call-button'));
      await tester.pump();
      await tester.tap(key('friend-profile-call-button'), warnIfMissed: false);
      await tester.pump();
      expect(enabled(tester, 'friend-profile-message-button'), isFalse);
      expect(enabled(tester, 'friend-profile-video-button'), isFalse);
      expect(find.text('Connecting…'), findsOneWidget);
      voice.permissionGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(fakes.calls.starts, 1);
      expect(fakes.messages.opens, 1);
      await cleanUp(tester);
    });

    testWidgets('an openDirectConversation refusal names the profile case '
        'in English and Polish', (tester) async {
      for (final polish in const [false, true]) {
        events.clear();
        final fakes = await pumpProfile(tester, polish: polish);
        fakes.messages.openError = FirebaseFunctionsException(
          message: 'denied',
          code: 'permission-denied',
        );
        await tester.tap(key('friend-profile-call-button'));
        await tester.pump();
        await tester.pump();
        expect(
          find.text(
            polish
                ? 'Nie możesz teraz zadzwonić do tej osoby z profilu.'
                : "You can't call this person from their profile right now.",
          ),
          findsOneWidget,
        );
        expect(fakes.calls.starts, 0);
        await cleanUp(tester);
      }
    });

    testWidgets('shared chat copy: friendship, email verification and the '
        'video capability retry', (tester) async {
      final calls = _FakeCalls(
        events: events,
        startErrors: [
          const DirectCallFriendshipException(),
          const DirectCallEmailVerificationException(),
          const DirectVideoCompatibilityException(message: 'old client'),
        ],
      );
      await pumpProfile(tester, calls: calls);
      await tester.tap(key('friend-profile-call-button'));
      await tester.pump();
      await tester.pump();
      expect(
        find.textContaining('Calls are temporarily unavailable'),
        findsOneWidget,
      );
      await tester.tap(key('friend-profile-call-button'));
      await tester.pump();
      await tester.pump();
      expect(
        find.textContaining('Verify your email before calling'),
        findsOneWidget,
      );
      await tester.tap(key('friend-profile-video-button'));
      await tester.pump();
      await tester.pump();
      await settle(tester);
      expect(find.text('Start audio'), findsOneWidget);
      await tester.tap(find.text('Start audio'));
      await tester.pump();
      await tester.pump();
      expect(calls.starts, 4);
      expect(calls.lastMediaType, DirectCallMediaType.audio);
      await cleanUp(tester);
    });
  });

  group('relationship gate', () {
    for (final status in const [
      FriendRelationshipStatus.none,
      FriendRelationshipStatus.requestSent,
      FriendRelationshipStatus.requestReceived,
    ]) {
      testWidgets('${status.name}: calls off with a visible reason, '
          'Message on, no Remove friend', (tester) async {
        await pumpProfile(
          tester,
          isFriend: false,
          resolver: (_) async => status,
        );
        expect(enabled(tester, 'friend-profile-call-button'), isFalse);
        expect(enabled(tester, 'friend-profile-video-button'), isFalse);
        expect(enabled(tester, 'friend-profile-message-button'), isTrue);
        expect(key('friend-profile-call-unavailable'), findsOneWidget);
        expect(find.text('Remove friend'), findsNothing);

        await tester.tap(key('friend-profile-more-button'));
        await settle(tester);
        expect(key('friend-profile-more-report'), findsOneWidget);
        expect(key('friend-profile-more-block'), findsOneWidget);
        expect(key('friend-profile-more-remove'), findsNothing);
        expect(key('friend-profile-more-voice-message'), findsNothing);
        expect(key('friend-profile-more-invite'), findsNothing);
      });
    }

    testWidgets('blocked: no quick row, no Follow, the blocked line, and '
        'More offers only Report', (tester) async {
      await pumpProfile(
        tester,
        resolver: (_) async => FriendRelationshipStatus.blocked,
      );
      expect(key('friend-profile-quick-actions'), findsNothing);
      expect(key('friend-profile-follow-button'), findsNothing);
      expect(find.text('You have blocked this user.'), findsOneWidget);
      expect(find.text('Remove friend'), findsNothing);
      await tester.tap(key('friend-profile-more-button'));
      await settle(tester);
      expect(key('friend-profile-more-report'), findsOneWidget);
      expect(key('friend-profile-more-block'), findsNothing);
      expect(key('friend-profile-more-remove'), findsNothing);
      expect(key('friend-profile-more-invite'), findsNothing);
    });

    testWidgets('a resolver error never guesses friends', (tester) async {
      await pumpProfile(
        tester,
        isFriend: false,
        resolver: (_) async => throw StateError('offline'),
      );
      expect(enabled(tester, 'friend-profile-call-button'), isFalse);
      expect(enabled(tester, 'friend-profile-video-button'), isFalse);
      expect(enabled(tester, 'friend-profile-message-button'), isTrue);
    });

    testWidgets('a friend route stays a friend when the read cannot see the '
        'friendship', (tester) async {
      await pumpProfile(
        tester,
        resolver: (_) async => FriendRelationshipStatus.none,
      );
      expect(enabled(tester, 'friend-profile-call-button'), isTrue);
      expect(key('friend-profile-call-unavailable'), findsNothing);
    });
  });

  group('Więcej', () {
    testWidgets('friends see the full sheet; Report files a user report', (
      tester,
    ) async {
      final reports = _FakeReports();
      await pumpProfile(tester, reports: reports);
      await tester.tap(key('friend-profile-more-button'));
      await settle(tester);
      for (final item in const [
        'friend-profile-more-voice-message',
        'friend-profile-more-invite',
        'friend-profile-more-report',
        'friend-profile-more-remove',
        'friend-profile-more-block',
      ]) {
        expect(key(item), findsOneWidget, reason: item);
      }
      await tester.tap(key('friend-profile-more-report'));
      await settle(tester);
      await tester.tap(key('report-reason-spam'));
      await settle(tester);
      expect(reports.calls, [
        (ReportTargetType.user, _friendId, _friendId, 'users/$_friendId'),
      ]);
    });

    testWidgets('Invite to a server opens the server picker', (tester) async {
      await pumpProfile(tester, servers: _NoServers());
      await tester.tap(key('friend-profile-more-button'));
      await settle(tester);
      await tester.tap(key('friend-profile-more-invite'));
      await settle(tester);
      expect(key('invite-person-to-server-sheet'), findsOneWidget);
      expect(key('invite-person-to-server-empty'), findsOneWidget);
    });

    testWidgets('Send a voice message opens the chat with the recorder '
        'launch action', (tester) async {
      final fakes = await pumpProfile(tester);
      await tester.tap(key('friend-profile-more-button'));
      await settle(tester);
      await tester.tap(key('friend-profile-more-voice-message'));
      await tester.pump();
      await tester.pump();
      expect(fakes.messages.opens, 1);
      final chat = tester.widget<ChatScreen>(find.byType(ChatScreen));
      expect(chat.initialAction, ChatLaunchAction.recordVoice);
      expect(chat.conversationId, 'conversation-1');
      await cleanUp(tester);
    });
  });

  group('layout matrix', () {
    const sizes = [
      Size(320, 568),
      Size(390, 844),
      Size(768, 1024),
      Size(1100, 800),
      Size(1440, 900),
      Size(2560, 1440),
    ];
    for (final pearl in const [false, true]) {
      for (final scale in const [1.0, 1.5, 2.0]) {
        testWidgets('${pearl ? 'Pearl' : 'Dark'} at ${(scale * 100).round()}% '
            'text', (tester) async {
          final semantics = tester.ensureSemantics();
          final palette = pearl ? AppPalette.light : AppPalette.dark;
          final scheme =
              (pearl ? AppTheme.lightTheme : AppTheme.darkTheme).colorScheme;
          for (final size in sizes) {
            await pumpProfile(
              tester,
              size: size,
              textScale: scale,
              pearl: pearl,
            );
            final scrollable = find
                .descendant(
                  of: key('friend-profile-content-frame'),
                  matching: find.byType(Scrollable),
                )
                .first;
            await tester.scrollUntilVisible(
              key('friend-profile-message-button'),
              120,
              scrollable: scrollable,
            );
            final group = tester.getRect(key('friend-profile-quick-actions'));
            final call = tester.getRect(key('friend-profile-call-button'));
            final message = tester.getRect(
              key('friend-profile-message-button'),
            );
            final more = tester.getRect(key('friend-profile-more-button'));
            final reason = '$size @ $scale';
            for (final slot in [call, message, more]) {
              expect(slot.height, greaterThanOrEqualTo(44), reason: reason);
              expect(slot.width, greaterThanOrEqualTo(44), reason: reason);
            }
            expect(group.width, lessThanOrEqualTo(640), reason: reason);
            if (scale * 14 >= 21) {
              // The list: one full-width row per action, stacked.
              expect(message.top, greaterThan(call.bottom), reason: reason);
              expect(call.width, closeTo(group.width, 1), reason: reason);
            } else if (group.width >= ProfileQuickActions.wideFromWidth) {
              // The toolbar: hugging buttons and a 44 px More square.
              expect(call.width, lessThan(group.width / 3), reason: reason);
              expect(more.width, closeTo(44, 4), reason: reason);
              expect(message.center.dy, closeTo(call.center.dy, 1));
            } else {
              expect(call.height, greaterThanOrEqualTo(64), reason: reason);
            }
            // Zadzwoń is the one accent; the others are hairline neutrals.
            final callStyle = tester
                .widget<ButtonStyleButton>(key('friend-profile-call-button'))
                .style!;
            expect(
              callStyle.backgroundColor!.resolve(<WidgetState>{}),
              scheme.primary,
              reason: reason,
            );
            final messageStyle = tester
                .widget<ButtonStyleButton>(key('friend-profile-message-button'))
                .style!;
            expect(
              messageStyle.backgroundColor!.resolve(<WidgetState>{}),
              palette.surface,
              reason: reason,
            );
            expect(
              messageStyle.side!.resolve(<WidgetState>{})!.color,
              palette.border,
              reason: reason,
            );
            expect(
              tester
                  .getSemantics(key('friend-profile-call-button'))
                  .getSemanticsData()
                  .hasAction(ui.SemanticsAction.tap),
              isTrue,
              reason: reason,
            );
            expect(tester.takeException(), isNull, reason: reason);
          }
          semantics.dispose();
        });
      }
    }

    testWidgets('below 300 px the compact tiles form a 2 x 2 grid', (
      tester,
    ) async {
      await pumpProfile(tester, size: const Size(280, 640));
      final scrollable = find
          .descendant(
            of: key('friend-profile-content-frame'),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        key('friend-profile-more-button'),
        120,
        scrollable: scrollable,
      );
      final call = tester.getRect(key('friend-profile-call-button'));
      final video = tester.getRect(key('friend-profile-video-button'));
      final message = tester.getRect(key('friend-profile-message-button'));
      expect(video.center.dy, closeTo(call.center.dy, 1));
      expect(message.top, greaterThan(call.bottom));
      expect(tester.takeException(), isNull);
    });
  });
}
