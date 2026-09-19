import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/navigation/yo_moments_icon.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_feed_chrome.dart';

/// The two content formats that live inside the single YO Moments
/// destination. Voice Moment remains the audio format name; YO Moments is the
/// section that brings audio and Reels together. Declared here, beside the
/// switch that names it, and re-exported by `moments_screen.dart` so every
/// existing importer keeps working.
enum YoMomentsFormat { voice, reels }

/// The shared YO Moments chrome on the page CANVAS: the section title, the
/// two-level format switch and pool filters, the local filter panel of the
/// wide layout and the create action.
///
/// Both formats (Voice and Reels) consume these pieces so the destination
/// has ONE header grammar. Nothing here knows about a pool, a player or a
/// service: every control is handed its state and its callback. The
/// destination draws no shell header and no bottom navigation — those are
/// the Home shell's (rail / dock) — and no search field, because no Moments
/// search backend exists.
///
/// Widths are read from the SLOT the destination receives, never from a
/// device label (docs/UI.md "Responsive layout contract").
@immutable
class YoMomentsLayout {
  const YoMomentsLayout._({
    required this.slotWidth,
    required this.tier,
    required this.gutter,
    required this.localPanelWidth,
  });

  /// Resolves the column plan for a slot [width] at [textScale].
  ///
  /// | slot S            | tier   | columns                                  |
  /// | S < 600           | narrow | one column, 16 gutter                    |
  /// | 600 ≤ S < 1100    | medium | one centred column (max 640), 24 gutter  |
  /// | 1100 ≤ S < wide-3 | wide2  | local panel 240 + main                   |
  /// | S ≥ wide-3        | wide3  | local 240 + main + calm panel 320        |
  ///
  /// The wide-3 threshold is 1200 at ordinary text and moves with the
  /// local panel: at ≥ 2× text the panel doubles exactly as the desktop
  /// rail does (264 → 528), so the third column needs 1440.
  factory YoMomentsLayout.of(double width, {double textScale = 1}) {
    final localPanelWidth = textScale >= 2
        ? localPanelBaseWidth * 2
        : localPanelBaseWidth;
    final wide3Threshold =
        wide3BaseThreshold + (localPanelWidth - localPanelBaseWidth);
    final tier = width < narrowMax
        ? YoMomentsLayoutTier.narrow
        : width < mediumMax
        ? YoMomentsLayoutTier.medium
        : width < wide3Threshold
        ? YoMomentsLayoutTier.wide2
        : YoMomentsLayoutTier.wide3;
    return YoMomentsLayout._(
      slotWidth: width,
      tier: tier,
      gutter: tier == YoMomentsLayoutTier.narrow ? narrowGutter : gutterInside,
      localPanelWidth: localPanelWidth,
    );
  }

  static const double narrowMax = 600;
  static const double mediumMax = 1100;
  static const double wide3BaseThreshold = 1200;

  /// 16 below 600; 24 everywhere else INSIDE the destination — a stated
  /// exception to the 32 desktop gutter, because 32 would cost the third
  /// column at every width the boards were drawn at.
  static const double narrowGutter = 16;
  static const double gutterInside = 24;

  /// The main column's measure — the detail screen's existing 640 column,
  /// so a card in the feed and the same Moment opened in detail keep one
  /// measure.
  static const double mainMaxWidth = 640;
  static const double mainMinWidth = 480;
  static const double localPanelBaseWidth = 240;
  static const double calmPanelWidth = 320;

  /// The widest the three columns may spread before they stop being a
  /// workspace and become two islands with a void between them. Visual
  /// contract §9.1's 1920 cell: "local + main + calm, workspace centred
  /// ≤ 1440". Beyond it the destination centres rather than stretches.
  static const double workspaceMaxWidth = 1440;

  /// How much of [slotWidth] the workspace gives back to the canvas on each
  /// side. Zero at every width the boards were drawn at except 1920.
  double get workspaceSideInset {
    final overflow = slotWidth - workspaceMaxWidth;
    return overflow > 0 ? overflow / 2 : 0;
  }

  final double slotWidth;
  final YoMomentsLayoutTier tier;
  final double gutter;
  final double localPanelWidth;

  bool get showsLocalPanel =>
      tier == YoMomentsLayoutTier.wide2 || tier == YoMomentsLayoutTier.wide3;
  bool get showsCalmPanel => tier == YoMomentsLayoutTier.wide3;
  bool get isNarrow => tier == YoMomentsLayoutTier.narrow;

  /// The width the main column may take including its two gutters.
  double get mainColumnOuterWidth => mainMaxWidth + 2 * gutter;
}

enum YoMomentsLayoutTier { narrow, medium, wide2, wide3 }

