import 'package:firebase_storage/firebase_storage.dart';

import 'package:yovoice/features/messages/data/services/direct_attachment_payload_source.dart';

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

  /// Copies [source] into durable storage without ever holding it whole.
  ///
  /// The only reason a voice message was ever read into a `Uint8List` was to
  /// hand that buffer to a bytes-shaped writer; the recording was a file the
  /// entire time. Payloads that genuinely are resident — a picked photo the
  /// composer is previewing — arrive here as a resident source and cost the
  /// same single write they always did.
  ///
  /// Ownership of [source] is NOT taken here. The caller releases it only
  /// after the manifest naming this payload is durable, so a failure anywhere
  /// in between leaves the producer's copy intact.
  Future<void> adopt(
    String accountNamespace,
    String entryId,
    DirectAttachmentPayloadSource source,
  );

  Future<bool> exists(String accountNamespace, String entryId);

  Future<Set<String>> keys(String accountNamespace);

  /// Uploads the durable copy and returns the committed Storage generation.
  ///
  /// [onProgress] receives values in 0..1 whenever Storage reports transferred
  /// bytes against a known total. It is advisory: a store that cannot observe
  /// its transport simply never calls it, and the caller must stay correct
  /// without it.
  Future<String> upload(
    String accountNamespace,
    String entryId,
    Reference reference,
    SettableMetadata metadata, {
    void Function(double progress)? onProgress,
  });

  Future<void> delete(String accountNamespace, String entryId);

  Future<void> clear(String accountNamespace);
}
