import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'offline_audio_storage.dart';

OfflineAudioStorage createOfflineAudioStorage() => _IoOfflineAudioStorage();

class _IoOfflineAudioStorage implements OfflineAudioStorage {
  Future<Directory> _directory(String accountKey) async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}offline_voice_moments'
      '${Platform.pathSeparator}$accountKey',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<File> _file(String accountKey, String name) async => File(
    '${(await _directory(accountKey)).path}${Platform.pathSeparator}$name',
  );

  Future<void> _recover(String accountKey) async {
    final directory = await _directory(accountKey);
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      if (entity.path.endsWith('.tmp')) {
        await entity.delete();
        continue;
      }
      if (!entity.path.endsWith('.bak')) continue;
      final destination = File(
        entity.path.substring(0, entity.path.length - '.bak'.length),
      );
      if (await destination.exists()) {
        await entity.delete();
      } else {
        await entity.rename(destination.path);
      }
    }
  }

  Future<void> _atomicReplace(File destination, List<int> bytes) async {
    final temporary = File('${destination.path}.tmp');
    final backup = File('${destination.path}.bak');
    if (await temporary.exists()) await temporary.delete();
    if (await backup.exists()) await backup.delete();
    await temporary.writeAsBytes(bytes, flush: true);
    final hadDestination = await destination.exists();
    if (hadDestination) await destination.rename(backup.path);
    try {
      await temporary.rename(destination.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (!await destination.exists() && await backup.exists()) {
        await backup.rename(destination.path);
      }
      rethrow;
    }
  }

  @override
  Future<String?> readManifest(String accountKey) async {
    await _recover(accountKey);
    final file = await _file(accountKey, 'manifest.json');
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> writeManifest(String accountKey, String manifest) async {
    await _recover(accountKey);
    final destination = await _file(accountKey, 'manifest.json');
    await _atomicReplace(destination, utf8.encode(manifest));
  }

  @override
  Future<void> writeAudio(
    String accountKey,
    String momentId,
    Uint8List bytes,
  ) async {
    await _recover(accountKey);
    final destination = await _file(accountKey, '$momentId.m4a');
    await _atomicReplace(destination, bytes);
  }

  @override
  Future<bool> hasAudio(String accountKey, String momentId) async =>
      (await _fileAfterRecovery(accountKey, '$momentId.m4a')).exists();

  Future<File> _fileAfterRecovery(String accountKey, String name) async {
    await _recover(accountKey);
    return _file(accountKey, name);
  }

  @override
  Future<OfflineAudioInventory> inventory(String accountKey) async {
    await _recover(accountKey);
    final directory = await _directory(accountKey);
    final lengths = <String, int>{};
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.m4a')) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      final objectKey = name.substring(0, name.length - '.m4a'.length);
      lengths[objectKey] = await entity.length();
    }
    return OfflineAudioInventory(Map.unmodifiable(lengths));
  }

  @override
  Future<OfflineAudioPlayback?> readPlayback(
    String accountKey,
    String momentId,
  ) async {
    final file = await _fileAfterRecovery(accountKey, '$momentId.m4a');
    return await file.exists()
        ? OfflineAudioPlayback.deviceFile(file.path)
        : null;
  }

  @override
  Future<void> deleteAudio(String accountKey, String momentId) async {
    final file = await _fileAfterRecovery(accountKey, '$momentId.m4a');
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> clear(String accountKey) async {
    final directory = await _directory(accountKey);
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
