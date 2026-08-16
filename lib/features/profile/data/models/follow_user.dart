import 'package:cloud_firestore/cloud_firestore.dart';

class FollowUser {
  const FollowUser({
    required this.uid,
    required this.displayName,
    required this.username,
    required this.photoUrl,
    required this.followedAt,
  });

  final String uid;
  final String displayName;
  final String username;
  final String? photoUrl;
  final DateTime? followedAt;

  String get initial =>
      displayName.trim().isEmpty ? '?' : displayName.trim()[0].toUpperCase();

  factory FollowUser.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return FollowUser(
      uid: (data['uid'] as String?)?.trim().isNotEmpty == true
          ? data['uid'] as String
          : document.id,
      // Legacy edges can contain stale identity snapshots. Callers that need
      // identity must join publicProfiles via fromEdgeAndProfile.
      displayName: 'YO Voice user',
      username: '',
      photoUrl: null,
      followedAt: data['followedAt'] is Timestamp
          ? (data['followedAt'] as Timestamp).toDate()
          : null,
    );
  }

  factory FollowUser.fromEdgeAndProfile({
    required DocumentSnapshot<Map<String, dynamic>> edge,
    required DocumentSnapshot<Map<String, dynamic>> profile,
  }) {
    final edgeData = edge.data() ?? const <String, dynamic>{};
    final profileData = profile.data() ?? const <String, dynamic>{};
    final uid = (edgeData['uid'] as String?)?.trim().isNotEmpty == true
        ? edgeData['uid'] as String
        : edge.id;
    final displayName = (profileData['displayName'] as String?)?.trim();
    final username = (profileData['username'] as String?)?.trim();
    final photoUrl = (profileData['photoUrl'] as String?)?.trim();
    return FollowUser(
      uid: uid,
      displayName: displayName?.isNotEmpty == true
          ? displayName!
          : 'YO Voice user',
      username: username ?? '',
      photoUrl: photoUrl?.isNotEmpty == true ? photoUrl : null,
      followedAt: edgeData['followedAt'] is Timestamp
          ? (edgeData['followedAt'] as Timestamp).toDate()
          : null,
    );
  }
}
