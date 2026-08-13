import 'package:cloud_firestore/cloud_firestore.dart';

enum ClubPrivacy {
  public,
  private,
  inviteOnly;

  static ClubPrivacy fromValue(Object? value) {
    return switch (value) {
      'private' => ClubPrivacy.private,
      'inviteOnly' => ClubPrivacy.inviteOnly,
      _ => ClubPrivacy.public,
    };
  }
}

/// What a club document IS. A Family Room is not a parallel product: it
/// is a Club with a private data boundary, so it reuses this document,
/// its members, roles, invites, channels and lounge wholesale.
///
/// Written once at creation and immutable in `firestore.rules` — a
/// community club can never become a family space, or the reverse.
enum ClubType {
  community,
  family;

  static ClubType fromValue(Object? value) {
    return value == 'family' ? ClubType.family : ClubType.community;
  }
}

class Club {
  const Club({
    required this.id,
    required this.name,
    required this.description,
    required this.ownerId,
    required this.ownerName,
    required this.avatarUrl,
    required this.bannerUrl,
    required this.privacy,
    required this.defaultLanguage,
    required this.memberCount,
    required this.onlineCount,
    required this.defaultChatChannelId,
    required this.defaultVoiceChannelId,
    required this.announcementChannelId,
    required this.createdAt,
    required this.updatedAt,
    this.type = ClubType.community,
  });

  /// A Family Room lives at a deterministic id. That id is what makes
  /// "one per account" enforceable in rules, which cannot count
  /// documents but can refuse every id except this one.
  static String familyRoomIdFor(String uid) => 'family_$uid';

  final String id;
  final String name;
  final String description;
  final String ownerId;
  final String ownerName;
  final String? avatarUrl;
  final String? bannerUrl;
  final ClubPrivacy privacy;
  final String defaultLanguage;
  final int memberCount;
  final int onlineCount;
  final String defaultChatChannelId;
  final String defaultVoiceChannelId;
  final String announcementChannelId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final ClubType type;

  bool get isFamilyRoom => type == ClubType.family;

  String get initial {
    final normalized = name.trim();
    return normalized.isEmpty ? 'C' : normalized[0].toUpperCase();
  }

  factory Club.fromFirestore(DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data();
    if (data == null) {
      throw StateError('Club ${document.id} does not contain data.');
    }

    return Club(
      id: document.id,
      name: (data['name'] as String?)?.trim() ?? 'Untitled club',
      description: (data['description'] as String?)?.trim() ?? '',
      ownerId: data['ownerId'] as String? ?? '',
      ownerName: (data['ownerName'] as String?)?.trim() ?? 'YO Voice user',
      avatarUrl: _nullableString(data['avatarUrl']),
      bannerUrl: _nullableString(data['bannerUrl']),
      privacy: ClubPrivacy.fromValue(data['privacy']),
      defaultLanguage:
          (data['defaultLanguage'] as String?)?.trim() ?? 'English',
      memberCount: (data['memberCount'] as num?)?.toInt() ?? 0,
      onlineCount: (data['onlineCount'] as num?)?.toInt() ?? 0,
      defaultChatChannelId: data['defaultChatChannelId'] as String? ?? '',
      defaultVoiceChannelId: data['defaultVoiceChannelId'] as String? ?? '',
      announcementChannelId: data['announcementChannelId'] as String? ?? '',
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
      type: ClubType.fromValue(data['type']),
    );
  }

  static String? _nullableString(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  static DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
