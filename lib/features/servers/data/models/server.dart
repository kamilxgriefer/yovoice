import 'package:characters/characters.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'server_member_role.dart';
import 'server_type.dart';

/// An additive domain view of clubs/{id}; reading never migrates data.
class Server {
  const Server({
    required this.id,
    required this.name,
    required this.description,
    required this.ownerId,
    required this.type,
    required this.privacy,
    this.defaultLanguage = 'English',
    this.memberCount = 0,
    this.defaultChannelId,
    this.defaultVoiceChannelId,
    this.loungeRoomId,
    this.schemaVersion,
    this.templateVersion,
    this.revision = 0,
    this.activationState,
    this.entitlementPolicyId,
    this.status = 'active',
    this.directoryRole,
  });

  final String id;
  final String name;
  final String description;
  final String ownerId;
  final ServerType type;
  final ServerPrivacy privacy;
  final String defaultLanguage;
  final int memberCount;
  final String? defaultChannelId;
  final String? defaultVoiceChannelId;
  final String? loungeRoomId;
  final int? schemaVersion;
  final int? templateVersion;
  final int revision;
  final String? activationState;
  final String? entitlementPolicyId;
  final String status;

  /// The viewer's role as their own `users/{uid}/clubs/{id}` directory mirror
  /// records it — never a field of `clubs/{id}` itself, so it is not parsed
  /// from the root. It only decides which directory action to OFFER (delete
  /// for the owner, leave for everyone else); every action it opens is
  /// re-proven by its callable, so a stale mirror can at worst show an action
  /// the backend then refuses. Null when the mirror carries no known role.
  final ServerMemberRole? directoryRole;

  /// The same root read, annotated with the viewer's directory-mirror role.
  Server withDirectoryRole(ServerMemberRole? role) => Server(
    id: id,
    name: name,
    description: description,
    ownerId: ownerId,
    type: type,
    privacy: privacy,
    defaultLanguage: defaultLanguage,
    memberCount: memberCount,
    defaultChannelId: defaultChannelId,
    defaultVoiceChannelId: defaultVoiceChannelId,
    loungeRoomId: loungeRoomId,
    schemaVersion: schemaVersion,
    templateVersion: templateVersion,
    revision: revision,
    activationState: activationState,
    entitlementPolicyId: entitlementPolicyId,
    status: status,
    directoryRole: role,
  );

  bool get isLegacy => schemaVersion == null;
  bool get isHeld => !isLegacy && activationState != 'active';
  String get initial =>
      name.trim().isEmpty ? 'YO' : name.trim().characters.first.toUpperCase();

  factory Server.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) throw const FormatException('Server is unavailable.');
    return Server.fromMap(doc.id, data);
  }

  factory Server.fromMap(String id, Map<String, dynamic> data) {
    final version = data['serverSchemaVersion'];
    if (version != null && version != 1) {
      throw const FormatException('Unsupported server schema version.');
    }
    final legacy = version == null;
    final type = legacy
        ? (data['type'] == 'family' ? ServerType.family : ServerType.community)
        : ServerType.parse(data['serverType']);
    final privacy = legacy
        ? (type == ServerType.family
              ? ServerPrivacy.inviteOnly
              : switch (data['privacy']) {
                  'private' => ServerPrivacy.private,
                  'inviteOnly' => ServerPrivacy.inviteOnly,
                  _ => ServerPrivacy.public,
                })
        : ServerPrivacy.parse(data['privacy']);
    if (!legacy &&
        ((type == ServerType.family && privacy != ServerPrivacy.inviteOnly) ||
            (!type.allowsPublic && privacy == ServerPrivacy.public))) {
      throw const FormatException('Invalid server privacy boundary.');
    }
    final name = serverString(data['name']) ?? '';
    final owner = serverString(data['ownerId']) ?? '';
    if (!legacy && (name.isEmpty || owner.isEmpty)) {
      throw const FormatException('Invalid server identity.');
    }
    return Server(
      id: id,
      name: name,
      description: serverString(data['description']) ?? '',
      ownerId: owner,
      type: type,
      privacy: privacy,
      defaultLanguage: serverString(data['defaultLanguage']) ?? 'English',
      memberCount: serverInt(data['memberCount']),
      defaultChannelId:
          serverString(data['defaultChannelId']) ??
          serverString(data['defaultChatChannelId']),
      defaultVoiceChannelId: serverString(data['defaultVoiceChannelId']),
      loungeRoomId: serverString(data['loungeRoomId']),
      schemaVersion: legacy ? null : 1,
      templateVersion: data['templateVersion'] is int
          ? data['templateVersion'] as int
          : null,
      revision: serverInt(data['revision']),
      activationState: serverString(data['serverActivationState']),
      entitlementPolicyId: serverString(data['entitlementPolicyId']),
      status: serverString(data['status']) ?? (legacy ? 'active' : 'unknown'),
    );
  }
}

String? serverString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

int serverInt(Object? value) =>
    value is num && value.isFinite && value >= 0 ? value.toInt() : 0;
