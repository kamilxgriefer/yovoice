import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/identity/vip_badge.dart';
import 'package:yovoice/shared/widgets/identity/vip_meaning_sheet.dart';

/// The owner-chosen VIP mark (2026-09-28, tick variant B): a flat 10-lobe
/// purple rosette with a white check, drawn right after a display name.
///
/// It is a mark, not a pill: it sits beside the name the way a verified tick
/// does and carries the accessible label "VIP". The fill is the brand primary
/// on Pearl and the same primary lifted 12 % toward white on Dark (#8B48F8),
/// derived here rather than copied as a new literal, so the palette in
/// [AppColors] stays the single source of truth.
class YoVipRosette extends StatelessWidget {
  const YoVipRosette({
    this.diameter = 16,
    this.excludeSemantics = false,
    super.key,
  });

  final double diameter;

  /// True when the caller already folds "VIP" into its own label.
  final bool excludeSemantics;

  /// The mark's diameter for a name set at [fontSize]: 0.92 × the size,
  /// clamped to 12–24 px.
  static double diameterFor(double fontSize) =>
      (fontSize * .92).clamp(12.0, 24.0).toDouble();

  /// The gap between a name and the mark: max(3, 0.18 × the size).
  static double gapFor(double fontSize) => math.max(3, .18 * fontSize);

  /// The fill for [brightness].
  static Color fillFor(Brightness brightness) => brightness == Brightness.dark
      ? Color.lerp(AppColors.primary, AppColors.white, .12)!
      : AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox(
      width: diameter,
      height: diameter,
      child: CustomPaint(
        painter: _RosettePainter(fillFor(Theme.of(context).brightness)),
        child: Center(
          child: Icon(
            Icons.check_rounded,
            size: diameter * .62,
            color: AppColors.white,
          ),
        ),
      ),
    );
    if (excludeSemantics) return ExcludeSemantics(child: mark);
    return Semantics(
      label: VipBadge.label,
      child: ExcludeSemantics(child: mark),
    );
  }
}

/// Ten lobe discs on a ring over a centre disc: peaks at R, valleys ≈ 0.81 R.
class _RosettePainter extends CustomPainter {
  _RosettePainter(this.fill);

  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = Offset(size.width / 2, size.height / 2);
    final ring = .75 * r;
    final lobe = .25 * r;
    var path = Path()..addOval(Rect.fromCircle(center: c, radius: ring));
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / 10;
      final p = c + Offset(math.cos(a), math.sin(a)) * ring;
      path = Path.combine(
        PathOperation.union,
        path,
        Path()..addOval(Rect.fromCircle(center: p, radius: lobe)),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = fill
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_RosettePainter oldDelegate) => oldDelegate.fill != fill;
}

/// A display name with the [YoVipRosette] hugging it when the account is VIP.
///
/// This is the premium-pages spec's `NameWithBadge` (§4.6, variant B): every
/// surface that shows a name with the VIP mark uses it, driven by the
/// server-written `publicBadges.isVip`.
///
/// VIP comes from [PublicIdentityRepository] (batched, cached,
/// server-authoritative `isVip`), resolved and re-resolved on the
/// repository's revision exactly like `UserIdentityBadges`; until the answer
/// lands the plain name is shown. [isVip] overrides the lookup (previews and
/// callers that already hold the answer).
///
/// With [maxLines] == 1 (the default) the name ellipsizes and the mark never
/// disappears. With more lines the mark rides the last word as an inline
/// span glued by a word joiner; when the text overflows, the name is trimmed
/// with "…" before the mark so the mark survives truncation.
///
/// Headers (a profile's or a Page's name, never a list row) set
/// [explainOnTap]: the mark then becomes a 44×44 button labelled "VIP" that
/// opens [showVipMeaningSheet]. The painted mark does not move; the widget
/// grows only as far as the target needs (to at least 44 px tall).
class NameWithVipMark extends StatefulWidget {
  const NameWithVipMark({
    required this.uid,
    required this.name,
    required this.style,
    this.maxLines = 1,
    this.isVip,
    this.repository,
    this.markSemantics = true,
    this.semanticsLabel,
    this.explainOnTap = false,
    this.onExplain,
    this.textAlign = TextAlign.start,
    this.headerRoom = EdgeInsets.zero,
    super.key,
  });

