import 'package:flutter/foundation.dart';

import 'package:yovoice/features/reels/data/models/reel_composition.dart';

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
  });

  final String id;
  final String authorId;
  final String authorName;
  final ReelMediaDescriptor media;
  final ReelBackingAudioDescriptor? backingAudio;
  final ReelComposition composition;
  final DateTime publishedAt;
  final String sortKey;

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
}

Map<String, Object?> _map(Object? value, String label) {
  if (value is! Map) throw FormatException('$label must be an object.');
  return value.map<String, Object?>((key, value) {
    if (key is! String) throw FormatException('$label has an invalid key.');
    return MapEntry(key, value);
  });
}

void _keys(Map<String, Object?> map, Set<String> expected, String label) {
  if (map.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(map.keys.toSet()).isNotEmpty) {
    throw FormatException('$label has an unsupported shape.');
  }
}

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
