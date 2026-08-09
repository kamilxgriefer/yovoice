import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/models/club_channel.dart';
import 'package:yovoice/features/clubs/data/models/club_member.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_chat_screen.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_member_management_screen.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_entry_screen.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_settings_screen.dart';

class ClubOverviewScreen extends StatefulWidget {
  const ClubOverviewScreen({required this.clubId, super.key});

  final String clubId;

  @override
  State<ClubOverviewScreen> createState() => _ClubOverviewScreenState();
}

class _ClubOverviewScreenState extends State<ClubOverviewScreen> {
  static const Color _background = Color(0xFF080711);
  static const Color _surface = Color(0xFF171120);
  static const Color _purple = Color(0xFF9D20FF);

  final ClubService _clubService = ClubService();
  final RoomService _roomService = RoomService();
  int _selectedTab = 0;
  bool _openingLounge = false;

  // Hoisted out of build() -- these previously lived inside the outer
  // StreamBuilder<Club>'s builder callback, so a fresh Stream (and a fresh
  // Firestore listener) was created every time the club document changed
  // at all (member joins, online-count ticks, etc.) or the user switched
  // tabs and triggered setState, not just when members/channels actually
  // needed to reload.
  late final Stream<Club> _club;
  late final Stream<List<ClubMember>> _members;
  late final Stream<List<ClubChannel>> _channels;

  @override
  void initState() {
    super.initState();
    _club = _clubService.watchClub(widget.clubId);
    _members = _clubService.watchMembers(widget.clubId);
    _channels = _clubService.watchChannels(widget.clubId);
  }

  Future<void> _openClubLounge(Club club) async {
    if (_openingLounge) return;
    setState(() => _openingLounge = true);

    try {
      final room = await _roomService.enterClubLounge(
        clubId: club.id,
        clubName: club.name,
        clubDescription: club.description,
        language: club.defaultLanguage,
        ownerId: club.ownerId,
        ownerName: club.ownerName,
        imageUrl: club.avatarUrl,
      );

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RoomEntryScreen(room: room),
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
      if (mounted) setState(() => _openingLounge = false);
    }
  }

