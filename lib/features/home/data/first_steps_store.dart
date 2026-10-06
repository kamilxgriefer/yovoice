import 'package:shared_preferences/shared_preferences.dart';

/// What this device remembers about the "Zacznij tutaj" card for one account.
enum FirstStepsOutcome {
  /// The checklist was shown with at least one open step. Completing the
  /// last one later earns the one-line "Gotowe" state.
  started,

  /// The person closed the card with its X. It never comes back here.
  dismissed,

  /// Every listed step was done. The card is gone for good, even if a
  /// counter falls later (an unfollow, a removed friend).
  completed,
}

/// Local, account-scoped memory of the card, like the guided tour's progress
/// store (`GuidedOnboardingProgressStore`): nothing is written to the
/// account, so another device decides for itself from the same real state.
abstract interface class FirstStepsStore {
  Future<FirstStepsOutcome?> read(String userId);
  Future<void> write(String userId, FirstStepsOutcome outcome);
}

final class SharedPreferencesFirstStepsStore implements FirstStepsStore {
  const SharedPreferencesFirstStepsStore();

  static String _key(String userId) => 'home.first_steps.v1.$userId.outcome';

  @override
  Future<FirstStepsOutcome?> read(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    return switch (preferences.getString(_key(userId))) {
      'started' => FirstStepsOutcome.started,
      'dismissed' => FirstStepsOutcome.dismissed,
      'completed' => FirstStepsOutcome.completed,
      _ => null,
    };
  }

  @override
  Future<void> write(String userId, FirstStepsOutcome outcome) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(_key(userId), outcome.name);
    if (!saved) throw StateError('Could not persist the first-steps card.');
  }
}
