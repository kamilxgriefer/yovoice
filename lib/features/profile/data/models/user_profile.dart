import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:yovoice/core/presence/user_availability.dart';

import 'package:yovoice/features/profile/data/models/profile_visibility.dart';

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
    this.creatorAudienceVisible = false,
    this.creatorAgeVerified = false,
    this.creatorAudienceEnabled = false,
    this.statusMessage = '',
    this.isOnline = false,
    this.availability = UserAvailability.available,
    required this.website,
    required this.accountType,
    required this.friendCount,
    required this.followerCount,
    this.accountFollowerCount = 0,
    required this.followingCount,
    this.accountFollowingCount = 0,
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
    this.profileUpdatedAt,
    this.profileVisibility = ProfileVisibility.public,
    this.likesHidden = false,
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

  /// Safe public projection of the complete Creator audience decision.
  ///
  /// The server writes this only after it has checked Creator identity,
  /// Premium, age verification and the owner's explicit opt-in. Public UI
  /// must use this field instead of reconstructing the decision from private
  /// eligibility data.
  final bool creatorAudienceVisible;

  /// Legacy owner-document field retained for stored-data compatibility.
  /// Public audience rendering never consults it.
  final bool creatorAgeVerified;

  /// Legacy owner-document preference retained for stored-data compatibility.
  /// Public audience rendering never consults it.
  final bool creatorAudienceEnabled;

  /// The "vibe" line — a short, social status ("Music + late night
  /// talks", "Gaming tonight 🎮"). The profile's headline, unlike [bio]
  /// (longer) or [website] (demoted to a secondary detail).
  final String statusMessage;

  /// Live presence flag maintained by PresenceService's heartbeat.
  final bool isOnline;

  /// The availability this account chose for itself (own document only;
  /// other people read the projected `socialPresence` form).
  final UserAvailability availability;
  final String website;
  final AccountType accountType;
  final int friendCount;
  final int followerCount;

  /// The account's own follower counter exactly as stored on `users/{uid}`,
  /// NOT gated by [creatorAudienceVisible]. For the owner's own surfaces
  /// only: a Page shares its follow edges with the account and shows this
  /// number to everyone (ADR-234), so the create preview must show it too.
  /// Public audience surfaces keep using [followerCount]. Another account's
  /// public projection never carries more than [followerCount] here.
  final int accountFollowerCount;
  final int followingCount;

  /// How many accounts and Pages this account follows, exactly as stored on
  /// `users/{uid}` (`setFollow` keeps it), NOT gated by
  /// [creatorAudienceVisible]. For the owner's own surfaces only: Start's
  /// "Zacznij tutaj" card ticks its follow step from it (firstSteps A).
  /// Public audience surfaces keep using [followingCount]; another account's
  /// public projection never carries more than [followingCount] here.
  final int accountFollowingCount;
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

  /// Changes whenever the owner profile projection changes. Media URLs stay
  /// private, but this non-sensitive revision signal lets avatar/banner
  /// widgets invalidate a short-lived grant after a new upload.
  final DateTime? profileUpdatedAt;

  /// Who may read the server-owned full public-profile projection.
  ///
  /// Missing legacy values intentionally decode as [ProfileVisibility.public]
  /// because that was the product's behaviour before this preference existed.
  final ProfileVisibility profileVisibility;

  /// "Hide my likes": the owner is left out of every likers list YO Voice
  /// shows (ADR-230). Server-written by `setMyLikesHiddenV1` only. Missing
  /// or `false` = visible; anything else = hidden, mirroring the server's
  /// fail-closed `likesHiddenOf`.
  final bool likesHidden;

  DateTime? get nextDisplayNameChangeAt =>
      displayNameChangedAt?.add(const Duration(days: 30));

  /// The single fail-closed gate used by follower/following surfaces.
  bool get canExposeCreatorAudience => creatorAudienceVisible;

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
    final creatorAudienceVisible =
        data['creatorAudienceVisible'] as bool? ?? false;

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
      // Legacy URL snapshots are untrusted bearer/external locations. The
      // UI resolves both media kinds from uid via ProfileMediaService.
      photoUrl: null,
      bannerUrl: null,
      premiumIdentity: data['premiumIdentity'] as bool? ?? false,
      creatorAudienceVisible: creatorAudienceVisible,
      creatorAgeVerified: data['creatorAgeVerified'] as bool? ?? false,
      creatorAudienceEnabled: data['creatorAudienceEnabled'] as bool? ?? false,
      statusMessage: data['statusMessage'] as String? ?? '',
      isOnline: data['isOnline'] as bool? ?? false,
      availability: UserAvailability.fromWire(data['availability']),
      website: data['website'] as String? ?? '',
      accountType: AccountType.fromValue(data['accountType']),
      friendCount: readInt('friendCount'),
      followerCount: creatorAudienceVisible ? readInt('followerCount') : 0,
      accountFollowerCount: readInt('followerCount'),
      followingCount: creatorAudienceVisible ? readInt('followingCount') : 0,
      accountFollowingCount: readInt('followingCount'),
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
      profileUpdatedAt: switch (data['profileUpdatedAt'] ?? data['updatedAt']) {
        final Timestamp value => value.toDate(),
        _ => null,
      },
      profileVisibility: ProfileVisibility.fromValue(data['profileVisibility']),
      likesHidden: data['likesHidden'] == null || data['likesHidden'] == false
          ? false
          : true,
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
