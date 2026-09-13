import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/clubs/data/models/club_invite.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/servers/data/models/server_invite.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/servers/presentation/server_action_failure.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

import 'server_workspace_screen.dart';

typedef ServerInviteWorkspaceBuilder = Widget Function(String serverId);
typedef LegacyServerInviteAction = Future<void> Function(ClubInvite invite);

/// The pre-membership boundary for a V1 Server invitation.
///
/// Private Server roots and channels are intentionally unreadable to an
/// invitee. This screen reads only the caller-owned invitation preview, then
/// lets the callable re-prove its generation, expiry, inviter authority and
/// the current Server state before it creates any membership.
class ServerInviteResponseScreen extends StatefulWidget {
  const ServerInviteResponseScreen({
    required this.serverId,
    this.firestore,
    this.auth,
    this.service,
    this.now,
    this.workspaceBuilder,
    this.acceptLegacyInvite,
    this.declineLegacyInvite,
    super.key,
  });

  final String serverId;
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;
  final ServerService? service;
  final DateTime Function()? now;
  final ServerInviteWorkspaceBuilder? workspaceBuilder;
  final LegacyServerInviteAction? acceptLegacyInvite;
  final LegacyServerInviteAction? declineLegacyInvite;

  @override
  State<ServerInviteResponseScreen> createState() =>
      _ServerInviteResponseScreenState();
}

