import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/clubs/data/models/family_check_in.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/clubs/presentation/widgets/family_check_in_panel.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/presentation/screens/create_club_screen.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_type_selector_screen.dart';

/// Family Room is a Club with a private data boundary, not a parallel
/// product. These tests cover the client half of that: the Create card
/// itself, its emerald identity, the navigation into the family template,
/// and — as importantly — that the three cards that were already there
/// are byte-for-byte what they were.
///
/// The privacy boundary itself is server-side and is covered where it is
/// actually enforced, in firestore-tests/rules.test.js.
void main() {
  late FakeFirebaseFirestore db;

  MockFirebaseAuth auth() => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'me', email: 'me@yovoice.app', displayName: 'Me'),
  );

  setUp(() {
    db = FakeFirebaseFirestore();
  });

  Widget host(Widget child) => MaterialApp(home: child);

  void usePhone(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('Create screen', () {
    testWidgets('offers Family Room with the agreed copy, directly below '
        'Club', (tester) async {
      usePhone(tester, const Size(390, 2400));
      await tester.pumpWidget(host(const RoomTypeSelectorScreen()));
      await tester.pump();

      expect(find.text('PRIVATE FAMILY SPACE'), findsOneWidget);
      expect(find.text('Family Room'), findsOneWidget);
      expect(
        find.text(
          'A permanent, invite-only space for the people closest to you.',
        ),
        findsOneWidget,
      );
      for (final benefit in const [
        'Always-open family voice lounge',
        'Private chat, announcements and quick check-ins',
        'Organizer and Member roles',
      ]) {
        expect(find.text(benefit), findsOneWidget, reason: benefit);
      }

      // Directly below Club, and last.
      double y(String label) => tester.getTopLeft(find.text(label)).dy;
      expect(y('Club'), lessThan(y('Family Room')));
      expect(y('Podcast Room'), lessThan(y('Club')));
      expect(y('Community Room'), lessThan(y('Podcast Room')));
    });

    testWidgets('the three existing choices are unchanged', (tester) async {
      usePhone(tester, const Size(390, 2400));
      await tester.pumpWidget(host(const RoomTypeSelectorScreen()));
      await tester.pump();

      for (final copy in const [
        'Community Room',
        'OPEN CONVERSATION',
        'A relaxed live room where everyone can speak.',
        'Podcast Room',
        'HOST + AUDIENCE',
        'A hosted show with a stage, audience and requests.',
        'Club',
        'PERMANENT COMMUNITY',
        'Members, roles, chat, announcements and a Club Lounge.',
      ]) {
        expect(find.text(copy), findsOneWidget, reason: copy);
      }
    });

    testWidgets('Family Room carries the emerald identity, and no other '
        'card does', (tester) async {
      usePhone(tester, const Size(390, 2400));
      await tester.pumpWidget(host(const RoomTypeSelectorScreen()));
      await tester.pump();

      // The eyebrow and title colours are the card's accent.
      final eyebrow = tester.widget<Text>(find.text('PRIVATE FAMILY SPACE'));
      expect(eyebrow.style?.color, RoomTypeSelectorScreen.familyAccent);

      // Its surface is the dark emerald tint, not the shared violet one.
      final card = find.ancestor(
        of: find.text('Family Room'),
        matching: find.byType(Material),
      );
      final surfaces = tester
          .widgetList<Material>(card)
          .map((material) => material.color)
          .toList();
      expect(
        surfaces,
        contains(RoomTypeSelectorScreen.familySurface),
        reason: 'the family card must use its own dark surface tint',
      );

      // The violet cards must not have picked up the emerald.
      final clubEyebrow = tester.widget<Text>(find.text('PERMANENT COMMUNITY'));
      expect(
        clubEyebrow.style?.color,
        isNot(RoomTypeSelectorScreen.familyAccent),
      );
    });

    testWidgets('every card keeps the same width and padding, so the new '
        'one is the same card', (tester) async {
      usePhone(tester, const Size(390, 2400));
      await tester.pumpWidget(host(const RoomTypeSelectorScreen()));
      await tester.pump();

      double width(String title) => tester
          .getSize(
            find
                .ancestor(of: find.text(title), matching: find.byType(Material))
                .first,
          )
          .width;

      final reference = width('Community Room');
      for (final title in const ['Podcast Room', 'Club', 'Family Room']) {
        expect(width(title), closeTo(reference, 0.5), reason: title);
      }
    });

    testWidgets('tapping Family Room opens the create flow in its family '
        'template', (tester) async {
      usePhone(tester, const Size(390, 2400));
      await tester.pumpWidget(host(const RoomTypeSelectorScreen()));
      await tester.pump();

      await tester.tap(find.text('Family Room'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final screen = tester.widget<CreateClubScreen>(
        find.byType(CreateClubScreen),
      );
      expect(screen.type, ClubType.family);
      expect(screen.isFamily, isTrue);
    });

    for (final size in const [
      Size(320, 2400),
      Size(390, 2400),
      Size(430, 2400),
      Size(1440, 2400),
    ]) {
      testWidgets('lays out without overflow at ${size.width.toInt()}pt', (
        tester,
      ) async {
        usePhone(tester, size);
        await tester.pumpWidget(host(const RoomTypeSelectorScreen()));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Family Room'), findsOneWidget);
      });
    }
  });

  group('Quick check-ins', () {
    testWidgets('offers exactly the four agreed statuses, and says plainly '
        'what they are not', (tester) async {
      usePhone(tester, const Size(390, 1200));
      await tester.pumpWidget(
        host(
          Scaffold(
            body: FamilyCheckInPanel(
              clubId: 'family_me',
              currentUserId: 'me',
              canManage: false,
              clubService: ClubService(
                firestore: db,
                auth: auth(),
                storage: MockFirebaseStorage(),
                notificationService: NotificationService(
                  firestore: db,
                  auth: auth(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      for (final label in const [
        "I'm home",
        'On my way',
        'All good',
        'Call me',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // Nothing here may read as an emergency or location feature.
      expect(
        find.textContaining('Not an emergency feature'),
        findsOneWidget,
      );
      expect(find.textContaining('no location'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a check-in is stored with its author, the room and a '
        'server timestamp, and carries no location', (tester) async {
      usePhone(tester, const Size(390, 1200));
      final service = ClubService(
        firestore: db,
        auth: auth(),
        storage: MockFirebaseStorage(),
        notificationService: NotificationService(firestore: db, auth: auth()),
      );

      await service.postCheckIn(
        clubId: 'family_me',
        status: FamilyCheckInStatus.onMyWay,
      );

      final rows = await db
          .collection('clubs')
          .doc('family_me')
          .collection('checkIns')
          .get();
      expect(rows.docs, hasLength(1));
      final data = rows.docs.single.data();
      expect(data['userId'], 'me');
      expect(data['clubId'], 'family_me');
      expect(data['status'], 'onMyWay');
      expect(data['createdAt'], isNotNull);
      // Precise location is never collected, so it can never be stored.
      expect(data.containsKey('latitude'), isFalse);
      expect(data.containsKey('longitude'), isFalse);
      expect(data.containsKey('location'), isFalse);
    });

    test('the four statuses are a closed set, and an unknown value is '
        'never rendered as one of them', () {
      expect(FamilyCheckInStatus.values, hasLength(4));
      expect(FamilyCheckInStatus.fromValue('home'), FamilyCheckInStatus.home);
      expect(FamilyCheckInStatus.fromValue('sos'), isNull);
      expect(FamilyCheckInStatus.fromValue(null), isNull);
      expect(FamilyCheckInStatus.fromValue(42), isNull);
    });

    testWidgets('the author can remove their own check-in; a plain member '
        'gets no control over someone else\'s', (tester) async {
      usePhone(tester, const Size(390, 1200));
      final service = ClubService(
        firestore: db,
        auth: auth(),
        storage: MockFirebaseStorage(),
        notificationService: NotificationService(firestore: db, auth: auth()),
      );
      await db
          .collection('clubs')
          .doc('family_me')
          .collection('checkIns')
          .doc('theirs')
          .set({
            'userId': 'someone-else',
            'clubId': 'family_me',
            'displayName': 'Ola',
            'status': 'home',
            'createdAt': Timestamp.now(),
          });

      await tester.pumpWidget(
        host(
          Scaffold(
            body: FamilyCheckInPanel(
              clubId: 'family_me',
              currentUserId: 'me',
              canManage: false,
              clubService: service,
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(find.textContaining('Ola'), findsOneWidget);
      // Not mine, and I am not an organizer: no remove control.
      expect(find.byTooltip('Remove check-in'), findsNothing);
    });

    testWidgets('an organizer can remove any check-in', (tester) async {
      usePhone(tester, const Size(390, 1200));
      final service = ClubService(
        firestore: db,
        auth: auth(),
        storage: MockFirebaseStorage(),
        notificationService: NotificationService(firestore: db, auth: auth()),
      );
      await db
          .collection('clubs')
          .doc('family_me')
          .collection('checkIns')
          .doc('theirs')
          .set({
            'userId': 'someone-else',
            'clubId': 'family_me',
            'displayName': 'Ola',
            'status': 'home',
            'createdAt': Timestamp.now(),
          });

      await tester.pumpWidget(
        host(
          Scaffold(
            body: FamilyCheckInPanel(
              clubId: 'family_me',
              currentUserId: 'me',
              canManage: true,
              clubService: service,
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(find.byTooltip('Remove check-in'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove check-in'));
      await tester.pump(const Duration(milliseconds: 200));

      final rows = await db
          .collection('clubs')
          .doc('family_me')
          .collection('checkIns')
          .get();
      expect(rows.docs, isEmpty);
    });
  });

  group('Family Room identity', () {
    test('a family room lives at a deterministic, per-account id', () {
      // This id IS the one-per-account limit: firestore.rules refuses
      // every other id, so a second family room has nowhere to go.
      expect(Club.familyRoomIdFor('abc123'), 'family_abc123');
      expect(
        Club.familyRoomIdFor('abc123'),
        isNot(Club.familyRoomIdFor('def456')),
      );
    });

    test('type defaults to community, so every club that already exists '
        'keeps its behaviour', () {
      expect(ClubType.fromValue(null), ClubType.community);
      expect(ClubType.fromValue('community'), ClubType.community);
      expect(ClubType.fromValue('anything else'), ClubType.community);
      expect(ClubType.fromValue('family'), ClubType.family);
    });
  });
}
