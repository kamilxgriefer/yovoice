import 'package:flutter/material.dart';

import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/presentation/screens/add_friend_screen.dart';
import 'package:yovoice/features/friends/presentation/screens/friend_profile_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final FriendService _service = FriendService();
  final TextEditingController _search = TextEditingController();
  late final Stream<List<FriendUser>> _friendsStream;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _friendsStream = _service.watchFriends();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080711),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Friends',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      StreamBuilder<int>(
                        stream: _service.watchPendingFriendRequestCount(),
                        builder: (context, snapshot) {
                          final count = snapshot.data ?? 0;
                          return IconButton.filled(
                            tooltip: 'Add friend',
                            onPressed: () => Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => const AddFriendScreen(),
                              ),
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFF9D20FF),
                            ),
                            icon: Badge(
                              isLabelVisible: count > 0,
                              label: Text(count > 99 ? '99+' : '$count'),
                              child: const Icon(
                                Icons.person_add_alt_1_rounded,
                                color: Colors.white,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Search your friends or add someone new.',
                    style: TextStyle(color: Color(0xFF9D95AD)),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _search,
                    onChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search friends...',
                      hintStyle: const TextStyle(color: Color(0xFF756D82)),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Color(0xFFB348FF),
                      ),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                      filled: true,
                      fillColor: const Color(0xFF12101D),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: Color(0xFF30263F)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: Color(0xFF9D20FF)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<FriendUser>>(
                stream: _friendsStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _Empty(
                      icon: Icons.cloud_off_rounded,
                      title: 'Could not load friends',
                      subtitle: snapshot.error.toString(),
                    );
                  }

                  final friends = (snapshot.data ?? const <FriendUser>[])
                      .where((friend) {
                        if (_query.isEmpty) return true;
                        return friend.displayName.toLowerCase().contains(
                              _query,
                            ) ||
                            friend.email.toLowerCase().contains(_query);
                      })
                      .toList(growable: false);

                  if (friends.isEmpty) {
                    return _Empty(
                      icon: _query.isEmpty
                          ? Icons.people_outline_rounded
                          : Icons.search_off_rounded,
                      title: _query.isEmpty
                          ? 'No friends yet'
                          : 'No matching friends',
                      subtitle: _query.isEmpty
                          ? 'Tap the add button to find people.'
                          : 'Try another name or email.',
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                    itemCount: friends.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      final friend = friends[index];
                      return ListTile(
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => FriendProfileScreen(friend: friend),
                          ),
                        ),
                        tileColor: const Color(0xFF12101D),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: const BorderSide(color: Color(0xFF30263F)),
                        ),
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              radius: 25,
                              backgroundColor: const Color(0xFF5D2181),
                              backgroundImage:
                                  friend.photoUrl?.isNotEmpty == true
                                  ? NetworkImage(friend.photoUrl!)
                                  : null,
                              child: friend.photoUrl?.isNotEmpty == true
                                  ? null
                                  : Text(
                                      friend.initial,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 1,
                              child: Container(
                                width: 13,
                                height: 13,
                                decoration: BoxDecoration(
                                  color: friend.isOnline
                                      ? const Color(0xFF20D66B)
                                      : const Color(0xFF6D6275),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF12101D),
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        title: Text(
                          friend.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(
                          friend.isOnline ? 'Online' : friend.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFF9D95AD)),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFF9D95AD),
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

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF9D20FF), size: 48),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF9D95AD), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
