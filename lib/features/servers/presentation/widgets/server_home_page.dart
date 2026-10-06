import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/badges/yo_metric_pill.dart';
import 'package:yovoice/shared/widgets/layout/home_section_header.dart';
import 'package:yovoice/shared/widgets/navigation/yo_server_rail_item.dart';
import 'package:yovoice/shared/widgets/rows/yo_channel_row.dart';

import '../../data/models/server.dart';
import '../../data/models/server_channel.dart';
import '../../data/models/server_event.dart';
import '../../data/models/server_invite_authority.dart';
import '../../data/models/server_member_role.dart';
import '../../data/models/server_type.dart';
import '../../data/services/server_service.dart';
import '../../data/services/server_session_controller.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';
import '../server_page_copy.dart';
import '../theme/server_identity.dart';
import 'server_channel_scene.dart';
import 'server_panel.dart';
import 'server_voice_stage.dart';
import 'server_waiting_dot.dart';

/// `Strona serwera` (ADR-240): what a server opens on, at every width.
///
/// One scrolling page instead of a tab strip that was different in every
/// template: the cover, the identity tile, the name, one meta line and the
/// description; the actions this person really has; the template's main
/// thing; then the conversations, the other voice channels and the next
/// events, with the whole channel list behind one row at the end.
///
/// Everything on it is read from documents this client may already read:
///
/// * **the cover is the template's own gradient and the tile is the initial**
///   — a server has no artwork writer (contract G7), so there is no photo to
///   show and none is implied;
/// * **the main thing** is the server's live or joinable media channel (the
///   friends' lounge, the community's stage, the podcast's studio, the
///   company's meeting) or, for a family, the `Dom` board the host passes as
///   [board]. A stage that is not live shows the next real event of the
///   server instead (`Następny LIVE`, `Następny odcinek`), or says that the
///   stage is quiet;
/// * **liveness is the channel document's projection** (ADR-177): a pill and
///   "since HH:MM". There is no viewer, listener or participant count
///   anywhere, no host name and no session title, because none of them has a
///   readable source before joining;
/// * **conversation rows carry a glyph and a name only** — server channels
///   have no read cursor (ADR-209). The one mark is the waiting dot on a
///   podcast host's Questions channel, which has a real cursor behind it.
///
/// The page owns no navigation of its own: opening a channel, the channel
/// list, the invitation and sharing are the host's callbacks, so the phone
/// route and the tablet and desktop centre share one page.
class ServerHomePage extends StatefulWidget {
  const ServerHomePage({
    required this.server,
    required this.channels,
    required this.session,
    required this.repository,
    required this.onOpenChannel,
    required this.onOpenAllChannels,
    this.role,
    this.onInvite,
    this.onShare,
    this.onBack,
    this.onMore,
    this.embedded = false,
    this.intro,
    this.board,
    this.questionsWaitingChannelId,
    this.now,
    super.key,
  });

  final Server server;

  /// The channels this person may see, in the server's own order.
  final List<ServerChannel> channels;
  final ServerSessionController session;

  /// Read for one thing: the events of the server's events or calendar
  /// channel, when the repository carries the Events contract.
  final ServerRepository repository;
  final ServerMemberRole? role;

  /// Opens a channel in the host's own channel view.
  final ValueChanged<ServerChannel> onOpenChannel;

  /// Opens the whole channel list (today's server panel).
  final VoidCallback onOpenAllChannels;

  /// Null disables `Zaproś` (a held server); the control is not drawn at all
  /// for a role that may not invite.
  final VoidCallback? onInvite;

  /// Null hides `Udostępnij`: only a server anyone may join has a link that
  /// leads somewhere for the person who receives it.
  final VoidCallback? onShare;

  /// Phone only: the glass discs on the cover. Both null on a tablet and a
  /// desktop, where the channel column owns the way back and the settings.
  final VoidCallback? onBack;
  final VoidCallback? onMore;

  /// The page is the centre scene of a wider layout: no cover controls and
  /// no status-bar inset of its own.
  final bool embedded;

  /// The "your server is waiting for people" card right after creation.
  final Widget? intro;

  /// The template's own board in place of the media hero (the family's
  /// `Dom`). The host builds it because it owns the board's repositories.
  final Widget? board;

  /// The Questions channel whose listener questions this host has not seen.
  final String? questionsWaitingChannelId;

  /// A test seam for "today / tomorrow" and for which events are upcoming.
  final DateTime Function()? now;

  /// The page keeps a reading measure in a wide centre column.
  static const maxWidth = 720.0;

  /// The cover's height under the status-bar inset.
  static const coverHeight = 120.0;

  /// How many rows a section shows before the full list is the better place.
  static const maxConversationRows = 5;
  static const maxVoiceRows = 4;
  static const maxEventRows = 2;

  /// The channel a template leads with, or null when it has none.
  ///
  /// Friends and families gather in the lounge, a community and a podcast
  /// broadcast from a stage, a company meets. A template whose own channel is
  /// missing falls back to the first channel anybody can talk in.
  static ServerChannel? mainChannel(
    Server server,
    List<ServerChannel> channels,
  ) {
    ServerChannel? first(ServerChannelKind kind) =>
        channels.where((channel) => channel.kind == kind).firstOrNull;
    final lounge =
        channels
            .where(
              (channel) =>
                  channel.kind == ServerChannelKind.voice &&
                  channel.id == server.defaultVoiceChannelId,
            )
            .firstOrNull ??
        first(ServerChannelKind.voice);
    final preferred = switch (server.type) {
      ServerType.friends || ServerType.family => lounge,
      ServerType.community ||
      ServerType.podcast => first(ServerChannelKind.stage),
      ServerType.company => first(ServerChannelKind.meeting),
    };
    return preferred ??
        lounge ??
        channels.where((channel) => channel.kind.isMedia).firstOrNull;
  }

  /// The channel whose events the page lists: the family's calendar, the
  /// other templates' events. A company has no Events contract.
  static ServerChannel? eventsChannel(
    Server server,
    List<ServerChannel> channels,
  ) {
    final kind = switch (server.type) {
      ServerType.family => ServerChannelKind.calendar,
      ServerType.company => null,
      _ => ServerChannelKind.events,
    };
    if (kind == null) return null;
    return channels.where((channel) => channel.kind == kind).firstOrNull;
  }

  @override
  State<ServerHomePage> createState() => _ServerHomePageState();
}

class _ServerHomePageState extends State<ServerHomePage> {
  Stream<List<ServerEvent>>? _events;
  String? _eventsKey;

  DateTime get _now => (widget.now?.call() ?? DateTime.now()).toUtc();

