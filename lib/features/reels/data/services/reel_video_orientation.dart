import 'dart:typed_data';

// Reads and rewrites the ONE thing every player already honours about a
// video's orientation: the 3×3 display matrix in each video track's `tkhd`.
//
// WHY THE MATRIX AND NOT A RECIPE FIELD (ADR-235). Readers of a Yeel check
// the composition's exact key set on the client and the server (ADR-187), so
// an added "rotation" key would make every installed build refuse the whole
// Yeel. A patched matrix is the same structure an iPhone already uploads:
// AVFoundation (`presentationSize`, the frame generator), ExoPlayer
// (`AtomParsers.parseTkhd` → `rotationDegrees`) and Chrome (`videoWidth`,
// drawn frames) all apply it, so the rotation reaches iOS, Android and web —
// old builds included — through the file bytes alone.
//
// This file is pure Dart (no `dart:io`): the scanner runs on io and on web
// through a [ReelByteRangeReader], and every 64-bit quantity is read as two
// uint32 halves because dart2js has no `getUint64`. It imports nothing but
// `dart:typed_data`, so `dart run tool/reel_rotate_fixture.dart` and the
// Chrome-platform test exercise the exact code the composer ships; the
// `XFile` adapter lives with the bake (reel_video_rotation_bake.dart).

/// One contiguous, exact range read over a media source.
abstract interface class ReelByteRangeReader {
  /// The source's length in bytes.
  int get length;

  /// Exactly [count] bytes starting at [offset]; throws when the source
  /// yields fewer (a truncated or changed file must never look valid).
  Future<Uint8List> read(int offset, int count);
}

/// A reader over bytes already in memory (web bake, tests).
ReelByteRangeReader bytesRangeReader(Uint8List bytes) => _BytesReader(bytes);

class _BytesReader implements ReelByteRangeReader {
  _BytesReader(this._bytes);
  final Uint8List _bytes;

  @override
  int get length => _bytes.length;

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (offset < 0 || count < 0 || offset + count > _bytes.length) {
      throw RangeError('Read past the end of the media.');
    }
    return Uint8List.sublistView(_bytes, offset, offset + count);
  }
}

/// Why a file is not offered the rotate action. Debug logs only; the composer
/// simply hides the pill.
enum ReelOrientationUnsupported {
  /// No leading `ftyp`: WebM and anything else without a track matrix.
  notIsoBmff,

  /// A box overruns its container, the walk does not end exactly at the
  /// container's end, a required box is missing or duplicated, or a 64-bit
  /// size is beyond what a double represents exactly.
  malformed,

  /// Zero or several top-level `moov` boxes.
  moovCount,

  /// A compressed movie header (`cmov`): the matrix is not addressable.
  compressedMoov,

  /// The movie-level (`mvhd`) matrix is not identity; rotating the track
  /// would compose with a transform players do not agree on.
  movieMatrix,

  /// No `vide` track at all.
  noVideoTrack,

  /// A video track matrix that is mirrored, scaled, sheared or perspective,
  /// or a video track header without a width and height (a rotation needs
  /// them for its translation). Platforms already disagree on such
  /// matrices: media3 (1.9.2 `BoxParser.parseTkhd`) turns most mirrored ones
  /// into a plain 90/180/270° rotation and drops the mirror, and treats
  /// scaled or sheared ones as 0°, while AVFoundation applies them exactly —
  /// so a rotation composed on top would not look the same everywhere.
  unsupportedMatrix,

  /// Over the box, track or read budget (a pathological box chain).
  budget,
}

/// One track's header, as found in the file.
class ReelVideoTrackOrientation {
  const ReelVideoTrackOrientation({
    required this.handler,
    required this.tkhdVersion,
    required this.matrixOffset,
    required this.quarterTurns,
    required this.widthFixed,
    required this.heightFixed,
  });

  /// The `hdlr` handler type (`vide`, `soun`, `meta`, `tmcd`, …).
  final String handler;
  final int tkhdVersion;

  /// Absolute file offset of the 36-byte matrix.
  final int matrixOffset;

  /// Clockwise quarter turns of a canonical rotation matrix, or null for a
  /// non-video track whose matrix is not one (never patched, so never read).
  final int? quarterTurns;

  /// `tkhd` width and height, unsigned 16.16 fixed point.
  final int widthFixed;
  final int heightFixed;

  bool get isVideo => handler == 'vide';
}

/// A rotatable ISO-BMFF/QuickTime file.
class ReelVideoOrientation {
  const ReelVideoOrientation({required this.length, required this.tracks});

  /// The scanned source length; a patch never changes it.
  final int length;

  /// Every `trak` in `moov` order, video or not.
  final List<ReelVideoTrackOrientation> tracks;

