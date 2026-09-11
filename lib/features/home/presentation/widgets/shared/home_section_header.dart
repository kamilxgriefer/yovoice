import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_spacing.dart';

/// Compact is the phone ramp (17 px title); expanded is the desktop one
/// (19 px). Only the type ramp changes — the rhythm is identical.
enum HomeSectionHeaderScale { compact, expanded }

/// THE section heading for Home, on every platform.
///
/// Why this exists as its own component: a heading's LAYOUT box used to
/// differ from its INK box by however much air its 44 px "View all" target
/// happened to add — 76 px tall with the button, 53 px without, from the
/// same widget. That is why Home's gaps alternated (40 / 37.5 / 20 / 30.9)
/// while the source read as one constant.
///
/// The contract here is exact, and it holds at any text scale, in any
/// locale, with or without the trailing button, and whether or not the
/// title wraps:
///
///   * the heading's ink top sits [AppRhythm.section] (24) below the
///     previous content's ink,
///   * the heading's ink bottom sits [AppRhythm.title] (16) above the next
///     content's ink.
///
/// The mechanism is [_SectionHeaderLayout]: the box is laid out as
/// `24 + titleHeight + 16`, the title is placed at exactly y = 24, and the
/// trailing action — taller than the title because it owns a 44 px target
/// — is centred on the title and therefore reaches INTO the declared gaps
/// rather than growing the box. Its own vertical air is subtracted, not
/// added, so the number the eye sees is the number the source declares.
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({
    required this.title,
    this.live = false,
    this.onSeeAll,
    this.seeAllKey,
    this.scale = HomeSectionHeaderScale.compact,
    super.key,
  });

  final String title;

  /// A 6 px live dot after the title. Presentation only — it never claims
  /// anything the caller has not already verified.
  final bool live;

  /// The way through to the full list. Null hides the button entirely, and
  /// the heading's box height does not change when it does.
  final VoidCallback? onSeeAll;

  /// Rides the "View all" button so an existing finder keeps resolving
  /// (`home-people-see-all`).
  final Key? seeAllKey;

  final HomeSectionHeaderScale scale;

  static const double _titleLineHeight = 1.3;
  static const double _labelLineHeight = 1.2;
  static const double _liveDot = 6;

  bool get _compact => scale == HomeSectionHeaderScale.compact;

  double get _titleSize => _compact ? 17 : 19;
  double get _labelSize => _compact ? 12.5 : 13;
  double get _chevronSize => _compact ? 18 : 19;

  /// The single-line ink height of the title at the caller's text scale.
  /// Exposed for the rhythm test, which pins the geometry rather than a
  /// screenshot.
  @visibleForTesting
  static double titleInkHeight(
    BuildContext context, {
    HomeSectionHeaderScale scale = HomeSectionHeaderScale.compact,
  }) =>
      MediaQuery.textScalerOf(
        context,
      ).scale(scale == HomeSectionHeaderScale.compact ? 17 : 19) *
      _titleLineHeight;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    // At enlarged text the button often no longer fits beside the title,
    // and it moves under it — the arrangement this heading already shipped.
    // "Often", not "always": whether it FITS is a question about the width
    // this heading was given, which only layout knows. A 1440 px desktop at
    // 200 % text has 1400 px for a 380 px title and a 200 px button, and
    // stacking there spent a whole line to push the action as far from its
    // own heading as the page allows. So this is permission to stack, and
    // `_RenderSectionHeader` stacks only when the two really cannot share
    // the line. The rhythm is 24 / 16 in either arrangement.
    final mayStack = scaler.scale(1) >= 1.6;

    final titleRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            title,
            // A heading wraps; it never ellipsises. Three lines is more
            // than any Home heading needs at 200 % text on a 320 px phone.
            maxLines: 3,
            overflow: TextOverflow.visible,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: _titleSize,
              // Explicit, so the ink box is arithmetic rather than a font
              // metric the rhythm cannot see.
              height: _titleLineHeight,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (live) ...[
          const SizedBox(width: 6),
          Container(
            width: _liveDot,
            height: _liveDot,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.live,
            ),
          ),
        ],
      ],
    );

    final onSeeAll = this.onSeeAll;
    if (onSeeAll == null) {
      return _SectionHeaderLayout(
        topGap: AppRhythm.section,
        bottomGap: AppRhythm.title,
        actionGap: AppRhythm.tight,
        actionInkInset: 0,
        mayStack: false,
        children: [titleRow],
      );
    }

    // The button's own ink is its label and chevron; the rest of its 44 px
    // box is the touch target. Both are known here, so the air can be
    // subtracted instead of guessed.
    final labelInk = scaler.scale(_labelSize) * _labelLineHeight;
    final actionInk = math.max(labelInk, _chevronSize);
    final actionBox = math.max(AppSizing.minimumTouchTarget, actionInk);

    final viewAll = TextButton(
      key: seeAllKey,
      onPressed: onSeeAll,
      style: TextButton.styleFrom(
        // Material inflates a button's LAYOUT box to 48 px for its tap
        // target. Shrink-wrapping keeps the box at the 44 px this row
        // reserves, so the declared rhythm is the rendered rhythm; the
        // 44 x 44 target is preserved by `minimumSize`.
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(
          AppSizing.minimumTouchTarget,
          AppSizing.minimumTouchTarget,
        ),
        // Pinned: the ambient platform density would otherwise shave 8 px
        // off the target on a desktop build.
        visualDensity: VisualDensity.standard,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        foregroundColor: palette.interactiveForeground,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Flexible: at 200 % text a long localized label ("Zobacz
          // wszystkie") is wider than a 320 px phone, and the button must
          // shrink rather than overflow the heading. The heading itself
          // still wraps and never ellipsises.
          Flexible(
            child: Text(
              copy.text('View all', 'Zobacz wszystkie'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _labelSize,
                height: _labelLineHeight,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 2),
          Icon(Icons.chevron_right_rounded, size: _chevronSize),
        ],
      ),
    );

    return _SectionHeaderLayout(
      topGap: AppRhythm.section,
      bottomGap: AppRhythm.title,
      actionGap: AppRhythm.tight,
      actionInkInset: (actionBox - actionInk) / 2,
      mayStack: mayStack,
      children: [titleRow, viewAll],
    );
  }
}

