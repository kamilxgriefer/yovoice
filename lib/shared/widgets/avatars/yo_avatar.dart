import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';

class YoAvatar extends StatelessWidget {
  const YoAvatar({
    super.key,
    this.imageUrl,
    this.name,
    this.size = 48,
    this.isOnline = false,
    this.onTap,
  });

  final String? imageUrl;
  final String? name;
  final double size;
  final bool isOnline;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final String initial = name == null || name!.trim().isEmpty
        ? '?'
        : name!.trim().characters.first.toUpperCase();

    final Widget avatar = Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.surfaceMuted,
            border: Border.all(color: palette.border, width: 1),
            image: imageUrl != null && imageUrl!.trim().isNotEmpty
                ? DecorationImage(
                    image: NetworkImage(imageUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          alignment: Alignment.center,
          child: imageUrl == null || imageUrl!.trim().isEmpty
              ? Text(
                  initial,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: size * 0.38,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : null,
        ),
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.27,
              height: size * 0.27,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.success,
                border: Border.all(color: palette.background, width: 2),
              ),
            ),
          ),
      ],
    );

    if (onTap == null) {
      return avatar;
    }

    final profileName = name?.trim();
    final label = profileName?.isNotEmpty == true
        ? 'Open profile for $profileName'
        : 'Open profile';
    return AccessibleTapRegion(
      onTap: onTap,
      semanticLabel: label,
      tooltip: label,
      circular: true,
      child: avatar,
    );
  }
}
