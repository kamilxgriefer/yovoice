import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_feed_chrome.dart'
    show ImmersiveChromeOption;

/// Level 2 of the Głos chrome below 1100 (G4): three trackless text tabs —
/// "Odkrywaj", "Obserwowani", "Popularne" — drawn into
/// `ImmersiveFeedChrome.filterBar`.
///
/// Quieter than level 1 by construction: 15 px against the switch's 17, a
/// 2 px `textPrimary` underline the width of the label against the switch's
/// 3 px gradient line, and no glow anywhere. The active tab is `textPrimary`
/// w700, a resting one `textTertiary` w600, so selection is carried by ink,
/// weight, the line AND the `selected` flag, never by colour alone.
///
/// Every tab is a full 48 px target with 12 px of air on either side (so the
/// labels sit 24 apart and the first one lines up with "Głos" above it),
/// focusable, and a button with the `selected` state in one node. Tapping
/// the ACTIVE tab again is a real action — the host scrolls the feed to the
/// top and refreshes it — so the active tab says so in its hint.
///
/// The row scrolls horizontally rather than wrapping (at 200 % text the
/// three labels are wider than a 320 px phone) and always keeps the active
/// tab in view. Whenever a label continues past an edge, that edge fades
/// out over [edgeFade] — the cue that there is more to reach.
class VoiceFeedFilterTabs extends StatefulWidget {
  const VoiceFeedFilterTabs({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    required this.groupLabel,
    this.selectedFocusNode,
    this.selectedHint,
    this.padding = EdgeInsets.zero,
    super.key,
  }) : assert(tabs.length > 0, 'A tab row needs a tab.');

  final List<ImmersiveChromeOption> tabs;
  final int selectedIndex;

  /// Called for every tap, including one on the tab that is already active
  /// (the host's "scroll to top and refresh").
  final ValueChanged<int> onSelected;

  /// Names the row to assistive technology (the filter group).
  final String groupLabel;

  /// Given to the ACTIVE tab: the feed's focus-recovery target after an
  /// expiry removal, which used to be the refresh button this row replaced.
  final FocusNode? selectedFocusNode;

  /// What activating the active tab again does, for a screen reader.
  final String? selectedHint;

  /// Scroll padding around the row.
  final EdgeInsetsGeometry padding;

  /// The minimum height of every tab: the full interaction target.
  static const double targetHeight = 48;

  /// Air on either side of a label inside its target; two of them are the
  /// 24 px the board puts between labels.
  static const double tabPadding = AppRhythm.item;

  static const double labelSize = 15;
  static const double underlineHeight = 2;
  static const double underlineGap = 6;

  /// How far an edge fades when labels continue past it.
  static const double edgeFade = 32;

  /// The fade, so a test can read which edges it covers.
  @visibleForTesting
  static const Key fadeKey = ValueKey<String>('voice-filter-tabs-fade');

  /// Which edges of the row under [element] fade right now.
  @visibleForTesting
  static ({bool start, bool end}) fadesOf(Element element) {
    final state = (element as StatefulElement).state;
    state as _VoiceFeedFilterTabsState;
    return (start: state._moreBefore, end: state._moreAfter);
  }

  @override
  State<VoiceFeedFilterTabs> createState() => _VoiceFeedFilterTabsState();
}

class _VoiceFeedFilterTabsState extends State<VoiceFeedFilterTabs> {
  final ScrollController _scroll = ScrollController();
  bool _moreBefore = false;
  bool _moreAfter = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_measure);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (!position.hasContentDimensions || !position.hasPixels) return;
    final before = position.extentBefore > .5;
    final after = position.extentAfter > .5;
    if (before != _moreBefore || after != _moreAfter) {
      setState(() {
        _moreBefore = before;
        _moreAfter = after;
      });
    }
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_measure)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.tabs.length;
    final selected = widget.selectedIndex.clamp(0, count - 1);
    Widget row = SingleChildScrollView(
      key: const ValueKey<String>('voice-filter-tabs-scroll'),
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      padding: widget.padding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var index = 0; index < count; index++)
            VoiceFeedFilterTab(
              key: widget.tabs[index].key,
              label: widget.tabs[index].label,
              semanticLabel: widget.tabs[index].semanticLabel,
              selected: index == selected,
              hint: index == selected ? widget.selectedHint : null,
              focusNode: index == selected ? widget.selectedFocusNode : null,
              onTap: () => widget.onSelected(index),
            ),
        ],
      ),
    );
    // A label that continues past an edge fades out there. The scroll
    // extent can change without a scroll (text size, width, a new label),
    // so the edges are re-read after every layout too.
    row = NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
        return false;
      },
      child: row,
    );
    final direction = Directionality.of(context);
    final fadeStart = _moreBefore;
    final fadeEnd = _moreAfter;
    row = ShaderMask(
      key: VoiceFeedFilterTabs.fadeKey,
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final width = bounds.width <= 0 ? 1.0 : bounds.width;
        final fraction = (VoiceFeedFilterTabs.edgeFade / width).clamp(0.0, .5);
        return LinearGradient(
          begin: AlignmentDirectional.centerStart.resolve(direction),
          end: AlignmentDirectional.centerEnd.resolve(direction),
          // A mask: only the alpha is read (dstIn).
          colors: <Color>[
            fadeStart ? Colors.transparent : Colors.black,
            Colors.black,
            Colors.black,
            fadeEnd ? Colors.transparent : Colors.black,
          ],
          stops: <double>[0, fraction, 1 - fraction, 1],
        ).createShader(bounds);
      },
      child: row,
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.groupLabel,
      child: row,
    );
  }

}

