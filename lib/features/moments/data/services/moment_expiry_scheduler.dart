import 'dart:async';

import 'package:yovoice/features/moments/data/models/voice_moment.dart';

/// The clock used to decide which exact availability deadline comes next.
typedef MomentExpiryClock = DateTime Function();

/// A cancellable timer small enough to fake without depending on the Dart
/// zone clock in widget tests.
abstract interface class MomentExpiryTimer {
  void cancel();
}

/// Creates one timer for [delay].
typedef MomentExpiryTimerFactory =
    MomentExpiryTimer Function(Duration delay, void Function() callback);

final class _DartMomentExpiryTimer implements MomentExpiryTimer {
  _DartMomentExpiryTimer(Duration delay, void Function() callback)
    : _timer = Timer(delay, callback);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}

/// Arms one timer for the nearest finite Voice Moment deadline.
///
/// Firestore's expiry sweep is intentionally eventual. A snapshot therefore
/// cannot be the event that removes a Moment from an already-open surface.
/// Owners pass their currently visible Moments here and, when [onDeadline]
/// fires, filter through that exact deadline and call [schedule] again. This
/// produces one timer per surface instead of one timer per card.
///
/// A permanent Moment has no `expiresAt`, so it never creates a timer.
final class MomentExpiryScheduler {
  MomentExpiryScheduler({
    required void Function(DateTime deadline) onDeadline,
    MomentExpiryClock? clock,
    MomentExpiryTimerFactory? timerFactory,
  }) : _onDeadline = onDeadline,
       _clock = clock ?? DateTime.now,
       _timerFactory =
           timerFactory ??
           ((delay, callback) => _DartMomentExpiryTimer(delay, callback));

  final void Function(DateTime deadline) _onDeadline;
  final MomentExpiryClock _clock;
  final MomentExpiryTimerFactory _timerFactory;

  // Browser timers use a signed 32-bit millisecond delay. Passing the full
  // 30-day availability would overflow that delay and can fire immediately,
  // so longer waits are split into safe chunks and checked against the clock
  // after every chunk.
  static const Duration _maximumTimerDelay = Duration(milliseconds: 0x7fffffff);

  MomentExpiryTimer? _timer;
  bool _disposed = false;
  int _generation = 0;

  DateTime now() => _clock();

  /// Cancels the old deadline and arms the nearest future one in [moments].
  void schedule(Iterable<VoiceMoment> moments) {
    if (_disposed) return;
    final generation = ++_generation;
    _timer?.cancel();
    _timer = null;

    final now = _clock();
    DateTime? nearest;
    for (final moment in moments) {
      final expiry = moment.expiresAt;
      if (expiry == null || !moment.isActiveAt(now)) continue;
      if (nearest == null || expiry.isBefore(nearest)) nearest = expiry;
    }
    if (nearest == null) return;

    _arm(nearest, generation);
  }

  void _arm(DateTime deadline, int generation) {
    if (_disposed || generation != _generation) return;
    final remaining = deadline.difference(_clock());
    final delay = remaining > _maximumTimerDelay
        ? _maximumTimerDelay
        : remaining.isNegative
        ? Duration.zero
        : remaining;
    _timer = _timerFactory(delay, () {
      if (_disposed || generation != _generation) return;
      _timer = null;
      if (_clock().isBefore(deadline)) {
        _arm(deadline, generation);
        return;
      }
      _onDeadline(deadline);
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
    _timer?.cancel();
    _timer = null;
  }
}
