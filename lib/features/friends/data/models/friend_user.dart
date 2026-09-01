import 'package:cloud_firestore/cloud_firestore.dart';

class FriendUser {
  const FriendUser({
    required this.id,
    required this.displayName,
    required this.email,
    required this.photoUrl,
    required this.isOnline,
    required this.lastSeen,
    this.username = '',
    this.premiumIdentity = false,
  });

  final String id;
  final String displayName;
  final String username;
  final String email;
  final String? photoUrl;
  final bool isOnline;
  final DateTime? lastSeen;

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
    bool? premiumIdentity,
  }) {
    return FriendUser(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      email: email ?? this.email,
      photoUrl: clearPhotoUrl ? null : photoUrl ?? this.photoUrl,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: clearLastSeen ? null : lastSeen ?? this.lastSeen,
      premiumIdentity: premiumIdentity ?? this.premiumIdentity,
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
