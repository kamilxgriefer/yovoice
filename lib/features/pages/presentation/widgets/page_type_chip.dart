import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_face.dart';
import 'package:yovoice/features/servers/presentation/theme/server_identity.dart';
import 'package:yovoice/shared/identity/public_identity.dart';

/// The Page type chip (wall A, R15): the Company / Community server
/// identity's surface, edge and ink, so the kind reads like the server
/// templates it mirrors. It grows with the reader's text (minimum 20, or 18
/// compact) instead of clipping at a fixed height.
class PageTypeChip extends StatelessWidget {
  const PageTypeChip({required this.kind, this.compact = false, super.key});

  final PageKind kind;
  final bool compact;

  static IconData iconFor(PageKind kind) => switch (kind) {
    PageKind.business => Icons.storefront_rounded,
    PageKind.community => Icons.groups_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final identity = ServerIdentity.of(
      PageFace.serverTypeFor(kind),
    ).resolve(Theme.of(context).brightness);
    final label = PagesCopy(AppLocalizations.of(context)).kindLabel(kind);
    return Container(
      constraints: BoxConstraints(minHeight: compact ? 18 : 20),
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 7, vertical: 1),
      decoration: BoxDecoration(
        color: identity.iconSurface,
        borderRadius: AppRadius.pill,
        border: Border.all(color: identity.iconBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            iconFor(kind),
            size: compact ? 11 : 12,
            color: identity.foreground,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.count.copyWith(
                color: identity.foreground,
                fontSize: compact ? 10.5 : 11,
                letterSpacing: .2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
