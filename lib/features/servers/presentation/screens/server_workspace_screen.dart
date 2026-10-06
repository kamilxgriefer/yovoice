import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/embedded_back_scope.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/navigation/yo_edge_back_gesture.dart';
import 'package:yovoice/shared/widgets/navigation/yo_server_rail_item.dart';
import 'package:yovoice/shared/widgets/states/yo_empty_state.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';

import '../../data/models/server.dart';
import '../../data/models/server_channel.dart';
import '../../data/models/server_invite_authority.dart';
import '../../data/models/server_member_role.dart';
import '../../data/models/server_type.dart';
import '../../data/server_links.dart';
import '../../data/services/server_company_file_service.dart';
import '../../data/services/server_family_check_in_service.dart';
import '../../data/services/server_family_memory_service.dart';
import '../../data/services/server_follow_service.dart';
import '../../data/services/server_media_connector.dart';
import '../../data/services/server_podcast_episode_repository.dart';
import '../../data/services/server_question_attention.dart';
import '../../data/services/server_screen_share_capability.dart';
import '../../data/services/server_service.dart';
import '../../data/services/server_session_controller.dart';
import '../../data/services/server_shared_list_service.dart';
import '../../data/services/server_whiteboard_repository.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';
import '../server_page_copy.dart';
import '../theme/server_identity.dart';
import '../widgets/server_channel_scene.dart';
import '../widgets/server_community_stage.dart';
import '../widgets/server_company_meeting.dart';
import '../widgets/server_company_files_board.dart';
import '../widgets/server_conversation_dock.dart';
import '../widgets/server_create_channel_sheet.dart';
import '../widgets/server_events_board.dart';
import '../widgets/server_family_board.dart';
import '../widgets/server_family_memory_album.dart';
import '../widgets/server_home_page.dart';
import '../widgets/server_invite_sheet.dart';
import '../widgets/server_local_tabs.dart';
import '../widgets/server_management_sheet.dart';
import '../widgets/server_panel.dart';
import '../widgets/server_podcast_questions_board.dart';
import '../widgets/server_podcast_episodes_board.dart';
import '../widgets/server_scrolling_details.dart';
import '../widgets/server_shared_list_board.dart';
import '../widgets/server_text_channel_scene.dart';
import '../widgets/server_waiting_dot.dart';
import '../widgets/server_whiteboard_board.dart';

export '../widgets/server_channel_scene.dart' show ServerChannelEmptyState;
export '../widgets/server_panel.dart' show serverChannelIcon;

typedef ServerChannelBuilder =
    Widget Function(BuildContext context, Server server, ServerChannel channel);

/// Podcast recording and its durable episode archive need the production
/// egress provider as one capability. Keep both surfaces unavailable unless
/// the release was built after that provider, its credentials and IAM were
/// verified. Tests and previews can still inject an explicit repository.
const _podcastRecordingAndArchiveEnabled = bool.fromEnvironment(
  'YOVOICE_PODCAST_RECORDING_ENABLED',
);

/// The in-server shell.
///
/// A server opens on its page (`ServerHomePage`, ADR-240): the cover, the
/// name, the actions, the template's main thing, then conversations, voice
/// and events, with the whole channel list behind one row. A channel is a
/// destination reached from the page or from the channel list.
///
/// Anatomy at every width: server panel (name, subtitle, `Zaproś`, grouped
/// channels, `Dodaj kanał`) · centre (the page, or a channel's header and
/// scene) · optional context panel · persistent conversation dock. Desktop
/// hosts the three or four panels side by side inside the shell's content
/// slot, a tablet two, a phone one surface at a time — the page, or a channel
/// with a way back to the page — and a compact dock. The global rail and dock
/// belong to the shell and are never drawn here.
class ServerWorkspaceScreen extends StatefulWidget {
  const ServerWorkspaceScreen({
    required this.serverId,
    this.repository,
    this.initialChannelId,
    this.isRootTab = false,
    this.onInvite,
    this.channelBuilder,
    this.justCreated = false,
    this.onBack,
    this.connector,
    this.anotherVoiceSessionActive,
    this.chatService,
    this.screenShare,
    this.familyCheckIns,
    this.familyMemories,
    this.sharedList,
    this.followRepository,
    this.podcastEpisodeRepository,
    this.whiteboardRepository,
    this.companyFileRepository,
    this.shareServer,
    this.isVisible,
    this.onOpenServer,
    this.questionAttention,
    super.key,
  });
  final String serverId;
  final ServerRepository? repository;
  final String? initialChannelId;

  /// True when hosted in a desktop content slot (no app bar of its own);
  /// false when pushed as a route, which carries a real app bar with Back.
  final bool isRootTab;

  /// Overrides the built-in invite sheet.
  final ValueChanged<Server>? onInvite;

  /// Overrides the built-in scene for an active server (integration seam).
  final ServerChannelBuilder? channelBuilder;

  /// Arrived here straight from creation, so the server has exactly one
  /// member. Offers the invitation once.
  final bool justCreated;

  /// Present when hosted inline over the directory: the panel then carries
  /// a way back that the shell's rail cannot provide.
  final VoidCallback? onBack;

  /// Test seams for the media provider, the device's other voice owner and
  /// the message store.
  final ServerMediaConnector? connector;
  final bool Function()? anotherVoiceSessionActive;
  final ClubChatService? chatService;

  /// What this platform can do about publishing a screen (contract decision
  /// D). Left null in production, where the real query answers.
  final ServerScreenShareCapability? screenShare;

  /// Template-module seams. Production resolves the callable-backed services;
  /// tests can keep every read and mutation in one in-memory repository.
  final ServerFamilyCheckInRepository? familyCheckIns;
  final ServerFamilyMemoryRepository? familyMemories;
  final ServerSharedListRepository? sharedList;
  final ServerFollowRepository? followRepository;
  final ServerPodcastEpisodeRepository? podcastEpisodeRepository;
  final ServerWhiteboardRepository? whiteboardRepository;
  final ServerCompanyFileRepository? companyFileRepository;
  final Future<void> Function(Uri link)? shareServer;

  /// Whether the surface hosting this workspace is on screen.
  ///
  /// A pushed route ends its conversation by being popped, which is what
  /// `dispose()` below is for. A workspace hosted in one of the desktop
  /// shell's retained content slots is never disposed when the person moves
  /// to Home or Chats: the `IndexedStack` keeps it built, the dock goes with
  /// it, and the microphone would stay open behind no UI at all. When the
  /// host publishes this listenable the conversation ends with the surface,
  /// exactly as it does on a phone. Null means always visible.
  final ValueListenable<bool>? isVisible;

  /// Opens another of the account's servers from the server rail. The
  /// directory that hosts a workspace inline swaps it in place; left null,
  /// the workspace (always the whole of its route) replaces its own route
  /// with the other server's, carrying the same seams. Either way it is the
  /// same as going back and opening that server: the conversation belongs to
  /// the server it was joined in and ends with it.
  final ValueChanged<Server>? onOpenServer;

  /// Which podcast servers have listener questions this host has not seen.
  /// The directory that hosts or pushes this workspace hands over its own, so
  /// the tile, the rail and the dots in here read one set of listeners; left
  /// null, the workspace keeps one of its own for its lifetime.
  final ServerQuestionAttention? questionAttention;

  /// Phone below, tablet from here.
  static const tabletBreakpoint = 768.0;

  /// Three (or four) panels from here.
  static const desktopBreakpoint = 1100.0;

  /// The server rail beside the channel column (tablet and desktop) and
  /// beside the channel list in the phone's `Kanały` sheet.
  static const serverRailWidth = YoServerRailItem.railWidth;

  /// The channel column on a desktop, and from a 1 440 px workspace up.
  /// Kept at the pre-rail widths rather than the brief's 248: below 264 the
  /// channel row's under-name `NA ŻYWO` marker shares its line with the
  /// clock and elides (seen in the phase-2 frames).
  static const desktopChannelColumnWidth = 264.0;
  static const wideDesktopChannelColumnWidth = 280.0;
  static const wideDesktopWidth = 1440.0;

  /// The channel column on a tablet. 264, not the former 240: at 240 the
  /// live row's under-name `NA ŻYWO` marker elided (phase-2 frames).
  static const tabletChannelColumnWidth = 264.0;

  /// The phone sheet shows the rail only when there is somewhere else to go:
  /// a one-server rail would take 64 of 320 px to repeat the header.
  static const phoneRailMinimumServers = 2;

  @override
  State<ServerWorkspaceScreen> createState() => _ServerWorkspaceScreenState();
}

class _ServerWorkspaceScreenState extends State<ServerWorkspaceScreen> {
  late final ServerRepository _repository;
  late final ServerSessionController _session;
  late Stream<Server?> _server;
  Stream<List<ServerChannel>>? _channels;
  late Stream<ServerMemberRole?> _role;
  late Stream<Set<String>> _moderators;
  String? _selectedId;
  ServerFamilyCheckInRepository? _defaultFamilyCheckIns;
  ServerFamilyMemoryRepository? _defaultFamilyMemories;
  ServerSharedListRepository? _defaultSharedList;
  ServerFollowRepository? _defaultFollowRepository;
  ServerCompanyFileRepository? _defaultCompanyFiles;
  String? _joinRequestId;
  bool _joining = false;

