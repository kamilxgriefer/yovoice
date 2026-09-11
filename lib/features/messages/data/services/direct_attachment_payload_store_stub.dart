import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import 'package:yovoice/features/messages/data/services/direct_attachment_payload_source.dart';

import 'direct_attachment_payload_store.dart';

DirectAttachmentPayloadStore createDirectAttachmentPayloadStore() =>
    _MemoryDirectAttachmentPayloadStore();

class _MemoryDirectAttachmentPayloadStore
    implements DirectAttachmentPayloadStore {
  final Map<String, Uint8List> _payloads = <String, Uint8List>{};

  String _key(String accountNamespace, String entryId) =>
      '$accountNamespace:$entryId';

  @override
  Future<void> adopt(
    String accountNamespace,
    String entryId,
    DirectAttachmentPayloadSource source,
  ) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in source.openRead()) {
      builder.add(chunk);
    }
    if (builder.length != source.length) {
      throw StateError('The attachment changed while it was being saved.');
    }
    _payloads[_key(accountNamespace, entryId)] = builder.takeBytes();
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
    SettableMetadata metadata, {
    void Function(double progress)? onProgress,
  }) async {
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
