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
      displayName: (data['displayName'] as String?)?.trim().isNotEmpty == true
          ? (data['displayName'] as String).trim()
          : 'YoVoice user',
      username: (data['username'] as String?)?.trim() ?? '',
      photoUrl: (data['photoUrl'] as String?)?.trim().isNotEmpty == true
          ? (data['photoUrl'] as String).trim()
          : null,
      followedAt: data['followedAt'] is Timestamp
          ? (data['followedAt'] as Timestamp).toDate()
          : null,
    );
  }
}
