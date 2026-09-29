import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:web/web.dart' as web;

import 'package:yovoice/features/reels/data/services/reel_video_orientation.dart';

/// Range requests answered 206 or refused (tests only).
@visibleForTesting
int debugReelBlobRangeRequests = 0;

/// Whole-object fetches (tests only): at most one per reader, and none at
/// all while the browser honours `Range` on blob URLs.
@visibleForTesting
int debugReelBlobWholeFetches = 0;

/// Simulates a browser that ignores `Range` on blob URLs (tests only).
@visibleForTesting
bool debugReelBlobIgnoreRange = false;

bool _isBlobUrl(String path) => path.startsWith('blob:');

/// A blob-URL pick (every image_picker_for_web file and `XFile.fromData`)
/// gets range requests; anything else keeps `XFile.openRead`.
ReelByteRangeReader? reelPlatformRangeReader(XFile file, int length) =>
    _isBlobUrl(file.path) ? _BlobUrlRangeReader(file.path, length) : null;

Future<Uint8List?> readReelPlatformHead(XFile file, int limit) async {
  if (!_isBlobUrl(file.path) || limit <= 0) return null;
  final ranged = await _rangeRequest(file.path, 0, limit, exact: false);
  return ranged == null || ranged.isEmpty ? null : ranged;
}

/// `[offset, offset + count)` of [url] by one `Range` request, or null when
/// the browser did not answer with exactly that range (a 200 whole-body
/// answer is cancelled unread). With [exact] false a shorter 206 — the file
/// ends inside the range — is accepted.
Future<Uint8List?> _rangeRequest(
  String url,
  int offset,
  int count, {
  bool exact = true,
}) async {
  if (debugReelBlobIgnoreRange) return null;
  debugReelBlobRangeRequests += 1;
  try {
    final headers = web.Headers()
      ..set('Range', 'bytes=$offset-${offset + count - 1}');
    final response = await web.window
        .fetch(url.toJS, web.RequestInit(headers: headers))
        .toDart;
    final contentRange = response.headers.get('Content-Range') ?? '';
    if (response.status != 206 || !contentRange.startsWith('bytes $offset-')) {
      final body = response.body;
      if (body != null) {
        unawaited(body.cancel().toDart.then((_) {}, onError: (Object _) {}));
      }
      return null;
    }
    final bytes = (await response.arrayBuffer().toDart).toDart.asUint8List();
    if (bytes.length > count || (exact && bytes.length != count)) return null;
    return bytes;
  } catch (_) {
    // A browser that refuses the header outright: the Blob path below
    // reports a revoked URL honestly.
    return null;
  }
}

class _BlobUrlRangeReader implements ReelByteRangeReader {
  _BlobUrlRangeReader(this._url, this.length);

  final String _url;

  @override
  final int length;

  bool _rangeHonoured = true;
  Future<web.Blob>? _blob;

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (offset < 0 || count < 0 || offset + count > length) {
      throw RangeError('Read past the end of the media.');
    }
    if (count == 0) return Uint8List(0);
    if (_rangeHonoured) {
      final ranged = await _rangeRequest(_url, offset, count);
      if (ranged != null) return ranged;
      _rangeHonoured = false;
    }
    final blob = await (_blob ??= _wholeBlob());
    if (blob.size != length) {
      throw RangeError('The media is not the length it was chosen with.');
    }
    final bytes =
        (await blob.slice(offset, offset + count).arrayBuffer().toDart).toDart
            .asUint8List();
    if (bytes.length != count) {
      throw RangeError('The media ended before the requested range.');
    }
    return bytes;
  }

  /// The one whole-object fetch this reader may make; released with it.
  Future<web.Blob> _wholeBlob() async {
    debugReelBlobWholeFetches += 1;
    final response = await web.window.fetch(_url.toJS).toDart;
    if (!response.ok) {
      throw StateError('The selected media is no longer available.');
    }
    return response.blob().toDart;
  }
}
