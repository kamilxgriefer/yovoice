import 'dart:typed_data';

import 'offline_audio_storage_stub.dart'
    if (dart.library.io) 'offline_audio_storage_io.dart'
    if (dart.library.js_interop) 'offline_audio_storage_web.dart';

class OfflineAudioPlayback {
  const OfflineAudioPlayback.bytes(Uint8List this.bytes)
    : deviceFilePath = null;
  const OfflineAudioPlayback.deviceFile(String this.deviceFilePath)
    : bytes = null;

  final Uint8List? bytes;
  final String? deviceFilePath;
}

class OfflineAudioInventory {
  const OfflineAudioInventory(this.byteLengths);

  final Map<String, int> byteLengths;

  int get totalBytes => byteLengths.values.fold(0, (sum, value) => sum + value);
}

abstract class OfflineAudioStorage {
  factory OfflineAudioStorage() => createOfflineAudioStorage();

  Future<String?> readManifest(String accountKey);
  Future<void> writeManifest(String accountKey, String manifest);
  Future<void> writeAudio(String accountKey, String momentId, Uint8List bytes);
  Future<bool> hasAudio(String accountKey, String momentId);
  Future<OfflineAudioInventory> inventory(String accountKey);
  Future<OfflineAudioPlayback?> readPlayback(
    String accountKey,
    String momentId,
  );
  Future<void> deleteAudio(String accountKey, String momentId);
  Future<void> clear(String accountKey);
}
