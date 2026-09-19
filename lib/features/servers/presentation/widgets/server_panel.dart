import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/navigation/yo_server_rail_item.dart';
import 'package:yovoice/shared/widgets/rows/yo_channel_row.dart';

import '../../data/models/server.dart';
import '../../data/models/server_channel.dart';
import '../../data/models/server_invite_authority.dart';
import '../../data/models/server_member_role.dart';
import '../../data/models/server_type.dart';
import '../../data/services/server_session_controller.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';
import 'server_channel_scene.dart';

/// The server panel: cover (an identity tile — no artwork writer exists,
/// contract G7), name, the board's subtitle, `Zaproś`, the channel list
/// grouped by kind (decision B) and `Dodaj kanał`.
///
/// It renders the same on a desktop column, a tablet column and inside the
/// phone's "Kanały" sheet; only the host decides its width.
///
/// Board 04 is the only board with a search field, and the company template
/// is the only one whose channel list is expected to outgrow the column, so
/// [searchable] is true for it alone. The search is real and local: it filters
/// the channels this person may actually see, which the panel already holds.
/// Nothing else in a server has a search index, so nothing else is searched.
class ServerPanel extends StatefulWidget {
  const ServerPanel({
    required this.server,
    required this.channels,
    required this.selectedId,
    required this.onSelected,
    this.role,
    this.onInvite,
    this.onAddChannel,
    this.onManage,
    this.onBack,
    this.connectedChannelId,
    this.session,
    this.onJoin,
    this.onHome,
    this.homeSelected = false,
    super.key,
  });

  final Server server;
  final List<ServerChannel> channels;
  final String? selectedId;
  final ValueChanged<ServerChannel> onSelected;
  final ServerMemberRole? role;

  /// Null disables `Zaproś` (held server, or a role that may not invite).
  final VoidCallback? onInvite;
  final VoidCallback? onAddChannel;

  /// Opens server, channel and member settings. Null hides the control for a
  /// read-only integration that does not provide the management contract.
  final VoidCallback? onManage;

  /// Present when the panel is hosted inline over the directory, so the
  /// person has a way back that the shell's rail does not provide.
  final VoidCallback? onBack;

  /// The media channel the person is currently in, if any.
  final String? connectedChannelId;

  /// The host's live session, read for one thing only: the roster of the
  /// channel named by [connectedChannelId]. ADR-177 keeps every other face
  /// off this list — `rooms/{roomId}`, `participants` and `channelSessions`
  /// are closed to the client, so nothing pre-join could be true. Null (the
  /// phone sheet's own stream, the screenshot harness) simply draws no faces.
  final ServerSessionController? session;

  /// Joins a media channel straight from its row, through the host's existing
  /// join path — the same `session.join(server, channel)` the channel scene's
  /// `server-join` calls. Null leaves the row select-only.
  final ValueChanged<ServerChannel>? onJoin;

  /// Present only where the template has a home board (the family board's
  /// `Rodzinny pulpit`). It is a view of the server, never a channel, so it
  /// carries no channel id and nothing is seeded for it.
  final VoidCallback? onHome;
  final bool homeSelected;

  /// Only board 04 draws a search field.
  bool get searchable => server.type == ServerType.company;

  @override
  State<ServerPanel> createState() => _ServerPanelState();

  /// The order in which a template's group headings appear, expressed as one
  /// representative kind per group (contract §4.2).
  static List<ServerChannelKind> groupAnchors(ServerType type) =>
      switch (type) {
        ServerType.friends => const [
          ServerChannelKind.text,
          ServerChannelKind.voice,
          ServerChannelKind.events,
        ],
        ServerType.community => const [
          ServerChannelKind.announcements,
          ServerChannelKind.text,
          ServerChannelKind.stage,
        ],
        ServerType.podcast => const [
          ServerChannelKind.stage,
          ServerChannelKind.text,
        ],
        ServerType.family => const [
          ServerChannelKind.text,
          ServerChannelKind.calendar,
        ],
        ServerType.company => const [
          ServerChannelKind.text,
          ServerChannelKind.meeting,
        ],
      };

