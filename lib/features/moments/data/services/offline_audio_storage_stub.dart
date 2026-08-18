import 'dart:typed_data';

import 'offline_audio_storage.dart';

OfflineAudioStorage createOfflineAudioStorage() =>
    _UnsupportedOfflineAudioStorage();

class _UnsupportedOfflineAudioStorage implements OfflineAudioStorage {
  Never _unsupported() =>
      throw UnsupportedError('Offline audio is unavailable on this platform.');

  @override
  Future<void> clear(String accountKey) async => _unsupported();

  @override
  Future<void> deleteAudio(String accountKey, String momentId) async =>
      _unsupported();

  @override
  Future<bool> hasAudio(String accountKey, String momentId) async =>
      _unsupported();

  @override
  Future<OfflineAudioInventory> inventory(String accountKey) async =>
      _unsupported();

  @override
  Future<OfflineAudioPlayback?> readPlayback(
    String accountKey,
    String momentId,
  ) async => _unsupported();

  @override
  Future<String?> readManifest(String accountKey) async => _unsupported();

  @override
  Future<void> writeAudio(
    String accountKey,
    String momentId,
    Uint8List bytes,
  ) async => _unsupported();

  @override
  Future<void> writeManifest(String accountKey, String manifest) async =>
      _unsupported();
}
