import 'package:cloud_firestore/cloud_firestore.dart';

enum AccountType {
  personal,
  creator,
  official;

  static AccountType fromValue(Object? value) {
    return switch (value) {
      'creator' => AccountType.creator,
      'official' => AccountType.official,
      _ => AccountType.personal,
    };
  }

  String get label => switch (this) {
    AccountType.personal => 'Personal',
    AccountType.creator => 'Creator',
    AccountType.official => 'Official',
  };
}

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.username,
    required this.bio,
    required this.country,
    required this.nativeLanguage,
    required this.spokenLanguages,
    required this.learningLanguages,
    required this.photoUrl,
    required this.bannerUrl,
    required this.website,
    required this.accountType,
    required this.friendCount,
    required this.followerCount,
    required this.followingCount,
    required this.roomCount,
    required this.communityCount,
    required this.voiceMinutes,
    required this.messageCount,
    required this.activeDays,
    required this.momentCount,
    required this.reactionCount,
    required this.hostMinutes,
    required this.selectedTitleId,
    required this.unlockedTitleIds,
    required this.unlockedTitleTimestamps,
    required this.createdAt,
  });

  final String uid;
  final String email;
  final String displayName;
  final String username;
  final String bio;
  final String country;
  final String nativeLanguage;
  final List<String> spokenLanguages;
  final List<String> learningLanguages;
  final String? photoUrl;
  final String? bannerUrl;
  final String website;
  final AccountType accountType;
  final int friendCount;
  final int followerCount;
  final int followingCount;
  final int roomCount;
  final int communityCount;
  final int voiceMinutes;
  final int messageCount;
  final int activeDays;
  final int momentCount;
  final int reactionCount;
  final int hostMinutes;
  final String? selectedTitleId;
  final List<String> unlockedTitleIds;
  final Map<String, DateTime> unlockedTitleTimestamps;
  final DateTime? createdAt;

  factory UserProfile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};

    int readInt(String key) => (data[key] as num?)?.toInt() ?? 0;
    List<String> readStrings(String key) =>
        (data[key] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>()
            .toList(growable: false);

    final fallbackName = (data['username'] as String?)?.trim();

    return UserProfile(
      uid: document.id,
      email: data['email'] as String? ?? '',
      displayName:
          data['displayName'] as String? ??
          (fallbackName?.isNotEmpty == true ? fallbackName! : 'YoVoice user'),
      username: data['username'] as String? ?? '',
      bio: data['bio'] as String? ?? '',
      country: data['country'] as String? ?? '',
      nativeLanguage: data['nativeLanguage'] as String? ?? '',
      spokenLanguages: readStrings('spokenLanguages'),
      learningLanguages: readStrings('learningLanguages'),
      photoUrl: data['photoUrl'] as String?,
      bannerUrl: data['bannerUrl'] as String?,
      website: data['website'] as String? ?? '',
      accountType: AccountType.fromValue(data['accountType']),
      friendCount: readInt('friendCount'),
      followerCount: readInt('followerCount'),
      followingCount: readInt('followingCount'),
      roomCount: readInt('roomCount'),
      communityCount: readInt('communityCount'),
      voiceMinutes: readInt('voiceMinutes'),
      messageCount: readInt('messageCount'),
      activeDays: readInt('activeDays'),
      momentCount: readInt('momentCount'),
      reactionCount: readInt('reactionCount'),
      hostMinutes: readInt('hostMinutes'),
      selectedTitleId: data['selectedTitleId'] as String?,
      unlockedTitleIds: readStrings('unlockedTitleIds'),
      unlockedTitleTimestamps:
          (data['unlockedTitleTimestamps'] as Map<String, dynamic>? ??
                  const <String, dynamic>{})
              .map(
                (key, value) => MapEntry(
                  key,
                  value is Timestamp ? value.toDate() : DateTime.now(),
                ),
              ),
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, int> get achievementStats => {
    'messages': messageCount,
    'followers': followerCount,
    'voiceMinutes': voiceMinutes,
    'rooms': roomCount,
    'communities': communityCount,
    'friends': friendCount,
    'reactions': reactionCount,
    'hostMinutes': hostMinutes,
    'activeDays': activeDays,
    'moments': momentCount,
  };
}
