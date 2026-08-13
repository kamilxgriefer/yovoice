import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/core/theme/space_identity.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/rooms/data/models/room_metadata.dart';
import 'package:yovoice/features/rooms/data/services/room_image_service.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/rooms/data/services/room_experience_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/create_room_screen.dart';

/// A picker/uploader that never touches Storage.
///
/// `RoomImageService` is reused rather than replaced — this stands in for
/// it so the wizard's cover behaviour (pick, preview, replace, remove,
/// upload, failure) can be exercised without a Firebase app.
class _FakeImageService implements RoomImageService {
  _FakeImageService({this.pickResult, this.uploadFails = false});

  XFile? pickResult;
  bool uploadFails;
  int pickCalls = 0;
  int uploadCalls = 0;
  String? uploadedForRoom;

  @override
  Future<XFile?> pickImage() async {
    pickCalls++;
    return pickResult;
  }

  @override
  Future<String> uploadRoomImage({
    required String roomId,
    required XFile file,
  }) async {
    uploadCalls++;
    uploadedForRoom = roomId;
    if (uploadFails) throw StateError('Storage rejected the upload.');
    return 'https://example.invalid/$roomId.jpg';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

XFile _fakeImage() =>
    XFile.fromData(Uint8List.fromList(List.filled(64, 7)), name: 'cover.jpg');

void main() {
  const uid = 'host-uid';
  late FakeFirebaseFirestore db;

  MockFirebaseAuth auth() => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: uid, email: 'h@yovoice.app', displayName: 'Host'),
  );

  setUp(() {
    db = FakeFirebaseFirestore();
  });

  Widget host(Widget child) => MaterialApp(home: child);