  Iterable<ReelVideoTrackOrientation> get videoTracks =>
      tracks.where((track) => track.isVideo);
}

/// The scan's answer: a rotatable [orientation], or the [reason] it is not.
class ReelVideoOrientationScan {
  const ReelVideoOrientationScan.supported(
    ReelVideoOrientation this.orientation,
  ) : reason = null;
  const ReelVideoOrientationScan.unsupported(
    ReelOrientationUnsupported this.reason,
  ) : orientation = null;

  final ReelVideoOrientation? orientation;
  final ReelOrientationUnsupported? reason;
}

/// One positioned write of a patch plan.
class ReelMatrixPatch {
  const ReelMatrixPatch({required this.offset, required this.bytes});
  final int offset;
  final Uint8List bytes;
}

/// Box budget for one whole scan (every level together).
const int reelOrientationBoxBudget = 4096;

/// At most this many `trak` boxes in one `moov`.
const int reelOrientationTrackBudget = 16;

/// The window the moov walk reads through, so a moov's dozens of small header
/// reads cost a handful of range requests.
const int reelOrientationReadWindow = 64 * 1024;

const int _one = 0x10000;
const int _w = 0x40000000;

/// (a, b, c, d) of the four clockwise rotations, 16.16 fixed point — the
/// tuples ExoPlayer's `parseTkhd` maps to rotationDegrees 0/90/180/270.
const List<List<int>> _rotations = <List<int>>[
  <int>[_one, 0, 0, _one],
  <int>[0, _one, -_one, 0],
  <int>[-_one, 0, 0, -_one],
  <int>[0, -_one, _one, 0],
];

/// Scans [reader] and reports whether every video track can be rotated.
Future<ReelVideoOrientationScan> scanReelVideoOrientation(
  ReelByteRangeReader reader,
) async {
  final scan = _Scan(reader);
  try {
    return ReelVideoOrientationScan.supported(await scan.run());
  } on _Unsupported catch (error) {
    return ReelVideoOrientationScan.unsupported(error.reason);
  } on RangeError {
    return const ReelVideoOrientationScan.unsupported(
      ReelOrientationUnsupported.malformed,
    );
  }
}

/// The canonical 36 bytes for [quarterTurns] clockwise on a track of
/// [widthFixed]×[heightFixed] (16.16): Apple's standardized transforms —
/// exactly what an iPhone writes — with u = v = 0 and w = 1.0 (2.30).
Uint8List reelRotationMatrixBytes(
  int quarterTurns,
  int widthFixed,
  int heightFixed,
) {
  final turns = quarterTurns % 4;
  final abcd = _rotations[turns];
  final (tx, ty) = switch (turns) {
    0 => (0, 0),
    1 => (heightFixed, 0),
    2 => (widthFixed, heightFixed),
    _ => (0, widthFixed),
  };
  final data = ByteData(36)
    ..setInt32(0, abcd[0])
    ..setInt32(4, abcd[1])
    ..setInt32(8, 0)
    ..setInt32(12, abcd[2])
    ..setInt32(16, abcd[3])
    ..setInt32(20, 0)
    ..setInt32(24, tx)
    ..setInt32(28, ty)
    ..setInt32(32, _w);
  return data.buffer.asUint8List();
}

/// The positioned writes that turn every video track [taps] quarter turns
/// clockwise: r' = (r + taps) mod 4 per track, the convention of
/// `RotatedBox.quarterTurns` and ExoPlayer's rotationDegrees. A whole number
/// of full turns writes nothing, so four taps are byte-identical.
List<ReelMatrixPatch> planReelVideoRotation(
  ReelVideoOrientation orientation,
  int taps,
) {
  if (taps % 4 == 0) return const <ReelMatrixPatch>[];
  return <ReelMatrixPatch>[
    for (final track in orientation.videoTracks)
      ReelMatrixPatch(
        offset: track.matrixOffset,
        bytes: reelRotationMatrixBytes(
          (track.quarterTurns! + taps) % 4,
          track.widthFixed,
          track.heightFixed,
        ),
      ),
  ];
}

/// Applies [plan] to [bytes] in place.
void applyReelMatrixPatches(Uint8List bytes, List<ReelMatrixPatch> plan) {
  for (final patch in plan) {
    bytes.setRange(
      patch.offset,
      patch.offset + patch.bytes.length,
      patch.bytes,
    );
  }
}

