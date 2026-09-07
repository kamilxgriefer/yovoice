import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';

/// Longest selection the Reel publish contract accepts — five minutes. It
/// mirrors `functions/reels/contract.js` (`MAX_DURATION_MS`) through the
/// client's single source of truth, [maxReelDurationMs]; raising it is a
/// server decision, so the client only displays and enforces the cap.
const int reelMaxTrimSelectionMs = maxReelDurationMs;

/// Shortest selection the Reel publish contract accepts.
const int reelMinTrimSelectionMs = minReelDurationMs;

/// Which boundary of the selection a gesture or assistive action moves.
enum ReelTrimHandle { start, end }

/// The selected `[startMs, endMs]` window of a local video.
@immutable
class ReelTrimRange {
  const ReelTrimRange(this.startMs, this.endMs);

  final int startMs;
  final int endMs;

  int get lengthMs => math.max(0, endMs - startMs);

  int msFor(ReelTrimHandle handle) =>
      handle == ReelTrimHandle.start ? startMs : endMs;

  @override
  bool operator ==(Object other) =>
      other is ReelTrimRange &&
      other.startMs == startMs &&
      other.endMs == endMs;

  @override
  int get hashCode => Object.hash(startMs, endMs);

  @override
  String toString() => 'ReelTrimRange($startMs, $endMs)';
}

/// Moves one handle of [range] towards [targetMs] and clamps it so the
/// selection stays inside the media, at least [minSelectionMs] long and at
/// most [maxSelectionMs] long. Only the moved handle changes: a handle that
/// runs into the other one stops there instead of freezing or pushing it.
ReelTrimRange moveReelTrimHandle({
  required ReelTrimRange range,
  required ReelTrimHandle handle,
  required int targetMs,
  required int durationMs,
  int minSelectionMs = reelMinTrimSelectionMs,
  int maxSelectionMs = reelMaxTrimSelectionMs,
}) {
  final duration = math.max(0, durationMs);
  final minimum = math.max(0, math.min(minSelectionMs, duration));
  final maximum = math.max(minimum, maxSelectionMs);
  switch (handle) {
    case ReelTrimHandle.start:
      final end = range.endMs.clamp(0, duration);
      final low = math.max(0, end - maximum);
      final high = math.max(low, end - minimum);
      return ReelTrimRange(targetMs.clamp(low, high), end);
    case ReelTrimHandle.end:
      final start = range.startMs.clamp(0, duration);
      final high = math.min(duration, start + maximum);
      final low = math.min(high, start + minimum);
      return ReelTrimRange(start, targetMs.clamp(low, high));
  }
}

/// Pure pixel ↔ millisecond mapping for a strip that is [width] wide.
///
/// The timeline track is inset by one handle plus its hit slop on each side,
/// so a handle at 0 or at the end still sits entirely inside the strip and
/// keeps its full 44 px target.
@immutable
class ReelTrimGeometry {
  const ReelTrimGeometry({
    required this.width,
    required this.durationMs,
    this.handleWidth = ReelTrimStrip.handleWidth,
    this.edgeInset = ReelTrimStrip.edgeInset,
  });

  final double width;
  final int durationMs;
  final double handleWidth;
  final double edgeInset;

  double get trackLeft => edgeInset + handleWidth;
  double get trackWidth => math.max(1.0, width - 2 * trackLeft);
  double get trackRight => trackLeft + trackWidth;

  double xForMs(int ms) {
    if (durationMs <= 0) return trackLeft;
    return trackLeft + trackWidth * (ms / durationMs).clamp(0.0, 1.0);
  }

  int msForX(double x) {
    if (durationMs <= 0) return 0;
    return ((x - trackLeft) / trackWidth * durationMs).round().clamp(
      0,
      durationMs,
    );
  }
}

