import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_face.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/widgets/identity/yo_vip_rosette.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';

/// One row of a Page ⋯ sheet (R10).
class PageMenuItem<T> {
  const PageMenuItem({
    required this.value,
    required this.icon,
    required this.label,
    this.danger = false,
    this.key,
  });

  final T value;
  final IconData icon;
  final String label;
  final bool danger;
  final Key? key;
}

/// The Page ⋯ sheet (R10): the Page's identity on top, then groups of rows
/// split by hairlines; destructive rows in the danger ink.
Future<T?> showPageMenuSheet<T>(
  BuildContext context, {
  required String sheetLabel,
  required String pageId,
  required String pageName,
  required PageKind? kind,
  required String meta,
  required List<List<PageMenuItem<T>>> groups,
}) {
  final palette = context.appPalette;
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: palette.surfaceRaised,
    showDragHandle: false,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => _PageMenuSheet<T>(
      sheetLabel: sheetLabel,
      pageId: pageId,
      pageName: pageName,
      kind: kind,
      meta: meta,
      groups: groups,
    ),
  );
}

class _PageMenuSheet<T> extends StatelessWidget {
  const _PageMenuSheet({
    required this.sheetLabel,
    required this.pageId,
    required this.pageName,
    required this.kind,
    required this.meta,
    required this.groups,
  });

  final String sheetLabel;
  final String pageId;
  final String pageName;
  final PageKind? kind;
  final String meta;
  final List<List<PageMenuItem<T>>> groups;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    Widget divider() =>
        Divider(height: 1, thickness: 1, indent: 72, color: palette.border);
    Widget tile(PageMenuItem<T> item) {
      final ink = item.danger ? palette.dangerForeground : palette.textPrimary;
      return ListTile(
        key: item.key,
        minTileHeight: 56,
        onTap: () => Navigator.of(context).pop(item.value),
        leading: Icon(item.icon, size: 22, color: ink),
        title: Text(
          item.label,
          style: AppTypography.titleMedium.copyWith(
            color: ink,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final rows = <Widget>[];
    for (var g = 0; g < groups.length; g++) {
      if (groups[g].isEmpty) continue;
      rows.add(divider());
      rows.addAll(groups[g].map(tile));
    }
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            YoModalSheetChrome(
              sheetLabel: sheetLabel,
              surfaceColor: palette.surfaceRaised,
              onClose: () => Navigator.of(context).pop(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  PageFace(
                    pageId: pageId,
                    name: pageName,
                    kind: kind,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        NameWithVipMark(
                          uid: pageId,
                          name: pageName,
                          style: AppTypography.rowTitle.copyWith(
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          style: AppTypography.bodySmall.copyWith(
                            color: palette.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ...rows,
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// A confirm dialog with a destructive action (remove friend, block,
/// delete post) or a plain one (pause).
Future<bool> confirmPageAction(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
  required String cancel,
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final palette = dialogContext.appPalette;
      final colors = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        backgroundColor: palette.surfaceRaised,
        title: Text(title, style: TextStyle(color: palette.textPrimary)),
        content: Text(body, style: TextStyle(color: palette.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(cancel),
          ),
          FilledButton(
            key: const ValueKey('page-confirm-action'),
            onPressed: () => Navigator.pop(dialogContext, true),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                  )
                : null,
            child: Text(confirm),
          ),
        ],
      );
    },
  );
  return result == true;
}
