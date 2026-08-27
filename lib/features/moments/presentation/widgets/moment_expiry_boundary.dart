import 'package:flutter/material.dart';

import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_expiry_scheduler.dart';

/// Removes a single frozen Moment subtree at its exact deadline.
///
/// Use this for surfaces that receive a Moment value rather than a live list.
/// Removing [child] also disposes any AudioPlayer owned by that subtree.
class MomentExpiryBoundary extends StatefulWidget {
  const MomentExpiryBoundary({
    required this.moment,
    required this.child,
    this.expired = const SizedBox.shrink(),
    this.onExpired,
    this.clock,
    this.timerFactory,
    super.key,
  });

  final VoiceMoment moment;
  final Widget child;
  final Widget expired;
  final VoidCallback? onExpired;

  @visibleForTesting
  final MomentExpiryClock? clock;

  @visibleForTesting
  final MomentExpiryTimerFactory? timerFactory;

  @override
  State<MomentExpiryBoundary> createState() => _MomentExpiryBoundaryState();
}

class _MomentExpiryBoundaryState extends State<MomentExpiryBoundary> {
  late final MomentExpiryScheduler _expiry = MomentExpiryScheduler(
    onDeadline: _handleDeadline,
    clock: widget.clock,
    timerFactory: widget.timerFactory,
  );
  DateTime? _expiredThrough;
  late bool _isExpired;
  bool _didNotifyExpired = false;

  DateTime _effectiveNow() {
    final now = _expiry.now();
    final floor = _expiredThrough;
    return floor != null && floor.isAfter(now) ? floor : now;
  }

  @override
  void initState() {
    super.initState();
    _isExpired = !widget.moment.isActiveAt(_effectiveNow());
    if (_isExpired) {
      _notifyExpired(postFrame: true);
    } else {
      _expiry.schedule([widget.moment]);
    }
  }

  @override
  void didUpdateWidget(MomentExpiryBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.moment.id == widget.moment.id &&
        oldWidget.moment.expiresAt == widget.moment.expiresAt &&
        oldWidget.moment.status == widget.moment.status &&
        oldWidget.moment.isPublished == widget.moment.isPublished &&
        oldWidget.moment.isDeleted == widget.moment.isDeleted) {
      return;
    }
    final expired = !widget.moment.isActiveAt(_effectiveNow());
    final becameExpired = !_isExpired && expired;
    _isExpired = expired;
    if (!expired) _didNotifyExpired = false;
    _expiry.schedule(expired ? const <VoiceMoment>[] : [widget.moment]);
    if (becameExpired) {
      _notifyExpired(postFrame: true);
    }
  }

  void _notifyExpired({required bool postFrame}) {
    if (_didNotifyExpired) return;
    _didNotifyExpired = true;
    if (!postFrame) {
      widget.onExpired?.call();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isExpired) widget.onExpired?.call();
    });
  }

  void _handleDeadline(DateTime deadline) {
    if (!mounted) return;
    _expiredThrough = deadline;
    if (widget.moment.isActiveAt(_effectiveNow())) {
      _expiry.schedule([widget.moment]);
      return;
    }
    setState(() => _isExpired = true);
    _notifyExpired(postFrame: false);
  }

  @override
  void dispose() {
    _expiry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _isExpired ? widget.expired : widget.child;
}

/// Rebuilds a frozen Moment list at each exact finite deadline.
///
/// The builder receives the scheduler's effective `now`, including the
/// deadline that just fired even if a fake or adjusted wall clock lags behind.
/// It decides whether the surface wants only live Moments or also drafts.
class MomentExpiryListBuilder extends StatefulWidget {
  const MomentExpiryListBuilder({
    required this.moments,
    required this.builder,
    this.onDeadline,
    this.clock,
    this.timerFactory,
    super.key,
  });

  final List<VoiceMoment> moments;
  final Widget Function(BuildContext context, DateTime now) builder;
  final ValueChanged<DateTime>? onDeadline;

  @visibleForTesting
  final MomentExpiryClock? clock;

  @visibleForTesting
  final MomentExpiryTimerFactory? timerFactory;

  @override
  State<MomentExpiryListBuilder> createState() =>
      _MomentExpiryListBuilderState();
}

class _MomentExpiryListBuilderState extends State<MomentExpiryListBuilder> {
  late final MomentExpiryScheduler _expiry = MomentExpiryScheduler(
    onDeadline: _handleDeadline,
    clock: widget.clock,
    timerFactory: widget.timerFactory,
  );
  DateTime? _expiredThrough;
  DateTime? _nextDeadline;

  DateTime _effectiveNow() {
    final now = _expiry.now();
    final floor = _expiredThrough;
    return floor != null && floor.isAfter(now) ? floor : now;
  }

  void _schedule() {
    final now = _effectiveNow();
    final active = widget.moments
        .where((moment) => moment.isActiveAt(now))
        .toList(growable: false);
    DateTime? nearest;
    for (final moment in active) {
      final expiry = moment.expiresAt;
      if (expiry != null && (nearest == null || expiry.isBefore(nearest))) {
        nearest = expiry;
      }
    }
    _nextDeadline = nearest;
    _expiry.schedule(active);
  }

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(MomentExpiryListBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pendingDeadline = _nextDeadline;
    if (pendingDeadline != null && !pendingDeadline.isAfter(_effectiveNow())) {
      // A parent rebuild can run after a deadline but before the queued timer
      // callback. Preserve that visible active-to-expired transition instead
      // of cancelling its timer and silently rebuilding without onDeadline.
      _applyDeadline(pendingDeadline, rebuild: false);
      return;
    }
    _schedule();
  }

  void _handleDeadline(DateTime deadline) =>
      _applyDeadline(deadline, rebuild: true);

  void _applyDeadline(DateTime deadline, {required bool rebuild}) {
    if (!mounted) return;
    if (_expiredThrough == null || deadline.isAfter(_expiredThrough!)) {
      _expiredThrough = deadline;
    }
    if (rebuild) setState(() {});
    _schedule();
    widget.onDeadline?.call(deadline);
  }

  @override
  void dispose() {
    _expiry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _effectiveNow());
}
