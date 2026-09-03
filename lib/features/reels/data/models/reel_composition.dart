import 'dart:math' as math;

import 'package:flutter/foundation.dart';

enum ReelMediaKind { image, video }

enum ReelFilter { original, vivid, warm, cool, monochrome }

enum ReelOverlayColor { light, dark, accent, cyan }

@immutable
class ReelCropTransform {
  const ReelCropTransform({this.scale = 1, this.offsetX = 0, this.offsetY = 0});

  final double scale;
  final double offsetX;
  final double offsetY;

  bool get isValid =>
      scale.isFinite &&
      scale >= 1 &&
      scale <= 8 &&
      offsetX.isFinite &&
      offsetX >= -1 &&
      offsetX <= 1 &&
      offsetY.isFinite &&
      offsetY >= -1 &&
      offsetY <= 1;

  Map<String, Object> toWire() => <String, Object>{
    'scalePermille': (scale * 1000).round(),
    'offsetXPermille': (offsetX * 1000).round(),
    'offsetYPermille': (offsetY * 1000).round(),
  };

  factory ReelCropTransform.fromWire(Object? value) {
    final map = _objectMap(value, 'crop');
    _exactKeys(map, const <String>{
      'scalePermille',
      'offsetXPermille',
      'offsetYPermille',
    }, 'crop');
    final result = ReelCropTransform(
      scale: _wireInt(map['scalePermille'], 'scalePermille') / 1000,
      offsetX: _wireInt(map['offsetXPermille'], 'offsetXPermille') / 1000,
      offsetY: _wireInt(map['offsetYPermille'], 'offsetYPermille') / 1000,
    );
    if (!result.isValid) {
      throw const FormatException('The reel crop transform is invalid.');
    }
    return result;
  }

  ReelCropTransform copyWith({
    double? scale,
    double? offsetX,
    double? offsetY,
  }) {
    return ReelCropTransform(
      scale: scale ?? this.scale,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
    );
  }
}

@immutable
class ReelTextOverlay {
  const ReelTextOverlay({
    required this.id,
    required this.text,
    required this.x,
    required this.y,
    this.scale = 1,
    this.color = ReelOverlayColor.light,
  });

  final String id;
  final String text;
  final double x;
  final double y;
  final double scale;
  final ReelOverlayColor color;

  bool get isValid =>
      RegExp(r'^[A-Za-z0-9_-]{1,40}$').hasMatch(id) &&
      text.trim().isNotEmpty &&
      text.trim().length <= 120 &&
      x.isFinite &&
      x >= 0 &&
      x <= 1 &&
      y.isFinite &&
      y >= 0 &&
      y <= 1 &&
      scale.isFinite &&
      scale >= .75 &&
      scale <= 2;

  Map<String, Object> toWire() => <String, Object>{
    'id': id,
    'text': text.trim(),
    'xPermille': (x * 1000).round(),
    'yPermille': (y * 1000).round(),
    'scalePermille': (scale * 1000).round(),
    'color': color.name,
  };

  factory ReelTextOverlay.fromWire(Object? value) {
    final map = _objectMap(value, 'text overlay');
    _exactKeys(map, const <String>{
      'id',
      'text',
      'xPermille',
      'yPermille',
      'scalePermille',
      'color',
    }, 'text overlay');
    final result = ReelTextOverlay(
      id: _wireString(map['id'], 'id'),
      text: _wireString(map['text'], 'text'),
      x: _wireInt(map['xPermille'], 'xPermille') / 1000,
      y: _wireInt(map['yPermille'], 'yPermille') / 1000,
      scale: _wireInt(map['scalePermille'], 'scalePermille') / 1000,
      color: _enumByName(
        ReelOverlayColor.values,
        _wireString(map['color'], 'color'),
        'overlay color',
      ),
    );
    if (!result.isValid) {
      throw const FormatException('The reel text overlay is invalid.');
    }
    return result;
  }
}

