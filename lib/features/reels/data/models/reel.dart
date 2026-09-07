import 'package:flutter/foundation.dart';

import 'package:yovoice/features/reels/data/models/reel_composition.dart';

/// Author-selected lifetime of one Reel.
///
/// The wire contract accepts whole hours from 24 through 720, or the literal
/// `permanent`. Presets live here so composer, retry state and service cannot
/// silently disagree about the value reserved by the backend.
@immutable
class ReelAvailabilityChoice {
  const ReelAvailabilityChoice._(this.hours);

  static const int minimumHours = 24;
  static const int maximumHours = 720;
  static const ReelAvailabilityChoice hours24 = ReelAvailabilityChoice._(24);
  static const ReelAvailabilityChoice days7 = ReelAvailabilityChoice._(168);
  static const ReelAvailabilityChoice days30 = ReelAvailabilityChoice._(720);
  static const ReelAvailabilityChoice permanent = ReelAvailabilityChoice._(
    null,
  );
  static const ReelAvailabilityChoice fallback = hours24;

  /// Null means "keep until deleted".
  final int? hours;

  bool get isPermanent => hours == null;
  Object get wireValue => hours ?? 'permanent';

  factory ReelAvailabilityChoice.timedHours(int hours) {
    if (hours < minimumHours || hours > maximumHours) {
      throw RangeError.range(hours, minimumHours, maximumHours, 'hours');
    }
    return ReelAvailabilityChoice._(hours);
  }

  factory ReelAvailabilityChoice.fromWire(Object? value) {
    if (value == 'permanent') return permanent;
    if (value is! int || value < minimumHours || value > maximumHours) {
      throw const FormatException('Invalid Reel availability.');
    }
    return ReelAvailabilityChoice.timedHours(value);
  }

  @override
  bool operator ==(Object other) =>
      other is ReelAvailabilityChoice && other.hours == hours;

  @override
  int get hashCode => hours.hashCode;
}

/// Server-stamped public availability carried by each v2 feed item.
@immutable
class ReelAvailability {
  const ReelAvailability({
    required this.schemaVersion,
    required this.choice,
    required this.contentExpiresAt,
  });

  static const ReelAvailability legacyPermanent = ReelAvailability(
    schemaVersion: 1,
    choice: ReelAvailabilityChoice.permanent,
    contentExpiresAt: null,
  );

  final int schemaVersion;
  final ReelAvailabilityChoice choice;

  /// Null only for permanent content. Timed content always has a server-owned
  /// absolute deadline; clients must not derive it from local publish time.
  final DateTime? contentExpiresAt;

  bool get isPermanent => choice.isPermanent;

  bool isAvailableAt(DateTime now) =>
      contentExpiresAt == null || contentExpiresAt!.isAfter(now.toUtc());

  @override
  bool operator ==(Object other) =>
      other is ReelAvailability &&
      other.schemaVersion == schemaVersion &&
      other.choice == choice &&
      other.contentExpiresAt == contentExpiresAt;

  @override
  int get hashCode => Object.hash(schemaVersion, choice, contentExpiresAt);

  factory ReelAvailability.fromWire(Object? value) {
    final map = _map(value, 'availability');
    _keys(map, const <String>{
      'schemaVersion',
      'availabilityHours',
      'expiresAtMillis',
    }, 'availability');
    final schemaVersion = _integer(
      map['schemaVersion'],
      'availability.schemaVersion',
    );
    if (schemaVersion != 1 && schemaVersion != 2) {
      throw const FormatException('Unsupported Reel availability schema.');
    }
    final choice = ReelAvailabilityChoice.fromWire(map['availabilityHours']);
    final rawExpiry = map['expiresAtMillis'];
    if (choice.isPermanent) {
      if (rawExpiry != null ||
          (schemaVersion == 1 && choice != ReelAvailabilityChoice.permanent)) {
        throw const FormatException('Malformed permanent Reel availability.');
      }
      return ReelAvailability(
        schemaVersion: schemaVersion,
        choice: choice,
        contentExpiresAt: null,
      );
    }
    if (schemaVersion != 2 || rawExpiry is! int || rawExpiry <= 0) {
      throw const FormatException('Malformed timed Reel availability.');
    }
    return ReelAvailability(
      schemaVersion: schemaVersion,
      choice: choice,
      contentExpiresAt: DateTime.fromMillisecondsSinceEpoch(
        rawExpiry,
        isUtc: true,
      ),
    );
  }
}

