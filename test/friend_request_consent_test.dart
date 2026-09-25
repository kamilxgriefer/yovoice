import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/audio/call_tone_service.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/calls/data/services/direct_call_service.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/creator/data/services/creator_pinned_post_service.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/friends/presentation/screens/friend_profile_screen.dart';
import 'package:yovoice/features/friends/presentation/widgets/friend_request_decision.dart';
import 'package:yovoice/features/messages/data/services/active_conversation_registry.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/notifications/presentation/friend_request_banner_decision.dart';
import 'package:yovoice/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:yovoice/features/notifications/presentation/widgets/yo_top_notification_host.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';

/// Accepting a friend request is a consent decision: it never happens on one
/// ambiguous tap. Every surface that shows an incoming request offers two
/// labelled buttons, a tap on its body only opens something, "Add friend"
/// never answers someone else's request, and a stale request is described
/// honestly instead of offering buttons that fail.
const _me = 'me-uid';
const _other = 'other-uid';

typedef _Call = ({String name, Map<String, dynamic> data});

MockFirebaseAuth _auth() => MockFirebaseAuth(
  signedIn: true,
  mockUser: MockUser(uid: _me, email: 'me@yovoice.app', displayName: 'Me'),
);

Widget _localized(Widget home, {bool polish = false, ThemeData? theme}) =>
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      locale: polish ? const Locale('pl') : const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    );

/// A button found by key must be a real labelled button, not an icon.
void _expectLabelledButton(Finder button, String label) {
  expect(button, findsOneWidget);
  expect(
    find.descendant(of: button, matching: find.text(label)),
    findsOneWidget,
    reason: 'the choice must be spelled out, never icon-only',
  );
}