/// `m:ss` for a timeline position; Reels are at most 90 s so minutes stay
/// single-digit.
String formatReelTrimClock(int ms) {
  final total = math.max(0, (ms / 1000).round());
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// On-video trimmer for a local Reel draft.
///
/// A horizontal timeline of the whole clip with a draggable start and end
/// handle, a dimmed scrim outside the selection, a playhead that follows the
/// preview, and a live `start–end · length` label next to the publish cap.
/// The strip is presentation only: it reports the new range and the handle's
/// time through callbacks, and the composer owns the recipe and the preview.
/// Phase 1 uses the video itself as the frame display while a handle moves;
/// a multi-frame filmstrip needs a thumbnail decoder the app does not ship.
class ReelTrimStrip extends StatefulWidget {
  const ReelTrimStrip({
    required this.durationMs,
    required this.range,
    required this.onChanged,
    this.playhead,
    this.onScrub,
    this.onEditStarted,
    this.onEditEnded,
    this.overlay = false,
    this.maxSelectionMs = reelMaxTrimSelectionMs,
    this.minSelectionMs = reelMinTrimSelectionMs,
    super.key,
  });

  /// Full length of the local clip.
  final int durationMs;
  final ReelTrimRange range;

  /// Null disables both handles (the draft is locked for a retry).
  final ValueChanged<ReelTrimRange>? onChanged;

  /// Current preview position; the playhead line follows it without
  /// rebuilding the composer.
  final ValueListenable<Duration>? playhead;

  /// Fired while a handle moves with that handle's time, so the preview can
  /// show the exact frame under the finger.
  final void Function(ReelTrimHandle handle, int positionMs)? onScrub;
  final VoidCallback? onEditStarted;
  final VoidCallback? onEditEnded;

  /// Drawn over the video (wide layouts) instead of on a surface below it.
  final bool overlay;
  final int maxSelectionMs;
  final int minSelectionMs;

  static const double handleWidth = 20;
  static const double hitExtent = 44;
  static const double trackHeight = 40;
  static const double edgeInset = (hitExtent - handleWidth) / 2;
  static const int stepMs = 1000;

  @override
  State<ReelTrimStrip> createState() => _ReelTrimStripState();
}

class _ReelTrimStripState extends State<ReelTrimStrip> {
  ReelTrimHandle? _dragging;
  double _dragX = 0;
  ReelTrimGeometry _geometry = const ReelTrimGeometry(width: 0, durationMs: 0);

  bool get _enabled => widget.onChanged != null && widget.durationMs > 0;

  ReelTrimRange _moved(ReelTrimHandle handle, int targetMs) =>
      moveReelTrimHandle(
        range: widget.range,
        handle: handle,
        targetMs: targetMs,
        durationMs: widget.durationMs,
        minSelectionMs: widget.minSelectionMs,
        maxSelectionMs: widget.maxSelectionMs,
      );

  void _apply(ReelTrimHandle handle, int targetMs) {
    final next = _moved(handle, targetMs);
    if (next != widget.range) widget.onChanged?.call(next);
    widget.onScrub?.call(handle, next.msFor(handle));
  }

  void _dragStart(ReelTrimHandle handle, DragStartDetails details) {
    if (!_enabled || _dragging != null) return;
    setState(() => _dragging = handle);
    _dragX = _geometry.xForMs(widget.range.msFor(handle));
    widget.onEditStarted?.call();
    widget.onScrub?.call(handle, widget.range.msFor(handle));
  }

  void _dragUpdate(ReelTrimHandle handle, DragUpdateDetails details) {
    if (_dragging != handle) return;
    _dragX += details.delta.dx;
    _apply(handle, _geometry.msForX(_dragX));
  }

  void _dragEnd(ReelTrimHandle handle) {
    if (_dragging != handle) return;
    setState(() => _dragging = null);
    widget.onEditEnded?.call();
  }

  void _step(ReelTrimHandle handle, int deltaMs) {
    if (!_enabled) return;
    widget.onEditStarted?.call();
    _apply(handle, widget.range.msFor(handle) + deltaMs);
    widget.onEditEnded?.call();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final theme = Theme.of(context);
    final overlay = widget.overlay;
    final range = widget.range;
    final enabled = _enabled;
    final seconds = copy.template(
      '{seconds} s',
      '{seconds} s',
      values: <String, Object>{'seconds': (range.lengthMs / 1000).round()},
    );
    final rangeLabel =
        '${formatReelTrimClock(range.startMs)}–'
        '${formatReelTrimClock(range.endMs)} · $seconds';
    final capLabel = copy.template(
      'Max {seconds} s',
      'Maks. {seconds} s',
      values: <String, Object>{'seconds': widget.maxSelectionMs ~/ 1000},
    );
    final labelColor = overlay ? Colors.white : palette.textPrimary;
    final capColor = overlay
        ? Colors.white.withValues(alpha: .82)
        : palette.textSecondary;
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: labelColor,
      fontWeight: FontWeight.w800,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    Widget labels = Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 2,
      children: <Widget>[
        Text(
          rangeLabel,
          key: const ValueKey('reel-trim-range-label'),
          style: labelStyle,
        ),
        Text(
          capLabel,
          key: const ValueKey('reel-trim-cap-label'),
          style: labelStyle?.copyWith(
            color: capColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
    if (overlay) {
      labels = DecoratedBox(
        decoration: BoxDecoration(
          color: AppPalette.dark.scrim.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: labels,
        ),
      );
    }
    // Over media the strip keeps the immersive dark chrome in both themes;
    // on a surface it takes the theme's semantic roles.
    final handleFill = overlay ? AppPalette.dark.focus : palette.focus;
    final grip = handleFill.computeLuminance() > .4
        ? AppColors.contrastInk
        : Colors.white;
    final trackBase = overlay
        ? AppPalette.dark.scrim.withValues(alpha: .28)
        : palette.surfaceRaised;
    final scrim = overlay
        ? AppPalette.dark.scrim.withValues(alpha: .62)
        : palette.scrim.withValues(alpha: .5);
    final tick = overlay
        ? Colors.white.withValues(alpha: .45)
        : palette.borderStrong;
    final playheadColor = overlay ? Colors.white : palette.textPrimary;
    final playheadOutline = overlay ? AppPalette.dark.scrim : palette.surface;
    return Semantics(
      container: true,
      label: copy.text('Trim video', 'Przytnij film'),
      value: rangeLabel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ExcludeSemantics(child: labels),
          const SizedBox(height: 4),
          SizedBox(
            height: ReelTrimStrip.hitExtent,
            child: LayoutBuilder(
              builder: (context, constraints) {
                _geometry = ReelTrimGeometry(
                  width: constraints.maxWidth,
                  durationMs: widget.durationMs,
                );
                final geometry = _geometry;
                final startX = geometry.xForMs(range.startMs);
                final endX = geometry.xForMs(range.endMs);
                return Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned(
                      left: geometry.trackLeft,
                      width: geometry.trackWidth,
                      top:
                          (ReelTrimStrip.hitExtent -
                              ReelTrimStrip.trackHeight) /
                          2,
                      height: ReelTrimStrip.trackHeight,
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _TrackPainter(
                            startX: startX - geometry.trackLeft,
                            endX: endX - geometry.trackLeft,
                            durationMs: widget.durationMs,
                            base: trackBase,
                            scrim: scrim,
                            tick: tick,
                            frame: enabled
                                ? handleFill
                                : handleFill.withValues(alpha: .45),
                          ),
                        ),
                      ),
                    ),
                    if (widget.playhead != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ValueListenableBuilder<Duration>(
                            valueListenable: widget.playhead!,
                            builder: (context, position, _) {
                              final ms = position.inMilliseconds;
                              if (widget.durationMs <= 0 ||
                                  ms < 0 ||
                                  ms > widget.durationMs) {
                                return const SizedBox.shrink();
                              }
                              return CustomPaint(
                                key: const ValueKey('reel-trim-playhead'),
                                painter: _PlayheadPainter(
                                  x: geometry.xForMs(ms),
                                  color: playheadColor,
                                  outline: playheadOutline,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    _handle(
                      ReelTrimHandle.start,
                      copy: copy,
                      x: startX - ReelTrimStrip.handleWidth,
                      fill: handleFill,
                      grip: grip,
                      shadow: palette.shadow,
                      enabled: enabled,
                    ),
                    _handle(
                      ReelTrimHandle.end,
                      copy: copy,
                      x: endX,
                      fill: handleFill,
                      grip: grip,
                      shadow: palette.shadow,
                      enabled: enabled,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _handle(
    ReelTrimHandle handle, {
    required AppLocalizations copy,
    required double x,
    required Color fill,
    required Color grip,
    required Color shadow,
    required bool enabled,
  }) {
    final isStart = handle == ReelTrimHandle.start;
    final ms = widget.range.msFor(handle);
    final active = _dragging == handle;
    final rounded = Radius.circular(ReelTrimStrip.handleWidth / 2);
    const square = Radius.circular(3);
    return Positioned(
      left: x - ReelTrimStrip.edgeInset,
      top: 0,
      width: ReelTrimStrip.hitExtent,
      height: ReelTrimStrip.hitExtent,
      child: Semantics(
        key: ValueKey('reel-trim-handle-${handle.name}'),
        slider: true,
        enabled: enabled,
        label: isStart
            ? copy.text('Trim start', 'Początek przycięcia')
            : copy.text('Trim end', 'Koniec przycięcia'),
        value: formatReelTrimClock(ms),
        increasedValue: formatReelTrimClock(
          _moved(handle, ms + ReelTrimStrip.stepMs).msFor(handle),
        ),
        decreasedValue: formatReelTrimClock(
          _moved(handle, ms - ReelTrimStrip.stepMs).msFor(handle),
        ),
        onIncrease: enabled ? () => _step(handle, ReelTrimStrip.stepMs) : null,
        onDecrease: enabled ? () => _step(handle, -ReelTrimStrip.stepMs) : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: enabled
              ? (details) => _dragStart(handle, details)
              : null,
          onHorizontalDragUpdate: enabled
              ? (details) => _dragUpdate(handle, details)
              : null,
          onHorizontalDragEnd: enabled ? (_) => _dragEnd(handle) : null,
          onHorizontalDragCancel: enabled ? () => _dragEnd(handle) : null,
          child: MouseRegion(
            cursor: enabled
                ? SystemMouseCursors.resizeLeftRight
                : SystemMouseCursors.basic,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                width: ReelTrimStrip.handleWidth,
                height: active
                    ? ReelTrimStrip.hitExtent
                    : ReelTrimStrip.trackHeight,
                decoration: BoxDecoration(
                  color: enabled ? fill : fill.withValues(alpha: .45),
                  borderRadius: BorderRadius.horizontal(
                    left: isStart ? rounded : square,
                    right: isStart ? square : rounded,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: shadow.withValues(alpha: .35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 3,
                    height: 14,
                    decoration: BoxDecoration(
                      color: grip,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  const _TrackPainter({
    required this.startX,
    required this.endX,
    required this.durationMs,
    required this.base,
    required this.scrim,
    required this.tick,
    required this.frame,
  });

  final double startX;
  final double endX;
  final int durationMs;
  final Color base;
  final Color scrim;
  final Color tick;
  final Color frame;

  static const List<int> _tickSteps = <int>[
    1000,
    2000,
    5000,
    10000,
    15000,
    30000,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.save();
    canvas.clipRRect(rounded);
    canvas.drawRect(rect, Paint()..color = base);
    if (durationMs > 0) {
      var step = _tickSteps.last;
      for (final candidate in _tickSteps) {
        if (size.width * candidate / durationMs >= 10) {
          step = candidate;
          break;
        }
      }
      final tickPaint = Paint()
        ..color = tick
        ..strokeWidth = 1;
      for (var ms = step; ms < durationMs; ms += step) {
        final x = size.width * ms / durationMs;
        final major = ms % (step * 5) == 0;
        canvas.drawLine(
          Offset(x, size.height * (major ? .22 : .38)),
          Offset(x, size.height * (major ? .78 : .62)),
          tickPaint,
        );
      }
    }
    final scrimPaint = Paint()..color = scrim;
    if (startX > 0) {
      canvas.drawRect(Rect.fromLTRB(0, 0, startX, size.height), scrimPaint);
    }
    if (endX < size.width) {
      canvas.drawRect(
        Rect.fromLTRB(endX, 0, size.width, size.height),
        scrimPaint,
      );
    }
    canvas.restore();
    final framePaint = Paint()
      ..color = frame
      ..strokeWidth = 3;
    canvas.drawLine(Offset(startX, 1.5), Offset(endX, 1.5), framePaint);
    canvas.drawLine(
      Offset(startX, size.height - 1.5),
      Offset(endX, size.height - 1.5),
      framePaint,
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.startX != startX ||
      old.endX != endX ||
      old.durationMs != durationMs ||
      old.base != base ||
      old.scrim != scrim ||
      old.tick != tick ||
      old.frame != frame;
}

class _PlayheadPainter extends CustomPainter {
  const _PlayheadPainter({
    required this.x,
    required this.color,
    required this.outline,
  });

  final double x;
  final Color color;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final outlinePaint = Paint()
      ..color = outline
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x, 4), Offset(x, size.height - 4), outlinePaint);
    canvas.drawLine(Offset(x, 4), Offset(x, size.height - 4), linePaint);
    canvas.drawCircle(Offset(x, 4), 4.5, Paint()..color = outline);
    canvas.drawCircle(Offset(x, 4), 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PlayheadPainter old) =>
      old.x != x || old.color != color || old.outline != outline;
}
