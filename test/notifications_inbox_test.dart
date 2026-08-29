import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';
import 'package:yovoice/features/notifications/presentation/screens/notifications_screen.dart';

/// The activity inbox's own guarantees.
///
/// The screen composes three streams — friend requests, conversations
/// and the activity feed — and the feed is the only one that is
/// canonical. Both of the failure modes pinned here were real: an
/// auxiliary stream stuck in `waiting` held the whole screen on a
/// spinner, and a single `hasError` across all three replaced everything
/// with one error state, so a Chats-side failure blanked the bell inbox.
void main() {
  const me = 'me-uid';
  const other = 'other-uid';

  late FakeFirebaseFirestore db;
  late NotificationService service;

  MockFirebaseAuth authFor(String uid) => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: uid, email: '$uid@yovoice.app', displayName: uid),
  );

  Future<void> seedNotification({
    required String id,
    String type = 'friendRequest',
    String actorName = 'Other',
    String? targetLabel,
    bool isRead = false,
    bool bellSuppressed = false,
    Duration age = const Duration(minutes: 1),
  }) async {
    await db
        .collection('users')
        .doc(me)
        .collection('notifications')
        .doc(id)
        .set(<String, dynamic>{
          'type': type,
          'actorId': other,
          'actorName': actorName,
          'actorPhotoUrl': null,
          'targetId': null,
          'targetLabel': targetLabel,
          'isRead': isRead,
          'createdAt': Timestamp.fromDate(DateTime.now().subtract(age)),
          'dedupeKey': id,
          'bellSuppressed': bellSuppressed,
        });
  }

  setUp(() {
    db = FakeFirebaseFirestore();
    service = NotificationService(firestore: db, auth: authFor(me));
  });

  group('bell feed and badge', () {
    test('the three social activity types all reach the feed', () async {
      await seedNotification(id: 'friendRequest_$other', type: 'friendRequest');
      await seedNotification(
        id: 'friendAccepted_$other',
        type: 'friendAccepted',
        age: const Duration(minutes: 2),
      );
      await seedNotification(
        id: 'follow_$other',
        type: 'follow',
        age: const Duration(minutes: 3),
      );

      final feed = await service.watchNotifications().first;
      expect(
        feed.map((n) => n.type),
        containsAll(<NotificationType>[
          NotificationType.friendRequest,
          NotificationType.friendAccepted,
          NotificationType.follow,
        ]),
      );
      // Newest first.
      expect(feed.first.type, NotificationType.friendRequest);
    });

    test('a friend DM carrier never reaches the feed or the badge', () async {
      await seedNotification(id: 'follow_$other', type: 'follow');
      await seedNotification(
        id: 'dm-carrier',
        type: 'directMessage',
        bellSuppressed: true,
        age: const Duration(seconds: 5),
      );

      final feed = await service.watchNotifications().first;
      expect(feed.map((n) => n.id), <String>['follow_$other']);
      expect(await service.watchUnreadCount().first, 1);
    });

    test('a non-friend message request DOES reach the feed', () async {
      await seedNotification(
        id: 'dm-request',
        type: 'directMessage',
        bellSuppressed: false,
      );
      final feed = await service.watchNotifications().first;
      expect(feed.single.type, NotificationType.directMessage);
      expect(await service.watchUnreadCount().first, 1);
    });

    test('reading one item clears only that item', () async {
      await seedNotification(id: 'follow_$other', type: 'follow');
      await seedNotification(
        id: 'friendRequest_$other',
        type: 'friendRequest',
        age: const Duration(minutes: 2),
      );
      expect(await service.watchUnreadCount().first, 2);

      await service.markAsRead('follow_$other');

      expect(await service.watchUnreadCount().first, 1);
      final still = await db
          .collection('users')
          .doc(me)
          .collection('notifications')
          .doc('friendRequest_$other')
          .get();
      expect(still.data()!['isRead'], isFalse);
    });

    test('mark-all touches only the caller\'s own inbox', () async {
      await seedNotification(id: 'follow_$other', type: 'follow');
      await db
          .collection('users')
          .doc(other)
          .collection('notifications')
          .doc('someone-elses')
          .set(<String, dynamic>{
            'type': 'follow',
            'actorId': me,
            'actorName': 'Me',
            'isRead': false,
            'createdAt': Timestamp.now(),
            'bellSuppressed': false,
          });

      await service.markAllAsRead();

      expect(await service.watchUnreadCount().first, 0);
      final theirs = await db
          .collection('users')
          .doc(other)
          .collection('notifications')
          .doc('someone-elses')
          .get();
      expect(
        theirs.data()!['isRead'],
        isFalse,
        reason: "another account's inbox must be untouched",
      );
    });

    test(
      'a legacy document with no bellSuppressed field stays visible',
      () async {
        await db
            .collection('users')
            .doc(me)
            .collection('notifications')
            .doc('legacy')
            .set(<String, dynamic>{
              'type': 'follow',
              'actorId': other,
              'actorName': 'Other',
              'isRead': false,
              'createdAt': Timestamp.now(),
            });

        final feed = await service.watchNotifications().first;
        expect(feed.single.id, 'legacy');
        expect(await service.watchUnreadCount().first, 1);
      },
    );
  });

  group('stream ownership', () {
    test(
      'a second account gets its OWN feed, never the previous one\'s',
      () async {
        await seedNotification(id: 'follow_$other', type: 'follow');
        expect(
          (await service.watchNotifications().first).single.id,
          'follow_$other',
        );

        // Account switch: a service bound to the new user reads that
        // user's subcollection and nothing else.
        final switched = NotificationService(
          firestore: db,
          auth: authFor('someone-new'),
        );
        expect(await switched.watchNotifications().first, isEmpty);
        expect(await switched.watchUnreadCount().first, 0);
      },
    );

    test(
      'cancelling the feed subscription closes its underlying streams',
      () async {
        await seedNotification(id: 'follow_$other', type: 'follow');
        final received = <int>[];
        final subscription = service.watchNotifications().listen(
          (event) => received.add(event.length),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await subscription.cancel();

        final before = received.length;
        await seedNotification(
          id: 'friendRequest_$other',
          type: 'friendRequest',
          age: const Duration(seconds: 1),
        );
        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(
          received.length,
          before,
          reason: 'a cancelled feed must stop emitting for the old account',
        );
      },
    );
  });

  group('the activity feed is independent of the auxiliary streams', () {
    Future<void> pumpScreen(
      WidgetTester tester, {
      required MessageService messages,
    }) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsScreen(
            isRootTab: true,
            friendService: FriendService(firestore: db, auth: authFor(me)),
            messageService: messages,
            notificationService: service,
            currentUserId: me,
          ),
        ),
      );
      // Bounded pumps: the erroring stream settles immediately, and the
      // hanging one never will.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('a failing conversations stream cannot blank the feed', (
      tester,
    ) async {
      await seedNotification(id: 'follow_$other', type: 'follow');

      await pumpScreen(
        tester,
        messages: _FailingMessageService(
          firestore: db,
          auth: authFor(me),
          notificationService: service,
        ),
      );

      // The activity is there...
      expect(find.textContaining('started following you'), findsOneWidget);
      // ...the screen did NOT collapse into the old blanket error...
      expect(find.text('Could not load notifications'), findsNothing);
      // ...and the missing section is admitted rather than hidden.
      expect(find.textContaining('could not be loaded'), findsOneWidget);
    });

    testWidgets('an auxiliary stream stuck loading cannot hold the screen '
        'on a spinner', (tester) async {
      await seedNotification(id: 'follow_$other', type: 'follow');

      await pumpScreen(
        tester,
        messages: _HangingMessageService(
          firestore: db,
          auth: authFor(me),
          notificationService: service,
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('started following you'), findsOneWidget);
    });
  });

  group('responsive activity layout', () {
    testWidgets('keeps a full-width phone feed and an 880px top-left '
        'desktop list with long activity copy', (tester) async {
      const notificationId = 'long-room-invite';
      const longActorName =
          'A very long display name that must wrap safely without stretching '
          'the activity list across the desktop shell';
      await seedNotification(
        id: notificationId,
        type: 'roomInvite',
        actorName: longActorName,
        targetLabel:
            'An equally long room title used to verify constrained text at '
            'every responsive breakpoint',
      );

      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      for (final size in const [
        Size(320, 640),
        Size(390, 844),
        Size(430, 932),
        Size(768, 1024),
        Size(1100, 800),
        Size(1440, 900),
        Size(2560, 1440),
      ]) {
        tester.view.physicalSize = size;
        final auth = authFor(me);
        await tester.pumpWidget(
          MaterialApp(
            home: NotificationsScreen(
              isRootTab: true,
              friendService: FriendService(firestore: db, auth: auth),
              messageService: MessageService(
                firestore: db,
                auth: auth,
                notificationService: service,
              ),
              notificationService: service,
              currentUserId: me,
            ),
          ),
        );
        for (var pump = 0; pump < 8; pump++) {
          await tester.pump(const Duration(milliseconds: 80));
        }

        final frame = tester.getRect(
          find.byKey(const ValueKey('notifications-content-frame')),
        );
        final background = tester.getRect(
          find.byKey(const ValueKey('notifications-background')),
        );
        final expectedWidth = size.width > 880 ? 880.0 : size.width;

        expect(frame.width, expectedWidth, reason: '$size frame width');
        expect(frame.left, 0, reason: '$size stays top-left in its slot');
        expect(background.width, size.width, reason: '$size full-bleed bg');
        expect(find.textContaining(longActorName), findsOneWidget);
        expect(
          tester
              .widget<Text>(
                find.byKey(
                  const ValueKey('notification-title-$notificationId'),
                ),
              )
              .maxLines,
          isNull,
          reason: '$size must not truncate a name or activity title',
        );
        expect(tester.takeException(), isNull, reason: '$size overflow');
      }
    });

    testWidgets('320px at 200% text reflows and exposes an accessible '
        'non-swipe delete action', (tester) async {
      const id = 'a11y-long-notification';
      const longActorName =
          'A very long accessible display name that must remain completely '
          'readable when system text is enlarged to two hundred percent';
      await seedNotification(
        id: id,
        type: 'roomInvite',
        actorName: longActorName,
        targetLabel:
            'A deliberately long room title for the narrow reflow test',
      );

      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();

      for (final size in const [Size(320, 568), Size(320, 844)]) {
        tester.view.physicalSize = size;
        final auth = authFor(me);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: NotificationsScreen(
                key: ValueKey(size.height),
                isRootTab: true,
                friendService: FriendService(firestore: db, auth: auth),
                messageService: MessageService(
                  firestore: db,
                  auth: auth,
                  notificationService: service,
                ),
                notificationService: service,
                currentUserId: me,
              ),
            ),
          ),
        );
        for (var pump = 0; pump < 8; pump++) {
          await tester.pump(const Duration(milliseconds: 80));
        }

        final title = find.byKey(ValueKey('notification-title-$id'));
        final actions = find.byKey(ValueKey('notification-actions-$id'));
        expect(
          tester
              .getSize(
                find.byKey(const ValueKey('notifications-mark-all-read')),
              )
              .height,
          greaterThanOrEqualTo(44),
        );
        await tester.scrollUntilVisible(
          actions,
          100,
          scrollable: find.byType(Scrollable).first,
        );

        expect(title, findsOneWidget);
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
          AppPalette.light.background,
        );
        expect(tester.widget<Text>(title).maxLines, isNull);
        expect(tester.getSize(title).height, greaterThan(40));
        expect(
          find.bySemanticsLabel(RegExp(r'^Unread notification\.')),
          findsOneWidget,
        );
        expect(find.byTooltip('Notification actions'), findsOneWidget);
        expect(tester.widget<PopupMenuButton>(actions).enabled, isTrue);
        expect(tester.getSize(actions).height, greaterThanOrEqualTo(44));
        expect(tester.takeException(), isNull, reason: '$size at 200% text');
      }

      final actions = find.byKey(ValueKey('notification-actions-$id'));
      await tester.tap(actions);
      await tester.pumpAndSettle();
      expect(find.text('Delete notification'), findsOneWidget);
      await tester.tap(find.text('Delete notification'));
      await tester.pumpAndSettle();

      expect(
        await db
            .collection('users')
            .doc(me)
            .collection('notifications')
            .doc(id)
            .get()
            .then((document) => document.exists),
        isFalse,
      );
      semantics.dispose();
    });
  });

  group('web push boundary', () {
    test('an unconfigured build reports web push as unavailable, and every '
        'other platform as unaffected', () {
      // No --dart-define in the test build, so the key is empty.
      expect(PushNotificationService.webVapidKey, isEmpty);
      // The getter is what gates registration; on non-web it must never
      // block, which is why it is `!kIsWeb || ...`.
      expect(PushNotificationService.webPushConfigured, isTrue);
    });
  });
}

/// The screen-level guarantee: the activity feed renders on its own
/// terms. These two cases are the regressions that made the inbox look
/// dead when nothing was wrong with it.
class _FailingMessageService extends MessageService {
  // MessageService builds its own NotificationService when none is
  // given, and that resolves FirebaseFirestore.instance — which needs a
  // Firebase app. Pass one through.
  _FailingMessageService({
    required super.firestore,
    required super.auth,
    required super.notificationService,
  });

  @override
  Stream<List<Conversation>> watchConversations({
    bool includeArchived = false,
  }) => Stream<List<Conversation>>.error(
    FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
  );
}

class _HangingMessageService extends MessageService {
  _HangingMessageService({
    required super.firestore,
    required super.auth,
    required super.notificationService,
  });

  /// Never emits and never closes, so its StreamBuilder stays in
  /// `waiting` for the lifetime of the screen.
  @override
  Stream<List<Conversation>> watchConversations({
    bool includeArchived = false,
  }) => StreamController<List<Conversation>>().stream;
}