@immutable
class ReelLinkOverlay {
  const ReelLinkOverlay({
    required this.id,
    required this.label,
    required this.uri,
    required this.x,
    required this.y,
  });

  final String id;
  final String label;
  final Uri uri;
  final double x;
  final double y;

  bool get isValid =>
      RegExp(r'^[A-Za-z0-9_-]{1,40}$').hasMatch(id) &&
      label.trim().isNotEmpty &&
      label.trim().length <= 60 &&
      isSafePublicHttpsUri(uri) &&
      x.isFinite &&
      x >= 0 &&
      x <= 1 &&
      y.isFinite &&
      y >= 0 &&
      y <= 1;

  Map<String, Object> toWire() => <String, Object>{
    'id': id,
    'label': label.trim(),
    'url': uri.toString(),
    'xPermille': (x * 1000).round(),
    'yPermille': (y * 1000).round(),
  };

  factory ReelLinkOverlay.fromWire(Object? value) {
    final map = _objectMap(value, 'link overlay');
    _exactKeys(map, const <String>{
      'id',
      'label',
      'url',
      'xPermille',
      'yPermille',
    }, 'link overlay');
    final uri = Uri.tryParse(_wireString(map['url'], 'url'));
    if (uri == null) {
      throw const FormatException('The reel link is invalid.');
    }
    final result = ReelLinkOverlay(
      id: _wireString(map['id'], 'id'),
      label: _wireString(map['label'], 'label'),
      uri: uri,
      x: _wireInt(map['xPermille'], 'xPermille') / 1000,
      y: _wireInt(map['yPermille'], 'yPermille') / 1000,
    );
    if (!result.isValid) {
      throw const FormatException('The reel link overlay is invalid.');
    }
    return result;
  }
}

/// The non-destructive edit recipe attached to an uploaded Reel.
///
/// The original media stays immutable. This bounded recipe is applied by the
/// feed and can later be consumed by a trusted transcode worker without a
/// Firestore migration. All coordinates use the normalized 0..1 canvas.
@immutable
class ReelComposition {
  const ReelComposition({
    this.caption = '',
    this.crop = const ReelCropTransform(),
    this.filter = ReelFilter.original,
    this.trimStartMs = 0,
    this.trimEndMs = 0,
    this.textOverlays = const <ReelTextOverlay>[],
    this.linkOverlays = const <ReelLinkOverlay>[],
    this.originalAudioVolume = 100,
    this.backingAudioVolume = 0,
    this.audioTrimStartMs = 0,
    this.audioRightsAttested = false,
    this.audioAttribution = '',
  });

  final String caption;
  final ReelCropTransform crop;
  final ReelFilter filter;
  final int trimStartMs;
  final int trimEndMs;
  final List<ReelTextOverlay> textOverlays;
  final List<ReelLinkOverlay> linkOverlays;
  final int originalAudioVolume;
  final int backingAudioVolume;
  final int audioTrimStartMs;

  /// User assertion recorded with the publish. It is not proof of a licence.
  final bool audioRightsAttested;
  final String audioAttribution;