@immutable
class ReelMediaDescriptor {
  const ReelMediaDescriptor({
    required this.kind,
    required this.contentType,
    required this.size,
    required this.generation,
    required this.durationMs,
  });

  final ReelMediaKind kind;
  final String contentType;
  final int size;
  final String generation;
  final int durationMs;

  factory ReelMediaDescriptor.fromWire(Object? value) {
    final map = _map(value, 'media');
    _keys(map, const <String>{
      'kind',
      'contentType',
      'size',
      'generation',
      'durationMs',
    }, 'media');
    final kindName = _string(map['kind'], 'media.kind');
    final kind = ReelMediaKind.values.firstWhere(
      (value) => value.name == kindName,
      orElse: () => throw const FormatException('Unknown reel media kind.'),
    );
    final contentType = _string(map['contentType'], 'media.contentType');
    final size = _integer(map['size'], 'media.size');
    final generation = _string(map['generation'], 'media.generation');
    final duration = _integer(map['durationMs'], 'media.durationMs');
    if (!RegExp(r'^[0-9]{1,30}$').hasMatch(generation) ||
        size < 128 ||
        duration < 0 ||
        (kind == ReelMediaKind.image && duration != 0) ||
        (kind == ReelMediaKind.video &&
            (duration < 1000 || duration > 90 * 1000))) {
      throw const FormatException('Malformed reel media descriptor.');
    }
    return ReelMediaDescriptor(
      kind: kind,
      contentType: contentType,
      size: size,
      generation: generation,
      durationMs: duration,
    );
  }
}

@immutable
class ReelBackingAudioDescriptor {
  const ReelBackingAudioDescriptor({
    required this.contentType,
    required this.size,
    required this.generation,
    required this.durationMs,
  });

  final String contentType;
  final int size;
  final String generation;
  final int durationMs;

  factory ReelBackingAudioDescriptor.fromWire(Object? value) {
    final map = _map(value, 'backingAudio');
    _keys(map, const <String>{
      'contentType',
      'size',
      'generation',
      'durationMs',
    }, 'backingAudio');
    final descriptor = ReelBackingAudioDescriptor(
      contentType: _string(map['contentType'], 'backingAudio.contentType'),
      size: _integer(map['size'], 'backingAudio.size'),
      generation: _string(map['generation'], 'backingAudio.generation'),
      durationMs: _integer(map['durationMs'], 'backingAudio.durationMs'),
    );
    if (!RegExp(r'^[0-9]{1,30}$').hasMatch(descriptor.generation) ||
        descriptor.size < 512 ||
        descriptor.durationMs < 1000 ||
        descriptor.durationMs > 90 * 1000) {
      throw const FormatException('Malformed reel backing audio descriptor.');
    }
    return descriptor;
  }
}

@immutable
class Reel {
  const Reel({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.media,
    required this.composition,
    required this.publishedAt,
    required this.sortKey,
    this.backingAudio,
    this.availability = ReelAvailability.legacyPermanent,
    this.likeCount = 0,
    this.commentCount = 0,
    this.callerLiked = false,
  });

  final String id;
  final String authorId;
  final String authorName;
  final ReelMediaDescriptor media;
  final ReelBackingAudioDescriptor? backingAudio;
  final ReelComposition composition;
  final DateTime publishedAt;
  final String sortKey;
  final ReelAvailability availability;

