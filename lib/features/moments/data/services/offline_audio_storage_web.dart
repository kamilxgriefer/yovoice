import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'offline_audio_storage.dart';

OfflineAudioStorage createOfflineAudioStorage() => _WebOfflineAudioStorage();

class _WebOfflineAudioStorage implements OfflineAudioStorage {
  String _cacheName(String accountKey) => 'yovoice-offline-audio-$accountKey';
  String get _origin => web.window.location.origin;
  String get _manifestKey => '$_origin/__yovoice_offline_audio/manifest';
  String get _audioPrefix => '$_origin/__yovoice_offline_audio/';
  String _audioKey(String momentId) =>
      '$_origin/__yovoice_offline_audio/${Uri.encodeComponent(momentId)}';

  Future<web.Cache> _cache(String accountKey) =>
      web.window.caches.open(_cacheName(accountKey)).toDart;

  web.Response _response(Uint8List bytes, String contentType) {
    final headers = web.Headers()
      ..set('content-type', contentType)
      ..set('x-yovoice-byte-length', bytes.length.toString());
    return web.Response(
      bytes.toJS,
      web.ResponseInit(status: 200, headers: headers),
    );
  }

  @override
  Future<String?> readManifest(String accountKey) async {
    final response = await (await _cache(
      accountKey,
    )).match(_manifestKey.toJS).toDart;
    if (response == null) return null;
    return (await response.text().toDart).toDart;
  }

  @override
  Future<void> writeManifest(String accountKey, String manifest) async {
    await (await _cache(accountKey))
        .put(
          _manifestKey.toJS,
          _response(
            Uint8List.fromList(utf8.encode(manifest)),
            'application/json',
          ),
        )
        .toDart;
  }

  @override
  Future<void> writeAudio(
    String accountKey,
    String momentId,
    Uint8List bytes,
  ) async {
    await (await _cache(
      accountKey,
    )).put(_audioKey(momentId).toJS, _response(bytes, 'audio/mp4')).toDart;
  }

  @override
  Future<bool> hasAudio(String accountKey, String momentId) async =>
      await (await _cache(accountKey)).match(_audioKey(momentId).toJS).toDart !=
      null;

  @override
  Future<OfflineAudioInventory> inventory(String accountKey) async {
    final cache = await _cache(accountKey);
    final requests = (await cache.keys().toDart).toDart;
    final entries = await Future.wait(
      requests.where((request) => request.url.startsWith(_audioPrefix)).map((
        request,
      ) async {
        final response = await cache.match(request).toDart;
        if (response == null) return null;
        final encodedKey = request.url.substring(_audioPrefix.length);
        if (encodedKey.isEmpty || encodedKey == 'manifest') return null;
        final objectKey = Uri.decodeComponent(encodedKey);
        // Cache metadata is not an authority: browser eviction, interrupted
        // writes, or an older client can leave a stale header. Blob.size is
        // the physical cached object length without materializing its bytes.
        final length = (await response.blob().toDart).size;
        return MapEntry(objectKey, length);
      }),
    );
    return OfflineAudioInventory(
      Map.unmodifiable(
        Map.fromEntries(entries.whereType<MapEntry<String, int>>()),
      ),
    );
  }

  @override
  Future<OfflineAudioPlayback?> readPlayback(
    String accountKey,
    String momentId,
  ) async {
    final response = await (await _cache(
      accountKey,
    )).match(_audioKey(momentId).toJS).toDart;
    if (response == null) return null;
    final buffer = await response.arrayBuffer().toDart;
    return OfflineAudioPlayback.bytes(buffer.toDart.asUint8List());
  }

  @override
  Future<void> deleteAudio(String accountKey, String momentId) async {
    await (await _cache(accountKey)).delete(_audioKey(momentId).toJS).toDart;
  }

  @override
  Future<void> clear(String accountKey) async {
    await web.window.caches.delete(_cacheName(accountKey)).toDart;
  }
}