  /// The account's servers for the server rail, from the same
  /// `watchMyServers()` read the directory and Start already use. An
  /// unreadable list leaves the rail with the open server alone.
  List<Server> _myServers = const [];
  StreamSubscription<List<Server>>? _myServersSubscription;
  Object? _joinError;

  /// Listener questions this host has not seen, across the account's podcast
  /// servers (ADR "listener questions dot").
  ServerQuestionAttention? _ownAttention;
  ServerQuestionAttention get _attention =>
      widget.questionAttention ??
      (_ownAttention ??= ServerQuestionAttention(
        repository: _repository,
        isVisible: widget.isVisible,
      ));

  ServerCompanyFileRepository get _companyFiles {
    final supplied = widget.companyFileRepository;
    if (supplied != null) return supplied;
    final repository = _repository;
    if (repository is ServerCompanyFileRepository) {
      return repository as ServerCompanyFileRepository;
    }
    return _defaultCompanyFiles ??= ServerCompanyFileService();
  }

  ServerWhiteboardRepository? get _whiteboardRepository {
    final supplied = widget.whiteboardRepository;
    if (supplied != null) return supplied;
    final repository = _repository;
    return repository is ServerWhiteboardRepository
        ? repository as ServerWhiteboardRepository
        : null;
  }

  ServerPodcastEpisodeRepository? get _podcastEpisodes {
    final supplied = widget.podcastEpisodeRepository;
    if (supplied != null) return supplied;
    if (!_podcastRecordingAndArchiveEnabled) return null;
    final repository = _repository;
    return repository is ServerPodcastEpisodeRepository
        ? repository as ServerPodcastEpisodeRepository
        : null;
  }

  ServerFamilyCheckInRepository get _familyCheckIns {
    final supplied = widget.familyCheckIns;
    if (supplied != null) return supplied;
    final repository = _repository;
    if (repository is ServerFamilyCheckInRepository) {
      return repository as ServerFamilyCheckInRepository;
    }
    return _defaultFamilyCheckIns ??= ServerFamilyCheckInService();
  }

  ServerFamilyMemoryRepository get _familyMemories {
    final supplied = widget.familyMemories;
    if (supplied != null) return supplied;
    final repository = _repository;
    if (repository is ServerFamilyMemoryRepository) {
      return repository as ServerFamilyMemoryRepository;
    }
    return _defaultFamilyMemories ??= ServerFamilyMemoryService();
  }

  ServerSharedListRepository get _sharedList {
    final supplied = widget.sharedList;
    if (supplied != null) return supplied;
    final repository = _repository;
    if (repository is ServerSharedListRepository) {
      return repository as ServerSharedListRepository;
    }
    return _defaultSharedList ??= ServerSharedListService();
  }

  ServerFollowRepository get _followRepository {
    final supplied = widget.followRepository;
    if (supplied != null) return supplied;
    final repository = _repository;
    if (repository is ServerFollowRepository) {
      return repository as ServerFollowRepository;
    }
    return _defaultFollowRepository ??= ServerFollowService();
  }

  /// The phone's and tablet's local tab inside a media channel: 0 = the
  /// scene, 1 = the conversation beside it.
  int _localTab = 0;

  /// The server page as a destination of its own (ADR-240): true while the
  /// page is what the centre shows, false once a channel has been chosen.
  /// Null means nobody has chosen yet, which the first build resolves from
  /// the requested channel.
  bool? _home;

