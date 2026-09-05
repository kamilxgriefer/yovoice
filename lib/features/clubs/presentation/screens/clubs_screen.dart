import 'package:flutter/material.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';

import 'package:yovoice/features/premium/premium_gates.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/models/club_invite.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_overview_screen.dart';
import 'package:yovoice/features/clubs/presentation/screens/create_club_screen.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

String _clubLanguageLabel(String language, AppLocalizations copy) {
  if (!copy.isPolish) return language;
  return switch (language) {
    'English' => 'Angielski',
    'Polish' => 'Polski',
    'Dutch' => 'Niderlandzki',
    'German' => 'Niemiecki',
    'Spanish' => 'Hiszpański',
    'French' => 'Francuski',
    'Italian' => 'Włoski',
    'Portuguese' => 'Portugalski',
    'Japanese' => 'Japoński',
    'Korean' => 'Koreański',
    _ => language,
  };
}

class ClubsScreen extends StatefulWidget {
  const ClubsScreen({this.isRootTab = false, super.key});

  /// True when this screen IS the shell's current content (a desktop
  /// content slot) rather than a pushed route — the same flag
  /// FriendsScreen uses, so a root tab never renders a back button that
  /// has nothing to pop.
  final bool isRootTab;

  @override
  State<ClubsScreen> createState() => _ClubsScreenState();
}

class _ClubsScreenState extends State<ClubsScreen> {
  final ClubService _clubService = ClubService();
  final Set<String> _processingInvites = <String>{};

