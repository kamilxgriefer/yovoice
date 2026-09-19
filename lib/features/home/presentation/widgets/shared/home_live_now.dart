import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/servers/presentation/server_localized_copy.dart';
import 'package:yovoice/features/servers/presentation/theme/server_identity.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_channel_scene.dart'
    show serverLiveClock;
import 'package:yovoice/features/servers/presentation/widgets/server_panel.dart'
    show serverChannelIcon;
import 'package:yovoice/shared/widgets/badges/yo_badge.dart';
import 'package:yovoice/shared/widgets/badges/yo_metric_pill.dart';
import 'package:yovoice/shared/widgets/layout/home_section_header.dart';
import 'package:yovoice/shared/widgets/navigation/yo_server_rail_item.dart'
    show YoServerTile;
import 'package:yovoice/shared/widgets/waveform/yo_waveform.dart';

/// One live media channel on one of the viewer's servers.
@immutable
class HomeLiveChannel {
  const HomeLiveChannel({required this.server, required this.channel});

  final Server server;
  final ServerChannel channel;
}

/// "Na żywo teraz" on Start (Slim phase 1): the viewer's own servers whose
/// voice, stage or meeting channel the channel document marks live.
///
/// Every fact on a card comes from the server-owned liveness projection
/// (ADR-177: `{isLive, startedAt}`) that the server workspace already reads
/// through [ServerRepository.watchChannels]. That projection deliberately has
/// no participant count, so the card's metric pill is the start clock
/// ("od 19:40"), never a listener number, and no avatars are drawn.
///
/// Bounded by construction like `HomeLoungeWatcher`: only the first [budget]
/// servers of the directory get a channel listener, the listeners are keyed
/// by server id so a rebuild never resubscribes, and a server whose channels
/// fail to read simply contributes no card. With nothing live the section
/// renders nothing at all, heading included: a section title is a promise
/// about content.
class HomeLiveNowSection extends StatefulWidget {
  const HomeLiveNowSection({
    required this.servers,
    required this.repository,
    required this.onOpenServer,
    this.horizontalPadding = 0,
    this.expanded = false,
    this.topSpacing = 0,
    super.key,
  });

  /// How many servers get a channel listener: the three Start previews
  /// plus the "Tu i teraz" server, which is always the first of them.
  static const int budget = 3;

  /// The phone card: 16:9 thumbnail at 280 × 158 (Slim brief).
  static const double cardWidth = 280;
  static const double expandedCardWidth = 320;

  final List<Server> servers;
  final ServerRepository? repository;
  final ValueChanged<Server> onOpenServer;

  /// Inset of the first and last card, so the rail can bleed to the screen
  /// edge while its content still starts on the page gutter.
  final double horizontalPadding;
  final bool expanded;

  /// Space drawn above the heading only when the section is present, so an
  /// absent section leaves no gap behind.
  final double topSpacing;

  @override
  State<HomeLiveNowSection> createState() => _HomeLiveNowSectionState();
}

class _HomeLiveNowSectionState extends State<HomeLiveNowSection> {
  final Map<String, StreamSubscription<List<ServerChannel>>> _subscriptions =
      {};
  final Map<String, List<ServerChannel>> _live = {};