/// Parses the rotation of a 36-byte matrix, or null when it is not one of
/// the four canonical rotations with u = v = 0 and w = 1.0. tx/ty are
/// ignored on input: Android's MediaMuxer writes 0, Apple writes normalized
/// translations.
int? reelMatrixQuarterTurns(ByteData matrix, [int offset = 0]) {
  int at(int index) => matrix.getInt32(offset + index * 4);
  if (at(2) != 0 || at(5) != 0 || at(8) != _w) return null;
  for (var turns = 0; turns < 4; turns += 1) {
    final abcd = _rotations[turns];
    if (at(0) == abcd[0] &&
        at(1) == abcd[1] &&
        at(3) == abcd[2] &&
        at(4) == abcd[3]) {
      return turns;
    }
  }
  return null;
}

class _Unsupported implements Exception {
  const _Unsupported(this.reason);
  final ReelOrientationUnsupported reason;
}

class _Box {
  const _Box(this.type, this.offset, this.headerSize, this.size);
  final String type;
  final int offset;
  final int headerSize;
  final int size;
  int get payload => offset + headerSize;
  int get end => offset + size;
  int get payloadSize => size - headerSize;
}

class _Scan {
  _Scan(this._source);

  final ReelByteRangeReader _source;
  int _boxes = 0;

  /// The first 16 bytes, read once: the `ftyp` check and the first box
  /// header of the top-level walk share them.
  Uint8List? _head;

  // A tiny window cache for the moov subtree. Top-level box headers are read
  // exactly (a moof/mdat chain can be hundreds of boxes megabytes apart).
  final List<(int, Uint8List)> _windows = <(int, Uint8List)>[];

  Future<Uint8List> _exact(int offset, int count) {
    final head = _head;
    if (head != null && offset == 0 && count <= head.length) {
      return Future<Uint8List>.value(Uint8List.sublistView(head, 0, count));
    }
    return _source.read(offset, count);
  }

  Future<Uint8List> _windowed(int offset, int count) async {
    if (count > reelOrientationReadWindow) return _exact(offset, count);
    for (final (start, bytes) in _windows) {
      if (offset >= start && offset + count <= start + bytes.length) {
        return Uint8List.sublistView(
          bytes,
          offset - start,
          offset - start + count,
        );
      }
    }
    final end = offset + count;
    if (end > _source.length) throw RangeError('Read past the end.');
    final windowEnd = offset + reelOrientationReadWindow > _source.length
        ? _source.length
        : offset + reelOrientationReadWindow;
    final window = await _exact(offset, windowEnd - offset);
    _windows.insert(0, (offset, window));
    if (_windows.length > 4) _windows.removeLast();
    return Uint8List.sublistView(window, 0, count);
  }

  Future<ReelVideoOrientation> run() async {
    final length = _source.length;
    if (length < 16) {
      throw const _Unsupported(ReelOrientationUnsupported.notIsoBmff);
    }
    final head = _head = await _source.read(0, 16);
    if (String.fromCharCodes(head, 4, 8) != 'ftyp') {
      throw const _Unsupported(ReelOrientationUnsupported.notIsoBmff);
    }
    final top = await _children(0, length, windowed: false);
    final moov = top.where((box) => box.type == 'moov').toList();
    if (moov.length != 1) {
      throw const _Unsupported(ReelOrientationUnsupported.moovCount);
    }
    final movie = await _children(moov.single.payload, moov.single.end);
    if (movie.any((box) => box.type == 'cmov')) {
      throw const _Unsupported(ReelOrientationUnsupported.compressedMoov);
    }
    await _checkMovieMatrix(_single(movie, 'mvhd'));
    final traks = movie.where((box) => box.type == 'trak').toList();
    if (traks.length > reelOrientationTrackBudget) {
      throw const _Unsupported(ReelOrientationUnsupported.budget);
    }
    final tracks = <ReelVideoTrackOrientation>[];
    for (final trak in traks) {
      tracks.add(await _track(trak));
    }
    if (!tracks.any((track) => track.isVideo)) {
      throw const _Unsupported(ReelOrientationUnsupported.noVideoTrack);
    }
    return ReelVideoOrientation(
      length: length,
      tracks: List<ReelVideoTrackOrientation>.unmodifiable(tracks),
    );
  }

  static _Box _single(List<_Box> boxes, String type) {
    final matches = boxes.where((box) => box.type == type).toList();
    if (matches.length != 1) {
      throw const _Unsupported(ReelOrientationUnsupported.malformed);
    }
    return matches.single;
  }