/// Lays the heading out so its layout box is exactly
/// `topGap + titleInk + bottomGap`, with the trailing action centred on the
/// title's ink rather than allowed to grow the box.
class _SectionHeaderLayout extends MultiChildRenderObjectWidget {
  const _SectionHeaderLayout({
    required this.topGap,
    required this.bottomGap,
    required this.actionGap,
    required this.actionInkInset,
    required this.mayStack,
    required super.children,
  });

  final double topGap;
  final double bottomGap;
  final double actionGap;

  /// How far the action's ink sits inside its own box. Only used when the
  /// action is stacked UNDER the title and therefore owns the heading's ink
  /// bottom.
  final double actionInkInset;

  /// Whether the trailing action is ALLOWED under the title. Whether it
  /// actually goes there is decided during layout, from the width.
  final bool mayStack;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSectionHeader(
    topGap: topGap,
    bottomGap: bottomGap,
    actionGap: actionGap,
    actionInkInset: actionInkInset,
    mayStack: mayStack,
    textDirection: Directionality.of(context),
  );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSectionHeader renderObject,
  ) {
    renderObject
      ..topGap = topGap
      ..bottomGap = bottomGap
      ..actionGap = actionGap
      ..actionInkInset = actionInkInset
      ..mayStack = mayStack
      ..textDirection = Directionality.of(context);
  }
}

class _HeaderParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSectionHeader extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HeaderParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HeaderParentData> {
  _RenderSectionHeader({
    required double topGap,
    required double bottomGap,
    required double actionGap,
    required double actionInkInset,
    required bool mayStack,
    required TextDirection textDirection,
  }) : _topGap = topGap,
       _bottomGap = bottomGap,
       _actionGap = actionGap,
       _actionInkInset = actionInkInset,
       _mayStack = mayStack,
       _textDirection = textDirection;

  double _topGap;
  double get topGap => _topGap;
  set topGap(double value) {
    if (_topGap == value) return;
    _topGap = value;
    markNeedsLayout();
  }

  double _bottomGap;
  double get bottomGap => _bottomGap;
  set bottomGap(double value) {
    if (_bottomGap == value) return;
    _bottomGap = value;
    markNeedsLayout();
  }

  double _actionGap;
  double get actionGap => _actionGap;
  set actionGap(double value) {
    if (_actionGap == value) return;
    _actionGap = value;
    markNeedsLayout();
  }

  double _actionInkInset;
  double get actionInkInset => _actionInkInset;
  set actionInkInset(double value) {
    if (_actionInkInset == value) return;
    _actionInkInset = value;
    markNeedsLayout();
  }

  bool _mayStack;
  bool get mayStack => _mayStack;
  set mayStack(bool value) {
    if (_mayStack == value) return;
    _mayStack = value;
    markNeedsLayout();
  }

