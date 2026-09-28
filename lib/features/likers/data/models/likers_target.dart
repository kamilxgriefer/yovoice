import 'package:flutter/foundation.dart';

/// What a "See who liked" list is about (spec §5.0, ADR-230).
///
/// One sealed family maps onto the four server-projected list callables:
/// Voice Moments and their comments go to `listVoiceMomentLikersV1`, Yeels
/// and their comments to `listReelLikersV1`, Server channel messages to
/// `listServerChannelMessageReactorsV1`, and Premium Page posts to
/// `listPagePostLikersV1` (ADR-233, post likes only, D15). The server is the
/// only authority on who is listed; a target carries ids, never names or
/// counts.
@immutable
sealed class LikersTarget {
  const LikersTarget();

  /// The callable that lists this target.
  String get callableName;

  /// The exact request body for one page, without a `limit` (the page size
  /// is a server constant and a `limit` key is refused, spec §3.0). Optional
  /// keys are omitted rather than sent as null.
  Map<String, Object?> payload({String? cursor});

  /// Server targets list emoji reactions; every other target lists likes.
  bool get isReactions => false;
}

final class VoiceMomentLikersTarget extends LikersTarget {
  const VoiceMomentLikersTarget(this.momentId);

  final String momentId;

  @override
  String get callableName => 'listVoiceMomentLikersV1';

  @override
  Map<String, Object?> payload({String? cursor}) => <String, Object?>{
    'momentId': momentId,
    'cursor': ?cursor,
  };

  @override
  bool operator ==(Object other) =>
      other is VoiceMomentLikersTarget && other.momentId == momentId;

  @override
  int get hashCode => Object.hash(VoiceMomentLikersTarget, momentId);
}

final class VoiceMomentCommentLikersTarget extends LikersTarget {
  const VoiceMomentCommentLikersTarget(this.momentId, this.commentId);

  final String momentId;
  final String commentId;

  @override
  String get callableName => 'listVoiceMomentLikersV1';

  @override
  Map<String, Object?> payload({String? cursor}) => <String, Object?>{
    'momentId': momentId,
    'commentId': commentId,
    'cursor': ?cursor,
  };

  @override
  bool operator ==(Object other) =>
      other is VoiceMomentCommentLikersTarget &&
      other.momentId == momentId &&
      other.commentId == commentId;

  @override
  int get hashCode =>
      Object.hash(VoiceMomentCommentLikersTarget, momentId, commentId);
}

final class ReelLikersTarget extends LikersTarget {
  const ReelLikersTarget(this.reelId);

  final String reelId;

  @override
  String get callableName => 'listReelLikersV1';

  @override
  Map<String, Object?> payload({String? cursor}) => <String, Object?>{
    'reelId': reelId,
    'cursor': ?cursor,
  };

  @override
  bool operator ==(Object other) =>
      other is ReelLikersTarget && other.reelId == reelId;

  @override
  int get hashCode => Object.hash(ReelLikersTarget, reelId);
}

final class ReelCommentLikersTarget extends LikersTarget {
  const ReelCommentLikersTarget(this.reelId, this.commentId);

  final String reelId;
  final String commentId;

  @override
  String get callableName => 'listReelLikersV1';

  @override
  Map<String, Object?> payload({String? cursor}) => <String, Object?>{
    'reelId': reelId,
    'commentId': commentId,
    'cursor': ?cursor,
  };

  @override
  bool operator ==(Object other) =>
      other is ReelCommentLikersTarget &&
      other.reelId == reelId &&
      other.commentId == commentId;

  @override
  int get hashCode => Object.hash(ReelCommentLikersTarget, reelId, commentId);
}

final class ServerMessageReactorsTarget extends LikersTarget {
  const ServerMessageReactorsTarget(
    this.serverId,
    this.channelId,
    this.messageId, {
    this.emoji,
  });

  final String serverId;
  final String channelId;
  final String messageId;

  /// Optional filter: one of the six message reactions, or null for all.
  final String? emoji;

  /// The same message filtered to [emoji] (null = every reaction).
  ServerMessageReactorsTarget withEmoji(String? emoji) =>
      ServerMessageReactorsTarget(serverId, channelId, messageId, emoji: emoji);

  @override
  String get callableName => 'listServerChannelMessageReactorsV1';

  @override
  bool get isReactions => true;

  @override
  Map<String, Object?> payload({String? cursor}) => <String, Object?>{
    'serverId': serverId,
    'channelId': channelId,
    'messageId': messageId,
    'emoji': ?emoji,
    'cursor': ?cursor,
  };

  @override
  bool operator ==(Object other) =>
      other is ServerMessageReactorsTarget &&
      other.serverId == serverId &&
      other.channelId == channelId &&
      other.messageId == messageId &&
      other.emoji == emoji;

  @override
  int get hashCode => Object.hash(
    ServerMessageReactorsTarget,
    serverId,
    channelId,
    messageId,
    emoji,
  );
}

/// A Premium Page post (spec premium-pages §2.6): `{postId, cursor?}`. There
/// is no comment target in v1 (D15).
final class PagePostLikersTarget extends LikersTarget {
  const PagePostLikersTarget(this.postId);

  final String postId;

  @override
  String get callableName => 'listPagePostLikersV1';

  @override
  Map<String, Object?> payload({String? cursor}) => <String, Object?>{
    'postId': postId,
    'cursor': ?cursor,
  };

  @override
  bool operator ==(Object other) =>
      other is PagePostLikersTarget && other.postId == postId;

  @override
  int get hashCode => Object.hash(PagePostLikersTarget, postId);
}
