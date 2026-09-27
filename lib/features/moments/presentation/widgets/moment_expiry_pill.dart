import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/badges/yo_progress_ring.dart';

/// A Moment's availability as one quiet pill (refine-look R12): a 14 px
/// ring showing how much of the author's chosen window is still left, and
/// the SAME copy the line printed before ("Wygasa za 23 godz.", "Dostępny
/// do usunięcia", "Przesyłanie…").
///
/// Everything it draws is a real fact: the ring's value is the remaining
/// share of `createdAt → expiresAt`, and it appears only when both exist
/// and the label is a countdown ([countdown]). A permanent Moment, an
/// upload in progress or a document without a window gets the pill with
/// no ring — never a ring that pretends to count something.
///
/// The pill is neutral (glass fill, control hairline, `textSecondary`
/// label, `interactiveForeground` arc on a `border` track). It turns to
/// `warningForeground` — arc and label — only in the last hour, which is
/// the only moment the countdown asks for attention. High contrast drops
/// the glass for a flat surface with a `borderStrong` edge.
///
/// At an accessibility text size the label wraps to a second line and the
/// ring stays aligned with the first one. The ring is excluded from
/// semantics; the label is read as it is.
///
/// **The one-hour mark is the pill's own.** The owners' expiry scheduler
/// arms timers for the real deadlines only (`expiresAt`), so a card left
/// open across `expiresAt − 1 h` would otherwise stay neutral until some
/// unrelated rebuild. The pill therefore arms ONE one-shot timer for that
/// mark (re-armed in steps of at most a day, so a long window never hands
/// a platform timer an out-of-range delay) and repaints itself amber when
/// it fires. No timer runs for a permanent Moment, an upload, a pill that
/// is already amber or a pill with a fixed [now].
class MomentExpiryPill extends StatefulWidget {
  const MomentExpiryPill({
    required this.label,
    this.createdAt,
    this.expiresAt,
    this.countdown = true,
    this.now,
    this.clock,
    this.labelKey,
    super.key,
  });

  /// The already-localized availability line.
  final String label;

  final DateTime? createdAt;
  final DateTime? expiresAt;

  /// False for a label that is not a countdown (uploading): no ring, no
  /// amber.
  final bool countdown;

  /// A fixed instant the ring and the amber threshold read (a snapshot):
  /// no timer is armed. Null reads [clock].
  final DateTime? now;

  /// The live clock, `DateTime.now` by default; a test injects its own to
  /// cross the one-hour mark.
  final DateTime Function()? clock;

  /// Goes on the label's [Text], where existing finders look for it.
  final Key? labelKey;

  static const double ringSize = 14;
  static const double ringStroke = 2;

  /// Below this much time left the pill turns amber.
  static const Duration urgentBelow = Duration(hours: 1);

  /// The remaining share of the window, 0..1, or null when there is no real
  /// window to measure.
  static double? remainingShare({
    required DateTime? createdAt,
    required DateTime? expiresAt,
    required DateTime now,
  }) {
    if (createdAt == null || expiresAt == null) return null;
    final window = expiresAt.difference(createdAt).inMilliseconds;
    if (window <= 0) return null;
    final left = expiresAt.difference(now).inMilliseconds;
    return (left / window).clamp(0.0, 1.0);
  }

  /// Whether the Moment is inside its last hour (and not already gone).
  static bool isUrgent({required DateTime? expiresAt, required DateTime now}) {
    if (expiresAt == null) return false;
    final left = expiresAt.difference(now);
    return !left.isNegative && left < urgentBelow;
  }

  /// The longest single wait the pill hands a timer; a later mark is
  /// reached by re-arming.
  static const Duration longestWait = Duration(days: 1);

  @override
  State<MomentExpiryPill> createState() => _MomentExpiryPillState();
}

class _MomentExpiryPillState extends State<MomentExpiryPill> {
  Timer? _urgentTimer;

  DateTime get _now => widget.now ?? (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _armUrgentMark();
  }

  @override
  void didUpdateWidget(MomentExpiryPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expiresAt != widget.expiresAt ||
        oldWidget.countdown != widget.countdown ||
        oldWidget.now != widget.now ||
        oldWidget.clock != widget.clock) {
      _armUrgentMark();
    }
  }

  @override
  void dispose() {
    _urgentTimer?.cancel();
    super.dispose();
  }

  /// One timer for the moment the pill must turn amber, or none.
  void _armUrgentMark() {
    _urgentTimer?.cancel();
    _urgentTimer = null;
    final expiresAt = widget.expiresAt;
    if (!widget.countdown || widget.now != null || expiresAt == null) return;
    final wait = expiresAt
        .subtract(MomentExpiryPill.urgentBelow)
        .difference(_now);
    // Past the mark: already amber (or gone), nothing left to wait for.
    if (wait.isNegative) return;
    // A millisecond past the mark, so the rebuild reads strictly less than
    // an hour left.
    final step = wait >= MomentExpiryPill.longestWait
        ? MomentExpiryPill.longestWait
        : wait + const Duration(milliseconds: 1);
    _urgentTimer = Timer(step, () {
      if (!mounted) return;
      setState(_armUrgentMark);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    final countdown = widget.countdown;
    final createdAt = widget.createdAt;
    final expiresAt = widget.expiresAt;
    final label = widget.label;
    final labelKey = widget.labelKey;
    const ringSize = MomentExpiryPill.ringSize;
    const ringStroke = MomentExpiryPill.ringStroke;
    final clock = _now;
    final share = countdown
        ? MomentExpiryPill.remainingShare(
            createdAt: createdAt,
            expiresAt: expiresAt,
            now: clock,
          )
        : null;
    final urgent =
        countdown &&
        MomentExpiryPill.isUrgent(expiresAt: expiresAt, now: clock);
    final ink = urgent ? palette.warningForeground : palette.textSecondary;
    final style = AppTypography.bodySmall.copyWith(
      color: ink,
      fontWeight: FontWeight.w600,
      height: 1.3,
    );
    // The ring sits on the first line's centre, whatever the text scale.
    final lineHeight =
        MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height!;
    final ringTop = ((lineHeight - ringSize) / 2).clamp(0.0, double.infinity);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.pill,
        color: highContrast ? palette.surface : palette.glass,
        border: Border.all(
          color: highContrast ? palette.borderStrong : palette.hairlineControl,
        ),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          share == null ? 10 : 7,
          3,
          10,
          3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (share != null) ...[
              Padding(
                padding: EdgeInsets.only(top: ringTop),
                child: YoProgressRing(
                  value: share,
                  size: ringSize,
                  stroke: ringStroke,
                  trackColor: highContrast
                      ? palette.borderStrong
                      : palette.border,
                  arcColor: urgent
                      ? palette.warningForeground
                      : palette.interactiveForeground,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                key: labelKey,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
