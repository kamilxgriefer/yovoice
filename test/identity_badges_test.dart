// The authoritative identity-badge system, client side.
//
// The properties under test:
//
//  1. Exact labels and exact colors — one per official role, plus VIP —
//     with USER always displayed for an ordinary account.
//  2. VIP coexists with every role and renders AFTER the role badge,
//     never instead of it.
//  3. The owner badge maps only from the wire value the server publishes
//     for the confirmed owner; unknown wire values fail to USER.
//  4. The repository batches, dedups, caches, clears on account switch,
//     falls back to USER on failure, and honors the 50-uid bound.
//  5. Achievement cosmetics can accompany, but never replace or
//     restyle, the official badges.
//  6. Long labels in narrow width wrap instead of overflowing.

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/identity/vip_badge.dart';

/// A repository with a scripted fetcher, a signed-in mock session, and
/// no real Firebase behind it.
PublicIdentityRepository fakeRepository({
  required Future<Map<String, dynamic>> Function(List<String> uids) fetch,
  MockFirebaseAuth? auth,
}) {
  return PublicIdentityRepository(
    auth: auth ??
        MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'viewer')),
    fetchOverride: fetch,
    flushDelay: const Duration(milliseconds: 1),
  );
}

Widget host(Widget child, {double width = 600}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: width, child: child)),
    ),
  );
}

