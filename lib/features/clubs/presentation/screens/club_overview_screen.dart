import 'package:flutter/material.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/models/club_channel.dart';
import 'package:yovoice/features/clubs/data/models/club_member.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_chat_screen.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_member_management_screen.dart';
import 'package:yovoice/features/calls/presentation/screens/voice_call_screen.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

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
          builder: (_) => VoiceCallScreen(roomId: room.id, roomName: room.name),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: StreamBuilder<Club>(
        stream: _clubService.watchClub(widget.clubId),
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
                    onPressed: () {},
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
                            onPressed: () {},
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
                      stream: _clubService.watchMembers(widget.clubId),
                    ),
                    _ => _ChannelsPreview(
                      clubName: club.name,
                      stream: _clubService.watchChannels(widget.clubId),
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
