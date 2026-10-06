import 'package:flutter/foundation.dart';

/// One step of Start's "Zacznij tutaj" card (firstSteps A, 2026-10-03), in
/// the order the card lists them.
enum FirstStep {
  /// A profile photo exists for the account (the avatar grant resolves).
  photo,

  /// The friends stream holds at least one friend.
  friend,

  /// `watchMyServers()` holds at least one server (joined or created).
  server,

  /// The Moments achievement counter (`momentCount`) reached 1.
  voice,

  /// The account follows at least one Page or creator. Listed only while
  /// Treści (Premium Pages) exist for the account.
  follow,
}

/// What the card knows about the account, from state the client already
/// holds. Built only by [evaluate], and only once every source has answered:
/// a step is never shown as open (or done) on a guess.
@immutable
class FirstStepsProgress {
  const FirstStepsProgress._({required this.steps, required this.done});

  /// The listed steps, in card order: four, or five with [FirstStep.follow].
  final List<FirstStep> steps;

  /// The listed steps the account has really completed.
  final Set<FirstStep> done;

  int get total => steps.length;
  int get doneCount => done.length;
  bool get isComplete => doneCount >= total;
  bool isDone(FirstStep step) => done.contains(step);

  /// The first open step: the one the card highlights. Null when complete.
  FirstStep? get next {
    for (final step in steps) {
      if (!done.contains(step)) return step;
    }
    return null;
  }

  /// The card's state, or null while any source is still unknown (loading
  /// or failed). [followingCount] is consulted only when [contentEnabled].
  static FirstStepsProgress? evaluate({
    required bool? hasPhoto,
    required int? friendCount,
    required int? serverCount,
    required int? momentCount,
    required int? followingCount,
    required bool contentEnabled,
  }) {
    if (hasPhoto == null ||
        friendCount == null ||
        serverCount == null ||
        momentCount == null ||
        (contentEnabled && followingCount == null)) {
      return null;
    }
    final steps = <FirstStep>[
      FirstStep.photo,
      FirstStep.friend,
      FirstStep.server,
      FirstStep.voice,
      if (contentEnabled) FirstStep.follow,
    ];
    final done = <FirstStep>{
      if (hasPhoto) FirstStep.photo,
      if (friendCount > 0) FirstStep.friend,
      if (serverCount > 0) FirstStep.server,
      if (momentCount > 0) FirstStep.voice,
      if (contentEnabled && (followingCount ?? 0) > 0) FirstStep.follow,
    };
    return FirstStepsProgress._(
      steps: List<FirstStep>.unmodifiable(steps),
      done: Set<FirstStep>.unmodifiable(done),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FirstStepsProgress &&
      listEquals(other.steps, steps) &&
      setEquals(other.done, done);

  @override
  int get hashCode => Object.hash(Object.hashAll(steps), doneCount);
}
