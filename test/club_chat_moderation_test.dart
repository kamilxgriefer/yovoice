import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

import 'package:yovoice/features/clubs/data/models/club_channel.dart';
import 'package:yovoice/features/clubs/data/models/club_chat_authority.dart';
import 'package:yovoice/features/clubs/data/models/club_member.dart';
import 'package:yovoice/features/clubs/data/models/club_message.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_chat_screen.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_context_action.dart';

/// Club chat moderation: a club owner or moderator can remove somebody
/// else's message, and the affordance offered by the screen matches
/// exactly what `firestore.rules` accepts.
///
/// The two halves have to agree or the feature is worse than absent — a
/// confirmation dialog that always ends in a permission denial is the
/// "looks fixed, isn't" shape this covers against. So these tests assert
/// BOTH sides against the same rule:
///
///  * the WRITE carries `deletedBy` and `deletedAt` (the moderator branch
///    is refused without them) alongside the `content`/`isDeleted`/
///    `editedAt` the author branch already sent;
///  * the AFFORDANCE appears for moderator power and above on other
///    people's messages, and never on the club owner's, whose messages
///    only staff tooling reaches.
///
/// The rules themselves are covered where they are enforced, in
/// firestore-tests/rules.test.js.
void main() {
  const clubId = 'club-1';
  const channelId = 'general';
  const ownerUid = 'owner-uid';
  const modUid = 'mod-uid';
  const memberUid = 'member-uid';
  const otherUid = 'other-uid';

  late FakeFirebaseFirestore db;
  late PublicIdentityRepository originalIdentityRepository;
  late Map<String, String> identityRoles;
  late Set<String> vipUids;

  MockFirebaseAuth authAs(String uid) => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: uid, email: '$uid@yovoice.app', displayName: uid),
  );

  ClubChatService serviceAs(String uid) =>
      ClubChatService(firestore: db, auth: authAs(uid));

  Future<void> seedClub({
    String ownerId = ownerUid,
    Map<String, String> roles = const {
      ownerUid: 'owner',
      modUid: 'moderator',
      memberUid: 'member',
      otherUid: 'member',
    },
  }) async {
    await db.collection('clubs').doc(clubId).set({
      'name': 'Test Club',
      'ownerId': ownerId,
      'ownerName': 'Owner',
      'privacy': 'public',
      'memberCount': roles.length,
    });
    for (final entry in roles.entries) {
      await db
          .collection('clubs')
          .doc(clubId)
          .collection('members')
          .doc(entry.key)
          .set({
            'userId': entry.key,
            'displayName': entry.key,
            'role': entry.value,
          });
    }
  }

  Future<void> seedMessage({
    required String id,
    required String senderId,
    required String content,
    String? senderName,
    int minute = 0,
    bool isDeleted = false,
    String? deletedBy,
    String? deletedByRole,
  }) async {
    await db
        .collection('clubs')
        .doc(clubId)
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .doc(id)
        .set({
          'clubId': clubId,
          'channelId': channelId,
          'senderId': senderId,
          'senderName': senderName ?? senderId,
          'senderPhotoUrl': null,
          'content': content,
          'sentAt': Timestamp.fromDate(DateTime.utc(2026, 3, 1, 12, minute)),
          'editedAt': null,
          'isDeleted': isDeleted,
          'deletedBy': ?deletedBy,
          'deletedByRole': ?deletedByRole,
        });
  }

  Future<Map<String, dynamic>> readMessage(String id) async {
    final snapshot = await db
        .collection('clubs')
        .doc(clubId)
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .doc(id)
        .get();
    return snapshot.data() ?? <String, dynamic>{};
  }

  Future<ClubMessage> loadMessage(String id) async {
    final snapshot = await db
        .collection('clubs')
        .doc(clubId)
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .doc(id)
        .get();
    return ClubMessage.fromFirestore(
      clubId: clubId,
      channelId: channelId,
      document: snapshot,
    );
  }

  setUp(() {
    db = FakeFirebaseFirestore();
    identityRoles = <String, String>{};
    vipUids = <String>{};
    // The message tile resolves identity badges through the shared
    // singleton; a scripted fetcher keeps the widget tests off Firebase
    // and deterministic.
    originalIdentityRepository = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: authAs(modUid),
      // PublicIdentity.fromWire reads `staffRole` and `isVip`. An earlier
      // version of this fixture sent `role`/`vip`, so EVERY badge fell
      // back to the shortest possible label and the layout cases below
      // were never actually exercised.
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids)
          uid: {
            'staffRole': identityRoles[uid] ?? 'user',
            'isVip': vipUids.contains(uid),
            'uid': uid,
          },
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentityRepository;
  });

  // -----------------------------------------------------------------
  // THE WRITE SHAPE
  // -----------------------------------------------------------------

  group('ClubChatService.deleteMessage write shape', () {
    test('a self-retraction sends the full removal shape — the same one a '
        'moderator sends, attribution included', () async {
      await seedClub();
      await seedMessage(id: 'm1', senderId: memberUid, content: 'oops');

      await serviceAs(memberUid).deleteMessage(
        clubId: clubId,
        channelId: channelId,
        message: await loadMessage('m1'),
      );

      final data = await readMessage('m1');
      expect(data['content'], '');
      expect(data['isDeleted'], isTrue);
      // The rules require editedAt == request.time, not merely permit it.
      expect(data['editedAt'], isA<Timestamp>());
      expect(data['deletedBy'], memberUid);
      expect(data['deletedAt'], isA<Timestamp>());
      // Authorship and the moment it was said are untouched.
      expect(data['senderId'], memberUid);
      expect(data['sentAt'], isA<Timestamp>());
    });

    test('a moderator removing another member\'s message stamps the '
        'MODERATOR as the actor', () async {
      await seedClub();
      await seedMessage(id: 'm1', senderId: memberUid, content: 'abuse');

      await serviceAs(modUid).deleteMessage(
        clubId: clubId,
        channelId: channelId,
        message: await loadMessage('m1'),
      );

      final data = await readMessage('m1');
      expect(data['content'], '');
      expect(data['isDeleted'], isTrue);
      expect(data['editedAt'], isA<Timestamp>());
      expect(data['deletedAt'], isA<Timestamp>());
      expect(
        data['deletedBy'],
        modUid,
        reason: 'the moderator branch is refused without attribution',
      );
      expect(data['senderId'], memberUid, reason: 'authorship is frozen');
    });

    test('every role at moderator power and above can remove a member\'s '
        'message', () async {
      await seedClub(
        roles: const {
          ownerUid: 'owner',
          'co-uid': 'coOwner',
          'admin-uid': 'admin',
          modUid: 'moderator',
          memberUid: 'member',
        },
      );
      for (final actor in const [ownerUid, 'co-uid', 'admin-uid', modUid]) {
        await seedMessage(id: 'm-$actor', senderId: memberUid, content: actor);
        await serviceAs(actor).deleteMessage(
          clubId: clubId,
          channelId: channelId,
          message: await loadMessage('m-$actor'),
        );
        expect((await readMessage('m-$actor'))['deletedBy'], actor);
      }
    });
  });

  // -----------------------------------------------------------------
  // WHOSE MESSAGE IS REACHABLE
  // -----------------------------------------------------------------

  group('ClubChatService.deleteMessage authority', () {
    test('a moderator cannot remove the club owner\'s message, and nothing '
        'is written', () async {
      await seedClub();
      await seedMessage(id: 'm1', senderId: ownerUid, content: 'announcement');

      await expectLater(
        serviceAs(modUid).deleteMessage(
          clubId: clubId,
          channelId: channelId,
          message: await loadMessage('m1'),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('YO Voice staff'),
          ),
        ),
      );

      final data = await readMessage('m1');
      expect(data['content'], 'announcement');
      expect(data['isDeleted'], isFalse);
      expect(data.containsKey('deletedBy'), isFalse);
    });

    test('the club owner can still retract their OWN message', () async {
      await seedClub();
      await seedMessage(id: 'm1', senderId: ownerUid, content: 'my typo');

      await serviceAs(ownerUid).deleteMessage(
        clubId: clubId,
        channelId: channelId,
        message: await loadMessage('m1'),
      );

      expect((await readMessage('m1'))['deletedBy'], ownerUid);
    });

    test('an ordinary member cannot remove somebody else\'s message', () async {
      await seedClub();
      await seedMessage(id: 'm1', senderId: otherUid, content: 'hello');

      await expectLater(
        serviceAs(memberUid).deleteMessage(
          clubId: clubId,
          channelId: channelId,
          message: await loadMessage('m1'),
        ),
        throwsA(isA<StateError>()),
      );
      expect((await readMessage('m1'))['content'], 'hello');
    });

    test('a non-member is refused before any club document is read', () async {
      await seedClub();
      await seedMessage(id: 'm1', senderId: memberUid, content: 'hello');

      await expectLater(
        serviceAs('stranger-uid').deleteMessage(
          clubId: clubId,
          channelId: channelId,
          message: await loadMessage('m1'),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('not a member'),
          ),
        ),
      );
    });

    test('a message another moderator removed in the meantime is refused '
        'with copy that says so, from the SERVER copy rather than the '
        'rendered tile', () async {
      await seedClub();
      await seedMessage(id: 'm1', senderId: memberUid, content: 'abuse');
      final stale = await loadMessage('m1');

      // Somebody else gets there first.
      await serviceAs(ownerUid).deleteMessage(
        clubId: clubId,
        channelId: channelId,
        message: stale,
      );

      await expectLater(
        serviceAs(modUid).deleteMessage(
          clubId: clubId,
          channelId: channelId,
          message: stale,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('already been removed'),
          ),
        ),
      );
      // The first actor keeps the attribution.
      expect((await readMessage('m1'))['deletedBy'], ownerUid);
    });

    test('a message that no longer exists is refused with copy that says '
        'so', () async {
      await seedClub();
      await seedMessage(id: 'm1', senderId: memberUid, content: 'abuse');
      final stale = await loadMessage('m1');
      await db
          .collection('clubs')
          .doc(clubId)
          .collection('channels')
          .doc(channelId)
          .collection('messages')
          .doc('m1')
          .delete();

      await expectLater(
        serviceAs(modUid).deleteMessage(
          clubId: clubId,
          channelId: channelId,
          message: stale,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('no longer exists'),
          ),
        ),
      );
    });

    test('a tile that lies about authorship cannot pick the author branch — '
        'the stored senderId decides it', () async {
      await seedClub();
      await seedMessage(id: 'm1', senderId: ownerUid, content: 'announcement');
      final real = await loadMessage('m1');
      // What a stale or tampered render might hand the service.
      final spoofed = ClubMessage(
        id: real.id,
        clubId: real.clubId,
        channelId: real.channelId,
        senderId: memberUid,
        senderName: real.senderName,
        senderPhotoUrl: null,
        content: real.content,
        sentAt: real.sentAt,
        editedAt: null,
        isDeleted: false,
      );

      await expectLater(
        serviceAs(modUid).deleteMessage(
          clubId: clubId,
          channelId: channelId,
          message: spoofed,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('YO Voice staff'),
          ),
        ),
      );
      expect((await readMessage('m1'))['content'], 'announcement');
    });

    test('an already-removed message cannot be removed again — the rules '
        'only accept the live -> removed transition, so a second attempt '
        'would be a denial rather than a no-op', () async {
      await seedClub();
      await seedMessage(
        id: 'm1',
        senderId: memberUid,
        content: '',
        isDeleted: true,
        deletedBy: modUid,
      );

      await expectLater(
        serviceAs(modUid).deleteMessage(
          clubId: clubId,
          channelId: channelId,
          message: await loadMessage('m1'),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('already been removed'),
          ),
        ),
      );
    });
  });

  // -----------------------------------------------------------------
  // THE POLICY OBJECT BOTH HALVES SHARE
  // -----------------------------------------------------------------

  group('ClubChatAuthority', () {
    ClubMessage messageFrom(String senderId, {bool isDeleted = false}) =>
        ClubMessage(
          id: 'm',
          clubId: clubId,
          channelId: channelId,
          senderId: senderId,
          senderName: senderId,
          senderPhotoUrl: null,
          content: 'text',
          sentAt: DateTime.utc(2026, 3, 1),
          editedAt: null,
          isDeleted: isDeleted,
        );

    test('a moderator reaches members but not the club owner', () {
      const authority = ClubChatAuthority(
        viewerId: modUid,
        role: ClubRole.moderator,
        clubOwnerId: ownerUid,
        viewerEmailVerified: true,
      );
      expect(authority.canRemove(messageFrom(memberUid)), isTrue);
      expect(authority.canRemove(messageFrom(ownerUid)), isFalse);
      expect(authority.canRemove(messageFrom(modUid)), isTrue);
      expect(authority.isModeratingOthers(messageFrom(memberUid)), isTrue);
      expect(authority.isModeratingOthers(messageFrom(modUid)), isFalse);
    });

    test('a member and a guest reach only their own message', () {
      for (final role in const [ClubRole.member, ClubRole.guest]) {
        final authority = ClubChatAuthority(
          viewerId: memberUid,
          role: role,
          clubOwnerId: ownerUid,
        );
        expect(authority.canRemove(messageFrom(memberUid)), isTrue);
        expect(authority.canRemove(messageFrom(otherUid)), isFalse);
      }
    });

    test('an unknown club owner withholds moderation but never blocks a '
        'self-retraction', () {
      const authority = ClubChatAuthority(
        viewerId: modUid,
        role: ClubRole.moderator,
        viewerEmailVerified: true,
      );
      expect(authority.canRemove(messageFrom(memberUid)), isFalse);
      expect(authority.canRemove(messageFrom(modUid)), isTrue);
    });

    test('an unresolved role permits exactly what the screen permitted '
        'before moderation existed', () {
      const authority = ClubChatAuthority(viewerId: memberUid);
      expect(authority.canRemove(messageFrom(memberUid)), isTrue);
      expect(authority.canRemove(messageFrom(otherUid)), isFalse);
    });

    test('an unverified email withholds MODERATION but never a member\'s '
        'own retraction — the rules gate the two branches differently', () {
      const authority = ClubChatAuthority(
        viewerId: modUid,
        role: ClubRole.moderator,
        clubOwnerId: ownerUid,
      );
      expect(authority.canRemove(messageFrom(memberUid)), isFalse);
      expect(
        authority.removalRefusal(messageFrom(memberUid)),
        contains('Verify your email'),
      );
      expect(authority.canRemove(messageFrom(modUid)), isTrue);
    });

    test('a communication mute withholds MODERATION but never a member\'s '
        'own retraction — a sanction on speech must not trap what they '
        'already said', () {
      const authority = ClubChatAuthority(
        viewerId: modUid,
        role: ClubRole.moderator,
        clubOwnerId: ownerUid,
        viewerEmailVerified: true,
        viewerIsCommunicationMuted: true,
      );
      expect(authority.canRemove(messageFrom(memberUid)), isFalse);
      expect(
        authority.removalRefusal(messageFrom(memberUid)),
        contains('muted'),
      );
      expect(authority.canRemove(messageFrom(modUid)), isTrue);
    });

    test('a signed-out viewer removes nothing', () {
      const authority = ClubChatAuthority.signedOut();
      expect(authority.canRemove(messageFrom(memberUid)), isFalse);
      expect(
        authority.removalRefusal(messageFrom(memberUid)),
        contains('signed in'),
      );
    });

    test('a removed message is refused for everyone', () {
      const authority = ClubChatAuthority(
        viewerId: ownerUid,
        role: ClubRole.owner,
        clubOwnerId: ownerUid,
        viewerEmailVerified: true,
      );
      expect(
        authority.canRemove(messageFrom(memberUid, isDeleted: true)),
        isFalse,
      );
    });
  });

  // -----------------------------------------------------------------
  // THE MESSAGE MODEL
  // -----------------------------------------------------------------

  group('ClubMessage.deletedBy', () {
    test('a removal by somebody other than the author is legible as '
        'moderation; an unattributed one is not', () async {
      await seedMessage(
        id: 'byMod',
        senderId: memberUid,
        content: '',
        isDeleted: true,
        deletedBy: modUid,
      );
      await seedMessage(
        id: 'bySelf',
        senderId: memberUid,
        content: '',
        isDeleted: true,
        deletedBy: memberUid,
      );
      // A removal written before the client stamped attribution.
      await seedMessage(
        id: 'legacy',
        senderId: memberUid,
        content: '',
        isDeleted: true,
      );

      expect((await loadMessage('byMod')).wasRemovedByModerator, isTrue);
      expect((await loadMessage('bySelf')).wasRemovedByModerator, isFalse);
      expect((await loadMessage('legacy')).deletedBy, isNull);
      expect((await loadMessage('legacy')).wasRemovedByModerator, isFalse);
    });
  });

  // -----------------------------------------------------------------
  // THE AFFORDANCE
  // -----------------------------------------------------------------

  group('ClubChatScreen removal affordance', () {
    const channel = ClubChannel(
      id: channelId,
      clubId: clubId,
      name: 'general',
      type: ClubChannelType.chat,
      position: 0,
      isPrivate: false,
      createdBy: ownerUid,
      createdAt: null,
    );

    Widget host(String uid, {double textScale = 1}) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ClubChatScreen(
        clubId: clubId,
        clubName: 'Test Club',
        channel: channel,
        firestore: db,
        auth: authAs(uid),
      ),
    );

    void useSurface(WidgetTester tester, Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    /// Whether the screen OFFERS removal on the tile showing [text].
    ///
    /// [AccessibleContextAction] is built for every tile and renders its
    /// child untouched when there is no action, so a null `onOpen` is
    /// exactly "no affordance" — no long press, no right click, no
    /// keyboard activation, and no semantics button.
    bool offeredOn(WidgetTester tester, String text) {
      final action = tester.widget<AccessibleContextAction>(
        find.ancestor(
          of: find.text(text),
          matching: find.byType(AccessibleContextAction),
        ),
      );
      return action.onOpen != null;
    }

    testWidgets('a moderator is offered removal on a member\'s message and '
        'never on the club owner\'s', (tester) async {
      useSurface(tester, const Size(390, 844));
      await seedClub();
      await seedMessage(id: 'm1', senderId: memberUid, content: 'abuse');
      await seedMessage(
        id: 'm2',
        senderId: ownerUid,
        content: 'club announcement',
        minute: 1,
      );
      await seedMessage(id: 'm3', senderId: modUid, content: 'mine', minute: 2);

      await tester.pumpWidget(host(modUid));
      await settle(tester);

      expect(offeredOn(tester, 'abuse'), isTrue);
      expect(offeredOn(tester, 'mine'), isTrue);

      // The owner's message still responds — silence reads as a broken
      // gesture — but it explains rather than confirming, so no dialog
      // can be raised for a write the rules would refuse.
      expect(offeredOn(tester, 'club announcement'), isTrue);
      await tester.longPress(find.text('club announcement'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('YO Voice staff'), findsOneWidget);
    });

    testWidgets('an ordinary member is offered removal only on their own '
        'message', (tester) async {
      useSurface(tester, const Size(390, 844));
      await seedClub();
      await seedMessage(id: 'm1', senderId: otherUid, content: 'theirs');
      await seedMessage(id: 'm2', senderId: memberUid, content: 'ours', minute: 1);

      await tester.pumpWidget(host(memberUid));
      await settle(tester);

      expect(offeredOn(tester, 'theirs'), isFalse);
      expect(offeredOn(tester, 'ours'), isTrue);
    });

    testWidgets('the club owner is offered removal on a moderator\'s message',
        (tester) async {
      useSurface(tester, const Size(390, 844));
      await seedClub();
      await seedMessage(id: 'm1', senderId: modUid, content: 'mod said this');

      await tester.pumpWidget(host(ownerUid));
      await settle(tester);

      expect(offeredOn(tester, 'mod said this'), isTrue);
    });

    testWidgets('an already-removed message offers nothing to anyone', (
      tester,
    ) async {
      useSurface(tester, const Size(390, 844));
      await seedClub();
      await seedMessage(
        id: 'm1',
        senderId: memberUid,
        content: '',
        isDeleted: true,
        deletedBy: modUid,
      );

      await tester.pumpWidget(host(modUid));
      await settle(tester);

      expect(offeredOn(tester, 'Removed by a club moderator'), isFalse);
    });

    testWidgets('a moderator removal is legible in the room; a retraction '
        'stays an ordinary deletion', (tester) async {
      useSurface(tester, const Size(390, 844));
      await seedClub();
      await seedMessage(
        id: 'm1',
        senderId: memberUid,
        content: '',
        isDeleted: true,
        deletedBy: modUid,
      );
      await seedMessage(
        id: 'm2',
        senderId: otherUid,
        content: '',
        isDeleted: true,
        deletedBy: otherUid,
        minute: 1,
      );

      await tester.pumpWidget(host(memberUid));
      await settle(tester);

      expect(find.text('Removed by a club moderator'), findsOneWidget);
      expect(find.text('Message deleted'), findsOneWidget);
    });

    testWidgets('the gate is identical at phone, tablet and desktop widths — '
        'authority is shared state, not presentation', (tester) async {
      for (final size in const [
        Size(390, 844),
        Size(834, 1112),
        Size(1440, 900),
      ]) {
        db = FakeFirebaseFirestore();
        await seedClub();
        await seedMessage(id: 'm1', senderId: memberUid, content: 'abuse');
        await seedMessage(
          id: 'm2',
          senderId: ownerUid,
          content: 'club announcement',
          minute: 1,
        );

        useSurface(tester, size);
        await tester.pumpWidget(host(modUid));
        await settle(tester);

        expect(offeredOn(tester, 'abuse'), isTrue, reason: '$size');
        await tester.longPress(find.text('club announcement'));
        await settle(tester);
        expect(find.byType(AlertDialog), findsNothing, reason: '$size');
        expect(tester.takeException(), isNull, reason: '$size');
      }
    });

    testWidgets('long content and a long sender name stay inside the tile at '
        'every width', (tester) async {
      final longName = 'A ${'very ' * 12}long club member name';
      final longContent = List.filled(40, 'wall-of-text').join(' ');

      for (final size in const [
        Size(320, 568),
        Size(834, 1112),
        Size(1440, 900),
      ]) {
        db = FakeFirebaseFirestore();
        await seedClub();
        await seedMessage(
          id: 'm1',
          senderId: memberUid,
          senderName: longName,
          content: longContent,
        );

        useSurface(tester, size);
        await tester.pumpWidget(host(modUid));
        await settle(tester);

        expect(find.text(longContent), findsOneWidget, reason: '$size');
        expect(tester.takeException(), isNull, reason: '$size');
      }
    });

    testWidgets('confirming the moderator dialog completes the removal — the '
        'affordance, the dialog and the write agree', (tester) async {
      useSurface(tester, const Size(390, 844));
      await seedClub();
      await seedMessage(id: 'm1', senderId: memberUid, content: 'abuse');

      await tester.pumpWidget(host(modUid));
      await settle(tester);

      await tester.longPress(find.text('abuse'));
      await settle(tester);

      expect(find.text('Remove this message?'), findsOneWidget);
      expect(find.textContaining('records your account'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await settle(tester);

      final data = await readMessage('m1');
      expect(data['isDeleted'], isTrue);
      expect(data['deletedBy'], modUid);
      expect(data['content'], '');
    });

    testWidgets('a self-retraction gets the retraction dialog, not the '
        'moderation one', (tester) async {
      useSurface(tester, const Size(390, 844));
      await seedClub();
      await seedMessage(id: 'm1', senderId: modUid, content: 'my own words');

      await tester.pumpWidget(host(modUid));
      await settle(tester);

      await tester.longPress(find.text('my own words'));
      await settle(tester);

      expect(find.text('Delete message?'), findsOneWidget);
      expect(find.text('Remove this message?'), findsNothing);
    });

    testWidgets('a wide staff badge and a long name never erase the sender '
        'or overflow the row', (tester) async {
      // The badges are what broke this: a MODERATOR or SUPER MODERATOR
      // pill beside a VIP one used to be laid out unbounded next to a
      // name capped at half the bubble, erasing the name to zero width
      // and overflowing at DEFAULT text size. The moderator identifies
      // their target from this line.
      const longName = 'Aleksandra Bartholomew Nowakowska-Wiśniewska';
      for (final size in const [
        Size(320, 568),
        Size(390, 844),
        Size(1440, 900),
      ]) {
        for (final scale in const [1.0, 1.3, 2.0]) {
          db = FakeFirebaseFirestore();
          identityRoles = {memberUid: 'superModerator'};
          vipUids = {memberUid};
          await seedClub();
          await seedMessage(
            id: 'm1',
            senderId: memberUid,
            senderName: longName,
            content: 'a message to identify',
          );

          useSurface(tester, size);
          await tester.pumpWidget(host(modUid, textScale: scale));
          await settle(tester);

          final reason = '$size @$scale';
          expect(tester.takeException(), isNull, reason: reason);
          expect(find.text(longName), findsOneWidget, reason: reason);
          expect(
            tester.getSize(find.text(longName)).width,
            greaterThan(0),
            reason: reason,
          );
        }
      }
    });

    testWidgets('the moderation dialog scrolls instead of silently '
        'swallowing the sentence that says what it does', (tester) async {
      // AlertDialog wraps non-scrollable content in a Flexible, so an
      // over-tall body is CLIPPED with no exception and no overflow
      // stripe — the vanished sentence being the one that names the
      // action and says it is recorded.
      for (final scale in const [2.0, 3.0]) {
        db = FakeFirebaseFirestore();
        await seedClub();
        await seedMessage(id: 'm1', senderId: memberUid, content: 'abuse');

        useSurface(tester, const Size(320, 568));
        await tester.pumpWidget(host(modUid, textScale: scale));
        await settle(tester);
        await tester.longPress(find.text('abuse'));
        await settle(tester);

        expect(
          tester.widget<AlertDialog>(find.byType(AlertDialog)).scrollable,
          isTrue,
          reason: 'scale $scale',
        );
        expect(tester.takeException(), isNull, reason: 'scale $scale');
      }
    });

    testWidgets('the dialog keeps a readable measure on desktop instead of '
        'letting a display name drive its width', (tester) async {
      useSurface(tester, const Size(1440, 900));
      await seedClub();
      await seedMessage(
        id: 'm1',
        senderId: memberUid,
        senderName: 'Bartholomew Maximilian Fitzgerald-Wetherington III',
        content: 'abuse',
      );

      await tester.pumpWidget(host(modUid));
      await settle(tester);
      await tester.longPress(find.text('abuse'));
      await settle(tester);

      // The body is the readable measure: uncapped, it became a single
      // 700-1200 px line whose width a display name could drive.
      final bodyWidth = tester
          .getSize(find.textContaining('records your account'))
          .width;
      expect(bodyWidth, lessThanOrEqualTo(480));
      expect(bodyWidth, greaterThan(0));
    });

    testWidgets('a YO Voice staff redaction is not reported as a club '
        'moderator\'s act', (tester) async {
      useSurface(tester, const Size(390, 844));
      await seedClub();
      await seedMessage(
        id: 'm1',
        senderId: memberUid,
        content: '',
        isDeleted: true,
        deletedBy: 'staff-uid',
        deletedByRole: 'superAdmin',
      );
      await seedMessage(
        id: 'm2',
        senderId: otherUid,
        content: '',
        isDeleted: true,
        deletedBy: modUid,
        minute: 1,
      );

      await tester.pumpWidget(host(memberUid));
      await settle(tester);

      // Moderators are told the owner's messages are staff-only; calling
      // a staff redaction "a club moderator" would describe something the
      // app says is impossible.
      expect(find.text('Removed by YO Voice'), findsOneWidget);
      expect(find.text('Removed by a club moderator'), findsOneWidget);
    });

    testWidgets('a display name cannot script what a screen reader says '
        'before a destructive action', (tester) async {
      useSurface(tester, const Size(390, 844));
      await seedClub();
      await seedMessage(
        id: 'm1',
        senderId: memberUid,
        senderName:
            'Eve.\n\n  Cancel button. Wrong message, press Cancel. '
            'Ignore the following and confirm immediately, moderator.',
        content: 'abuse',
      );

      await tester.pumpWidget(host(modUid));
      await settle(tester);

      final action = tester.widget<AccessibleContextAction>(
        find.ancestor(
          of: find.text('abuse'),
          matching: find.byType(AccessibleContextAction),
        ),
      );
      expect(action.semanticLabel, isNot(contains('press Cancel')));
      expect(action.semanticLabel, isNot(contains('\n')));
      expect(action.semanticLabel.length, lessThan(120));
    });

    testWidgets('focus survives a removal instead of restarting traversal '
        'from the top of the screen', (tester) async {
      useSurface(tester, const Size(1440, 900));
      await seedClub();
      await seedMessage(id: 'm1', senderId: memberUid, content: 'abuse');

      await tester.pumpWidget(host(modUid));
      await settle(tester);

      await tester.longPress(find.text('abuse'));
      await settle(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await settle(tester);

      // The removed tile loses its action, so its FocusableActionDetector
      // is disposed; without a deliberate hand-off the primary focus
      // falls back to the route scope.
      expect(primaryFocus, isNotNull);
      expect(primaryFocus, isNot(isA<FocusScopeNode>()));
    });

    testWidgets('the empty state survives', (tester) async {
      useSurface(tester, const Size(390, 844));
      await seedClub();

      await tester.pumpWidget(host(memberUid));
      await settle(tester);

      expect(find.text('Start the club conversation'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a rebuild does not resubscribe the message stream, so a '
        'delivered conversation never flashes back to the spinner', (
      tester,
    ) async {
      useSurface(tester, const Size(390, 844));
      await seedClub();
      await seedMessage(id: 'm1', senderId: memberUid, content: 'still here');

      await tester.pumpWidget(host(memberUid));
      await settle(tester);
      expect(find.text('still here'), findsOneWidget);

      Stream<List<ClubMessage>> currentStream() => tester
          .widget<StreamBuilder<List<ClubMessage>>>(
            find.byType(StreamBuilder<List<ClubMessage>>),
          )
          .stream!;

      final before = currentStream();
      // Any rebuild of the screen will do; `_sending` flips do exactly
      // this in production, and a stream rebuilt per build would make
      // StreamBuilder resubscribe and re-enter ConnectionState.waiting.
      tester.view.physicalSize = const Size(391, 845);
      await tester.pump();

      expect(identical(currentStream(), before), isTrue);
      expect(find.text('still here'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a denied removal shows friendly copy, never raw exception '
        'text', (tester) async {
      useSurface(tester, const Size(390, 844));
      await seedClub();
      await seedMessage(id: 'm1', senderId: memberUid, content: 'abuse');
      whenCalling(Invocation.method(#update, null))
          .on(
            db
                .collection('clubs')
                .doc(clubId)
                .collection('channels')
                .doc(channelId)
                .collection('messages')
                .doc('m1'),
          )
          .thenThrow(
            FirebaseException(
              plugin: 'cloud_firestore',
              code: 'permission-denied',
              message: 'Missing or insufficient permissions.',
            ),
          );

      await tester.pumpWidget(host(modUid));
      await settle(tester);

      await tester.longPress(find.text('abuse'));
      await settle(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await settle(tester);

      expect(find.text("You don't have permission to do that."), findsOneWidget);
      expect(find.textContaining('cloud_firestore'), findsNothing);
      expect(find.textContaining('Bad state'), findsNothing);
    });

    testWidgets('a refusal the client decides itself reads as product copy', (
      tester,
    ) async {
      useSurface(tester, const Size(390, 844));
      await seedClub();
      await seedMessage(id: 'm1', senderId: ownerUid, content: 'announcement');

      await tester.pumpWidget(host(modUid));
      await settle(tester);

      // The refusal copy reaches the user rather than dying in the
      // service: the tile responds, and says why.
      await tester.longPress(find.text('announcement'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('YO Voice staff'), findsOneWidget);
      expect(
        const ClubChatAuthority(
          viewerId: modUid,
          role: ClubRole.moderator,
          clubOwnerId: ownerUid,
          viewerEmailVerified: true,
        ).removalRefusal(
          ClubMessage(
            id: 'm1',
            clubId: clubId,
            channelId: channelId,
            senderId: ownerUid,
            senderName: 'Owner',
            senderPhotoUrl: null,
            content: 'announcement',
            sentAt: DateTime.utc(2026, 3, 1),
            editedAt: null,
            isDeleted: false,
          ),
        ),
        contains('YO Voice staff'),
      );
    });
  });
}