  /// Channels grouped under their template heading, in template order, with
  /// the server's own `position` order kept inside each group.
  static Map<String, List<ServerChannel>> group(
    AppLocalizations copy,
    ServerType type,
    List<ServerChannel> channels,
  ) {
    final groups = <String, List<ServerChannel>>{
      for (final anchor in groupAnchors(type))
        copy.serverShellChannelGroup(type, anchor): [],
    };
    for (final channel in channels) {
      groups
          .putIfAbsent(
            copy.serverShellChannelGroup(type, channel.kind),
            () => [],
          )
          .add(channel);
    }
    groups.removeWhere((_, members) => members.isEmpty);
    return groups;
  }
}

class _ServerPanelState extends State<ServerPanel> {
  final _search = TextEditingController();

  /// The trimmed, case-folded query. Empty means the whole list.
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(ServerChannel channel) =>
      _query.isEmpty || channel.name.toLowerCase().contains(_query);

  @override
  Widget build(BuildContext context) {
    final server = widget.server;
    final onHome = widget.onHome;
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = ServerIdentity.of(
      server.type,
    ).resolve(Theme.of(context).brightness);
    final searching = widget.searchable && _query.isNotEmpty;
    final channels = searching
        ? widget.channels.where(_matches).toList(growable: false)
        : widget.channels;
    final groups = ServerPanel.group(copy, server.type, channels);
    // The home board belongs to the template's first group (board 03 lists
    // `Rodzinny pulpit` under DOM); if that group has no channels at all it
    // is created for the board alone. A search is looking for a channel, so
    // the board — which is a view, not a channel — steps out of the way.
    final homeGroup = onHome == null || searching
        ? null
        : copy.serverShellChannelGroup(server.type, ServerChannelKind.text);
    final entries = <MapEntry<String, List<ServerChannel>>>[
      if (homeGroup != null && !groups.containsKey(homeGroup))
        MapEntry(homeGroup, const []),
      ...groups.entries,
    ];
    final canInvite = canInviteToServer(widget.server, widget.role);
    return Material(
      color: palette.surfaceMuted,
      child: ListView(
        key: const ValueKey('server-panel'),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (widget.onBack != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('server-panel-back'),
                onPressed: widget.onBack,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: palette.textSecondary,
                ),
                icon: const Icon(Icons.chevron_left_rounded),
                label: Text(copy.serversTitle),
              ),
            ),
          if (widget.searchable) ...[
            _SearchField(
              controller: _search,
              hint: copy.serverSearchChannels,
              clearLabel: copy.serverSearchClear,
              onChanged: (value) {
                final next = value.trim().toLowerCase();
                if (next != _query) setState(() => _query = next);
              },
            ),
            const SizedBox(height: 12),
          ],
          // Slim: one header row (squircle, name, subtitle, settings)
          // instead of a 96 px gradient cover card above a second name
          // block. The cover carried no data of its own (no artwork writer
          // exists, contract G7), so nothing is lost by flattening it.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, top: 2),
                child: YoServerTile(
                  initial: server.initial,
                  type: server.type,
                  size: 40,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(
                            child: Text(
                              server.name.isEmpty
                                  ? copy.serversTitle
                                  : server.name,
                              // A server name nobody sized for (118
                              // characters at 200 % text in a 240-px column)
                              // ran to a dozen lines and pushed `Zaproś` and
                              // every channel row out of the panel's lazily
                              // built viewport — on a phone, where this panel
                              // IS the channel list. The full name is on the
                              // surface's own header; here it is an
                              // identifier, so it takes two lines and elides.
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.titleMedium.copyWith(
                                fontWeight: FontWeight.w800,
                                color: palette.textPrimary,
                              ),
                            ),
                          ),
                          if (server.privacy == ServerPrivacy.inviteOnly)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(
                                start: 6,
                                top: 2,
                              ),
                              child: Icon(
                                Icons.lock_outline,
                                size: 16,
                                color: palette.textSecondary,
                                semanticLabel: copy.serverPrivacyTitle(
                                  server.privacy,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${copy.serverKindSubtitle(server.type, server.privacy)} · '
                        '${copy.serverMembers(server.memberCount)}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.onManage != null)
                IconButton(
                  key: const ValueKey('server-manage-action'),
                  onPressed: widget.onManage,
                  tooltip: copy.serverManage,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    foregroundColor: palette.textSecondary,
                  ),
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
            ],
          ),
          if (canInvite) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('server-invite-action'),
              onPressed: server.isHeld ? null : widget.onInvite,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.person_add_outlined, size: 18),
              label: Text(copy.serverInvite),
            ),
            if (server.isHeld)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text(
                  copy.serverInviteHeldBody,
                  style: AppTypography.bodySmall.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 8),
          Divider(color: palette.border, height: 24),
          if (channels.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                // A search that found nothing is a different fact from a
                // server with no channels, and says so.
                searching
                    ? copy.serverSearchNoChannels
                    : copy.serverNoChannelsBody,
                key: searching
                    ? const ValueKey('server-panel-search-empty')
                    : null,
                style: AppTypography.bodySmall.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ),
          for (final entry in entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Text(
                entry.key,
                style: AppTypography.eyebrow.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ),
            if (entry.key == homeGroup)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: YoChannelRow(
                  // The home board selects a view, not a channel, so it
                  // carries no live marker and no channel key.
                  tileKey: const ValueKey('server-home-board'),
                  label: copy.serverFamilyHome,
                  icon: Icons.home_outlined,
                  // Its label is a sentence, not a channel name.
                  labelMaxLines: 2,
                  selected: widget.homeSelected,
                  selectedForeground: colors.selectedForeground,
                  selectedWash: colors.selectedWash,
                  onTap: onHome!,
                ),
              ),
            for (final channel in entry.value)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: _PanelChannelRow(
                  server: server,
                  channel: channel,
                  selected: channel.id == widget.selectedId,
                  connected: channel.id == widget.connectedChannelId,
                  colors: colors,
                  role: widget.role,
                  session: widget.session,
                  onJoin: widget.onJoin,
                  onTap: () => widget.onSelected(channel),
                ),
              ),
          ],
          if (widget.onAddChannel != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('server-add-channel'),
                onPressed: widget.onAddChannel,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: palette.textSecondary,
                ),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(copy.serverAddChannel),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Board 04's panel search. It filters the list already on screen, so it
