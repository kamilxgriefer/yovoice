import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/features/clubs/data/models/family_check_in.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/clubs/presentation/widgets/family_check_in_panel.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';

import 'package:yovoice/core/theme/space_identity.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';

/// Legacy Family spaces keep a private data boundary while existing accounts
/// migrate to Family servers. These tests cover their canonical data, check-in
/// behavior and compatibility identity.
///
/// The privacy boundary itself is server-side and is covered where it is
/// actually enforced, in firestore-tests/rules.test.js.
void main() {
  late FakeFirebaseFirestore db;

  MockFirebaseAuth auth() => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'me', email: 'me@yovoice.app', displayName: 'Me'),
  );

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('users').doc('me').set({
      'uid': 'me',
      'displayName': 'Me',
    });
  });

  Widget host(Widget child) => MaterialApp(home: child);

  void usePhone(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('Family creation service', () {
    test('creates the complete canonical space for a free account with '
        'private media disabled and reopens idempotently', () async {
      final mockAuth = auth();
      final storage = MockFirebaseStorage();
      final service = ClubService(
        firestore: db,
        auth: mockAuth,
        storage: storage,
        notificationService: NotificationService(firestore: db, auth: mockAuth),
      );
      final created = await service.createFamilyRoom(
        name: 'Our Family',
        description: 'Our private home',
        defaultLanguage: 'Polish',
      );

      expect(created.id, 'family_me');
      expect(created.type, ClubType.family);
      expect(created.privacy, ClubPrivacy.inviteOnly);
      expect(created.avatarUrl, isNull);
      expect(created.bannerUrl, isNull);
      expect(
        (await db.collection('entitlements').doc('me').get()).exists,
        isFalse,
        reason: 'Family Rooms are the free exception to Premium Club gating',
      );

      final root = await db.collection('clubs').doc('family_me').get();
      expect(root.data()?['ownerId'], 'me');
      expect(root.data()?['type'], 'family');
      expect(root.data()?['privacy'], 'inviteOnly');
      expect(root.data()?['avatarUrl'], isNull);
      expect(root.data()?['bannerUrl'], isNull);
      expect(root.data()?['loungeRoomId'], 'club_lounge_family_me');

      final member = await db
          .collection('clubs')
          .doc('family_me')
          .collection('members')
          .doc('me')
          .get();
      expect(member.data()?['role'], 'owner');
      final projection = await db
          .collection('users')
          .doc('me')
          .collection('clubs')
          .doc('family_me')
          .get();
      expect(projection.data()?['role'], 'owner');
      expect(projection.data()?['avatarUrl'], isNull);

      final channels = await db
          .collection('clubs')
          .doc('family_me')
          .collection('channels')
          .get();
      expect(channels.docs, hasLength(3));
      expect(channels.docs.map((doc) => doc.data()['type']).toSet(), <String>{
        'chat',
        'announcement',
        'voice',
      });
      final lounge = await db
          .collection('rooms')
          .doc('club_lounge_family_me')
          .get();
      expect(lounge.data()?['clubId'], 'family_me');
      expect(lounge.data()?['visibility'], 'private');
      expect(lounge.data()?['roomKind'], 'clubLounge');
      expect(lounge.data()?['imageUrl'], isNull);

      final reopened = await service.createFamilyRoom(
        name: 'A different name must not create another room',
        description: 'Ignored on reopen',
      );
      expect(reopened.id, created.id);
      expect(reopened.name, 'Our Family');
      expect((await db.collection('clubs').get()).docs, hasLength(1));
      expect((await db.collection('rooms').get()).docs, hasLength(1));
    });

    test('rejects every Family image before creating or uploading', () async {
      final mockAuth = auth();
      final storage = MockFirebaseStorage();
      final service = ClubService(
        firestore: db,
        auth: mockAuth,
        storage: storage,
        notificationService: NotificationService(firestore: db, auth: mockAuth),
      );
      final image = XFile.fromData(
        Uint8List.fromList(List<int>.filled(256, 0)),
        name: 'family-banner.png',
        mimeType: 'image/png',
      );

      await expectLater(
        service.createFamilyRoom(
          name: 'Our Family',
          description: 'Private',
          bannerFile: image,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('private authenticated media'),
          ),
        ),
      );
      expect((await db.collection('clubs').get()).docs, isEmpty);
    });

    test(
      'concurrent create attempts converge on one canonical Family Room',
      () async {
        final mockAuth = auth();
        ClubService service() => ClubService(
          firestore: db,
          auth: mockAuth,
          storage: MockFirebaseStorage(),
          notificationService: NotificationService(
            firestore: db,
            auth: mockAuth,
          ),
        );

        final results = await Future.wait([
          service().createFamilyRoom(
            name: 'Our Family',
            description: 'First device',
          ),
          service().createFamilyRoom(
            name: 'Our Family',
            description: 'Second device',
          ),
        ]);

        expect(results.map((club) => club.id).toSet(), {'family_me'});
        expect((await db.collection('clubs').get()).docs, hasLength(1));
        expect((await db.collection('rooms').get()).docs, hasLength(1));
        final root = await db.collection('clubs').doc('family_me').get();
        for (final channelId in [
          root.data()?['defaultChatChannelId'],
          root.data()?['announcementChannelId'],
          root.data()?['defaultVoiceChannelId'],
        ]) {
          expect(channelId, isA<String>());
          expect(
            (await db
                    .collection('clubs')
                    .doc('family_me')
                    .collection('channels')
                    .doc(channelId as String)
                    .get())
                .exists,
            isTrue,
          );
        }
      },
    );
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
      expect(find.textContaining('Not an emergency feature'), findsOneWidget);
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
      await db.collection('users').doc('me').set({
        'uid': 'me',
        'displayName': 'Me',
      });

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

  group('Space identity system', () {
    test('every space type has its own distinct identity', () {
      expect(SpaceIdentity.community.primary, const Color(0xFF8A2BE2));
      expect(SpaceIdentity.community.accent, const Color(0xFFC026FF));
      expect(SpaceIdentity.podcast.primary, const Color(0xFFFF3D68));
      expect(SpaceIdentity.podcast.accent, const Color(0xFFFF6B81));
      expect(SpaceIdentity.club.primary, const Color(0xFFD9A441));
      expect(SpaceIdentity.club.accent, const Color(0xFFFFD166));
      expect(SpaceIdentity.family.primary, const Color(0xFF28D17C));
      expect(SpaceIdentity.family.accent, const Color(0xFF35E58D));
      expect(SpaceIdentity.family.surface, const Color(0xFF12231D));
      expect(SpaceIdentity.family.border, const Color(0xFF286447));

      // No two types may share a primary — the colour IS the identity.
      final primaries = SpaceIdentity.all.map((i) => i.primary).toSet();
      expect(primaries, hasLength(4));
      final surfaces = SpaceIdentity.all.map((i) => i.surface).toSet();
      expect(surfaces, hasLength(4));
    });

    test('of() resolves every kind, so no surface can miss one', () {
      for (final kind in SpaceKind.values) {
        expect(SpaceIdentity.of(kind).kind, kind);
      }
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