  /// Board 04's meeting view. It lives here, not in the scene, because the
  /// dock's `Tablica` changes it and because a view is not a session: moving
  /// between these never starts, stops or interrupts a meeting.
  ServerMeetingTab _meetingTab = ServerMeetingTab.presentation;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? ServerService();
    _session = ServerSessionController(
      repository: _repository,
      connector: widget.connector,
      anotherVoiceSessionActive: widget.anotherVoiceSessionActive,
      screenShare: widget.screenShare,
    );
    _selectedId = widget.initialChannelId;
    _listen();
    widget.isVisible?.addListener(_onVisibilityChanged);
    _attention
      ..claim(widget.serverId)
      ..addListener(_onAttention);
    try {
      _myServersSubscription = _repository.watchMyServers().listen((servers) {
        if (!mounted) return;
        _attention.trackDirectory(servers);
        setState(() => _myServers = servers);
      }, onError: (Object _) {});
    } on Object {
      // A repository without the account list simply has no rail beyond
      // the open server.
    }
  }

  /// The rail's servers: the account's list, with the open server first if
  /// the list (still loading, or unreadable) does not carry it yet.
  List<Server> _railServers(Server current) =>
      _myServers.any((server) => server.id == current.id)
      ? _myServers
      : [current, ..._myServers];

  void _openServer(Server target) {
    if (target.id == widget.serverId) return;
    final callback = widget.onOpenServer;
    if (callback != null) {
      callback(target);
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ServerWorkspaceScreen(
          serverId: target.id,
          repository: widget.repository,
          isRootTab: widget.isRootTab,
          onInvite: widget.onInvite,
          channelBuilder: widget.channelBuilder,
          onBack: widget.onBack,
          connector: widget.connector,
          anotherVoiceSessionActive: widget.anotherVoiceSessionActive,
          chatService: widget.chatService,
          screenShare: widget.screenShare,
          familyCheckIns: widget.familyCheckIns,
          familyMemories: widget.familyMemories,
          sharedList: widget.sharedList,
          followRepository: widget.followRepository,
          podcastEpisodeRepository: widget.podcastEpisodeRepository,
          whiteboardRepository: widget.whiteboardRepository,
          companyFileRepository: widget.companyFileRepository,
          shareServer: widget.shareServer,
          isVisible: widget.isVisible,
        ),
      ),
    );
  }

  /// Leaving the surface leaves the conversation. Nothing is muted halfway or
  /// kept "just in case": a live microphone with no dock on screen is the
  /// defect, not the fix.
  void _onVisibilityChanged() {
    if (widget.isVisible?.value ?? true) return;
    if (_session.isActive) unawaited(_session.leave());
  }

  void _onAttention() {
    if (mounted) setState(() {});
  }

  /// The Questions channel this viewer is told about: a Podcast server that
  /// is not held, a role that may moderate it, and the channel `Pytania`
  /// actually opens beside the studio.
  static ServerChannel? _hostedQuestions(
    Server server,
    List<ServerChannel> channels,
    ServerMemberRole? role,
  ) {
    if (server.type != ServerType.podcast ||
        server.isHeld ||
        !(role?.canModerate ?? false)) {
      return null;
    }
    return channels
        .where((channel) => channel.kind == ServerChannelKind.questions)
        .firstOrNull;
  }

  /// The Questions channel whose new questions wait for this host, or null.
  String? _waitingQuestions(Server server) => _attention.isWaiting(server.id)
      ? _attention.watchedChannel(server.id)
      : null;

  void _listen() {
    _server = _repository.watchServer(widget.serverId);
    // Channel LIST authority begins at membership. A public non-member can
    // read the root in order to decide whether to join, but Rules correctly
    // refuse its channels, so the stream is created only after a role row is
    // present.
    _channels = null;
    _role = _repository.watchMyRole(widget.serverId);
    // The roster read that earns a `Moderator` badge in a thread. It fails
    // closed to an empty set, so an unread or denied roster simply badges
    // nobody.
    _moderators = _repository.watchModerators(widget.serverId);
  }

  @override
  void didUpdateWidget(ServerWorkspaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isVisible != widget.isVisible) {
      oldWidget.isVisible?.removeListener(_onVisibilityChanged);
      widget.isVisible?.addListener(_onVisibilityChanged);
    }
    if (oldWidget.questionAttention != widget.questionAttention) {
      final previous = oldWidget.questionAttention ?? _ownAttention;
      previous
        ?..removeListener(_onAttention)
        ..release(oldWidget.serverId);
      if (widget.questionAttention != null) {
        _ownAttention?.dispose();
        _ownAttention = null;
      }
      _attention
        ..claim(widget.serverId)
        ..addListener(_onAttention)
        ..trackDirectory(_myServers);
    } else if (oldWidget.serverId != widget.serverId) {
      _attention
        ..release(oldWidget.serverId)
        ..claim(widget.serverId);
    }
    if (oldWidget.serverId != widget.serverId) {
      _selectedId = widget.initialChannelId;
      _localTab = 0;
      _home = null;
      _meetingTab = ServerMeetingTab.presentation;
      _joinRequestId = null;
      _joining = false;
      _joinError = null;
      // A conversation belongs to the server it was joined in.
      _session.leave();
      _listen();
    }
  }

  @override
  void dispose() {
    // The dock lives in this shell; leaving the shell ends the
    // conversation instead of keeping a microphone open behind no UI.
    widget.isVisible?.removeListener(_onVisibilityChanged);
    _myServersSubscription?.cancel();
    _attention
      ..removeListener(_onAttention)
      ..release(widget.serverId);
    _ownAttention?.dispose();
    _session.dispose();
    super.dispose();
  }

  void _select(ServerChannel channel) => setState(() {
    _selectedId = channel.id;
    _localTab = 0;
    _home = false;
    // Another channel is another meeting; its view starts where board 04
    // starts rather than on the tab the previous one happened to be on.
    _meetingTab = ServerMeetingTab.presentation;
  });

  /// Only the family template has a board of its own (`Dom`); it is the
  /// main thing of that server's page. A held root has no runtime for it.
  static bool _hasHomeBoard(Server server) =>
      server.type == ServerType.family && !server.isHeld;

  /// A server opens on its page unless a specific channel was asked for (a
  /// deep link, a notification). A server that was just created opens on the
  /// page as well: the page is its face, and it carries the invitation.
  bool _homeSelected() =>
      _home ?? (widget.initialChannelId == null || widget.justCreated);

  void _selectHome() => setState(() {
    _home = true;
    _localTab = 0;
  });

  /// Leaves the server from its page: back to the directory that hosts this
  /// workspace inline, or off the route it was pushed as. Null when neither
  /// exists, so the cover draws no control that would lead nowhere.
  VoidCallback? _leaveAction(BuildContext context) {
    final onBack = widget.onBack;
    if (onBack != null) return onBack;
    if (!(ModalRoute.of(context)?.canPop ?? false)) return null;
    return () => Navigator.of(context).maybePop();
  }

  /// Only a server anyone may join has a link that leads somewhere for the
  /// person who receives it; every other server is entered by invitation.
  VoidCallback? _shareAction(Server server) {
    if (server.isHeld ||
        !serverAdmitsPublicJoin(server) ||
        !isSafeServerLinkId(server.id)) {
      return null;
    }
    return () => unawaited(_share(server));
  }

  Future<void> _share(Server server) async {
    final link = buildServerLink(server.id);
    // An iPad presents the share sheet as a popover and refuses to without
    // an anchor inside the view; the surface itself is always a valid one.
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize && !box.size.isEmpty
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    try {
      final override = widget.shareServer;
      if (override != null) {
        await override(link);
      } else {
        await SharePlus.instance.share(
          ShareParams(
            text: '${server.name}\n$link',
            sharePositionOrigin: origin,
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            serverActionFailureCopy(error, AppLocalizations.of(context)),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.appPalette.background,
      // No app bar of the scaffold's own: pushed as a route, the status-bar
      // inset belongs to whatever leads the surface — the route bar of a
      // state or of the wide workspace ([_routeBar]), the server page's
      // cover, or a channel's own header on a phone.
      body: SafeArea(
        top: widget.isRootTab,
        child: StreamBuilder<Server?>(
          stream: _server,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _state(context, _error(snapshot.error!));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _loadingState(context, copy);
            }
            final server = snapshot.data;
            if (server == null) {
              return _state(
                context,
                SingleChildScrollView(
                  child: YoEmptyState(
                    icon: Icons.lock_outline,
                    title: copy.text(
                      'Server unavailable',
                      'Serwer jest niedostępny',
                    ),
                    subtitle: copy.text(
                      'It may have been removed or your access may have changed.',
                      'Mógł zostać usunięty lub Twój dostęp się zmienił.',
                    ),
                  ),
                ),
              );
            }
            return StreamBuilder<ServerMemberRole?>(
              stream: _role,
              builder: (context, roleSnapshot) {
                if (roleSnapshot.connectionState == ConnectionState.waiting) {
                  return _loadingState(context, copy);
                }
                // An unreadable or absent role withholds every channel and
                // affordance. Only the two canonical public templates get an
                // admission action; every other case stays closed.
                final role = roleSnapshot.hasError ? null : roleSnapshot.data;
                if (role == null) return _membershipGate(context, server);
                final channels = _channels ??= _repository.watchChannels(
                  widget.serverId,
                );
                return StreamBuilder<List<ServerChannel>>(
                  stream: channels,
                  builder: (context, channelsSnapshot) {
                    // Do not retain private content behind a failed/revoked
                    // read.
                    if (channelsSnapshot.hasError) {
                      return _state(context, _error(channelsSnapshot.error!));
                    }
                    if (channelsSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return _loadingState(context, copy);
                    }
                    return StreamBuilder<Set<String>>(
                      stream: _moderators,
                      initialData: const <String>{},
                      builder: (context, moderatorSnapshot) => _workspace(
                        context,
                        server,
                        channelsSnapshot.data ?? const [],
                        role,
                        moderatorSnapshot.hasError
                            ? const <String>{}
                            : moderatorSnapshot.data ?? const <String>{},
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _membershipGate(BuildContext context, Server server) {
    final publicAdmission =
        !server.isLegacy &&
        !server.isHeld &&
        server.status == 'active' &&
        server.privacy == ServerPrivacy.public &&
        (server.type == ServerType.community ||
            server.type == ServerType.podcast);
    if (!publicAdmission) {
      final copy = AppLocalizations.of(context);
      return _state(
        context,
        SingleChildScrollView(
          child: YoEmptyState(
            icon: Icons.lock_outline,
            title: copy.text('Server unavailable', 'Serwer jest niedostępny'),
            subtitle: copy.text(
              'You are not a member of this server.',
              'Nie należysz do tego serwera.',
            ),
          ),
        ),
      );
    }
    // The server's own page with `Dołącz` as its one action (ADR-240). It
    // shows nothing a channel would: channels become readable only once the
    // member row exists.
    return LayoutBuilder(
      builder: (context, constraints) {
        final phone =
            constraints.maxWidth < ServerWorkspaceScreen.tabletBreakpoint;
        if (phone) {
          // The cover carries the way out, as it does for a member.
          return ServerPageAdmission(
            server: server,
            joining: _joining,
            error: _joinError,
            onJoin: () => _joinPublicServer(server),
            onBack: _leaveAction(context),
          );
        }
        // Wider, the route bar or the directory's `Serwery` control leads
        // out, and the page keeps its reading measure under it.
        return _state(
          context,
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: ServerHomePage.maxWidth,
              ),
              child: ServerPageAdmission(
                server: server,
                joining: _joining,
                error: _joinError,
                onJoin: () => _joinPublicServer(server),
                embedded: true,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _joinPublicServer(Server server) async {
    if (_joining) return;
    final requestId = _joinRequestId ??= _repository.newRequestId();
    setState(() {
      _joining = true;
      _joinError = null;
    });
    try {
      await _repository.joinServer(serverId: server.id, requestId: requestId);
      if (!mounted || widget.serverId != server.id) return;
      setState(() {
        _joining = false;
        // A completed operation id belongs to the membership generation it
        // created. If that membership is later revoked while this retained
        // workspace stays mounted, a new public admission needs a new id.
        // Ambiguous failures deliberately keep the old id in the catch path.
        _joinRequestId = null;
        // Re-subscribe explicitly for repositories whose role stream is a
        // point-in-time test/preview stream. Firestore's live stream would
        // update on its own, and the second subscription sees the same
        // atomic membership write.
        _role = _repository.watchMyRole(server.id);
        _channels = null;
        _moderators = _repository.watchModerators(server.id);
      });
    } catch (error) {
      if (!mounted || widget.serverId != server.id) return;
      setState(() {
        _joining = false;
        _joinError = error;
      });
    }
  }

  /// Wraps a state drawn INSTEAD of the workspace so it still has a way out.
  ///
  /// The panel's `Serwery` control and the phone header's back button both
  /// live inside [_workspace], which these states replace — so hosted inline
  /// over the directory (`isRootTab: true`, no app bar, and a shell rail that
  /// selects destinations rather than clearing this screen's own state) a
  /// deleted server, a revoked membership or a root read that errors or never
  /// answers used to leave the person on this surface with nothing to press.
  /// Switching the rail away and back rebuilds the same retained state with
  /// the same server still open, so the directory was unreachable for the
  /// rest of the app session.
  ///
  /// Pushed as a route there is a real `AppBar` with Back, `onBack` is null,
  /// and nothing extra is drawn — the shell owns chrome exactly once.
  Widget _state(BuildContext context, Widget child) {
    if (!widget.isRootTab) return _withRouteBar(context, child);
    final onBack = widget.onBack;
    if (onBack == null) return child;
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: serverDivider(context))),
          ),
          child: Row(
            children: [
              IconButton(
                key: const ValueKey('server-state-back'),
                onPressed: onBack,
                tooltip: copy.serversTitle,
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: palette.textSecondary,
                ),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  copy.serversTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleMedium.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  /// The pushed route's own bar: a real `AppBar` with Back, drawn above a
  /// state and above the tablet and desktop workspace. The phone's server
  /// page and channel view carry their own way back instead.
  Widget _withRouteBar(BuildContext context, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppBar(title: Text(AppLocalizations.of(context).serversTitle)),
      Expanded(
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: child,
        ),
      ),
    ],
  );

  /// The wait before the server, the role and the channels answer.
  ///
  /// On a phone route it keeps the way out exactly where the page's cover
  /// will put it, so the surface does not show an app bar for a moment and
  /// then swap it for a cover. Every other host keeps the state's own bar.
  Widget _loadingState(BuildContext context, AppLocalizations copy) {
    if (widget.isRootTab) return _state(context, _loading(copy));
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= ServerWorkspaceScreen.tabletBreakpoint) {
          return _state(context, _loading(copy));
        }
        final leave = _leaveAction(context);
        return Stack(
          children: [
            Positioned.fill(child: _loading(copy)),
            if (leave != null)
              PositionedDirectional(
                top:
                    MediaQuery.paddingOf(context).top +
                    8 -
                    ServerPageCoverButton.overhang,
                start: 12 - ServerPageCoverButton.overhang,
                child: ServerPageCoverButton(
                  key: const ValueKey('server-page-back'),
                  icon: Icons.arrow_back_rounded,
                  tooltip: copy.serversTitle,
                  onPressed: leave,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _loading(AppLocalizations copy) => Center(
    child: Semantics(
      label: copy.text('Loading server', 'Wczytywanie serwera'),
      child: const CircularProgressIndicator(),
    ),
  );

  Widget _error(Object error) => SingleChildScrollView(
    child: YoErrorState(error: error, onRetry: () => setState(_listen)),
  );

  ServerChannel? _selected(Server server, List<ServerChannel> channels) =>
      channels.where((channel) => channel.id == _selectedId).firstOrNull ??
      channels
          .where((channel) => channel.id == server.defaultChannelId)
          .firstOrNull ??
      channels.firstOrNull;

  Widget _workspace(
    BuildContext context,
    Server server,
    List<ServerChannel> channels,
    ServerMemberRole? role,
    Set<String> moderators,
  ) {
    final home = _homeSelected();
    final selected = home ? null : _selected(server, channels);
    // The live role and channel list answer for this server; the directory's
    // guess steps aside while it is open.
    _attention.pin(
      server.id,
      questionsChannelId: _hostedQuestions(server, channels, role)?.id,
    );
    final waitingQuestions = _waitingQuestions(server);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final phone = width < ServerWorkspaceScreen.tabletBreakpoint;
        final desktop = width >= ServerWorkspaceScreen.desktopBreakpoint;
        // Board 04's meeting. The integration seam keeps its own scene, so a
        // host that supplies one is never overridden by a template.
        final meeting =
            selected != null &&
            widget.channelBuilder == null &&
            _isCompanyMeeting(server, selected);
        final dock = ServerConversationDock(
          controller: _session,
          compact: phone,
          onOpenChannel: _select,
          screenShare: _session.screenShare,
          canModerateSession: role?.canModerate ?? false,
          // The channel document itself, so the dock can read the server's
          // own start instant for the clock. It is handed over as data
          // because the shell does not rebuild when a session connects —
          // the dock listens to the session and decides for itself.
          meetingChannel: meeting ? selected : null,
          // A phone shows the whiteboard as a card in the meeting itself, so
          // only the widths that have the tab get the control that selects it.
          onOpenWhiteboard: meeting && !phone
              ? () => setState(() => _meetingTab = ServerMeetingTab.whiteboard)
              : null,
        );
        // The server page (ADR-240): what the server opens on, and where the
        // phone returns to from a channel.
        Widget page({required bool embedded}) => ServerHomePage(
          key: ValueKey('server-page-${server.id}'),
          server: server,
          channels: channels,
          session: _session,
          repository: _repository,
          role: role,
          onOpenChannel: _select,
          onOpenAllChannels: () =>
              _openChannels(context, server, role).ignore(),
          onInvite: _inviteAction(context, server, role),
          onShare: _shareAction(server),
          onBack: embedded ? null : _leaveAction(context),
          onMore: embedded
              ? null
              : () => _openPageMenu(context, server, channels, role).ignore(),
          embedded: embedded,
          intro: widget.justCreated
              ? _InviteIntroduction(
                  server: server,
                  onInvite: _inviteAction(context, server, role),
                )
              : null,
          // The family's `Dom` is that template's main thing. It is measured
          // against the column it actually gets, so a narrow centre keeps the
          // phone's tighter board.
          board: _hasHomeBoard(server)
              ? LayoutBuilder(
                  builder: (context, box) => ServerFamilyBoard(
                    server: server,
                    channels: channels,
                    session: _session,
                    role: role,
                    onOpenChannel: _select,
                    checkIns: _familyCheckIns,
                    memories: _familyMemories,
                    currentUserId: _repository.currentUserId,
                    compact: box.maxWidth < _familyBoardWideWidth,
                    embedded: true,
                  ),
                )
              : null,
          questionsWaitingChannelId: waitingQuestions,
        );
        // Board 02's phone surface keeps the broadcast on screen above the
        // conversation, so the stage owns the whole surface there instead of
        // becoming one of the shell's scene tabs.
        final communityStage =
            phone && selected != null && _isCommunityStage(server, selected);
        final podcastStage =
            phone && selected != null && _isPodcastStage(server, selected);
        final centre = selected == null
            ? _noChannels(context)
            : communityStage
            ? ServerCommunityStage(
                key: ValueKey('server-community-${selected.id}'),
                server: server,
                channel: selected,
                session: _session,
                role: role,
                channels: channels,
                onOpenChannel: _select,
                chat: _contextThread(
                  context,
                  server,
                  channels,
                  selected,
                  role,
                  moderators,
                  phone: true,
                ),
                onOpenChannels: () =>
                    _openChannels(context, server, role).ignore(),
                followRepository: _followRepository,
                shareServer: widget.shareServer,
                compact: true,
              )
            : meeting
            // Board 04's meeting is mounted here rather than inside
            // `ServerChannelScene` at every width: its views are the shell's
            // own state (the dock selects one), and the conversation it puts
            // in a tab is the one the shell already owns.
            ? ServerCompanyMeeting(
                key: ValueKey('server-meeting-${selected.id}'),
                server: server,
                channel: selected,
                session: _session,
                role: role,
                channels: channels,
                onOpenChannel: _select,
                tab: _meetingTab,
                onTabSelected: (tab) => setState(() => _meetingTab = tab),
                whiteboardRepository: _whiteboardRepository,
                // Tablet and phone have nowhere else for the conversation;
                // a desktop keeps it permanently in the context panel.
                chat: desktop || phone
                    ? null
                    : _contextThread(
                        context,
                        server,
                        channels,
                        selected,
                        role,
                        moderators,
                        phone: false,
                      ),
                // The tiles move into the context panel on a desktop, beside
                // the conversation, exactly as board 04 arranges them.
                showParticipants: !desktop,
                compact: phone,
              )
            : _scene(
                context,
                server,
                selected,
                role,
                channels,
                moderators,
                compact: phone,
              );
        if (phone && home) {
          // The page is the whole surface: its cover carries the way out and
          // the menu, and it takes the status-bar inset itself.
          return Column(
            children: [
              Expanded(child: page(embedded: false)),
              dock,
            ],
          );
        }
        if (phone) {
          // A media channel keeps one switch between its scene and the
          // conversation beside it, which a wider layout shows side by side.
          // Everything that used to be a destination in this strip — the
          // channel list, the events, the family's board, calendar and
          // album — is on the server page now.
          final localTabs =
              communityStage || selected == null || !selected.kind.isMedia
              ? const <ServerLocalTab>[]
              : _sceneTabs(
                  context,
                  server,
                  selected,
                  channels,
                  phone: true,
                  waitingQuestions: waitingQuestions,
                );
          final surface = SafeArea(
            bottom: false,
            child: Column(
              children: [
                Expanded(
                  child: _PhoneSurface(
                    server: server,
                    selected: selected,
                    onBack: _selectHome,
                    onChannels: () => _openChannels(context, server, role),
                    // The community stage's own strip owns the entry to the
                    // channel list, so it is offered exactly once.
                    showChannelsButton: !communityStage,
                    // The Questions row waits inside the channel list; its
                    // way in says so, unless the Questions board is already
                    // on screen or a closer `Pytania` tab carries the dot.
                    channelsWaiting:
                        waitingQuestions != null &&
                        selected?.id != waitingQuestions &&
                        !localTabs.any((tab) => tab.attentionLabel != null),
                    tabs: localTabs.isEmpty
                        ? null
                        : _tabStrip(
                            context,
                            server,
                            localTabs,
                            _localTab,
                            (index) => setState(() => _localTab = index),
                          ),
                    centre: localTabs.isEmpty || _localTab == 0
                        ? centre
                        : _contextThread(
                            context,
                            server,
                            channels,
                            selected,
                            role,
                            moderators,
                            phone: true,
                          ),
                    // The stage carries the channel's name and its live
                    // state itself, directly under the picture; the shell's
                    // header above it would say the same thing twice.
                    showChannelHeader:
                        !communityStage &&
                        !podcastStage &&
                        (localTabs.isEmpty || _localTab == 0),
                  ),
                ),
                dock,
              ],
            ),
          );
          // One level of Back belongs to the channel view: system Back and
          // the leading-edge swipe return to the server page first, and from
          // the page they leave the server, as before.
          //
          // The claim is an [EmbeddedBackScope], not a bare `PopScope`: hosted
          // inline in the shell this view shares the shell's route, where a
          // refused pop calls every pop entry — a bare scope would return to
          // the page AND move the shell's tab history on one Back. It is also
          // dropped while the hosting slot is off screen, so a retained,
          // hidden workspace never holds the route (or swallows a Back meant
          // for the tab on screen).
          //
          // Holding the route switches Flutter's own Cupertino back swipe
          // off, so the swipe is given back by the same edge detector the
          // shell uses for its retained tabs.
          Widget channelView(bool visible) => EmbeddedBackScope(
            claimed: visible,
            onBack: _selectHome,
            child: YoEdgeBackGesture(
              enabled: visible,
              navigationIdentity: selected?.id ?? '',
              onBack: _selectHome,
              child: surface,
            ),
          );
          final visibility = widget.isVisible;
          return visibility == null
              ? channelView(true)
              : ValueListenableBuilder<bool>(
                  valueListenable: visibility,
                  builder: (context, visible, _) => channelView(visible),
                );
        }
        final wideDesktop = width >= ServerWorkspaceScreen.wideDesktopWidth;
        final panelWidth = wideDesktop
            ? ServerWorkspaceScreen.wideDesktopChannelColumnWidth
            : desktop
            ? ServerWorkspaceScreen.desktopChannelColumnWidth
            : ServerWorkspaceScreen.tabletChannelColumnWidth;
        final contextWidth = wideDesktop ? 360.0 : 320.0;
        // Beside the page a desktop keeps the server's conversation in view;
        // beside a media scene, the conversation that belongs to it. A host
        // that supplies its own scenes (the integration seam) keeps the page
        // without a conversation the seam never mounted.
        final showContextPanel =
            desktop &&
            ((home && widget.channelBuilder == null) ||
                (selected != null && selected.kind.isMedia));
        // The meeting owns its own strip (`Prezentacja | Tablica | Czat`), so
        // the shell does not put a second one above it.
        final wideTabs =
            selected == null || desktop || !selected.kind.isMedia || meeting
            ? const <ServerLocalTab>[]
            : _sceneTabs(
                context,
                server,
                selected,
                channels,
                phone: false,
                waitingQuestions: waitingQuestions,
              );
        final workspace = Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ServerRail(
                    servers: _railServers(server),
                    selectedId: server.id,
                    onOpen: _openServer,
                    questionsWaiting: _attention.isWaiting,
                  ),
                  VerticalDivider(width: 1, color: serverDivider(context)),
                  SizedBox(
                    width: panelWidth,
                    child: ServerPanel(
                      server: server,
                      channels: channels,
                      selectedId: selected?.id,
                      role: role,
                      onSelected: _select,
                      onInvite: _inviteAction(context, server, role),
                      onAddChannel: _addChannelAction(context, server, role),
                      onManage: _manageAction(context, server, channels, role),
                      labelledSettings: true,
                      onBack: widget.onBack,
                      connectedChannelId: _session.isActive
                          ? _session.channel?.id
                          : null,
                      session: _session,
                      onJoin: (channel) {
                        _select(channel);
                        _session.join(server, channel);
                      },
                      // The family keeps its `Rodzinny pulpit` row, which is
                      // the page too and carries the selection for it; every
                      // other template's page is selected on the header.
                      onHome: _hasHomeBoard(server) ? _selectHome : null,
                      homeSelected: home,
                      onOpenPage: _selectHome,
                      pageSelected: home && !_hasHomeBoard(server),
                      questionsWaitingChannelId: waitingQuestions,
                    ),
                  ),
                  VerticalDivider(width: 1, color: serverDivider(context)),
                  Expanded(
                    child: home
                        // The page keeps a reading measure of its own and
                        // sits at the top of the centre column.
                        ? Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: ServerHomePage.maxWidth,
                              ),
                              child: page(embedded: true),
                            ),
                          )
                        // The panel and the context column are fixed; the
                        // centre used to take everything else, so at 1920 the
                        // meeting put a 1 230-px tab bar around an 816-px
                        // presentation slot. The shell (1 136) and the
                        // configuration screen (1 012) already hold a measure,
                        // and so does the servers directory, which uses this
                        // exact token — the workspace was the one surface that
                        // did not.
                        : ResponsiveContentFrame(
                            width: ResponsiveContentWidth.dashboard,
                            child: _Centre(
                              header: selected == null
                                  ? null
                                  : ServerChannelHeader(
                                      server: server,
                                      channel: selected,
                                    ),
                              intro: widget.justCreated
                                  ? _InviteIntroduction(
                                      server: server,
                                      onInvite: _inviteAction(
                                        context,
                                        server,
                                        role,
                                      ),
                                    )
                                  : null,
                              // Tablet: the context is a local tab.
                              tabs: wideTabs.isEmpty
                                  ? null
                                  : _tabStrip(
                                      context,
                                      server,
                                      wideTabs,
                                      _localTab,
                                      (index) =>
                                          setState(() => _localTab = index),
                                    ),
                              body: wideTabs.isEmpty || _localTab == 0
                                  ? centre
                                  : _contextThread(
                                      context,
                                      server,
                                      channels,
                                      selected,
                                      role,
                                      moderators,
                                      phone: false,
                                    ),
                            ),
                          ),
                  ),
                  if (showContextPanel) ...[
                    VerticalDivider(width: 1, color: serverDivider(context)),
                    SizedBox(
                      width: contextWidth,
                      child: _contextThread(
                        context,
                        server,
                        channels,
                        selected,
                        role,
                        moderators,
                        phone: false,
                        titled: true,
                        // Board 04 puts the meeting's tiles above the
                        // conversation in this column. They are the
                        // provider's own roster, so the block is simply not
                        // there until this device is in the meeting.
                        above: meeting
                            ? _MeetingPeoplePanel(
                                server: server,
                                session: _session,
                              )
                            : null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            dock,
          ],
        );
        // Pushed as a route at tablet or desktop width, the workspace keeps
        // the route's own bar with Back, as it always had.
        return widget.isRootTab ? workspace : _withRouteBar(context, workspace);
      },
    );
  }

  /// From this centre width the family's board uses its roomier arrangement.
  static const _familyBoardWideWidth = 620.0;

  /// The phone page's `⋯`: the server-level actions that are not already a
  /// button on the page — the channel list, a new channel and the settings —
  /// each offered only to a role its callable accepts.
  Future<void> _openPageMenu(
    BuildContext context,
    Server server,
    List<ServerChannel> channels,
    ServerMemberRole? role,
  ) async {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final addChannel = _addChannelAction(context, server, role);
    final manage = _manageAction(context, server, channels, role);
    final picked = await showModalBottomSheet<_PageMenuAction>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(context),
      builder: (sheetContext) {
        Widget item(_PageMenuAction action, IconData icon, String label) =>
            ListTile(
              key: ValueKey('server-page-menu-${action.name}'),
              minTileHeight: 56,
              leading: Icon(icon, color: palette.textSecondary),
              title: Text(label),
              onTap: () => Navigator.of(sheetContext).pop(action),
            );
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                item(
                  _PageMenuAction.channels,
                  Icons.format_list_bulleted_rounded,
                  copy.serverChannels,
                ),
                if (addChannel != null)
                  item(
                    _PageMenuAction.addChannel,
                    Icons.add_rounded,
                    copy.serverAddChannel,
                  ),
                if (manage != null)
                  item(
                    _PageMenuAction.settings,
                    Icons.settings_outlined,
                    copy.serverSettings,
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || !context.mounted) return;
    switch (picked) {
      case _PageMenuAction.channels:
        await _openChannels(context, server, role);
      case _PageMenuAction.addChannel:
        addChannel?.call();
      case _PageMenuAction.settings:
        manage?.call();
      case null:
        break;
    }
  }

  Widget _noChannels(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return SingleChildScrollView(
      child: YoEmptyState(
        icon: Icons.tag_rounded,
        title: copy.serverNoChannels,
        subtitle: copy.serverNoChannelsBody,
      ),
    );
  }

  /// Board 02's broadcast, the one media channel with a scene of its own.
  static bool _isCommunityStage(Server server, ServerChannel channel) =>
      server.type == ServerType.community &&
      channel.kind == ServerChannelKind.stage &&
      !server.isHeld;

  /// Board 04's `Spotkanie zespołu`. Unlike the two stages it is mounted by
  /// the shell at every width: its views are shell state (the dock's
  /// `Tablica` selects one) and one of them is the shell's own conversation.
  /// A held root keeps the ordinary held scene, exactly as every other
  /// template does.
  static bool _isCompanyMeeting(Server server, ServerChannel channel) =>
      server.type == ServerType.company &&
      channel.kind == ServerChannelKind.meeting &&
      !server.isHeld;

  /// Board 05's studio. Like board 02's broadcast it carries its own name and
  /// live line on the phone: the shell's header sits in a scrolling block
  /// bounded to half the surface, and with a dock on screen at 200 % text
  /// that block cuts straight through the `NA ŻYWO` pill.
  static bool _isPodcastStage(Server server, ServerChannel channel) =>
      server.type == ServerType.podcast &&
      channel.kind == ServerChannelKind.stage &&
      !server.isHeld;

  Widget _scene(
    BuildContext context,
    Server server,
    ServerChannel channel,
    ServerMemberRole? role,
    List<ServerChannel> channels,
    Set<String> moderators, {
    bool compact = false,
  }) {
    final builder = widget.channelBuilder;
    if (builder != null && !server.isHeld) {
      return KeyedSubtree(
        key: ValueKey('${server.id}/${channel.id}'),
        child: builder(context, server, channel),
      );
    }
    if (_isEventsChannel(server, channel) &&
        _repository is ServerEventsRepository &&
        !server.isHeld) {
      return ServerEventsBoard(
        server: server,
        channel: channel,
        repository: _repository,
        role: role,
        currentUserId: _repository.currentUserId,
      );
    }
    if (server.type == ServerType.family &&
        channel.kind == ServerChannelKind.list &&
        !server.isHeld) {
      return ServerSharedListBoard(
        serverId: server.id,
        channel: channel,
        repository: _sharedList,
        colors: ServerIdentity.of(
          server.type,
        ).resolve(Theme.of(context).brightness),
        role: role,
        compact: compact,
      );
    }
    if (server.type == ServerType.family &&
        channel.kind == ServerChannelKind.memories &&
        !server.isHeld) {
      return ServerFamilyMemoryAlbum(
        serverId: server.id,
        channelId: channel.id,
        repository: _familyMemories,
        currentUserId: _repository.currentUserId,
        role: role,
        colors: ServerIdentity.of(
          server.type,
        ).resolve(Theme.of(context).brightness),
        serverHeld: server.isHeld,
        compact: compact,
      );
    }
    if (server.type == ServerType.podcast &&
        channel.kind == ServerChannelKind.questions &&
        !server.isHeld) {
      return ServerPodcastQuestionsBoard(
        server: server,
        channel: channel,
        repository: _repository,
        role: role,
        compact: compact,
        isVisible: widget.isVisible,
      );
    }
    if (server.type == ServerType.podcast &&
        channel.kind == ServerChannelKind.episodes &&
        !server.isHeld) {
      final repository = _podcastEpisodes;
      if (repository == null) {
        return Center(
          child: Text(
            AppLocalizations.of(context).serverActionUnavailable,
            key: const ValueKey('server-podcast-episodes-unavailable'),
          ),
        );
      }
      return ServerPodcastEpisodesBoard(
        server: server,
        channel: channel,
        repository: repository,
        role: role,
        compact: compact,
      );
    }
    if (server.type == ServerType.company &&
        channel.kind == ServerChannelKind.whiteboard &&
        !server.isHeld) {
      final repository = _whiteboardRepository;
      if (repository == null) {
        return Center(
          child: Text(AppLocalizations.of(context).serverActionUnavailable),
        );
      }
      return ServerWhiteboardBoard(
        server: server,
        channel: channel,
        repository: repository,
        liveTransport: _session,
        role: role,
        compact: compact,
      );
    }
    if (server.type == ServerType.company &&
        channel.kind == ServerChannelKind.files &&
        !server.isHeld) {
      return ServerCompanyFilesBoard(
        server: server,
        channel: channel,
        repository: _companyFiles,
        role: role,
        compact: compact,
      );
    }
    return ServerChannelScene(
      server: server,
      channel: channel,
      session: _session,
      role: role,
      currentUserId: _repository.currentUserId,
      chatService: widget.chatService,
      channels: channels,
      onOpenChannel: _select,
      moderatorIds: moderators,
      followRepository: server.type == ServerType.community
          ? _followRepository
          : null,
      podcastEpisodeRepository: server.type == ServerType.podcast
          ? _podcastEpisodes
          : null,
      shareServer: widget.shareServer,
      compact: compact,
    );
  }

  static bool _isEventsChannel(Server server, ServerChannel channel) =>
      switch (server.type) {
        ServerType.friends ||
        ServerType.community ||
        ServerType.podcast => channel.kind == ServerChannelKind.events,
        ServerType.family => channel.kind == ServerChannelKind.calendar,
        ServerType.company => false,
      };

  /// The conversation beside a media scene: the server's default text
  /// channel, read and written through the same club message path.
  Widget _contextThread(
    BuildContext context,
    Server server,
    List<ServerChannel> channels,
    ServerChannel? beside,
    ServerMemberRole? role,
    Set<String> moderators, {
    required bool phone,
    bool titled = false,
    Widget? above,
  }) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final thread = serverContextThreadChannel(
      server,
      channels,
      prefer: _contextThreadPreference(server, beside),
    );
    if (thread == null) {
      return SingleChildScrollView(
        child: YoEmptyState(
          icon: Icons.forum_outlined,
          title: copy.serverNoChannels,
          subtitle: copy.serverNoChannelsBody,
          compact: true,
        ),
      );
    }
    final podcastQuestions =
        server.type == ServerType.podcast &&
        beside?.kind == ServerChannelKind.stage &&
        thread.kind == ServerChannelKind.questions &&
        !server.isHeld;
    final scene = podcastQuestions
        ? KeyedSubtree(
            key: ValueKey('server-context-${thread.id}'),
            child: ServerPodcastQuestionsBoard(
              server: server,
              channel: thread,
              repository: _repository,
              role: role,
              compact: true,
              isVisible: widget.isVisible,
            ),
          )
        : ServerTextChannelScene(
            key: ValueKey('server-context-${thread.id}'),
            server: server,
            channel: thread,
            currentUserId: _repository.currentUserId,
            chatService: widget.chatService,
            moderatorIds: moderators,
            compact: true,
          );
    if (!titled) return scene;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        key: const ValueKey('server-context-panel'),
        children: [
          // The tiles are the flexible half of this column and the
          // conversation is the fixed one: a composer (or the read-only line
          // in its place) cannot shrink, and at 200 % text a roster holding a
          // flat 320 px left the thread 99 px and overflowed it by 100. The
          // block keeps its own 320 px ceiling and yields a share of the
          // column below that, scrolling inside whatever it gets.
          if (above != null)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight.isFinite
                    ? constraints.maxHeight * _contextAboveShare
                    : double.infinity,
              ),
              child: above,
            ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: serverDivider(context))),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.forum_outlined,
                  size: 20,
                  color: palette.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    // Boards 01 and 03 title this "Czat salonu"; the real
                    // channel is named next to it so the heading describes
                    // the place without renaming what is actually being read.
                    '${_threadHeading(copy, server, beside)} · #${thread.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.titleSmall.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: scene),
        ],
      ),
    );
  }

  /// How much of the context column the meeting's tiles may take before the
  /// conversation under them starts paying for it.
  static const _contextAboveShare = .32;

  /// Board 05 reads its listeners' questions beside the studio, and that is a
  /// real channel of its own (`questions`), not the podcast's discussion
  /// channel. Every other scene keeps the server's default conversation.
  static ServerChannelKind? _contextThreadPreference(
    Server server,
    ServerChannel? beside,
  ) =>
      server.type == ServerType.podcast &&
          beside?.kind == ServerChannelKind.stage
      ? ServerChannelKind.questions
      : null;

  String _threadHeading(
    AppLocalizations copy,
    Server server,
    ServerChannel? beside,
  ) {
    if ((server.type == ServerType.friends ||
            server.type == ServerType.family) &&
        beside?.kind == ServerChannelKind.voice) {
      return copy.serverLoungeChat;
    }
    // Board 02 titles the panel beside a broadcast "Czat na żywo".
    if (server.type == ServerType.community &&
        beside?.kind == ServerChannelKind.stage) {
      return copy.serverLiveChat;
    }
    // Board 05 titles the panel beside the studio "Pytania słuchaczy".
    if (server.type == ServerType.podcast &&
        beside?.kind == ServerChannelKind.stage) {
      return copy.serverListenerQuestions;
    }
    return copy.serverChat;
  }

  /// The local tabs of a media channel: the scene and the conversation
  /// beside it. They are two views of one channel, which a desktop shows side
  /// by side; everything that used to be a destination in this strip (the
  /// channel list, the events, the family's board) is on the server page.
  List<ServerLocalTab> _sceneTabs(
    BuildContext context,
    Server server,
    ServerChannel channel,
    List<ServerChannel> channels, {
    required bool phone,
    String? waitingQuestions,
  }) {
    final copy = AppLocalizations.of(context);
    // Board 04's phone strip: the meeting and its conversation. The scene
    // itself carries `Prezentacja` and `Tablica` as cards at this width, so
    // they are not tabs here.
    if (phone && _isCompanyMeeting(server, channel)) {
      return [
        ServerLocalTab(
          key: const ValueKey('server-tab-scene'),
          label: copy.serverChannelKindTitle(ServerChannelKind.meeting),
          icon: serverChannelIcon(channel.kind),
        ),
        ServerLocalTab(
          key: const ValueKey('server-tab-chat'),
          label: copy.serverChat,
          icon: Icons.forum_outlined,
        ),
      ];
    }
    // A scene whose conversation is not the server's ordinary chat names the
    // channel it actually reads — board 05's `Pytania` beside the studio.
    final prefer = _contextThreadPreference(server, channel);
    final conversation = prefer == null
        ? null
        : serverContextThreadChannel(server, channels, prefer: prefer);
    return serverSceneAndChatTabs(
      context,
      channel,
      conversationLabel: conversation?.kind == prefer
          ? conversation?.name
          : null,
      // Board 05's `Pytania` tab carries the host's "new questions" dot.
      attentionLabel:
          waitingQuestions != null &&
              conversation?.kind == prefer &&
              conversation?.id == waitingQuestions
          ? copy.serverQuestionsWaitingLabel
          : null,
    );
  }

  Widget _tabStrip(
    BuildContext context,
    Server server,
    List<ServerLocalTab> tabs,
    int selected,
    ValueChanged<int> onSelected,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: ServerLocalTabs(
      tabs: tabs,
      selectedIndex: selected,
      onSelected: onSelected,
      colors: ServerIdentity.of(
        server.type,
      ).resolve(Theme.of(context).brightness),
    ),
  );

  VoidCallback? _inviteAction(
    BuildContext context,
    Server server,
    ServerMemberRole? role,
  ) {
    // `createServerInviteV1` refuses a held root and non-inviter roles; the
    // affordance follows the same two facts. Who counts as an inviter depends
    // on the server as well as the role — on a server anyone may already join,
    // an ordinary member may invite too (`server_invite_authority.dart`).
    if (server.isHeld || !canInviteToServer(server, role)) return null;
    final override = widget.onInvite;
    if (override != null) return () => override(server);
    return () =>
        showServerInviteSheet(context, server: server, repository: _repository);
  }

  VoidCallback? _addChannelAction(
    BuildContext context,
    Server server,
    ServerMemberRole? role,
  ) {
    if (role == null || !role.canManage) return null;
    return () async {
      final created = await showServerCreateChannelSheet(
        context,
        server: server,
        repository: _repository,
        role: role,
      );
      if (created != null && mounted) {
        setState(() {
          _selectedId = created;
          _localTab = 0;
          // The new channel is where its creator wants to be.
          _home = false;
        });
      }
    };
  }

  VoidCallback? _manageAction(
    BuildContext context,
    Server server,
    List<ServerChannel> channels,
    ServerMemberRole? role,
  ) {
    final effectiveRole = role;
    if (effectiveRole == null ||
        !effectiveRole.canModerate ||
        _repository is! ServerManagementRepository) {
      return null;
    }
    return () async {
      final outcome = await showServerManagementSheet(
        context,
        server: server,
        channels: channels,
        role: effectiveRole,
        repository: _repository,
      );
      if (!mounted || outcome == null) return;
      final onBack = widget.onBack;
      if (onBack != null) {
        onBack();
      } else {
        await Navigator.of(this.context).maybePop();
      }
    };
  }

  /// Phone: the whole server panel as a sheet — the page's
  /// `Wszystkie kanały` and a channel's own `Kanały`.
  Future<void> _openChannels(
    BuildContext context,
    Server server,
    ServerMemberRole? role,
  ) async {
    final invite = _inviteAction(context, server, role);
    final addChannel = _addChannelAction(context, server, role);
    final railServers = _railServers(server);
    final showRail =
        railServers.length >= ServerWorkspaceScreen.phoneRailMinimumServers;
    final palette = context.appPalette;
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(context),
      // Refine-look §8.2: the sheet IS the panel's surface, so the handle
      // band no longer sits on a second tone above it (the "two-tone band");
      // a hairline marks the top edge instead (R16: the top side only).
      backgroundColor: palette.surfaceMuted,
      shape: _SheetTopEdge(side: BorderSide(color: serverDivider(context))),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .88,
        child: _WithServerRail(
          rail: showRail
              ? ListenableBuilder(
                  listenable: _attention,
                  builder: (context, _) => _ServerRail(
                    servers: railServers,
                    selectedId: server.id,
                    onOpen: (target) =>
                        Navigator.of(sheetContext).pop(_ServerRequest(target)),
                    questionsWaiting: _attention.isWaiting,
                    // One surface from the handle band down: the rail
                    // column takes the sheet's own tone instead of starting
                    // a darker, square-topped column under the band.
                    surface: palette.surfaceMuted,
                  ),
                )
              : null,
          child: StreamBuilder<List<ServerChannel>>(
            // Its own subscription: the shell's stream is single-subscription
            // and already listened to.
            stream: _repository.watchChannels(widget.serverId),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SingleChildScrollView(
                  child: YoErrorState(error: snapshot.error, compact: true),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _loading(AppLocalizations.of(context));
              }
              return ListenableBuilder(
                listenable: _attention,
                builder: (context, _) {
                  final channels = snapshot.data ?? const <ServerChannel>[];
                  final onPage = _homeSelected();
                  return ServerPanel(
                    server: server,
                    channels: channels,
                    // On the page no channel is open, so no row is marked.
                    selectedId: onPage ? null : _selectedId,
                    role: role,
                    onSelected: (channel) =>
                        Navigator.of(sheetContext).pop(channel),
                    onOpenPage: () =>
                        Navigator.of(sheetContext).pop(_SheetAction.page),
                    pageSelected: onPage,
                    onInvite: invite == null
                        ? null
                        : () => Navigator.of(
                            sheetContext,
                          ).pop(_SheetAction.invite),
                    onAddChannel: addChannel == null
                        ? null
                        : () =>
                              Navigator.of(sheetContext).pop(_SheetAction.add),
                    onManage:
                        !(role?.canModerate ?? false) ||
                            _repository is! ServerManagementRepository
                        ? null
                        : () => Navigator.of(
                            sheetContext,
                          ).pop(_ManageRequest(channels)),
                    connectedChannelId: _session.isActive
                        ? _session.channel?.id
                        : null,
                    session: _session,
                    // The sheet closes onto the channel it joins, so the join
                    // runs on the screen's own controller, not the sheet's
                    // context.
                    onJoin: (channel) =>
                        Navigator.of(sheetContext).pop(_JoinRequest(channel)),
                    questionsWaitingChannelId: _waitingQuestions(server),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (picked) {
      case ServerChannel channel:
        _select(channel);
      case _JoinRequest request:
        _select(request.channel);
        await _session.join(server, request.channel);
      case _SheetAction.invite:
        invite?.call();
      case _SheetAction.add:
        addChannel?.call();
      case _SheetAction.page:
        _selectHome();
      case _ManageRequest request:
        _manageAction(this.context, server, request.channels, role)?.call();
      case _ServerRequest request:
        _openServer(request.server);
      default:
        break;
    }
  }
}

enum _SheetAction { invite, add, page }

/// What the phone page's `⋯` menu can open.
enum _PageMenuAction { channels, addChannel, settings }

class _ManageRequest {
  const _ManageRequest(this.channels);
  final List<ServerChannel> channels;
}

/// A `Dołącz` pressed on a channel row inside the phone sheet.
class _ServerRequest {
  const _ServerRequest(this.server);
  final Server server;
}

/// The server rail: the account's servers as [YoServerRailItem] squircles in
/// a 64 px column. No unread badge or counter: server channels have no read
/// cursor (ADR-209). The one mark is the shared waiting dot on another
/// podcast server whose listener questions this host has not seen — that has
/// a real cursor behind it (ADR "listener questions dot"). The open server
/// shows its own inside the workspace instead.
class _ServerRail extends StatelessWidget {
  const _ServerRail({
    required this.servers,
    required this.selectedId,
    required this.onOpen,
    this.questionsWaiting,
    this.surface,
  });
  final List<Server> servers;
  final String selectedId;
  final ValueChanged<Server> onOpen;
  final bool Function(String serverId)? questionsWaiting;

  /// The column's fill: the canvas beside the desktop panel (null), the
  /// sheet's own surface inside the phone's `Kanały` sheet.
  final Color? surface;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Material(
      color: surface ?? context.appPalette.background,
      child: SizedBox(
        width: ServerWorkspaceScreen.serverRailWidth,
        child: ListView.separated(
          key: const ValueKey('server-rail'),
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: servers.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final server = servers[index];
            return YoServerRailItem(
              key: ValueKey('server-rail-${server.id}'),
              initial: server.initial,
              type: server.type,
              semanticLabel: server.name.isEmpty
                  ? copy.serversTitle
                  : server.name,
              selected: server.id == selectedId,
              onTap: () => onOpen(server),
              attention:
                  server.id != selectedId &&
                      (questionsWaiting?.call(server.id) ?? false)
                  ? ServerWaitingDot(
                      key: ValueKey(
                        'server-rail-questions-waiting-${server.id}',
                      ),
                      semanticLabel: copy.serverQuestionsWaitingLabel,
                    )
                  : null,
            );
          },
        ),
      ),
    );
  }
}

/// The `Kanały` sheet's shape (refine-look R16): the 28 px rounded top of a
/// sheet, with its hairline on the top side only. A
/// `RoundedRectangleBorder` side would also ring the sides and the bottom
/// wherever the sheet is narrower than the screen. The top edge thins out
/// around the corners, as a light catching the rim would.
class _SheetTopEdge extends OutlinedBorder {
  const _SheetTopEdge({super.side});

  static const _radius = BorderRadius.vertical(top: Radius.circular(28));
  static const _shape = RoundedRectangleBorder(borderRadius: _radius);

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.only(top: side.strokeInset);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _shape.getInnerPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _shape.getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    Border(
      top: side,
    ).paint(canvas, rect, textDirection: textDirection, borderRadius: _radius);
  }

  @override
  _SheetTopEdge copyWith({BorderSide? side}) =>
      _SheetTopEdge(side: side ?? this.side);

  @override
  ShapeBorder scale(double t) => _SheetTopEdge(side: side.scale(t));

  @override
  bool operator ==(Object other) =>
      other is _SheetTopEdge && other.side == side;

  @override
  int get hashCode => side.hashCode;
}

/// The phone sheet's body with the rail beside it, when there is one.
class _WithServerRail extends StatelessWidget {
  const _WithServerRail({required this.rail, required this.child});
  final Widget? rail;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final rail = this.rail;
    if (rail == null) return child;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        rail,
        VerticalDivider(width: 1, color: serverDivider(context)),
        Expanded(child: child),
      ],
    );
  }
}

class _JoinRequest {
  const _JoinRequest(this.channel);
  final ServerChannel channel;
}

/// Header + optional intro + optional local tabs + the scene, with the
/// header area bounded so a long intro at 200 % never starves the scene.
class _Centre extends StatelessWidget {
  const _Centre({required this.body, this.header, this.intro, this.tabs});
  final Widget? header;
  final Widget body;
  final Widget? intro;
  final Widget? tabs;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight * .45),
          // Same honest edge as the phone tier: when this block has to
          // scroll, it says so with a fade instead of cutting the header
          // through its glyphs.
          child: ServerScrollingDetails(
            fadeKey: const ValueKey('server-centre-header-fade'),
            child: Column(
              children: [
                if (intro != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: intro,
                  ),
                ?header,
                ?tabs,
              ],
            ),
          ),
        ),
        Expanded(child: body),
      ],
    ),
  );
}

/// The phone's channel view: the way back to the server page, the server's
/// name, the scene's own view switch when the channel has one, and the centre.
///
/// `Kanały` is offered exactly once: from the header pill, or — on the
/// community stage, whose strip owns that entry — from the strip itself.
class _PhoneSurface extends StatelessWidget {
  const _PhoneSurface({
    required this.server,
    required this.selected,
    required this.onBack,
    required this.onChannels,
    required this.showChannelsButton,
    required this.showChannelHeader,
    required this.centre,
    this.tabs,
    this.channelsWaiting = false,
  });
  final Server server;
  final ServerChannel? selected;

  /// Something in the channel list waits for the viewer (new listener
  /// questions), so `Kanały` carries the shared waiting dot.
  final bool channelsWaiting;

  /// Back to the server page (ADR-240). The page's own cover is what leads
  /// out of the server.
  final VoidCallback onBack;
  final VoidCallback onChannels;
  final bool showChannelsButton;
  final bool showChannelHeader;
  final Widget centre;
  final Widget? tabs;

  /// What the scene under the header keeps no matter how tall the header
  /// wants to be. Enough for a title, a line about it and the one action the
  /// surface is for.
  static double _phoneSceneFloor(double height) =>
      height.isFinite ? (height * .28).clamp(0.0, height) : 0;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
    final tonal = AppFinish.tonalNeutral(
      palette,
      highContrast: MediaQuery.highContrastOf(context),
    );
    final channel = selected;
    // Board 03 states the family's real boundary on the phone header, beside
    // a lock; every other template keeps the member line it already had.
    final family = server.type == ServerType.family;
    final locked = family && server.privacy == ServerPrivacy.inviteOnly;
    final subtitle = family
        ? '${copy.serverMembers(server.memberCount)} · '
              '${copy.serverPrivacyTitle(server.privacy)}'
        : copy.serverMembersInServer(server.memberCount);
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          ConstrainedBox(
            // The header used to be capped at exactly half the surface inside
            // a plain scroll view, so at 320 px / 200 % text the channel
            // title was cut horizontally through its glyphs and its subtitle
            // vanished. The cap is now expressed as what the SCENE needs
            // rather than as a fraction of the surface: the header takes its
            // natural height as long as the scene keeps a floor, which at
            // every reported failing size is enough to show it whole. When it
            // genuinely cannot fit, `ServerScrollingDetails` gives the cut the
            // faded edge this slice already uses everywhere else instead of a
            // hard slice.
            constraints: BoxConstraints(
              maxHeight:
                  constraints.maxHeight -
                  _phoneSceneFloor(constraints.maxHeight),
            ),
            child: ServerScrollingDetails(
              fadeKey: const ValueKey('server-phone-header-fade'),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: serverDivider(context)),
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          key: const ValueKey('server-channel-back'),
                          onPressed: onBack,
                          tooltip: copy.serverPageTitle,
                          style: IconButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            foregroundColor: palette.textSecondary,
                          ),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const SizedBox(width: 4),
                        YoServerTile(
                          initial: server.initial,
                          type: server.type,
                          size: 40,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // The lock rides in the name's own text flow
                              // rather than a sibling row: at 320 px and
                              // 200 % the name can be left with a few
                              // pixels, and a fixed glyph beside it would
                              // be content that cannot be seen.
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: server.name.isEmpty
                                          ? copy.serversTitle
                                          : server.name,
                                    ),
                                    if (locked)
                                      WidgetSpan(
                                        alignment: PlaceholderAlignment.middle,
                                        child: Padding(
                                          padding:
                                              const EdgeInsetsDirectional.only(
                                                start: 6,
                                              ),
                                          child: Icon(
                                            Icons.lock_outline,
                                            size: 16,
                                            color: palette.textSecondary,
                                            semanticLabel: copy
                                                .serverPrivacyTitle(
                                                  server.privacy,
                                                ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.titleMedium.copyWith(
                                  color: palette.textPrimary,
                                ),
                              ),
                              Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.bodySmall.copyWith(
                                  color: palette.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (showChannelsButton) ...[
                          const SizedBox(width: 8),
                          // Refine-look R7 neutral: glass, a control
                          // hairline and the interactive ink, keeping each
                          // widget type and the surface's own key.
                          if (largeText)
                            IconButton.outlined(
                              key: const ValueKey('server-open-channels'),
                              onPressed: onChannels,
                              tooltip: copy.serverChannels,
                              style: tonal.merge(
                                IconButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                ),
                              ),
                              icon: ServerWaitingDot.on(
                                waiting: channelsWaiting,
                                semanticLabel: copy.serverQuestionsWaitingLabel,
                                dotKey: const ValueKey(
                                  'server-open-channels-waiting',
                                ),
                                child: const Icon(Icons.tag_rounded),
                              ),
                            )
                          else
                            OutlinedButton.icon(
                              key: const ValueKey('server-open-channels'),
                              onPressed: onChannels,
                              style: tonal.merge(
                                OutlinedButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                ),
                              ),
                              icon: ServerWaitingDot.on(
                                waiting: channelsWaiting,
                                semanticLabel: copy.serverQuestionsWaitingLabel,
                                dotKey: const ValueKey(
                                  'server-open-channels-waiting',
                                ),
                                child: const Icon(Icons.tag_rounded, size: 18),
                              ),
                              label: Text(copy.serverChannels),
                            ),
                        ],
                      ],
                    ),
                  ),
                  ?tabs,
                  if (channel != null && showChannelHeader)
                    ServerChannelHeader(
                      server: server,
                      channel: channel,
                      compact: true,
                    ),
                ],
              ),
            ),
          ),
          Expanded(child: centre),
        ],
      ),
    );
  }
}

