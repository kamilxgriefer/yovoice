import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/app/app.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';

/// The global in-app notification banner must not depend on FCM: any
/// unread notification document arriving on the Firestore feed after the
/// session's baseline banners — once — whether or not push is configured.
void main() {
  AppNotification notification(
    String id, {
    bool isRead = false,
    bool bellSuppressed = false,
  }) {
    return AppNotification(
      id: id,
      type: NotificationType.follow,
      actorId: 'actor-$id',
      actorName: 'Actor $id',
      actorPhotoUrl: null,
      targetId: null,
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
    final messengerKey = GlobalKey<ScaffoldMessengerState>();

    final source = ForegroundNotificationStreamSource(
      authStates: auth.stream,
      watchNotifications: () => feed.stream,
      // The production glue minus the sound: the real banner widget on
      // the app-level messenger.
      showBanner: (arrival) {
        shown.add(arrival.id);
        messengerKey.currentState!
          ..hideCurrentSnackBar()
          ..showSnackBar(
            buildForegroundNotificationBanner(
              title: arrival.title,
              body: null,
              type: arrival.type,
              targetId: arrival.targetId,
              actorId: arrival.actorId,
            ),
          );
      },
    )..start();
    addTearDown(source.dispose);

    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messengerKey,
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
    expect(find.byType(SnackBar), findsNothing);

    // A genuinely new arrival banners exactly once.
    feed.add([notification('fresh'), notification('pre-existing')]);
    await tester.pump();
    await tester.pump();
    expect(shown, ['fresh']);
    expect(
      find.text('Actor fresh started following you'),
      findsOneWidget,
    );

    // Firestore re-delivers the whole window on any change: no duplicate.
    feed.add([notification('fresh'), notification('pre-existing')]);
    await tester.pump();
    expect(shown, ['fresh']);
    expect(find.byType(SnackBar), findsOneWidget);

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
      showBanner: (arrival) => shown.add(arrival.id),
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
      showBanner: (arrival) => shown.add(arrival.id),
    )..start();
    addTearDown(source.dispose);

    auth.add(MockUser(uid: 'me-uid'));
    await Future<void>.delayed(Duration.zero);
    feed.add(const <AppNotification>[]); // baseline
    await Future<void>.delayed(Duration.zero);

    // Push beat Firestore: the FCM banner shows, the stream stays quiet.
    expect(source.registerPushBanner('n1'), isTrue);
    feed.add([notification('n1')]);
    await Future<void>.delayed(Duration.zero);
    expect(shown, isEmpty);

    // Firestore beat push: the stream banner shows, the FCM one is vetoed.
    feed.add([notification('n2'), notification('n1')]);
    await Future<void>.delayed(Duration.zero);
    expect(shown, ['n2']);
    expect(source.registerPushBanner('n2'), isFalse);

    // A payload without an id cannot be deduped and stays allowed.
    expect(source.registerPushBanner(null), isTrue);
  });

  test('signing out and back in resets the baseline', () async {
    final auth = StreamController<User?>.broadcast();
    final feed = StreamController<List<AppNotification>>.broadcast();
    final shown = <String>[];

    final source = ForegroundNotificationStreamSource(
      authStates: auth.stream,
      watchNotifications: () => feed.stream,
      showBanner: (arrival) => shown.add(arrival.id),
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
}