class _EmptyGraph implements SocialGraphService {
  @override
  Future<MutualFriendsSummary> getMutualFriends(String targetUserId) async =>
      MutualFriendsSummary.empty;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoCalls implements DirectCallGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuietVoice extends VoiceCallService {
  _QuietVoice() : super.forTesting();
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
  late List<_Call> calls;

  FriendService friendsWith(
    Future<Map<String, dynamic>> Function(
      String name,
      Map<String, dynamic> data,
    )?
    respond,
  ) => FriendService(
    firestore: db,
    auth: auth,
    mutationInvoker: (name, data) async {
      calls.add((name: name, data: data));
      if (respond != null) return respond(name, data);
      return const <String, dynamic>{'changed': true};
    },
  );

  Future<void> seedPendingRequest() => db
      .collection('users')
      .doc(_me)
      .collection('friendRequests')
      .doc(_other)
      .set(<String, dynamic>{
        'senderId': _other,
        'senderName': 'Ola',
        'senderPhotoUrl': null,
        'createdAt': Timestamp.now(),
      });

  Future<void> seedRequestRow(String id) => db
      .collection('users')
      .doc(_me)
      .collection('notifications')
      .doc(id)
      .set(<String, dynamic>{
        'type': 'friendRequest',
        'actorId': _other,
        'actorName': 'Ola',
        'actorPhotoUrl': null,
        'targetId': null,
        'targetLabel': null,
        'isRead': false,
        'createdAt': Timestamp.now(),
        'dedupeKey': id,
        'bellSuppressed': false,
      });

  setUp(() {
    db = FakeFirebaseFirestore();
    auth = _auth();
    calls = <_Call>[];
  });

  tearDown(FriendService.clearSharedReadCaches);

  group('FriendService: Add friend never answers a request', () {
    const receiver = FriendUser(
      id: _other,
      displayName: 'Ola',
      email: '',
      photoUrl: null,
      isOnline: false,
      lastSeen: null,
    );

    test('every send carries acceptIncoming: false', () async {
      final service = friendsWith(
        (_, _) async => <String, dynamic>{'outcome': 'requested'},
      );
      final result = await service.requestFriendship(receiver);
      expect(calls.single.name, 'sendFriendRequest');
      expect(calls.single.data, <String, dynamic>{
        'targetUserId': _other,
        'acceptIncoming': false,
      });
      expect(result.status, FriendRelationshipStatus.requestSent);
      expect(result.incomingPending, isFalse);
      expect(result.acceptedWithoutPrompt, isFalse);
    });

    test(
      'incomingPending becomes requestReceived with a prompt flag',
      () async {
        final service = friendsWith(
          (_, _) async => <String, dynamic>{
            'outcome': 'incomingPending',
            'changed': false,
          },
        );
        final result = await service.requestFriendship(receiver);
        expect(result.status, FriendRelationshipStatus.requestReceived);
        expect(result.incomingPending, isTrue);
        expect(result.acceptedWithoutPrompt, isFalse);
      },
    );

    test(
      'an old server\'s "accepted" is flagged, never a plain success',
      () async {
        final service = friendsWith(
          (_, _) async => <String, dynamic>{'outcome': 'accepted'},
        );
        final result = await service.requestFriendship(receiver);
        expect(result.status, FriendRelationshipStatus.friends);
        expect(result.acceptedWithoutPrompt, isTrue);
      },
    );
  });

  group('FriendService: explicit answers report stale states', () {
    test('server outcomes map one to one', () async {
      final outcomes = <String, FriendRequestResponseOutcome>{
        'accepted': FriendRequestResponseOutcome.accepted,
        'declined': FriendRequestResponseOutcome.declined,
        'alreadyAccepted': FriendRequestResponseOutcome.alreadyFriends,
        'alreadyResolved': FriendRequestResponseOutcome.alreadyResolved,
      };
      for (final entry in outcomes.entries) {
        final service = friendsWith(
          (_, _) async => <String, dynamic>{'outcome': entry.key},
        );
        expect(
          await service.respondToFriendRequest(_other, accept: true),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test(
      'a cancelled request is noLongerAvailable, a block unavailable',
      () async {
        final gone = friendsWith(
          (_, _) async => throw SocialActionException(
            'not-found',
            serverMessage: 'This friend request is no longer available.',
          ),
        );
        expect(
          await gone.respondToFriendRequest(_other, accept: true),
          FriendRequestResponseOutcome.noLongerAvailable,
        );
        final blocked = friendsWith(
          (_, _) async => throw SocialActionException(
            'failed-precondition',
            serverMessage:
                'This action is unavailable because one of the accounts has '
                'blocked the other.',
          ),
        );
        expect(
          await blocked.respondToFriendRequest(_other, accept: true),
          FriendRequestResponseOutcome.unavailable,
        );
      },
    );

    test('a refusal that is not about the request still throws', () async {
      final unverified = friendsWith(
        (_, _) async => throw SocialActionException(
          'failed-precondition',
          serverMessage: 'Verify your email before connecting with people.',
        ),
      );
      await expectLater(
        unverified.respondToFriendRequest(_other, accept: true),
        throwsA(isA<SocialActionException>()),
      );
    });
  });

  group('Notifications screen', () {
    late List<AppNotification> opened;

    Future<void> pumpInbox(
      WidgetTester tester, {
      required FriendService friends,
      Size size = const Size(390, 844),
      bool polish = false,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final notifications = NotificationService(firestore: db, auth: auth);
      final messages = MessageService(
        firestore: db,
        auth: auth,
        notificationService: notifications,
      );
      addTearDown(messages.dispose);
      opened = <AppNotification>[];
      await tester.pumpWidget(
        _localized(
          NotificationsScreen(
            isRootTab: true,
            acknowledgeOnVisible: false,
            friendService: friends,
            messageService: messages,
            notificationService: notifications,
            currentUserId: _me,
            firestore: db,
            auth: auth,
            openNotification: (notification) async => opened.add(notification),
          ),
          polish: polish,
        ),
      );
      for (var pump = 0; pump < 8; pump++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    for (final size in const [Size(390, 844), Size(1280, 900)]) {
      testWidgets('the request card and the activity row both offer labelled '
          'Accept and Decline at ${size.width.toInt()} px', (tester) async {
        await seedPendingRequest();
        await seedRequestRow('friendRequest_${_other}_1');
        await pumpInbox(tester, friends: friendsWith(null), size: size);

        _expectLabelledButton(
          find.byKey(const ValueKey('notification-request-accept-$_other')),
          'Accept',
        );
        _expectLabelledButton(
          find.byKey(const ValueKey('notification-request-decline-$_other')),
          'Decline',
        );
        _expectLabelledButton(
          find.byKey(
            const ValueKey('notification-row-accept-friendRequest_${_other}_1'),
          ),
          'Accept',
        );
        _expectLabelledButton(
          find.byKey(
            const ValueKey(
              'notification-row-decline-friendRequest_${_other}_1',
            ),
          ),
          'Decline',
        );
        expect(
          find.byType(IconButton).evaluate().where((element) {
            final button = element.widget as IconButton;
            final icon = button.icon;
            return icon is Icon && icon.icon == Icons.check_rounded;
          }),
          isEmpty,
          reason: 'no icon-only accept check may remain',
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Polish copy: Akceptuj and Odrzuć', (tester) async {
      await seedPendingRequest();
      await pumpInbox(tester, friends: friendsWith(null), polish: true);
      _expectLabelledButton(
        find.byKey(const ValueKey('notification-request-accept-$_other')),
        'Akceptuj',
      );
      _expectLabelledButton(
        find.byKey(const ValueKey('notification-request-decline-$_other')),
        'Odrzuć',
      );
    });

    testWidgets('tapping a card or a row body opens, and never answers', (
      tester,
    ) async {
      await seedPendingRequest();
      await seedRequestRow('friendRequest_${_other}_1');
      await pumpInbox(tester, friends: friendsWith(null));

      await tester.tap(find.text('Sent you a friend request'));
      await tester.pump();
      await tester.tap(find.text('Ola sent you a friend request').first);
      await tester.pump();

      expect(calls, isEmpty, reason: 'a body tap must never accept');
      expect(opened.single.type, NotificationType.friendRequest);
    });

    testWidgets('Accept on the activity row answers once with feedback', (
      tester,
    ) async {
      await seedPendingRequest();
      await seedRequestRow('friendRequest_${_other}_1');
      await pumpInbox(
        tester,
        friends: friendsWith(
          (_, _) async => <String, dynamic>{'outcome': 'accepted'},
        ),
      );

      await tester.tap(
        find.byKey(
          const ValueKey('notification-row-accept-friendRequest_${_other}_1'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(calls.single.name, 'respondToFriendRequest');
      expect(calls.single.data, <String, dynamic>{
        'senderId': _other,
        'accept': true,
      });
      expect(find.text('You and Ola are now friends.'), findsWidgets);
    });

    testWidgets('Decline gives its own feedback', (tester) async {
      await seedPendingRequest();
      await pumpInbox(
        tester,
        friends: friendsWith(
          (_, _) async => <String, dynamic>{'outcome': 'declined'},
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('notification-request-decline-$_other')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(calls.single.data['accept'], isFalse);
      expect(find.text('Friend request declined.'), findsOneWidget);
    });

    testWidgets('a cancelled request says so instead of failing', (
      tester,
    ) async {
      await seedPendingRequest();
      await pumpInbox(
        tester,
        friends: friendsWith(
          (_, _) async => throw SocialActionException(
            'not-found',
            serverMessage: 'This friend request is no longer available.',
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('notification-request-accept-$_other')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('This request is no longer available.'), findsOneWidget);
      expect(
        find.text('Something went wrong. Please try again.'),
        findsNothing,
      );
    });

    testWidgets('a new request from the same person after a Decline offers '
        'the buttons again', (tester) async {
      final first = DateTime(2026, 9, 25, 10);
      Future<void> seedRequest(DateTime createdAt) => db
          .collection('users')
          .doc(_me)
          .collection('friendRequests')
          .doc(_other)
          .set(<String, dynamic>{
            'senderId': _other,
            'senderName': 'Ola',
            'senderPhotoUrl': null,
            'createdAt': Timestamp.fromDate(createdAt),
          });
      await seedRequest(first);
      await seedRequestRow('friendRequest_${_other}_1');
      await pumpInbox(
        tester,
        friends: friendsWith(
          (_, _) async => <String, dynamic>{'outcome': 'declined'},
        ),
      );

      await tester.tap(
        find.byKey(
          const ValueKey('notification-row-decline-friendRequest_${_other}_1'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(
          const ValueKey('notification-row-accept-friendRequest_${_other}_1'),
        ),
        findsNothing,
        reason: 'the answered row shows its result, not buttons',
      );

      // The server removes the answered request and row; later Ola asks again.
      await db
          .collection('users')
          .doc(_me)
          .collection('notifications')
          .doc('friendRequest_${_other}_1')
          .delete();
      await seedRequest(first.add(const Duration(hours: 1)));
      await seedRequestRow('friendRequest_${_other}_2');
      for (var pump = 0; pump < 6; pump++) {
        await tester.pump(const Duration(milliseconds: 80));
      }

      _expectLabelledButton(
        find.byKey(
          const ValueKey('notification-row-accept-friendRequest_${_other}_2'),
        ),
        'Accept',
      );
      _expectLabelledButton(
        find.byKey(const ValueKey('notification-request-accept-$_other')),
        'Accept',
      );
      expect(calls, hasLength(1));
    });

    testWidgets('a row whose request is gone shows the state, not buttons', (
      tester,
    ) async {
      await seedRequestRow('friendRequest_${_other}_stale');
      await pumpInbox(tester, friends: friendsWith(null));

      expect(
        find.byKey(
          const ValueKey(
            'notification-row-accept-friendRequest_${_other}_stale',
          ),
        ),
        findsNothing,
      );
      expect(find.text('This request is no longer available.'), findsOneWidget);
    });
  });

  group('Friend profile, requestReceived', () {
    late CallToneService tones;
    late PublicIdentityRepository originalIdentity;

    setUp(() async {
      ActiveConversationRegistry.instance.clear();
      tones = CallToneService(enabled: () => false);
      debugCallToneServiceOverride = tones;
      originalIdentity = PublicIdentityRepository.instance;
      PublicIdentityRepository.instance = PublicIdentityRepository(
        auth: _auth(),
        fetchOverride: (uids) async => <String, dynamic>{
          for (final uid in uids) uid: {'role': 'user', 'uid': uid},
        },
        flushDelay: const Duration(milliseconds: 1),
      );
      await db.collection('users').doc(_me).set({
        'uid': _me,
        'displayName': 'Me',
      });
      await db.collection('publicProfiles').doc(_other).set({
        'uid': _other,
        'displayName': 'Ola',
        'username': 'ola',
      });
    });

    tearDown(() {
      ActiveConversationRegistry.instance.clear();
      PublicIdentityRepository.instance = originalIdentity;
      debugCallToneServiceOverride = null;
      unawaited(tones.dispose());
    });

    Future<void> pumpProfile(
      WidgetTester tester,
      FriendService friends, {
      Size size = const Size(390, 844),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final notifications = NotificationService(firestore: db, auth: auth);
      final messages = MessageService(
        firestore: db,
        auth: auth,
        notificationService: notifications,
      );
      addTearDown(messages.dispose);
      await tester.pumpWidget(
        _localized(
          FriendProfileScreen(
            friend: const FriendUser(
              id: _other,
              displayName: 'Ola',
              email: '',
              photoUrl: null,
              isOnline: false,
              lastSeen: null,
            ),
            firestore: db,
            auth: auth,
            friendService: friends,
            messageService: messages,
            profileService: ProfileService(firestore: db, auth: auth),
            followService: FollowService(firestore: db, auth: auth),
            socialGraphService: _EmptyGraph(),
            creatorPinnedPostService: CreatorPinnedPostService(
              firestore: db,
              auth: auth,
            ),
            isFriend: false,
            relationshipStatusResolver: (_) async =>
                FriendRelationshipStatus.requestReceived,
            directCallService: _NoCalls(),
            voiceCallService: _QuietVoice(),
            serverRepository: _NoServers(),
          ),
        ),
      );
      for (var pump = 0; pump < 8; pump++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    Future<void> cleanUp(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }

    for (final size in const [Size(390, 844), Size(1280, 900)]) {
      testWidgets('offers labelled Accept and Decline at '
          '${size.width.toInt()} px, and Accept answers once', (tester) async {
        await pumpProfile(
          tester,
          friendsWith((_, _) async => <String, dynamic>{'outcome': 'accepted'}),
          size: size,
        );

        final accept = find.byKey(
          const ValueKey('friend-profile-request-accept'),
        );
        await tester.ensureVisible(accept);
        _expectLabelledButton(accept, 'Accept');
        _expectLabelledButton(
          find.byKey(const ValueKey('friend-profile-request-decline')),
          'Decline',
        );
        expect(calls, isEmpty);

        await tester.tap(accept);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(calls.single.name, 'respondToFriendRequest');
        expect(calls.single.data['accept'], isTrue);
        expect(find.text('You and Ola are now friends.'), findsOneWidget);
        expect(accept, findsNothing, reason: 'answered: no second chance');
        expect(tester.takeException(), isNull);
        await cleanUp(tester);
      });
    }
  });

  group('Profile preview', () {
    Future<void> openPreview(
      WidgetTester tester, {
      required FriendService friends,
      bool pending = true,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await db.collection('users').doc(_me).set({'uid': _me});
      await db.collection('publicProfiles').doc(_other).set({
        'uid': _other,
        'displayName': 'Ola',
        'username': 'ola',
      });
      if (pending) await seedPendingRequest();
      await tester.pumpWidget(
        _localized(
          Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => unawaited(
                    showProfilePreview(
                      context,
                      userId: _other,
                      displayName: 'Ola',
                      firestore: db,
                      auth: auth,
                      friendService: friends,
                    ),
                  ),
                  child: const Text('Open profile preview'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open profile preview'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('a received request shows Accept and Decline, never a lone '
        'Accept', (tester) async {
      await openPreview(tester, friends: friendsWith(null));

      _expectLabelledButton(
        find.byKey(const ValueKey('profile-preview-request-accept')),
        'Accept',
      );
      _expectLabelledButton(
        find.byKey(const ValueKey('profile-preview-request-decline')),
        'Decline',
      );
      expect(find.text('Request received'), findsOneWidget);
      expect(calls, isEmpty);
    });

    testWidgets('a Decline on a request accepted on another device re-reads '
        'the friendship instead of offering Add friend', (tester) async {
      await openPreview(
        tester,
        friends: friendsWith(
          (_, _) async => <String, dynamic>{'outcome': 'alreadyResolved'},
        ),
      );
      // Accepted on another device while the preview was open.
      await db
          .collection('users')
          .doc(_me)
          .collection('friendRequests')
          .doc(_other)
          .delete();
      await db
          .collection('users')
          .doc(_me)
          .collection('friends')
          .doc(_other)
          .set(<String, dynamic>{'uid': _other});

      final decline = find.byKey(
        const ValueKey('profile-preview-request-decline'),
      );
      await tester.ensureVisible(decline);
      await tester.tap(decline);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(calls.single.data['accept'], isFalse);
      expect(find.text('This request was already answered.'), findsOneWidget);
      expect(find.text('Add friend'), findsNothing);
      expect(find.text('Friends'), findsWidgets);
    });

    testWidgets('Add friend on someone who already asked opens the prompt '
        'and changes nothing', (tester) async {
      await openPreview(
        tester,
        pending: false,
        friends: friendsWith(
          (name, _) async => name == 'sendFriendRequest'
              ? <String, dynamic>{
                  'outcome': 'incomingPending',
                  'changed': false,
                }
              : <String, dynamic>{'outcome': 'declined'},
        ),
      );

      final add = find.text('Add friend');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(calls.single.data['acceptIncoming'], isFalse);
      expect(find.text('Friends'), findsNothing);
      final decline = find.byKey(
        const ValueKey('profile-preview-request-decline'),
      );
      _expectLabelledButton(decline, 'Decline');

      await tester.ensureVisible(decline);
      await tester.tap(decline);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls.last.name, 'respondToFriendRequest');
      expect(calls.last.data['accept'], isFalse);
      expect(find.text('Friend request declined.'), findsOneWidget);
    });
  });

  group('Decision buttons', () {
    testWidgets('the spoken Accept / Decline carry the tap action and the '
        'enabled state', (tester) async {
      final semantics = tester.ensureSemantics();
      var accepted = 0;
      var declined = 0;
      Future<void> pumpPair({bool busyAccept = false}) => tester.pumpWidget(
        _localized(
          Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: FriendRequestDecisionButtons(
                  name: 'Ola',
                  busyAccept: busyAccept,
                  onAccept: () => accepted++,
                  onDecline: () => declined++,
                ),
              ),
            ),
          ),
        ),
      );

      await pumpPair();
      for (final label in const [
        'Accept friend request from Ola',
        'Decline friend request from Ola',
      ]) {
        final node = tester.getSemantics(find.bySemanticsLabel(label));
        final data = node.getSemanticsData();
        expect(data.hasAction(ui.SemanticsAction.tap), isTrue, reason: label);
        expect(data.flagsCollection.isEnabled, ui.Tristate.isTrue);
        expect(data.flagsCollection.isButton, isTrue);
        node.owner!.performAction(node.id, ui.SemanticsAction.tap);
        await tester.pump();
      }
      expect(accepted, 1);
      expect(declined, 1);

      await pumpPair(busyAccept: true);
      for (final label in const [
        'Accept friend request from Ola',
        'Decline friend request from Ola',
      ]) {
        final data = tester
            .getSemantics(find.bySemanticsLabel(label))
            .getSemanticsData();
        expect(data.flagsCollection.isEnabled, ui.Tristate.isFalse);
        expect(data.hasAction(ui.SemanticsAction.tap), isFalse, reason: label);
      }
      semantics.dispose();
    });

    for (final (width, theme) in [
      (320.0, AppTheme.lightTheme),
      (390.0, AppTheme.darkTheme),
    ]) {
      testWidgets('Pearl and Dark at 200 % text: both labels read in full at '
          '${width.toInt()} px', (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _localized(
            MediaQuery(
              data: const MediaQueryData(
                size: Size(390, 700),
                textScaler: TextScaler.linear(2),
              ),
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FriendRequestResponsePanel(
                    senderId: _other,
                    senderName: 'Aleksandra Konstantynopolitańczykiewicz',
                    friendService: friendsWith(null),
                    showIdentity: false,
                  ),
                ),
              ),
            ),
            polish: true,
            theme: theme,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        _expectLabelledButton(
          find.byKey(const ValueKey('friend-request-panel-accept')),
          'Akceptuj',
        );
        _expectLabelledButton(
          find.byKey(const ValueKey('friend-request-panel-decline')),
          'Odrzuć',
        );
        final accept = tester.getRect(
          find.byKey(const ValueKey('friend-request-panel-accept')),
        );
        final decline = tester.getRect(
          find.byKey(const ValueKey('friend-request-panel-decline')),
        );
        expect(
          decline.top,
          greaterThanOrEqualTo(accept.bottom),
          reason: 'at 200 % text the pair stacks instead of squeezing',
        );
      });
    }

    test(
      'a stale answer re-reads the relationship; a fresh one does not',
      () async {
        var reads = 0;
        Future<FriendRelationshipStatus> reread() async {
          reads++;
          return FriendRelationshipStatus.friends;
        }

        expect(
          await friendRelationshipAfterResponse(
            FriendRequestResponseOutcome.accepted,
            reread: reread,
          ),
          FriendRelationshipStatus.friends,
        );
        expect(
          await friendRelationshipAfterResponse(
            FriendRequestResponseOutcome.declined,
            reread: reread,
          ),
          FriendRelationshipStatus.none,
        );
        expect(reads, 0);
        expect(
          await friendRelationshipAfterResponse(
            FriendRequestResponseOutcome.alreadyResolved,
            reread: reread,
          ),
          FriendRelationshipStatus.friends,
          reason: 'a Decline on a request accepted elsewhere keeps the friends',
        );
        expect(
          await friendRelationshipAfterResponse(
            FriendRequestResponseOutcome.noLongerAvailable,
            reread: reread,
          ),
          FriendRelationshipStatus.friends,
        );
        expect(reads, 2);
        expect(
          await friendRelationshipAfterResponse(
            FriendRequestResponseOutcome.alreadyResolved,
            reread: () async => throw StateError('offline'),
          ),
          FriendRelationshipStatus.none,
        );
      },
    );
  });

  group('Incoming-request prompt', () {
    testWidgets('shows who asked with both buttons; closing decides nothing', (
      tester,
    ) async {
      FriendRequestResponseOutcome? result =
          FriendRequestResponseOutcome.accepted;
      await tester.pumpWidget(
        _localized(
          Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  result = await showFriendRequestPrompt(
                    context,
                    senderId: _other,
                    senderName: 'Ola',
                    friendService: friendsWith(null),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Ola already asked to be your friend'), findsOneWidget);
      _expectLabelledButton(
        find.byKey(const ValueKey('friend-request-prompt-accept')),
        'Accept',
      );
      _expectLabelledButton(
        find.byKey(const ValueKey('friend-request-prompt-decline')),
        'Decline',
      );
      await tester.tap(
        find.byKey(const ValueKey('friend-request-prompt-close')),
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(result, isNull);
    });

    testWidgets('an answer is returned however the sheet is closed', (
      tester,
    ) async {
      FriendRequestResponseOutcome? result;
      var closed = false;
      await tester.pumpWidget(
        _localized(
          Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  result = await showFriendRequestPrompt(
                    context,
                    senderId: _other,
                    senderName: 'Ola',
                    friendService: friendsWith(
                      (_, _) async => <String, dynamic>{'outcome': 'declined'},
                    ),
                  );
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('friend-request-prompt-decline')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Friend request declined.'), findsOneWidget);

      // Dismissed through the barrier, not "Done".
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, FriendRequestResponseOutcome.declined);
      expect(calls, hasLength(1));
    });
  });

  group('Foreground banner', () {
    Future<YoTopNotificationController> pumpHost(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = YoTopNotificationController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              YoTopNotificationHost(controller: controller, child: child!),
          home: const Scaffold(body: SizedBox.expand()),
        ),
      );
      await tester.pump();
      return controller;
    }

    YoTopNotification friendRequestCard({
      required FriendService friends,
      required VoidCallback onOpen,
    }) => YoTopNotification(
      title: 'Ola sent you a friend request',
      type: NotificationType.friendRequest,
      onOpen: onOpen,
      decision: friendRequestBannerDecision(
        type: NotificationType.friendRequest,
        senderId: _other,
        senderName: 'Ola',
        friendService: () => friends,
      ),
    );

    testWidgets('a friend-request card offers labelled Accept and Decline; '
        'its body only opens', (tester) async {
      final controller = await pumpHost(tester);
      var opened = 0;
      expect(
        controller.show(
          friendRequestCard(friends: friendsWith(null), onOpen: () => opened++),
        ),
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 400));

      _expectLabelledButton(
        find.byKey(const ValueKey('yo-top-notification-accept')),
        'Accept',
      );
      _expectLabelledButton(
        find.byKey(const ValueKey('yo-top-notification-decline')),
        'Decline',
      );
      expect(find.text('View request'), findsOneWidget);

      await tester.tap(find.text('Ola sent you a friend request'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(opened, 1);
      expect(calls, isEmpty, reason: 'opening the card never accepts');
    });

    testWidgets('Accept answers once and the card shows the result', (
      tester,
    ) async {
      final controller = await pumpHost(tester);
      controller.show(
        friendRequestCard(
          friends: friendsWith(
            (_, _) async => <String, dynamic>{'outcome': 'accepted'},
          ),
          onOpen: () {},
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      // The pair arms 500 ms after the 300 ms entrance (arrival guard).
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(
        find.byKey(const ValueKey('yo-top-notification-accept')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(calls.single.name, 'respondToFriendRequest');
      expect(calls.single.data['accept'], isTrue);
      expect(find.text('You and Ola are now friends.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('yo-top-notification-accept')),
        findsNothing,
      );
      controller.clear();
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('a tap as the card arrives never answers; the pair arms '
        'once the card has settled', (tester) async {
      final controller = await pumpHost(tester);
      controller.show(
        friendRequestCard(
          friends: friendsWith(
            (_, _) async => <String, dynamic>{'outcome': 'accepted'},
          ),
          onOpen: () {},
        ),
      );
      final accept = find.byKey(const ValueKey('yo-top-notification-accept'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(accept, warnIfMissed: false);
      await tester.pump();
      expect(calls, isEmpty, reason: 'a tap during the entrance is ignored');

      // 300 ms after show: the entrance has only just finished.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(accept, warnIfMissed: false);
      await tester.pump();
      expect(calls, isEmpty, reason: 'still inside the settle window');

      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(accept);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(calls, hasLength(1));
      expect(calls.single.data['accept'], isTrue);
      controller.clear();
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('a new banner during an in-flight decision is never left '
        'busy, still auto-dismisses, and the first answer is not lost', (
      tester,
    ) async {
      final controller = await pumpHost(tester);
      final gate = Completer<Map<String, dynamic>>();
      controller.show(
        friendRequestCard(
          friends: friendsWith((_, _) => gate.future),
          onOpen: () {},
        ),
      );
      await tester.pump(const Duration(milliseconds: 900));
      await tester.tap(
        find.byKey(const ValueKey('yo-top-notification-accept')),
      );
      await tester.pump();
      expect(calls, hasLength(1));

      // Another request arrives while the first answer is still running.
      expect(
        controller.show(
          YoTopNotification(
            title: 'Kai sent you a friend request',
            type: NotificationType.friendRequest,
            onOpen: () {},
            decision: friendRequestBannerDecision(
              type: NotificationType.friendRequest,
              senderId: 'kai-uid',
              senderName: 'Kai',
              friendService: () => friendsWith(null),
            ),
          ),
        ),
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('Kai sent you a friend request'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('yo-top-notification-accept')),
            )
            .onPressed,
        isNotNull,
        reason: 'the new card is not busy with the old card\'s call',
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);

      gate.complete(<String, dynamic>{'outcome': 'accepted'});
      await tester.pump();
      expect(
        find.text('Kai sent you a friend request'),
        findsOneWidget,
        reason: 'the older answer never cuts the newer card short',
      );
      expect(find.text('You and Ola are now friends.'), findsNothing);

      // The newer card keeps its normal 5 s window and then closes...
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 400));
      for (var pump = 0; pump < 4; pump++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Kai sent you a friend request'), findsNothing);
      // ...and the first answer is shown after it.
      expect(find.text('You and Ola are now friends.'), findsOneWidget);
      expect(calls, hasLength(1));
      controller.clear();
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('an answer that finishes after a session clear says nothing', (
      tester,
    ) async {
      final controller = await pumpHost(tester);
      final gate = Completer<Map<String, dynamic>>();
      controller.show(
        friendRequestCard(
          friends: friendsWith((_, _) => gate.future),
          onOpen: () {},
        ),
      );
      await tester.pump(const Duration(milliseconds: 900));
      await tester.tap(
        find.byKey(const ValueKey('yo-top-notification-accept')),
      );
      await tester.pump();
      controller.clear();
      await tester.pump();
      gate.complete(<String, dynamic>{'outcome': 'accepted'});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('You and Ola are now friends.'), findsNothing);
      expect(
        find.byKey(const ValueKey('yo-top-notification-card')),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('other types keep the plain Open card', (tester) async {
      expect(
        friendRequestBannerDecision(
          type: NotificationType.follow,
          senderId: _other,
          senderName: 'Ola',
          friendService: () => friendsWith(null),
        ),
        isNull,
      );
      expect(
        friendRequestBannerDecision(
          type: NotificationType.friendRequest,
          senderId: '',
          senderName: 'Ola',
          friendService: () => friendsWith(null),
        ),
        isNull,
        reason: 'a legacy row with no sender has nobody to answer',
      );
    });
  });
}