  String? validate({
    required ReelMediaKind mediaKind,
    required int durationMs,
    required bool hasBackingAudio,
  }) {
    if (caption.trim().length > 2200) return 'Caption is too long.';
    if (!crop.isValid) return 'Crop settings are invalid.';
    if (textOverlays.length > 8 || textOverlays.any((item) => !item.isValid)) {
      return 'Text overlays are invalid.';
    }
    if (linkOverlays.length > 4 || linkOverlays.any((item) => !item.isValid)) {
      return 'Link overlays are invalid.';
    }
    if (textOverlays.map((item) => item.id).toSet().length !=
        textOverlays.length) {
      return 'Text overlay identifiers must be unique.';
    }
    if (linkOverlays.map((item) => item.id).toSet().length !=
        linkOverlays.length) {
      return 'Link overlay identifiers must be unique.';
    }
    if (originalAudioVolume < 0 || originalAudioVolume > 100) {
      return 'Original audio volume is invalid.';
    }
    if (backingAudioVolume < 0 || backingAudioVolume > 100) {
      return 'Backing audio volume is invalid.';
    }
    if (audioTrimStartMs < 0 || audioTrimStartMs > 90 * 1000) {
      return 'Backing audio trim is invalid.';
    }
    if (audioAttribution.trim().length > 160) {
      return 'Audio attribution is too long.';
    }
    if (hasBackingAudio && !audioRightsAttested) {
      return 'Confirm that you may use the backing audio.';
    }
    if (!hasBackingAudio &&
        (backingAudioVolume != 0 ||
            audioTrimStartMs != 0 ||
            audioRightsAttested ||
            audioAttribution.trim().isNotEmpty)) {
      return 'Backing audio settings require an audio upload.';
    }
    if (mediaKind == ReelMediaKind.image) {
      if (trimStartMs != 0 || trimEndMs != 0 || originalAudioVolume != 0) {
        return 'Still images cannot carry video trim or original audio.';
      }
    } else {
      if (durationMs < 1000 ||
          trimStartMs < 0 ||
          trimEndMs <= trimStartMs ||
          trimEndMs > durationMs ||
          trimEndMs - trimStartMs > 90 * 1000) {
        return 'Video trim must select between 1 and 90 seconds.';
      }
    }
    return null;
  }

  Map<String, Object> toWire() => <String, Object>{
    'caption': caption.trim(),
    'crop': crop.toWire(),
    'filter': filter.name,
    'trimStartMs': trimStartMs,
    'trimEndMs': trimEndMs,
    'textOverlays': textOverlays.map((item) => item.toWire()).toList(),
    'linkOverlays': linkOverlays.map((item) => item.toWire()).toList(),
    'originalAudioVolume': originalAudioVolume,
    'backingAudioVolume': backingAudioVolume,
    'audioTrimStartMs': audioTrimStartMs,
    'audioRightsAttested': audioRightsAttested,
    'audioAttribution': audioAttribution.trim(),
  };

  factory ReelComposition.fromWire(
    Object? value, {
    required ReelMediaKind mediaKind,
    required int durationMs,
    required bool hasBackingAudio,
  }) {
    final map = _objectMap(value, 'composition');
    _exactKeys(map, const <String>{
      'caption',
      'crop',
      'filter',
      'trimStartMs',
      'trimEndMs',
      'textOverlays',
      'linkOverlays',
      'originalAudioVolume',
      'backingAudioVolume',
      'audioTrimStartMs',
      'audioRightsAttested',
      'audioAttribution',
    }, 'composition');
    final text = _wireList(
      map['textOverlays'],
      'textOverlays',
    ).map(ReelTextOverlay.fromWire).toList(growable: false);
    final links = _wireList(
      map['linkOverlays'],
      'linkOverlays',
    ).map(ReelLinkOverlay.fromWire).toList(growable: false);
    final result = ReelComposition(
      caption: _wireString(map['caption'], 'caption'),
      crop: ReelCropTransform.fromWire(map['crop']),
      filter: _enumByName(
        ReelFilter.values,
        _wireString(map['filter'], 'filter'),
        'filter',
      ),
      trimStartMs: _wireInt(map['trimStartMs'], 'trimStartMs'),
      trimEndMs: _wireInt(map['trimEndMs'], 'trimEndMs'),
      textOverlays: text,
      linkOverlays: links,
      originalAudioVolume: _wireInt(
        map['originalAudioVolume'],
        'originalAudioVolume',
      ),
      backingAudioVolume: _wireInt(
        map['backingAudioVolume'],
        'backingAudioVolume',
      ),
      audioTrimStartMs: _wireInt(map['audioTrimStartMs'], 'audioTrimStartMs'),
      audioRightsAttested: _wireBool(
        map['audioRightsAttested'],
        'audioRightsAttested',
      ),
      audioAttribution: _wireString(
        map['audioAttribution'],
        'audioAttribution',
      ),
    );
    final problem = result.validate(
      mediaKind: mediaKind,
      durationMs: durationMs,
      hasBackingAudio: hasBackingAudio,
    );
    if (problem != null) throw FormatException(problem);
    return result;
  }