/// The slim section header: ONE 48 px row — title, level-1 format switch,
/// create — at ordinary text sizes (Slim redesign: title row ≤ 56, 44+ px
/// targets, no card under the header). Below 600 ([fullWidthSwitch]) and at
/// an accessibility text size the switch keeps its own row under the title,
/// so neither word is ever squeezed.
///
/// Trailing: the create `+` (48, primary disc) when [onCreate] is given —
/// the phone and tablet layouts, where no local panel exists — or nothing,
/// on desktop where the local panel's "Utwórz" owns creation. Leading: a
/// real Back control only when this destination was pushed as a route.
class YoMomentsHeader extends StatelessWidget {
  const YoMomentsHeader({
    required this.selectedFormat,
    required this.onFormatSelected,
    required this.gutter,
    this.showBack = false,
    this.onCreate,
    this.fullWidthSwitch = false,
    super.key,
  });

  final YoMomentsFormat selectedFormat;
  final ValueChanged<YoMomentsFormat> onFormatSelected;
  final double gutter;
  final bool showBack;
  final VoidCallback? onCreate;

  /// Below 600 the switch spans the slot minus the gutters (the board's
  /// phone). Above it keeps its intrinsic width (segments 120–160).
  final bool fullWidthSwitch;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    // At an accessibility text size the title owns its own row; a one-line
    // cap would still truncate some font/locale combinations at 200 %.
    final largeText = textScaler.scale(1) >= 1.6;
    final accessibilityLayout = largeText && fullWidthSwitch;
    // Wide slots at ordinary text sizes: the title, the switch and create
    // share one row instead of stacking two 48 px bands.
    final inlineSwitch = !fullWidthSwitch && !largeText;
    final title = Semantics(
      header: true,
      child: Text(
        copy.moments,
        key: const ValueKey<String>('yo-moments-title'),
        maxLines: accessibilityLayout ? null : 1,
        softWrap: accessibilityLayout,
        overflow: accessibilityLayout
            ? TextOverflow.visible
            : TextOverflow.ellipsis,
        textWidthBasis: TextWidthBasis.parent,
        // 22 px w800: the Slim wordmark size. Hierarchy comes from weight,
        // and the feed below owns the screen's content, not the chrome.
        style: AppTypography.headlineMedium.copyWith(
          color: palette.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    final back = showBack
        ? IconButton(
            key: const ValueKey<String>('yo-moments-back'),
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: palette.textPrimary,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          )
        : null;
    final create = onCreate == null
        ? null
        : YoMomentsCreateButton(onTap: onCreate!, compact: true);
    final switcher = YoMomentsFormatSwitch(
      selected: selectedFormat,
      onSelected: onFormatSelected,
      fullWidth: fullWidthSwitch,
    );

    if (inlineSwitch) {
      return Padding(
        padding: EdgeInsets.fromLTRB(gutter, AppRhythm.tight, gutter, 0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSizing.standardControlHeight,
          ),
          child: Row(
            children: <Widget>[
              if (back != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    end: AppRhythm.tight,
                  ),
                  child: back,
                ),
              Expanded(
                // Both loose, so a narrow medium slot or a long locale
                // shortens the words (ellipsis) instead of overflowing; at
                // every width the boards use both keep their natural size.
                child: Row(
                  children: <Widget>[
                    Flexible(child: title),
                    const SizedBox(width: AppRhythm.section),
                    Flexible(flex: 2, child: switcher),
                  ],
                ),
              ),
              if (create != null) ...<Widget>[
                const SizedBox(width: AppRhythm.item),
                create,
              ],
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, AppRhythm.tight, gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (accessibilityLayout) ...<Widget>[
            if (back != null)
              Align(alignment: AlignmentDirectional.centerStart, child: back),
            SizedBox(width: double.infinity, child: title),
            if (create != null) ...<Widget>[
              const SizedBox(height: AppRhythm.tight),
              Align(alignment: AlignmentDirectional.centerEnd, child: create),
            ],
          ] else
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppSizing.standardControlHeight,
              ),
              child: Row(
                children: <Widget>[
                  if (back != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        end: AppRhythm.tight,
                      ),
                      child: back,
                    ),
                  Expanded(child: title),
                  if (create != null) ...<Widget>[
                    const SizedBox(width: AppRhythm.item),
                    create,
                  ],
                ],
              ),
            ),
          const SizedBox(height: AppRhythm.tight),
          if (fullWidthSwitch)
            SizedBox(width: double.infinity, child: switcher)
          else
            Align(alignment: AlignmentDirectional.centerStart, child: switcher),
        ],
      ),
    );
  }
}

/// Level 1 on the canvas: trackless "Głos" | "Yeels" text tabs with a 48 px
/// interaction target and theme-aware violet active state. Slim segments:
/// 96–160 wide, so the pair sits beside the title in one header row.
class YoMomentsFormatSwitch extends StatelessWidget {
  const YoMomentsFormatSwitch({
    required this.selected,
    required this.onSelected,
    this.fullWidth = false,
    super.key,
  });

