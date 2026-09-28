import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';

/// "+ Obserwuj" / "✓ Obserwujesz" (wall A rail, Find rows, R15): the R7
/// neutral tonal pill. The visible pill is [height] tall; the hit area is
/// padded to 48 × 44 at least, and it grows with the reader's text.
class PageFollowButton extends StatelessWidget {
  const PageFollowButton({
    required this.following,
    required this.pageName,
    required this.onPressed,
    this.busy = false,
    this.expand = false,
    this.height = 32,
    super.key,
  });

  final bool following;
  final String pageName;
  final VoidCallback? onPressed;
  final bool busy;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    final scaler = MediaQuery.textScalerOf(context);
    final visible = height > scaler.scale(12.5) * 1.2 + 12
        ? height
        : scaler.scale(12.5) * 1.2 + 12;
    final style = AppFinish.tonalNeutral(palette, highContrast: highContrast)
        .copyWith(
          minimumSize: WidgetStatePropertyAll(Size(48, visible)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12),
          ),
          tapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.standard,
          textStyle: WidgetStatePropertyAll(
            AppTypography.labelMedium.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
          iconSize: const WidgetStatePropertyAll(16),
        );
    final label = following ? copy.following : copy.follow;
    final Widget icon = busy
        ? SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: palette.interactiveForeground,
            ),
          )
        : Icon(following ? Icons.check_rounded : Icons.add_rounded);
    final Widget core = TextButton.icon(
      onPressed: busy ? null : onPressed,
      style: style,
      icon: icon,
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    return Semantics(
      button: true,
      enabled: !busy && onPressed != null,
      onTap: busy ? null : onPressed,
      toggled: following,
      label: following
          ? copy.unfollowPage(pageName)
          : copy.followPage(pageName),
      excludeSemantics: true,
      child: expand ? SizedBox(width: double.infinity, child: core) : core,
    );
  }
}
