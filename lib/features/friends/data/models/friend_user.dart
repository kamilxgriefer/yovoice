import 'package:cloud_firestore/cloud_firestore.dart';

enum FriendRelationshipStatus {
  none,
  friends,
  requestSent,
  requestReceived,
  blocked;

  static FriendRelationshipStatus? fromWire(Object? value) => switch (value) {
    'none' => FriendRelationshipStatus.none,
    'friends' => FriendRelationshipStatus.friends,
    'requestSent' => FriendRelationshipStatus.requestSent,
    'requestReceived' => FriendRelationshipStatus.requestReceived,
    'blocked' => FriendRelationshipStatus.blocked,
    _ => null,
  };
}

class FriendUser {
  const FriendUser({
    required this.id,
    required this.displayName,
    required this.email,
    required this.photoUrl,
    required this.isOnline,
    required this.lastSeen,
    this.availability,
    this.username = '',
    this.premiumIdentity = false,
    this.profileUpdatedAt,
    this.relationshipStatus,
  });

  final String id;
  final String displayName;
  final String username;
  final String email;
  final String? photoUrl;
  final bool isOnline;
  final DateTime? lastSeen;

  /// Projected availability from `socialPresence` ('available' | 'away' |
  /// 'busy' | 'offline'); null when the projection predates the field.
  /// Never 'invisible' — the server masks that to offline.
  final String? availability;
  final DateTime? profileUpdatedAt;

  /// Server-resolved state returned with public-search results. Null means
  /// the caller is talking to an older callable and should use the legacy
  /// relationship lookup as a backward-compatible fallback.
  final FriendRelationshipStatus? relationshipStatus;

  /// The server-written public mirror of the premium entitlement, read
  /// straight off the user document. Never a locally computed flag —
  /// only Cloud Functions write it.
  final bool premiumIdentity;

  String get initial {
    final normalizedName = displayName.trim();

    if (normalizedName.isNotEmpty) {
      return normalizedName[0].toUpperCase();
    }

    final normalizedUsername = username.trim();

    if (normalizedUsername.isNotEmpty) {
      return normalizedUsername[0].toUpperCase();
    }

    final normalizedEmail = email.trim();

    if (normalizedEmail.isNotEmpty) {
      return normalizedEmail[0].toUpperCase();
    }

    return '?';
  }

  String get searchableDisplayName {
    return displayName.trim().toLowerCase();
  }

  String get searchableUsername {
    return username.trim().toLowerCase();
  }

  String get searchableEmail {
    return email.trim().toLowerCase();
  }

  factory FriendUser.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();

    if (data == null) {
      throw StateError(
        'User document ${document.id} does not contain any data.',
      );
    }

    return FriendUser(
      id: document.id,
      displayName: _resolveDisplayName(data),
      username: _normalizeString(data['username']),
      // Public profile reads never carry email. Keep the compatibility field
      // empty and presence false even if a malformed projection somehow
      // contains either. FriendService joins the separately authorised
      // socialPresence document after loading identity.
      email: '',
      photoUrl: null,
      isOnline: false,
      lastSeen: null,
      premiumIdentity: data['premiumIdentity'] as bool? ?? false,
      profileUpdatedAt: _dateTime(
        data['profileUpdatedAt'] ?? data['updatedAt'],
      ),
      relationshipStatus: FriendRelationshipStatus.fromWire(
        data['relationshipStatus'],
      ),
    );
  }

  factory FriendUser.fromMap({
    required String id,
    required Map<String, dynamic> data,
  }) {
    return FriendUser(
      id: id,
      displayName: _resolveDisplayName(data),
      username: _normalizeString(data['username']),
      email: '',
      photoUrl: null,
      isOnline: false,
      lastSeen: null,
      premiumIdentity: data['premiumIdentity'] as bool? ?? false,
      profileUpdatedAt: _dateTime(
        data['profileUpdatedAtMillis'] ??
            data['profileUpdatedAt'] ??
            data['updatedAt'],
      ),
      relationshipStatus: FriendRelationshipStatus.fromWire(
        data['relationshipStatus'],
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': id,
      'displayName': displayName.trim(),
      'username': username.trim(),
      'email': email.trim().toLowerCase(),
      'photoUrl': photoUrl,
      'isOnline': isOnline,
      'lastSeen': lastSeen == null ? null : Timestamp.fromDate(lastSeen!),
    };
  }

  FriendUser copyWith({
    String? id,
    String? displayName,
    String? username,
    String? email,
    String? photoUrl,
    bool clearPhotoUrl = false,
    bool? isOnline,
    DateTime? lastSeen,
    bool clearLastSeen = false,
    String? availability,
    bool clearAvailability = false,
    bool? premiumIdentity,
    DateTime? profileUpdatedAt,
    bool clearProfileUpdatedAt = false,
    FriendRelationshipStatus? relationshipStatus,
    bool clearRelationshipStatus = false,
  }) {
    return FriendUser(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      email: email ?? this.email,
      photoUrl: clearPhotoUrl ? null : photoUrl ?? this.photoUrl,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: clearLastSeen ? null : lastSeen ?? this.lastSeen,
      availability: clearAvailability
          ? null
          : availability ?? this.availability,
      premiumIdentity: premiumIdentity ?? this.premiumIdentity,
      profileUpdatedAt: clearProfileUpdatedAt
          ? null
          : profileUpdatedAt ?? this.profileUpdatedAt,
      relationshipStatus: clearRelationshipStatus
          ? null
          : relationshipStatus ?? this.relationshipStatus,
    );
  }

  static String _resolveDisplayName(Map<String, dynamic> data) {
    final possibleNames = [data['displayName'], data['username'], data['name']];

    for (final value in possibleNames) {
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    return 'YO Voice user';
  }

  static String? _normalizeNullableString(Object? value) {
    if (value is! String) {
      return null;
    }

    final normalizedValue = value.trim();

    if (normalizedValue.isEmpty) {
      return null;
    }

    return normalizedValue;
  }

  static String _normalizeString(Object? value) {
    return _normalizeNullableString(value) ?? '';
  }

  static DateTime? _dateTime(Object? value) => switch (value) {
    Timestamp timestamp => timestamp.toDate(),
    int milliseconds when milliseconds > 0 =>
      DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true),
    num milliseconds when milliseconds.isFinite && milliseconds > 0 =>
      DateTime.fromMillisecondsSinceEpoch(milliseconds.toInt(), isUtc: true),
    DateTime dateTime => dateTime,
    _ => null,
  };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is FriendUser &&
            runtimeType == other.runtimeType &&
            id == other.id;
  }

  @override
  int get hashCode => id.hashCode;
}
