import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'package:yovoice/features/reels/data/services/reel_video_orientation.dart';

import 'reel_picked_file_range_stub.dart'
    if (dart.library.js_interop) 'reel_picked_file_range_web.dart'
    as platform;

// Range reads over a picked Yeel video (ADR-235).
//
// io: `XFile.openRead(start, end)` is a file seek, so a read touches only its
// own range.
//
// web: `XFile.openRead` is NOT a `Blob.slice` there. cross_file keeps no Blob
// for a picker's object URL and re-downloads the WHOLE URL into a new Blob
// (an XHR with responseType blob) on every `openRead`, `readAsBytes` and
// `length` call — 100 MB copied for a 16-byte read, and a fresh browser
// context stops answering after ~2 GB of such copies. The web reader instead
// asks for the range itself (`fetch` with a `Range` header; blob URLs answer
// 206 with just those bytes) and, in a browser that ignores the header,
// fetches the Blob ONCE per reader and slices it.

/// A range reader over [file], whose byte length is [length].
ReelByteRangeReader reelPickedFileRangeReader(XFile file, int length) =>
    platform.reelPlatformRangeReader(file, length) ??
    ReelXFileRangeReader(file, length);

/// Up to [limit] leading bytes of [file] from a single range request, or null
/// when this platform has no cheaper way than `XFile.openRead` (io, or a
/// browser that ignores `Range` on blob URLs).
Future<Uint8List?> readReelPickedFileHead(XFile file, int limit) =>
    platform.readReelPlatformHead(file, limit);

/// Exact range reads through `XFile.openRead` (a file seek on io).
class ReelXFileRangeReader implements ReelByteRangeReader {
  ReelXFileRangeReader(this._file, this.length);

  final XFile _file;

  @override
  final int length;

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (offset < 0 || count < 0 || offset + count > length) {
      throw RangeError('Read past the end of the media.');
    }
    if (count == 0) return Uint8List(0);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in _file.openRead(offset, offset + count)) {
      builder.add(chunk);
      if (builder.length >= count) break;
    }
    final bytes = builder.takeBytes();
    if (bytes.length < count) {
      throw RangeError('The media ended before the requested range.');
    }
    return bytes.length == count
        ? bytes
        : Uint8List.sublistView(bytes, 0, count);
  }
}
