import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';

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

  @override
  Future<void> write(
    String accountNamespace,
    String entryId,
    Uint8List bytes,
  ) async {
    await _recover(accountNamespace);
    final destination = await _file(accountNamespace, entryId);
    final temporary = File('${destination.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
    await temporary.writeAsBytes(bytes, flush: true);
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
    SettableMetadata metadata,
  ) async {
    final file = await _file(accountNamespace, entryId);
    if (!await file.exists()) {
      throw StateError('Pending attachment bytes are missing.');
    }
    final snapshot = await reference.putFile(file, metadata);
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