/// One text tab of [VoiceFeedFilterTabs].
class VoiceFeedFilterTab extends StatefulWidget {
  const VoiceFeedFilterTab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.semanticLabel,
    this.hint,
    this.focusNode,
    super.key,
  });

  final String label;
  final String? semanticLabel;
  final bool selected;
  final String? hint;
  final FocusNode? focusNode;
  final VoidCallback onTap;

  /// Every tab's underline box (transparent unless active), so a test can
  /// read its width and colour under the tab's own key.
  static const Key underlineKey = ValueKey<String>('voice-filter-underline');

  @override
  State<VoiceFeedFilterTab> createState() => _VoiceFeedFilterTabState();
}

class _VoiceFeedFilterTabState extends State<VoiceFeedFilterTab> {
  bool _focused = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _revealIfSelected();
  }

  @override
  void didUpdateWidget(covariant VoiceFeedFilterTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) _revealIfSelected();
  }

  /// Keeps the active tab inside the row's viewport, on first layout (a
  /// feed can mount on the far tab) and whenever it becomes active. It
  /// jumps: an eased reveal would make the row ignore the next tap while it
  /// animates.
  void _revealIfSelected() {
    if (!widget.selected) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.selected) return;
      if (Scrollable.maybeOf(context) == null) return;
      Scrollable.ensureVisible(context, alignment: .5);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final selected = widget.selected;
    final ink = selected
        ? palette.textPrimary
        : _hovered
        ? palette.textSecondary
        : palette.textTertiary;
    final label = Text(
      widget.label,
      maxLines: 1,
      softWrap: false,
      style: AppTypography.titleSmall.copyWith(
        fontSize: VoiceFeedFilterTabs.labelSize,
        height: 1.2,
        color: ink,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: widget.semanticLabel ?? widget.label,
      hint: widget.hint,
      // The node replaces its subtree, so the activation, focus and enabled
      // state the discarded InkWell node would have carried are restated.
      onTap: widget.onTap,
      enabled: true,
      focusable: true,
      focused: _focused,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          focusNode: widget.focusNode,
          onTap: widget.onTap,
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          // Ink colour carries hover; no wash, no ripple on a text tab.
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          onHover: (value) {
            if (value != _hovered) setState(() => _hovered = value);
          },
          onFocusChange: (value) {
            if (value != _focused) setState(() => _focused = value);
          },
          child: DecoratedBox(
            // The focus ring is a foreground, always in the tree, so focusing
            // a tab never moves a pixel.
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(8)),
              border: Border.all(
                color: _focused ? palette.focus : Colors.transparent,
                width: 2,
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: VoiceFeedFilterTabs.targetHeight,
                minWidth: VoiceFeedFilterTabs.targetHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: VoiceFeedFilterTabs.tabPadding,
                ),
                child: Center(
                  widthFactor: 1,
                  child: IntrinsicWidth(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        // The underline's height is reserved on every tab so
                        // selecting one never shifts the labels.
                        const SizedBox(
                          height:
                              VoiceFeedFilterTabs.underlineGap +
                              VoiceFeedFilterTabs.underlineHeight,
                        ),
                        label,
                        const SizedBox(
                          height: VoiceFeedFilterTabs.underlineGap,
                        ),
                        AnimatedContainer(
                          key: VoiceFeedFilterTab.underlineKey,
                          duration: AppMotion.resolve(context, AppMotion.quick),
                          curve: AppMotion.standardCurve,
                          height: VoiceFeedFilterTabs.underlineHeight,
                          decoration: BoxDecoration(
                            color: selected
                                ? palette.textPrimary
                                : Colors.transparent,
                            borderRadius: const BorderRadius.all(
                              Radius.circular(1),
                            ),
                          ),
                        ),
                      ],
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

/// The spoken hint of the active tab: activating it again reloads the feed.
String voiceFeedTabRefreshHint(AppLocalizations copy) =>
    copy.text('Reload Moments', 'Odśwież Momenty');
