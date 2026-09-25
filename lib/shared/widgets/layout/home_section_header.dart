import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';

/// Compact is the phone ramp (17 px title); expanded is the desktop one
/// (19 px). Only the type ramp changes — the rhythm is identical.
enum HomeSectionHeaderScale { compact, expanded }

/// THE section heading — born on Home, now the one heading for every
/// scrolling page (Slim redesign, phase 0: one state = one primitive). The
/// class keeps its Home-era name because `test/home_rhythm_test.dart` pins
/// the contract by type.
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
///
/// Three optional slots let other screens mount the same heading without a
/// private copy, and none of them changes the box arithmetic: [leading]
/// (a small glyph before the title), [subtitle] (one secondary line under
/// it, part of the title ink) and [trailing] (a non-action trailer — a count
/// pill, an icon box — laid out exactly where the "View all" would be, so it
/// too is centred on the title and never grows the box).
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.live = false,
    this.onSeeAll,
    this.seeAllKey,
    this.seeAllLabel,
    this.seeAllVocabulary,
    this.scale = HomeSectionHeaderScale.compact,
    super.key,
  }) : assert(
         onSeeAll == null || trailing == null,
         'A heading carries either a "View all" action or a trailing '
         'widget; both would compete for the same slot.',
       );

  final String title;

  /// One secondary line under the title (`textSecondary`, w500). It belongs
  /// to the title's ink, so the box is still `section + ink + title`.
  final String? subtitle;

  /// A small glyph before the title — an `Icon` of 16–18 px. Centred on the
  /// title's line; it brings no padding of its own.
  final Widget? leading;

  /// A trailer that is NOT the "View all" action: a count pill, a category
  /// icon box. It takes the action's slot — centred on the title's ink,
  /// never stacking under it — and is therefore mutually exclusive with
  /// [onSeeAll].
  final Widget? trailing;

  /// A 6 px live dot after the title. Presentation only — it never claims
  /// anything the caller has not already verified.
  final bool live;

  /// The way through to the full list. Null hides the button entirely, and
  /// the heading's box height does not change when it does.
  final VoidCallback? onSeeAll;

  /// Rides the "View all" button so an existing finder keeps resolving
  /// (`home-people-see-all`).
  final Key? seeAllKey;

  /// The action's own words. Polish declines the object of "see all"
  /// ("wszystkich" for people, "wszystkie" for places), so a single
  /// hardcoded label is wrong on at least one Home section. Null keeps the
  /// neutral default every other caller already uses.
  final String? seeAllLabel;

  /// The widest "View all" labels the PAGE can carry — the set the stacking
  /// verdict is answered against, so every heading on one page arranges
  /// itself identically (see [_arrangementActionWidth]). Null keeps Home's
  /// own vocabulary (`homeSeeAll`, `homeSeeAllPeople`, the neutral label);
  /// a non-Home page passes its own. The label this heading renders is
  /// always part of the set.
  final Iterable<String>? seeAllVocabulary;

  final HomeSectionHeaderScale scale;

  static const double _titleLineHeight = 1.3;
  static const double _labelLineHeight = 1.2;
  static const double _liveDot = 6;

  /// The trailing action's own chrome, shared by the button below and by the
  /// arrangement measurement so the two can never drift: the gap between the
  /// label and the chevron, and the button's horizontal padding per side.
  static const double _actionLabelGap = 2;
  static const double _actionPadding = 8;

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

  /// The width the arrangement test is answered against: the widest "View
  /// all" the page can carry, NOT the one this heading happens to carry.
  ///
  /// Home's action vocabulary is not one string. Polish declines the object
  /// of "see all" — "Zobacz wszystkich" for people, "Zobacz wszystkie" for
  /// places and servers — and the two land on opposite sides of the
  /// third-of-the-row threshold over a band of widths (the reported case: a
  /// 1032 pt window at 200 % text, where "Twoi znajomi" pushed its action
  /// onto a second row while "W Twoich serwerach" and "Ostatnie czaty" kept
  /// theirs on the heading line). Measuring the vocabulary rather than the
  /// instance makes every heading on the page answer the test identically,
  /// which is the invariant `docs/UI.md` states.
  double _arrangementActionWidth(
    BuildContext context,
    TextScaler scaler,
    Iterable<String> vocabulary,
  ) {
    final theme = Theme.of(context);
    // How the button's own label resolves: `TextButton` has no textStyle in
    // this app's theme, so its `DefaultTextStyle` is `labelLarge`, and the
    // `Text` below merges its size/weight/height onto it. Measuring with the
    // same base keeps the family and letter spacing honest.
    final base =
        theme.textButtonTheme.style?.textStyle?.resolve(const <WidgetState>{}) ??
        theme.textTheme.labelLarge ??
        const TextStyle();
    final style = base.copyWith(
      fontSize: _labelSize,
      height: _labelLineHeight,
      fontWeight: FontWeight.w700,
    );
    final textDirection = Directionality.of(context);
    var widestLabel = 0.0;
    for (final label in vocabulary) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: textDirection,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      widestLabel = math.max(widestLabel, painter.width);
      painter.dispose();
    }
    // The chevron does not follow the text scaler (no `applyTextScaling` in
    // this theme), which is why `actionInk` below compares against it raw.
    return math.max(
      AppSizing.minimumTouchTarget,
      widestLabel + _actionLabelGap + _chevronSize + 2 * _actionPadding,
    );
  }

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

    final leading = this.leading;
    final titleRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[
          // Boxed to one title line so the glyph is centred on the words
          // and adds no ink above or below them; the Row centres that box
          // on the title exactly as it centres the live dot.
          SizedBox(
            height: scaler.scale(_titleSize) * _titleLineHeight,
            child: Center(child: leading),
          ),
          const SizedBox(width: AppRhythm.tight),
        ],
        Flexible(
          // A section title must be a HEADING to assistive technology, not
          // just large text: without this, VoiceOver's Headings rotor and
          // TalkBack's heading navigation are empty on a long scrolling
          // page, so the only way through Home is to swipe every element in
          // turn. WCAG 1.3.1, Level A. discover_clubs_rail.dart:88 already
          // does this; Home's shared header did not.
          child: Semantics(
            header: true,
            child: Text(
              title,
              // A heading wraps; it never ellipsises. Three lines is more
              // than any Home heading needs at 200 % text on a 320 px phone.
              maxLines: 3,
              overflow: TextOverflow.visible,
              // The refine-look section role (17 / 19, w700, -0.25): calm
              // type, one weight cap. Its size is `_titleSize`, so the rhythm
              // arithmetic below still reads the number that renders.
              style:
                  (_compact
                          ? AppTypography.sectionTitle
                          : AppTypography.sectionTitleExpanded)
                      .copyWith(
                        color: palette.textPrimary,
                        fontSize: _titleSize,
                        // Explicit, so the ink box is arithmetic rather than
                        // a font metric the rhythm cannot see.
                        height: _titleLineHeight,
                      ),
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

    final subtitle = this.subtitle;
    // The subtitle is part of the heading's ink: the render object sees one
    // "title" child whose height is title + hairline + subtitle, so the
    // 24 / ink / 16 arithmetic is untouched and a trailer is centred on the
    // whole lockup.
    final Widget titleBlock = subtitle == null
        ? titleRow
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleRow,
              const SizedBox(height: AppRhythm.hairline),
              Text(
                subtitle,
                maxLines: 3,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: _labelSize,
                  height: _titleLineHeight,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          );

    final onSeeAll = this.onSeeAll;
    if (onSeeAll == null) {
      final trailing = this.trailing;
      return _SectionHeaderLayout(
        topGap: AppRhythm.section,
        bottomGap: AppRhythm.title,
        actionGap: AppRhythm.tight,
        actionInkInset: 0,
        // A trailer never stacks: it is a mark beside the words, not a way
        // through, so at enlarged text the title wraps beside it instead.
        mayStack: false,
        arrangementActionWidth: 0,
        children: [titleBlock, ?trailing],
      );
    }

    // The button's own ink is its label and chevron; the rest of its 44 px
    // box is the touch target. Both are known here, so the air can be
    // subtracted instead of guessed.
    final labelInk = scaler.scale(_labelSize) * _labelLineHeight;
    final actionInk = math.max(labelInk, _chevronSize);
    final actionBox = math.max(AppSizing.minimumTouchTarget, actionInk);

    // The neutral label every caller that passes none renders. It is part of
    // the page's vocabulary even when this heading overrides it.
    final neutralSeeAll = copy.text('View all', 'Zobacz wszystkie');

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
        padding: const EdgeInsets.symmetric(horizontal: _actionPadding),
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
              seeAllLabel ?? neutralSeeAll,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _labelSize,
                height: _labelLineHeight,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: _actionLabelGap),
          Icon(Icons.chevron_right_rounded, size: _chevronSize),
        ],
      ),
    );

    // Deliberately the whole vocabulary and not `seeAllLabel`: a heading
    // may not decide the page's arrangement from its own wording. Home's
    // set is the default; another page passes its own, and the label this
    // heading renders is always in it.
    final pageVocabulary = seeAllVocabulary;
    final vocabulary = pageVocabulary == null
        ? <String>{copy.homeSeeAll, copy.homeSeeAllPeople, neutralSeeAll}
        : <String>{...pageVocabulary, seeAllLabel ?? neutralSeeAll};

    return _SectionHeaderLayout(
      topGap: AppRhythm.section,
      bottomGap: AppRhythm.title,
      actionGap: AppRhythm.tight,
      actionInkInset: (actionBox - actionInk) / 2,
      mayStack: mayStack,
      arrangementActionWidth: _arrangementActionWidth(
        context,
        scaler,
        vocabulary,
      ),
      children: [titleBlock, viewAll],
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
    required this.arrangementActionWidth,
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

  /// The width the arrangement test is answered against — a page constant,
  /// not this action's rendered width. Placement still uses the real one.
  final double arrangementActionWidth;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSectionHeader(
    topGap: topGap,
    bottomGap: bottomGap,
    actionGap: actionGap,
    actionInkInset: actionInkInset,
    mayStack: mayStack,
    arrangementActionWidth: arrangementActionWidth,
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
      ..arrangementActionWidth = arrangementActionWidth
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
    required double arrangementActionWidth,
    required TextDirection textDirection,
  }) : _topGap = topGap,
       _bottomGap = bottomGap,
       _actionGap = actionGap,
       _actionInkInset = actionInkInset,
       _mayStack = mayStack,
       _arrangementActionWidth = arrangementActionWidth,
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

  double _arrangementActionWidth;
  double get arrangementActionWidth => _arrangementActionWidth;
  set arrangementActionWidth(double value) {
    if (_arrangementActionWidth == value) return;
    _arrangementActionWidth = value;
    markNeedsLayout();
  }

  /// Whether the action actually moves under the title.
  ///
  /// The test is what the ACTION costs the row, not what the title happens
  /// to say. A trailing control that wants more than a third of the row has
  /// stopped being trailing — that is the phone at 200 % text, and it stacks
  /// exactly as it does today. A 768 px slate or a 1440 px desktop at the
  /// same text scale has room to spare, and there the action stays on its
  /// heading's line instead of being pushed a full row width away from the
  /// words it belongs to.
  ///
  /// The width fed in is [arrangementActionWidth]: the widest "View all" the
  /// PAGE can carry, never the one this heading renders. Headings on one page
  /// do not all carry the same string — Polish declines the object, "Zobacz
  /// wszystkich" for people against "Zobacz wszystkie" for places — and
  /// answering from the rendered label let one heading stack while its
  /// neighbours did not. Asking the same question of the same number is what
  /// keeps a page from mixing the two arrangements.
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
    // Verdict from the page constant; `reserve` and placement below still
    // use the action's REAL size, so the 24 / titleInk / 16 rhythm is
    // untouched.
    final stacked = action != null && _stacksAt(maxWidth, arrangementActionWidth);
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
    if (!_stacksAt(width, arrangementActionWidth)) {
      final actionWidth = action.getMaxIntrinsicWidth(double.infinity);
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