  void useSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  CreateRoomScreen build({
    RoomExperience experience = RoomExperience.community,
    RoomImageService? images,
  }) {
    final firebaseAuth = auth();
    return CreateRoomScreen(
      experience: experience,
      roomService: RoomService(firestore: db, auth: firebaseAuth),
      imageService: images ?? _FakeImageService(),
      // Injected too: it constructs a NotificationService, which needs a
      // Firebase app the test does not have.
      experienceService: RoomExperienceService(
        firestore: db,
        auth: firebaseAuth,
        notificationService: NotificationService(
          firestore: db,
          auth: firebaseAuth,
        ),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  group('identity colours', () {
    testWidgets('Community wears violet and Podcast wears coral, on the '
        'same screen', (tester) async {
      useSize(tester, const Size(430, 2000));

      for (final (experience, identity) in <(RoomExperience, SpaceIdentity)>[
        (RoomExperience.community, SpaceIdentity.community),
        (RoomExperience.broadcast, SpaceIdentity.podcast),
      ]) {
        await tester.pumpWidget(host(build(experience: experience)));
        await settle(tester);

        // The step bar's completed segment is the identity's primary.
        final bars = tester
            .widgetList<Container>(find.byType(Container))
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .toList();
        expect(
          bars.any((d) => d.color == identity.primary),
          isTrue,
          reason: '${identity.label} primary missing from the step bar',
        );
        // And the other type's primary must not be anywhere on it.
        final other = experience == RoomExperience.community
            ? SpaceIdentity.podcast
            : SpaceIdentity.community;
        expect(
          bars.any((d) => d.color == other.primary),
          isFalse,
          reason: '${other.label} colour leaked onto ${identity.label}',
        );
      }
    });

    test('the four identities keep their agreed values', () {
      expect(SpaceIdentity.community.primary, const Color(0xFF8A2BE2));
      expect(SpaceIdentity.community.accent, const Color(0xFFC026FF));
      expect(SpaceIdentity.podcast.primary, const Color(0xFFFF3D68));
      expect(SpaceIdentity.podcast.accent, const Color(0xFFFF6B81));
      expect(SpaceIdentity.club.primary, const Color(0xFFD9A441));
      expect(SpaceIdentity.family.primary, const Color(0xFF28D17C));
    });
  });

  group('three-step wizard', () {
    testWidgets('walks Identity → Audience → Experience and keeps what was '
        'typed when stepping back', (tester) async {
      useSize(tester, const Size(430, 2000));
      await tester.pumpWidget(host(build()));
      await settle(tester);

      expect(find.text('Identity'), findsOneWidget);
      expect(find.text('Room cover'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, 'Evening Talk');
      await tester.tap(find.text('Continue'));
      await settle(tester);

      expect(find.text('Intended audience'), findsOneWidget);
      await tester.tap(find.text('Enthusiasts'));
      await settle(tester);

      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(find.text('Conversation style'), findsOneWidget);
      // The summary reflects the earlier steps.
      expect(find.text('Evening Talk'), findsWidgets);
      expect(find.text('Enthusiasts'), findsWidgets);

      // Stepping back twice must not lose the name.
      await tester.tap(find.text('Back'));
      await settle(tester);
      await tester.tap(find.text('Back'));
      await settle(tester);
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField).first).controller
            ?.text,
        'Evening Talk',
      );
    });

    testWidgets('a too-short name blocks leaving the Identity step', (
      tester,
    ) async {
      useSize(tester, const Size(430, 2000));
      await tester.pumpWidget(host(build()));
      await settle(tester);

      await tester.enterText(find.byType(TextFormField).first, 'ab');
      await tester.tap(find.text('Continue'));
      await settle(tester);

      expect(find.text('Enter at least 3 characters'), findsOneWidget);
      expect(find.text('Room cover'), findsOneWidget);
    });

    testWidgets('Podcast shows its own Identity and Experience fields, and '
        'never Community\'s', (tester) async {
      useSize(tester, const Size(430, 2000));
      await tester.pumpWidget(
        host(build(experience: RoomExperience.broadcast)),
      );
      await settle(tester);

      expect(find.text('Show cover'), findsOneWidget);
      expect(find.text('Room cover'), findsNothing);

      await tester.enterText(find.byType(TextFormField).first, 'The Show');
      await tester.enterText(find.byType(TextFormField).at(1), 'Episode one');
      await tester.tap(find.text('Continue'));
      await settle(tester);
      await tester.tap(find.text('Continue'));
      await settle(tester);

      expect(find.text('Show format'), findsOneWidget);
      expect(find.text('Panel'), findsOneWidget);
      expect(find.text('Allow audience to raise hands'), findsOneWidget);
      // Community-only controls must not appear.
      expect(find.text('Conversation style'), findsNothing);
      expect(find.text('Newcomer friendly'), findsNothing);
    });

    testWidgets('Community never shows Podcast-only controls', (tester) async {
      useSize(tester, const Size(430, 2000));
      await tester.pumpWidget(host(build()));
      await settle(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Open room');
      await tester.tap(find.text('Continue'));
      await settle(tester);
      await tester.tap(find.text('Continue'));
      await settle(tester);

      expect(find.text('Conversation style'), findsOneWidget);
      expect(find.text('Show format'), findsNothing);
      expect(find.text('Allow audience to raise hands'), findsNothing);
    });
  });

  group('cover', () {
    testWidgets('select, preview, replace and remove', (tester) async {
      useSize(tester, const Size(430, 2000));
      final images = _FakeImageService(pickResult: _fakeImage());
      await tester.pumpWidget(host(build(images: images)));
      await settle(tester);

      // Nothing chosen yet: the invitation is shown, not a broken image.
      expect(find.text('Choose cover'), findsOneWidget);
      expect(find.byType(Image), findsNothing);

      await tester.tap(find.text('Choose cover'));
      await settle(tester);

      expect(images.pickCalls, 1);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Replace'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);

      await tester.tap(find.text('Replace'));
      await settle(tester);
      expect(images.pickCalls, 2);

      await tester.tap(find.text('Remove'));
      await settle(tester);
      expect(find.byType(Image), findsNothing);
      expect(find.text('Choose cover'), findsOneWidget);
    });

    testWidgets('a failed upload leaves a usable room and says so', (
      tester,
    ) async {
      useSize(tester, const Size(430, 2000));
      final images = _FakeImageService(
        pickResult: _fakeImage(),
        uploadFails: true,
      );
      await tester.pumpWidget(host(build(images: images)));
      await settle(tester);

      await tester.tap(find.text('Choose cover'));
      await settle(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Cover room');
      await tester.tap(find.text('Continue'));
      await settle(tester);
      await tester.tap(find.text('Continue'));
      await settle(tester);
      await tester.tap(find.text('Create Room'));
      await settle(tester);

      // Creation succeeds and then pushes RoomEntryScreen, which needs a
      // Firebase app this test does not have. That is the destination's
      // concern, not this one's — consume it and assert what was written.
      tester.takeException();
      // The room exists even though the cover did not upload.
      final rooms = await db.collection('rooms').get();
      expect(rooms.docs, hasLength(1));
      expect(rooms.docs.single.data()['imageUrl'], isNull);
      expect(images.uploadCalls, 1);
      expect(find.textContaining('cover did not upload'), findsOneWidget);
    });

    testWidgets('nothing uploads when creation is abandoned', (tester) async {
      useSize(tester, const Size(430, 2000));
      final images = _FakeImageService(pickResult: _fakeImage());
      await tester.pumpWidget(host(build(images: images)));
      await settle(tester);

      await tester.tap(find.text('Choose cover'));
      await settle(tester);
      // Walk away without pressing Create.
      await tester.pumpWidget(host(const SizedBox()));
      await settle(tester);

      expect(images.uploadCalls, 0, reason: 'no orphaned upload');
      final rooms = await db.collection('rooms').get();
      expect(rooms.docs, isEmpty);
    });
  });

  group('persisted payload', () {
    testWidgets('a Community room writes exactly its own metadata', (
      tester,
    ) async {
      useSize(tester, const Size(430, 2000));
      await tester.pumpWidget(host(build()));
      await settle(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Study Hall');
      await tester.tap(find.text('Continue'));
      await settle(tester);
      await tester.tap(find.text('Professionals'));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Add a tag'),
          'dart');
      await tester.tap(find.text('Add'));
      await settle(tester);
      await tester.tap(find.text('Continue'));
      await settle(tester);
      await tester.ensureVisible(find.text('Focused'));
      await settle(tester);
      await tester.tap(find.text('Focused'));
      await settle(tester);
      await tester.tap(find.text('Create Room'));
      await settle(tester);

      // Creation succeeds and then pushes RoomEntryScreen, which needs a
      // Firebase app this test does not have. That is the destination's
      // concern, not this one's — consume it and assert what was written.
      tester.takeException();
      final data = (await db.collection('rooms').get()).docs.single.data();
      expect(data['targetAudience'], 'professionals');
      expect(data['topicTags'], ['dart']);
      expect(data['conversationStyle'], 'focused');
      // Podcast-only field must be absent, not null.
      expect(data.containsKey('showFormat'), isFalse);
    });

    testWidgets('a Podcast room writes exactly its own metadata', (
      tester,
    ) async {
      useSize(tester, const Size(430, 2000));
      await tester.pumpWidget(
        host(build(experience: RoomExperience.broadcast)),
      );
      await settle(tester);

      await tester.enterText(find.byType(TextFormField).first, 'The Show');
      await tester.enterText(find.byType(TextFormField).at(1), 'Episode one');
      await tester.tap(find.text('Continue'));
      await settle(tester);
      await tester.tap(find.text('Continue'));
      await settle(tester);
      await tester.ensureVisible(find.text('Interview'));
      await settle(tester);
      await tester.tap(find.text('Interview'));
      await settle(tester);
      // The AppBar title and the CTA share this label; the CTA is last.
      await tester.tap(find.text('Create Podcast Room').last);
      await settle(tester);

      // Creation succeeds and then pushes RoomEntryScreen, which needs a
      // Firebase app this test does not have. That is the destination's
      // concern, not this one's — consume it and assert what was written.
      tester.takeException();
      final data = (await db.collection('rooms').get()).docs.single.data();
      expect(data['showFormat'], 'interview');
      expect(data.containsKey('conversationStyle'), isFalse);
      expect(data.containsKey('newcomerFriendly'), isFalse);
    });

    test('tag normalisation matches what rules will accept', () {
      expect(
        RoomMetadataLimits.normalizeTags(['a', 'b', 'c', 'd']),
        ['a', 'b', 'c'],
      );
      expect(RoomMetadataLimits.normalizeTags(['x', 'X', ' x ']), ['x']);
      expect(RoomMetadataLimits.normalizeTags(['', '   ']), isEmpty);
      expect(
        RoomMetadataLimits.normalizeTags(['y' * 40]),
        isEmpty,
        reason: 'an over-long tag is dropped, not truncated',
      );
    });

    test('legacy documents load with safe defaults', () {
      expect(TargetAudience.fromValue(null), TargetAudience.everyone);
      expect(TargetAudience.fromValue('vip'), TargetAudience.everyone);
      expect(ConversationStyle.fromValue(null), isNull);
      expect(ShowFormat.fromValue('livestream'), isNull);
    });
  });

  group('responsive', () {
    for (final width in const [320.0, 390.0, 430.0, 1440.0]) {
      testWidgets('no overflow at ${width.toInt()}pt', (tester) async {
        useSize(tester, Size(width, 2000));
        await tester.pumpWidget(host(build()));
        await settle(tester);
        expect(tester.takeException(), isNull);

        await tester.enterText(find.byType(TextFormField).first, 'Room name');
        await tester.tap(find.text('Continue'));
        await settle(tester);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Continue'));
        await settle(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