/// Board 04's tiles in the desktop context panel, above the conversation.
///
/// It is the provider's own in-session roster and nothing else: before this
/// device joins the meeting there is no roster, so the block is absent rather
/// than empty, and no count of people is printed anywhere (contract G3/G6).
class _MeetingPeoplePanel extends StatelessWidget {
  const _MeetingPeoplePanel({required this.server, required this.session});
  final Server server;
  final ServerSessionController session;

  /// The conversation underneath keeps at least its composer and a message
  /// in view: a large meeting scrolls inside this block instead of pushing
  /// the chat off the column.
  static const maxHeight = 320.0;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) {
      final people = session.participants;
      if (people.isEmpty) return const SizedBox.shrink();
      final copy = AppLocalizations.of(context);
      return Container(
        constraints: const BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: serverDivider(context))),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: ServerMeetingPeople(
            participants: people,
            colors: ServerIdentity.of(
              server.type,
            ).resolve(Theme.of(context).brightness),
            title: copy.serverMeetingPeople,
          ),
        ),
      );
    },
  );
}

/// The R2 block with the template's ink at .30 as its edge — the admission
/// and the invite introduction, the two cards that speak for the server
/// itself. High contrast: flat `surface` and `borderStrong`.
BoxDecoration _identityBlock(
  BuildContext context,
  ServerIdentityVisuals colors,
  BorderRadius radius,
) {
  final palette = context.appPalette;
  final highContrast = MediaQuery.highContrastOf(context);
  return AppFinish.block(
    palette,
    radius: radius,
    highContrast: highContrast,
  ).copyWith(
    border: Border.all(
      color: highContrast ? palette.borderStrong : colors.identityEdge,
    ),
  );
}