class _ServerInviteResponseScreenState
    extends State<ServerInviteResponseScreen> {
  late final FirebaseFirestore _firestore =
      widget.firestore ?? FirebaseFirestore.instance;
  late final FirebaseAuth _auth = widget.auth ?? FirebaseAuth.instance;
  late final ServerService _service =
      widget.service ?? ServerService(firestore: _firestore, auth: _auth);
  ClubService? _legacyService;
  late Future<_LoadedServerInvite?> _invite = _loadInvite();

  bool _busy = false;
  String? _error;
  String? _pendingRequestId;
  bool? _pendingAccept;

  DateTime get _now => (widget.now?.call() ?? DateTime.now()).toUtc();

  ClubService get _clubService =>
      _legacyService ??= ClubService(firestore: _firestore, auth: _auth);

  Future<_LoadedServerInvite?> _loadInvite() async {
    final uid = _auth.currentUser?.uid;
    final serverId = widget.serverId.trim();
    if (uid == null || !_isSafeId(serverId)) return null;
    final snapshot = await _firestore
        .collection('clubs')
        .doc(serverId)
        .collection('invites')
        .doc(uid)
        .get();
    if (!snapshot.exists) return null;
    final data = snapshot.data();
    if (data == null) return null;
    if (data['serverSchemaVersion'] == null) {
      try {
        return _LoadedServerInvite.fromLegacy(snapshot);
      } on FormatException {
        return null;
      }
    }
    try {
      final invite = ServerInvite.fromFirestore(snapshot);
      return invite.isActionableAt(_now)
          ? _LoadedServerInvite.fromV1(invite)
          : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> _respond(
    _LoadedServerInvite invite, {
    required bool accept,
  }) async {
    if (_busy) return;
    if (!invite.isActionableAt(_now)) {
      setState(() {
        _invite = Future<_LoadedServerInvite?>.value(null);
        _error = null;
      });
      return;
    }
    final v1 = invite.v1;
    final requestId = v1 == null
        ? null
        : _pendingAccept == accept && _pendingRequestId != null
        ? _pendingRequestId!
        : _service.newRequestId();
    if (v1 != null) {
      _pendingAccept = accept;
      _pendingRequestId = requestId;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final legacy = invite.legacy;
      if (v1 != null) {
        await _service.respondToInvite(
          serverId: invite.serverId,
          accept: accept,
          requestId: requestId!,
        );
      } else if (legacy != null) {
        if (accept) {
          await (widget.acceptLegacyInvite?.call(legacy) ??
              _clubService.acceptClubInvite(legacy));
        } else {
          await (widget.declineLegacyInvite?.call(legacy) ??
              _clubService.declineClubInvite(legacy));
        }
      } else {
        throw const FormatException('Malformed server invitation.');
      }
      if (!mounted) return;
      _pendingAccept = null;
      _pendingRequestId = null;
      if (!accept) {
        setState(() {
          _busy = false;
          _invite = Future<_LoadedServerInvite?>.value(null);
        });
        return;
      }
      final destination =
          widget.workspaceBuilder?.call(invite.serverId) ??
          ServerWorkspaceScreen(serverId: invite.serverId);
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(builder: (_) => destination),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = serverActionFailureCopy(
          error,
          AppLocalizations.of(context),
          invite: true,
          fallback: AppLocalizations.of(context).text(
            'This invitation changed or expired. Review it and try again.',
            'To zaproszenie zmieniło się lub wygasło. Sprawdź je i spróbuj ponownie.',
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Scaffold(
      key: const ValueKey('server-invite-response-screen'),
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        title: Text(copy.text('Server invitation', 'Zaproszenie do serwera')),
      ),
      body: ResponsiveContentFrame(
        width: ResponsiveContentWidth.form,
        child: FutureBuilder<_LoadedServerInvite?>(
          future: _invite,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _InviteMessage(
                message: copy.text(
                  'This invitation is unavailable right now.',
                  'To zaproszenie jest teraz niedostępne.',
                ),
              );
            }
            final invite = snapshot.data;
            if (invite == null) {
              return _InviteMessage(
                key: const ValueKey('server-invite-unavailable'),
                message: copy.text(
                  'This invitation is no longer active.',
                  'To zaproszenie nie jest już aktywne.',
                ),
              );
            }
            return _InviteCard(
              invite: invite,
              busy: _busy,
              error: _error,
              onAccept: () => _respond(invite, accept: true),
              onDecline: () => _respond(invite, accept: false),
            );
          },
        ),
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.invite,
    required this.busy,
    required this.error,
    required this.onAccept,
    required this.onDecline,
  });

  final _LoadedServerInvite invite;
  final bool busy;
  final String? error;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: AppRadius.xl,
            border: Border.all(color: palette.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.primaryContainer,
                ),
                child: Icon(
                  Icons.hub_rounded,
                  color: colors.onPrimaryContainer,
                  size: 36,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                invite.serverName,
                textAlign: TextAlign.center,
                style: AppTypography.headlineSmall.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                copy.template(
                  '{name} invited you to this server.',
                  '{name} zaprasza Cię do tego serwera.',
                  values: {'name': invite.inviterName},
                ),
                textAlign: TextAlign.center,
                style: AppTypography.bodyLarge.copyWith(
                  color: palette.textSecondary,
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error!,
                    key: const ValueKey('server-invite-error'),
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              if (busy)
                const SizedBox.square(
                  key: ValueKey('server-invite-busy'),
                  dimension: 32,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final vertical =
                        constraints.maxWidth < 340 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.3;
                    final decline = OutlinedButton(
                      key: const ValueKey('decline-server-invite'),
                      onPressed: onDecline,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      child: Text(copy.text('Decline', 'Odrzuć')),
                    );
                    final accept = FilledButton(
                      key: const ValueKey('accept-server-invite'),
                      onPressed: onAccept,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      child: Text(copy.text('Accept', 'Akceptuj')),
                    );
                    if (vertical) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          accept,
                          const SizedBox(height: AppSpacing.sm),
                          decline,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: decline),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: accept),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InviteMessage extends StatelessWidget {
  const _InviteMessage({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: AppTypography.bodyLarge.copyWith(
          color: context.appPalette.textSecondary,
        ),
      ),
    ),
  );
}

bool _isSafeId(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value);

class _LoadedServerInvite {
  const _LoadedServerInvite._({this.v1, this.legacy})
    : assert((v1 == null) != (legacy == null));

  factory _LoadedServerInvite.fromV1(ServerInvite invite) =>
      _LoadedServerInvite._(v1: invite);

  factory _LoadedServerInvite.fromLegacy(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final serverId = document.reference.parent.parent?.id;
    if (data == null || serverId == null) {
      throw const FormatException('Server invitation is unavailable.');
    }

    String requiredText(String field) {
      final value = data[field];
      if (value is! String || value.trim().isEmpty) {
        throw const FormatException('Malformed legacy server invitation.');
      }
      return value.trim();
    }

    if (requiredText('clubId') != serverId ||
        requiredText('inviteeId') != document.id ||
        requiredText('status') != 'pending') {
      throw const FormatException('Malformed legacy server invitation.');
    }
    requiredText('clubName');
    requiredText('inviterId');
    requiredText('inviterName');
    return _LoadedServerInvite._(legacy: ClubInvite.fromFirestore(document));
  }

  final ServerInvite? v1;
  final ClubInvite? legacy;

  String get serverId => v1?.serverId ?? legacy!.clubId;
  String get serverName => v1?.serverName ?? legacy!.clubName;
  String get inviterName => v1?.inviterName ?? legacy!.inviterName;

  bool isActionableAt(DateTime now) => v1?.isActionableAt(now) ?? true;
}