void main() {
  group('vocabulary', () {
    test('every official role carries its exact label and color', () {
      expect(OfficialRole.user.label, 'USER');
      expect(OfficialRole.user.color, const Color(0xFF9189A6));
      expect(OfficialRole.guideMaster.label, 'GUIDE MASTER');
      expect(OfficialRole.guideMaster.color, const Color(0xFF35E58D));
      expect(OfficialRole.support.label, 'SUPPORT');
      expect(OfficialRole.support.color, const Color(0xFF38BDF8));
      expect(OfficialRole.auditor.label, 'AUDITOR');
      expect(OfficialRole.auditor.color, const Color(0xFF818CF8));
      expect(OfficialRole.moderator.label, 'MODERATOR');
      expect(OfficialRole.moderator.color, const Color(0xFFA855F7));
      expect(OfficialRole.superModerator.label, 'SUPER MODERATOR');
      expect(OfficialRole.superModerator.color, const Color(0xFFFF6B81));
      expect(OfficialRole.ownerSuperAdmin.label, 'OWNER · SUPER ADMIN');
      expect(OfficialRole.ownerSuperAdmin.color, const Color(0xFFFF3344));
      // The theme is the single palette source.
      expect(AppColors.vipGold, const Color(0xFFFFD166));
    });

    test('wire parsing fails safely to USER', () {
      expect(OfficialRole.fromWire('moderator'), OfficialRole.moderator);
      expect(OfficialRole.fromWire('superAdmin'), OfficialRole.ownerSuperAdmin);
      expect(OfficialRole.fromWire('wizard'), OfficialRole.user);
      expect(OfficialRole.fromWire(''), OfficialRole.user);
      expect(OfficialRole.fromWire(null), OfficialRole.user);
      // Nothing cosmetic can enter the official vocabulary.
      expect(OfficialRole.fromWire('OWNER'), OfficialRole.user);
      expect(OfficialRole.fromWire('Admin'), OfficialRole.user);
    });
  });

  group('badges render', () {
    testWidgets('every role badge shows its exact label', (tester) async {
      for (final role in OfficialRole.values) {
        await tester.pumpWidget(host(OfficialRoleBadge(role: role)));
        expect(find.text(role.label), findsOneWidget);
      }
    });

    testWidgets('an unresolved account still displays USER', (tester) async {
      final repository = fakeRepository(fetch: (_) async => {});
      await tester.pumpWidget(
        host(UserIdentityBadges(uid: 'u1', repository: repository)),
      );
      expect(find.text('USER'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('USER'), findsOneWidget);
      expect(find.text('VIP'), findsNothing);
    });

    testWidgets('every role coexists with VIP, role first', (tester) async {
      for (final role in OfficialRole.values) {
        final repository = fakeRepository(
          fetch: (uids) async => {
            for (final uid in uids)
              uid: {'staffRole': role.wire, 'isVip': true},
          },
        );
        await tester.pumpWidget(
          host(
            UserIdentityBadges(
              uid: 'u-${role.wire}',
              variant: IdentityBadgeVariant.full,
              repository: repository,
            ),
          ),
        );
        // The flush timer runs on fake time: pump past it, then settle
        // so the resolved identity lands.
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pumpAndSettle();

        expect(find.text(role.label), findsOneWidget,
            reason: '${role.wire} label');
        expect(find.text('VIP'), findsOneWidget,
            reason: '${role.wire} must coexist with VIP');

        // Order: the official role badge precedes the VIP badge.
        final roleCenter = tester.getCenter(find.byType(OfficialRoleBadge));
        final vipCenter = tester.getCenter(find.byType(VipBadge));
        expect(roleCenter.dx, lessThan(vipCenter.dx));
      }
    });

    testWidgets('the owner wire value renders OWNER · SUPER ADMIN + VIP',
        (tester) async {
      final repository = fakeRepository(
        fetch: (uids) async => {
          for (final uid in uids) uid: {'staffRole': 'superAdmin', 'isVip': true},
        },
      );
      await tester.pumpWidget(
        host(
          UserIdentityBadges(
            uid: 'owner',
            variant: IdentityBadgeVariant.full,
            repository: repository,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      expect(find.text('OWNER · SUPER ADMIN'), findsOneWidget);
      expect(find.text('VIP'), findsOneWidget);
    });

    testWidgets('icon variant keeps the role reachable via tooltip',
        (tester) async {
      await tester.pumpWidget(
        host(const OfficialRoleBadge(
          role: OfficialRole.moderator,
          variant: IdentityBadgeVariant.icon,
        )),
      );
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, 'MODERATOR');
    });

    testWidgets('long labels at narrow width wrap without overflow',
        (tester) async {
      final repository = fakeRepository(
        fetch: (uids) async => {
          for (final uid in uids) uid: {'staffRole': 'superAdmin', 'isVip': true},
        },
      );
      await tester.pumpWidget(
        host(
          UserIdentityBadges(
            uid: 'owner',
            variant: IdentityBadgeVariant.full,
            repository: repository,
          ),
          width: 120, // narrower than the owner pill + VIP side by side
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      // Both badges present; the Wrap put them on separate runs instead
      // of overflowing (an overflow would fail the test through the
      // framework's exception reporting).
      expect(find.text('OWNER · SUPER ADMIN'), findsOneWidget);
      expect(find.text('VIP'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('achievement cosmetics render after — never instead of — '
        'the official badges', (tester) async {
      final repository = fakeRepository(
        fetch: (uids) async => {
          for (final uid in uids) uid: {'staffRole': 'moderator', 'isVip': true},
        },
      );
      await tester.pumpWidget(
        host(
          UserIdentityBadges(
            uid: 'mod',
            variant: IdentityBadgeVariant.full,
            repository: repository,
            achievementStyle: const AchievementStyle(
              rankLabel: 'Star Voyager',
              rankColor: Color(0xFF00FF00),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();

      // Official badges intact.
      expect(find.text('MODERATOR'), findsOneWidget);
      expect(find.text('VIP'), findsOneWidget);
      // The cosmetic is present but positioned after both.
      expect(find.text('Star Voyager'), findsOneWidget);
      final vipCenter = tester.getCenter(find.byType(VipBadge));
      final rankCenter = tester.getCenter(find.text('Star Voyager'));
      expect(vipCenter.dx, lessThan(rankCenter.dx));
    });
  });

  group('repository', () {
    test('N lookups in one window become one batched request', () async {
      var calls = 0;
      final repository = fakeRepository(
        fetch: (uids) async {
          calls += 1;
          return {
            for (final uid in uids) uid: {'staffRole': 'user', 'isVip': false},
          };
        },
      );

      final futures = [
        for (var i = 0; i < 30; i++) repository.resolve('user-${i % 10}'),
      ];
      await Future.wait(futures);

      expect(calls, 1, reason: '30 lookups over 10 uids = one request');
    });

    test('the callable bound is honored by chunking', () async {
      final requestSizes = <int>[];
      final repository = fakeRepository(
        fetch: (uids) async {
          requestSizes.add(uids.length);
          return {
            for (final uid in uids) uid: {'staffRole': 'user', 'isVip': false},
          };
        },
      );

      await Future.wait([
        for (var i = 0; i < 120; i++) repository.resolve('user-$i'),
      ]);

      expect(requestSizes.every((size) => size <= 50), isTrue);
      expect(requestSizes.fold<int>(0, (sum, size) => sum + size), 120);
    });

    test('cached identities are served without a second request', () async {
      var calls = 0;
      final repository = fakeRepository(
        fetch: (uids) async {
          calls += 1;
          return {
            for (final uid in uids)
              uid: {'staffRole': 'moderator', 'isVip': false},
          };
        },
      );

      final first = await repository.resolve('mod');
      final second = await repository.resolve('mod');
      expect(first.role, OfficialRole.moderator);
      expect(second, first);
      expect(calls, 1);
      expect(repository.peek('mod')?.role, OfficialRole.moderator);
    });

    test('a failed fetch answers USER and is not cached as truth', () async {
      var calls = 0;
      final repository = fakeRepository(
        fetch: (uids) async {
          calls += 1;
          if (calls == 1) throw Exception('network down');
          return {
            for (final uid in uids) uid: {'staffRole': 'support', 'isVip': false},
          };
        },
      );

      final failed = await repository.resolve('sup');
      expect(failed, PublicIdentity.fallback,
          reason: 'failure answers the safe USER identity');
      expect(repository.peek('sup'), isNull,
          reason: 'a transient failure must not stick in the cache');

      final recovered = await repository.resolve('sup');
      expect(recovered.role, OfficialRole.support);
    });

    test('absence is the designed answer for an ordinary account', () async {
      final repository = fakeRepository(fetch: (_) async => {});
      final identity = await repository.resolve('plain');
      expect(identity, PublicIdentity.fallback);
      expect(repository.peek('plain'), PublicIdentity.fallback,
          reason: 'absence IS cacheable — it is the common case');
    });

    test('invalidate forgets a uid and bumps the revision', () async {
      var calls = 0;
      final repository = fakeRepository(
        fetch: (uids) async {
          calls += 1;
          return {
            for (final uid in uids)
              uid: {
                'staffRole': calls == 1 ? 'user' : 'moderator',
                'isVip': false,
              },
          };
        },
      );

      var revisions = 0;
      repository.revision.addListener(() => revisions += 1);

      expect((await repository.resolve('m')).role, OfficialRole.user);
      repository.invalidate('m');
      expect(revisions, 1);
      expect(repository.peek('m'), isNull);
      expect((await repository.resolve('m')).role, OfficialRole.moderator);
    });

    test('duplicate uids in one batch deduplicate', () async {
      final seen = <String>[];
      final repository = fakeRepository(
        fetch: (uids) async {
          seen.addAll(uids);
          return {
            for (final uid in uids) uid: {'staffRole': 'user', 'isVip': false},
          };
        },
      );
      await repository.resolveAll(['a', 'a', ' a ', 'b']);
      expect(seen, unorderedEquals(['a', 'b']));
    });

    test('clear empties the cache', () async {
      final repository = fakeRepository(
        fetch: (uids) async => {
          for (final uid in uids) uid: {'staffRole': 'auditor', 'isVip': false},
        },
      );
      await repository.resolve('aud');
      expect(repository.peek('aud'), isNotNull);
      repository.clear();
      expect(repository.peek('aud'), isNull);
    });

    test('the cache empties when the signed-in account changes', () async {
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'account-a'),
      );
      final repository = fakeRepository(
        auth: auth,
        fetch: (uids) async => {
          for (final uid in uids)
            uid: {'staffRole': 'moderator', 'isVip': true},
        },
      );

      await repository.resolve('mod');
      expect(repository.peek('mod'), isNotNull);

      // Sign-out is an account change: nothing from the previous session
      // may survive into the next one.
      await auth.signOut();
      expect(repository.peek('mod'), isNull);

      // And signed out, resolution answers the safe fallback without a
      // network round trip.
      expect(await repository.resolve('mod'), PublicIdentity.fallback);
    });

    test('signed out, resolution answers USER immediately', () async {
      var calls = 0;
      final repository = fakeRepository(
        auth: MockFirebaseAuth(signedIn: false),
        fetch: (uids) async {
          calls += 1;
          return {};
        },
      );
      expect(await repository.resolve('anyone'), PublicIdentity.fallback);
      expect(calls, 0, reason: 'no request without a session');
    });
  });
}
