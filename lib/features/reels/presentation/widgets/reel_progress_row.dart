import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_playback_coordinator.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_overlay_atoms.dart';

/// `0:06`. Seconds are always two digits so a row of times never jitters.
String reelClockLabel(Duration value) {
  final total = value.inSeconds < 0 ? 0 : value.inSeconds;
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// How far a Reel has played, as a bar.
///
/// One source of truth: the bar, the labels beside it and the spoken value
/// all read the coordinator's own clock (`ReelPlaybackCoordinator.position`).
/// That clock is a [ValueListenable] rather than a notifier tick, and every
/// piece here sits under a [RepaintBoundary], so a running Reel repaints the
/// bar alone and never rebuilds the card around it (spec §9 line 167).
///
/// Colour never carries the meaning on its own: the same fact is the bar's
/// length, the numeric labels of [ReelProgressTimes], and the spoken value.
class ReelProgressBar extends StatelessWidget {
  const ReelProgressBar({
    required this.position,
    required this.total,
    this.onMedia = true,
    this.announce = true,
    super.key,
  });

  /// The engine clock, in timeline units (0 → [total]).
  final ValueListenable<Duration> position;

  /// The published timeline length. Zero while it is not known yet, which
  /// leaves the track empty instead of inventing a full bar.
  final Duration total;

  /// True while the bar is drawn over footage of unknown luminance, which
  /// decides the unplayed track: white at 32 % over media, a semantic tint
  /// on an app surface.
  final bool onMedia;

  /// False while a [ReelProgressScrubber] over this bar carries the spoken
  /// position as an adjustable slider: one announcement per fact.
  final bool announce;

  /// Slim redesign: a 2 px hairline timeline. On the phone stage it is the
  /// last row of the frame, directly above the dock.
  static const double trackHeight = 2;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final unplayed = onMedia
        ? Colors.white.withValues(alpha: .32)
        : palette.textPrimary.withValues(alpha: .20);
    return RepaintBoundary(
      child: ValueListenableBuilder<Duration>(
        valueListenable: position,
        builder: (context, value, _) {
          final fraction = total.inMilliseconds <= 0
              ? 0.0
              : (value.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
          final track = ClipRRect(
            key: const ValueKey<String>('reel-progress-bar'),
            borderRadius: BorderRadius.circular(trackHeight / 2),
            child: SizedBox(
              height: trackHeight,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(child: ColoredBox(color: unplayed)),
                  FractionallySizedBox(
                    widthFactor: fraction,
                    // Full height: a childless box under the Stack's loose height
                    // would otherwise lay out 0 px tall and draw no progress at all.
                    heightFactor: 1,
                    alignment: AlignmentDirectional.centerStart,
                    child: ColoredBox(color: palette.audioAccent),
                  ),
                ],
              ),
            ),
          );
          if (!announce) return ExcludeSemantics(child: track);
          return Semantics(
            container: true,
            label: copy.contextualText(
              'reels.playbackPosition',
              'Playback position',
              'Pozycja odtwarzania',
            ),
            value: copy.template(
              '{position} of {total}',
              '{position} z {total}',
              values: <String, Object>{
                'position': reelClockLabel(value),
                'total': reelClockLabel(total),
              },
            ),
            excludeSemantics: true,
            child: track,
          );
        },
      ),
    );
  }
}

/// `0:06 / 0:18` — the same clock as [ReelProgressBar], in numbers.
///
/// The bar already carries the spoken value, so these are excluded from
/// semantics: one announcement per fact.
class ReelProgressTimes extends StatelessWidget {
  const ReelProgressTimes({
    required this.position,
    required this.total,
    this.onMedia = true,
    super.key,
  });

