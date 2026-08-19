import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/discover_clubs_rail.dart';

/// Home's "Discover clubs" rail, on both halves of the defect that kept it
/// invisible for the entire life of the product:
///
///  1. THE QUERY. `watchSuggestedClubs()` sent one equality
///     (`privacy == 'public'`) while `match /clubs/{clubId}` said
///     `allow list: if false`, so the rail was permission-denied for every
///     account, a club owner listing their own public club included. The
///     replacement rule authorizes exactly one query shape — three
///     equalities, `privacy`/`type`/`status` — because a Firestore `list`
///     rule is proved against the QUERY'S CONSTRAINTS and not against the
///     documents that come back. The service tests below pin all three: a
///     family room, a suspended club and a private club are each excluded
///     by a filter that must be in the query for the query to be allowed to
///     run at all.
///
///  2. THE SILENCE. The rail read `snapshot.data ?? const <Club>[]` with no
///     `hasError` branch and then hid the whole section when the list was
///     empty, so the denial, the heading and the rail vanished together and
///     Home looked merely quiet. The widget tests pin four distinguishable
///     states and the heading surviving all of them.
void main() {
  const uid = 'me-uid';

  // -------------------------------------------------------------- query

  group('watchSuggestedClubs sends the query the rules authorize', () {
    late FakeFirebaseFirestore db;
    late HomeFeedService service;

    setUp(() {
      db = FakeFirebaseFirestore();
      service = HomeFeedService(
        firestore: db,
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: uid, displayName: 'Kamil'),
        ),
      );
    });

    Future<void> seedClub({
      required String id,
      required String name,
      String privacy = 'public',
      String type = 'community',
      String? status = 'active',
      int memberCount = 1,
    }) async {
      await db.collection('clubs').doc(id).set({
        'name': name,
        'description': 'A club',
        'ownerId': 'owner-$id',
        'ownerName': 'Owner',
        'privacy': privacy,
        'type': type,
        'status': ?status,
        'defaultLanguage': 'English',
        'memberCount': memberCount,
        'onlineCount': 0,
        'defaultChatChannelId': 'chat',
        'defaultVoiceChannelId': 'voice',
        'announcementChannelId': 'announcements',
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });
    }

    test('a family room is not discoverable through the public rail', () async {
      await seedClub(id: 'community', name: 'Night Owls', memberCount: 12);
      // Public PRIVACY, family TYPE: the exact document the old
      // single-equality query returned and the rule refuses to authorize a
      // query for. `privacy == 'public'` alone cannot exclude it.
      await seedClub(
        id: 'family',
        name: 'The Kowalskis',
        type: 'family',
        memberCount: 99,
      );

      final clubs = await service.watchSuggestedClubs().first;

      expect(clubs.map((club) => club.id), <String>['community']);
      expect(clubs.single.type, ClubType.community);
    });

    test('a suspended club is not discoverable', () async {
      await seedClub(id: 'active', name: 'Night Owls');
      await seedClub(
        id: 'suspended',
        name: 'Suspended Club',
        status: 'suspended',
        memberCount: 500,
      );

      final clubs = await service.watchSuggestedClubs().first;

      expect(clubs.map((club) => club.id), <String>['active']);
    });

    test('a club with no status field at all is not discoverable', () async {
      await seedClub(id: 'active', name: 'Night Owls');
      // Real Firestore leaves such a document out of the `status` index, so
      // an equality filter never sees it. Excluding it is the correct
      // direction for a discovery rail to fail.
      await seedClub(id: 'legacy', name: 'Legacy Club', status: null);

      final clubs = await service.watchSuggestedClubs().first;

      expect(clubs.map((club) => club.id), <String>['active']);
    });

    test('private and invite-only clubs stay out of the rail', () async {
      await seedClub(id: 'public', name: 'Night Owls');
      await seedClub(id: 'private', name: 'Private Club', privacy: 'private');
      await seedClub(
        id: 'invite',
        name: 'Invite Club',
        privacy: 'inviteOnly',
      );

      final clubs = await service.watchSuggestedClubs().first;

      expect(clubs.map((club) => club.id), <String>['public']);
    });

    test(
      'every excluded kind at once, and the survivors are ordered by size',
      () async {
        await seedClub(id: 'small', name: 'Small Club', memberCount: 3);
        await seedClub(id: 'big', name: 'Big Club', memberCount: 40);
        await seedClub(id: 'family', name: 'Family', type: 'family');
        await seedClub(id: 'suspended', name: 'Gone', status: 'suspended');
        await seedClub(id: 'private', name: 'Private', privacy: 'private');

        final clubs = await service.watchSuggestedClubs().first;

        expect(clubs.map((club) => club.id), <String>['big', 'small']);
      },
    );

    test('the limit is honoured', () async {
      for (var index = 0; index < 5; index++) {
        await seedClub(id: 'club-$index', name: 'Club $index');
      }

      final clubs = await service.watchSuggestedClubs(limit: 2).first;

      expect(clubs, hasLength(2));
    });
  });

  // -------------------------------------------------------------- states

  group('DiscoverClubsRail keeps every stream state distinguishable', () {
    Club club(String id, String name, {int memberCount = 12}) => Club(
      id: id,
      name: name,
      description: 'A club',
      ownerId: 'owner',
      ownerName: 'Owner',
      avatarUrl: null,
      bannerUrl: null,
      privacy: ClubPrivacy.public,
      defaultLanguage: 'English',
      memberCount: memberCount,
      onlineCount: 0,
      defaultChatChannelId: 'chat',
      defaultVoiceChannelId: 'voice',
      announcementChannelId: 'announcements',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    void useWidth(WidgetTester tester, Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Widget host(Widget child, {double textScale = 1}) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );

    Widget rail(
      AsyncSnapshot<List<Club>> snapshot, {
      ValueChanged<Club>? onOpenClub,
      VoidCallback? onRetry,
    }) => DiscoverClubsRail(
      snapshot: snapshot,
      onOpenClub: onOpenClub ?? (_) {},
      onRetry: onRetry,
    );

    testWidgets('loading shows placeholders, not an empty or failed rail', (
      tester,
    ) async {
      useWidth(tester, const Size(390, 900));
      await tester.pumpWidget(
        host(rail(const AsyncSnapshot<List<Club>>.waiting())),
      );

      expect(find.text('Discover clubs'), findsOneWidget);
      expect(find.bySemanticsLabel('Loading clubs'), findsNWidgets(3));
      expect(find.textContaining('could not be loaded'), findsNothing);
      expect(find.textContaining('No public clubs'), findsNothing);
    });

    testWidgets('a permission denial is visible and never mistaken for empty', (
      tester,
    ) async {
      useWidth(tester, const Size(390, 900));
      var retries = 0;
      await tester.pumpWidget(
        host(
          rail(
            AsyncSnapshot<List<Club>>.withError(
              ConnectionState.active,
              FirebaseException(
                plugin: 'cloud_firestore',
                code: 'permission-denied',
                message: 'Missing or insufficient permissions.',
              ),
            ),
            onRetry: () => retries += 1,
          ),
        ),
      );

      // The heading survives the failure: the section going silent as a
      // whole is what hid this defect for the life of the product.
      expect(find.text('Discover clubs'), findsOneWidget);
      expect(find.text('Clubs could not be loaded.'), findsOneWidget);
      // Distinguishable from the empty state, in words and not only in tone.
      expect(find.textContaining('No public clubs'), findsNothing);
      // Raw exception text never reaches the surface.
      expect(find.textContaining('FirebaseException'), findsNothing);
      expect(find.textContaining('cloud_firestore'), findsNothing);

      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('without a retry callback the failure is still spoken', (
      tester,
    ) async {
      useWidth(tester, const Size(390, 900));
      await tester.pumpWidget(
        host(
          rail(
            AsyncSnapshot<List<Club>>.withError(
              ConnectionState.active,
              Exception('offline'),
            ),
          ),
        ),
      );

      expect(find.text('Clubs could not be loaded.'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('empty reads as empty, with its own words and no error tone', (
      tester,
    ) async {
      useWidth(tester, const Size(390, 900));
      await tester.pumpWidget(
        host(
          rail(
            const AsyncSnapshot<List<Club>>.withData(
              ConnectionState.active,
              <Club>[],
            ),
          ),
        ),
      );

      expect(find.text('Discover clubs'), findsOneWidget);
      expect(find.text('No public clubs yet.'), findsOneWidget);
      expect(find.textContaining('could not be loaded'), findsNothing);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('populated lists the clubs and opens the one that was tapped', (
      tester,
    ) async {
      useWidth(tester, const Size(390, 900));
      Club? opened;
      await tester.pumpWidget(
        host(
          rail(
            AsyncSnapshot<List<Club>>.withData(ConnectionState.active, [
              club('a', 'Night Owls'),
              club('b', 'Morning Coffee'),
            ]),
            onOpenClub: (value) => opened = value,
          ),
        ),
      );

      expect(find.text('Night Owls'), findsOneWidget);
      expect(find.text('12 members'), findsNWidgets(2));
      expect(find.textContaining('No public clubs'), findsNothing);

      await tester.tap(find.text('Morning Coffee'));
      await tester.pump();
      expect(opened?.id, 'b');
    });

    testWidgets('one member reads as "1 member"', (tester) async {
      useWidth(tester, const Size(390, 900));
      await tester.pumpWidget(
        host(
          rail(
            AsyncSnapshot<List<Club>>.withData(ConnectionState.active, [
              club('a', 'Night Owls', memberCount: 1),
            ]),
          ),
        ),
      );

      expect(find.text('1 member'), findsOneWidget);
    });

    testWidgets('an error after a first successful emission replaces the '
        'stale list instead of hiding behind it', (tester) async {
      useWidth(tester, const Size(390, 900));
      final controller = StreamController<List<Club>>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        host(
          StreamBuilder<List<Club>>(
            stream: controller.stream,
            builder: (context, snapshot) => DiscoverClubsRail(
              snapshot: snapshot,
              onOpenClub: (_) {},
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Loading clubs'), findsNWidgets(3));

      controller.add([club('a', 'Night Owls')]);
      await tester.pump();
      expect(find.text('Night Owls'), findsOneWidget);

      // StreamBuilder keeps `data` alongside the error, so reading `data`
      // first — the shape this whole change exists to remove — would keep
      // painting a list the connection can no longer refresh.
      controller.addError(Exception('permission-denied'));
      await tester.pump();
      expect(find.text('Clubs could not be loaded.'), findsOneWidget);
      expect(find.text('Night Owls'), findsNothing);
    });

    // ------------------------------------------------------- responsive

    testWidgets('narrow: a horizontally scrolling rail that bleeds off the '
        'trailing edge', (tester) async {
      useWidth(tester, const Size(390, 900));
      await tester.pumpWidget(
        host(
          rail(
            AsyncSnapshot<List<Club>>.withData(ConnectionState.active, [
              for (var index = 0; index < 4; index++)
                club('c$index', 'Club $index'),
            ]),
          ),
        ),
      );

      // All four sit on one line, and the last one starts past the fold —
      // which is what tells the reader the row scrolls.
      final first = tester.getTopLeft(find.text('Club 0'));
      final last = tester.getTopLeft(find.text('Club 3'));
      expect(last.dy, first.dy);
      expect(last.dx, greaterThan(390));
      expect(tester.takeException(), isNull);
    });

    testWidgets('medium: three columns, wrapping to a second row', (
      tester,
    ) async {
      useWidth(tester, const Size(768, 1200));
      await tester.pumpWidget(
        host(
          rail(
            AsyncSnapshot<List<Club>>.withData(ConnectionState.active, [
              for (var index = 0; index < 4; index++)
                club('c$index', 'Club $index'),
            ]),
          ),
        ),
      );

      final row = tester.getTopLeft(find.text('Club 0')).dy;
      expect(tester.getTopLeft(find.text('Club 1')).dy, row);
      expect(tester.getTopLeft(find.text('Club 2')).dy, row);
      // The fourth wraps rather than scrolling off a tablet.
      expect(tester.getTopLeft(find.text('Club 3')).dy, greaterThan(row));
      expect(tester.getTopLeft(find.text('Club 3')).dx, lessThan(768));
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide: four columns, and never a stretched phone rail', (
      tester,
    ) async {
      useWidth(tester, const Size(1280, 1200));
      await tester.pumpWidget(
        host(
          rail(
            AsyncSnapshot<List<Club>>.withData(ConnectionState.active, [
              for (var index = 0; index < 4; index++)
                club('c$index', 'Club $index'),
            ]),
          ),
        ),
      );

      final row = tester.getTopLeft(find.text('Club 0')).dy;
      for (var index = 1; index < 4; index++) {
        expect(tester.getTopLeft(find.text('Club $index')).dy, row);
        expect(tester.getTopLeft(find.text('Club $index')).dx, lessThan(1280));
      }
      expect(tester.takeException(), isNull);
    });

    // ----------------------------------------------------- long content

    for (final size in const <Size>[
      Size(390, 2200),
      Size(768, 2200),
      Size(1280, 2200),
    ]) {
      testWidgets(
        'long names at a doubled text scale still lay out at '
        '${size.width.toInt()} px',
        (tester) async {
          useWidth(tester, size);
          await tester.pumpWidget(
            host(
              rail(
                AsyncSnapshot<List<Club>>.withData(ConnectionState.active, [
                  club(
                    'a',
                    'The Extremely Long Late Night Voice Club For People '
                        'Who Cannot Sleep',
                    memberCount: 123456,
                  ),
                  club('b', 'Another Considerably Overlong Club Name Here'),
                ]),
              ),
              textScale: 2,
            ),
          );

          expect(tester.takeException(), isNull);
          expect(find.textContaining('The Extremely Long'), findsOneWidget);
        },
      );

      testWidgets(
        'the error state wraps rather than overflowing at '
        '${size.width.toInt()} px',
        (tester) async {
          useWidth(tester, size);
          await tester.pumpWidget(
            host(
              rail(
                AsyncSnapshot<List<Club>>.withError(
                  ConnectionState.active,
                  Exception('permission-denied'),
                ),
                onRetry: () {},
              ),
              textScale: 2,
            ),
          );

          expect(find.text('Clubs could not be loaded.'), findsOneWidget);
          expect(find.text('Try again'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'the empty state wraps rather than overflowing at '
        '${size.width.toInt()} px',
        (tester) async {
          useWidth(tester, size);
          await tester.pumpWidget(
            host(
              rail(
                const AsyncSnapshot<List<Club>>.withData(
                  ConnectionState.active,
                  <Club>[],
                ),
              ),
              textScale: 2,
            ),
          );

          expect(find.text('No public clubs yet.'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
