import 'dart:js_interop';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:web/web.dart' as web;

import 'package:yovoice/features/messages/data/services/direct_attachment_payload_source.dart';

import 'direct_attachment_payload_store.dart';

DirectAttachmentPayloadStore createDirectAttachmentPayloadStore() =>
    _WebDirectAttachmentPayloadStore();

class _WebDirectAttachmentPayloadStore implements DirectAttachmentPayloadStore {
  String _cacheName(String accountNamespace) =>
      'yovoice-direct-attachment-outbox-$accountNamespace';
  String get _prefix =>
      '${web.window.location.origin}/__yovoice_direct_attachment/';
  String _key(String entryId) => '$_prefix${Uri.encodeComponent(entryId)}';

  Future<web.Cache> _cache(String accountNamespace) =>
      web.window.caches.open(_cacheName(accountNamespace)).toDart;

  /// Streams [source] into a Blob assembled from its own chunks.
  ///
  /// A browser has no filesystem to move a file across, so the bytes must be
  /// handed to Cache Storage one way or another. Passing the chunks as Blob
  /// parts leaves them with the browser instead of concatenating them into a
  /// single Dart buffer first, which is the only thing this platform can
  /// meaningfully avoid.
  @override
  Future<void> adopt(
    String accountNamespace,
    String entryId,
    DirectAttachmentPayloadSource source,
  ) async {
    final parts = <JSAny>[];
    var streamed = 0;
    await for (final chunk in source.openRead()) {
      streamed += chunk.length;
      // Already a Uint8List on every path this app produces; the copy is only
      // for a source that hands back some other List<int>.
      parts.add((chunk is Uint8List ? chunk : Uint8List.fromList(chunk)).toJS);
    }
    if (streamed != source.length) {
      throw StateError('The attachment changed while it was being saved.');
    }
    final headers = web.Headers()
      ..set('content-type', 'application/octet-stream')
      ..set('cache-control', 'no-store');
    await (await _cache(accountNamespace))
        .put(
          _key(entryId).toJS,
          web.Response(
            web.Blob(parts.toJS),
            web.ResponseInit(status: 200, headers: headers),
          ),
        )
        .toDart;
  }

  @override
  Future<bool> exists(String accountNamespace, String entryId) async =>
      await (await _cache(accountNamespace)).match(_key(entryId).toJS).toDart !=
      null;

  @override
  Future<Set<String>> keys(String accountNamespace) async {
    final requests = (await (await _cache(
      accountNamespace,
    )).keys().toDart).toDart;
    return requests
        .where((request) => request.url.startsWith(_prefix))
        .map(
          (request) =>
              Uri.decodeComponent(request.url.substring(_prefix.length)),
        )
        .where((key) => key.isNotEmpty)
        .toSet();
  }

  @override
  Future<String> upload(
    String accountNamespace,
    String entryId,
    Reference reference,
    SettableMetadata metadata, {
    void Function(double progress)? onProgress,
  }) async {
    final response = await (await _cache(
      accountNamespace,
    )).match(_key(entryId).toJS).toDart;
    if (response == null) {
      throw StateError('Pending attachment bytes are missing.');
    }
    final buffer = await response.arrayBuffer().toDart;
    final task = reference.putData(buffer.toDart.asUint8List(), metadata);
    final report = onProgress;
    final progress = report == null
        ? null
        : task.snapshotEvents.listen((snapshot) {
            final total = snapshot.totalBytes;
            if (total > 0) report(snapshot.bytesTransferred / total);
          }, onError: (Object _) {});
    final TaskSnapshot snapshot;
    try {
      snapshot = await task;
    } finally {
      await progress?.cancel();
    }
    final generation = snapshot.metadata?.generation?.trim();
    if (generation != null && generation.isNotEmpty) return generation;
    return (await snapshot.ref.getMetadata()).generation ?? '';
  }

  @override
  Future<void> delete(String accountNamespace, String entryId) async {
    await (await _cache(accountNamespace)).delete(_key(entryId).toJS).toDart;
  }

  @override
  Future<void> clear(String accountNamespace) async {
    await web.window.caches.delete(_cacheName(accountNamespace)).toDart;
  }
}