  /// Server-owned engagement aggregates.
  ///
  /// The backend materializes `likeCount`/`commentCount` on the Reel root
  /// lazily: every Reel published before the engagement contract carries
  /// neither key and no backfill runs, so **absent is exactly zero**. The v1
  /// `listReels` projection never carries them at all. Both facts make these
  /// three fields optional on the wire and defaulted here rather than
  /// required — the alternative would reject every already-published Reel.
  final int likeCount;
  final int commentCount;

  /// Whether the *calling* viewer has liked this Reel. Never an aggregate:
  /// the backend answers it from this viewer's own like edge.
  final bool callerLiked;

  /// Returns the same Reel with new engagement aggregates.
  ///
  /// The feed applies an optimistic like through this and then replaces it
  /// with the server's authoritative counter (or reverts) once the callable
  /// answers, so a card and the wide context panel can never disagree about
  /// the same Reel.
  Reel copyWithEngagement({
    int? likeCount,
    int? commentCount,
    bool? callerLiked,
  }) => Reel(
    id: id,
    authorId: authorId,
    authorName: authorName,
    media: media,
    composition: composition,
    publishedAt: publishedAt,
    sortKey: sortKey,
    backingAudio: backingAudio,
    availability: availability,
    likeCount: likeCount ?? this.likeCount,
    commentCount: commentCount ?? this.commentCount,
    callerLiked: callerLiked ?? this.callerLiked,
  );

  factory Reel.fromWire(Object? value) {
    final map = _map(value, 'reel');
    _keys(map, const <String>{
      'id',
      'authorId',
      'authorName',
      'media',
      'backingAudio',
      'composition',
      'publishedAtMillis',
      'sortKey',
    }, 'reel');
    final media = ReelMediaDescriptor.fromWire(map['media']);
    final backing = map['backingAudio'] == null
        ? null
        : ReelBackingAudioDescriptor.fromWire(map['backingAudio']);
    final reel = Reel(
      id: _safeId(map['id'], 'id'),
      authorId: _opaqueUid(map['authorId'], 'authorId'),
      authorName: _string(map['authorName'], 'authorName').trim(),
      media: media,
      backingAudio: backing,
      composition: ReelComposition.fromWire(
        map['composition'],
        mediaKind: media.kind,
        durationMs: media.durationMs,
        hasBackingAudio: backing != null,
      ),
      publishedAt: DateTime.fromMillisecondsSinceEpoch(
        _integer(map['publishedAtMillis'], 'publishedAtMillis'),
        isUtc: true,
      ),
      sortKey: _string(map['sortKey'], 'sortKey'),
    );
    if (reel.authorName.isEmpty ||
        reel.authorName.length > 120 ||
        !RegExp(r'^[0-9]{13}_[A-Za-z0-9_-]{1,128}$').hasMatch(reel.sortKey)) {
      throw const FormatException('Malformed reel identity.');
    }
    return reel;
  }

  /// Strict v2 parser. The legacy parser intentionally remains available for
  /// old call sites/tests, but the live service uses this shape exclusively.
  ///
  /// The three engagement keys are accepted but not demanded. A build that
  /// predates the engagement contract, and a Reel whose counters were never
  /// materialized, both arrive without them and must read as 0/0/false rather
  /// than emptying a feed page.
  factory Reel.fromV2Wire(Object? value) {
    final map = _map(value, 'reel');
    _keys(
      map,
      const <String>{
        'id',
        'authorId',
        'authorName',
        'media',
        'backingAudio',
        'composition',
        'publishedAtMillis',
        'sortKey',
        'availability',
      },
      'reel',
      optional: _engagementKeys,
    );
    final legacyShape = <String, Object?>{
      for (final entry in map.entries)
        if (entry.key != 'availability' && !_engagementKeys.contains(entry.key))
          entry.key: entry.value,
    };
    final legacy = Reel.fromWire(legacyShape);
    return Reel(
      id: legacy.id,
      authorId: legacy.authorId,
      authorName: legacy.authorName,
      media: legacy.media,
      backingAudio: legacy.backingAudio,
      composition: legacy.composition,
      publishedAt: legacy.publishedAt,
      sortKey: legacy.sortKey,
      availability: ReelAvailability.fromWire(map['availability']),
      likeCount: _tolerantCount(map['likeCount']),
      commentCount: _tolerantCount(map['commentCount']),
      callerLiked: map['callerLiked'] == true,
    );
  }

