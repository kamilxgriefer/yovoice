import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/pages/data/page_catalog.dart';
import 'package:yovoice/features/pages/presentation/page_profile_copy.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_face.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/widgets/navigation/yo_server_rail_item.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

// The pickers a Page form opens (category / topic, linked server), shared by
// create A and "Edytuj stronę".

/// The server-owned categories of [kind] as a radio list; pops the key.
class PageCategorySheet extends StatelessWidget {
  const PageCategorySheet({
    required this.kind,
    required this.selected,
    super.key,
  });

  final PageKind kind;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    final title = kind == PageKind.business
        ? copy.chooseCategory
        : copy.chooseTopic;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            YoModalSheetChrome(
              sheetLabel: title,
              surfaceColor: palette.surfaceRaised,
              onClose: () => Navigator.of(context).pop(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                title,
                style: AppTypography.screenTitle.copyWith(
                  color: palette.textPrimary,
                  fontSize: 21,
                ),
              ),
            ),
            RadioGroup<String>(
              groupValue: selected,
              onChanged: (value) => Navigator.of(context).pop(value),
              child: Column(
                children: [
                  for (final key in PageCatalog.categoriesFor(kind))
                    RadioListTile<String>(
                      key: ValueKey('page-category-$key'),
                      value: key,
                      title: Text(
                        copy.categoryLabel(key),
                        style: AppTypography.bodyLarge.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerChoice {
  const _ServerChoice(this.serverId);

  final String? serverId;
}

/// The owner's public Community / Podcast servers (the only ones a Page may
/// link, §2.2) plus "Bez serwera"; pops the choice.
class PageServerSheet extends StatelessWidget {
  const PageServerSheet({
    required this.userId,
    required this.selected,
    this.servers,
    super.key,
  });

  final String userId;
  final String? selected;
  final Stream<List<Server>> Function()? servers;

  /// Servers a Page may link: owned, active, public Community or Podcast.
  static List<Server> eligible(List<Server> servers, String userId) => [
    for (final server in servers)
      if (server.ownerId == userId &&
          server.status == 'active' &&
          server.privacy == ServerPrivacy.public &&
          (server.type == ServerType.community ||
              server.type == ServerType.podcast))
        server,
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    final stream = (servers ?? () => ServerService().watchMyServers())();
    return SafeArea(
      top: false,
      child: StreamBuilder<List<Server>>(
        stream: stream,
        builder: (context, snapshot) {
          final options = eligible(snapshot.data ?? const <Server>[], userId);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                YoModalSheetChrome(
                  sheetLabel: copy.linkedServerLabel,
                  surfaceColor: palette.surfaceRaised,
                  onClose: () => Navigator.of(context).pop(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Text(
                    copy.linkedServerLabel,
                    style: AppTypography.screenTitle.copyWith(
                      color: palette.textPrimary,
                      fontSize: 21,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Text(
                    copy.linkedServerHelper,
                    style: AppTypography.bodySmall.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ),
                ListTile(
                  key: const ValueKey('page-server-none'),
                  minTileHeight: 56,
                  leading: const Icon(Icons.link_off_rounded),
                  title: Text(copy.noLinkedServer),
                  trailing: selected == null
                      ? Icon(
                          Icons.check_rounded,
                          color: palette.interactiveForeground,
                        )
                      : null,
                  onTap: () =>
                      Navigator.of(context).pop(const _ServerChoice(null)),
                ),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    options.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: YoLoadingIndicator()),
                  )
                else if (options.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      copy.noEligibleServers,
                      style: AppTypography.bodySmall.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                for (final server in options)
                  ListTile(
                    key: ValueKey('page-server-${server.id}'),
                    minTileHeight: 56,
                    leading: YoServerTile(
                      initial: PageFace.initialFor(server.name),
                      type: server.type,
                      size: 36,
                      bordered: false,
                    ),
                    title: Text(
                      server.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: selected == server.id
                        ? Icon(
                            Icons.check_rounded,
                            color: palette.interactiveForeground,
                          )
                        : null,
                    onTap: () =>
                        Navigator.of(context).pop(_ServerChoice(server.id)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Opens [PageServerSheet]; null when dismissed, else the chosen id (which
/// may itself be null for "Bez serwera").
Future<({String? serverId})?> pickLinkedServer(
  BuildContext context, {
  required String userId,
  required String? selected,
  Stream<List<Server>> Function()? servers,
}) async {
  final choice = await showModalBottomSheet<_ServerChoice>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: context.appPalette.surfaceRaised,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) =>
        PageServerSheet(userId: userId, selected: selected, servers: servers),
  );
  return choice == null ? null : (serverId: choice.serverId);
}

/// Opens [PageCategorySheet]; the picked key or null.
Future<String?> pickPageCategory(
  BuildContext context, {
  required PageKind kind,
  required String? selected,
}) => showModalBottomSheet<String>(
  context: context,
  useRootNavigator: true,
  useSafeArea: true,
  isScrollControlled: true,
  backgroundColor: context.appPalette.surfaceRaised,
  constraints: const BoxConstraints(maxWidth: 560),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) => PageCategorySheet(kind: kind, selected: selected),
);