  /// Whether the action actually moves under the title.
  ///
  /// The test is what the ACTION costs the row, not what the title happens
  /// to say: every heading on a page carries the same "View all", so this
  /// answers the same way for all of them and a page never mixes the two
  /// arrangements. A trailing control that wants more than a third of the
  /// row has stopped being trailing — that is the phone at 200 % text, and
  /// it stacks exactly as it does today. A 768 px slate or a 1440 px
  /// desktop at the same text scale has room to spare, and there the action
  /// stays on its heading's line instead of being pushed a full row width
  /// away from the words it belongs to.
  static const double _actionShareOfRow = 1 / 3;

  bool _stacksAt(double maxWidth, double actionWidth) {
    if (!mayStack || !maxWidth.isFinite) return false;
    return actionWidth + actionGap > maxWidth * _actionShareOfRow;
  }

  TextDirection _textDirection;
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(covariant RenderObject child) {
    if (child.parentData is! _HeaderParentData) {
      child.parentData = _HeaderParentData();
    }
  }

  RenderBox get _title => firstChild!;
  RenderBox? get _action => childAfter(firstChild!);

  ({Size box, Size title, Size action, bool stacked}) _measure(
    BoxConstraints constraints,
    ChildLayouter layoutChild,
  ) {
    final action = _action;
    final maxWidth = constraints.maxWidth;
    final childMaxWidth = maxWidth.isFinite ? maxWidth : double.infinity;
    var actionSize = Size.zero;
    if (action != null) {
      actionSize = layoutChild(action, BoxConstraints(maxWidth: childMaxWidth));
    }
    final stacked = action != null && _stacksAt(maxWidth, actionSize.width);
    final reserve = (action == null || stacked)
        ? 0.0
        : actionSize.width + actionGap;
    final titleSize = layoutChild(
      _title,
      BoxConstraints(
        maxWidth: childMaxWidth.isFinite
            ? math.max(0, childMaxWidth - reserve)
            : double.infinity,
      ),
    );
    final width = maxWidth.isFinite
        ? maxWidth
        : math.max(titleSize.width + reserve, actionSize.width);
    final double height;
    if (action != null && stacked) {
      // Stacked, the action owns the heading's ink bottom, so its own
      // vertical air is subtracted from the declared gap instead of added
      // to it.
      height =
          topGap +
          titleSize.height +
          actionSize.height +
          math.max(0.0, bottomGap - actionInkInset);
    } else {
      height = topGap + titleSize.height + bottomGap;
    }
    return (
      box: constraints.constrain(Size(width, height)),
      title: titleSize,
      action: actionSize,
      stacked: stacked,
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _measure(constraints, ChildLayoutHelper.dryLayoutChild).box;

  @override
  void performLayout() {
    final measured = _measure(constraints, ChildLayoutHelper.layoutChild);
    size = measured.box;
    final leftToRight = textDirection == TextDirection.ltr;

    (_title.parentData! as _HeaderParentData).offset = Offset(
      leftToRight ? 0 : size.width - measured.title.width,
      topGap,
    );

    final action = _action;
    if (action == null) return;
    final actionData = action.parentData! as _HeaderParentData;
    final double actionTop;
    if (measured.stacked) {
      actionTop = topGap + measured.title.height;
    } else {
      // Centred on the TITLE's ink, not on the box: that is what makes the
      // heading read as one line whatever the button's target height is.
      actionTop =
          (topGap + (measured.title.height - measured.action.height) / 2).clamp(
            0.0,
            math.max(0.0, size.height - measured.action.height),
          );
    }
    actionData.offset = Offset(
      leftToRight ? size.width - measured.action.width : 0,
      actionTop,
    );
  }

  // Intrinsics have no width to test the arrangement against, so they
  // report the widest case: side by side, which is what an unbounded row
  // would draw.
  @override
  double computeMinIntrinsicWidth(double height) {
    final action = _action;
    final title = _title.getMinIntrinsicWidth(double.infinity);
    if (action == null) return title;
    return title + actionGap + action.getMinIntrinsicWidth(double.infinity);
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    final action = _action;
    final title = _title.getMaxIntrinsicWidth(double.infinity);
    if (action == null) return title;
    return title + actionGap + action.getMaxIntrinsicWidth(double.infinity);
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    final action = _action;
    if (action == null) {
      return topGap + _title.getMaxIntrinsicHeight(width) + bottomGap;
    }
    final actionWidth = action.getMaxIntrinsicWidth(double.infinity);
    if (!_stacksAt(width, actionWidth)) {
      final beside = math.max(0.0, width - actionWidth - actionGap);
      return topGap + _title.getMaxIntrinsicHeight(beside) + bottomGap;
    }
    return topGap +
        _title.getMaxIntrinsicHeight(width) +
        action.getMaxIntrinsicHeight(width) +
        math.max(0.0, bottomGap - actionInkInset);
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
