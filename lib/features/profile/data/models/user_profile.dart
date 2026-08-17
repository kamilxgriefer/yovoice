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
    this.premiumIdentity = false,
    this.statusMessage = '',
    this.isOnline = false,
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
    this.displayNameChangedAt,
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

  /// Public mirror of the Premium entitlement, written ONLY by Cloud
  /// Functions (premium/entitlements.js) — not client-writable per
  /// firestore.rules, which is what makes it safe for other users'
  /// clients to render the premium ring from it.
  final bool premiumIdentity;

  /// The "vibe" line — a short, social status ("Music + late night
  /// talks", "Gaming tonight 🎮"). The profile's headline, unlike [bio]
  /// (longer) or [website] (demoted to a secondary detail).
  final String statusMessage;

  /// Live presence flag maintained by PresenceService's heartbeat.
  final bool isOnline;
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

  /// Canonical server timestamp of the latest display-name change.
  ///
  /// This is an informational hint for the owner-facing editor. The Cloud
  /// Function remains authoritative and re-checks the 30-day window in a
  /// transaction for every actual change.
  final DateTime? displayNameChangedAt;

  DateTime? get nextDisplayNameChangeAt =>
      displayNameChangedAt?.add(const Duration(days: 30));

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
          (fallbackName?.isNotEmpty == true ? fallbackName! : 'YO Voice user'),
      username: data['username'] as String? ?? '',
      bio: data['bio'] as String? ?? '',
      country: data['country'] as String? ?? '',
      nativeLanguage: data['nativeLanguage'] as String? ?? '',
      spokenLanguages: readStrings('spokenLanguages'),
      learningLanguages: readStrings('learningLanguages'),
      photoUrl: data['photoUrl'] as String?,
      bannerUrl: data['bannerUrl'] as String?,
      premiumIdentity: data['premiumIdentity'] as bool? ?? false,
      statusMessage: data['statusMessage'] as String? ?? '',
      isOnline: data['isOnline'] as bool? ?? false,
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
      displayNameChangedAt: data['displayNameChangedAt'] is Timestamp
          ? (data['displayNameChangedAt'] as Timestamp).toDate()
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
