import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
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
      final cardsWidth = math.min(width, ServerSelectorMetrics.maxWidth) - 96;
      final readableCardWidth = 160 * titleScale;
      // Preserve the reference breakpoints at normal text size. Enlarged text
      // gets fewer, wider columns instead of splitting words into fragments.
      final compact =
          width <= ServerSelectorMetrics.compactBreakpoint ||
          (largeText && (cardsWidth - 32) / 3 < readableCardWidth);
      final medium =
          width <= ServerSelectorMetrics.wideBreakpoint ||
          (largeText && (cardsWidth - 64) / 5 < readableCardWidth);
      final copy = AppLocalizations.of(context);
      final palette = context.appPalette;
      final titleSize = compact ? 39.0 : (width * .042).clamp(34.0, 64.0);
      final align = compact ? TextAlign.start : TextAlign.center;
      return SingleChildScrollView(
        key: const ValueKey('server-selector-scroll'),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ServerSelectorMetrics.maxWidth,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 20 : 48,
                compact
                    ? 25
                    : width >= 1600
                    ? 80
                    : 45,
                compact ? 20 : 48,
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
                  Semantics(
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
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '${copy.serverSelectorQuestion}\n${copy.serverSelectorLead}',
                    textAlign: align,
                    style: AppTypography.bodyLarge.copyWith(
                      fontSize: compact ? 14 : 17,
                      height: compact ? 1.5 : 1.6,
                      color: palette.textSecondary,
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
                            const SizedBox(height: 11),
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
                          (cards.maxWidth - 32) / 3,
                        );
                        return Column(
                          children: [
                            _row(ServerType.values.take(3).toList(), 320),
                            const SizedBox(height: 16),
                            Center(
                              child: SizedBox(
                                width: cardWidth * 2 + 16,
                                child: _row(
                                  ServerType.values.skip(3).toList(),
                                  320,
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

  Widget _row(List<ServerType> types, double minimumHeight) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final type in types) ...[
          if (type != types.first) const SizedBox(width: 16),
          Expanded(
            child: ServerTemplateCard(
              type: type,
              minimumHeight: minimumHeight,
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
    this.minimumHeight = 390,
    super.key,
  });
  final ServerType type;
  final VoidCallback onPressed;
  final bool compact;
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
    final colors = ServerIdentity.of(
      widget.type,
    ).resolve(Theme.of(context).brightness);
    final compact = widget.compact;
    final stackedCompact =
        compact && MediaQuery.textScalerOf(context).scale(19) > 19 * 1.3;
    final radius = BorderRadius.circular(
      compact
          ? ServerSelectorMetrics.compactRadius
          : ServerSelectorMetrics.cardRadius,
    );
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
    return Semantics(
      button: true,
      enabled: true,
      focusable: true,
      focused: _focused,
      label: copy.serverTypeTitle(widget.type),
      hint:
          '${copy.serverTypeDescription(widget.type)} '
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
          color: palette.surfaceMuted,
          borderRadius: radius,
          border: Border.all(
            width: _focused ? 3 : 1,
            color: _focused
                ? colors.focus
                : _hovered
                ? colors.foreground
                : palette.border,
          ),
          gradient: LinearGradient(
            begin: const Alignment(-.17, -1),
            end: const Alignment(.17, 1),
            colors: [
              _hovered ? colors.selectedWash : colors.cardWash,
              palette.surfaceMuted.withValues(alpha: 0),
            ],
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
                  Positioned(
                    right: -64,
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
                                    Icons.north_east_rounded,
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
                                  Icons.north_east_rounded,
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
                              SizedBox(
                                height: widget.minimumHeight == 320 ? 22 : 35,
                              ),
                              title,
                              const SizedBox(height: 15),
                              description,
                              const SizedBox(height: 25),
                              const Spacer(),
                              Text(
                                copy.serverTypeFeatures(widget.type),
                                style: AppTypography.bodySmall.copyWith(
                                  height: 1.9,
                                  color: palette.textSecondary,
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
                                        color: colors.foreground,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.north_east_rounded,
                                    size: 18,
                                    color: colors.foreground,
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