  /// The side of the header tap target (premium-pages §4.6, R14).
  static const double explainTargetSize = 44;

  final String uid;
  final String name;
  final TextStyle style;
  final int? maxLines;
  final bool? isVip;

  /// Test seam; the app uses [PublicIdentityRepository.instance].
  final PublicIdentityRepository? repository;

  /// False when the caller already includes "VIP" in its own label.
  final bool markSemantics;

  /// Replaces the name's own semantics label (e.g. "Ola, reacted 👍"); the
  /// mark still adds "VIP" unless [markSemantics] is false.
  final String? semanticsLabel;

  /// Header only: the mark is a 44×44 "VIP" button that explains what VIP
  /// means. List rows keep the plain mark.
  final bool explainOnTap;

  /// Replaces the default action of [explainOnTap] ([showVipMeaningSheet]).
  final VoidCallback? onExplain;

  /// Alignment of a wrapping name (a centred rail tile). A one-line name is
  /// sized to its glyphs, so its parent positions it.
  final TextAlign textAlign;

  /// The header's own gaps above and below the name (only [EdgeInsets.top]
  /// and [EdgeInsets.bottom] are read). A wrapping name's 44 px target
  /// shares them instead of adding height of its own: it lifts into the gap
  /// above (never past this widget's top), so the name keeps the approved
  /// render's position and the header below it moves as little as it can
  /// (deviation sheet §13). Always applied, VIP or not.
  final EdgeInsets headerRoom;

  @override
  State<NameWithVipMark> createState() => _NameWithVipMarkState();
}