  ServerChannel? get _eventsChannel => widget.server.isHeld
      ? null
      : ServerHomePage.eventsChannel(widget.server, widget.channels);

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant ServerHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _listen();
  }

  /// One subscription per events channel, kept across rebuilds: the page is
  /// rebuilt whenever a session ticks, and a stream opened in `build` would
  /// reopen the read every time.
  void _listen() {
    final repository = widget.repository;
    final channel = _eventsChannel;
    final key = channel == null || repository is! ServerEventsRepository
        ? null
        : '${widget.server.id}/${channel.id}';
    if (key == _eventsKey) return;
    _eventsKey = key;
    _events = key == null
        ? null
        : (repository as ServerEventsRepository).watchEvents(
            widget.server.id,
            channel!.id,
          );
  }

  /// Joins a media channel through the host's session. A lounge is joined in
  /// place, exactly as the family board does; a stage or a meeting is a
  /// scene with its own controls, so the join opens it as well.
  void _join(ServerChannel channel) {
    if (channel.kind != ServerChannelKind.voice) widget.onOpenChannel(channel);
    widget.session.join(widget.server, channel);
  }

  @override
  Widget build(BuildContext context) {
    final events = _events;
    if (events == null) return _page(context, null);
    return StreamBuilder<List<ServerEvent>>(
      stream: events,
      builder: (context, snapshot) {
        // An unreadable events channel leaves the page without its events
        // rather than without everything else.
        if (!snapshot.hasData) return _page(context, null);
        final now = _now;
        final upcoming =
            snapshot.data!
                .where(
                  (event) =>
                      event.status == ServerEventStatus.scheduled &&
                      event.endsAt.isAfter(now),
                )
                .toList(growable: false)
              ..sort((first, second) {
                final starts = first.startsAt.compareTo(second.startsAt);
                return starts != 0 ? starts : first.id.compareTo(second.id);
              });
        return _page(context, upcoming);
      },
    );
  }

  Widget _page(BuildContext context, List<ServerEvent>? upcoming) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final server = widget.server;
    final inset = widget.embedded ? 0.0 : MediaQuery.paddingOf(context).top;
    final board = widget.board;
    final main = board != null
        ? ServerHomePage.mainChannel(server, widget.channels)
        : null;
    final hero = board == null
        ? ServerHomePage.mainChannel(server, widget.channels)
        : null;
    final eventsChannel = _eventsChannel;

    final conversations = _conversations();
    final waiting = widget.questionsWaitingChannelId;
    final waitingShown =
        waiting != null &&
        conversations.any((channel) => channel.id == waiting);

    return ColoredBox(
      color: palette.background,
      child: ListView(
        key: const ValueKey('server-page'),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _ServerPageHeader(
            server: server,
            inset: inset,
            onBack: widget.embedded ? null : widget.onBack,
            onMore: widget.embedded ? null : widget.onMore,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ServerPageIdentity(server: server),
                // `Nadaj LIVE` leaves the row once this device is in the
                // stage, so the row follows the session on its own.
                AnimatedBuilder(
                  animation: widget.session,
                  builder: (context, _) => _ServerPageActions(
                    server: server,
                    role: widget.role,
                    onInvite: widget.onInvite,
                    onShare: widget.onShare,
                    onGoLive: _goLiveAction(hero),
                    // A camera on the video stage; the podcast's studio is
                    // heard, not watched, so it keeps the stage's own glyph.
                    goLiveIcon: hero?.mediaMode == ServerMediaMode.video
                        ? Icons.videocam_rounded
                        : serverChannelIcon(ServerChannelKind.stage),
                  ),
                ),
                if (widget.intro != null) ...[
                  const SizedBox(height: 16),
                  widget.intro!,
                ],
                if (board != null) ...[const SizedBox(height: 20), board],
                if (hero != null) ...[
                  const SizedBox(height: 20),
                  _hero(context, hero, eventsChannel, upcoming),
                ],
                if (widget.channels.isEmpty) ...[
                  const SizedBox(height: 24),
                  // A server whose channels this person cannot see, or that
                  // has none yet: said plainly, above the way to the list
                  // (where a role that may add one finds `Dodaj kanał`).
                  Text(
                    copy.serverNoChannels,
                    key: const ValueKey('server-page-empty'),
                    style: AppTypography.titleMedium.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    copy.serverNoChannelsBody,
                    style: AppTypography.bodyMedium.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
                if (conversations.isNotEmpty) ...[
                  HomeSectionHeader(
                    title:
                        server.type == ServerType.friends ||
                            server.type == ServerType.family
                        ? copy.serverChat
                        : copy.serverPageConversations,
                  ),
                  _ServerPageBlock(
                    child: _dividedRows(context, [
                      for (final channel in conversations)
                        _ConversationRow(
                          channel: channel,
                          waiting: channel.id == waiting,
                          onTap: () => widget.onOpenChannel(channel),
                        ),
                    ]),
                  ),
                ],
                // The section follows the session: which card the hero is
                // decides whether the stage needs a row of its own here.
                AnimatedBuilder(
                  animation: widget.session,
                  builder: (context, _) {
                    final voices = _voices(
                      hero: hero,
                      boardLounge: main,
                      eventsChannel: eventsChannel,
                      upcoming: upcoming,
                    );
                    if (voices.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HomeSectionHeader(title: copy.serverPageVoice),
                        _ServerPageBlock(
                          child: _dividedRows(context, [
                            for (final channel in voices)
                              _VoiceRow(
                                server: server,
                                channel: channel,
                                role: widget.role,
                                session: widget.session,
                                onOpen: () => widget.onOpenChannel(channel),
                                onJoin: () => _join(channel),
                              ),
                          ]),
                        ),
                      ],
                    );
                  },
                ),
                if (eventsChannel != null && upcoming != null) ...[
                  HomeSectionHeader(
                    title: copy.serverChannelKindTitle(eventsChannel.kind),
                  ),
                  _ServerPageBlock(
                    child: _ServerPageEvents(
                      events: upcoming
                          .take(ServerHomePage.maxEventRows)
                          .toList(growable: false),
                      onOpen: () => widget.onOpenChannel(eventsChannel),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _ServerPageBlock(
                  child: YoChannelRow(
                    tileKey: const ValueKey('server-open-channels'),
                    label: copy.serverPageAllChannels(widget.channels.length),
                    labelMaxLines: 2,
                    icon: Icons.format_list_bulleted_rounded,
                    iconColor: palette.textSecondary,
                    minHeight: _rowHeight,
                    onTap: widget.onOpenAllChannels,
                    trailing: _RowTrailing(
                      // A waiting Questions row that is not among the rows
                      // above waits inside the list, and its way in says so.
                      waitingLabel: waiting != null && !waitingShown
                          ? copy.serverQuestionsWaitingLabel
                          : null,
                      waitingKey: const ValueKey(
                        'server-open-channels-waiting',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The threads people talk in: the server's default channel first, then
  /// text, questions and announcements in the server's own order. `Zasady`
  /// and every module stay in the full list.
  List<ServerChannel> _conversations() {
    int rank(ServerChannel channel) => switch (channel.kind) {
      _ when channel.id == widget.server.defaultChannelId => 0,
      ServerChannelKind.text => 1,
      ServerChannelKind.questions => 2,
      _ => 3,
    };
    final threads = [
      for (final channel in widget.channels)
        if (channel.kind == ServerChannelKind.text ||
            channel.kind == ServerChannelKind.questions ||
            channel.kind == ServerChannelKind.announcements)
          channel,
    ];
    // A stable sort: channels of one rank keep the order they arrived in.
    final indexed = [
      for (var index = 0; index < threads.length; index++)
        (index, threads[index]),
    ];
    indexed.sort((first, second) {
      final ranks = rank(first.$2).compareTo(rank(second.$2));
      return ranks != 0 ? ranks : first.$1.compareTo(second.$1);
    });
    return [
      for (final entry in indexed.take(ServerHomePage.maxConversationRows))
        entry.$2,
    ];
  }

  /// The media channels listed under `Głos`.
  ///
  /// The channel the hero card stands for is not repeated as a row, and
  /// neither is the lounge the family's board already carries. A quiet stage
  /// whose place in the hero is taken by the next event is NOT on the page
  /// otherwise, so then it gets its row: the stage (with its `Obserwuj`, its
  /// share and its own start) stays one tap away for everybody.
  List<ServerChannel> _voices({
    required ServerChannel? hero,
    required ServerChannel? boardLounge,
    required ServerChannel? eventsChannel,
    required List<ServerEvent>? upcoming,
  }) {
    final skip = hero == null
        ? boardLounge?.id
        : _heroShowsNextEvent(hero, eventsChannel, upcoming)
        ? null
        : hero.id;
    return widget.channels
        .where((channel) => channel.kind.isMedia && channel.id != skip)
        .take(ServerHomePage.maxVoiceRows)
        .toList(growable: false);
  }

  /// A quiet stage this device is not in gives the hero to the server's next
  /// real event, when there is one.
  bool _heroShowsNextEvent(
    ServerChannel hero,
    ServerChannel? eventsChannel,
    List<ServerEvent>? upcoming,
  ) =>
      hero.kind == ServerChannelKind.stage &&
      !hero.liveness.isLive &&
      !widget.session.isIn(hero.id) &&
      !widget.server.isHeld &&
      eventsChannel != null &&
      (upcoming?.isNotEmpty ?? false);

  /// `Nadaj LIVE` is offered to a role that may start the stage, while the
  /// stage is quiet and this device is not already in it. It opens the stage;
  /// the stage's own action starts the broadcast.
  VoidCallback? _goLiveAction(ServerChannel? hero) {
    if (hero == null ||
        hero.kind != ServerChannelKind.stage ||
        widget.server.isHeld ||
        hero.liveness.isLive ||
        hero.access == ServerChannelAccess.restricted ||
        !(widget.role?.canModerate ?? false) ||
        widget.session.isIn(hero.id)) {
      return null;
    }
    return () => widget.onOpenChannel(hero);
  }

  Widget _hero(
    BuildContext context,
    ServerChannel channel,
    ServerChannel? eventsChannel,
    List<ServerEvent>? upcoming,
  ) => AnimatedBuilder(
    animation: widget.session,
    builder: (context, _) {
      final server = widget.server;
      final here = widget.session.isIn(channel.id);
      final live = channel.liveness.isLive;
      final stage = channel.kind == ServerChannelKind.stage;
      if (stage && live && !here && !server.isHeld) {
        return _LiveStageHero(
          server: server,
          channel: channel,
          role: widget.role,
          onJoin: () => _join(channel),
        );
      }
      if (_heroShowsNextEvent(channel, eventsChannel, upcoming)) {
        return _NextEventHero(
          server: server,
          stage: channel,
          event: upcoming!.first,
          now: _now,
          repository: widget.repository,
          onOpen: () => widget.onOpenChannel(eventsChannel!),
        );
      }
      return _SessionHero(
        server: server,
        channel: channel,
        role: widget.role,
        session: widget.session,
        onJoin: () => _join(channel),
        onOpen: () => widget.onOpenChannel(channel),
      );
    },
  );
}

/// The page of a public server seen by somebody who has not joined it yet
/// (ADR-240): the same cover, name and meta line a member sees, and `Dołącz`
/// as the one action.
///
/// It deliberately carries no channel-derived information — no hero, no
/// section, no channel count: channel names and conversations become readable
/// only after `joinServerV1` commits the member row, so the body says what
/// joining opens instead of showing it.
class ServerPageAdmission extends StatelessWidget {
  const ServerPageAdmission({
    required this.server,
    required this.joining,
    required this.onJoin,
    this.error,
    this.onBack,
    this.embedded = false,
    super.key,
  });

  final Server server;
  final bool joining;
  final Object? error;
  final VoidCallback onJoin;

  /// Phone only: the glass Back on the cover. Null where the host already
  /// draws a way out above the page.
  final VoidCallback? onBack;

  /// Under a host's own bar: no status-bar inset of the page's own.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final colors = ServerIdentity.of(
      server.type,
    ).resolve(Theme.of(context).brightness);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;
    return ColoredBox(
      color: palette.background,
      child: ListView(
        key: const ValueKey('server-public-admission'),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _ServerPageHeader(
            server: server,
            inset: embedded ? 0 : MediaQuery.paddingOf(context).top,
            onBack: embedded ? null : onBack,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ServerPageIdentity(server: server),
                const SizedBox(height: 14),
                // The admission's one action: the server join, in the
                // template's identity gradient (R5).
                ServerGradientFilledButton(
                  buttonKey: const ValueKey('server-public-join'),
                  onPressed: joining ? null : onJoin,
                  gradient: colors.ctaGradient,
                  fill: colors.cta,
                  foreground: colors.onCta,
                  minimumSize: Size.fromHeight(largeText ? 56 : 48),
                  icon: joining
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login_rounded, size: 18),
                  label: Text(
                    joining
                        ? copy.serverPublicJoining
                        : copy.serverPublicJoinAction,
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    serverActionFailureCopy(
                      error!,
                      copy,
                      fallback: copy.serverJoinFailed,
                    ),
                    key: const ValueKey('server-public-join-error'),
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                _ServerPageBlock(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          copy.serverPublicJoinTitle,
                          style: AppTypography.titleMedium.copyWith(
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          copy.serverPublicJoinBody,
                          style: AppTypography.bodyMedium.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _rowHeight = 56.0;

Widget _dividedRows(
  BuildContext context,
  List<Widget> rows, {
  double indent = 48,
}) => Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    for (var index = 0; index < rows.length; index++) ...[
      if (index > 0)
        Divider(
          height: 1,
          thickness: 1,
          indent: indent,
          color: serverDivider(context),
        ),
      rows[index],
    ],
  ],
);

/// A content block (R2): the top-lit fill and the hairline edge, with the
/// rows' ink clipped to its corners.
class _ServerPageBlock extends StatelessWidget {
  const _ServerPageBlock({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    return Container(
      decoration: AppFinish.blockFill(palette, highContrast: highContrast),
      foregroundDecoration: BoxDecoration(
        borderRadius: AppRadius.block,
        border: AppFinish.blockEdge(palette, highContrast: highContrast),
      ),
      child: ClipRRect(
        borderRadius: AppRadius.block,
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }
}

/// The cover and the identity tile over its lower edge.
///
/// The cover is the template's own hue over the canvas, softened from the top
/// the way a profile banner is, so the glass discs read on it. It is a
/// gradient and never a photo: a server has no artwork writer (contract G7).
class _ServerPageHeader extends StatelessWidget {
  const _ServerPageHeader({
    required this.server,
    required this.inset,
    this.onBack,
    this.onMore,
  });
  final Server server;
  final double inset;
  final VoidCallback? onBack;
  final VoidCallback? onMore;

  static const _tile = 64.0;
  static const _ring = 3.0;
  static const _overlap = 24.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final identity = ServerIdentity.of(server.type);
    final cover = inset + ServerHomePage.coverHeight;
    return SizedBox(
      // The ringed tile hangs [_overlap] over the cover's lower edge; the
      // header ends 4 px under it.
      height: cover + _tile + _ring - _overlap + 1,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: cover,
            child: ExcludeSemantics(
              child: DecoratedBox(
                key: const ValueKey('server-page-cover'),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                    colors: [
                      Color.lerp(palette.background, identity.primary, .58)!,
                      Color.lerp(palette.background, identity.primary, .24)!,
                      Color.lerp(palette.background, identity.primary, .06)!,
                    ],
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      // Pearl's discs are smoked, so its cover needs only
                      // a breath of the softening and stays a clean tint.
                      colors: [
                        Colors.black.withValues(
                          alpha: palette.isDark ? .35 : .12,
                        ),
                        Colors.black.withValues(alpha: 0),
                      ],
                      stops: const [0, .56],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (onBack != null)
            PositionedDirectional(
              top: inset + 8 - ServerPageCoverButton.overhang,
              start: 12 - ServerPageCoverButton.overhang,
              child: ServerPageCoverButton(
                key: const ValueKey('server-page-back'),
                icon: Icons.arrow_back_rounded,
                tooltip: copy.serversTitle,
                onPressed: onBack!,
              ),
            ),
          if (onMore != null)
            PositionedDirectional(
              top: inset + 8 - ServerPageCoverButton.overhang,
              end: 12 - ServerPageCoverButton.overhang,
              child: ServerPageCoverButton(
                key: const ValueKey('server-page-more'),
                icon: Icons.more_horiz_rounded,
                tooltip: copy.more,
                onPressed: onMore!,
              ),
            ),
          PositionedDirectional(
            start: 16 - _ring,
            top: cover - _overlap - _ring,
            child: Container(
              padding: const EdgeInsets.all(_ring),
              decoration: BoxDecoration(
                color: palette.background,
                borderRadius: const BorderRadius.all(Radius.circular(17)),
              ),
              child: YoServerTile(
                initial: server.initial,
                type: server.type,
                size: _tile,
                textStyle: AppTypography.headlineMedium.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A 44 px glass disc on the cover (Back, `⋯`), the same object as a Page's
/// cover controls: a white glyph on glass. The disc is drawn at 44 inside a
/// 48 px target ([target]), the Servers surface's minimum for a touch.
///
/// On the Dark cover the glass is white at .22. Pearl's cover fades into a
/// light canvas, where a white glyph on white glass would not be seen, so the
/// disc is smoked there (black at .42, which keeps the glyph above 3:1 at the
/// cover's lightest corner). High contrast: black at .78 with a white edge.
class ServerPageCoverButton extends StatelessWidget {
  const ServerPageCoverButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// The touch target. The visible disc is [disc] wide, centred in it.
  static const target = 48.0;
  static const disc = 44.0;

  /// How far the target reaches beyond the disc on each side: a host that
  /// places the DISC a given distance from an edge insets the control by
  /// that distance less this.
  static const overhang = (target - disc) / 2;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        onTap: onPressed,
        // The ring between the disc and the target answers the same tap; on
        // the disc itself the ink well does, with its ripple.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox.square(
            dimension: target,
            child: Center(
              child: Material(
                color: highContrast
                    ? Colors.black.withValues(alpha: .78)
                    : palette.isDark
                    ? Colors.white.withValues(alpha: .22)
                    : Colors.black.withValues(alpha: .42),
                shape: CircleBorder(
                  side: BorderSide(
                    color: highContrast
                        ? AppColors.white
                        : Colors.white.withValues(alpha: .28),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onPressed,
                  child: SizedBox.square(
                    dimension: disc,
                    child: Icon(icon, color: AppColors.white, size: 22),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The name, one meta line and the description.
class _ServerPageIdentity extends StatelessWidget {
  const _ServerPageIdentity({required this.server});
  final Server server;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
    final description = server.description.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            server.name.isEmpty ? copy.serversTitle : server.name,
            key: const ValueKey('server-page-name'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.headlineMedium.copyWith(
              color: palette.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // An invite-only server says so with the lock the channel column
            // already uses, in front of the line that names the boundary.
            if (server.privacy == ServerPrivacy.inviteOnly)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 5, top: 1),
                child: Icon(
                  Icons.lock_outline,
                  key: const ValueKey('server-page-lock'),
                  size: 15,
                  color: palette.textSecondary,
                  semanticLabel: copy.serverPrivacyTitle(server.privacy),
                ),
              ),
            Flexible(
              child: Text(
                serverPageMeta(copy, server),
                key: const ValueKey('server-page-meta'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.rowPreview.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ),
          ],
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            description,
            key: const ValueKey('server-page-description'),
            maxLines: largeText ? 4 : 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMedium.copyWith(
              color: palette.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// "Społeczność · publiczny · 128 osób": what the server is, that anyone may
/// join it when that is true, and how many people belong to it. The line only
/// breaks after a separator and never between a number and its noun.
String serverPageMeta(AppLocalizations copy, Server server) {
  final parts = <String>[
    copy.serverKindSubtitle(server.type, server.privacy),
    if (serverAdmitsPublicJoin(server)) copy.serverPagePublic,
    serverKeepCountTogether(copy.peopleCount(server.memberCount)),
  ];
  return parts.join(' · ');
}

/// The action row (44 px controls): the stage's way in for a role that may
/// start it, `Zaproś` for a role that may invite, `Udostępnij` for a server
/// with a link worth sending. At 200 % text, or in a column too narrow for
/// the row, the same controls stack at full width.
class _ServerPageActions extends StatelessWidget {
  const _ServerPageActions({
    required this.server,
    required this.role,
    this.onInvite,
    this.onShare,
    this.onGoLive,
    this.goLiveIcon = Icons.videocam_rounded,
  });
  final Server server;
  final ServerMemberRole? role;
  final VoidCallback? onInvite;
  final VoidCallback? onShare;
  final VoidCallback? onGoLive;
  final IconData goLiveIcon;

  static const _height = 44.0;

  /// The controls' height once the text is large enough to stack them: a
  /// 28 px label needs more than the 44 px row gives it.
  static const _largeTextHeight = 56.0;

  /// Slack kept between what the labels measure and the row, so a label is
  /// never a pixel from its button's edge.
  static const _fitMargin = 10.0;

  /// The width of a button label at the caller's text size (the buttons'
  /// own style: `labelLarge` at w600).
  static double _labelWidth(BuildContext context, String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
      ),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;
    final height = largeText ? _largeTextHeight : _height;
    final canInvite = canInviteToServer(server, role);
    final goLive = onGoLive;
    final share = onShare;
    if (!canInvite && share == null && goLive == null) {
      return const SizedBox.shrink();
    }
    final tonal = AppFinish.tonalNeutral(palette, highContrast: highContrast)
        .merge(
          OutlinedButton.styleFrom(
            minimumSize: Size(48, height),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        );
    Widget label(String text) =>
        Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.fade);

    final Widget? live = goLive == null
        ? null
        : ServerGradientFilledButton(
            buttonKey: const ValueKey('server-page-go-live'),
            onPressed: goLive,
            gradient: AppGradients.primaryAction(scheme),
            fill: scheme.primary,
            foreground: scheme.onPrimary,
            liftColor: AppColors.primary,
            minimumSize: Size(48, height),
            icon: Icon(goLiveIcon, size: 18),
            label: label(copy.serverPageGoLive),
          );
    final Widget? invite = !canInvite
        ? null
        : OutlinedButton.icon(
            key: const ValueKey('server-page-invite'),
            // `createServerInviteV1` refuses a held root, so the control is
            // there and disabled rather than appearing to send something.
            onPressed: server.isHeld ? null : onInvite,
            style: tonal,
            icon: const Icon(Icons.person_add_outlined, size: 18),
            label: label(copy.serverInvite),
          );
    final Widget? shareLabelled = share == null
        ? null
        : OutlinedButton.icon(
            key: const ValueKey('server-page-share'),
            onPressed: share,
            style: tonal,
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            label: label(copy.serverShare),
          );

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The row is kept only while every label fits it whole: a longer
          // language (or a narrower column) stacks the same controls at full
          // width instead of cutting a word.
          double labelled(String text, {double chrome = 58}) =>
              _labelWidth(context, text) + chrome;
          final double needed;
          if (live != null) {
            // The primary carries 24 px of padding at its end.
            needed =
                labelled(copy.serverPageGoLive, chrome: 66) +
                (invite == null ? 0 : 8 + labelled(copy.serverInvite)) +
                (share == null ? 0 : 8 + _height);
          } else if (invite != null && shareLabelled != null) {
            final widest = [
              labelled(copy.serverInvite),
              labelled(copy.serverShare),
            ].reduce((a, b) => a > b ? a : b);
            needed = widest * 2 + 8;
          } else {
            needed = 0;
          }
          final stacked =
              largeText ||
              constraints.maxWidth < 296 ||
              needed + _fitMargin > constraints.maxWidth;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, action) in [
                  ?live,
                  ?invite,
                  ?shareLabelled,
                ].indexed) ...[
                  if (index > 0) const SizedBox(height: 8),
                  action,
                ],
              ],
            );
          }
          // With the stage's primary in the row, sharing steps back to its
          // glyph so the primary keeps the width its label needs.
          if (live != null) {
            return Row(
              children: [
                Expanded(child: live),
                if (invite != null) ...[const SizedBox(width: 8), invite],
                if (share != null) ...[
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    key: const ValueKey('server-page-share'),
                    onPressed: share,
                    tooltip: copy.serverShare,
                    style:
                        AppFinish.tonalNeutral(
                          palette,
                          highContrast: highContrast,
                        ).merge(
                          IconButton.styleFrom(
                            minimumSize: const Size(_height, _height),
                            fixedSize: const Size(_height, _height),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                    icon: const Icon(Icons.ios_share_rounded, size: 20),
                  ),
                ],
              ],
            );
          }
          return Row(
            children: [
              if (invite != null) Expanded(child: invite),
              if (invite != null && shareLabelled != null)
                const SizedBox(width: 8),
              if (shareLabelled != null) Expanded(child: shareLabelled),
            ],
          );
        },
      ),
    );
  }
}

/// A live video stage this device has not joined: the 16:9 picture frame
/// with the live marker and the clock, the channel's name and `Oglądaj`.
///
/// Video arrives with the token, so the frame says that instead of drawing a
/// picture nobody sent; the name is the channel's own because a live
/// generation carries no title, and no host is named because nobody is
/// readable before joining (contract G2/G3).
class _LiveStageHero extends StatelessWidget {
  const _LiveStageHero({
    required this.server,
    required this.channel,
    required this.role,
    required this.onJoin,
  });
  final Server server;
  final ServerChannel channel;
  final ServerMemberRole? role;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final colors = ServerIdentity.of(
      server.type,
    ).resolve(Theme.of(context).brightness);
    final video = channel.mediaMode == ServerMediaMode.video;
    final started = channel.liveness.startedAt;
    return Column(
      key: const ValueKey('server-page-live-hero'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (!highContrast)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: AppRadius.block,
                        boxShadow: AppFinish.liveGlow(palette),
                      ),
                    ),
                  ),
                ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: highContrast
                        ? palette.surface
                        : Color.alphaBlend(
                            colors.cardWash,
                            palette.surfaceRaised,
                          ),
                    borderRadius: AppRadius.block,
                  ),
                  foregroundDecoration: BoxDecoration(
                    borderRadius: AppRadius.block,
                    border: AppFinish.liveRim(
                      palette,
                      highContrast: highContrast,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: AppRadius.block,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 44, 20, 12),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Icon(
                                    serverJoinIcon(channel, live: true),
                                    size: 40,
                                    color: colors.foreground,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                video
                                    ? copy.serverStageJoinToWatch
                                    : copy.serverPodcastJoinToListen,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.bodyMedium.copyWith(
                                  color: palette.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PositionedDirectional(
                          top: 10,
                          start: 10,
                          child: ServerLivePill(label: copy.serverLivePill),
                        ),
                        if (started != null)
                          PositionedDirectional(
                            top: 10,
                            end: 10,
                            child: YoMetricPill(
                              value: copy.serverLiveSinceShort(
                                serverLiveClock(context, started),
                              ),
                              icon: Icons.schedule_rounded,
                              tone: YoMetricPillTone.overlay,
                              semanticLabel: copy.serverLiveSince(
                                serverLiveClock(context, started),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          channel.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.titleMedium.copyWith(
            color: palette.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        // The page's one lifted action while the stage is live: the scene's
        // own join (the same key, the same word), at the row height the page
        // gives a primary.
        ServerGradientFilledButton(
          buttonKey: const ValueKey('server-join'),
          onPressed: onJoin,
          gradient: colors.ctaGradient,
          fill: colors.cta,
          foreground: colors.onCta,
          minimumSize: Size.fromHeight(
            MediaQuery.textScalerOf(context).scale(14) > 19 ? 56 : 48,
          ),
          icon: Icon(serverJoinIcon(channel, live: true), size: 18),
          label: Text(serverJoinLabel(copy, channel, live: true, role: role)!),
        ),
      ],
    );
  }
}

/// The date block of an event row: the day over the clock, in the event's
/// own time zone, exactly as the events board draws it.
class _EventDateBlock extends StatelessWidget {
  const _EventDateBlock({required this.day, required this.time});
  final String day;
  final String time;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      constraints: const BoxConstraints(minWidth: 52),
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: AppRadius.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tabular figures: "19:00" and "20:00" are equally wide, so two
          // rows' blocks — and the titles beside them — line up at any text
          // size (at 200 % the clock, not the 52 px floor, sets the width).
          Text(
            day,
            style: AppTypography.titleMedium.copyWith(
              color: palette.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            time,
            style: AppTypography.labelSmall.copyWith(
              color: palette.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

({String day, String time, String date, DateTime zoned}) _eventWhen(
  BuildContext context,
  ServerEvent event,
) {
  final zoned = ServerEventTime.inZone(event.startsAt, event.timeZone);
  final localizations = MaterialLocalizations.of(context);
  return (
    day: '${zoned.day}',
    time: localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(zoned),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    ),
    date: localizations.formatMediumDate(zoned),
    zoned: zoned,
  );
}

/// An overline in capitals, the way its own language writes them.
///
/// Dart's `toUpperCase` knows no locale: Turkish would get a dotless `I` for
/// its `i` ("SONRAKI" for "sonraki"), and Greek capitals would keep the tonos
/// that an all-capitals Greek word drops ("ΕΠΌΜΕΝΟ" for "ΕΠΟΜΕΝΟ").
String serverPageOverline(Locale locale, String text) {
  switch (locale.languageCode) {
    case 'tr':
      return text.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
    case 'el':
      const plain = {
        'Ά': 'Α',
        'Έ': 'Ε',
        'Ή': 'Η',
        'Ί': 'Ι',
        'Ό': 'Ο',
        'Ύ': 'Υ',
        'Ώ': 'Ω',
      };
      return text
          .toUpperCase()
          .split('')
          .map((letter) => plain[letter] ?? letter)
          .join();
    default:
      return text.toUpperCase();
  }
}

/// The quiet stage's hero: the next real event of this server.
///
/// `Następny LIVE` on a community, `Następny odcinek` on a podcast, with the
/// day relative to now in the event's own time zone, the stage it will be on
/// and one action — the reminder where the event kind has one (a podcast
/// programme), otherwise the RSVP every event has.
class _NextEventHero extends StatelessWidget {
  const _NextEventHero({
    required this.server,
    required this.stage,
    required this.event,
    required this.now,
    required this.repository,
    required this.onOpen,
  });
  final Server server;
  final ServerChannel stage;
  final ServerEvent event;
  final DateTime now;
  final ServerRepository repository;
  final VoidCallback onOpen;

  String _relativeDay(
    BuildContext context,
    AppLocalizations copy,
    DateTime zoned,
    String date,
  ) {
    final today = ServerEventTime.inZone(now, event.timeZone);
    final days = DateTime.utc(
      zoned.year,
      zoned.month,
      zoned.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    return switch (days) {
      0 => copy.serverPageToday,
      1 => copy.serverPageTomorrow,
      _ => date,
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final identity = ServerIdentity.of(server.type);
    final colors = identity.resolve(Theme.of(context).brightness);
    final when = _eventWhen(context, event);
    return ServerSessionCard(
      key: const ValueKey('server-page-next-event'),
      state: ServerSessionCardState.quiet,
      accent: identity.accent,
      colors: colors,
      padding: const EdgeInsets.all(16),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              key: const ValueKey('server-page-next-event-open'),
              onTap: onOpen,
              borderRadius: AppRadius.md,
              child: Row(
                children: [
                  _EventDateBlock(day: when.day, time: when.time),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          serverPageOverline(
                            Localizations.localeOf(context),
                            server.type == ServerType.podcast
                                ? copy.serverNextEpisode
                                : copy.serverPageNextLive,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.overline.copyWith(
                            color: colors.foreground,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          event.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.titleMedium.copyWith(
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_relativeDay(context, copy, when.zoned, when.date)}'
                          ' · ${stage.name}',
                          maxLines: 2,
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
            ),
            if (repository is ServerEventsRepository &&
                event.acceptsResponsesAt(now)) ...[
              const SizedBox(height: 14),
              _EventAction(
                key: ValueKey('server-page-event-action-${event.id}'),
                event: event,
                repository: repository,
                onOpen: onOpen,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The next event's one action.
///
/// An event kind with a reminder (`reminderOptInEnabled`: a podcast
/// programme, a family plan) gets `Przypomnij mi`, which toggles the real
/// reminder through `respondToEvent`; a first reminder is saved with the
/// weakest answer the contract has (`Może`), because asking to be reminded is
/// not a promise to come. Every other kind has no reminder at all, so its
/// action is the RSVP it does have (`Będę`). Once that answer is saved the
/// button shows it and leads to the event, where it can be changed.
///
/// Whatever answer is on record and not shown by the button itself is said
/// in words under it (`Twoja odpowiedź: Może`): other people see that answer
/// counted on the events board, so the person it belongs to sees it here.
class _EventAction extends StatefulWidget {
  const _EventAction({
    required this.event,
    required this.repository,
    required this.onOpen,
    super.key,
  });
  final ServerEvent event;
  final ServerRepository repository;
  final VoidCallback onOpen;

  @override
  State<_EventAction> createState() => _EventActionState();
}

class _EventActionState extends State<_EventAction> {
  late Stream<ServerEventAttendance?> _attendance;
  bool _busy = false;
  Object? _error;

  /// The answer this button just saved, shown until the document's own
  /// snapshot moves on from [_savedOver] — the answer the stream held when
  /// the save was sent. After that the stream is the truth again, so an
  /// answer changed on the events board or on another device is never
  /// covered by what this button once saved.
  ServerEventAttendance? _saved;
  ServerEventAttendance? _savedOver;

  /// The stream's latest answer, kept for [_savedOver].
  ServerEventAttendance? _latest;

  ServerEventsRepository get _events =>
      widget.repository as ServerEventsRepository;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void didUpdateWidget(covariant _EventAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.id != widget.event.id ||
        oldWidget.event.channelId != widget.event.channelId) {
      _saved = null;
      _savedOver = null;
      _latest = null;
      _error = null;
      _watch();
    }
  }

  void _watch() {
    _attendance = _events.watchMyEventResponse(
      widget.event.serverId,
      widget.event.channelId,
      widget.event.id,
    );
  }

  Future<void> _respond(ServerEventAttendance next) async {
    if (_busy) return;
    final sentOver = _latest;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _events.respondToEvent(
        event: widget.event,
        response: next.response,
        reminderRequested: widget.event.reminderOptInEnabled
            ? next.reminderRequested
            : null,
        requestId: widget.repository.newRequestId(),
      );
      if (mounted) {
        setState(() {
          _saved = next;
          _savedOver = sentOver;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final reminder = widget.event.reminderOptInEnabled;
    return StreamBuilder<ServerEventAttendance?>(
      stream: _attendance,
      builder: (context, snapshot) {
        _latest = snapshot.data;
        final attendance = _saved != null && snapshot.data == _savedOver
            ? _saved
            : snapshot.data;
        final selected = reminder
            ? attendance?.reminderRequested ?? false
            : attendance?.response == ServerEventResponse.going;
        final VoidCallback? onPressed;
        if (_busy) {
          onPressed = null;
        } else if (reminder) {
          onPressed = () => _respond(
            ServerEventAttendance(
              response: attendance?.response ?? ServerEventResponse.maybe,
              reminderRequested: !selected,
            ),
          );
        } else if (selected) {
          onPressed = widget.onOpen;
        } else {
          onPressed = () => _respond(
            const ServerEventAttendance(
              response: ServerEventResponse.going,
              reminderRequested: false,
            ),
          );
        }
        final error = _error;
        // The answer on record, said in words wherever the button shows
        // something else: the reminder button never shows an answer, and the
        // RSVP button only shows `Będę`. A first reminder is saved together
        // with `Może`, so this is also where the page tells the person that.
        final answer = switch (attendance?.response) {
          null => null,
          ServerEventResponse.going => reminder ? copy.serverEventGoing : null,
          ServerEventResponse.maybe => copy.serverEventMaybe,
          ServerEventResponse.declined => copy.serverEventDeclined,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              selected: selected,
              child: OutlinedButton.icon(
                key: const ValueKey('server-page-event-respond'),
                onPressed: onPressed,
                style:
                    AppFinish.tonalNeutral(
                      palette,
                      highContrast: MediaQuery.highContrastOf(context),
                    ).merge(
                      OutlinedButton.styleFrom(
                        minimumSize: Size.fromHeight(
                          MediaQuery.textScalerOf(context).scale(14) > 19
                              ? 56
                              : 44,
                        ),
                      ),
                    ),
                icon: Icon(
                  reminder
                      ? (selected
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_none_rounded)
                      : (selected
                            ? Icons.check_circle_rounded
                            : Icons.event_available_outlined),
                  size: 18,
                ),
                label: Text(
                  reminder ? copy.serverEventReminder : copy.serverEventGoing,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            if (answer != null) ...[
              const SizedBox(height: 8),
              Text(
                copy.serverPageYourAnswer(answer),
                key: const ValueKey('server-page-event-answer'),
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                serverActionFailureCopy(error, copy),
                key: const ValueKey('server-page-event-error'),
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: palette.dangerForeground,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The template's main media channel as a card: what it is, the one honest
/// line about it, and the way in.
///
/// Before joining it says only what the channel document carries — live
/// since HH:MM, or that it is quiet — and never a number of people. A lounge
/// is joined in place and shows the provider's own roster and the three
/// round controls once this device is in it; a stage or a meeting has a
/// scene of its own, so in session the card leads back to it.
class _SessionHero extends StatelessWidget {
  const _SessionHero({
    required this.server,
    required this.channel,
    required this.role,
    required this.session,
    required this.onJoin,
    required this.onOpen,
  });
  final Server server;
  final ServerChannel channel;
  final ServerMemberRole? role;
  final ServerSessionController session;
  final VoidCallback onJoin;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final identity = ServerIdentity.of(server.type);
    final colors = identity.resolve(Theme.of(context).brightness);
    final here = session.isIn(channel.id);
    final inRoom =
        here &&
        (session.phase == ServerSessionPhase.connected ||
            session.phase == ServerSessionPhase.reconnecting);
    final live = channel.liveness.isLive;
    final lounge = channel.kind == ServerChannelKind.voice;
    final state = server.isHeld
        ? ServerSessionCardState.quiet
        : here && session.isConnected
        ? ServerSessionCardState.connected
        : live && !here
        ? ServerSessionCardState.live
        : ServerSessionCardState.quiet;
    final status = here && session.isConnected
        ? copy.serverInConversation
        : live
        ? copy.serverLiveSince(
            serverLiveClock(context, channel.liveness.startedAt!),
          )
        : copy.serverQuiet(channel.kind);

    final Widget action;
    if (server.isHeld) {
      action = ServerSessionHeld(
        copy: copy,
        palette: palette,
        colors: colors,
        fullWidth: true,
      );
    } else if (here && lounge) {
      action = ServerSessionStatus(
        session: session,
        copy: copy,
        palette: palette,
        colors: colors,
        compact: true,
      );
    } else if (here) {
      action = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!inRoom) ...[
            ServerSessionStatus(
              session: session,
              copy: copy,
              palette: palette,
              colors: colors,
              compact: true,
              controls: false,
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            key: const ValueKey('server-page-open-main'),
            onPressed: onOpen,
            style:
                AppFinish.tonalNeutral(
                  palette,
                  highContrast: MediaQuery.highContrastOf(context),
                ).merge(
                  OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
            icon: Icon(serverChannelIcon(channel.kind), size: 18),
            label: Text(
              channel.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    } else if (channel.kind == ServerChannelKind.stage && !live) {
      // A quiet stage is started from the stage itself (`Nadaj LIVE` in the
      // action row opens it for a role that may), so the card states what
      // everybody else is waiting for and draws no control to fail.
      action = (role?.canModerate ?? false)
          ? const SizedBox.shrink()
          : Text(
              copy.serverStageWaiting,
              key: const ValueKey('server-page-stage-waiting'),
              style: AppTypography.bodySmall.copyWith(
                color: palette.textSecondary,
              ),
            );
    } else {
      action = ServerJoinAction(
        channel: channel,
        role: role,
        live: live,
        copy: copy,
        colors: colors,
        fullWidth: true,
        onJoin: onJoin,
      );
    }
    final hasAction = action is! SizedBox;
    // A quiet stage has no control on its card, and the stage is a scene of
    // its own (its `Obserwuj`, its share, its start): the card's header leads
    // there, the way the next event's header leads to the events.
    final opensScene =
        channel.kind == ServerChannelKind.stage &&
        !live &&
        !here &&
        !server.isHeld;

    final header = Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.iconSurface,
            border: Border.all(color: colors.iconBorder),
          ),
          child: Icon(
            channel.access == ServerChannelAccess.restricted
                ? Icons.lock_outline
                : serverChannelIcon(channel.kind),
            size: 22,
            color: colors.foreground,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                channel.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleMedium.copyWith(
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (live) ServerLivePill(label: copy.serverLivePill),
                  Text(
                    status,
                    key: const ValueKey('server-page-hero-status'),
                    style: AppTypography.bodySmall.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (opensScene) ...[const SizedBox(width: 8), const _RowTrailing()],
      ],
    );

    return ServerSessionCard(
      key: const ValueKey('server-page-hero'),
      state: state,
      accent: identity.accent,
      colors: colors,
      igniteKey:
          state == ServerSessionCardState.live &&
              channel.liveness.startedAt != null
          ? '${server.id}/${channel.id}/'
                '${channel.liveness.startedAt!.microsecondsSinceEpoch}'
          : null,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (opensScene)
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: const ValueKey('server-page-hero-open'),
                onTap: onOpen,
                borderRadius: AppRadius.md,
                child: header,
              ),
            )
          else
            header,
          if (inRoom && lounge) ...[
            const SizedBox(height: 16),
            ServerVoiceStage(
              participants: session.participants,
              colors: colors,
              compact: true,
            ),
          ],
          if (hasAction) ...[const SizedBox(height: 14), action],
        ],
      ),
    );
  }
}

/// The row's end: the waiting dot when something waits, then the chevron.
class _RowTrailing extends StatelessWidget {
  const _RowTrailing({this.waitingLabel, this.waitingKey});
  final String? waitingLabel;
  final Key? waitingKey;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (waitingLabel != null) ...[
        ServerWaitingDot(key: waitingKey, semanticLabel: waitingLabel!),
        const SizedBox(width: 8),
      ],
      Icon(
        Icons.chevron_right_rounded,
        size: 22,
        color: context.appPalette.textTertiary,
      ),
    ],
  );
}

/// One conversation: the kind's glyph (a lock for a restricted channel) and
/// the name. No unread mark — server channels have no read cursor.
class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.channel,
    required this.waiting,
    required this.onTap,
  });
  final ServerChannel channel;
  final bool waiting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final restricted = channel.access == ServerChannelAccess.restricted;
    return YoChannelRow(
      tileKey: ValueKey('server-page-channel-${channel.id}'),
      label: channel.name,
      icon: restricted ? Icons.lock_outline : serverChannelIcon(channel.kind),
      iconSemanticLabel: copy.serverChannelSpokenKind(
        channel.kind,
        restricted: restricted,
      ),
      iconColor: context.appPalette.textSecondary,
      minHeight: _rowHeight,
      onTap: onTap,
      trailing: _RowTrailing(
        waitingLabel: waiting ? copy.serverQuestionsWaitingLabel : null,
        waitingKey: ValueKey('server-page-questions-waiting-${channel.id}'),
      ),
    );
  }
}

/// One more voice channel: its name, the live line when the document says
/// live, and a short join. The row opens the channel; the button joins it.
class _VoiceRow extends StatelessWidget {
  const _VoiceRow({
    required this.server,
    required this.channel,
    required this.role,
    required this.session,
    required this.onOpen,
    required this.onJoin,
  });
  final Server server;
  final ServerChannel channel;
  final ServerMemberRole? role;
  final ServerSessionController session;
  final VoidCallback onOpen;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) {
      final palette = context.appPalette;
      final copy = AppLocalizations.of(context);
      final restricted = channel.access == ServerChannelAccess.restricted;
      final live = channel.liveness.isLive;
      final here = session.isIn(channel.id);
      final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;
      // The same gate as the channel list's own join: a held server reaches
      // no provider, a restricted channel is not this person's to open, and
      // a stage nobody may start has no label and so no control.
      final full = server.isHeld || restricted || here
          ? null
          : serverJoinLabel(copy, channel, live: live, role: role);
      final label = full == null
          ? null
          : channel.kind == ServerChannelKind.stage
          ? (live ? full : null)
          : copy.serverPageJoin;
      final Widget? trailing;
      if (here) {
        trailing = Text(
          copy.serverConnected,
          key: ValueKey('server-page-connected-${channel.id}'),
          style: AppTypography.labelMedium.copyWith(color: palette.audioAccent),
        );
      } else if (label != null && !largeText) {
        trailing = OutlinedButton(
          key: ValueKey('server-page-join-${channel.id}'),
          onPressed: onJoin,
          style:
              AppFinish.tonalNeutral(
                palette,
                highContrast: MediaQuery.highContrastOf(context),
              ).merge(
                OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
              ),
          child: Semantics(
            label: full,
            excludeSemantics: true,
            child: Text(label, maxLines: 1, softWrap: false),
          ),
        );
      } else {
        // At 200 % text the name keeps the row; the channel's own scene and
        // its full-size join are one tap away.
        trailing = const _RowTrailing();
      }
      return YoChannelRow(
        tileKey: ValueKey('server-page-channel-${channel.id}'),
        label: channel.name,
        icon: restricted ? Icons.lock_outline : serverChannelIcon(channel.kind),
        iconSemanticLabel: copy.serverChannelSpokenKind(
          channel.kind,
          restricted: restricted,
        ),
        iconColor: palette.textSecondary,
        minHeight: _rowHeight,
        onTap: onOpen,
        subtitle: live && channel.liveness.startedAt != null
            ? ServerLiveLamp(
                key: ValueKey('server-page-live-${channel.id}'),
                semanticLabel: copy.serverLivePill,
                label: copy.serverLiveSince(
                  serverLiveClock(context, channel.liveness.startedAt!),
                ),
                style: AppTypography.bodySmall.copyWith(
                  color: palette.textSecondary,
                ),
              )
            : null,
        trailing: trailing,
      );
    },
  );
}

/// The next events of the server's events or calendar channel: the date
/// block, the title and when. Each row opens the events board, where the
/// RSVP, the reminder and the editing live.
class _ServerPageEvents extends StatelessWidget {
  const _ServerPageEvents({required this.events, required this.onOpen});
  final List<ServerEvent> events;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    if (events.isEmpty) {
      return YoChannelRow(
        tileKey: const ValueKey('server-page-events-empty'),
        label: copy.serverNoUpcomingEvents,
        labelMaxLines: 3,
        icon: Icons.event_available_outlined,
        iconColor: palette.textSecondary,
        minHeight: _rowHeight,
        onTap: onOpen,
        trailing: const _RowTrailing(),
      );
    }
    // At 200 % text a two-line title cuts an ordinary one ("Rozmowa o nocnych
    // pocią…"); the row is as tall as it needs to be, so it gets a third.
    final titleLines = MediaQuery.textScalerOf(context).scale(16) > 24 ? 3 : 2;
    return _dividedRows(context, indent: 76, [
      for (final event in events)
        InkWell(
          key: ValueKey('server-page-event-${event.id}'),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Builder(
              builder: (context) {
                final when = _eventWhen(context, event);
                return Row(
                  children: [
                    _EventDateBlock(day: when.day, time: when.time),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            maxLines: titleLines,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.rowTitle.copyWith(
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${when.date} · ${when.time}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.rowPreview.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
    ]);
  }
}
