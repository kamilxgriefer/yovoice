// Builds ISO-BMFF / QuickTime structures in memory for the Yeel rotation
// tests (ADR-235): the 64-bit, version-1 and malformed shapes no committed
// fixture carries. Pure Dart — no dart:io, no Flutter — so the Chrome-platform
// test compiles it with dart2js too. Every 32-bit field goes through ByteData,
// never through shifts, which dart2js truncates to int32.
import 'dart:typed_data';

import 'package:yovoice/features/reels/data/services/reel_video_orientation.dart';

const int isoOne = 0x10000;
const int isoW = 0x40000000;

Uint8List u32(int value) =>
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

Uint8List i32(int value) =>
    (ByteData(4)..setInt32(0, value)).buffer.asUint8List();

Uint8List concat(List<List<int>> parts) {
  final builder = BytesBuilder(copy: false);
  for (final part in parts) {
    builder.add(part);
  }
  return builder.takeBytes();
}

Uint8List fourCc(String type) {
  assert(type.length == 4);
  return Uint8List.fromList(type.codeUnits);
}

/// A plain box: 32-bit size, type, payload.
Uint8List box(String type, List<int> payload) =>
    concat(<List<int>>[u32(8 + payload.length), fourCc(type), payload]);

/// A FullBox: version, 24-bit flags, payload.
Uint8List fullBox(
  String type,
  int version,
  List<int> payload, {
  int flags = 0,
}) => box(
  type,
  concat(<List<int>>[
    <int>[version, (flags >> 16) & 0xff, (flags >> 8) & 0xff, flags & 0xff],
    payload,
  ]),
);

/// A box with size32 = 1 and a 64-bit largesize of [high]·2³² + [low]. With
/// [high] and [low] null the largesize is the box's real length.
Uint8List largeBox(String type, List<int> payload, {int? high, int? low}) {
  final real = 16 + payload.length;
  return concat(<List<int>>[
    u32(1),
    fourCc(type),
    u32(high ?? 0),
    u32(low ?? real),
    payload,
  ]);
}

/// A 36-byte matrix {a, b, u, c, d, v, tx, ty, w}.
Uint8List matrix({
  int a = isoOne,
  int b = 0,
  int u = 0,
  int c = 0,
  int d = isoOne,
  int v = 0,
  int tx = 0,
  int ty = 0,
  int w = isoW,
}) => concat(<List<int>>[
  i32(a),
  i32(b),
  i32(u),
  i32(c),
  i32(d),
  i32(v),
  i32(tx),
  i32(ty),
  i32(w),
]);

/// The canonical matrix for [turns] clockwise on [width]×[height] pixels.
Uint8List rotationMatrix(int turns, {int width = 64, int height = 36}) =>
    reelRotationMatrixBytes(turns, width * isoOne, height * isoOne);

/// A track header. v0: 4 version/flags + 20 + 8 + 8, matrix at payload +40.
/// v1: 64-bit times, matrix at payload +52. Width/height follow the matrix.
Uint8List tkhd({
  int version = 0,
  List<int>? matrixBytes,
  int width = 64,
  int height = 36,
}) {
  final times = version == 1 ? 32 : 20;
  return fullBox(
    'tkhd',
    version,
    concat(<List<int>>[
      Uint8List(times),
      Uint8List(8),
      Uint8List(8),
      matrixBytes ?? matrix(),
      u32(width * isoOne),
      u32(height * isoOne),
    ]),
    flags: 3,
  );
}

/// A movie header. v0: matrix at payload +36; v1: at payload +48.
Uint8List mvhd({int version = 0, List<int>? matrixBytes}) {
  final times = version == 1 ? 28 : 16;
  return fullBox(
    'mvhd',
    version,
    concat(<List<int>>[
      Uint8List(times),
      u32(isoOne), // rate
      Uint8List(2), // volume
      Uint8List(10), // reserved
      matrixBytes ?? matrix(),
      Uint8List(24), // pre_defined
      u32(3), // next_track_ID
    ]),
  );
}

/// A handler box; [handler] sits at payload offset 8 either way.
Uint8List hdlr(
  String handler, {
  String componentType = '\u0000\u0000\u0000\u0000',
}) => fullBox(
  'hdlr',
  0,
  concat(<List<int>>[
    Uint8List.fromList(componentType.codeUnits),
    fourCc(handler),
    Uint8List(12),
    <int>[0],
  ]),
);

Uint8List trak({
  String handler = 'vide',
  int tkhdVersion = 0,
  List<int>? matrixBytes,
  int width = 64,
  int height = 36,
  List<List<int>> extra = const <List<int>>[],
}) => box(
  'trak',
  concat(<List<int>>[
    tkhd(
      version: tkhdVersion,
      matrixBytes: matrixBytes,
      width: width,
      height: height,
    ),
    box(
      'mdia',
      concat(<List<int>>[fullBox('mdhd', 0, Uint8List(20)), hdlr(handler)]),
    ),
    ...extra,
  ]),
);

Uint8List moov({
  List<int>? movieHeader,
  List<List<int>> traks = const <List<int>>[],
  List<List<int>> extra = const <List<int>>[],
}) =>
    box('moov', concat(<List<int>>[movieHeader ?? mvhd(), ...traks, ...extra]));

Uint8List ftyp([String brand = 'isom']) => box(
  'ftyp',
  concat(<List<int>>[fourCc(brand), u32(0x200), fourCc(brand), fourCc('mp42')]),
);

/// ftyp + moov(one video trak) + mdat — the simplest rotatable file.
Uint8List simpleMovie({
  List<int>? matrixBytes,
  int tkhdVersion = 0,
  int mvhdVersion = 0,
}) => concat(<List<int>>[
  ftyp(),
  moov(
    movieHeader: mvhd(version: mvhdVersion),
    traks: <List<int>>[
      trak(tkhdVersion: tkhdVersion, matrixBytes: matrixBytes),
    ],
  ),
  box('mdat', Uint8List(32)),
]);

/// A reader over a file that is mostly a hole: [head] at offset 0, [tail] at
/// [tailOffset], zeros in between. It lets a test walk a 4 GB+ largesize box
/// without allocating it — exactly the offsets dart2js must get right.
class SparseRangeReader implements ReelByteRangeReader {
  SparseRangeReader({
    required this.head,
    required this.tail,
    required this.tailOffset,
  }) : length = tailOffset + tail.length;

  final Uint8List head;
  final Uint8List tail;
  final int tailOffset;
  int reads = 0;
  int bytesRead = 0;

  @override
  final int length;

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (offset < 0 || count < 0 || offset + count > length) {
      throw RangeError('Read past the end.');
    }
    reads += 1;
    bytesRead += count;
    final out = Uint8List(count);
    for (var index = 0; index < count; index += 1) {
      final at = offset + index;
      if (at < head.length) {
        out[index] = head[at];
      } else if (at >= tailOffset) {
        out[index] = tail[at - tailOffset];
      }
    }
    return out;
  }
}

/// Counts reads over in-memory bytes.
class CountingRangeReader implements ReelByteRangeReader {
  CountingRangeReader(this.bytes);
  final Uint8List bytes;
  int reads = 0;
  int bytesRead = 0;

  @override
  int get length => bytes.length;

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (offset < 0 || count < 0 || offset + count > bytes.length) {
      throw RangeError('Read past the end.');
    }
    reads += 1;
    bytesRead += count;
    return Uint8List.sublistView(bytes, offset, offset + count);
  }
}
