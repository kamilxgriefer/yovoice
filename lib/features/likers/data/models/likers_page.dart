import 'package:flutter/foundation.dart';

import 'package:yovoice/shared/widgets/interactions/message_reactions.dart';

/// The server's fixed page size (`LIKERS_PAGE_SIZE`, spec §3.0). The client
/// never sends a page size; it only refuses a page longer than this.
const int kLikersPageSize = 20;

final RegExp _cursorPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');
final RegExp _controlCharacters = RegExp(r'[\x00-\x1F\x7F]');

/// One listed person, exactly as the list callables project them
/// (spec §3.0): `{userId, displayName, photoUrl, reaction}`.
///
/// There is deliberately no avatar URL and no username: `photoUrl` is always
/// null on the wire (avatars resolve through `UserAvatar(userId:)`'s
/// viewer-authorised grant) and the contract carries no public handle.
@immutable
class Liker {
  const Liker({required this.userId, required this.displayName, this.reaction});

  final String userId;
  final String displayName;

  /// The emoji for a Server message reactor; null for a like.
  final String? reaction;

  factory Liker.parse(Object? value) {
    final data = _exactMap(value, const <String>{
      'userId',
      'displayName',
      'photoUrl',
      'reaction',
    }, 'Liker');
    _expect(data['photoUrl'] == null, 'Durable liker artwork is forbidden.');
    final userId = data['userId'];
    _expect(
      userId is String &&
          userId.isNotEmpty &&
          userId.length <= 128 &&
          !userId.contains('/') &&
          !_controlCharacters.hasMatch(userId),
      'Malformed liker userId.',
    );
    final displayName = data['displayName'];
    _expect(
      displayName is String &&
          displayName.isNotEmpty &&
          displayName.length <= 80 &&
          displayName.trim() == displayName,
      'Malformed liker displayName.',
    );
    final reaction = data['reaction'];
    _expect(
      reaction == null ||
          (reaction is String && kMessageReactionEmojis.contains(reaction)),
      'Malformed liker reaction.',
    );
    return Liker(
      userId: userId as String,
      displayName: displayName as String,
      reaction: reaction as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Liker &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.reaction == reaction;

  @override
  int get hashCode => Object.hash(userId, displayName, reaction);
}

/// One page of a likers list: EXACTLY
/// `{schemaVersion: 1, likers, nextCursor, hasMore}` (spec §3.0, §5.0).
///
/// Anything else is a contract break and throws [FormatException]: an extra
/// or missing key, more than [kLikersPageSize] likers, a cursor that is not
/// the 43-character opaque token, or `hasMore` disagreeing with the cursor.
@immutable
class LikersPage {
  const LikersPage({
    required this.likers,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<Liker> likers;
  final String? nextCursor;
  final bool hasMore;

  factory LikersPage.parse(Object? value) {
    final data = _exactMap(value, const <String>{
      'schemaVersion',
      'likers',
      'nextCursor',
      'hasMore',
    }, 'Likers page');
    _expect(data['schemaVersion'] == 1, 'Unsupported likers page version.');
    final rawLikers = data['likers'];
    _expect(rawLikers is List, 'Likers page likers must be a list.');
    final list = rawLikers as List<Object?>;
    _expect(list.length <= kLikersPageSize, 'Likers page is too long.');
    final cursor = data['nextCursor'];
    _expect(
      cursor == null || (cursor is String && _cursorPattern.hasMatch(cursor)),
      'Malformed likers cursor.',
    );
    final hasMore = data['hasMore'];
    _expect(hasMore is bool, 'Malformed likers hasMore.');
    _expect(
      hasMore == (cursor != null),
      'Likers hasMore disagrees with nextCursor.',
    );
    return LikersPage(
      likers: List<Liker>.unmodifiable(list.map(Liker.parse)),
      nextCursor: cursor as String?,
      hasMore: hasMore as bool,
    );
  }
}

Map<String, Object?> _exactMap(
  Object? value,
  Set<String> expected,
  String label,
) {
  _expect(value is Map, '$label must be an object.');
  final source = value as Map<Object?, Object?>;
  _expect(source.keys.every((key) => key is String), '$label has bad keys.');
  final data = <String, Object?>{
    for (final entry in source.entries) entry.key as String: entry.value,
  };
  _expect(
    data.length == expected.length && data.keys.toSet().containsAll(expected),
    '$label schema does not match the likers contract.',
  );
  return data;
}

void _expect(bool condition, String message) {
  if (!condition) throw FormatException(message);
}
