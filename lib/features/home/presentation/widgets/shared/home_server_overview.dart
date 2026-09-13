import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_header.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_status.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/presentation/server_localized_copy.dart';
import 'package:yovoice/features/servers/presentation/theme/server_identity.dart';

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
    super.key,
  });

  final AsyncSnapshot<List<Server>> snapshot;
  final VoidCallback onOpenServers;
  final VoidCallback onRetry;
  final ValueChanged<Server>? onOpenServer;
  final bool expanded;

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
        for (final server in visibleServers) ...[
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
          if (server != visibleServers.last)
            const SizedBox(height: AppRhythm.tight),
        ],
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
    return Material(
      color: Color.alphaBlend(visuals.cardWash, palette.surface),
      borderRadius: AppRadius.lg,
      child: InkWell(
        onTap: () {
          final openServer = onOpenServer;
          if (openServer != null) {
            openServer(server);
          } else {
            onOpenServers();
          }
        },
        borderRadius: AppRadius.lg,
        child: Container(
          constraints: BoxConstraints(minHeight: expanded ? 216 : 164),
          padding: EdgeInsets.all(expanded ? AppSpacing.xl : AppRhythm.title),
          decoration: BoxDecoration(
            borderRadius: AppRadius.lg,
            border: Border.all(color: visuals.iconBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Container(
                    width: expanded ? 58 : 48,
                    height: expanded ? 58 : 48,
                    decoration: BoxDecoration(
                      color: visuals.iconSurface,
                      borderRadius: AppRadius.md,
                      border: Border.all(color: visuals.iconBorder),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      server.initial,
                      style: AppTypography.titleLarge.copyWith(
                        color: visuals.foreground,
                        fontWeight: FontWeight.w900,
                      ),
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
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          server.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              (expanded
                                      ? AppTypography.headlineMedium
                                      : AppTypography.titleLarge)
                                  .copyWith(
                                    color: palette.textPrimary,
                                    fontWeight: FontWeight.w800,
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
                    server.isHeld
                        ? Icons.schedule_rounded
                        : Icons.forum_outlined,
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
                  Icon(Icons.arrow_forward_rounded, color: visuals.foreground),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServerEmptyCard extends StatelessWidget {
  const _ServerEmptyCard({
    required this.onOpenServers,
    required this.expanded,
    super.key,
  });

  final VoidCallback onOpenServers;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Container(
      constraints: BoxConstraints(minHeight: expanded ? 216 : 164),
      padding: EdgeInsets.all(expanded ? AppSpacing.xl : AppRhythm.title),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.hub_outlined, color: palette.interactiveForeground),
          const SizedBox(height: AppRhythm.item),
          Text(
            copy.text(
              'A good conversation starts in your server.',
              'Dobra rozmowa zaczyna się na Twoim serwerze.',
            ),
            style: AppTypography.headlineMedium.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
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
          FilledButton.icon(
            key: const ValueKey('home-empty-create-server'),
            onPressed: onOpenServers,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, AppSizing.minimumTouchTarget),
            ),
            icon: const Icon(Icons.add_rounded),
            label: Text(copy.homeCreateServer),
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
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Semantics(
      label: copy.text('Loading servers', 'Wczytywanie serwerów'),
      child: Container(
        constraints: const BoxConstraints(minHeight: 164),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: AppRadius.lg,
          border: Border.all(color: palette.border),
        ),
        alignment: Alignment.center,
        child: const CircularProgressIndicator(strokeWidth: 2.4),
      ),
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({required this.server, required this.onTap, super.key});

  final Server server;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final visuals = ServerIdentity.of(
      server.type,
    ).resolve(Theme.of(context).brightness);
    return Material(
      color: palette.surface,
      borderRadius: AppRadius.md,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.md,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppSizing.minimumTouchTarget,
          ),
          padding: const EdgeInsets.all(AppRhythm.item),
          decoration: BoxDecoration(
            borderRadius: AppRadius.md,
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: visuals.iconSurface,
                  borderRadius: AppRadius.sm,
                  border: Border.all(color: visuals.iconBorder),
                ),
                alignment: Alignment.center,
                child: Text(
                  server.initial,
                  style: AppTypography.titleMedium.copyWith(
                    color: visuals.foreground,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: AppRhythm.item),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
      ),
    );
  }
}
