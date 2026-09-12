import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';

import '../../data/models/server_channel.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';
import 'server_panel.dart';

/// An honest module card.
///
/// Events, the calendar, memories and the shared list have channel kinds but
/// no persistence, callable or Rules yet (contract G9). The card names the
/// module the board shows, says `Wkrótce`, keeps the board's own action as a
/// visibly disabled control next to that label, and offers the real channel
/// as the way in. It never shows a date, a photo, a count or a list item that
/// no one wrote.
class ServerModuleCard extends StatelessWidget {
  const ServerModuleCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.colors,
    this.primaryLabel,
    this.primaryIcon,
    this.channel,
    this.onOpenChannel,
    this.large = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final ServerIdentityVisuals colors;

  /// The board's own action (`Dołączę`, `Będę`, `Odtwórz`, `Dodaj produkt`),
  /// drawn disabled beside the `Wkrótce` label — never a control that fails.
  final String? primaryLabel;
  final IconData? primaryIcon;

  /// The channel this module lives in, offered as a real destination.
  final ServerChannel? channel;
  final ValueChanged<ServerChannel>? onOpenChannel;

  /// The family template's larger type and targets.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final target = channel;
    final open = onOpenChannel;
    return Container(
      padding: EdgeInsets.all(large ? 20 : 16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: large ? 44 : 36,
                height: large ? 44 : 36,
                decoration: BoxDecoration(
                  color: colors.iconSurface,
                  borderRadius: AppRadius.sm,
                  border: Border.all(color: colors.iconBorder),
                ),
                child: Icon(
                  icon,
                  size: large ? 24 : 20,
                  color: colors.foreground,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    title,
                    style:
                        (large
                                ? AppTypography.titleLarge
                                : AppTypography.titleMedium)
                            .copyWith(color: palette.textPrimary),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: (large ? AppTypography.bodyMedium : AppTypography.bodySmall)
                .copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(
                avatar: const Icon(Icons.schedule_rounded, size: 16),
                label: Text(copy.serverComingSoon),
              ),
              if (primaryLabel != null)
                FilledButton.icon(
                  onPressed: null,
                  style: FilledButton.styleFrom(
                    minimumSize: Size(48, large ? 52 : 48),
                  ),
                  icon: Icon(primaryIcon ?? Icons.check_rounded, size: 18),
                  label: Text(primaryLabel!),
                ),
              if (target != null && open != null)
                TextButton.icon(
                  onPressed: () => open(target),
                  style: TextButton.styleFrom(
                    minimumSize: Size(48, large ? 52 : 48),
                    foregroundColor: colors.linkForeground,
                  ),
                  icon: Icon(serverChannelIcon(target.kind), size: 18),
                  label: Text(target.name),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
