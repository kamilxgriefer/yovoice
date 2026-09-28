import 'package:cloud_functions/cloud_functions.dart';

import 'package:yovoice/features/reels/data/models/reel_composition.dart';

/// Wire fixtures for comment likes (ADR-230, spec §3.4-§3.6): the exact v2
/// Voice Moment and Yeel view shapes, with or without `commentLikes`.

const int kCommentFixtureMillis = 1_800_000_000_000;
const String kCommentFixtureReceipt =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<Object?, Object?> voiceMomentWire({
  String id = 'm1',
  int expiresInHours = 24,
  DateTime? createdAt,
}) {
  final created =
      (createdAt ?? DateTime.now().subtract(const Duration(hours: 1)))
          .millisecondsSinceEpoch;
  return <Object?, Object?>{
    'schemaVersion': 2,
    'momentId': id,
    'authorId': 'nadia',
    'authorName': 'Nadia Rutkowska',
    'authorPhotoUrl': null,
    'caption': 'The night bus is where the truth lives.',
    'durationSeconds': 27,
    'likeCount': 4,
    'commentCount': 2,
    'callerLiked': false,
    'createdAtMillis': created,
    'publishedAtMillis': created,
    'expiresAtMillis': created + expiresInHours * 3_600_000,
    'reportReceipt': kCommentFixtureReceipt,
  };
}

Map<Object?, Object?> voiceCommentWire(
  String id, {
  String authorId = 'zofia',
  String authorName = 'Zofia Wróblewska',
  String text = 'Słychać cały poranek.',
  int offsetMillis = 0,
  DateTime? createdAt,
}) => <Object?, Object?>{
  'schemaVersion': 2,
  'commentId': id,
  'type': 'text',
  'authorId': authorId,
  'authorName': authorName,
  'authorPhotoUrl': null,
  'text': text,
  'durationSeconds': null,
  'createdAtMillis':
      (createdAt ?? DateTime.now().subtract(const Duration(minutes: 30)))
          .millisecondsSinceEpoch +
      offsetMillis,
  'reportReceipt': kCommentFixtureReceipt,
};

Map<Object?, Object?> likeStateWire(int count, {bool liked = false}) =>
    <Object?, Object?>{'likeCount': count, 'callerLiked': liked};

Map<Object?, Object?> voiceViewWire({
  Map<Object?, Object?>? moment,
  List<Map<Object?, Object?>>? comments,
  Map<Object?, Object?>? commentLikes,
  bool truncated = false,
  String? cursor,
}) => <Object?, Object?>{
  'schemaVersion': 2,
  'moment': moment ?? voiceMomentWire(),
  'comments': comments ?? <Map<Object?, Object?>>[voiceCommentWire('c1')],
  'commentsTruncated': truncated,
  'nextCommentCursor': cursor,
  'topReactions': const <Object?>[],
  'commentLikes': ?commentLikes,
};

Map<String, Object?> reelWire({String id = 'reel_1', int commentCount = 2}) {
  const millis = 1725000000000;
  return <String, Object?>{
    'id': id,
    'authorId': 'creator_1',
    'authorName': 'Creator One',
    'media': <String, Object?>{
      'kind': 'video',
      'contentType': 'video/mp4',
      'size': 4096,
      'generation': '7',
      'durationMs': 10000,
    },
    'backingAudio': null,
    'composition': const ReelComposition(
      trimStartMs: 0,
      trimEndMs: 10000,
    ).toWire(),
    'publishedAtMillis': millis,
    'sortKey': '${millis}_$id',
    'availability': <String, Object?>{
      'schemaVersion': 1,
      'availabilityHours': 'permanent',
      'expiresAtMillis': null,
    },
    'likeCount': 0,
    'commentCount': commentCount,
    'callerLiked': false,
  };
}

Map<String, Object?> reelCommentWire(
  String id, {
  String authorId = 'zofia',
  String authorName = 'Zofia Wróblewska',
  String text = 'Gdzie to było?',
}) => <String, Object?>{
  'schemaVersion': 1,
  'commentId': id,
  'type': 'text',
  'authorId': authorId,
  'authorName': authorName,
  'authorPhotoUrl': null,
  'text': text,
  'durationSeconds': null,
  'createdAtMillis': 1725000100000,
};

Map<Object?, Object?> reelViewWire({
  List<Map<String, Object?>>? comments,
  Map<Object?, Object?>? commentLikes,
  String? cursor,
}) => <Object?, Object?>{
  'schemaVersion': 2,
  'reel': reelWire(),
  'comments': comments ?? <Map<String, Object?>>[reelCommentWire('c1')],
  'commentsTruncated': cursor != null,
  'nextCommentCursor': cursor,
  'commentLikes': ?commentLikes,
};

FirebaseFunctionsException callableError(String code) =>
    FirebaseFunctionsException(code: code, message: code);
