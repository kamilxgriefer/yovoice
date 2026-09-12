import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_typography.dart';

import '../../data/models/server_type.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';
import 'server_type_symbol.dart';

class ServerTemplateSelector extends StatelessWidget {
  const ServerTemplateSelector({required this.onSelected, super.key});
  final ValueChanged<ServerType> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final titleScale = MediaQuery.textScalerOf(context).scale(23) / 23;
      final largeText = titleScale > 1.3;
      // The fit tests below evaluate the multi-column hypothesis — "would
      // three (or five) readable columns fit if we kept the wide page
      // padding?" — so they deliberately carry the wide padding on both
      // sides, not the compact padding that applies only once the answer
      // is no.
      final cardsWidth =
          math.min(width, ServerSelectorMetrics.maxWidth) -
          2 * ServerSelectorMetrics.sidePadding;
      final readableCardWidth = 160 * titleScale;
      // Preserve the reference breakpoints at normal text size. Enlarged text
      // gets fewer, wider columns instead of splitting words into fragments.
      final compact =
          width <= ServerSelectorMetrics.compactBreakpoint ||
          (largeText &&
              (cardsWidth - 2 * ServerSelectorMetrics.columnGap) / 3 <
                  readableCardWidth);
      final medium =
          width <= ServerSelectorMetrics.wideBreakpoint ||
          (largeText &&
              (cardsWidth - 4 * ServerSelectorMetrics.columnGap) / 5 <
                  readableCardWidth);
      final copy = AppLocalizations.of(context);
      final palette = context.appPalette;
      final titleSize = compact ? 39.0 : (width * .042).clamp(34.0, 64.0);
      final align = compact ? TextAlign.start : TextAlign.center;
      final sidePadding = compact
          ? ServerSelectorMetrics.compactSidePadding
          : ServerSelectorMetrics.sidePadding;
      final heading = Semantics(
        header: true,
        child: Text(
          copy.createServerTitle,
          textAlign: align,
          style: AppTypography.displayLarge.copyWith(
            fontSize: titleSize,
            height: 1.1,
            letterSpacing: compact ? -1.5 : -2.4,
            color: palette.textPrimary,
          ),
        ),
      );
      final lead = Text(
        '${copy.serverSelectorQuestion}\n${copy.serverSelectorLead}',
        textAlign: align,
        style: AppTypography.bodyLarge.copyWith(
          fontSize: compact ? 14 : 17,
          height: compact ? 1.5 : 1.6,
          color: palette.textSecondary,
        ),
      );
      return SingleChildScrollView(
        key: const ValueKey('server-selector-scroll'),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ServerSelectorMetrics.maxWidth,
            ),
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                sidePadding,
                compact
                    ? 25
                    : width >= 1600
                    ? 80
                    : 45,
                sidePadding,
                48,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    copy.serverSelectorEyebrow,
                    textAlign: align,
                    style: AppTypography.labelMedium.copyWith(
                      fontSize: compact ? 10 : 12,
                      letterSpacing: 2,
                      color: palette.interactiveForeground,
                    ),
                  ),
                  const SizedBox(height: 18),
                  // `@media(max-width:640){h1{max-width:350px}}`; the wide
                  // heading has no measure in the reference and keeps the
                  // full width so its centring is exact.
                  if (compact)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: ServerSelectorMetrics.compactHeadingMeasure,
                        ),
                        child: heading,
                      ),
                    )
                  else
                    heading,
                  const SizedBox(height: 14),
                  // `.lead{max-width:620px;margin:0 auto}` at every width.
                  Align(
                    alignment: compact
                        ? AlignmentDirectional.centerStart
                        : Alignment.center,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: ServerSelectorMetrics.leadMeasure,
                      ),
                      child: lead,
                    ),
                  ),
                  SizedBox(
                    height: compact
                        ? 25
                        : medium
                        ? 30
                        : 48,
                  ),
                  if (compact)
                    Column(
                      children: [
                        for (final type in ServerType.values) ...[
                          if (type != ServerType.values.first)
                            const SizedBox(
                              height: ServerSelectorMetrics.compactRowGap,
                            ),
                          ServerTemplateCard(
                            type: type,
                            compact: true,
                            onPressed: () => onSelected(type),
                          ),
                        ],
                      ],
                    )
                  else if (medium)
                    LayoutBuilder(
                      builder: (context, cards) {
                        final cardWidth = math.max(
                          0.0,
                          (cards.maxWidth -
                                  2 * ServerSelectorMetrics.columnGap) /
                              3,
                        );
                        return Column(
                          children: [
                            _row(
                              ServerType.values.take(3).toList(),
                              320,
                              medium: true,
                            ),
                            const SizedBox(
                              height: ServerSelectorMetrics.columnGap,
                            ),
                            Center(
                              child: SizedBox(
                                width:
                                    cardWidth * 2 +
                                    ServerSelectorMetrics.columnGap,
                                child: _row(
                                  ServerType.values.skip(3).toList(),
                                  320,
                                  medium: true,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    )
                  else
                    _row(ServerType.values, width >= 1600 ? 435 : 390),
                  SizedBox(height: compact ? 22 : 28),
                  Text(
                    copy.text(
                      'One server. Many channels. Your character.',
                      'Jeden serwer. Wiele kanałów. Twój charakter.',
                    ),
                    textAlign: align,
                    style: AppTypography.bodySmall.copyWith(
                      color: palette.textSecondary,
                      fontSize: compact ? 11 : 12,
                      height: 1.7,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _row(
    List<ServerType> types,
    double minimumHeight, {
    bool medium = false,
  }) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final type in types) ...[
          if (type != types.first)
            const SizedBox(width: ServerSelectorMetrics.columnGap),
          Expanded(
            child: ServerTemplateCard(
              type: type,
              minimumHeight: minimumHeight,
              medium: medium,
              onPressed: () => onSelected(type),
            ),
          ),
        ],
      ],
    ),
  );
}

class ServerTemplateCard extends StatefulWidget {
  const ServerTemplateCard({
    required this.type,
    required this.onPressed,
    this.compact = false,
    this.medium = false,
    this.minimumHeight = 390,
    super.key,
  });
  final ServerType type;
  final VoidCallback onPressed;
  final bool compact;

  /// The 3 + 2 arrangement (`@media(max-width:1150)`): the only thing it
  /// changes inside the card is `.symbol{margin-bottom:22px}`. It is a layout
  /// mode, not a height, so changing the medium card's height never moves
  /// the symbol by accident.
  final bool medium;
  final double minimumHeight;

  @override
  State<ServerTemplateCard> createState() => _ServerTemplateCardState();
}

class _ServerTemplateCardState extends State<ServerTemplateCard> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final brightness = Theme.of(context).brightness;
    final colors = ServerIdentity.of(widget.type).resolve(brightness);
    final compact = widget.compact;
    final stackedCompact =
        compact && MediaQuery.textScalerOf(context).scale(19) > 19 * 1.3;
    final radius = BorderRadius.circular(
      compact
          ? ServerSelectorMetrics.compactRadius
          : ServerSelectorMetrics.cardRadius,
    );
    // The reference's ↗ points into the reading direction's far corner; in
    // a right-to-left layout that corner is on the left.
    final arrow = Directionality.of(context) == TextDirection.rtl
        ? Icons.north_west_rounded
        : Icons.north_east_rounded;
    final symbol = Container(
      width: compact ? 49 : 64,
      height: compact ? 49 : 64,
      decoration: BoxDecoration(
        color: colors.iconSurface,
        border: Border.all(color: colors.iconBorder),
        borderRadius: BorderRadius.circular(compact ? 16 : 20),
      ),
      child: Center(
        child: ServerTypeSymbol(
          type: widget.type,
          color: colors.foreground,
          size: compact ? 25 : 31,
        ),
      ),
    );
    final title = Text(
      copy.serverTypeTitle(widget.type),
      style: AppTypography.headlineSmall.copyWith(
        fontSize: compact ? 19 : 23,
        fontWeight: FontWeight.w700,
        letterSpacing: -.8,
        height: 1.15,
        color: palette.textPrimary,
      ),
    );
    final description = Text(
      copy.serverTypeDescription(widget.type),
      style: AppTypography.bodyMedium.copyWith(
        fontSize: compact ? 12 : 14,
        height: compact ? 1.45 : 1.6,
        color: palette.textSecondary,
      ),
    );
    final features = copy.serverTypeFeatures(widget.type);
    return Semantics(
      button: true,
      enabled: true,
      focusable: true,
      focused: _focused,
      label: copy.serverTypeTitle(widget.type),
      // The feature list is a third of what a sighted person weighs before
      // choosing, so it is spoken wherever it is drawn. At ≤640 the
      // reference hides it (`.features{display:none}`) and so does the hint.
      hint:
          '${copy.serverTypeDescription(widget.type)} '
          '${compact ? '' : '${features.replaceAll('\n', ', ')}. '}'
          '${copy.text('Configure this server', 'Skonfiguruj ten serwer')}',
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: AnimatedContainer(
        key: ValueKey('server-template-${widget.type.name}'),
        duration: AppMotion.resolve(context, AppMotion.standard),
        transform: Matrix4.translationValues(
          0,
          _hovered && !compact ? -6 : 0,
          0,
        ),
        constraints: BoxConstraints(
          minHeight: compact ? 110 : widget.minimumHeight,
        ),
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: _hovered ? colors.foreground : palette.border,
          ),
          // `background:#100D18` under
          // `linear-gradient(170deg, rgba(--rgb,.085), transparent 75%)`,
          // stretched to `.16 / 90%` on hover.
          //
          // Both stops are OPAQUE, and that is the fix, not a detail:
          // `BoxDecoration` paints a gradient as the background paint's
          // *shader*, which overrides `color:` entirely. With the far stop at
          // alpha 0 the card had no base fill at all below the fade — its
          // interior measured `#080711`, the page colour, instead of
          // `#100D18`, at every width and in both themes. Compositing the
          // wash over the card fill here reproduces what the browser draws
          // with a translucent gradient over an opaque background.
          gradient: LinearGradient(
            begin: const Alignment(-.17, -1),
            end: const Alignment(.17, 1),
            stops: [
              0,
              _hovered
                  ? ServerSelectorMetrics.hoverWashFadeStop
                  : ServerSelectorMetrics.washFadeStop,
            ],
            colors: [
              Color.alphaBlend(
                _hovered ? colors.selectedWash : colors.cardWash,
                palette.surfaceMuted,
              ),
              palette.surfaceMuted,
            ],
          ),
        ),
        // Painted over the card instead of widening its border, so arriving
        // focus never nudges the title and description by the extra width.
        //
        // The ring is ALWAYS present and only changes colour. A null-to-value
        // foregroundDecoration would add a DecoratedBox to the tree the moment
        // focus arrived, which re-parents everything below it: Flutter reuses
        // the existing DecoratedBox element for the new foreground one, finds
        // a different widget type beneath it and rebuilds the Material and
        // InkWell from scratch — destroying the very focus node that had just
        // been focused. Keyboard focus then landed on nothing and Enter did
        // not activate the card, while `Semantics(focused:)` still reported
        // focus because it mirrors this widget's own state.
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: _focused ? colors.focus : AppColors.transparent,
            width: ServerSelectorMetrics.focusRingWidth,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: radius,
            onFocusChange: (focused) => setState(() => _focused = focused),
            onHover: (hovered) => setState(() => _hovered = hovered),
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                children: [
                  // `.card:before{right:-64px;top:-46px}` — the far corner of
                  // the reading direction, so it mirrors with the layout.
                  PositionedDirectional(
                    end: -64,
                    top: -46,
                    child: IgnorePointer(
                      child: Container(
                        width: 190,
                        height: 190,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.orbit),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 19 : 23,
                      vertical: compact ? 19 : 30,
                    ),
                    child: stackedCompact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  symbol,
                                  const Spacer(),
                                  Icon(
                                    arrow,
                                    size: 22,
                                    color: colors.foreground,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              title,
                              const SizedBox(height: 6),
                              description,
                            ],
                          )
                        : compact
                        ? Row(
                            children: [
                              symbol,
                              const SizedBox(width: 17),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    title,
                                    const SizedBox(height: 6),
                                    description,
                                  ],
                                ),
                              ),
                              const SizedBox(width: 17),
                              SizedBox(
                                width: 28,
                                child: Icon(
                                  arrow,
                                  size: 22,
                                  color: colors.foreground,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 8),
                              symbol,
                              SizedBox(height: widget.medium ? 22 : 35),
                              title,
                              const SizedBox(height: 15),
                              description,
                              const SizedBox(height: 25),
                              const Spacer(),
                              Text(
                                features,
                                style: AppTypography.bodySmall.copyWith(
                                  height: 1.9,
                                  color: serverSelectorFeatureInk(
                                    brightness,
                                    palette,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Divider(
                                height: 1,
                                color: palette.textPrimary.withValues(
                                  alpha: .05,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      copy.text('Choose', 'Wybierz'),
                                      style: AppTypography.labelMedium.copyWith(
                                        fontSize: 13,
                                        color: colors.linkForeground,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    arrow,
                                    size: 18,
                                    color: colors.linkForeground,
                                  ),
                                ],
                              ),
                            ],
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