  Future<void> _showInviteFriends(Club club) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InviteFriendsSheet(club: club),
    );
  }

  Future<void> _showClubOptions(Club club) async {
    final membership = await _clubService.getMyMembership(club.id);
    if (!mounted) return;
    final canManage = membership?.role.canEditClub ?? false;
    final inviteLink = _clubService.createInviteLink(club.id);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ClubOptionsSheet(
        canManage: canManage,
        onSettings: canManage
            ? () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => ClubSettingsScreen(club: club),
                  ),
                );
              }
            : null,
        onMembers: () {
          Navigator.pop(sheetContext);
          setState(() => _selectedTab = 1);
        },
        onShare: () async {
          Navigator.pop(sheetContext);
          await SharePlus.instance.share(
            ShareParams(
              text: 'Join ${club.name} on YO Voice: $inviteLink',
              subject: 'Join ${club.name} on YO Voice',
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: StreamBuilder<Club>(
        stream: _club,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _purple),
            );
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return _ClubLoadError(message: snapshot.error?.toString());
          }

          final club = snapshot.data!;
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 238,
                backgroundColor: _background,
                surfaceTintColor: Colors.transparent,
                leading: IconButton.filledTonal(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                actions: [
                  IconButton.filledTonal(
                    onPressed: () => _showClubOptions(club),
                    tooltip: 'Club options',
                    icon: const Icon(Icons.more_horiz_rounded),
                  ),
                  const SizedBox(width: 10),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: _ClubHero(club: club),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        club.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        club.description.isEmpty
                            ? 'A permanent place for your people.'
                            : club.description,
                        style: const TextStyle(
                          color: Color(0xFFB6ACBB),
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _ClubStat(
                            value: club.memberCount.toString(),
                            label: 'Members',
                          ),
                          const SizedBox(width: 10),
                          _ClubStat(
                            value: club.onlineCount.toString(),
                            label: 'Online',
                          ),
                          const SizedBox(width: 10),
                          _ClubStat(
                            value: club.defaultLanguage,
                            label: 'Language',
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _openingLounge
                                  ? null
                                  : () => _openClubLounge(club),
                              style: FilledButton.styleFrom(
                                backgroundColor: _purple,
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: _openingLounge
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.graphic_eq_rounded),
                              label: Text(
                                _openingLounge ? 'OPENING...' : 'CLUB LOUNGE',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton.outlined(
                            onPressed: () => _showInviteFriends(club),
                            tooltip: 'Invite members',
                            style: IconButton.styleFrom(
                              minimumSize: const Size(52, 52),
                              side: const BorderSide(color: Color(0xFF4A385A)),
                            ),
                            icon: const Icon(
                              Icons.person_add_alt_1_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _ClubTabs(
                        selectedIndex: _selectedTab,
                        onSelected: (index) {
                          setState(() {
                            _selectedTab = index;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
                sliver: SliverToBoxAdapter(
                  child: switch (_selectedTab) {
                    1 => _MembersPreview(
                      clubId: widget.clubId,
                      stream: _members,
                    ),
                    _ => _ChannelsPreview(
                      clubName: club.name,
                      stream: _channels,
                      onOpenVoice: () => _openClubLounge(club),
                    ),
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ClubHero extends StatelessWidget {
  const _ClubHero({required this.club});

  final Club club;

  @override
  Widget build(BuildContext context) {
    final hasBanner = club.bannerUrl?.isNotEmpty ?? false;
    final hasAvatar = club.avatarUrl?.isNotEmpty ?? false;

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: hasBanner
                ? null
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF652B8B), Color(0xFF160C24)],
                  ),
            image: hasBanner
                ? DecorationImage(
                    image: NetworkImage(club.bannerUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0xEE080711)],
            ),
          ),
        ),
        Positioned(
          left: 18,
          bottom: 0,
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF7A2BB6),
              border: Border.all(color: const Color(0xFF080711), width: 5),
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
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ClubStat extends StatelessWidget {
  const _ClubStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          color: _ClubOverviewScreenState._surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF33263F)),
        ),
        child: Column(
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF9D93A4),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClubTabs extends StatelessWidget {
  const _ClubTabs({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const labels = ['Channels', 'Members'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF15101D),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = index == selectedIndex;
          return Expanded(
            child: InkWell(
              onTap: () => onSelected(index),
              borderRadius: BorderRadius.circular(13),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF38204B)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  labels[index],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF9F95A6),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _ChannelsPreview extends StatelessWidget {
  const _ChannelsPreview({
    required this.clubName,
    required this.stream,
    required this.onOpenVoice,
  });

  final String clubName;
  final Stream<List<ClubChannel>> stream;
  final VoidCallback onOpenVoice;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ClubChannel>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: CircularProgressIndicator(color: Color(0xFF9D20FF)),
            ),
          );
        }

        final channels = snapshot.data ?? const <ClubChannel>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Club spaces',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            for (final channel in channels) ...[
              _ChannelTile(
                channel: channel,
                clubName: clubName,
                onOpenVoice: onOpenVoice,
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.channel,
    required this.clubName,
    required this.onOpenVoice,
  });

  final ClubChannel channel;
  final String clubName;
  final VoidCallback onOpenVoice;

  @override
  Widget build(BuildContext context) {
    final (icon, subtitle) = switch (channel.type) {
      ClubChannelType.voice => (
        Icons.graphic_eq_rounded,
        'Persistent voice room',
      ),
      ClubChannelType.announcement => (
        Icons.campaign_rounded,
        'Important club updates',
      ),
      ClubChannelType.chat => (Icons.tag_rounded, 'Main club conversation'),
    };

    return ListTile(
      onTap: () {
        if (channel.type == ClubChannelType.voice) {
          onOpenVoice();
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ClubChatScreen(
              clubId: channel.clubId,
              clubName: clubName,
              channel: channel,
            ),
          ),
        );
      },
      tileColor: const Color(0xFF171120),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: const BorderSide(color: Color(0xFF33263F)),
      ),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF2D1B3A),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: const Color(0xFFC17BFF)),
      ),
      title: Text(
        channel.name,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Color(0xFF9F95A6), fontSize: 11),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFF8D8295),
      ),
    );
  }
}

class _MembersPreview extends StatelessWidget {
  const _MembersPreview({required this.clubId, required this.stream});

  final String clubId;
  final Stream<List<ClubMember>> stream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ClubMember>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: CircularProgressIndicator(color: Color(0xFF9D20FF)),
            ),
          );
        }

        final members = snapshot.data ?? const <ClubMember>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${members.length} members',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            for (final member in members) ...[
              _MemberTile(clubId: clubId, member: member),
              const SizedBox(height: 9),
            ],
          ],
        );
      },
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.clubId, required this.member});

  final String clubId;
  final ClubMember member;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = member.photoUrl?.isNotEmpty ?? false;
    final initial = member.displayName.trim().isEmpty
        ? '?'
        : member.displayName.trim()[0].toUpperCase();

    return ListTile(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ClubMemberManagementScreen(clubId: clubId, member: member),
          ),
        );
      },
      tileColor: const Color(0xFF171120),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: const BorderSide(color: Color(0xFF33263F)),
      ),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFF7230A5),
            backgroundImage: hasPhoto ? NetworkImage(member.photoUrl!) : null,
            child: hasPhoto
                ? null
                : Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: member.isOnline
                    ? const Color(0xFF49D58A)
                    : const Color(0xFF5B5362),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF171120), width: 2),
              ),
            ),
          ),
        ],
      ),
      title: Text(
        member.displayName,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        member.isOnline ? 'Online' : 'Offline',
        style: const TextStyle(color: Color(0xFF9F95A6), fontSize: 11),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF2E1C3A),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              member.role.label,
              style: const TextStyle(
                color: Color(0xFFD19CFF),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF7E7485)),
        ],
      ),
    );
  }
}

