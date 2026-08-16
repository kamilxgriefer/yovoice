import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/clubs/data/models/club_invite.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_overview_screen.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

/// A deliberately small, ungated destination for a Club invitation.
///
/// The full Clubs hub is Premium, but accepting or declining an invitation is
/// free. This screen reads the invitee-scoped canonical invite document and
/// never treats notification payload fields as authority.
class ClubInviteResponseScreen extends StatefulWidget {
  const ClubInviteResponseScreen({
    required this.clubId,
    this.firestore,
    this.auth,
    this.clubService,
    super.key,
  });

  final String clubId;
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;
  final ClubService? clubService;

  @override
  State<ClubInviteResponseScreen> createState() =>
      _ClubInviteResponseScreenState();
}

class _ClubInviteResponseScreenState extends State<ClubInviteResponseScreen> {
  late final FirebaseFirestore _firestore =
      widget.firestore ?? FirebaseFirestore.instance;
  late final FirebaseAuth _auth = widget.auth ?? FirebaseAuth.instance;
  late final ClubService _service =
      widget.clubService ?? ClubService(firestore: _firestore, auth: _auth);
  late Future<ClubInvite?> _invite = _loadInvite();
  bool _busy = false;
  String? _error;

  Future<ClubInvite?> _loadInvite() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || widget.clubId.trim().isEmpty) return null;
    final snapshot = await _firestore
        .collection('clubs')
        .doc(widget.clubId)
        .collection('invites')
        .doc(uid)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists ||
        data?['inviteeId'] != uid ||
        data?['status'] != 'pending') {
      return null;
    }
    return ClubInvite.fromFirestore(snapshot);
  }

  Future<void> _accept(ClubInvite invite) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.acceptClubInvite(invite);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (_) => ClubOverviewScreen(clubId: invite.clubId),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'This invitation could not be accepted. Please try again.';
      });
    }
  }

  Future<void> _decline(ClubInvite invite) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.declineClubInvite(invite);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _invite = Future<ClubInvite?>.value(null);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'This invitation could not be declined. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080711),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080711),
        foregroundColor: Colors.white,
        title: const Text('Club invitation'),
      ),
      body: ResponsiveContentFrame(
        width: ResponsiveContentWidth.form,
        child: FutureBuilder<ClubInvite?>(
          future: _invite,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const _InviteMessage(
                message: 'This invitation is unavailable right now.',
              );
            }
            final invite = snapshot.data;
            if (invite == null) {
              return const _InviteMessage(
                key: ValueKey('club-invite-unavailable'),
                message: 'This invitation is no longer pending.',
              );
            }
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF171121),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFF3A2C49)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 38,
                            backgroundColor: const Color(0xFF392052),
                            backgroundImage: invite.clubAvatarUrl == null
                                ? null
                                : NetworkImage(invite.clubAvatarUrl!),
                            child: invite.clubAvatarUrl == null
                                ? const Icon(
                                    Icons.groups_rounded,
                                    color: Color(0xFFD89BFF),
                                    size: 36,
                                  )
                                : null,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            invite.clubName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${invite.inviterName} invited you to join.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFA69CAF),
                              fontSize: 16,
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFFFF8FA8)),
                            ),
                          ],
                          const SizedBox(height: 24),
                          _InviteActions(
                            busy: _busy,
                            onDecline: () => _decline(invite),
                            onAccept: () => _accept(invite),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InviteActions extends StatelessWidget {
  const _InviteActions({
    required this.busy,
    required this.onDecline,
    required this.onAccept,
  });

  final bool busy;
  final VoidCallback onDecline;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final decline = OutlinedButton(
      key: const ValueKey('decline-club-invite'),
      onPressed: busy ? null : onDecline,
      child: const Text('Decline'),
    );
    final accept = FilledButton(
      key: const ValueKey('accept-club-invite'),
      onPressed: busy ? null : onAccept,
      child: Text(busy ? 'Please wait…' : 'Accept'),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        if (constraints.maxWidth < 360 || textScale > 1.3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [accept, const SizedBox(height: 10), decline],
          );
        }
        return Row(
          children: [
            Expanded(child: decline),
            const SizedBox(width: 12),
            Expanded(child: accept),
          ],
        );
      },
    );
  }
}

class _InviteMessage extends StatelessWidget {
  const _InviteMessage({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFA69CAF), fontSize: 16),
        ),
      ),
    );
  }
}
