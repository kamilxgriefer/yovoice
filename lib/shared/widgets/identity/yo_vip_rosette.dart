import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/identity/vip_badge.dart';

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
    super.key,
  });

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
    final vip = widget.isVip ?? _vip;
    final style = widget.style;
    final maxLines = widget.maxLines;
    if (!vip) {
      return Text(
        widget.name,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        semanticsLabel: widget.semanticsLabel,
        style: style,
      );
    }
    // The mark scales with the reader's text size, like the name beside it.
    final fontSize = MediaQuery.textScalerOf(
      context,
    ).scale(style.fontSize ?? 14);
    final diameter = YoVipRosette.diameterFor(fontSize);
    final gap = YoVipRosette.gapFor(fontSize);
    final mark = Padding(
      padding: EdgeInsetsDirectional.only(start: gap),
      child: YoVipRosette(
        diameter: diameter,
        excludeSemantics: !widget.markSemantics,
      ),
    );
    if (maxLines == 1) {
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
          mark,
        ],
      );
    }
    return _MultiLineVipName(
      name: widget.name,
      semanticsLabel: widget.semanticsLabel,
      style: style,
      maxLines: maxLines,
      mark: mark,
      markSize: Size(gap + diameter, diameter),
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
    this.semanticsLabel,
  });

  final String name;
  final String? semanticsLabel;
  final TextStyle style;
  final int? maxLines;
  final Widget mark;
  final Size markSize;

  InlineSpan _span(String text) => TextSpan(
    children: [
      // U+2060 WORD JOINER keeps the mark on the last word's line.
      TextSpan(text: '$text⁠'),
      WidgetSpan(alignment: PlaceholderAlignment.middle, child: mark),
    ],
  );

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
            if (result == 1 &&
                boxes.isNotEmpty &&
                boxes.first.left < 1 &&
                boxes.first.top > 1) {
              result = 2;
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
        final text = Text.rich(
          _span(shown),
          maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.clip,
          style: style,
        );
        final label = semanticsLabel;
        if (label == null) return text;
        // The label replaces the text; the mark keeps its own "VIP" node.
        return Semantics(
          label: label,
          child: ExcludeSemantics(child: text),
        );
      },
    );
  }
}
