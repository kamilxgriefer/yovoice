import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/features/onboarding/data/guided_onboarding_progress.dart';

void main() {
  final now = DateTime.utc(2026, 8, 29, 12);

  group('GuidedOnboardingProgress', () {
    test(
      'SharedPreferences store round-trips outcomes per UID and version',
      () async {
        SharedPreferences.setMockInitialValues({});
        const store = SharedPreferencesGuidedOnboardingProgressStore();

        await store.markDismissed(
          userId: 'first-user',
          version: 1,
          outcome: GuidedOnboardingOutcome.skipped,
        );
        await store.markDismissed(
          userId: 'second-user',
          version: 1,
          outcome: GuidedOnboardingOutcome.completed,
        );

        expect(
          await store.readOutcome(userId: 'first-user', version: 1),
          GuidedOnboardingOutcome.skipped,
        );
        expect(
          await store.readOutcome(userId: 'second-user', version: 1),
          GuidedOnboardingOutcome.completed,
        );
        expect(
          await store.readOutcome(userId: 'first-user', version: 2),
          isNull,
        );
        expect(
          await store.readOutcome(userId: 'unknown-user', version: 1),
          isNull,
        );
      },
    );

    test('auto-starts only during a fresh account initial session', () async {
      final store = _MemoryProgressStore();
      final progress = GuidedOnboardingProgress(store: store, now: () => now);
      final created = now.subtract(const Duration(minutes: 20));

      expect(
        await progress.shouldAutoStart(
          userId: '  fresh-user  ',
          creationTime: created,
          lastSignInTime: created.add(const Duration(seconds: 30)),
        ),
        isTrue,
      );
      expect(store.reads, [(userId: 'fresh-user', version: 1)]);
    });

    test(
      'newAccountsOnly rejects existing, returning and invalid sessions',
      () async {
        final store = _MemoryProgressStore();
        final progress = GuidedOnboardingProgress(store: store, now: () => now);
        final created = now.subtract(const Duration(minutes: 20));
        final cases =
            <
              ({
                String name,
                String userId,
                DateTime? creationTime,
                DateTime? lastSignInTime,
              })
            >[
              (
                name: 'existing account',
                userId: 'user',
                creationTime: now.subtract(const Duration(days: 8)),
                lastSignInTime: now,
              ),
              (
                name: 'returning session',
                userId: 'user',
                creationTime: created,
                lastSignInTime: created.add(const Duration(minutes: 6)),
              ),
              (
                name: 'future account timestamp',
                userId: 'user',
                creationTime: now.add(const Duration(seconds: 1)),
                lastSignInTime: now.add(const Duration(seconds: 1)),
              ),
              (
                name: 'missing creation timestamp',
                userId: 'user',
                creationTime: null,
                lastSignInTime: now,
              ),
              (
                name: 'missing last sign-in timestamp',
                userId: 'user',
                creationTime: created,
                lastSignInTime: null,
              ),
              (
                name: 'empty user id',
                userId: '   ',
                creationTime: created,
                lastSignInTime: created,
              ),
            ];

        for (final value in cases) {
          expect(
            GuidedOnboardingProgress.isInitialAccountSession(
              userId: value.userId,
              creationTime: value.creationTime,
              lastSignInTime: value.lastSignInTime,
              now: now,
            ),
            isFalse,
            reason: value.name,
          );
          expect(
            await progress.shouldAutoStart(
              userId: value.userId,
              creationTime: value.creationTime,
              lastSignInTime: value.lastSignInTime,
            ),
            isFalse,
            reason: value.name,
          );
        }
        expect(store.reads, isEmpty);
      },
    );

    test('initial-session boundaries remain inclusive', () {
      final sevenDaysAgo = now.subtract(const Duration(days: 7));

      expect(
        GuidedOnboardingProgress.isInitialAccountSession(
          userId: 'user',
          creationTime: sevenDaysAgo,
          lastSignInTime: sevenDaysAgo.add(const Duration(minutes: 5)),
          now: now,
        ),
        isTrue,
      );
    });

    test(
      'allAccountsOnce bypasses account-age metadata but not user id',
      () async {
        final store = _MemoryProgressStore();
        final progress = GuidedOnboardingProgress(store: store, now: () => now);

        expect(
          await progress.shouldAutoStart(
            userId: 'established-user',
            creationTime: null,
            lastSignInTime: null,
            audience: GuidedOnboardingAudience.allAccountsOnce,
          ),
          isTrue,
        );
        expect(
          await progress.shouldAutoStart(
            userId: '  ',
            creationTime: null,
            lastSignInTime: null,
            audience: GuidedOnboardingAudience.allAccountsOnce,
          ),
          isFalse,
        );
        expect(store.reads, [(userId: 'established-user', version: 1)]);
      },
    );

    for (final outcome in GuidedOnboardingOutcome.values) {
      test(
        '${outcome.name} is account- and version-scoped and suppresses replay',
        () async {
          final store = _MemoryProgressStore();
          final progress = GuidedOnboardingProgress(
            store: store,
            now: () => now,
          );

          await progress.markDismissed('  first-user ', outcome: outcome);

          expect(
            store.outcomes[(
              'first-user',
              GuidedOnboardingProgress.currentVersion,
            )],
            outcome,
          );
          expect(
            await progress.shouldAutoStart(
              userId: 'first-user',
              creationTime: null,
              lastSignInTime: null,
              audience: GuidedOnboardingAudience.allAccountsOnce,
            ),
            isFalse,
          );
          expect(
            await progress.shouldAutoStart(
              userId: 'second-user',
              creationTime: null,
              lastSignInTime: null,
              audience: GuidedOnboardingAudience.allAccountsOnce,
            ),
            isTrue,
          );

          store.outcomes[(
                'versioned-user',
                GuidedOnboardingProgress.currentVersion - 1,
              )] =
              outcome;
          expect(
            await progress.shouldAutoStart(
              userId: 'versioned-user',
              creationTime: null,
              lastSignInTime: null,
              audience: GuidedOnboardingAudience.allAccountsOnce,
            ),
            isTrue,
          );
        },
      );
    }

    test(
      'read failures fail closed instead of repeatedly opening the tour',
      () async {
        final progress = GuidedOnboardingProgress(
          store: _MemoryProgressStore(throwOnRead: true),
          now: () => now,
        );

        expect(
          await progress.shouldAutoStart(
            userId: 'user',
            creationTime: null,
            lastSignInTime: null,
            audience: GuidedOnboardingAudience.allAccountsOnce,
          ),
          isFalse,
        );
      },
    );

    test('write failures surface and an empty user id is a no-op', () async {
      final store = _MemoryProgressStore(throwOnWrite: true);
      final progress = GuidedOnboardingProgress(store: store, now: () => now);

      await expectLater(
        progress.markDismissed(
          'user',
          outcome: GuidedOnboardingOutcome.completed,
        ),
        throwsA(isA<StateError>()),
      );
      expect(store.outcomes, isEmpty);

      await progress.markDismissed(
        '   ',
        outcome: GuidedOnboardingOutcome.skipped,
      );
      expect(store.writes, isEmpty);
    });
  });
}

class _MemoryProgressStore implements GuidedOnboardingProgressStore {
  _MemoryProgressStore({this.throwOnRead = false, this.throwOnWrite = false});

  final bool throwOnRead;
  final bool throwOnWrite;
  final Map<(String, int), GuidedOnboardingOutcome> outcomes = {};
  final List<({String userId, int version})> reads = [];
  final List<({String userId, int version, GuidedOnboardingOutcome outcome})>
  writes = [];

  @override
  Future<GuidedOnboardingOutcome?> readOutcome({
    required String userId,
    required int version,
  }) async {
    reads.add((userId: userId, version: version));
    if (throwOnRead) throw StateError('read unavailable');
    return outcomes[(userId, version)];
  }

  @override
  Future<void> markDismissed({
    required String userId,
    required int version,
    required GuidedOnboardingOutcome outcome,
  }) async {
    if (throwOnWrite) throw StateError('write unavailable');
    writes.add((userId: userId, version: version, outcome: outcome));
    outcomes[(userId, version)] = outcome;
  }
}