/// The one thing a server needs immediately after it exists: people.
///
/// The action follows the same authority as the panel's own `Zaproś`:
/// `createServerInviteV1` refuses a held root outright, so while the server
/// is being prepared the button is disabled and the card says why, rather
/// than appearing to send something that never leaves.
class _InviteIntroduction extends StatelessWidget {
  const _InviteIntroduction({required this.server, this.onInvite});
  final Server server;
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = ServerIdentity.of(
      server.type,
    ).resolve(Theme.of(context).brightness);
    return Container(
      key: const ValueKey('server-invite-introduction'),
      padding: const EdgeInsets.all(16),
      decoration: _identityBlock(context, colors, AppRadius.block),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            copy.serverInviteIntroTitle,
            style: AppTypography.titleMedium.copyWith(
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            server.isHeld
                ? copy.serverInviteHeldBody
                : copy.serverInviteIntroBody,
            style: AppTypography.bodySmall.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              key: const ValueKey('server-invite-introduction-action'),
              onPressed: onInvite,
              style: FilledButton.styleFrom(
                backgroundColor: colors.cta,
                foregroundColor: colors.onCta,
                minimumSize: const Size(48, 48),
              ).copyWith(side: serverFocusRing(colors.onCta)),
              icon: const Icon(Icons.person_add_outlined, size: 18),
              label: Text(copy.serverInvite),
            ),
          ),
        ],
      ),
    );
  }
}
