import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';

import '../../data/models/server_session.dart';
import '../../data/services/server_service.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';

enum _StageParticipantAction { stage, audience, mute, releaseMute }

/// The generation-bound controls behind a participant's overflow button.
///
/// Visibility is only an affordance: `setServerSessionParticipantRoleV1` and
/// `setServerSessionMuteV1` re-prove the caller's server hierarchy, channel
/// ACL, live generation and target participant. The provider roster does not
/// expose a target's server role or the two stored mute flags, so the client
/// never guesses either. It offers explicit apply/release commands and reports
/// the exact receipt returned by the backend.
class ServerStageParticipantMenu extends StatefulWidget {
  const ServerStageParticipantMenu({
    required this.repository,
    required this.serverId,
    required this.channelId,
    required this.sessionId,
    required this.participantId,
    required this.participantName,
    required this.participantRole,
    required this.isLocal,
    required this.viewerSessionRole,
    required this.viewerCanModerate,
    this.compact = false,
    super.key,
  });

  final ServerRepository repository;
  final String serverId;
  final String channelId;
  final String sessionId;
  final String participantId;
  final String participantName;

  /// `host | guest | listener`, or null when provider metadata failed closed.
  final String? participantRole;
  final bool isLocal;

  /// The role signed into this device's own token. A host may govern targets
  /// even when their server role is below moderator.
  final String? viewerSessionRole;

  /// The caller's canonical server role grants `moderate` on this channel.
  final bool viewerCanModerate;
  final bool compact;

  @override
  State<ServerStageParticipantMenu> createState() =>
      _ServerStageParticipantMenuState();
}

class _ServerStageParticipantMenuState
    extends State<ServerStageParticipantMenu> {
  bool _busy = false;

  bool get _canGovern =>
      widget.viewerSessionRole == 'host' || widget.viewerCanModerate;

  bool get _canChangeRole =>
      _canGovern &&
      widget.participantRole != 'host' &&
      !(widget.isLocal && widget.viewerSessionRole == 'host');

  bool get _canMute => _canGovern && !widget.isLocal;

  List<_StageParticipantAction> get _actions => [
    if (_canChangeRole)
      widget.participantRole == 'guest'
          ? _StageParticipantAction.audience
          : _StageParticipantAction.stage,
    if (_canMute) ...[
      _StageParticipantAction.mute,
      _StageParticipantAction.releaseMute,
    ],
  ];

  Future<void> _run(_StageParticipantAction action) async {
    if (_busy) return;
    final copy = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final ServerSessionParticipationResult result;
      switch (action) {
        case _StageParticipantAction.stage:
        case _StageParticipantAction.audience:
          result = await widget.repository.setSessionParticipantRole(
            serverId: widget.serverId,
            channelId: widget.channelId,
            sessionId: widget.sessionId,
            participantId: widget.participantId,
            role: action == _StageParticipantAction.stage
                ? 'guest'
                : 'listener',
            requestId: widget.repository.newRequestId(),
          );
        case _StageParticipantAction.mute:
        case _StageParticipantAction.releaseMute:
          result = await widget.repository.setSessionParticipantMute(
            serverId: widget.serverId,
            channelId: widget.channelId,
            sessionId: widget.sessionId,
            participantId: widget.participantId,
            muted: action == _StageParticipantAction.mute,
            requestId: widget.repository.newRequestId(),
          );
      }
      if (!mounted) return;
      final message = switch (action) {
        _StageParticipantAction.stage || _StageParticipantAction.audience =>
          copy.serverStageRoleChanged(widget.participantName),
        _StageParticipantAction.mute => copy.serverStageMuteApplied(
          widget.participantName,
        ),
        _StageParticipantAction.releaseMute =>
          result.isMuted
              ? copy.serverStageMuteStillActive(widget.participantName)
              : copy.serverStageMuteReleased(widget.participantName),
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            serverActionFailureCopy(
              error,
              copy,
              fallback: copy.serverStageModerationFailed,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  PopupMenuItem<_StageParticipantAction> _item(
    _StageParticipantAction action,
    AppLocalizations copy,
  ) {
    final (icon, label, suffix) = switch (action) {
      _StageParticipantAction.stage => (
        Icons.record_voice_over_rounded,
        copy.serverStageMoveToStage,
        'stage',
      ),
      _StageParticipantAction.audience => (
        Icons.hearing_rounded,
        copy.serverStageMoveToAudience,
        'audience',
      ),
      _StageParticipantAction.mute => (
        Icons.mic_off_rounded,
        copy.serverStageMuteParticipant,
        'mute',
      ),
      _StageParticipantAction.releaseMute => (
        Icons.mic_rounded,
        copy.serverStageReleaseMute,
        'release-mute',
      ),
    };
    return PopupMenuItem<_StageParticipantAction>(
      key: ValueKey('server-stage-$suffix-${widget.participantId}'),
      value: action,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions;
    if (actions.isEmpty) return const SizedBox.shrink();
    final copy = AppLocalizations.of(context);
    const size = 48.0;
    if (_busy) {
      return SizedBox.square(
        dimension: size,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return SizedBox.square(
      dimension: size,
      child: PopupMenuButton<_StageParticipantAction>(
        key: ValueKey('server-stage-participant-menu-${widget.participantId}'),
        tooltip: copy.serverStageManageParticipant(widget.participantName),
        padding: EdgeInsets.zero,
        iconSize: widget.compact ? 18 : 22,
        icon: Icon(
          Icons.more_horiz_rounded,
          color: context.appPalette.textSecondary,
        ),
        onSelected: (action) => unawaited(_run(action)),
        itemBuilder: (_) => [for (final action in actions) _item(action, copy)],
      ),
    );
  }
}
