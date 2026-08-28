import 'dart:js_interop';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:web/web.dart' as web;

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

  @override
  Future<void> write(
    String accountNamespace,
    String entryId,
    Uint8List bytes,
  ) async {
    final headers = web.Headers()
      ..set('content-type', 'application/octet-stream')
      ..set('cache-control', 'no-store');
    await (await _cache(accountNamespace))
        .put(
          _key(entryId).toJS,
          web.Response(
            bytes.toJS,
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
    SettableMetadata metadata,
  ) async {
    final response = await (await _cache(
      accountNamespace,
    )).match(_key(entryId).toJS).toDart;
    if (response == null) {
      throw StateError('Pending attachment bytes are missing.');
    }
    final buffer = await response.arrayBuffer().toDart;
    final snapshot = await reference.putData(
      buffer.toDart.asUint8List(),
      metadata,
    );
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
