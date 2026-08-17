import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/models/club_invite.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';

/// Client lifecycle regressions for Family Rooms.
///
/// The authorization boundary is emulator-tested in
/// `firestore-tests/rules.test.js`; these cases independently pin the exact
/// multi-document shape emitted by ClubService and its idempotent reopen path.
void main() {
  late FakeFirebaseFirestore firestore;

  MockFirebaseAuth authFor(String uid, {String? displayName}) =>
      MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
          uid: uid,
          email: '$uid@yovoice.app',
          displayName: displayName ?? uid,
        ),
      );

  ClubService serviceFor(MockFirebaseAuth auth) => ClubService(
    firestore: firestore,
    auth: auth,
    storage: MockFirebaseStorage(),
    notificationService: NotificationService(firestore: firestore, auth: auth),
  );

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  group('Family Room create and reopen', () {
    test(
      'a free account creates the complete deterministic family graph',
      () async {
        final service = serviceFor(authFor('parent', displayName: 'Parent'));

        final family = await service.createFamilyRoom(
          name: '  The Family  ',
          description: '  Our private place  ',
          defaultLanguage: '  Polish  ',
        );

        expect(family.id, 'family_parent');
        expect(family.name, 'The Family');
        expect(family.description, 'Our private place');
        expect(family.defaultLanguage, 'Polish');
        expect(family.type, ClubType.family);
        expect(family.privacy, ClubPrivacy.inviteOnly);
        expect(family.memberCount, 1);
        expect(family.onlineCount, 1);

        final root = await firestore.doc('clubs/family_parent').get();
        expect(root.data(), containsPair('ownerId', 'parent'));
        expect(root.data(), containsPair('type', 'family'));
        expect(root.data(), containsPair('privacy', 'inviteOnly'));
        expect(
          root.data(),
          containsPair('loungeRoomId', 'club_lounge_family_parent'),
        );

        final owner = await firestore
            .doc('clubs/family_parent/members/parent')
            .get();
        expect(owner.data(), containsPair('role', 'owner'));
        expect(owner.data(), containsPair('userId', 'parent'));

        final ownerMirror = await firestore
            .doc('users/parent/clubs/family_parent')
            .get();
        expect(ownerMirror.data(), containsPair('role', 'owner'));
        expect(ownerMirror.data(), containsPair('clubId', 'family_parent'));

        final channels = await firestore
            .collection('clubs/family_parent/channels')
            .get();
        expect(channels.docs, hasLength(3));
        expect(
          channels.docs.map((document) => document.data()['name']).toSet(),
          {'general', 'announcements', 'Family Lounge'},
        );

        final lounge = await firestore
            .doc('rooms/club_lounge_family_parent')
            .get();
        expect(lounge.data(), containsPair('clubId', 'family_parent'));
        expect(lounge.data(), containsPair('visibility', 'private'));
        expect(lounge.data(), containsPair('roomKind', 'clubLounge'));
        expect(lounge.data(), containsPair('membersCanStartVoice', true));
      },
    );

    test(
      'reopening returns the existing room and creates no duplicate graph',
      () async {
        final service = serviceFor(authFor('parent', displayName: 'Parent'));
        final created = await service.createFamilyRoom(
          name: 'The Family',
          description: 'Original',
        );
        final originalChannels = await firestore
            .collection('clubs/family_parent/channels')
            .get();

        final reopened = await service.createFamilyRoom(
          name: 'A second family attempt',
          description: 'Must not overwrite the first room',
        );

        expect(reopened.id, created.id);
        expect(reopened.name, 'The Family');
        expect(reopened.description, 'Original');
        expect((await firestore.collection('clubs').get()).docs, hasLength(1));
        expect((await firestore.collection('rooms').get()).docs, hasLength(1));
        final reopenedChannels = await firestore
            .collection('clubs/family_parent/channels')
            .get();
        expect(reopenedChannels.docs, hasLength(3));
        expect(
          reopenedChannels.docs.map((document) => document.id).toSet(),
          originalChannels.docs.map((document) => document.id).toSet(),
        );
      },
    );
  });

  group('Family invitations', () {
    const invite = ClubInvite(
      clubId: 'family_parent',
      clubName: 'The Family',
      clubAvatarUrl: null,
      inviteeId: 'sibling',
      inviterId: 'parent',
      inviterName: 'Parent',
      createdAt: null,
    );

    Future<void> seedFamilyAndInvite() async {
      await firestore.doc('users/sibling').set({
        'displayName': 'Sibling',
        'photoUrl': null,
      });
      await firestore.doc('clubs/family_parent').set({
        'name': 'The Family',
        'description': '',
        'ownerId': 'parent',
        'ownerName': 'Parent',
        'avatarUrl': null,
        'bannerUrl': null,
        'privacy': 'inviteOnly',
        'type': 'family',
        'defaultLanguage': 'English',
        'memberCount': 1,
        'onlineCount': 1,
        'defaultChatChannelId': 'general',
        'defaultVoiceChannelId': 'lounge',
        'announcementChannelId': 'announcements',
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });
      await firestore.doc('clubs/family_parent/invites/sibling').set({
        'clubId': 'family_parent',
        'clubName': 'The Family',
        'clubAvatarUrl': null,
        'inviteeId': 'sibling',
        'inviterId': 'parent',
        'inviterName': 'Parent',
        'createdAt': Timestamp.now(),
      });
    }

    test(
      'acceptance consumes the invitation and atomically joins the family',
      () async {
        await seedFamilyAndInvite();
        final service = serviceFor(authFor('sibling', displayName: 'Sibling'));

        await service.acceptClubInvite(invite);

        expect(
          (await firestore.doc('clubs/family_parent/invites/sibling').get())
              .exists,
          isFalse,
        );
        final member = await firestore
            .doc('clubs/family_parent/members/sibling')
            .get();
        expect(member.data(), containsPair('userId', 'sibling'));
        expect(member.data(), containsPair('role', 'member'));
        expect(member.data(), containsPair('invitedBy', 'parent'));
        final mirror = await firestore
            .doc('users/sibling/clubs/family_parent')
            .get();
        expect(mirror.data(), containsPair('clubId', 'family_parent'));
        expect(mirror.data(), containsPair('role', 'member'));
        final root = await firestore.doc('clubs/family_parent').get();
        expect(root.data(), containsPair('memberCount', 2));
        expect(root.data(), containsPair('onlineCount', 2));
      },
    );

    test('declining removes only the invitation and does not join', () async {
      await seedFamilyAndInvite();
      final service = serviceFor(authFor('sibling', displayName: 'Sibling'));

      await service.declineClubInvite(invite);

      expect(
        (await firestore.doc('clubs/family_parent/invites/sibling').get())
            .exists,
        isFalse,
      );
      expect(
        (await firestore.doc('clubs/family_parent/members/sibling').get())
            .exists,
        isFalse,
      );
      expect(
        (await firestore.doc('users/sibling/clubs/family_parent').get()).exists,
        isFalse,
      );
      final root = await firestore.doc('clubs/family_parent').get();
      expect(root.data(), containsPair('memberCount', 1));
      expect(root.data(), containsPair('onlineCount', 1));
    });

    test(
      'another account cannot accept or decline someone else\'s invitation',
      () async {
        await seedFamilyAndInvite();
        final service = serviceFor(authFor('outsider'));

        await expectLater(
          service.acceptClubInvite(invite),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          service.declineClubInvite(invite),
          throwsA(isA<StateError>()),
        );

        expect(
          (await firestore.doc('clubs/family_parent/invites/sibling').get())
              .exists,
          isTrue,
        );
      },
    );
  });
}