  ReelComposition copyWith({
    String? caption,
    ReelCropTransform? crop,
    ReelFilter? filter,
    int? trimStartMs,
    int? trimEndMs,
    List<ReelTextOverlay>? textOverlays,
    List<ReelLinkOverlay>? linkOverlays,
    int? originalAudioVolume,
    int? backingAudioVolume,
    int? audioTrimStartMs,
    bool? audioRightsAttested,
    String? audioAttribution,
  }) {
    return ReelComposition(
      caption: caption ?? this.caption,
      crop: crop ?? this.crop,
      filter: filter ?? this.filter,
      trimStartMs: trimStartMs ?? this.trimStartMs,
      trimEndMs: trimEndMs ?? this.trimEndMs,
      textOverlays: textOverlays ?? this.textOverlays,
      linkOverlays: linkOverlays ?? this.linkOverlays,
      originalAudioVolume: originalAudioVolume ?? this.originalAudioVolume,
      backingAudioVolume: backingAudioVolume ?? this.backingAudioVolume,
      audioTrimStartMs: audioTrimStartMs ?? this.audioTrimStartMs,
      audioRightsAttested: audioRightsAttested ?? this.audioRightsAttested,
      audioAttribution: audioAttribution ?? this.audioAttribution,
    );
  }
}

/// Accepts only public HTTPS web destinations. Localhost, private/link-local
/// IPv4 space, credentials, custom ports and single-label hosts fail closed.
bool isSafePublicHttpsUri(Uri uri) {
  if (uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.host.isEmpty ||
      uri.toString().length > 2048) {
    return false;
  }
  final host = uri.host.toLowerCase();
  if (host == 'localhost' ||
      host.endsWith('.local') ||
      host.endsWith('.localhost') ||
      host.contains(':') ||
      !host.contains('.')) {
    return false;
  }
  final octets = host.split('.').map(int.tryParse).toList();
  if (octets.length == 4 && octets.every((part) => part != null)) {
    final values = octets.cast<int>();
    if (values.any((part) => part < 0 || part > 255)) return false;
    final first = values[0];
    final second = values[1];
    return !(first == 0 ||
        first == 10 ||
        first == 127 ||
        first >= 224 ||
        (first == 100 && second >= 64 && second <= 127) ||
        (first == 169 && second == 254) ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168));
  }
  return RegExp(
    r'^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
  ).hasMatch(host);
}

Map<String, Object?> _objectMap(Object? value, String label) {
  if (value is! Map) throw FormatException('$label must be an object.');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$label contains a non-text key.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _exactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String label,
) {
  if (value.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(value.keys.toSet()).isNotEmpty) {
    throw FormatException('$label has an unsupported shape.');
  }
}

String _wireString(Object? value, String label) {
  if (value is! String) throw FormatException('$label must be text.');
  return value;
}

int _wireInt(Object? value, String label) {
  if (value is! int) throw FormatException('$label must be an integer.');
  return value;
}

bool _wireBool(Object? value, String label) {
  if (value is! bool) throw FormatException('$label must be true or false.');
  return value;
}

List<Object?> _wireList(Object? value, String label) {
  if (value is! List) throw FormatException('$label must be a list.');
  return value.cast<Object?>();
}

T _enumByName<T extends Enum>(List<T> values, String name, String label) {
  return values.firstWhere(
    (value) => value.name == name,
    orElse: () => throw FormatException('$label is invalid.'),
  );
}

double clampNormalized(double value) => math.max(0, math.min(1, value));
