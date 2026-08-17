enum CreatorDirectoryAccountType {
  creator,
  official;

  static CreatorDirectoryAccountType? fromValue(Object? value) {
    return switch (value) {
      'creator' => CreatorDirectoryAccountType.creator,
      'official' => CreatorDirectoryAccountType.official,
      _ => null,
    };
  }

  String get label => switch (this) {
    CreatorDirectoryAccountType.creator => 'Creator',
    CreatorDirectoryAccountType.official => 'Official',
  };
}

class CreatorSearchResult {
  const CreatorSearchResult({
    required this.uid,
    required this.displayName,
    required this.username,
    required this.photoUrl,
    required this.bio,
    required this.statusMessage,
    required this.accountType,
    required this.premiumIdentity,
    required this.followerCount,
  });

  final String uid;
  final String displayName;
  final String username;
  final String? photoUrl;
  final String bio;
  final String statusMessage;
  final CreatorDirectoryAccountType accountType;
  final bool premiumIdentity;
  final int followerCount;

  String get supportingText {
    final status = statusMessage.trim();
    if (status.isNotEmpty) return status;
    final description = bio.trim();
    if (description.isNotEmpty) return description;
    return accountType == CreatorDirectoryAccountType.official
        ? 'Official voice on YO Voice'
        : 'Creating conversations on YO Voice';
  }

  factory CreatorSearchResult.fromMap(Map<String, dynamic> data) {
    final type = CreatorDirectoryAccountType.fromValue(data['accountType']);
    if (type == null) {
      throw const FormatException('The profile is not a creator.');
    }
    final uid = (data['uid'] as String?)?.trim() ?? '';
    if (uid.isEmpty) throw const FormatException('Creator uid is missing.');
    final displayName = (data['displayName'] as String?)?.trim() ?? '';
    final username = (data['username'] as String?)?.trim() ?? '';
    final photoUrl = (data['photoUrl'] as String?)?.trim();
    final followerCount = (data['followerCount'] as num?)?.toInt() ?? 0;
    return CreatorSearchResult(
      uid: uid,
      displayName: displayName.isEmpty
          ? (username.isEmpty ? 'YO Voice creator' : username)
          : displayName,
      username: username,
      photoUrl: photoUrl?.isEmpty == true ? null : photoUrl,
      bio: (data['bio'] as String?)?.trim() ?? '',
      statusMessage: (data['statusMessage'] as String?)?.trim() ?? '',
      accountType: type,
      premiumIdentity: data['premiumIdentity'] as bool? ?? false,
      followerCount: followerCount.clamp(0, 1 << 31),
    );
  }
}