class _NameWithVipMarkState extends State<NameWithVipMark> {
  bool _vip = false;
  late PublicIdentityRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? PublicIdentityRepository.instance;
    _repository.revision.addListener(_resolve);
    _resolve();
  }

  @override
  void didUpdateWidget(NameWithVipMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.repository ?? PublicIdentityRepository.instance;
    final repositoryChanged = !identical(next, _repository);
    if (repositoryChanged) {
      _repository.revision.removeListener(_resolve);
      _repository = next;
      _repository.revision.addListener(_resolve);
    }
    if (oldWidget.uid != widget.uid || repositoryChanged) {
      _vip = false;
      _resolve();
    }
  }

  @override
  void dispose() {
    _repository.revision.removeListener(_resolve);
    super.dispose();
  }

  void _resolve() {
    if (!mounted || widget.isVip != null) return;
    final cached = _repository.peek(widget.uid);
    if (cached != null) {
      if (cached.isVip != _vip) setState(() => _vip = cached.isVip);
      return;
    }
    final requested = widget.uid;
    _repository.resolve(requested).then((identity) {
      if (!mounted || requested != widget.uid) return;
      if (identity.isVip != _vip) setState(() => _vip = identity.isVip);
    });
  }

  @override
  Widget build(BuildContext context) {
    final room = EdgeInsets.only(
      top: widget.headerRoom.top,
      bottom: widget.headerRoom.bottom,
    );
    final name = _name(context, room);
    // A wrapping VIP name spends the room itself (around its target).
    if (name is _MultiLineVipName || room == EdgeInsets.zero) return name;
    return Padding(padding: room, child: name);
  }

  Widget _name(BuildContext context, EdgeInsets room) {
    final vip = widget.isVip ?? _vip;
    final style = widget.style;
    final maxLines = widget.maxLines;
    if (!vip) {
      return Text(
        widget.name,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        semanticsLabel: widget.semanticsLabel,
        textAlign: widget.textAlign,
        style: style,
      );
    }
    // The mark scales with the reader's text size, like the name beside it.
    final fontSize = MediaQuery.textScalerOf(
      context,
    ).scale(style.fontSize ?? 14);
    final diameter = YoVipRosette.diameterFor(fontSize);
    final gap = YoVipRosette.gapFor(fontSize);
    final explain = widget.explainOnTap;
    final onExplain = widget.onExplain ?? () => showVipMeaningSheet(context);
    final mark = Padding(
      padding: EdgeInsetsDirectional.only(start: gap),
      child: YoVipRosette(
        diameter: diameter,
        // The header button carries "VIP" itself.
        excludeSemantics: explain || !widget.markSemantics,
      ),
    );
    if (maxLines == 1) {
      const target = NameWithVipMark.explainTargetSize;
      final boxWidth = math.max(target, gap + diameter);
      final ltr = Directionality.of(context) == TextDirection.ltr;
      final Widget trailing = explain
          ? _VipMarkButton(
              key: const ValueKey('vip-mark-explain'),
              onTap: onExplain,
              size: Size(boxWidth, target),
              markRect: Rect.fromLTWH(
                ltr ? gap : boxWidth - gap - diameter,
                (target - diameter) / 2,
                diameter,
                diameter,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: mark,
              ),
            )
          : mark;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              widget.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // Size to the drawn glyphs so the mark hugs an ellipsized name
              // instead of floating at the constraint's edge.
              textWidthBasis: TextWidthBasis.longestLine,
              semanticsLabel: widget.semanticsLabel,
              style: style,
            ),
          ),
          trailing,
        ],
      );
    }
    // A WidgetSpan child is laid out in unscaled units and then scaled by
    // the paragraph's text-scale factor at its font size, so the inline mark
    // is built at 1/factor of the size it must end up with.
    final spanFontSize =
        DefaultTextStyle.of(context).style.merge(style).fontSize ?? 14;
    final spanScaled = MediaQuery.textScalerOf(context).scale(spanFontSize);
    final spanFactor = spanFontSize <= 0 || spanScaled <= 0
        ? 1.0
        : spanScaled / spanFontSize;
    final inlineMark = Padding(
      padding: EdgeInsetsDirectional.only(start: gap / spanFactor),
      // The paragraph's own label carries "VIP" (below): an inline span's
      // node would sit inside the excluded paragraph and never be read.
      child: YoVipRosette(
        diameter: diameter / spanFactor,
        excludeSemantics: true,
      ),
    );
    return _MultiLineVipName(
      name: widget.name,
      semanticsLabel: widget.semanticsLabel,
      // The header button carries "VIP" itself; a caller that folds it into
      // its own label says so through [markSemantics].
      announceVip: !explain && widget.markSemantics,
      style: style,
      maxLines: maxLines,
      mark: inlineMark,
      markSize: Size(gap + diameter, diameter),
      markGap: gap,
      onExplain: explain ? onExplain : null,
      textAlign: widget.textAlign,
      room: room,
    );
  }
}

class _MultiLineVipName extends StatelessWidget {
  const _MultiLineVipName({
    required this.name,
    required this.style,
    required this.maxLines,
    required this.mark,
    required this.markSize,
    required this.markGap,
    this.semanticsLabel,
    this.announceVip = true,
    this.onExplain,
    this.textAlign = TextAlign.start,
    this.room = EdgeInsets.zero,
  });

  final String name;
  final String? semanticsLabel;

  /// [NameWithVipMark.headerRoom], vertical only.
  final EdgeInsets room;

  /// Appends "VIP" to the paragraph's label.
  final bool announceVip;
  final TextAlign textAlign;
  final TextStyle style;
  final int? maxLines;
  final Widget mark;
  final Size markSize;
  final double markGap;

  /// Non-null in header mode: a 44×44 button is laid over the painted mark.
  final VoidCallback? onExplain;

  InlineSpan _span(String text) => TextSpan(
    children: [
      // U+2060 WORD JOINER keeps the mark on the last word's line.
      TextSpan(text: '$text⁠'),
      WidgetSpan(alignment: PlaceholderAlignment.middle, child: mark),
    ],
  );

