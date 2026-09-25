import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_motion.dart';
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
import 'package:yovoice/shared/widgets/interactions/yo_press_feedback.dart';
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
///
/// Refine-look W2: the section ARRIVES rather than jumping ~250 px in one
/// frame — its size grows over [AppMotion.entrance] and collapses over
/// [AppMotion.standard] (zero under Reduce Motion). No placeholder is ever
/// reserved: that would promise a live that may not exist. Each live
/// `(channel, startedAt)` ignites its card's light exactly once.
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

  /// Forgets which live sessions have already ignited (tests only).
  @visibleForTesting
  static void debugResetIgnitions() => _ignitedLiveSessions.clear();

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

/// The `(server, channel, startedAt)` sessions whose card has already
/// ignited. App-lifetime rather than per-State on purpose: Home's list can
/// dispose the section when it scrolls far away, and a retained tab can
/// rebuild it — neither may replay the ignite. A NEW `startedAt` is a new
/// key, so a channel that goes live again ignites again. Bounded: only the
/// most recent sessions are remembered (a `LinkedHashSet`, oldest first).
final Set<String> _ignitedLiveSessions = <String>{};
const int _ignitedMemory = 32;

class _HomeLiveNowSectionState extends State<HomeLiveNowSection> {
  /// True exactly once per live session: the first time it is shown.
  static bool _firstSight(HomeLiveChannel entry) {
    final key =
        '${entry.server.id}/${entry.channel.id}@'
        '${entry.channel.liveness.startedAt!.microsecondsSinceEpoch}';
    if (_ignitedLiveSessions.contains(key)) return false;
    _ignitedLiveSessions.add(key);
    if (_ignitedLiveSessions.length > _ignitedMemory) {
      _ignitedLiveSessions.remove(_ignitedLiveSessions.first);
    }
    return true;
  }

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
    final arriving = entries.isNotEmpty;
    final content = arriving
        ? _buildSection(context, entries)
        : const SizedBox(width: double.infinity);
    final duration = AppMotion.resolve(
      context,
      arriving ? AppMotion.entrance : AppMotion.standard,
    );
    // Reduce Motion: the section simply is (or is not) there. A zero-length
    // AnimatedSize would finish inside its own layout pass, which Flutter
    // rejects, so the size animation is left out altogether.
    if (duration == Duration.zero) return content;
    // The section's box eases to its content's height instead of jumping.
    // `RenderAnimatedSize` clips only while its content overflows the
    // animating box, so at rest the card's under-glow is never cut; during
    // the 320 ms arrival the incoming card is revealed rather than painted
    // over the sections it is pushing down.
    return AnimatedSize(
      duration: duration,
      curve: arriving ? AppMotion.entranceCurve : AppMotion.standardCurve,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.hardEdge,
      child: content,
    );
  }

  Widget _buildSection(BuildContext context, List<HomeLiveChannel> entries) {
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
                    ignite: _firstSight(entries[i]),
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
///
/// Refine-look R4 / W2 — LIVE is the one lit surface on Start:
///
/// * the base fill stays the identity wash over `surfaceRaised`, so Pearl
///   stays light; radius [AppRadius.block];
/// * a corner light in the identity ACCENT from the top-end corner
///   ([AppFinish.liveCorner], reach capped at 200 px), under the content;
/// * a 1 px live rim instead of the neutral border, and in Dark a specular
///   top hairline;
/// * an under-glow in the live red ([AppFinish.liveGlow]) that replaces the
///   block shadow (never both).
///
/// [ignite] is true the first time this `(channel, startedAt)` is shown: the
/// glow and the corner light fade in over [AppMotion.entrance] beside the
/// badge dot's own bounded pulse, then rest. No translate, scale or breathing
/// loop; rebuilds and returns never replay it. Under Reduce Motion (or a
/// paused ticker) the card renders at rest. Hover brightens the glow and the
/// rim; a touch press settles the card by .985 and sinks the glow 14 → 8.
/// High contrast: no glow, no corner light, a 1.5 px solid live rim.
///
/// The waveform is a still silhouette in the identity ink: it carries no
/// amplitude, so it never animates and never pretends to be live audio.
class HomeLiveChannelCard extends StatefulWidget {
  const HomeLiveChannelCard({
    required this.entry,
    required this.onOpen,
    this.ignite = false,
    super.key,
  });

  final HomeLiveChannel entry;
  final VoidCallback onOpen;

  /// Play the one-time light-up (first sight of this live session).
  final bool ignite;

  @override
  State<HomeLiveChannelCard> createState() => _HomeLiveChannelCardState();
}

class _HomeLiveChannelCardState extends State<HomeLiveChannelCard>
    with SingleTickerProviderStateMixin {
  AnimationController? _ignite;
  Animation<double> _light = kAlwaysCompleteAnimation;
  bool _igniteChecked = false;
  bool _hovered = false;
  bool _pressed = false;
  Duration _glowDuration = AppMotion.quick;
  Curve _glowCurve = AppMotion.standardCurve;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_igniteChecked) return;
    _igniteChecked = true;
    if (widget.ignite) _startIgnite();
  }

  @override
  void didUpdateWidget(covariant HomeLiveChannelCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The same channel went live again (a new `startedAt`): light up once
    // more. Any other rebuild leaves the card at rest.
    if (widget.ignite && !oldWidget.ignite) _startIgnite();
  }

  void _startIgnite() {
    if (!AppMotion.decorative(context)) {
      _light = kAlwaysCompleteAnimation;
      return;
    }
    final controller = _ignite ??= AnimationController(
      vsync: this,
      duration: AppMotion.entrance,
    );
    _light = CurvedAnimation(
      parent: controller,
      curve: AppMotion.entranceCurve,
    );
    controller.forward(from: 0);
  }

  @override
  void dispose() {
    _ignite?.dispose();
    super.dispose();
  }

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() {
      _hovered = value;
      _glowDuration = AppMotion.quick;
      _glowCurve = AppMotion.standardCurve;
    });
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() {
      _pressed = value;
      // Settles in over the press; lets go over the release, with its
      // small overshoot.
      _glowDuration = value ? AppMotion.press : AppMotion.release;
      _glowCurve = value ? AppMotion.standardCurve : AppMotion.releaseCurve;
    });
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    final server = widget.entry.server;
    final channel = widget.entry.channel;
    final identity = ServerIdentity.of(server.type);
    final visuals = identity.resolve(Theme.of(context).brightness);
    final clock = serverLiveClock(context, channel.liveness.startedAt!);
    final since = copy.serverLiveSince(clock);
    final specular = AppFinish.liveSpecular(
      palette,
      highContrast: highContrast,
    );
    final glowDuration = AppMotion.resolve(context, _glowDuration);

    final thumbnail = AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The under-glow: its own layer behind the tile, so the one-time
          // ignite fades only the light and never the tile itself.
          if (!highContrast)
            Positioned.fill(
              child: IgnorePointer(
                child: FadeTransition(
                  key: const ValueKey('home-live-glow'),
                  opacity: _light,
                  child: AnimatedContainer(
                    duration: glowDuration,
                    curve: _glowCurve,
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.block,
                      boxShadow: AppFinish.liveGlow(
                        palette,
                        hovered: _hovered,
                        pressed: _pressed,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: AnimatedContainer(
              duration: AppMotion.resolve(context, AppMotion.quick),
              curve: AppMotion.standardCurve,
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  visuals.cardWash,
                  palette.surfaceRaised,
                ),
                borderRadius: AppRadius.block,
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: AppRadius.block,
                border: AppFinish.liveRim(
                  palette,
                  hovered: _hovered,
                  highContrast: highContrast,
                ),
              ),
              child: ClipRRect(
                borderRadius: AppRadius.block,
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    children: [
                      if (!highContrast)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: FadeTransition(
                              key: const ValueKey('home-live-corner'),
                              opacity: _light,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: AppFinish.liveCorner(
                                    identity.accent,
                                    palette,
                                    shortestSide:
                                        constraints.biggest.shortestSide,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (specular != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          height: 1,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(gradient: specular),
                            ),
                          ),
                        ),
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
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      label: '${channel.name}, ${server.name}, $since',
      excludeSemantics: true,
      child: YoPressFeedback(
        scale: YoPressFeedback.block,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onOpen,
            onHover: _setHovered,
            onHighlightChanged: _setPressed,
            borderRadius: AppRadius.block,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                thumbnail,
                const SizedBox(height: AppRhythm.tight),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    YoServerTile(
                      initial: server.initial,
                      type: server.type,
                      size: 36,
                      textStyle: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
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
      ),
    );
  }
}
