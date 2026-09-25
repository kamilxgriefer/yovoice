import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/layout/home_section_header.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_status.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/presentation/server_localized_copy.dart';
import 'package:yovoice/features/servers/presentation/theme/server_identity.dart';
import 'package:yovoice/shared/widgets/navigation/yo_server_rail_item.dart'
    show YoServerTile;

/// Home's server-backed answer to “what can I continue right now?”.
///
/// The card deliberately makes no liveness or participant-count claim: the
/// server directory projection does not carry either fact. It only offers the
/// exact server workspace, where a person chooses an authorised channel.
class HomeServerConversationCard extends StatelessWidget {
  const HomeServerConversationCard({
    required this.snapshot,
    required this.onOpenServers,
    required this.onRetry,
    this.onOpenServer,
    this.expanded = false,
    this.liftCreate = true,
    super.key,
  });

  final AsyncSnapshot<List<Server>> snapshot;
  final VoidCallback onOpenServers;
  final VoidCallback onRetry;
  final ValueChanged<Server>? onOpenServer;
  final bool expanded;

  /// Whether the empty invitation's "Stwórz serwer" carries the screen's
  /// one CTA lift. Desktop passes false: the rail's own lifted "Stwórz
  /// serwer" is on the same screen, so Start keeps the gradient only.
  final bool liftCreate;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    if (snapshot.hasError) {
      return HomeSectionError(
        key: const ValueKey('home-servers-error'),
        error: snapshot.error,
        message: copy.text(
          'Your servers could not be loaded.',
          'Nie udało się wczytać Twoich serwerów.',
        ),
        onRetry: onRetry,
      );
    }
    if (!snapshot.hasData) {
      return const _ServerLoadingCard(key: ValueKey('home-servers-loading'));
    }

    final servers = snapshot.data ?? const <Server>[];
    if (servers.isEmpty) {
      return _ServerEmptyCard(
        key: const ValueKey('home-servers-empty'),
        onOpenServers: onOpenServers,
        expanded: expanded,
        liftCreate: liftCreate,
      );
    }
    return _ServerContinueCard(
      key: ValueKey('home-server-continue-${servers.first.id}'),
      server: servers.first,
      onOpenServers: onOpenServers,
      onOpenServer: onOpenServer,
      expanded: expanded,
    );
  }
}

/// A compact, honest directory preview. Selecting a row opens that exact
/// workspace when the shell supplies [onOpenServer]. Older callers keep the
/// Servers-directory fallback. Home never bypasses channel authorisation or
/// joins media by itself.
class HomeServersOverview extends StatelessWidget {
  const HomeServersOverview({
    required this.snapshot,
    required this.onOpenServers,
    this.onOpenServer,
    this.expandedHeading = false,
    super.key,
  });