  static const Set<String> _engagementKeys = <String>{
    'likeCount',
    'commentCount',
    'callerLiked',
  };
}

/// One text comment on a Reel, exactly as `getReelViewV2` projects it.
///
/// Parsing is strict on purpose: the projection is server-owned, versioned,
/// and already drops documents it could not validate, so an unexpected shape
/// here means the client and the deployed contract disagree. Reporting that
/// as a visible, retryable failure beats silently hiding somebody's words.
@immutable
class ReelComment {
  const ReelComment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.createdAt,
  });

  static const int maxTextLength = 1000;

  final String id;
  final String authorId;
  final String authorName;
  final String text;
  final DateTime createdAt;

  factory ReelComment.fromWire(Object? value) {
    final map = _map(value, 'comment');
    _keys(map, const <String>{
      'schemaVersion',
      'commentId',
      'type',
      'authorId',
      'authorName',
      'authorPhotoUrl',
      'text',
      'durationSeconds',
      'createdAtMillis',
    }, 'comment');
    if (map['schemaVersion'] != 1) {
      throw const FormatException('Unsupported Reel comment schema.');
    }
    // `type` and `durationSeconds` are the fields a later voice reply would
    // use. Today the contract emits only text with a null duration, and this
    // client renders only text; accepting anything else would mean inventing
    // a presentation for content that does not exist yet.
    if (map['type'] != 'text' || map['durationSeconds'] != null) {
      throw const FormatException('Unsupported Reel comment type.');
    }
    final photo = map['authorPhotoUrl'];
    if (photo != null && photo is! String) {
      throw const FormatException('Malformed Reel comment author photo.');
    }
    final comment = ReelComment(
      id: _safeId(map['commentId'], 'commentId'),
      authorId: _opaqueUid(map['authorId'], 'authorId'),
      authorName: _string(map['authorName'], 'authorName').trim(),
      text: _string(map['text'], 'text'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        _integer(map['createdAtMillis'], 'createdAtMillis'),
        isUtc: true,
      ),
    );
    if (comment.authorName.isEmpty ||
        comment.authorName.length > 120 ||
        comment.text.trim().isEmpty ||
        comment.text.length > maxTextLength) {
      throw const FormatException('Malformed Reel comment.');
    }
    return comment;
  }
}

/// One `getReelViewV2` response: the Reel plus one page of its thread.
///
/// Comments are OLDEST-first, so [nextCommentCursor] pages forward in time and
/// a newly posted comment belongs at the end of a fully loaded thread.
@immutable
class ReelView {
  const ReelView({
    required this.reel,
    required this.comments,
    required this.commentsTruncated,
    required this.nextCommentCursor,
  });

  /// The server's own ceiling for one comment page.
  static const int maxCommentLimit = 7;

  final Reel reel;
  final List<ReelComment> comments;
  final bool commentsTruncated;
  final String? nextCommentCursor;

  factory ReelView.fromWire(Object? value) {
    final map = _map(value, 'reel view');
    _keys(map, const <String>{
      'schemaVersion',
      'reel',
      'comments',
      'commentsTruncated',
      'nextCommentCursor',
    }, 'reel view');
    if (map['schemaVersion'] != 2) {
      throw const FormatException('Unsupported Reel view schema.');
    }
    final rawComments = map['comments'];
    final truncated = map['commentsTruncated'];
    final cursor = map['nextCommentCursor'];
    if (rawComments is! List ||
        rawComments.length > maxCommentLimit ||
        truncated is! bool ||
        (cursor != null && cursor is! String)) {
      throw const FormatException('Malformed Reel view.');
    }
    // A cursor without truncation would page a thread the server just called
    // complete. Refuse rather than loop on a boundary that cannot advance.
    if (cursor != null && !truncated) {
      throw const FormatException('Inconsistent Reel comment page boundary.');
    }
    return ReelView(
      reel: Reel.fromV2Wire(map['reel']),
      comments: rawComments.map(ReelComment.fromWire).toList(growable: false),
      commentsTruncated: truncated,
      nextCommentCursor: cursor as String?,
    );
  }
}