  /// Walks the boxes in [start, end). The walk must end exactly at [end]:
  /// size 1 is a 64-bit largesize, size 0 runs to the container's end.
  ///
  /// This is no stricter than publishing already is: the server's trusted
  /// probe (`functions/reels/probe.js`, `listIsoBmffAtoms` and
  /// `exactlyOneAtom`) refuses a top-level walk that does not end at the
  /// file's length and a trak without exactly one tkhd, mdia and hdlr, so a
  /// file hidden from "Obróć" for those reasons could not be published at
  /// all.
  Future<List<_Box>> _children(
    int start,
    int end, {
    bool windowed = true,
  }) async {
    final boxes = <_Box>[];
    var offset = start;
    while (offset < end) {
      if (++_boxes > reelOrientationBoxBudget) {
        throw const _Unsupported(ReelOrientationUnsupported.budget);
      }
      if (end - offset < 8) {
        throw const _Unsupported(ReelOrientationUnsupported.malformed);
      }
      final available = end - offset < 16 ? end - offset : 16;
      final header = windowed
          ? await _windowed(offset, available)
          : await _exact(offset, available);
      final data = ByteData.sublistView(header);
      final size32 = data.getUint32(0);
      final type = String.fromCharCodes(header, 4, 8);
      var headerSize = 8;
      int size;
      if (size32 == 1) {
        if (header.length < 16) {
          throw const _Unsupported(ReelOrientationUnsupported.malformed);
        }
        final high = data.getUint32(8);
        final low = data.getUint32(12);
        // 2^21 × 2^32 = 2^53: past that a double cannot hold the size exactly.
        if (high >= 0x200000) {
          throw const _Unsupported(ReelOrientationUnsupported.malformed);
        }
        size = high * 0x100000000 + low;
        headerSize = 16;
      } else if (size32 == 0) {
        size = end - offset;
      } else {
        size = size32;
      }
      if (size < headerSize || size > end - offset) {
        throw const _Unsupported(ReelOrientationUnsupported.malformed);
      }
      boxes.add(_Box(type, offset, headerSize, size));
      offset += size;
    }
    if (offset != end) {
      throw const _Unsupported(ReelOrientationUnsupported.malformed);
    }
    return boxes;
  }

  Future<void> _checkMovieMatrix(_Box mvhd) async {
    final version = (await _windowed(mvhd.payload, 1))[0];
    final matrixAt = switch (version) {
      0 => 36,
      1 => 48,
      _ => throw const _Unsupported(ReelOrientationUnsupported.malformed),
    };
    if (mvhd.payloadSize < matrixAt + 36) {
      throw const _Unsupported(ReelOrientationUnsupported.malformed);
    }
    final matrix = ByteData.sublistView(
      await _windowed(mvhd.payload + matrixAt, 36),
    );
    const identity = <int>[_one, 0, 0, 0, _one, 0, 0, 0, _w];
    for (var index = 0; index < 9; index += 1) {
      if (matrix.getInt32(index * 4) != identity[index]) {
        throw const _Unsupported(ReelOrientationUnsupported.movieMatrix);
      }
    }
  }

  Future<ReelVideoTrackOrientation> _track(_Box trak) async {
    final children = await _children(trak.payload, trak.end);
    final tkhd = _single(children, 'tkhd');
    final mdia = _single(children, 'mdia');
    final hdlr = _single(await _children(mdia.payload, mdia.end), 'hdlr');
    if (hdlr.payloadSize < 12) {
      throw const _Unsupported(ReelOrientationUnsupported.malformed);
    }
    // ISO handler_type and the QuickTime 'mhlr' component subtype share
    // payload offset 8 (4 version/flags + 4 pre_defined/component type).
    final handler = String.fromCharCodes(await _windowed(hdlr.payload + 8, 4));

    final version = (await _windowed(tkhd.payload, 1))[0];
    // v0: 4 version/flags + 20 times/id/reserved/duration + 8 reserved +
    // 8 layer/alternate group/volume/reserved. v1 widens the times to 64 bits.
    final matrixAt = switch (version) {
      0 => 40,
      1 => 52,
      _ => throw const _Unsupported(ReelOrientationUnsupported.malformed),
    };
    if (tkhd.payloadSize < matrixAt + 44) {
      throw const _Unsupported(ReelOrientationUnsupported.malformed);
    }
    final matrixOffset = tkhd.payload + matrixAt;
    final bytes = ByteData.sublistView(await _windowed(matrixOffset, 44));
    final turns = reelMatrixQuarterTurns(bytes);
    final width = bytes.getUint32(36);
    final height = bytes.getUint32(40);
    if (handler == 'vide' &&
        (turns == null ||
            width == 0 ||
            height == 0 ||
            width > 0x7fffffff ||
            height > 0x7fffffff)) {
      throw const _Unsupported(ReelOrientationUnsupported.unsupportedMatrix);
    }
    return ReelVideoTrackOrientation(
      handler: handler,
      tkhdVersion: version,
      matrixOffset: matrixOffset,
      quarterTurns: turns,
      widthFixed: width,
      heightFixed: height,
    );
  }
}
