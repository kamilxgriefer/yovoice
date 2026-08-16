import 'package:flutter/material.dart';

import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

import '../../data/models/follow_user.dart';
import '../../data/services/follow_service.dart';

enum FollowListType { followers, following }

class FollowListScreen extends StatelessWidget {
  FollowListScreen({
    required this.userId,
    required this.type,
    FollowService? service,
    super.key,
  }) : _service = service ?? FollowService();

  final String userId;
  final FollowListType type;
  final FollowService _service;

  @override
  Widget build(BuildContext context) {
    final isFollowers = type == FollowListType.followers;
    final stream = isFollowers
        ? _service.watchFollowers(userId)
        : _service.watchFollowing(userId);

    return Scaffold(
      backgroundColor: const Color(0xFF09050F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09050F),
        foregroundColor: Colors.white,
        title: Text(isFollowers ? 'Followers' : 'Following'),
      ),
      body: ResponsiveContentFrame(
        width: ResponsiveContentWidth.list,
        alignment: ResponsiveContentAlignment.topLeft,
        child: StreamBuilder<List<FollowUser>>(
          stream: stream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load this list.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFB8ADC1)),
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final users = snapshot.data!;
            if (users.isEmpty) {
              return Center(
                child: Text(
                  isFollowers
                      ? 'No followers yet.'
                      : 'Not following anyone yet.',
                  style: const TextStyle(
                    color: Color(0xFFB8ADC1),
                    fontSize: 16,
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: users.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final user = users[index];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF17101F),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFF34263F)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: const Color(0xFF5D2181),
                        backgroundImage: user.photoUrl == null
                            ? null
                            : NetworkImage(user.photoUrl!),
                        child: user.photoUrl == null
                            ? Text(
                                user.initial,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  user.displayName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                                UserIdentityBadges(uid: user.uid),
                              ],
                            ),
                            if (user.username.isNotEmpty)
                              Text(
                                '@${user.username.replaceAll(' ', '').toLowerCase()}',
                                style: const TextStyle(
                                  color: Color(0xFFA99DB3),
                                  fontSize: 13,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