  Future<void> _openCreateClub() async {
    if (!await PremiumGates.ensureCanCreateClub(context)) return;
    if (!mounted) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const CreateClubScreen()),
    );
    if (!mounted || created != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(
            context,
          ).text('Club created successfully.', 'Klub został utworzony.'),
        ),
      ),
    );
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
            accept
                ? AppLocalizations.of(context).text(
                    'You joined ${invite.clubName}.',
                    'Dołączono do ${invite.clubName}.',
                  )
                : AppLocalizations.of(
                    context,
                  ).text('Invitation declined.', 'Odrzucono zaproszenie.'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final copy = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              error,
              fallback: copy.text(
                'Could not respond to the invitation. Please try again.',
                'Nie udało się odpowiedzieć na zaproszenie. Spróbuj ponownie.',
              ),
              copy: copy,
            ),
          ),
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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    return Scaffold(
      key: const ValueKey('clubs-screen'),
      backgroundColor: palette.background,
      body: YoPageBackground(
        child: SafeArea(
          bottom: false,
          child: ResponsiveContentFrame(
            width: ResponsiveContentWidth.feed,
            alignment: ResponsiveContentAlignment.topLeft,
            child: Column(
              children: [
                _Header(
                  onCreatePressed: _openCreateClub,
                  isRootTab: widget.isRootTab,
                ),
                Expanded(
                  child: StreamBuilder<List<ClubInvite>>(
                    stream: _clubService.watchMyClubInvites(),
                    builder: (context, inviteSnapshot) {
                      final invites =
                          inviteSnapshot.data ?? const <ClubInvite>[];
                      return StreamBuilder<List<Club>>(
                        stream: _clubService.watchMyClubs(),
                        builder: (context, clubSnapshot) {
                          if (clubSnapshot.connectionState ==
                                  ConnectionState.waiting &&
                              !clubSnapshot.hasData) {
                            return Center(
                              child: CircularProgressIndicator(
                                color: colors.primary,
                              ),
                            );
                          }
                          if (clubSnapshot.hasError) {
                            return _ErrorState(
                              message: copy.isPolish
                                  ? 'Sprawdź połączenie i spróbuj ponownie.'
                                  : friendlyErrorMessage(
                                      clubSnapshot.error ?? 'unknown',
                                      fallback: 'Could not load your clubs.',
                                    ),
                              onRetry: () => setState(() {}),
                            );
                          }

                          final clubs = clubSnapshot.data ?? const <Club>[];
                          if (clubs.isEmpty && invites.isEmpty) {
                            return _EmptyState(
                              onCreatePressed: _openCreateClub,
                            );
                          }

                          return RefreshIndicator(
                            color: colors.primary,
                            backgroundColor: palette.surfaceRaised,
                            onRefresh: () async => setState(() {}),
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(
                                18,
                                10,
                                18,
                                130,
                              ),
                              children: [
                                if (invites.isNotEmpty) ...[
                                  Text(
                                    copy.text(
                                      'Club invitations',
                                      'Zaproszenia do klubów',
                                    ),
                                    style: TextStyle(
                                      color: palette.textPrimary,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  for (final invite in invites) ...[
                                    ClubInviteCard(
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
                                  Text(
                                    copy.text('Your clubs', 'Twoje kluby'),
                                    style: TextStyle(
                                      color: palette.textPrimary,
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
        ),
      ),
    );
  }
}

class ClubInviteCard extends StatelessWidget {
  const ClubInviteCard({
    required this.invite,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
    super.key,
  });

  final ClubInvite invite;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    final hasAvatar = invite.clubAvatarUrl?.isNotEmpty == true;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.borderStrong),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: colors.primary,
            backgroundImage: hasAvatar
                ? NetworkImage(invite.clubAvatarUrl!)
                : null,
            child: hasAvatar
                ? null
                : Text(
                    invite.clubName.isEmpty
                        ? 'C'
                        : invite.clubName[0].toUpperCase(),
                    style: TextStyle(
                      color: colors.onPrimary,
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
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  copy.text(
                    'Invited by ${invite.inviterName}',
                    'Zaprasza: ${invite.inviterName}',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.textSecondary),
                ),
                const SizedBox(height: 11),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final textScale = MediaQuery.textScalerOf(context).scale(1);
                    final stackActions =
                        textScale > 1.4 || constraints.maxWidth < 250;
                    final accept = FilledButton(
                      key: const ValueKey('club-invite-accept'),
                      onPressed: busy ? null : onAccept,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                      ),
                      child: busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(copy.text('Accept', 'Akceptuj')),
                    );
                    final decline = OutlinedButton(
                      key: const ValueKey('club-invite-decline'),
                      onPressed: busy ? null : onDecline,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: Text(copy.text('Decline', 'Odrzuć')),
                    );

                    if (stackActions) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [accept, const SizedBox(height: 9), decline],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: decline),
                        const SizedBox(width: 9),
                        Expanded(child: accept),
                      ],
                    );
                  },
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
  const _Header({required this.onCreatePressed, this.isRootTab = false});

  final VoidCallback onCreatePressed;
  final bool isRootTab;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 16, 8),
      child: Row(
        children: [
          if (!isRootTab) ...[
            YoIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              iconSize: 18,
              size: 40,
              backgroundColor: palette.surface,
              borderColor: palette.border,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  copy.text('Clubs', 'Kluby'),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.7,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  copy.text(
                    'Your permanent communities',
                    'Twoje stałe społeczności',
                  ),
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filled(
            onPressed: onCreatePressed,
            tooltip: copy.text('Create club', 'Utwórz klub'),
            style: IconButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.surfaceRaised, palette.surface],
        ),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: .12),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.groups_2_rounded,
              color: colors.onPrimaryContainer,
              size: 32,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clubCount == 1
                      ? copy.text('1 club joined', '1 klub')
                      : copy.text(
                          '$clubCount clubs joined',
                          '$clubCount klubów',
                        ),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  copy.text(
                    'Chat, voice rooms and people that stay together.',
                    'Czat, pokoje głosowe i społeczność w jednym miejscu.',
                  ),
                  style: TextStyle(
                    color: palette.textSecondary,
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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    final hasBanner = club.bannerUrl?.isNotEmpty ?? false;
    final hasAvatar = club.avatarUrl?.isNotEmpty ?? false;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: palette.border),
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
                              color: colors.primary,
                              border: Border.all(
                                color: palette.surface,
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
                                    style: TextStyle(
                                      color: colors.onPrimary,
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
                                  ? palette.successSurface
                                  : palette.surfaceMuted,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              club.onlineCount > 0
                                  ? copy.text(
                                      '${club.onlineCount} online',
                                      '${club.onlineCount} online',
                                    )
                                  : copy.text('Quiet now', 'Teraz cisza'),
                              style: TextStyle(
                                color: club.onlineCount > 0
                                    ? palette.successForeground
                                    : palette.textSecondary,
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
                                  style: TextStyle(
                                    color: palette.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: palette.textTertiary,
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            club.description.isEmpty
                                ? copy.text(
                                    'A YO Voice club.',
                                    'Klub w YO Voice.',
                                  )
                                : club.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _MetaChip(
                                icon: Icons.people_alt_rounded,
                                text: club.memberCount == 1
                                    ? copy.text('1 member', '1 członek')
                                    : copy.text(
                                        '${club.memberCount} members',
                                        '${club.memberCount} członków',
                                      ),
                              ),
                              const SizedBox(width: 8),
                              _MetaChip(
                                icon: Icons.language_rounded,
                                text: _clubLanguageLabel(
                                  club.defaultLanguage,
                                  copy,
                                ),
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
    final palette = context.appPalette;
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: palette.surfaceMuted,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: palette.textSecondary),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textPrimary,
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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
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
        Text(
          copy.text('Find your people', 'Znajdź swoją społeczność'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 27,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          copy.text(
            'Create a permanent club with members, roles, chat and a private voice lounge.',
            'Utwórz stały klub z członkami, rolami, czatem i prywatnym pokojem głosowym.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: onCreatePressed,
          style: FilledButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: colors.onPrimary,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          icon: const Icon(Icons.add_rounded),
          label: Text(
            copy.text('CREATE CLUB', 'UTWÓRZ KLUB'),
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, color: colors.error, size: 46),
            const SizedBox(height: 14),
            Text(
              copy.text(
                'Could not load your clubs',
                'Nie udało się wczytać klubów',
              ),
              style: TextStyle(
                color: palette.textPrimary,
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
              style: TextStyle(color: palette.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(copy.text('Try again', 'Spróbuj ponownie')),
            ),
          ],
        ),
      ),
    );
  }
}
