import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';

import 'package:yovoice/features/premium/premium_gates.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/models/club_invite.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_overview_screen.dart';
import 'package:yovoice/features/clubs/presentation/screens/create_club_screen.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';

class ClubsScreen extends StatefulWidget {
  const ClubsScreen({super.key});

  @override
  State<ClubsScreen> createState() => _ClubsScreenState();
}

class _ClubsScreenState extends State<ClubsScreen> {
  static const Color _background = Color(0xFF080711);
  static const Color _surface = Color(0xFF171120);
  static const Color _surfaceLight = Color(0xFF21182C);
  static const Color _purple = Color(0xFF9D20FF);
  static const Color _muted = Color(0xFFA59BAF);

  final ClubService _clubService = ClubService();
  final Set<String> _processingInvites = <String>{};

  Future<void> _openCreateClub() async {
    if (!await PremiumGates.ensureCanCreateClub(context)) return;
    if (!mounted) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const CreateClubScreen()),
    );
    if (!mounted || created != true) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Club created successfully.')));
  }

  Future<void> _openClub(Club club) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ClubOverviewScreen(clubId: club.id),
      ),
    );
  }

  Future<void> _respondToInvite(ClubInvite invite, bool accept) async {
    if (_processingInvites.contains(invite.clubId)) return;
    setState(() => _processingInvites.add(invite.clubId));
    try {
      if (accept) {
        await _clubService.acceptClubInvite(invite);
      } else {
        await _clubService.declineClubInvite(invite);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept ? 'You joined ${invite.clubName}.' : 'Invitation declined.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _processingInvites.remove(invite.clubId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(onCreatePressed: _openCreateClub),
            Expanded(
              child: StreamBuilder<List<ClubInvite>>(
                stream: _clubService.watchMyClubInvites(),
                builder: (context, inviteSnapshot) {
                  final invites = inviteSnapshot.data ?? const <ClubInvite>[];
                  return StreamBuilder<List<Club>>(
                    stream: _clubService.watchMyClubs(),
                    builder: (context, clubSnapshot) {
                      if (clubSnapshot.connectionState ==
                              ConnectionState.waiting &&
                          !clubSnapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(color: _purple),
                        );
                      }
                      if (clubSnapshot.hasError) {
                        return _ErrorState(
                          message: friendlyErrorMessage(
                            clubSnapshot.error ?? 'unknown',
                            fallback: 'Could not load your clubs.',
                          ),
                          onRetry: () => setState(() {}),
                        );
                      }

                      final clubs = clubSnapshot.data ?? const <Club>[];
                      if (clubs.isEmpty && invites.isEmpty) {
                        return _EmptyState(onCreatePressed: _openCreateClub);
                      }

                      return RefreshIndicator(
                        color: _purple,
                        backgroundColor: _surfaceLight,
                        onRefresh: () async => setState(() {}),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(18, 10, 18, 130),
                          children: [
                            if (invites.isNotEmpty) ...[
                              const Text(
                                'Club invitations',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 12),
                              for (final invite in invites) ...[
                                _ClubInviteCard(
                                  invite: invite,
                                  busy: _processingInvites.contains(
                                    invite.clubId,
                                  ),
                                  onAccept: () =>
                                      _respondToInvite(invite, true),
                                  onDecline: () =>
                                      _respondToInvite(invite, false),
                                ),
                                const SizedBox(height: 12),
                              ],
                              const SizedBox(height: 8),
                            ],
                            if (clubs.isNotEmpty) ...[
                              _SummaryCard(clubCount: clubs.length),
                              const SizedBox(height: 18),
                              const Text(
                                'Your clubs',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 12),
                              for (final club in clubs) ...[
                                _ClubCard(
                                  club: club,
                                  onTap: () => _openClub(club),
                                ),
                                const SizedBox(height: 12),
                              ],
                            ],
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClubInviteCard extends StatelessWidget {
  const _ClubInviteCard({
    required this.invite,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  final ClubInvite invite;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final hasAvatar = invite.clubAvatarUrl?.isNotEmpty == true;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _ClubsScreenState._surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF5C3477)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: const Color(0xFF54247C),
            backgroundImage: hasAvatar
                ? NetworkImage(invite.clubAvatarUrl!)
                : null,
            child: hasAvatar
                ? null
                : Text(
                    invite.clubName.isEmpty
                        ? 'C'
                        : invite.clubName[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invite.clubName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Invited by ${invite.inviterName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _ClubsScreenState._muted),
                ),
                const SizedBox(height: 11),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: busy ? null : onDecline,
                        child: const Text('Decline'),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: FilledButton(
                        onPressed: busy ? null : onAccept,
                        style: FilledButton.styleFrom(
                          backgroundColor: _ClubsScreenState._purple,
                        ),
                        child: busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Accept'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onCreatePressed});

  final VoidCallback onCreatePressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 16, 8),
      child: Row(
        children: [
          YoIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            iconSize: 18,
            size: 40,
            backgroundColor: _ClubsScreenState._surface,
            borderColor: _ClubsScreenState._surfaceLight,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Clubs',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.7,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Your permanent communities',
                  style: TextStyle(
                    color: _ClubsScreenState._muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filled(
            onPressed: onCreatePressed,
            tooltip: 'Create club',
            style: IconButton.styleFrom(
              backgroundColor: _ClubsScreenState._purple,
              foregroundColor: Colors.white,
              minimumSize: const Size(48, 48),
            ),
            icon: const Icon(Icons.add_rounded, size: 28),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.clubCount});

  final int clubCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A175A), Color(0xFF1D112B)],
        ),
        border: Border.all(color: const Color(0xFF623287)),
        boxShadow: const [
          BoxShadow(color: Color(0x449D20FF), blurRadius: 28, spreadRadius: 1),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFF9D20FF).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.groups_2_rounded,
              color: Color(0xFFC982FF),
              size: 32,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clubCount == 1 ? '1 club joined' : '$clubCount clubs joined',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Chat, voice rooms and people that stay together.',
                  style: TextStyle(
                    color: Color(0xFFC5B8D0),
                    fontSize: 12,
                    height: 1.35,
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

class _ClubCard extends StatelessWidget {
  const _ClubCard({required this.club, required this.onTap});

  final Club club;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasBanner = club.bannerUrl?.isNotEmpty ?? false;
    final hasAvatar = club.avatarUrl?.isNotEmpty ?? false;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(
            color: _ClubsScreenState._surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF33263F)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 88,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(23),
                  ),
                  gradient: hasBanner
                      ? null
                      : const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF56227C), Color(0xFF1E1430)],
                        ),
                  image: hasBanner
                      ? DecorationImage(
                          image: NetworkImage(club.bannerUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Transform.translate(
                      offset: const Offset(0, -29),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            width: 66,
                            height: 66,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF7B2CBF),
                              border: Border.all(
                                color: _ClubsScreenState._surface,
                                width: 4,
                              ),
                              image: hasAvatar
                                  ? DecorationImage(
                                      image: NetworkImage(club.avatarUrl!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: hasAvatar
                                ? null
                                : Text(
                                    club.initial,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 26,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                          ),
                          const Spacer(),
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: club.onlineCount > 0
                                  ? const Color(0xFF173B2A)
                                  : const Color(0xFF28222E),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              club.onlineCount > 0
                                  ? '${club.onlineCount} online'
                                  : 'Quiet now',
                              style: TextStyle(
                                color: club.onlineCount > 0
                                    ? const Color(0xFF68E6A1)
                                    : const Color(0xFFA49AAA),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Transform.translate(
                      offset: const Offset(0, -18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  club.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: Color(0xFF9F94A8),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            club.description.isEmpty
                                ? 'A YO Voice club.'
                                : club.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFB5AABB),
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _MetaChip(
                                icon: Icons.people_alt_rounded,
                                text: '${club.memberCount} members',
                              ),
                              const SizedBox(width: 8),
                              _MetaChip(
                                icon: Icons.language_rounded,
                                text: club.defaultLanguage,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: _ClubsScreenState._surfaceLight,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFFBFA5D3)),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFD4CBD9),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreatePressed});

  final VoidCallback onCreatePressed;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 130),
      children: [
        Container(
          width: 112,
          height: 112,
          margin: const EdgeInsets.symmetric(horizontal: 100),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0xFFB23BFF), Color(0xFF3A1650)],
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x669D20FF), blurRadius: 36),
            ],
          ),
          child: const Icon(
            Icons.groups_2_rounded,
            color: Colors.white,
            size: 52,
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'Find your people',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 27,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Create a permanent club with members, roles, chat and a private voice lounge.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFFAEA3B5),
            fontSize: 14,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: onCreatePressed,
          style: FilledButton.styleFrom(
            backgroundColor: _ClubsScreenState._purple,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text(
            'CREATE CLUB',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.7),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: Color(0xFFFF6B8E),
              size: 46,
            ),
            const SizedBox(height: 14),
            const Text(
              'Could not load your clubs',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message.replaceFirst('Bad state: ', ''),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFA99FAC), fontSize: 12),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