@immutable
class ReelFeedPage {
  const ReelFeedPage({required this.items, required this.nextCursor});

  final List<Reel> items;
  final String? nextCursor;

  factory ReelFeedPage.fromWire(Object? value) {
    final map = _map(value, 'feed');
    _keys(map, const <String>{'items', 'nextCursor'}, 'feed');
    final rawItems = map['items'];
    if (rawItems is! List || rawItems.length > 20) {
      throw const FormatException('Malformed reel feed page.');
    }
    final cursor = map['nextCursor'];
    if (cursor != null && cursor is! String) {
      throw const FormatException('Malformed reel feed cursor.');
    }
    return ReelFeedPage(
      items: rawItems.map(Reel.fromWire).toList(growable: false),
      nextCursor: cursor as String?,
    );
  }

  factory ReelFeedPage.fromV2Wire(Object? value) {
    final map = _map(value, 'feed');
    _keys(map, const <String>{'schemaVersion', 'items', 'nextCursor'}, 'feed');
    if (map['schemaVersion'] != 2) {
      throw const FormatException('Unsupported Reel feed schema.');
    }
    final rawItems = map['items'];
    if (rawItems is! List || rawItems.length > 20) {
      throw const FormatException('Malformed reel feed page.');
    }
    final cursor = map['nextCursor'];
    if (cursor != null && cursor is! String) {
      throw const FormatException('Malformed reel feed cursor.');
    }
    return ReelFeedPage(
      items: rawItems.map(Reel.fromV2Wire).toList(growable: false),
      nextCursor: cursor as String?,
    );
  }
}

Map<String, Object?> _map(Object? value, String label) {
  if (value is! Map) throw FormatException('$label must be an object.');
  return value.map<String, Object?>((key, value) {
    if (key is! String) throw FormatException('$label has an invalid key.');
    return MapEntry(key, value);
  });
}

void _keys(
  Map<String, Object?> map,
  Set<String> expected,
  String label, {
  Set<String> optional = const <String>{},
}) {
  final present = map.keys.toSet();
  if (present.difference(expected.union(optional)).isNotEmpty ||
      expected.difference(present).isNotEmpty) {
    throw FormatException('$label has an unsupported shape.');
  }
}

/// An engagement counter is a decorative aggregate, never an authorization
/// input. Absent, null or corrupt all read as zero so one bad counter cannot
/// blank a feed page — the same choice the backend makes for a malformed like
/// edge. Every state-changing call still uses the server's returned counter.
int _tolerantCount(Object? value) => value is int && value >= 0 ? value : 0;

String _string(Object? value, String label) {
  if (value is! String) throw FormatException('$label must be text.');
  return value;
}

String _safeId(Object? value, String label) {
  final result = _string(value, label);
  if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(result)) {
    throw FormatException('$label is invalid.');
  }
  return result;
}

String _opaqueUid(Object? value, String label) {
  final result = _string(value, label);
  if (result.isEmpty ||
      result.length > 128 ||
      result.contains('/') ||
      result.runes.any(
        (codePoint) =>
            codePoint <= 0x1f || (codePoint >= 0x7f && codePoint <= 0x9f),
      )) {
    throw FormatException('$label is invalid.');
  }
  return result;
}

int _integer(Object? value, String label) {
  if (value is! int || value < 0) {
    throw FormatException('$label must be a non-negative integer.');
  }
  return value;
}