class _ClubLoadError extends StatelessWidget {
  const _ClubLoadError({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFFF6B8E),
                size: 48,
              ),
              const SizedBox(height: 14),
              const Text(
                'Could not open this club',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!.replaceFirst('Bad state: ', ''),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFA99FAC)),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClubOptionsSheet extends StatelessWidget {
  const _ClubOptionsSheet({
    required this.canManage,
    required this.onSettings,
    required this.onMembers,
    required this.onShare,
  });

  final bool canManage;
  final VoidCallback? onSettings;
  final VoidCallback onMembers;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        decoration: const BoxDecoration(
          color: Color(0xFF171120),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFF665A70),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 18),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Club options',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (canManage)
              ListTile(
                onTap: onSettings,
                leading: const Icon(
                  Icons.settings_rounded,
                  color: Color(0xFFB348FF),
                ),
                title: const Text(
                  'Club settings',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: const Text(
                  'Name, description, privacy and language',
                  style: TextStyle(color: Color(0xFF9D95AD)),
                ),
              ),
            ListTile(
              onTap: onMembers,
              leading: const Icon(
                Icons.manage_accounts_rounded,
                color: Color(0xFFB348FF),
              ),
              title: const Text(
                'Manage members',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: const Text(
                'View members and manage roles',
                style: TextStyle(color: Color(0xFF9D95AD)),
              ),
            ),
            ListTile(
              onTap: onShare,
              leading: const Icon(Icons.link_rounded, color: Color(0xFFB348FF)),
              title: const Text(
                'Share invite link',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: const Text(
                'Invite people through any app',
                style: TextStyle(color: Color(0xFF9D95AD)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteFriendsSheet extends StatefulWidget {
  const _InviteFriendsSheet({required this.club});
  final Club club;

  @override
  State<_InviteFriendsSheet> createState() => _InviteFriendsSheetState();
}

class _InviteFriendsSheetState extends State<_InviteFriendsSheet> {
  final FriendService _friends = FriendService();
  final ClubService _clubs = ClubService();
  final Set<String> _busy = <String>{};

  Future<void> _sendInvite(FriendUser friend, bool alreadyInvited) async {
    if (_busy.contains(friend.id)) return;
    setState(() => _busy.add(friend.id));
    try {
      if (alreadyInvited) {
        await _clubs.cancelClubInvite(
          clubId: widget.club.id,
          inviteeId: friend.id,
        );
      } else {
        await _clubs.sendClubInvite(
          clubId: widget.club.id,
          friendId: friend.id,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            alreadyInvited
                ? 'Invitation cancelled.'
                : 'Invitation sent to ${friend.displayName}.',
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
        setState(() => _busy.remove(friend.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: MediaQuery.sizeOf(context).height * .72,
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
        decoration: const BoxDecoration(
          color: Color(0xFF171120),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFF665A70),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 18),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Invite friends',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'They will join only after accepting your invitation.',
                style: TextStyle(color: Color(0xFF9D95AD)),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<Set<String>>(
                stream: _clubs.watchInvitedUserIds(widget.club.id),
                builder: (context, inviteSnapshot) {
                  final invitedIds = inviteSnapshot.data ?? const <String>{};
                  return StreamBuilder<List<FriendUser>>(
                    stream: _friends.watchFriends(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF9D20FF),
                          ),
                        );
                      }
                      final items = snapshot.data!;
                      if (items.isEmpty) {
                        return const Center(
                          child: Text(
                            'Add friends first, then invite them here.',
                            style: TextStyle(color: Color(0xFF9D95AD)),
                          ),
                        );
                      }
                      return ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: Color(0xFF30263F)),
                        itemBuilder: (context, index) {
                          final friend = items[index];
                          final busy = _busy.contains(friend.id);
                          final invited = invitedIds.contains(friend.id);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundImage:
                                  friend.photoUrl?.isNotEmpty == true
                                  ? NetworkImage(friend.photoUrl!)
                                  : null,
                              child: friend.photoUrl?.isNotEmpty == true
                                  ? null
                                  : Text(friend.initial),
                            ),
                            title: Text(
                              friend.displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              invited
                                  ? 'Invitation pending'
                                  : friend.isOnline
                                  ? 'Online'
                                  : friend.email,
                              style: TextStyle(
                                color: invited
                                    ? const Color(0xFFC982FF)
                                    : const Color(0xFF9D95AD),
                              ),
                            ),
                            trailing: FilledButton(
                              onPressed: busy
                                  ? null
                                  : () => _sendInvite(friend, invited),
                              style: FilledButton.styleFrom(
                                backgroundColor: invited
                                    ? const Color(0xFF30243C)
                                    : const Color(0xFF7D25F4),
                              ),
                              child: busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(invited ? 'Cancel' : 'Invite'),
                            ),
                          );
                        },
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
