import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum GuidedOnboardingOutcome { skipped, completed }

enum GuidedOnboardingAudience { newAccountsOnly, allAccountsOnce }

abstract interface class GuidedOnboardingProgressStore {
  Future<GuidedOnboardingOutcome?> readOutcome({
    required String userId,
    required int version,
  });

  Future<void> markDismissed({
    required String userId,
    required int version,
    required GuidedOnboardingOutcome outcome,
  });
}

final class SharedPreferencesGuidedOnboardingProgressStore
    implements GuidedOnboardingProgressStore {
  const SharedPreferencesGuidedOnboardingProgressStore();

  static String _key(String userId, int version) =>
      'onboarding.guided_tour.v$version.$userId.outcome';

  @override
  Future<GuidedOnboardingOutcome?> readOutcome({
    required String userId,
    required int version,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_key(userId, version));
    return switch (stored) {
      'skipped' => GuidedOnboardingOutcome.skipped,
      'completed' => GuidedOnboardingOutcome.completed,
      _ => null,
    };
  }

  @override
  Future<void> markDismissed({
    required String userId,
    required int version,
    required GuidedOnboardingOutcome outcome,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _key(userId, version),
      outcome.name,
    );
    if (!saved) throw StateError('Could not persist guided onboarding.');
  }
}

/// Account-scoped eligibility and persistence for the optional product tour.
///
/// A missing local marker is deliberately NOT enough to auto-open the tour:
/// existing members installing a new build or changing devices must not be
/// mistaken for new accounts. Firebase Auth's creation and last-sign-in
/// timestamps identify the account's initial session without adding a public
/// profile field or widening Firestore update authority.
final class GuidedOnboardingProgress {
  GuidedOnboardingProgress({
    GuidedOnboardingProgressStore? store,
    DateTime Function()? now,
  }) : _store = store ?? const SharedPreferencesGuidedOnboardingProgressStore(),
       _now = now ?? DateTime.now;

  static const int currentVersion = 1;
  // A registration can remain on the optional email-verification screen for
  // more than a day. Seven days is still a genuinely new account while
  // avoiding a race between verification and the first useful app session.
  static const Duration _newAccountWindow = Duration(days: 7);
  static const Duration _initialSessionSkew = Duration(minutes: 5);

  final GuidedOnboardingProgressStore _store;
  final DateTime Function() _now;

  Future<bool> shouldAutoStart({
    required String userId,
    required DateTime? creationTime,
    required DateTime? lastSignInTime,
    GuidedOnboardingAudience audience =
        GuidedOnboardingAudience.newAccountsOnly,
  }) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return false;
    if (audience == GuidedOnboardingAudience.newAccountsOnly &&
        !isInitialAccountSession(
          userId: normalizedUserId,
          creationTime: creationTime,
          lastSignInTime: lastSignInTime,
          now: _now(),
        )) {
      return false;
    }

    try {
      return await _store.readOutcome(
            userId: normalizedUserId,
            version: currentVersion,
          ) ==
          null;
    } catch (error) {
      // A damaged or unavailable local store must never trap someone behind
      // onboarding or surprise an established account on every launch.
      debugPrint('Guided onboarding progress could not be read: $error');
      return false;
    }
  }

  Future<void> markDismissed(
    String userId, {
    required GuidedOnboardingOutcome outcome,
  }) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return;
    await _store.markDismissed(
      userId: normalizedUserId,
      version: currentVersion,
      outcome: outcome,
    );
  }

  @visibleForTesting
  static bool isInitialAccountSession({
    required String userId,
    required DateTime? creationTime,
    required DateTime? lastSignInTime,
    required DateTime now,
  }) {
    if (userId.trim().isEmpty ||
        creationTime == null ||
        lastSignInTime == null) {
      return false;
    }

    final age = now.difference(creationTime);
    if (age.isNegative || age > _newAccountWindow) return false;

    final sessionSkew = lastSignInTime.difference(creationTime).abs();
    return sessionSkew <= _initialSessionSkew;
  }
}
