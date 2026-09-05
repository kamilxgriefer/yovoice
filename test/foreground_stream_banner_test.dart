import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/app/app.dart';
import 'package:yovoice/features/messages/data/services/active_conversation_registry.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';
import 'package:yovoice/features/notifications/presentation/widgets/yo_top_notification_host.dart';

/// The global in-app notification banner must not depend on FCM: any
/// unread notification document arriving on the Firestore feed after the
/// session's baseline banners — once — whether or not push is configured.
void main() {
  AppNotification notification(
    String id, {
    bool isRead = false,
    bool bellSuppressed = false,
    NotificationType type = NotificationType.follow,
    String? targetId,
  }) {
    return AppNotification(
      id: id,
      type: type,
      actorId: 'actor-$id',
      actorName: 'Actor $id',
      actorPhotoUrl: null,
      targetId: targetId,
      targetLabel: null,
      isRead: isRead,
      createdAt: DateTime.utc(2026, 8, 18, 12),
      bellSuppressed: bellSuppressed,
    );
  }

  testWidgets('a doc arriving after the baseline banners once, and a '
      're-emit never duplicates', (tester) async {
    final auth = StreamController<User?>.broadcast();
    final feed = StreamController<List<AppNotification>>.broadcast();
    final shown = <String>[];
    final topNotifications = YoTopNotificationController();
    addTearDown(topNotifications.dispose);

    final source = ForegroundNotificationStreamSource(
      authStates: auth.stream,
      watchNotifications: () => feed.stream,
      // The production glue minus the sound: the real app-level top host.
      showBanner: (arrival) {
        shown.add(arrival.id);
        return topNotifications.show(
          YoTopNotification(
            title: arrival.title,
            type: arrival.type,
            onOpen: () {},
          ),
        );
      },
    )..start();
    addTearDown(source.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            YoTopNotificationHost(controller: topNotifications, child: child!),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );

    auth.add(MockUser(uid: 'me-uid'));
    await tester.pump();

    // First snapshot is the baseline: the pre-existing backlog, unread or
    // not, never banners.
    feed.add([notification('pre-existing')]);
    await tester.pump();
    expect(shown, isEmpty);
    expect(
      find.byKey(const ValueKey('yo-top-notification-card')),
      findsNothing,
    );

    // A genuinely new arrival banners exactly once.
    feed.add([notification('fresh'), notification('pre-existing')]);
    await tester.pump();
    await tester.pump();
    expect(shown, ['fresh']);
    expect(find.text('Actor fresh started following you'), findsOneWidget);

    // Firestore re-delivers the whole window on any change: no duplicate.
    feed.add([notification('fresh'), notification('pre-existing')]);
    await tester.pump();
    expect(shown, ['fresh']);
    expect(
      find.byKey(const ValueKey('yo-top-notification-card')),
      findsOneWidget,
    );

    // Let the banner's auto-dismiss timer expire before the test ends.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  test('read and bell-suppressed documents never banner', () async {
    final auth = StreamController<User?>.broadcast();
    final feed = StreamController<List<AppNotification>>.broadcast();
    final shown = <String>[];

    final source = ForegroundNotificationStreamSource(
      authStates: auth.stream,
      watchNotifications: () => feed.stream,
      showBanner: (arrival) {
        shown.add(arrival.id);
        return true;
      },
    )..start();
    addTearDown(source.dispose);

    auth.add(MockUser(uid: 'me-uid'));
    await Future<void>.delayed(Duration.zero);

    feed.add(const <AppNotification>[]); // baseline
    await Future<void>.delayed(Duration.zero);

    feed.add([
      notification('suppressed-carrier', bellSuppressed: true),
      notification('already-read', isRead: true),
      notification('genuine'),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(shown, ['genuine']);
  });

  test('the FCM path and the stream path dedupe against each other', () async {
    final auth = StreamController<User?>.broadcast();
    final feed = StreamController<List<AppNotification>>.broadcast();
    final shown = <String>[];

    final source = ForegroundNotificationStreamSource(
      authStates: auth.stream,
      watchNotifications: () => feed.stream,
      showBanner: (arrival) {
        shown.add(arrival.id);
        return true;
      },
    )..start();
    addTearDown(source.dispose);

    auth.add(MockUser(uid: 'me-uid'));
    await Future<void>.delayed(Duration.zero);
    feed.add(const <AppNotification>[]); // baseline
    await Future<void>.delayed(Duration.zero);

    // Push beat Firestore: reserve first, then commit only after the platform
    // accepted its presentation. The stream defers the matching document.
    final pushFirst = source.claimPushBanner('n1');
    expect(pushFirst.shouldPresent, isTrue);
    expect(pushFirst.claim, isNotNull);
    expect(source.claimPushBanner('n1').shouldPresent, isFalse);
    feed.add([notification('n1')]);
    await Future<void>.delayed(Duration.zero);
    expect(shown, isEmpty);
    pushFirst.claim!.complete(presented: true);
    expect(shown, isEmpty);

    // Firestore beat push: the stream banner shows, the FCM one is vetoed.
    feed.add([notification('n2'), notification('n1')]);
    await Future<void>.delayed(Duration.zero);
    expect(shown, ['n2']);
    expect(source.claimPushBanner('n2').shouldPresent, isFalse);

    // A legacy payload without an id cannot be deduped, but must not vanish.
    final idless = source.claimPushBanner(null);
    expect(idless.shouldPresent, isTrue);
    expect(idless.claim, isNull);
  });

  test(
    'a failed FCM presentation releases its deferred Firestore banner',
    () async {
      final auth = StreamController<User?>.broadcast();
      final feed = StreamController<List<AppNotification>>.broadcast();
      final shown = <String>[];
      final source = ForegroundNotificationStreamSource(
        authStates: auth.stream,
        watchNotifications: () => feed.stream,
        showBanner: (arrival) {
          shown.add(arrival.id);
          return true;
        },
      )..start();
      addTearDown(source.dispose);

      auth.add(MockUser(uid: 'me-uid'));
      await Future<void>.delayed(Duration.zero);
      feed.add(const <AppNotification>[]); // baseline
      await Future<void>.delayed(Duration.zero);

      final decision = source.claimPushBanner('failed-native');
      feed.add([notification('failed-native')]);
      await Future<void>.delayed(Duration.zero);
      expect(shown, isEmpty);

      decision.claim!.complete(presented: false);
      expect(shown, ['failed-native']);

      // Completion and Firestore re-emission are both idempotent.
      decision.claim!.complete(presented: false);
      feed.add([notification('failed-native')]);
      await Future<void>.delayed(Duration.zero);
      expect(shown, ['failed-native']);
    },
  );

  test('messenger rejection stays pending and retries exactly once', () async {
    final auth = StreamController<User?>.broadcast();
    final feed = StreamController<List<AppNotification>>.broadcast();
    final shown = <String>[];
    var messengerReady = false;
    var attempts = 0;
    final source = ForegroundNotificationStreamSource(
      authStates: auth.stream,
      watchNotifications: () => feed.stream,
      showBanner: (arrival) {
        attempts++;
        if (!messengerReady) return false;
        shown.add(arrival.id);
        return true;
      },
    )..start();
    addTearDown(source.dispose);

    auth.add(MockUser(uid: 'me-uid'));
    await Future<void>.delayed(Duration.zero);
    feed.add(const <AppNotification>[]); // baseline
    await Future<void>.delayed(Duration.zero);

    final decision = source.claimPushBanner('not-mounted-yet');
    feed.add([notification('not-mounted-yet')]);
    await Future<void>.delayed(Duration.zero);
    decision.claim!.complete(presented: false);
    expect(attempts, 1);
    expect(shown, isEmpty);

    source.retryPendingBanners();
    expect(attempts, 2);
    expect(shown, isEmpty);

    messengerReady = true;
    source.retryPendingBanners();
    expect(shown, ['not-mounted-yet']);
    expect(source.claimPushBanner('not-mounted-yet').shouldPresent, isFalse);

    source.retryPendingBanners();
    feed.add([notification('not-mounted-yet')]);
    await Future<void>.delayed(Duration.zero);
    expect(shown, ['not-mounted-yet']);
  });

  test(
    'failed push before the first snapshot is not mistaken for backlog',
    () async {
      final auth = StreamController<User?>.broadcast();
      final feed = StreamController<List<AppNotification>>.broadcast();
      final shown = <String>[];
      final source = ForegroundNotificationStreamSource(
        authStates: auth.stream,
        watchNotifications: () => feed.stream,
        showBanner: (arrival) {
          shown.add(arrival.id);
          return true;
        },
      )..start();
      addTearDown(source.dispose);

      auth.add(MockUser(uid: 'me-uid'));
      await Future<void>.delayed(Duration.zero);
      final decision = source.claimPushBanner('startup-arrival');
      decision.claim!.complete(presented: false);

      // This is technically the baseline snapshot, but the failed FCM claim
      // proves this one id is a live arrival that still needs presentation.
      feed.add([notification('startup-arrival'), notification('old-backlog')]);
      await Future<void>.delayed(Duration.zero);
      expect(shown, ['startup-arrival']);
    },
  );

  test(
    'a delayed failed push can fall back to an already-known document',
    () async {
      final auth = StreamController<User?>.broadcast();
      final feed = StreamController<List<AppNotification>>.broadcast();
      final shown = <String>[];
      final source = ForegroundNotificationStreamSource(
        authStates: auth.stream,
        watchNotifications: () => feed.stream,
        showBanner: (arrival) {
          shown.add(arrival.id);
          return true;
        },
      )..start();
      addTearDown(source.dispose);

      auth.add(MockUser(uid: 'me-uid'));
      await Future<void>.delayed(Duration.zero);
      feed.add([notification('already-in-baseline')]);
      await Future<void>.delayed(Duration.zero);
      expect(shown, isEmpty);

      // The FCM delivery may lag behind the snapshot. Its presentation failure
      // must reuse the cached source-of-truth document immediately; there may be
      // no second Firestore emission to wake a retry.
      final decision = source.claimPushBanner('already-in-baseline');
      decision.claim!.complete(presented: false);
      expect(shown, ['already-in-baseline']);
    },
  );

  test(
    'presentation decisions preserve id-less delivery and settle claims',
    () async {
      var presentations = 0;
      expect(
        await presentForegroundNotificationDecision(
          decision: const ForegroundNotificationClaimDecision.allowUntracked(),
          present: () async {
            presentations++;
            return true;
          },
        ),
        isTrue,
      );
      expect(
        presentations,
        1,
        reason: 'an id-less legacy push must not vanish',
      );

      expect(
        await presentForegroundNotificationDecision(
          decision: const ForegroundNotificationClaimDecision.skip(),
          present: () async {
            presentations++;
            return true;
          },
        ),
        isFalse,
      );
      expect(presentations, 1, reason: 'a duplicate decision must not present');

      final outcomes = <bool>[];
      final successClaim = ForegroundNotificationClaim(outcomes.add);
      expect(
        await presentForegroundNotificationDecision(
          decision: ForegroundNotificationClaimDecision.claimed(successClaim),
          present: () async => true,
        ),
        isTrue,
      );
      successClaim.complete(presented: false);
      expect(outcomes, [true], reason: 'a claim is single-use');

      final failedClaim = ForegroundNotificationClaim(outcomes.add);
      await expectLater(
        presentForegroundNotificationDecision(
          decision: ForegroundNotificationClaimDecision.claimed(failedClaim),
          present: () async => throw StateError('platform unavailable'),
        ),
        throwsStateError,
      );
      expect(outcomes, [true, false]);
    },
  );

  test('signing out and back in resets the baseline', () async {
    final auth = StreamController<User?>.broadcast();
    final feed = StreamController<List<AppNotification>>.broadcast();
    final shown = <String>[];

    final source = ForegroundNotificationStreamSource(
      authStates: auth.stream,
      watchNotifications: () => feed.stream,
      showBanner: (arrival) {
        shown.add(arrival.id);
        return true;
      },
    )..start();
    addTearDown(source.dispose);

    auth.add(MockUser(uid: 'me-uid'));
    await Future<void>.delayed(Duration.zero);
    feed.add([notification('a')]); // baseline
    await Future<void>.delayed(Duration.zero);
    feed.add([notification('b'), notification('a')]);
    await Future<void>.delayed(Duration.zero);
    expect(shown, ['b']);

    auth.add(null);
    await Future<void>.delayed(Duration.zero);
    auth.add(MockUser(uid: 'me-uid'));
    await Future<void>.delayed(Duration.zero);

    // First snapshot of the new session is a fresh baseline — even ids
    // this session has never seen do not banner from it.
    feed.add([notification('c'), notification('b'), notification('a')]);
    await Future<void>.delayed(Duration.zero);
    expect(shown, ['b']);

    feed.add([
      notification('d'),
      notification('c'),
      notification('b'),
      notification('a'),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(shown, ['b', 'd']);
  });

  test(
    'FCM-first active-DM suppression cannot replay after chat closes',
    () async {
      final auth = StreamController<User?>.broadcast();
      final feed = StreamController<List<AppNotification>>.broadcast();
      final shown = <String>[];
      final active = ActiveConversationRegistry()..enter('conversation-1');
      final source = ForegroundNotificationStreamSource(
        authStates: auth.stream,
        watchNotifications: () => feed.stream,
        showBanner: (arrival) {
          shown.add(arrival.id);
          return true;
        },
      )..start();
      addTearDown(source.dispose);

      auth.add(MockUser(uid: 'me-uid'));
      await Future<void>.delayed(Duration.zero);
      feed.add(const <AppNotification>[]);
      await Future<void>.delayed(Duration.zero);

      final decision = source.claimPushBanner('dm-1');
      expect(
        await presentForegroundNotificationDecision(
          decision: decision,
          present: () async {
            final suppressed = shouldSuppressForegroundNotification(
              type: NotificationType.directMessage,
              targetId: 'conversation-1',
              activeConversations: active,
            );
            if (suppressed) return true;
            shown.add('fcm-dm-1');
            return true;
          },
        ),
        isTrue,
      );

      active.leave('conversation-1');
      feed.add([
        notification(
          'dm-1',
          type: NotificationType.directMessage,
          targetId: 'conversation-1',
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(shown, isEmpty);
    },
  );
}
