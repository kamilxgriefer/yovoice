import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_moments_strip.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

/// The regression tests commit fb7874a shipped without.
///
/// Everything here is driven by fake_cloud_firestore and mock auth: no
/// network, no LiveKit, no image decoding, and therefore nothing that can
/// stall the test zone.
void main() {
  const me = 'me-uid';
  const host = 'host-uid';

  group('Find creators (Moments empty state)', () {
    testWidgets('is a secondary OutlinedButton, at least 150x40, and calls '
        'the real Discover callback by tap and by keyboard', (tester) async {
      tester.view.physicalSize = const Size(1200, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var discovered = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopMomentsStrip(
              onOpenMoment: (_) {},
              onCreateMoment: () {},
              onSeeAll: () {},
              onDiscover: () => discovered++,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));

      final button = find.widgetWithText(OutlinedButton, 'Find creators');
      expect(button, findsOneWidget, reason: 'must stay a secondary button');

      final size = tester.getSize(button);
      expect(size.width, greaterThanOrEqualTo(150));
      expect(size.height, greaterThanOrEqualTo(40));

      // Secondary, not a stretched CTA: it must occupy a small fraction
      // of the strip it sits in.
      final stripWidth = tester.getSize(find.byType(DesktopMomentsStrip)).width;
      expect(
        size.width,
        lessThan(stripWidth * 0.35),
        reason: 'Find creators must not read as a full-width primary CTA',
      );

      await tester.tap(button);
      await tester.pump();
      expect(discovered, 1);

      // Keyboard: reach it by real traversal, then activate. Focus.of()
      // on the button's own context looks for an ANCESTOR Focus and
      // throws — the button's node is a descendant of that context.
      var reached = false;
      for (var i = 0; i < 10 && !reached; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focused = primaryFocus?.context?.widget;
        reached =
            focused != null &&
            find
                .descendant(of: button, matching: find.byWidget(focused))
                .evaluate()
                .isNotEmpty;
      }
      expect(reached, isTrue, reason: 'Tab never reached Find creators');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(discovered, 2, reason: 'keyboard activation must also fire');

      expect(tester.takeException(), isNull);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('Featured Live roster', () {
    late FakeFirebaseFirestore db;
    late MockFirebaseAuth auth;

    /// One live room plus a deliberately SHUFFLED participant set, so an
    /// ordering assertion cannot pass by accident of insertion order.
    Future<void> seedRoom({int listeners = 2}) async {
      await db.collection('rooms').doc('room-1').set(<String, dynamic>{
        'hostId': host,
        'hostName': 'Hosty',
        'name': 'what is going on',
        'description': 'haha yes',
        'category': 'talk',
        'visibility': 'public',
        'language': 'English',
        'participantCount': 2 + listeners,
        'memberCount': 0,
        'isLive': true,
        'roomType': 'community',
        'status': 'active',
        'experience': 'community',
        'createdAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      });

      final participants = db
          .collection('rooms')
          .doc('room-1')
          .collection('participants');

      // Insertion order is listener → speaker → moderator → host on
      // purpose: the widget must sort, not echo.
      for (var i = 0; i < listeners; i++) {
        await participants.doc('listener-$i').set(<String, dynamic>{
          'userId': 'listener-$i',
          'displayName': 'Listener $i',
          'role': 'listener',
          'isMuted': true,
          'isSpeaker': false,
        });
      }
      await participants.doc('speaker-1').set(<String, dynamic>{
        'userId': 'speaker-1',
        'displayName': 'Speaky',
        'role': 'speaker',
        'isMuted': false,
        'isSpeaker': true,
      });
      await participants.doc('mod-1').set(<String, dynamic>{
        'userId': 'mod-1',
        'displayName': 'Moddy',
        'role': 'moderator',
        'isMuted': false,
        'isSpeaker': true,
      });
      await participants.doc(host).set(<String, dynamic>{
        'userId': host,
        'displayName': 'Hosty',
        'role': 'host',
        'isMuted': false,
        'isSpeaker': true,
      });
    }

    Future<void> pumpHome(WidgetTester tester, {Size? size}) async {
      tester.view.physicalSize = size ?? const Size(1440, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopHome(
              currentUserId: me,
              onOpenRoom: (_) {},
              onSeeAllRooms: () {},
              onViewAllFriends: () {},
              onStartRoom: () {},
              onOpenMoment: (_) {},
              onCreateMoment: () {},
              onSeeAllMoments: () {},
              onOpenConversation: (_) {},
              onOpenClub: (_) {},
              onSeeAllChats: () {},
              onOpenClubs: () {},
              roomService: RoomService(firestore: db, auth: auth),
            ),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    setUp(() async {
      db = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: me, displayName: 'Me'),
      );
      await db.collection('users').doc(me).set(<String, dynamic>{
        'uid': me,
        'displayName': 'Me',
      });
    });

    testWidgets('the card exposes ONE avatar trigger, and it reports a '
        'truthful count from the participant stream', (tester) async {
      await seedRoom();
      await pumpHome(tester);

      // 5 participants: host, moderator, speaker, 2 listeners.
      expect(find.text('5 in the room'), findsOneWidget);
      // The cluster of four decorative avatars is gone.
      expect(find.textContaining('in the room'), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 90)));

    testWidgets('activating the avatar opens a roster ordered host → '
        'moderator → speaker → listener, with real mute state', (tester) async {
      await seedRoom();
      await pumpHome(tester);

      await tester.tap(find.text('5 in the room'));
      await tester.pump(const Duration(milliseconds: 300));

      // Every row came from the seeded stream.
      for (final name in ['Hosty', 'Moddy', 'Speaky', 'Listener 0']) {
        expect(find.text(name), findsWidgets, reason: '$name missing');
      }
      expect(find.text('Host'), findsOneWidget);
      expect(find.text('Moderator'), findsOneWidget);
      expect(find.text('Speaker'), findsOneWidget);
      expect(find.text('Listening'), findsNWidgets(2));

      // Ordering by rendered position, not by list index.
      double y(String label) => tester.getTopLeft(find.text(label).last).dy;
      expect(y('Host'), lessThan(y('Moderator')));
      expect(y('Moderator'), lessThan(y('Speaker')));
      expect(y('Speaker'), lessThan(y('Listening')));

      // Mute state is the participants' own: the two listeners are muted,
      // the three speakers are not.
      expect(find.byIcon(Icons.mic_off_rounded), findsNWidgets(2));
    }, timeout: const Timeout(Duration(seconds: 90)));

    testWidgets('Escape closes the roster, and reopening does not duplicate '
        'its rows', (tester) async {
      await seedRoom(listeners: 1);
      await pumpHome(tester);

      await tester.tap(find.text('4 in the room'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Moddy'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Moddy'), findsNothing);

      await tester.tap(find.text('4 in the room'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Moddy'),
        findsOneWidget,
        reason: 'reopening must not stack a second copy of the roster',
      );
    }, timeout: const Timeout(Duration(seconds: 90)));

    testWidgets(
      'an empty room says so instead of showing an empty list',
      (tester) async {
        await db.collection('rooms').doc('room-1').set(<String, dynamic>{
          'hostId': host,
          'hostName': 'Hosty',
          'name': 'quiet room',
          'description': 'nobody here',
          'category': 'talk',
          'visibility': 'public',
          'language': 'English',
          'participantCount': 0,
          'memberCount': 0,
          'isLive': true,
          'roomType': 'community',
          'status': 'active',
          'experience': 'community',
          'createdAt': Timestamp.now(),
        });
        await pumpHome(tester);

        expect(find.text('Host'), findsOneWidget);
        await tester.tap(find.text('Host'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Nobody is in this room yet.'), findsOneWidget);
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );

    testWidgets(
      'disposing the surface tears the room subscription down',
      (tester) async {
        await seedRoom();
        await pumpHome(tester);
        expect(find.text('5 in the room'), findsOneWidget);

        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await tester.pump(const Duration(milliseconds: 200));

        // A live listener writing after teardown would throw into the test
        // zone; a clean teardown leaves nothing behind.
        await db
            .collection('rooms')
            .doc('room-1')
            .collection('participants')
            .doc('late-arrival')
            .set(<String, dynamic>{
              'userId': 'late-arrival',
              'displayName': 'Late',
              'role': 'listener',
              'isMuted': true,
              'isSpeaker': false,
            });
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  });
}
