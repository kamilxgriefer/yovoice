import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:yovoice/features/media/data/models/gif_asset.dart';

/// A Servers V1 photo or video written by
/// `finalizeServerChannelMessageMediaV1`: the private object's path,
/// generation and bounded metadata — never a URL. Bytes are read only through
/// a short-lived grant from `getServerChannelMessageMediaAccessV1`.
class ClubMessageMedia {
  const ClubMessageMedia({
    required this.type,
    required this.storagePath,
    required this.generation,
    required this.contentType,
    required this.size,
    this.durationSeconds,
  });

  /// `image` or `video`.
  final String type;
  final String storagePath;
  final String generation;
  final String contentType;
  final int size;

  /// Whole seconds, 1-60, for a video; null for a photo.
  final int? durationSeconds;

  bool get isVideo => type == 'video';

  static final _generation = RegExp(r'^[0-9]{1,30}$');

  /// The descriptor of a live media message, or null for anything else: a
  /// removed message, a text/GIF message, or a malformed descriptor (which
  /// then renders as its `Photo`/`Video` content fallback, never a guess).
  static ClubMessageMedia? fromMessage(Map<String, dynamic> data) {
    if (data['isDeleted'] == true) return null;
    final type = data['type'];
    if (type != 'image' && type != 'video') return null;
    final media = data['media'];
    if (media is! Map) return null;
    final storagePath = media['storagePath'];
    final generation = media['generation'];
    final contentType = media['contentType'];
    final size = media['size'];
    final duration = media['durationSeconds'];
    if (storagePath is! String ||
        !storagePath.startsWith('server_message_media/') ||
        generation is! String ||
        !_generation.hasMatch(generation) ||
        contentType is! String ||
        contentType.isEmpty ||
        size is! num ||
        size <= 0) {
      return null;
    }
    int? durationSeconds;
    if (type == 'video') {
      if (duration is! num || duration < 1 || duration > 60) return null;
      durationSeconds = duration.toInt();
    } else if (duration != null) {
      return null;
    }
    return ClubMessageMedia(
      type: type as String,
      storagePath: storagePath,
      generation: generation,
      contentType: contentType,
      size: size.toInt(),
      durationSeconds: durationSeconds,
    );
  }
}

class ClubMessage {
  const ClubMessage({
    required this.id,
    required this.clubId,
    required this.channelId,
    required this.senderId,
    required this.senderName,
    required this.senderPhotoUrl,
    required this.content,
    required this.sentAt,
    required this.editedAt,
    required this.isDeleted,
    this.deletedBy,
    this.deletedByRole,
    this.gif,
    this.reactions = const <String, String>{},
    this.type,
    this.media,
  });

  final String id;
  final String clubId;
  final String channelId;
  final String senderId;
  final String senderName;
  final String? senderPhotoUrl;
  final String content;
  final DateTime sentAt;
  final DateTime? editedAt;
  final bool isDeleted;
  final GifAsset? gif;

  /// One reaction per person, `uid -> emoji`, written only by the
  /// `setServerChannelMessageReactionV1` callable (Servers V1). Absent on
  /// every older message and read as empty; a removed message shows none.
  final Map<String, String> reactions;

  /// The stored message type: absent (plain text), `gif`, `image` or
  /// `video`. Unknown values are kept so a newer type is never misread as
  /// text by this model; renderers still fall back to [content].
  final String? type;

  /// The photo or video of a live media message; null otherwise.
  final ClubMessageMedia? media;

  /// Who performed the removal. Absent on live messages, and absent on
  /// removals written before the client started stamping it — so a null
  /// value means "unknown", never "the author did it".
  final String? deletedBy;

  /// The staff role recorded against a removal, written only by
  /// `adminDeleteMessage` through the Admin SDK. Clients cannot write it:
  /// it is absent from the update allowlist in `firestore.rules`, and the
  /// create allowlist's `hasOnly` keeps it from being forged at birth.
  final String? deletedByRole;

  /// A YO Voice staff redaction, which is NOT the same act as a club
  /// moderator's and must not be reported as one — moderators are told in
  /// product copy that the club owner's messages are staff-only, so
  /// labelling a staff removal "by a moderator" would describe something
  /// the app says is impossible and pin a platform decision on the club's
  /// volunteers.
  bool get wasRemovedByStaff =>
      isDeleted && (deletedByRole?.isNotEmpty ?? false);

  /// A club moderator reaching into somebody else's message. An
  /// unattributed removal is deliberately excluded: a null `deletedBy`
  /// means "unknown", never "the author did it".
  bool get wasRemovedByModerator =>
      isDeleted &&
      !wasRemovedByStaff &&
      deletedBy != null &&
      deletedBy != senderId;

  factory ClubMessage.fromFirestore({
    required String clubId,
    required String channelId,
    required DocumentSnapshot<Map<String, dynamic>> document,
  }) {
    final data = document.data() ?? const <String, dynamic>{};
    return ClubMessage(
      id: document.id,
      clubId: clubId,
      channelId: channelId,
      senderId: data['senderId'] as String? ?? '',
      senderName: (data['senderName'] as String?)?.trim().isNotEmpty == true
          ? (data['senderName'] as String).trim()
          : 'YO Voice user',
      senderPhotoUrl: null,
      content: data['content'] as String? ?? '',
      sentAt:
          _readDate(data['sentAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      editedAt: _readDate(data['editedAt']),
      isDeleted: data['isDeleted'] as bool? ?? false,
      gif: data['isDeleted'] == true || data['type'] != 'gif'
          ? null
          : GifAsset.fromMessage(data['gif']),
      deletedBy: _nullableString(data['deletedBy']),
      deletedByRole: _nullableString(data['deletedByRole']),
      reactions: data['isDeleted'] == true
          ? const <String, String>{}
          : _stringMap(data['reactions']),
      type: _nullableString(data['type']),
      media: ClubMessageMedia.fromMessage(data),
    );
  }

  /// `Message._stringMap`'s rule: only string -> non-empty string entries
  /// survive, anything else is dropped rather than guessed.
  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) return const <String, String>{};
    final result = <String, String>{};
    for (final entry in value.entries) {
      final key = entry.key;
      final emoji = entry.value;
      if (key is String &&
          key.isNotEmpty &&
          emoji is String &&
          emoji.isNotEmpty) {
        result[key] = emoji;
      }
    }
    return Map<String, String>.unmodifiable(result);
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
