import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:yovoice/features/moments/data/services/recorded_audio.dart';

/// The content of one pending direct-message attachment, in whatever form the
/// platform that produced it happens to hold it.
///
/// WHY THIS EXISTS. Enqueuing a voice message used to begin with
/// `await audio.readBytes()`: the complete recording pulled across the
/// platform channel into one `Uint8List`, hashed as a single buffer, and then
/// written to the durable outbox — a second full copy of the same bytes, with
/// both alive at once. The recording was already a file on disk; nothing about
/// that round trip through the heap made it more durable.
///
/// This is the same seam `ReelUploadPayload` introduced for Reel video
/// (`lib/features/reels/data/services/reel_upload.dart`): a payload is either
/// resident bytes or a handle to bytes that live somewhere else, and every
/// consumer works from [length] and [openRead] instead of demanding the whole
/// thing at once.
///
/// WHAT DOES NOT CHANGE. The backend contract. A source describes only how to
/// read bytes locally — it carries no device path, and none is added to a
/// reservation, to an upload's metadata or to a finalize call. The server
/// keeps deriving truth from the committed object's own headers and Storage
/// metadata, exactly as it did when the client held the bytes in memory.
abstract class DirectAttachmentPayloadSource {
  const DirectAttachmentPayloadSource();

  /// A payload whose bytes are legitimately resident already — a picked photo
  /// the composer is previewing, for example.
  const factory DirectAttachmentPayloadSource.bytes(Uint8List bytes) =
      _ResidentPayloadSource;

  /// A finished recording, streamed from wherever the recorder left it.
  const factory DirectAttachmentPayloadSource.recording(RecordedAudio audio) =
      _RecordedAudioPayloadSource;

  /// The authoritative byte count, known before any read.
  int get length;

  /// Bounded, sequential read of the whole payload.
  Stream<List<int>> openRead();

  /// Releases the producer's copy after the outbox has taken durable
  /// ownership. A no-op for resident bytes.
  ///
  /// Ownership transfers on a *successful* enqueue and not a moment earlier:
  /// until the manifest is persisted, the recorder's own file is still the
  /// only guaranteed copy of somebody's voice message.
  Future<void> release() async {}

  /// Streams the payload once, returning its sha256 and the number of bytes
  /// actually read.
  ///
  /// The caller compares the count against the declared [length]; a recording
  /// that changed underneath the sheet is caught here rather than by a server
  /// that would refuse the finalize much later.
  Future<DirectAttachmentPayloadDigest> digest() async {
    final sink = _DigestSink();
    final input = sha256.startChunkedConversion(sink);
    var streamed = 0;
    try {
      await for (final chunk in openRead()) {
        streamed += chunk.length;
        input.add(chunk);
      }
    } finally {
      input.close();
    }
    final digest = sink.value;
    if (digest == null) {
      throw StateError('The attachment payload could not be fingerprinted.');
    }
    return DirectAttachmentPayloadDigest(
      fingerprint: digest.toString(),
      length: streamed,
    );
  }
}

/// A payload's identity: the fingerprint the outbox deduplicates on and the
/// length that was actually observed while computing it.
class DirectAttachmentPayloadDigest {
  const DirectAttachmentPayloadDigest({
    required this.fingerprint,
    required this.length,
  });

  /// Lowercase hex sha256, the exact shape the durable manifest validates.
  final String fingerprint;

  final int length;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

class _ResidentPayloadSource extends DirectAttachmentPayloadSource {
  const _ResidentPayloadSource(this._bytes);

  final Uint8List _bytes;

  @override
  int get length => _bytes.lengthInBytes;

  @override
  Stream<List<int>> openRead() => Stream<List<int>>.value(_bytes);
}

class _RecordedAudioPayloadSource extends DirectAttachmentPayloadSource {
  const _RecordedAudioPayloadSource(this._audio);

  final RecordedAudio _audio;

  @override
  int get length => _audio.byteLength;

  @override
  Stream<List<int>> openRead() => _audio.openRead();

  @override
  Future<void> release() => _audio.discard();
}