/// promises nothing it cannot do: no message, file or person is searched,
/// because none of those has an index.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.clearLabel,
    required this.onChanged,
  });
  final TextEditingController controller;
  final String hint;
  final String clearLabel;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        key: const ValueKey('server-panel-search'),
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: AppTypography.bodyMedium.copyWith(color: palette.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          filled: true,
          fillColor: palette.surface,
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: palette.textSecondary,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 44),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  key: const ValueKey('server-panel-search-clear'),
                  tooltip: clearLabel,
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
          border: const OutlineInputBorder(borderRadius: AppRadius.md),
        ),
      ),
    );
  }
}

/// One channel row of the panel.
///
/// The drawing is the shared [YoChannelRow] / [YoVoiceChannelRow]; what stays
/// here is everything that belongs to a server: the contract key, the glyph
/// map, the lock for a restricted channel, the identity wash, the liveness
/// copy and clock, the join gate and the mapping of the provider's roster.
///
/// A media row reads the roster only for the channel this person is connected
/// to, and only then: it listens to the session for that one row, so a
/// speaking tick repaints a single tile instead of the whole list.
class _PanelChannelRow extends StatelessWidget {
  const _PanelChannelRow({
    required this.server,
    required this.channel,
    required this.selected,
    required this.connected,
    required this.colors,
    required this.onTap,
    this.role,
    this.session,
    this.onJoin,
  });
  final Server server;
  final ServerChannel channel;
  final bool selected;
  final bool connected;
  final ServerIdentityVisuals colors;
  final VoidCallback onTap;
  final ServerMemberRole? role;

