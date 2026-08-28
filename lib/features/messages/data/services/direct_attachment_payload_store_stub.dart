import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import 'direct_attachment_payload_store.dart';

DirectAttachmentPayloadStore createDirectAttachmentPayloadStore() =>
    _MemoryDirectAttachmentPayloadStore();

class _MemoryDirectAttachmentPayloadStore
    implements DirectAttachmentPayloadStore {
  final Map<String, Uint8List> _payloads = <String, Uint8List>{};

  String _key(String accountNamespace, String entryId) =>
      '$accountNamespace:$entryId';

  @override
  Future<void> write(
    String accountNamespace,
    String entryId,
    Uint8List bytes,
  ) async {
    _payloads[_key(accountNamespace, entryId)] = Uint8List.fromList(bytes);
  }

  @override
  Future<bool> exists(String accountNamespace, String entryId) async =>
      _payloads.containsKey(_key(accountNamespace, entryId));

  @override
  Future<Set<String>> keys(String accountNamespace) async {
    final prefix = '$accountNamespace:';
    return _payloads.keys
        .where((key) => key.startsWith(prefix))
        .map((key) => key.substring(prefix.length))
        .toSet();
  }

  @override
  Future<String> upload(
    String accountNamespace,
    String entryId,
    Reference reference,
    SettableMetadata metadata,
  ) async {
    final bytes = _payloads[_key(accountNamespace, entryId)];
    if (bytes == null) {
      throw StateError('Pending attachment bytes are missing.');
    }
    final snapshot = await reference.putData(bytes, metadata);
    final generation = snapshot.metadata?.generation?.trim();
    if (generation != null && generation.isNotEmpty) return generation;
    return (await snapshot.ref.getMetadata()).generation ?? '';
  }

  @override
  Future<void> delete(String accountNamespace, String entryId) async {
    _payloads.remove(_key(accountNamespace, entryId));
  }

  @override
  Future<void> clear(String accountNamespace) async {
    final prefix = '$accountNamespace:';
    _payloads.removeWhere((key, _) => key.startsWith(prefix));
  }
}