  final YoMomentsFormat selected;
  final ValueChanged<YoMomentsFormat> onSelected;
  final bool fullWidth;

  /// Desktop segments: min 96, max 160 (Slim: the words plus 12 px of air
  /// on either side, never a wide empty tab).
  static const double segmentMinWidth = 96;
  static const double segmentMaxWidth = 160;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final switcher = ImmersiveSegmentedSwitch(
      key: const ValueKey<String>('yo-moments-format-tabs'),
      onCanvas: true,
      segmentMinWidth: fullWidth ? 72 : segmentMinWidth,
      groupLabel: copy.contextualText(
        'yoMoments.contentFormat',
        'Content format',
        'Format treści',
      ),
      selectedIndex: selected.index,
      onSelected: (index) => onSelected(YoMomentsFormat.values[index]),
      segments: <ImmersiveChromeOption>[
        ImmersiveChromeOption(
          key: const ValueKey<String>('yo-moments-format-voice'),
          label: copy.contextualText('yoMoments.voiceFormat', 'Voice', 'Głos'),
        ),
        const ImmersiveChromeOption(
          key: ValueKey<String>('yo-moments-format-reels'),
          label: 'Yeels',
        ),
      ],
    );
    if (fullWidth) return switcher;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: segmentMaxWidth * YoMomentsFormat.values.length,
      ),
      child: switcher,
    );
  }
}

/// One pool filter as the chrome draws it — a row on desktop, a chip below.
@immutable
class YoMomentsFilterOption {
  const YoMomentsFilterOption({
    required this.key,
    required this.label,
    required this.icon,
  });

  final Key key;
  final String label;
  final IconData icon;
}

/// Level 2 below 1100: the pool filters as canvas chips (ink 36 in a 48
/// target) with an optional trailing control (the feed's refresh, which is
/// also the focus-recovery target after an expiry removal). Slim: no card
/// or outline under an unselected chip; only the selected one carries a
/// tonal wash (plus weight and the `selected` flag).
class YoMomentsFilterChips extends StatelessWidget {
  const YoMomentsFilterChips({
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
    required this.groupLabel,
    required this.gutter,
    this.trailing,
    super.key,
  });

  final List<YoMomentsFilterOption> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String groupLabel;
  final double gutter;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: ImmersiveFilterRow(
            onCanvas: true,
            // The strip scrolls; its last chip has to be cut by a clean
            // edge and not by the pinned control beside it, so the trailing
            // inset is the full gutter with or without that control.
            padding: EdgeInsetsDirectional.only(start: gutter, end: gutter),
            groupLabel: groupLabel,
            options: <ImmersiveChromeOption>[
              for (final option in options)
                ImmersiveChromeOption(key: option.key, label: option.label),
            ],
            selectedIndex: selectedIndex,
            onSelected: onSelected,
          ),
        ),
        if (trailing != null)
          Padding(
            padding: EdgeInsetsDirectional.only(end: gutter - AppRhythm.tight),
            child: trailing,
          ),
      ],
    );
  }
}

/// Level 2 at ≥ 1100: the local panel — filter rows (48, `AppRadius.md`,
/// selected wash), an optional trailing control and the "Utwórz" action.
///
/// `surfaceMuted` with a trailing hairline, flush with the slot's leading
/// edge exactly like the rail it sits beside. It carries NO title: the main
/// header owns "YO Moments" (spec §11 forbids a duplicated heading). Slim:
/// 12 px insets, rows without an outline, a flat create bar.
class YoMomentsLocalPanel extends StatelessWidget {
  const YoMomentsLocalPanel({
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
    required this.groupLabel,
    required this.width,
    this.trailing,
    this.onCreate,
    super.key,
  });

  final List<YoMomentsFilterOption> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String groupLabel;
  final double width;
  final Widget? trailing;
  final VoidCallback? onCreate;