  /// Present only where the host holds a session; the roster is read from it
  /// for the connected row alone (ADR-177).
  final ServerSessionController? session;
  final ValueChanged<ServerChannel>? onJoin;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final restricted = channel.access == ServerChannelAccess.restricted;
    final icon = restricted
        ? Icons.lock_outline
        : serverChannelIcon(channel.kind);
    // The kind is voiced on every row: for a voice-first product it decides
    // whether selecting leads to talking. The lock adds its access on top.
    final iconLabel = copy.serverChannelSpokenKind(
      channel.kind,
      restricted: restricted,
    );
    if (!channel.kind.isMedia) {
      return YoChannelRow(
        tileKey: ValueKey('server-channel-${channel.id}'),
        label: channel.name,
        icon: icon,
        iconSemanticLabel: iconLabel,
        selected: selected,
        selectedForeground: colors.selectedForeground,
        selectedWash: colors.selectedWash,
        onTap: onTap,
      );
    }

    final live = channel.liveness.isLive;
    // A held server reaches no provider, a restricted channel is not this
    // person's to open and the channel you are already in has nothing to
    // join; a stage nobody may start has no label, and so no control.
    final joinLabel = onJoin == null || server.isHeld || restricted || connected
        ? null
        : serverJoinLabel(copy, channel, live: live, role: role);
    YoVoiceChannelRow row(List<YoVoiceRowParticipant> people) =>
        YoVoiceChannelRow(
          tileKey: ValueKey('server-channel-${channel.id}'),
          label: channel.name,
          icon: icon,
          iconSemanticLabel: iconLabel,
          selected: selected,
          selectedForeground: colors.selectedForeground,
          selectedWash: colors.selectedWash,
          // The same key as the header's pill: one finder addresses every
          // live marker in the shell, so "nothing claims liveness" can be
          // asserted once instead of per surface.
          liveBadge: live ? ServerLivePill(label: copy.serverLivePill) : null,
          liveSince: live && channel.liveness.startedAt != null
              ? copy.serverLiveSinceShort(
                  serverLiveClock(context, channel.liveness.startedAt!),
                )
              : null,
          connected: connected,
          connectedLabel: copy.serverConnected,
          avatarBackground: colors.iconSurface,
          participants: people,
          onJoin: joinLabel == null ? null : () => onJoin!(channel),
          joinLabel: joinLabel,
          joinIcon: serverJoinIcon(channel, live: live),
          // Never `server-join`: the scene's single full-size CTA is counted
          // by that key, and this row is one more way to the same call.
          joinKey: ValueKey('server-channel-join-${channel.id}'),
          onTap: onTap,
        );

    final controller = session;
    if (!connected || controller == null) {
      return row(const <YoVoiceRowParticipant>[]);
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => row(<YoVoiceRowParticipant>[
        for (final person in controller.participants)
          YoVoiceRowParticipant(
            userId: person.identity,
            displayName: person.isLocal ? copy.serverYou : person.name,
            isSpeaking: person.isSpeaking,
            isMicrophoneEnabled: person.isMicrophoneEnabled,
            semanticLabel: <String>[
              person.isLocal ? copy.serverYou : person.name,
              if (person.isSpeaking)
                copy.serverSpeaking
              else if (!person.isMicrophoneEnabled)
                copy.serverMicrophoneOff,
            ].join(', '),
          ),
      ]),
    );
  }
}

IconData serverChannelIcon(ServerChannelKind kind) => switch (kind) {
  ServerChannelKind.text => Icons.tag_rounded,
  ServerChannelKind.voice => Icons.volume_up_outlined,
  ServerChannelKind.stage => Icons.podcasts_rounded,
  ServerChannelKind.events ||
  ServerChannelKind.calendar => Icons.calendar_month_outlined,
  ServerChannelKind.announcements => Icons.campaign_outlined,
  ServerChannelKind.rules => Icons.article_outlined,
  ServerChannelKind.questions => Icons.chat_bubble_outline,
  ServerChannelKind.episodes => Icons.library_music_outlined,
  ServerChannelKind.memories => Icons.photo_library_outlined,
  ServerChannelKind.list => Icons.checklist_outlined,
  ServerChannelKind.meeting => Icons.groups_outlined,
  ServerChannelKind.whiteboard => Icons.draw_outlined,
  ServerChannelKind.files => Icons.insert_drive_file_outlined,
};
