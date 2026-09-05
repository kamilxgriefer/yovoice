import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_moments_strip.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

/// The regression tests commit fb7874a shipped without, carried onto the
/// surfaces that replaced its cards.
///
/// The Featured Live card is gone; the room banner's face pile is the
/// affordance that now opens a room's roster, so the roster coverage
/// points there rather than at the deleted host-avatar button.
///
/// Everything here is driven by fake_cloud_firestore and mock auth: no
/// network, no LiveKit, no image decoding, and therefore nothing that can
/// stall the test zone.
void main() {
  const me = 'me-uid';
  const host = 'host-uid';

  group('Moments avatar-only empty state', () {
    testWidgets(
      'keeps only the own avatar and its accessible record action',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        var created = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DesktopMomentsStrip(
                onOpenMoment: (_) {},
                onCreateMoment: () => created++,
                onSeeAll: () {},
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 60));

        expect(find.text('YO Moments from your circle'), findsOneWidget);
        expect(find.byKey(const ValueKey('home-your-moment')), findsOneWidget);
        expect(
          find.textContaining('No Moments from your circle yet'),
          findsNothing,
        );
        expect(find.text('Find creators'), findsNothing);

        final plus = find.byKey(const ValueKey('home-record-moment'));
        expect(plus, findsOneWidget);
        expect(tester.getSize(plus), const Size(44, 44));
        await tester.tap(plus);
        await tester.pump();
        expect(created, 1);

        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });

  group('Room banner participant preview', () {
    late FakeFirebaseFirestore db;
    late MockFirebaseAuth auth;

    /// One live room plus a deliberately SHUFFLED participant set, so an
    /// ordering assertion cannot pass by accident of insertion order.
    /// `participantCount` matches the number of participant documents,
    /// the way the room writes keep it in production.
    Future<void> seedRoom({int listeners = 2}) async {
      await db.collection('rooms').doc('room-1').set(<String, dynamic>{
        'hostId': host,
        'hostName': 'Hosty',
        'name': 'what is going on',
        'description': 'haha yes',
        'category': 'talk',
        'visibility': 'public',
        'language': 'English',
        'participantCount': 3 + listeners,
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

    testWidgets('the banner exposes ONE face pile, and the count beside the '
        'LIVE badge is the room\'s own', (tester) async {
      await seedRoom();
      await pumpHome(tester);

      // 5 participants: host, moderator, speaker, 2 listeners.
      expect(find.text('5'), findsOneWidget);
      expect(find.byTooltip('See who is in the room'), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 90)));

    testWidgets('activating the face pile opens a roster ordered host → '
        'moderator → speaker → listener, with real mute state', (tester) async {
      await seedRoom();
      await pumpHome(tester);

      await tester.tap(find.byTooltip('See who is in the room'));
      await tester.pumpAndSettle();

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

      await tester.tap(find.byTooltip('See who is in the room'));
      await tester.pumpAndSettle();
      expect(find.text('Moddy'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Moddy'), findsNothing);

      await tester.tap(find.byTooltip('See who is in the room'));
      await tester.pumpAndSettle();
      expect(
        find.text('Moddy'),
        findsOneWidget,
        reason: 'reopening must not stack a second copy of the roster',
      );
    }, timeout: const Timeout(Duration(seconds: 90)));

    testWidgets(
      'a room nobody is in shows no face pile rather than placeholder faces',
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

        // The banner is there and honest about being empty...
        expect(find.text('quiet room'), findsOneWidget);
        expect(find.text('0'), findsOneWidget);
        // ...and offers no way into a roster that would be empty.
        expect(find.byTooltip('See who is in the room'), findsNothing);
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );

    testWidgets(
      'the roster itself says so when the room empties out under it',
      (tester) async {
        // The list widget keeps its own empty state, for the case where
        // the last participant leaves while the roster is open.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RoomRosterList(
                participants: const [],
                hostId: host,
                onDismiss: () {},
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Nobody is in this room yet.'), findsOneWidget);
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    testWidgets(
      'disposing the surface tears the room subscription down',
      (tester) async {
        await seedRoom();
        await pumpHome(tester);
        expect(find.byTooltip('See who is in the room'), findsOneWidget);

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
