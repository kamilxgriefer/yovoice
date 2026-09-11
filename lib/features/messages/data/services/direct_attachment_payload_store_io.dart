import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'package:yovoice/features/messages/data/services/direct_attachment_payload_source.dart';

import 'direct_attachment_payload_store.dart';

DirectAttachmentPayloadStore createDirectAttachmentPayloadStore() =>
    _IoDirectAttachmentPayloadStore();

class _IoDirectAttachmentPayloadStore implements DirectAttachmentPayloadStore {
  Future<Directory> _directory(String accountNamespace) async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}direct_attachment_outbox'
      '${Platform.pathSeparator}$accountNamespace',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<File> _file(String accountNamespace, String entryId) async => File(
    '${(await _directory(accountNamespace)).path}'
    '${Platform.pathSeparator}$entryId.payload',
  );

  Future<void> _recover(String accountNamespace) async {
    final directory = await _directory(accountNamespace);
    await for (final entity in directory.list()) {
      if (entity is File && entity.path.endsWith('.tmp')) {
        await entity.delete();
      }
    }
  }

  /// Streams into a `.tmp` file that is flushed and renamed into place, so a
  /// crash mid-copy can never leave a truncated payload that looks complete.
  @override
  Future<void> adopt(
    String accountNamespace,
    String entryId,
    DirectAttachmentPayloadSource source,
  ) async {
    await _recover(accountNamespace);
    final destination = await _file(accountNamespace, entryId);
    final temporary = File('${destination.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
    final sink = temporary.openWrite();
    var written = 0;
    try {
      await for (final chunk in source.openRead()) {
        sink.add(chunk);
        written += chunk.length;
      }
      await sink.flush();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {
        // Closing a sink that already failed reports the same failure again.
        // The half-written file below is what actually has to go.
      }
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
    await sink.close();
    if (written != source.length) {
      // The producer's file changed underneath the copy. Publishing a
      // truncated recording is worse than refusing: the reservation already
      // declared what this attachment is, and the server would reject the
      // finalize anyway — after the person was told it had been sent.
      if (await temporary.exists()) await temporary.delete();
      throw StateError('The attachment changed while it was being saved.');
    }
    if (await destination.exists()) await destination.delete();
    await temporary.rename(destination.path);
  }

  @override
  Future<bool> exists(String accountNamespace, String entryId) async {
    await _recover(accountNamespace);
    return (await _file(accountNamespace, entryId)).exists();
  }

  @override
  Future<Set<String>> keys(String accountNamespace) async {
    await _recover(accountNamespace);
    final directory = await _directory(accountNamespace);
    final result = <String>{};
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.payload')) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      result.add(name.substring(0, name.length - '.payload'.length));
    }
    return result;
  }

  @override
  Future<String> upload(
    String accountNamespace,
    String entryId,
    Reference reference,
    SettableMetadata metadata, {
    void Function(double progress)? onProgress,
  }) async {
    final file = await _file(accountNamespace, entryId);
    if (!await file.exists()) {
      throw StateError('Pending attachment bytes are missing.');
    }
    final task = reference.putFile(file, metadata);
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
    final file = await _file(accountNamespace, entryId);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> clear(String accountNamespace) async {
    final directory = await _directory(accountNamespace);
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