  final AsyncSnapshot<List<Server>> snapshot;
  final VoidCallback onOpenServers;
  final ValueChanged<Server>? onOpenServer;
  final bool expandedHeading;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final servers = snapshot.data ?? const <Server>[];
    if (!snapshot.hasData || snapshot.hasError || servers.isEmpty) {
      return const SizedBox.shrink();
    }
    final visibleServers = servers.take(3).toList(growable: false);
    return Column(
      key: const ValueKey('home-servers-overview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          title: copy.homeInYourServers,
          scale: expandedHeading
              ? HomeSectionHeaderScale.expanded
              : HomeSectionHeaderScale.compact,
          onSeeAll: onOpenServers,
        ),
        // One layer (Slim): a single block whose rows are divided by 1 px
        // hairlines indented to the text edge, instead of a stack of
        // separately bordered cards. Refine-look: the R2 block finish (lit
        // fill, hairline edge, radius 20) with no padding; the rows keep
        // their own ink on a transparent Material inside the block.
        YoCard(
          key: const ValueKey('home-servers-list'),
          padding: EdgeInsets.zero,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final server in visibleServers) ...[
                  if (server != visibleServers.first)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: _ServerRow.textInset,
                      color: palette.hairline,
                    ),
                  _ServerRow(
                    key: ValueKey('home-server-row-${server.id}'),
                    server: server,
                    onTap: () {
                      final openServer = onOpenServer;
                      if (openServer != null) {
                        openServer(server);
                      } else {
                        onOpenServers();
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ServerContinueCard extends StatelessWidget {
  const _ServerContinueCard({
    required this.server,
    required this.onOpenServers,
    required this.onOpenServer,
    required this.expanded,
    super.key,
  });

  final Server server;
  final VoidCallback onOpenServers;
  final ValueChanged<Server>? onOpenServer;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final visuals = ServerIdentity.of(
      server.type,
    ).resolve(Theme.of(context).brightness);
    final status = server.isHeld
        ? copy.text('Preparing', 'W przygotowaniu')
        : copy.text('Choose a channel', 'Wybierz kanał');
    // Refine-look R2 + R3: Start's ONE lead block. The lit block finish
    // with a 240 px corner tint in the server's identity hue at the top-end
    // corner — fixed in pixels, so at 1440 it lights the empty right half of
    // the wide card instead of washing the whole of it. The phone
    // composition is sized by its content; the wide one keeps its 216 px
    // floor so the two-column desktop body still starts on an even line.
    return YoCard(
      tint: ServerIdentity.of(server.type).primary,
      minHeight: expanded ? 216 : null,
      padding: EdgeInsets.all(expanded ? AppSpacing.xl : AppRhythm.title),
      onTap: () {
        final openServer = onOpenServer;
        if (openServer != null) {
          openServer(server);
        } else {
          onOpenServers();
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Row(
            children: [
              YoServerTile(
                initial: server.initial,
                type: server.type,
                size: expanded ? 56 : 48,
                textStyle: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppRhythm.item),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      copy.serverTypeTitle(server.type),
                      style: AppTypography.labelMedium.copyWith(
                        color: visuals.foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      server.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.headlineSmall.copyWith(
                        color: palette.textPrimary,
                        fontSize: expanded ? 22 : 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.3,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppRhythm.item),
          Text(
            server.description.trim().isEmpty
                ? copy.serverTypeDescription(server.type)
                : server.description,
            maxLines: expanded ? 3 : 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMedium.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: AppRhythm.item),
          Row(
            children: [
              Icon(
                server.isHeld ? Icons.schedule_rounded : Icons.forum_outlined,
                size: 18,
                color: visuals.foreground,
              ),
              const SizedBox(width: AppRhythm.tight),
              Expanded(
                child: Text(
                  status,
                  style: AppTypography.labelLarge.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ),
              // The way in, as a quiet identity disc. Decorative: the whole
              // card is the one button, so the disc adds no second node.
              ExcludeSemantics(
                child: Container(
                  key: const ValueKey('home-server-continue-arrow'),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: visuals.iconSurface,
                    border: Border.all(color: visuals.iconBorder),
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 20,
                    color: visuals.foreground,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ServerEmptyCard extends StatelessWidget {
  const _ServerEmptyCard({
    required this.onOpenServers,
    required this.expanded,
    required this.liftCreate,
    super.key,
  });

  final VoidCallback onOpenServers;
  final bool expanded;
  final bool liftCreate;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    // With no server yet, the invitation is Start's lead block: the brand
    // violet in the corner, and the screen's one violet action (lifted on a
    // phone or tablet; flat beside the desktop rail's lifted one).
    return YoCard(
      tint: AppColors.primary,
      minHeight: expanded ? 216 : null,
      padding: EdgeInsets.all(expanded ? AppSpacing.xl : AppRhythm.title),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Icon(Icons.hub_outlined, color: palette.interactiveForeground),
          const SizedBox(height: AppRhythm.item),
          Text(
            copy.text(
              'A good conversation starts in your server.',
              'Dobra rozmowa zaczyna się na Twoim serwerze.',
            ),
            style: AppTypography.titleLarge.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
              letterSpacing: -.2,
            ),
          ),
          const SizedBox(height: AppRhythm.tight),
          Text(
            copy.text(
              'Create one, invite your people and choose a voice or text channel.',
              'Stwórz go, zaproś swoich ludzi i wybierz kanał głosowy lub tekstowy.',
            ),
            style: AppTypography.bodyMedium.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: AppRhythm.item),
          YoGradientFilledButton(
            key: const ValueKey('home-empty-create-server'),
            onPressed: onOpenServers,
            emphasis: liftCreate
                ? YoActionEmphasis.lifted
                : YoActionEmphasis.flat,
            minimumSize: const Size(0, AppSizing.minimumTouchTarget),
            padding: const EdgeInsets.symmetric(
              horizontal: AppRhythm.title,
              vertical: AppRhythm.tight,
            ),
            icon: const Icon(Icons.add_rounded),
            child: Text(copy.homeCreateServer),
          ),
        ],
      ),
    );
  }
}

class _ServerLoadingCard extends StatelessWidget {
  const _ServerLoadingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Semantics(
      label: copy.text('Loading servers', 'Wczytywanie serwerów'),
      // A calm placeholder in the block's shape, without a tint (a tint is a
      // claim about a server that has not arrived). The indicator stays: it
      // is the one moving signal that the directory is still on its way.
      child: const YoCard(
        minHeight: 164,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
      ),
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({required this.server, required this.onTap, super.key});

  final Server server;
  final VoidCallback onTap;

  static const double _tile = 40;

  /// Where the row's text starts; the list's dividers are indented to it.
  static const double textInset = AppRhythm.item + _tile + AppRhythm.item;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return InkWell(
      onTap: onTap,
      child: Container(
        // Slim list row: 56 px floor, 40 px squircle, one line each for the
        // name and the type. It grows with the reader's text scale.
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(
          horizontal: AppRhythm.item,
          vertical: AppRhythm.tight,
        ),
        child: Row(
          children: [
            YoServerTile(
              initial: server.initial,
              type: server.type,
              size: _tile,
              textStyle: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: AppRhythm.item),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    server.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.titleMedium.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    server.isHeld
                        ? copy.text('Preparing', 'W przygotowaniu')
                        : copy.serverTypeTitle(server.type),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: palette.textTertiary),
          ],
        ),
      ),
    );
  }
}
