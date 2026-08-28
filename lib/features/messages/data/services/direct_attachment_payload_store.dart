import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import 'direct_attachment_payload_store_stub.dart'
    if (dart.library.io) 'direct_attachment_payload_store_io.dart'
    if (dart.library.js_interop) 'direct_attachment_payload_store_web.dart';

/// Durable, app-private payload storage for direct-message attachment work.
///
/// Metadata lives in the attachment outbox. This store owns only the bytes,
/// under an already-hashed account namespace, so switching accounts can never
/// expose or resume another account's pending media.
abstract class DirectAttachmentPayloadStore {
  factory DirectAttachmentPayloadStore() =>
      createDirectAttachmentPayloadStore();

  Future<void> write(String accountNamespace, String entryId, Uint8List bytes);

  Future<bool> exists(String accountNamespace, String entryId);

  Future<Set<String>> keys(String accountNamespace);

  /// Uploads the durable copy and returns the committed Storage generation.
  Future<String> upload(
    String accountNamespace,
    String entryId,
    Reference reference,
    SettableMetadata metadata,
  );

  Future<void> delete(String accountNamespace, String entryId);

  Future<void> clear(String accountNamespace);
}