  /// Lays the 44×44 button over the inline mark without moving any glyph:
  /// the text takes the full [width] (so its line boxes match the measuring
  /// painter's), and top/bottom padding is added only where the target would
  /// otherwise reach past the paragraph.
  Widget _withExplainTarget({
    required Widget text,
    required String shown,
    required double width,
    required TextStyle measured,
    required TextScaler scaler,
    required TextDirection direction,
    required VoidCallback onTap,
  }) {
    const target = NameWithVipMark.explainTargetSize;
    final painter = TextPainter(
      text: TextSpan(style: measured, children: [_span(shown)]),
      textDirection: direction,
      textAlign: textAlign,
      textScaler: scaler,
      maxLines: maxLines,
    );
    painter.setPlaceholderDimensions(<PlaceholderDimensions>[
      PlaceholderDimensions(
        size: markSize,
        alignment: PlaceholderAlignment.middle,
      ),
    ]);
    painter.layout(minWidth: width, maxWidth: width);
    final boxes = painter.inlinePlaceholderBoxes ?? const <TextBox>[];
    final height = painter.height;
    painter.dispose();
    if (boxes.isEmpty) return Padding(padding: room, child: text);
    final box = boxes.first.toRect();
    final diameter = markSize.height;
    // The rosette sits after the start gap, inside the placeholder box.
    final markLeft = direction == TextDirection.ltr
        ? box.left + markGap
        : box.right - markGap - diameter;
    final markCenter = Offset(markLeft + diameter / 2, box.center.dy);
    // Centred on the mark, the target reaches past the paragraph by
    // -centredTop above and overhang below. It lifts only into [room]'s top
    // gap (keeping the mark inside it) to take height off the bottom; with
    // no room it stays centred on the mark.
    final centredTop = markCenter.dy - target / 2;
    final overhang = math.max(0.0, markCenter.dy + target / 2 - height);
    final lift = math.min(
      overhang,
      math.min(
        math.max(0.0, math.min(room.top, room.top + centredTop)),
        (target - diameter) / 2,
      ),
    );
    final padTop = math.max(room.top, lift - centredTop);
    final padBottom = math.max(room.bottom, overhang - lift);
    final left = (markCenter.dx - target / 2)
        .clamp(0.0, math.max(0.0, width - target))
        .toDouble();
    final top = centredTop - lift + padTop;
    return SizedBox(
      width: width,
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(top: padTop, bottom: padBottom),
            child: SizedBox(width: width, child: text),
          ),
          Positioned(
            left: left,
            top: top,
            width: target,
            height: target,
            child: _VipMarkButton(
              key: const ValueKey('vip-mark-explain'),
              onTap: onTap,
              size: const Size.square(target),
              markRect: Rect.fromCenter(
                center: Offset(
                  markCenter.dx - left,
                  markCenter.dy + padTop - top,
                ),
                width: diameter,
                height: diameter,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final measured = DefaultTextStyle.of(context).style.merge(style);
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        var shown = name;
        final lines = maxLines;
        if (lines != null && constraints.maxWidth.isFinite) {
          // 0 = does not fit, 1 = fits, 2 = fits but the mark starts a line
          // on its own (orphaned from the name).
          int check(String text) {
            final painter = TextPainter(
              text: TextSpan(style: measured, children: [_span(text)]),
              textDirection: direction,
              textAlign: textAlign,
              textScaler: scaler,
              maxLines: lines,
            );
            painter.setPlaceholderDimensions(<PlaceholderDimensions>[
              PlaceholderDimensions(
                size: markSize,
                alignment: PlaceholderAlignment.middle,
              ),
            ]);
            painter.layout(maxWidth: constraints.maxWidth);
            var result = painter.didExceedMaxLines ? 0 : 1;
            final boxes = painter.inlinePlaceholderBoxes ?? const <TextBox>[];
            if (result == 1 && boxes.isNotEmpty) {
              // Orphaned = the mark is the only thing on a line after the
              // first. Line metrics make this hold in both directions (an
              // RTL line starts at the right edge).
              final box = boxes.first.toRect();
              final metrics = painter.computeLineMetrics();
              for (var i = 1; i < metrics.length; i++) {
                final line = metrics[i];
                final top = line.baseline - line.ascent;
                final bottom = line.baseline + line.descent;
                if (box.center.dy >= top &&
                    box.center.dy <= bottom &&
                    line.width <= box.width + 1) {
                  result = 2;
                }
              }
            }
            painter.dispose();
            return result;
          }

          String trimmed(int length) =>
              '${name.characters.take(length).toString().trimRight()}…';

          final length = name.characters.length;
          if (check(name) == 0) {
            var lo = 0;
            var hi = length;
            while (lo < hi) {
              final mid = (lo + hi + 1) ~/ 2;
              if (check(trimmed(mid)) != 0) {
                lo = mid;
              } else {
                hi = mid - 1;
              }
            }
            // Never leave the mark alone at the start of a line.
            while (lo > 1 && check(trimmed(lo)) == 2) {
              lo--;
            }
            shown = trimmed(lo);
          } else if (check(name) == 2 && name.trim().contains(' ')) {
            // The mark would wrap alone: take the last word down with it.
            final at = name.trimRight().lastIndexOf(' ');
            final candidate =
                '${name.substring(0, at)}\n${name.substring(at + 1)}';
            if (check(candidate) == 1) shown = candidate;
          }
        }
        Widget text = Text.rich(
          _span(shown),
          maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.clip,
          textAlign: textAlign,
          style: style,
        );
        // Assistive tech always hears the full, untrimmed name (never the
        // display cut with its "…" and word joiner) and, for a VIP, "VIP":
        // the painted paragraph, inline mark included, is excluded.
        final base = semanticsLabel ?? name;
        text = Semantics(
          label: announceVip ? '$base, ${VipBadge.label}' : base,
          child: ExcludeSemantics(child: text),
        );
        final onTap = onExplain;
        if (onTap == null || !constraints.maxWidth.isFinite) {
          return Padding(padding: room, child: text);
        }
        return _withExplainTarget(
          text: text,
          shown: shown,
          width: constraints.maxWidth,
          measured: measured,
          scaler: scaler,
          direction: direction,
          onTap: onTap,
        );
      },
    );
  }
}

/// The header rosette's 44×44 target: a "VIP" button (with a hint saying what
/// it does) that shows a 2 px focus ring around the painted mark for keyboard
/// users and a circular ink response for touch and pointer.
class _VipMarkButton extends StatefulWidget {
  const _VipMarkButton({
    required this.onTap,
    required this.size,
    required this.markRect,
    this.child,
    super.key,
  });

  final VoidCallback onTap;
  final Size size;

  /// Where the painted rosette is, in this box's coordinates.
  final Rect markRect;

  /// The painted mark when the button hosts it (single-line names); null
  /// when the button is laid over an inline mark (multi-line names).
  final Widget? child;

  @override
  State<_VipMarkButton> createState() => _VipMarkButtonState();
}

class _VipMarkButtonState extends State<_VipMarkButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final ring = widget.markRect.inflate(3);
    return Semantics(
      container: true,
      button: true,
      label: VipBadge.label,
      hint: copy.text('Shows what VIP means', 'Pokazuje, co oznacza VIP'),
      child: SizedBox.fromSize(
        size: widget.size,
        child: Material(
          type: MaterialType.transparency,
          child: InkResponse(
            onTap: widget.onTap,
            onFocusChange: (focused) => setState(() => _focused = focused),
            radius: NameWithVipMark.explainTargetSize / 2,
            highlightShape: BoxShape.circle,
            focusColor: Colors.transparent,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ?widget.child,
                if (_focused)
                  Positioned.fromRect(
                    rect: ring,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        key: const ValueKey('vip-mark-focus-ring'),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.focus, width: 2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