  static const double rowHeight = 48;
  static const double rowGap = AppRhythm.hairline;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Semantics(
      container: true,
      label: groupLabel,
      child: Container(
        key: const ValueKey<String>('yo-moments-local-panel'),
        width: width,
        decoration: BoxDecoration(
          color: palette.surfaceMuted,
          border: BorderDirectional(end: BorderSide(color: palette.border)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppRhythm.item),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var index = 0; index < options.length; index++) ...<Widget>[
                if (index > 0) const SizedBox(height: rowGap),
                _LocalPanelRow(
                  key: options[index].key,
                  option: options[index],
                  selected: index == selectedIndex,
                  onTap: () => onSelected(index),
                ),
              ],
              if (trailing != null) ...<Widget>[
                const SizedBox(height: AppRhythm.tight),
                trailing!,
              ],
              if (onCreate != null) ...<Widget>[
                const SizedBox(height: AppRhythm.title),
                YoMomentsCreateButton(onTap: onCreate!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalPanelRow extends StatefulWidget {
  const _LocalPanelRow({
    required this.option,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final YoMomentsFilterOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_LocalPanelRow> createState() => _LocalPanelRowState();
}

class _LocalPanelRowState extends State<_LocalPanelRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final primary = Theme.of(context).colorScheme.primary;
    final selected = widget.selected;
    return Semantics(
      button: true,
      selected: selected,
      label: widget.option.label,
      onTap: widget.onTap,
      enabled: true,
      focusable: true,
      focused: _focused,
      excludeSemantics: true,
      child: Material(
        // Selection is the tonal wash + weight + ink (and the semantic flag);
        // no outline, so the panel reads as a list, not a stack of cards.
        color: selected ? primary.withValues(alpha: .14) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.md,
          side: BorderSide(
            color: _focused ? palette.focus : Colors.transparent,
            width: _focused ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: selected ? () {} : widget.onTap,
          onFocusChange: (focused) {
            if (_focused != focused) setState(() => _focused = focused);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: YoMomentsLocalPanel.rowHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppRhythm.item),
              child: Row(
                children: <Widget>[
                  Icon(
                    widget.option.icon,
                    size: 20,
                    color: selected
                        ? palette.textPrimary
                        : palette.textSecondary,
                  ),
                  const SizedBox(width: AppRhythm.item),
                  Expanded(
                    child: Text(
                      widget.option.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleSmall.copyWith(
                        color: selected
                            ? palette.textPrimary
                            : palette.textSecondary,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Utwórz" — the create action, the screen's one violet accent. On the
/// local panel it is a full-width 48 bar (`AppRadius.md`, solid primary,
/// white w800, no gradient and no shadow: it does not float); [compact] is
/// the 48 disc the phone header carries.
///
/// Always enabled: the active-Moment cap is the server's rule, enforced by
/// `reserveMomentDraft`, and the recorder surfaces its refusal honestly.
class YoMomentsCreateButton extends StatefulWidget {
  const YoMomentsCreateButton({
    required this.onTap,
    this.compact = false,
    super.key,
  });

  final VoidCallback onTap;
  final bool compact;

  @override
  State<YoMomentsCreateButton> createState() => _YoMomentsCreateButtonState();
}

class _YoMomentsCreateButtonState extends State<YoMomentsCreateButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final label = copy.contextualText('yoMoments.create', 'Create', 'Utwórz');
    if (widget.compact) {
      return IconButton.filled(
        key: const ValueKey<String>('moments-create-cta'),
        onPressed: widget.onTap,
        tooltip: label,
        constraints: const BoxConstraints(
          minWidth: AppSizing.standardControlHeight,
          minHeight: AppSizing.standardControlHeight,
        ),
        style: IconButton.styleFrom(
          backgroundColor: colors.primary,
          shape: const CircleBorder(),
        ),
        icon: Icon(Icons.add_rounded, color: colors.onPrimary),
      );
    }
    return Semantics(
      button: true,
      label: label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: SizedBox(
        width: double.infinity,
        height: AppSizing.standardControlHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: AppRadius.md,
            color: colors.primary,
            border: Border.all(
              color: _focused ? colors.onPrimary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey<String>('moments-create-cta'),
              borderRadius: AppRadius.md,
              onFocusChange: (value) => setState(() => _focused = value),
              onTap: widget.onTap,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.add_rounded, color: colors.onPrimary, size: 19),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.onPrimary,
                          fontWeight: FontWeight.w800,
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
    );
  }
}

/// The static "VOICE MOMENT" format mark: a 28-px pill with the shared
/// Moments glyph and the tracked eyebrow. It names the format and nothing
/// else — no data, no state — and reads to assistive technology as the
/// invariant format name, not as shouting capitals.
class YoMomentsFormatBadge extends StatelessWidget {
  const YoMomentsFormatBadge({this.outlined = true, super.key});

  /// The card draws the bordered pill; a hero eyebrow drops the border.
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final name = copy.text('Voice Moment', 'Voice Moment');
    return Semantics(
      container: true,
      label: name,
      excludeSemantics: true,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: AppRhythm.item),
        decoration: BoxDecoration(
          borderRadius: AppRadius.pill,
          border: outlined ? Border.all(color: palette.border) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            YoMomentsIcon(
              state: YoMomentsIconState.inactive,
              size: 14,
              color: palette.textSecondary,
            ),
            const SizedBox(width: AppRhythm.tight - 2),
            Text(
              name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // The mark is a fixed-height pill; its copy is repeated in the
              // semantic label at the reader's own size.
              textScaler: MediaQuery.textScalerOf(
                context,
              ).clamp(maxScaleFactor: 1.3),
              style: AppTypography.eyebrow.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