  /// Servers whose repository refused to list channels. They are not asked
  /// again on every rebuild; a new repository clears the set.
  final Set<String> _refused = {};

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant HomeLiveNowSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _cancelAll();
      _refused.clear();
    }
    _sync();
  }

  List<Server> get _watched =>
      widget.servers.take(HomeLiveNowSection.budget).toList(growable: false);

  void _sync() {
    final repository = widget.repository;
    final wanted = {for (final server in _watched) server.id};
    for (final id in _subscriptions.keys.toList()) {
      if (!wanted.contains(id)) {
        unawaited(_subscriptions.remove(id)?.cancel());
        _live.remove(id);
      }
    }
    if (repository == null) return;
    for (final id in wanted) {
      if (_subscriptions.containsKey(id) || _refused.contains(id)) continue;
      Stream<List<ServerChannel>> stream;
      try {
        stream = repository.watchChannels(id);
      } catch (_) {
        // A repository that cannot list channels (a narrow test double, a
        // signed-out session) is a server with nothing live to show.
        _refused.add(id);
        continue;
      }
      _subscriptions[id] = stream.listen(
        (channels) {
          if (!mounted) return;
          final live = [
            for (final channel in channels)
              if (channel.kind.isMedia &&
                  channel.liveness.isLive &&
                  channel.liveness.startedAt != null)
                channel,
          ];
          setState(() => _live[id] = live);
        },
        onError: (Object _, StackTrace _) {
          if (!mounted) return;
          setState(() => _live.remove(id));
        },
      );
    }
  }

  void _cancelAll() {
    for (final subscription in _subscriptions.values) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _live.clear();
  }

  @override
  void dispose() {
    _cancelAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = <HomeLiveChannel>[
      for (final server in _watched)
        for (final channel in _live[server.id] ?? const <ServerChannel>[])
          HomeLiveChannel(server: server, channel: channel),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();
    // Newest first: the room that just went live is the one to catch.
    entries.sort(
      (a, b) => b.channel.liveness.startedAt!.compareTo(
        a.channel.liveness.startedAt!,
      ),
    );

    final copy = AppLocalizations.of(context);
    final cardWidth = widget.expanded
        ? HomeLiveNowSection.expandedCardWidth
        : HomeLiveNowSection.cardWidth;
    final padding = widget.horizontalPadding;
    return Column(
      key: const ValueKey('home-live-now'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.topSpacing > 0) SizedBox(height: widget.topSpacing),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: padding),
          child: HomeSectionHeader(
            title: copy.text('Live now', 'Teraz na żywo'),
            live: true,
            scale: widget.expanded
                ? HomeSectionHeaderScale.expanded
                : HomeSectionHeaderScale.compact,
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: padding),
          clipBehavior: Clip.none,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) const SizedBox(width: AppRhythm.item),
                SizedBox(
                  width: cardWidth,
                  child: HomeLiveChannelCard(
                    key: ValueKey(
                      'home-live-${entries[i].server.id}-'
                      '${entries[i].channel.id}',
                    ),
                    entry: entries[i],
                    onOpen: () => widget.onOpenServer(entries[i].server),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A 16:9 live card: an audio-first thumbnail in the server's identity with
/// the NA ŻYWO badge and the start-clock pill on it, then the server squircle,
/// the channel name and "server · kind" under it.
class HomeLiveChannelCard extends StatelessWidget {
  const HomeLiveChannelCard({
    required this.entry,
    required this.onOpen,
    super.key,
  });

  final HomeLiveChannel entry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final server = entry.server;
    final channel = entry.channel;
    final visuals = ServerIdentity.of(
      server.type,
    ).resolve(Theme.of(context).brightness);
    final clock = serverLiveClock(context, channel.liveness.startedAt!);
    final since = copy.serverLiveSince(clock);

    return Semantics(
      button: true,
      label: '${channel.name}, ${server.name}, $since',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onOpen,
          borderRadius: AppRadius.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      visuals.cardWash,
                      palette.surfaceRaised,
                    ),
                    borderRadius: AppRadius.card,
                    border: Border.all(color: palette.border),
                  ),
                  child: Stack(
                    children: [
                      // The audio visual: a still waveform in the server's
                      // identity ink. It carries no amplitude, so it never
                      // animates and never pretends to be live audio.
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                serverChannelIcon(channel.kind),
                                size: 24,
                                color: visuals.foreground,
                              ),
                              const SizedBox(width: AppRhythm.item),
                              Flexible(
                                child: YoWaveform(
                                  color: visuals.foreground.withValues(
                                    alpha: .72,
                                  ),
                                  height: 36,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: AppRhythm.tight,
                        top: AppRhythm.tight,
                        child: YoBadge(
                          label: copy.serverLivePill,
                          variant: YoBadgeVariant.live,
                        ),
                      ),
                      Positioned(
                        right: AppRhythm.tight,
                        bottom: AppRhythm.tight,
                        child: YoMetricPill(
                          value: copy.serverLiveSinceShort(clock),
                          icon: Icons.schedule_rounded,
                          tone: YoMetricPillTone.overlay,
                          semanticLabel: since,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppRhythm.tight),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  YoServerTile(
                    initial: server.initial,
                    type: server.type,
                    size: 36,
                    textStyle: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: AppRhythm.tight),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.titleSmall.copyWith(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${server.name} · '
                          '${copy.serverChannelKindTitle(channel.kind)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