  final ValueListenable<Duration> position;
  final Duration total;
  final bool onMedia;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final totalLabel = reelClockLabel(total);
    return RepaintBoundary(
      child: ExcludeSemantics(
        child: ValueListenableBuilder<Duration>(
          valueListenable: position,
          builder: (context, value, _) => Text(
            '${reelClockLabel(value)} / $totalLabel',
            key: const ValueKey<String>('reel-progress-times'),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: onMedia ? Colors.white : palette.textSecondary,
              fontSize: 12,
              height: 1.2,
              fontWeight: FontWeight.w700,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              shadows: onMedia ? overlayTextShadows : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// The bar and its times on one line: the shape the stage uses at the widths
/// where the frame has room for both inside its bottom inset.
class ReelProgressRow extends StatelessWidget {
  const ReelProgressRow({
    required this.position,
    required this.total,
    this.onMedia = true,
    this.announce = true,
    this.barKey,
    super.key,
  });

  final ValueListenable<Duration> position;
  final Duration total;
  final bool onMedia;

  /// See [ReelProgressBar.announce].
  final bool announce;

  /// Wraps the bar alone (not the times), so a [ReelProgressScrubber] can map
  /// a finger onto the track's real extent.
  final GlobalKey? barKey;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        // On a frame this narrow the times would take the whole line and
        // leave no bar at all. The bar keeps the spoken value either way, so
        // the numbers are what gives way — never the progress itself.
        final showTimes =
            !constraints.hasBoundedWidth || constraints.maxWidth >= 160 * scale;
        return Row(
          key: const ValueKey<String>('reel-progress-row'),
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: KeyedSubtree(
                key: barKey,
                child: ReelProgressBar(
                  position: position,
                  total: total,
                  onMedia: onMedia,
                  announce: announce,
                ),
              ),
            ),
            if (showTimes) ...<Widget>[
              const SizedBox(width: 12),
              Flexible(
                child: ReelProgressTimes(
                  position: position,
                  total: total,
                  onMedia: onMedia,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Drag-to-seek over a [ReelProgressBar] (ADR-210).
///
/// A band laid over the hairline, never around it: the visible bar keeps its
/// 2 px, its key and its place, so no stage geometry moves. The band is
/// translucent and claims only a HORIZONTAL drag (and, for a mouse or a
/// trackpad, a click). A touch tap falls through to whatever lies under it —
/// the action rail, the identity block, tap-to-pause and double-tap-to-like
/// — and a vertical swipe that starts here still turns the feed page, because
/// that recognizer wins the arena whenever the finger travels vertically
/// first.
///
/// While the finger is down the track grows to [scrubTrackHeight], a thumb
/// marks the position and a time label rides above it; under Reduce Motion
/// the change is instant. The band carries the spoken position as an
/// adjustable slider (±[keyboardStep]) and takes the arrow keys when focused.
class ReelProgressScrubber extends StatefulWidget {
  const ReelProgressScrubber({
    required this.target,
    required this.position,
    required this.total,
    required this.trackKey,
    this.onMedia = true,
    this.respectSystemGestureInsets = false,
    this.showTimeLabel = true,
    super.key,
  });

  /// False where the stage already prints the times beside the bar: the
  /// floating label would repeat them.
  final bool showTimeLabel;

  /// The playback the finger drives, in practice the Reel's coordinator.
  final ReelScrubTarget target;

  /// The same clock the bar reads.
  final ValueListenable<Duration> position;
  final Duration total;

  /// Wraps the visible bar. The finger is mapped onto that bar's own extent,
  /// whatever the band's size, the stage's padding or the times beside it.
  final GlobalKey trackKey;

  final bool onMedia;

  /// On a full-bleed stage the system edge-swipe (Android back) owns the
  /// outermost strip. The band steps inside it; the mapping is unchanged, so
  /// 0:00 and the end are still reachable from further in.
  final bool respectSystemGestureInsets;

  static const double scrubTrackHeight = 4;
  static const double thumbSize = 12;
  static const Duration keyboardStep = Duration(seconds: 5);

  @override
  State<ReelProgressScrubber> createState() => _ReelProgressScrubberState();
}

class _ReelProgressScrubberState extends State<ReelProgressScrubber> {
  final GlobalKey _bandKey = GlobalKey();
  bool _dragging = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  void didUpdateWidget(ReelProgressScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.target, widget.target) && _dragging) {
      _dragging = false;
      _guard(oldWidget.target.endScrub());
    }
  }

  @override
  void dispose() {
    // A stage that swaps shape mid-drag must not leave the Reel held.
    if (_dragging) _guard(widget.target.endScrub());
    super.dispose();
  }

  void _guard(Future<void> operation) =>
      unawaited(operation.catchError((Object _) {}));

  RenderBox? _box(BuildContext? context) {
    final object = context?.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) {
      return null;
    }
    return object;
  }

  /// The bar's rectangle in the band's own coordinates.
  Rect? _trackRect() {
    final band = _box(_bandKey.currentContext);
    final bar = _box(widget.trackKey.currentContext);
    if (band == null || bar == null) return null;
    final origin = band.globalToLocal(bar.localToGlobal(Offset.zero));
    return origin & bar.size;
  }

  double? _fractionAt(Offset global) {
    final bar = _box(widget.trackKey.currentContext);
    if (bar == null || bar.size.width <= 0) return null;
    final local = bar.globalToLocal(global);
    final fraction = (local.dx / bar.size.width).clamp(0.0, 1.0);
    return Directionality.of(context) == TextDirection.rtl
        ? 1 - fraction
        : fraction;
  }

  void _scrubAt(Offset global) {
    final fraction = _fractionAt(global);
    if (fraction == null) return;
    widget.target.scrubTo(
      Duration(milliseconds: (widget.total.inMilliseconds * fraction).round()),
    );
  }

  void _onStart(DragStartDetails details) {
    if (!widget.target.canSeek) return;
    _dragging = true;
    _guard(widget.target.beginScrub());
    _scrubAt(details.globalPosition);
    unawaited(HapticFeedback.selectionClick());
    setState(() {});
  }

  void _onUpdate(DragUpdateDetails details) {
    if (_dragging) _scrubAt(details.globalPosition);
  }

  void _onEnd(DragEndDetails details) => _release();

  void _release() {
    if (!_dragging) return;
    _dragging = false;
    _guard(widget.target.endScrub());
    if (mounted) setState(() {});
  }

  void _onClick(TapUpDetails details) {
    if (!widget.target.canSeek) return;
    final fraction = _fractionAt(details.globalPosition);
    if (fraction == null) return;
    final target = Duration(
      milliseconds: (widget.total.inMilliseconds * fraction).round(),
    );
    _guard(widget.target.seekBy(target - widget.position.value));
  }

  void _step(bool forward) {
    if (!widget.target.canSeek) return;
    _guard(
      widget.target.seekBy(
        forward
            ? ReelProgressScrubber.keyboardStep
            : -ReelProgressScrubber.keyboardStep,
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _step(!rtl);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _step(rtl);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.target,
      builder: (context, _) {
        final canSeek = widget.target.canSeek;
        final scrubbing = widget.target.isScrubbing || _dragging;
        final insets = widget.respectSystemGestureInsets
            ? MediaQuery.systemGestureInsetsOf(context)
            : EdgeInsets.zero;
        Widget band = RawGestureDetector(
          key: _bandKey,
          behavior: HitTestBehavior.translucent,
          excludeFromSemantics: true,
          gestures: <Type, GestureRecognizerFactory>{
            HorizontalDragGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  HorizontalDragGestureRecognizer
                >(() => HorizontalDragGestureRecognizer(debugOwner: this), (
                  recognizer,
                ) {
                  recognizer
                    ..dragStartBehavior = DragStartBehavior.down
                    ..onStart = _onStart
                    ..onUpdate = _onUpdate
                    ..onEnd = _onEnd
                    ..onCancel = _release;
                }),
            TapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  () => TapGestureRecognizer(
                    debugOwner: this,
                    supportedDevices: const <PointerDeviceKind>{
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.trackpad,
                    },
                  ),
                  (recognizer) => recognizer.onTapUp = _onClick,
                ),
          },
          child: Stack(
            clipBehavior: Clip.none,
            fit: StackFit.expand,
            children: <Widget>[
              Positioned.fill(
                child: IgnorePointer(
                  child: _ScrubFeedback(
                    position: widget.position,
                    total: widget.total,
                    onMedia: widget.onMedia,
                    scrubbing: scrubbing && canSeek,
                    hovered: _hovered && canSeek,
                    focused: _focused && canSeek,
                    showTimeLabel: widget.showTimeLabel,
                    trackRect: _trackRect,
                  ),
                ),
              ),
            ],
          ),
        );
        // Not a FocusableActionDetector: its MouseRegion is opaque and would
        // swallow every tap meant for the controls under the band.
        band = MouseRegion(
          opaque: false,
          cursor: canSeek ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: band,
        );
        band = Focus(
          canRequestFocus: canSeek,
          skipTraversal: !canSeek,
          onKeyEvent: _onKey,
          onFocusChange: (focused) => setState(() => _focused = focused),
          child: band,
        );
        band = Padding(
          padding: EdgeInsets.only(left: insets.left, right: insets.right),
          child: band,
        );
        return _ScrubSemantics(
          enabled: canSeek,
          position: widget.position,
          total: widget.total,
          onIncrease: () => _step(true),
          onDecrease: () => _step(false),
          child: band,
        );
      },
    );
  }
}

/// The one spoken node for the timeline once it can be moved. While it
/// cannot, the band says nothing and the bar keeps its own read-only node.
class _ScrubSemantics extends StatelessWidget {
  const _ScrubSemantics({
    required this.enabled,
    required this.position,
    required this.total,
    required this.onIncrease,
    required this.onDecrease,
    required this.child,
  });

  final bool enabled;
  final ValueListenable<Duration> position;
  final Duration total;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    String spoken(Duration value) {
      final clamped = value < Duration.zero
          ? Duration.zero
          : value > total
          ? total
          : value;
      return copy.template(
        '{position} of {total}',
        '{position} z {total}',
        values: <String, Object>{
          'position': reelClockLabel(clamped),
          'total': reelClockLabel(total),
        },
      );
    }

    // One widget shape either way, so the band's focus and gesture state
    // survive the timeline becoming seekable.
    return ValueListenableBuilder<Duration>(
      valueListenable: position,
      child: child,
      builder: (context, value, child) => Semantics(
        container: enabled,
        slider: enabled ? true : null,
        label: enabled
            ? copy.contextualText(
                'reels.playbackPosition',
                'Playback position',
                'Pozycja odtwarzania',
              )
            : null,
        value: enabled ? spoken(value) : null,
        increasedValue: enabled
            ? spoken(value + ReelProgressScrubber.keyboardStep)
            : null,
        decreasedValue: enabled
            ? spoken(value - ReelProgressScrubber.keyboardStep)
            : null,
        onIncrease: enabled ? onIncrease : null,
        onDecrease: enabled ? onDecrease : null,
        excludeSemantics: true,
        child: child,
      ),
    );
  }
}

/// Paints the scrub state over the bar: a thicker track, a thumb and the
/// previewed time. Nothing here hit-tests.
class _ScrubFeedback extends StatelessWidget {
  const _ScrubFeedback({
    required this.position,
    required this.total,
    required this.onMedia,
    required this.scrubbing,
    required this.hovered,
    required this.focused,
    required this.showTimeLabel,
    required this.trackRect,
  });

  final ValueListenable<Duration> position;
  final Duration total;
  final bool onMedia;
  final bool scrubbing;
  final bool hovered;
  final bool focused;
  final bool showTimeLabel;
  final Rect? Function() trackRect;

  @override
  Widget build(BuildContext context) {
    if (!scrubbing && !hovered && !focused) return const SizedBox.shrink();
    final palette = context.appPalette;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final fade = AppMotion.resolve(context, AppMotion.quick);
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) => ValueListenableBuilder<Duration>(
          valueListenable: position,
          builder: (context, value, _) {
            final bandWidth = constraints.maxWidth;
            // Read after layout: the band never moves the bar, so the rect
            // from the last frame is the rect of this one.
            final rect = trackRect();
            if (rect == null || rect.width <= 0) {
              return const SizedBox.shrink();
            }
            final fraction = total.inMilliseconds <= 0
                ? 0.0
                : (value.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
            final thumbX = rtl
                ? rect.right - rect.width * fraction
                : rect.left + rect.width * fraction;
            const thumb = ReelProgressScrubber.thumbSize;
            // The thumb stays whole at 0:00 and at the end of a full-bleed
            // bar.
            final thumbLeft = (thumbX - thumb / 2)
                .clamp(0.0, math.max(0.0, bandWidth - thumb))
                .toDouble();
            final grow = scrubbing || hovered;
            final height = grow
                ? ReelProgressScrubber.scrubTrackHeight
                : ReelProgressBar.trackHeight;
            final bandHeight = constraints.maxHeight;
            // On the phone stage the hairline IS the frame's bottom edge, so
            // a centred track and thumb would be cut in half. There they grow
            // upward instead: the track covers the hairline from its bottom
            // and the thumb rests on the edge.
            final trackBottom = math.min(
              rect.center.dy + height / 2,
              bandHeight,
            );
            final centerY = trackBottom - height / 2;
            final thumbCenterY = math.min(centerY, bandHeight - thumb / 2);
            final unplayed = onMedia
                ? Colors.white.withValues(alpha: .40)
                : palette.textPrimary.withValues(alpha: .24);
            final thumbColor = onMedia ? Colors.white : palette.audioAccent;
            final ring = Rect.fromLTRB(
              math.max(2, rect.left - 6),
              thumbCenterY - thumb / 2 - 4,
              math.min(bandWidth - 2, rect.right + 6),
              math.min(bandHeight - 1, thumbCenterY + thumb / 2 + 4),
            );
            return Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                if (focused)
                  Positioned.fromRect(
                    rect: ring,
                    child: DecoratedBox(
                      key: const ValueKey<String>('reel-progress-scrub-focus'),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(thumb),
                        border: Border.all(color: palette.focus, width: 2),
                      ),
                    ),
                  ),
                AnimatedPositioned(
                  duration: fade,
                  curve: AppMotion.standardCurve,
                  left: rect.left,
                  width: rect.width,
                  top: centerY - height / 2,
                  height: height,
                  child: ClipRRect(
                    key: const ValueKey<String>('reel-progress-scrub-track'),
                    borderRadius: BorderRadius.circular(height / 2),
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(child: ColoredBox(color: unplayed)),
                        FractionallySizedBox(
                          widthFactor: fraction,
                          // Full height: a childless box under the Stack's loose height
                          // would otherwise lay out 0 px tall and draw no progress at all.
                          heightFactor: 1,
                          alignment: AlignmentDirectional.centerStart,
                          child: ColoredBox(color: palette.audioAccent),
                        ),
                      ],
                    ),
                  ),
                ),
                if (scrubbing) ...<Widget>[
                  Positioned(
                    left: thumbLeft,
                    top: thumbCenterY - thumb / 2,
                    width: thumb,
                    height: thumb,
                    child: DecoratedBox(
                      key: const ValueKey<String>('reel-progress-scrub-thumb'),
                      decoration: BoxDecoration(
                        color: thumbColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: palette.audioAccent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  if (showTimeLabel)
                    Positioned(
                      left: rect.left,
                      width: rect.width,
                      bottom: 0,
                      top: -200,
                      child: CustomSingleChildLayout(
                        delegate: _ScrubLabelLayout(
                          anchorX: thumbX - rect.left,
                          bottomGap: 200 + thumbCenterY - thumb / 2 - 6,
                        ),
                        child: Text(
                          '${reelClockLabel(value)} / ${reelClockLabel(total)}',
                          key: const ValueKey<String>(
                            'reel-progress-scrub-time',
                          ),
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            color: onMedia ? Colors.white : palette.textPrimary,
                            fontSize: 13,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                            shadows: onMedia ? overlayTextShadows : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Centres the time label over the thumb, kept inside the track's extent,
/// with its bottom [bottomGap] from the top of the laid-out area.
class _ScrubLabelLayout extends SingleChildLayoutDelegate {
  const _ScrubLabelLayout({required this.anchorX, required this.bottomGap});

  final double anchorX;
  final double bottomGap;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxLeft = math.max(0.0, size.width - childSize.width);
    final left = (anchorX - childSize.width / 2).clamp(0.0, maxLeft);
    return Offset(left, bottomGap - childSize.height);
  }

  @override
  bool shouldRelayout(_ScrubLabelLayout oldDelegate) =>
      anchorX != oldDelegate.anchorX || bottomGap != oldDelegate.bottomGap;
}
