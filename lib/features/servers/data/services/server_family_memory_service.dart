import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:yovoice/features/moments/data/services/recorded_audio.dart';

import '../models/server_family_memory.dart';

typedef ServerFamilyMemoryCall =
    Future<Map<Object?, Object?>> Function(
      String callable,
      Map<String, Object?> payload,
    );
typedef ServerFamilyMemoryPhotoUploader =
    Future<String> Function(
      Uint8List bytes,
      ServerFamilyMemoryUploadTarget target,
    );
typedef ServerFamilyMemoryVoiceUploader =
    Future<String> Function(
      RecordedAudio audio,
      ServerFamilyMemoryUploadTarget target,
    );
typedef ServerFamilyMemoryRequestIdFactory = String Function();

enum ServerFamilyMemoryFailure {
  permission,
  quota,
  expiredReservation,
  changed,
  missing,
  invalidInput,
  corruptData,
  unavailable,
}

class ServerFamilyMemoryException implements Exception {
  const ServerFamilyMemoryException(this.failure);

  final ServerFamilyMemoryFailure failure;

  @override
  String toString() => 'Family Memory failed: ${failure.name}';
}

class ServerFamilyMemoryUploadTarget {
  const ServerFamilyMemoryUploadTarget({
    required this.storagePath,
    required this.contentType,
    required this.size,
    required this.uploadMetadata,
    this.durationMs,
  });

  final String storagePath;
  final String contentType;
  final int size;
  final Map<String, String> uploadMetadata;
  final int? durationMs;
}

class ServerFamilyMemoryReservation {
  const ServerFamilyMemoryReservation({
    required this.serverId,
    required this.channelId,
    required this.memoryId,
    required this.expiresAt,
    required this.photo,
    required this.voice,
  });

  final String serverId;
  final String channelId;
  final String memoryId;
  final DateTime expiresAt;
  final ServerFamilyMemoryUploadTarget photo;
  final ServerFamilyMemoryUploadTarget voice;
}

class ServerFamilyMemoryPublishAttempt {
  ServerFamilyMemoryPublishAttempt({
    required this.serverId,
    required this.channelId,
    required this.caption,
    required this.photoBytes,
    required this.photoContentType,
    required this.voice,
    required this.voiceDurationMs,
    required this.reserveRequestId,
    required this.finalizeRequestId,
  });

  final String serverId;
  final String channelId;
  final String caption;
  final Uint8List photoBytes;
  final String photoContentType;
  final RecordedAudio voice;
  final int voiceDurationMs;
  final String reserveRequestId;
  final String finalizeRequestId;

  ServerFamilyMemoryReservation? reservation;
  String? photoGeneration;
  String? voiceGeneration;
}

abstract interface class ServerFamilyMemoryRepository {
  String newFamilyMemoryRequestId();

  Stream<List<ServerFamilyMemory>> watchFamilyMemories(
    String serverId,
    String channelId,
  );

  ServerFamilyMemoryPublishAttempt newFamilyMemoryPublishAttempt({
    required String serverId,
    required String channelId,
    required String caption,
    required Uint8List photoBytes,
    required String photoContentType,
    required RecordedAudio voice,
    required int voiceDurationMs,
  });

  Future<String> publishFamilyMemory(ServerFamilyMemoryPublishAttempt attempt);

  Future<ServerFamilyMemoryMediaAccess> getFamilyMemoryMediaAccess({
    required String serverId,
    required String channelId,
    required String memoryId,
  });

  Future<void> deleteFamilyMemory({
    required String serverId,
    required String channelId,
    required String memoryId,
    required int expectedRevision,
    required String requestId,
  });
}

class ServerFamilyMemoryService implements ServerFamilyMemoryRepository {
  ServerFamilyMemoryService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseStorage? storage,
    ServerFamilyMemoryCall? callOverride,
    ServerFamilyMemoryPhotoUploader? photoUploader,
    ServerFamilyMemoryVoiceUploader? voiceUploader,
    ServerFamilyMemoryRequestIdFactory? requestIdFactory,
    DateTime Function()? clock,
  }) : _firestoreOverride = firestore,
       _functionsOverride = functions,
       _storageOverride = storage,
       _callOverride = callOverride,
       _photoUploader = photoUploader,
       _voiceUploader = voiceUploader,
       _requestIdFactory = requestIdFactory,
       _clock = clock ?? DateTime.now;

  static const _maxBytes = 8 * 1024 * 1024;
  static final _safeId = RegExp(r'^[A-Za-z0-9_-]{8,128}$');
  static final _generation = RegExp(r'^[0-9]{1,30}$');
  static const _photoTypes = {'image/jpeg', 'image/png', 'image/webp'};

  final FirebaseFirestore? _firestoreOverride;
  final FirebaseFunctions? _functionsOverride;
  final FirebaseStorage? _storageOverride;
  final ServerFamilyMemoryCall? _callOverride;
  final ServerFamilyMemoryPhotoUploader? _photoUploader;
  final ServerFamilyMemoryVoiceUploader? _voiceUploader;
  final ServerFamilyMemoryRequestIdFactory? _requestIdFactory;
  final DateTime Function() _clock;
  final Map<String, ServerFamilyMemoryMediaAccess> _mediaCache = {};

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  @override
  String newFamilyMemoryRequestId() {
    final supplied = _requestIdFactory?.call();
    if (supplied != null) {
      if (!_safeId.hasMatch(supplied)) {
        throw const ServerFamilyMemoryException(
          ServerFamilyMemoryFailure.invalidInput,
        );
      }
      return supplied;
    }
    final random = Random.secure();
    final entropy = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'fm_${_clock().toUtc().microsecondsSinceEpoch}_$entropy';
  }

  @override
  Stream<List<ServerFamilyMemory>> watchFamilyMemories(
    String serverId,
    String channelId,
  ) {
    _requireScopedId(serverId);
    _requireScopedId(channelId);
    return _firestore
        .collection('clubs')
        .doc(serverId)
        .collection('moments')
        .where('channelId', isEqualTo: channelId)
        .where('status', isEqualTo: 'published')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((document) {
                try {
                  return ServerFamilyMemory.fromFirestore(
                    document,
                    serverId: serverId,
                    channelId: channelId,
                  );
                } on FormatException {
                  return null;
                }
              })
              .whereType<ServerFamilyMemory>()
              .toList(growable: false),
        );
  }

  @override
  ServerFamilyMemoryPublishAttempt newFamilyMemoryPublishAttempt({
    required String serverId,
    required String channelId,
    required String caption,
    required Uint8List photoBytes,
    required String photoContentType,
    required RecordedAudio voice,
    required int voiceDurationMs,
  }) {
    final cleanCaption = caption.trim();
    final cleanPhotoType = photoContentType.trim().toLowerCase();
    final cleanVoiceType = normalizeAudioContentType(voice.contentType);
    if (serverId.trim().isEmpty ||
        channelId.trim().isEmpty ||
        serverId.contains('/') ||
        channelId.contains('/') ||
        cleanCaption.length > 500 ||
        !_photoTypes.contains(cleanPhotoType) ||
        photoBytes.lengthInBytes < 128 ||
        photoBytes.lengthInBytes > _maxBytes ||
        cleanVoiceType != 'audio/mp4' ||
        voice.byteLength < 1024 ||
        voice.byteLength > _maxBytes ||
        voiceDurationMs < 1000 ||
        voiceDurationMs > 30000) {
      throw const ServerFamilyMemoryException(
        ServerFamilyMemoryFailure.invalidInput,
      );
    }
    return ServerFamilyMemoryPublishAttempt(
      serverId: serverId,
      channelId: channelId,
      caption: cleanCaption,
      photoBytes: photoBytes,
      photoContentType: cleanPhotoType,
      voice: voice,
      voiceDurationMs: voiceDurationMs,
      reserveRequestId: newFamilyMemoryRequestId(),
      finalizeRequestId: newFamilyMemoryRequestId(),
    );
  }

  @override
  Future<String> publishFamilyMemory(
    ServerFamilyMemoryPublishAttempt attempt,
  ) async {
    try {
      final reservation = attempt.reservation ??= await _reserve(attempt);
      if (reservation.expiresAt.isBefore(_clock().toUtc())) {
        throw const ServerFamilyMemoryException(
          ServerFamilyMemoryFailure.expiredReservation,
        );
      }
      attempt.photoGeneration ??= await _uploadPhoto(
        attempt.photoBytes,
        reservation.photo,
      );
      attempt.voiceGeneration ??= await _uploadVoice(
        attempt.voice,
        reservation.voice,
      );
      final result =
          await _call('finalizeServerFamilyMemoryV1', <String, Object?>{
            'serverId': attempt.serverId,
            'channelId': attempt.channelId,
            'memoryId': reservation.memoryId,
            'requestId': attempt.finalizeRequestId,
            'photoGeneration': attempt.photoGeneration,
            'voiceGeneration': attempt.voiceGeneration,
          });
      if (result.length != 6 ||
          result['schemaVersion'] != 1 ||
          result['serverId'] != attempt.serverId ||
          result['channelId'] != attempt.channelId ||
          result['memoryId'] != reservation.memoryId ||
          result['revision'] != 1 ||
          result['status'] != 'published') {
        throw const ServerFamilyMemoryException(
          ServerFamilyMemoryFailure.corruptData,
        );
      }
      return reservation.memoryId;
    } on ServerFamilyMemoryException {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw _functionFailure(error.code);
    } on FirebaseException catch (error) {
      throw ServerFamilyMemoryException(
        error.code == 'permission-denied'
            ? ServerFamilyMemoryFailure.permission
            : ServerFamilyMemoryFailure.unavailable,
      );
    } catch (_) {
      throw const ServerFamilyMemoryException(
        ServerFamilyMemoryFailure.unavailable,
      );
    }
  }

  Future<ServerFamilyMemoryReservation> _reserve(
    ServerFamilyMemoryPublishAttempt attempt,
  ) async {
    final response =
        await _call('reserveServerFamilyMemoryV1', <String, Object?>{
          'serverId': attempt.serverId,
          'channelId': attempt.channelId,
          'requestId': attempt.reserveRequestId,
          'caption': attempt.caption,
          'photoContentType': attempt.photoContentType,
          'photoSize': attempt.photoBytes.lengthInBytes,
          'voiceContentType': 'audio/mp4',
          'voiceSize': attempt.voice.byteLength,
          'voiceDurationMs': attempt.voiceDurationMs,
        });
    if (response.length != 7 ||
        response['schemaVersion'] != 1 ||
        response['serverId'] != attempt.serverId ||
        response['channelId'] != attempt.channelId ||
        response['memoryId'] is! String ||
        response['expiresAtMillis'] is! int) {
      throw const ServerFamilyMemoryException(
        ServerFamilyMemoryFailure.corruptData,
      );
    }
    final memoryId = response['memoryId']! as String;
    final photo = _uploadTarget(
      response['photo'],
      expectedServerId: attempt.serverId,
      expectedChannelId: attempt.channelId,
      expectedMemoryId: memoryId,
      expectedAssetKind: 'photo',
      expectedType: attempt.photoContentType,
      expectedSize: attempt.photoBytes.lengthInBytes,
      expectedDuration: null,
    );
    final voice = _uploadTarget(
      response['voice'],
      expectedServerId: attempt.serverId,
      expectedChannelId: attempt.channelId,
      expectedMemoryId: memoryId,
      expectedAssetKind: 'voice',
      expectedType: 'audio/mp4',
      expectedSize: attempt.voice.byteLength,
      expectedDuration: attempt.voiceDurationMs,
    );
    final expectedPrefix = 'family_moments/${attempt.serverId}/';
    if (memoryId.isEmpty ||
        memoryId.contains('/') ||
        !photo.storagePath.startsWith(expectedPrefix) ||
        !voice.storagePath.startsWith(expectedPrefix) ||
        !photo.storagePath.contains('/${memoryId}_photo.') ||
        !voice.storagePath.contains('/${memoryId}_voice.')) {
      throw const ServerFamilyMemoryException(
        ServerFamilyMemoryFailure.corruptData,
      );
    }
    return ServerFamilyMemoryReservation(
      serverId: attempt.serverId,
      channelId: attempt.channelId,
      memoryId: memoryId,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        response['expiresAtMillis']! as int,
        isUtc: true,
      ),
      photo: photo,
      voice: voice,
    );
  }

  ServerFamilyMemoryUploadTarget _uploadTarget(
    Object? raw, {
    required String expectedServerId,
    required String expectedChannelId,
    required String expectedMemoryId,
    required String expectedAssetKind,
    required String expectedType,
    required int expectedSize,
    required int? expectedDuration,
  }) {
    if (raw is! Map) {
      throw const ServerFamilyMemoryException(
        ServerFamilyMemoryFailure.corruptData,
      );
    }
    final data = Map<Object?, Object?>.from(raw);
    final metadataRaw = data['uploadMetadata'];
    if (data.length != (expectedDuration == null ? 4 : 5) ||
        data['storagePath'] is! String ||
        data['contentType'] != expectedType ||
        data['size'] != expectedSize ||
        (expectedDuration != null && data['durationMs'] != expectedDuration) ||
        metadataRaw is! Map) {
      throw const ServerFamilyMemoryException(
        ServerFamilyMemoryFailure.corruptData,
      );
    }
    final metadata = <String, String>{};
    for (final entry in metadataRaw.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const ServerFamilyMemoryException(
          ServerFamilyMemoryFailure.corruptData,
        );
      }
      metadata[entry.key as String] = entry.value as String;
    }
    final path = (data['storagePath']! as String).trim();
    if (metadata.length != 5 ||
        !metadata.keys.toSet().containsAll(const {
          'yovoiceServerId',
          'yovoiceChannelId',
          'yovoiceOwnerUid',
          'yovoiceMemoryId',
          'yovoiceAssetKind',
        }) ||
        metadata['yovoiceServerId'] != expectedServerId ||
        metadata['yovoiceChannelId'] != expectedChannelId ||
        metadata['yovoiceMemoryId'] != expectedMemoryId ||
        metadata['yovoiceAssetKind'] != expectedAssetKind ||
        (metadata['yovoiceOwnerUid']?.trim().isEmpty ?? true) ||
        metadata['yovoiceOwnerUid']!.contains('/') ||
        path.isEmpty ||
        path.contains('..')) {
      throw const ServerFamilyMemoryException(
        ServerFamilyMemoryFailure.corruptData,
      );
    }
    return ServerFamilyMemoryUploadTarget(
      storagePath: path,
      contentType: expectedType,
      size: expectedSize,
      uploadMetadata: metadata,
      durationMs: expectedDuration,
    );
  }

  Future<String> _uploadPhoto(
    Uint8List bytes,
    ServerFamilyMemoryUploadTarget target,
  ) async {
    final override = _photoUploader;
    if (override != null) {
      return _validGeneration(await override(bytes, target));
    }
    final upload = _storage
        .ref(target.storagePath)
        .putData(
          bytes,
          SettableMetadata(
            contentType: target.contentType,
            customMetadata: target.uploadMetadata,
          ),
        );
    late final TaskSnapshot snapshot;
    try {
      snapshot = await upload.timeout(const Duration(seconds: 60));
    } on TimeoutException {
      try {
        await upload.cancel().timeout(const Duration(seconds: 2));
      } catch (_) {
        // The immutable generation check in finalize prevents a late upload
        // from publishing stale bytes. Retain the attempt for a safe retry.
      }
      throw const ServerFamilyMemoryException(
        ServerFamilyMemoryFailure.unavailable,
      );
    }
    var generation = snapshot.metadata?.generation?.trim();
    if (generation == null || generation.isEmpty) {
      generation = (await snapshot.ref.getMetadata()).generation?.trim();
    }
    return _validGeneration(generation ?? '');
  }

  Future<String> _uploadVoice(
    RecordedAudio audio,
    ServerFamilyMemoryUploadTarget target,
  ) async {
    final override = _voiceUploader;
    if (override != null) {
      return _validGeneration(await override(audio, target));
    }
    return _validGeneration(
      await audio.uploadTo(
        _storage.ref(target.storagePath),
        SettableMetadata(
          contentType: target.contentType,
          customMetadata: target.uploadMetadata,
        ),
      ),
    );
  }

  String _validGeneration(String generation) {
    if (!_generation.hasMatch(generation)) {
      throw const ServerFamilyMemoryException(
        ServerFamilyMemoryFailure.corruptData,
      );
    }
    return generation;
  }

  @override
  Future<ServerFamilyMemoryMediaAccess> getFamilyMemoryMediaAccess({
    required String serverId,
    required String channelId,
    required String memoryId,
  }) async {
    _requireScopedId(serverId);
    _requireScopedId(channelId);
    _requireScopedId(memoryId);
    final key = '$serverId/$channelId/$memoryId';
    final cached = _mediaCache[key];
    if (cached != null &&
        cached.expiresAt.isAfter(
          _clock().toUtc().add(const Duration(seconds: 15)),
        )) {
      return cached;
    }
    try {
      final result = await _call('getServerFamilyMemoryMediaAccessV1', {
        'serverId': serverId,
        'channelId': channelId,
        'memoryId': memoryId,
      });
      if (result.length != 7 ||
          result['schemaVersion'] != 1 ||
          result['serverId'] != serverId ||
          result['channelId'] != channelId ||
          result['memoryId'] != memoryId ||
          result['expiresAtMillis'] is! int) {
        throw const ServerFamilyMemoryException(
          ServerFamilyMemoryFailure.corruptData,
        );
      }
      final access = ServerFamilyMemoryMediaAccess(
        serverId: serverId,
        channelId: channelId,
        memoryId: memoryId,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          result['expiresAtMillis']! as int,
          isUtc: true,
        ),
        photo: _mediaAsset(result['photo'], voice: false),
        voice: _mediaAsset(result['voice'], voice: true),
      );
      if (!access.expiresAt.isAfter(_clock().toUtc())) {
        throw const ServerFamilyMemoryException(
          ServerFamilyMemoryFailure.corruptData,
        );
      }
      _mediaCache[key] = access;
      return access;
    } on FirebaseFunctionsException catch (error) {
      throw _functionFailure(error.code);
    } on ServerFamilyMemoryException {
      rethrow;
    } catch (_) {
      throw const ServerFamilyMemoryException(
        ServerFamilyMemoryFailure.unavailable,
      );
    }
  }

  ServerFamilyMemoryMediaAsset _mediaAsset(Object? raw, {required bool voice}) {
    if (raw is! Map) {
      throw const ServerFamilyMemoryException(
        ServerFamilyMemoryFailure.corruptData,
      );
    }
    final data = Map<Object?, Object?>.from(raw);
    final expectedLength = voice ? 5 : 4;
    final url = Uri.tryParse(data['url'] as String? ?? '');
    final generation = data['generation'];
    final contentType = data['contentType'];
    final size = data['size'];
    final duration = data['durationMs'];
    final safeUrl =
        url != null &&
        url.host.isNotEmpty &&
        !url.hasFragment &&
        (url.scheme == 'https' ||
            (url.scheme == 'http' &&
                (url.host == 'localhost' || url.host == '127.0.0.1')));
    final contentTypeAllowed = voice
        ? contentType == 'audio/mp4'
        : contentType is String && _photoTypes.contains(contentType);
    if (data.length != expectedLength ||
        !safeUrl ||
        generation is! String ||
        !_generation.hasMatch(generation) ||
        !contentTypeAllowed ||
        size is! int ||
        size < (voice ? 1024 : 128) ||
        size > _maxBytes ||
        (voice && (duration is! int || duration < 1000 || duration > 30000))) {
      throw const ServerFamilyMemoryException(
        ServerFamilyMemoryFailure.corruptData,
      );
    }
    return ServerFamilyMemoryMediaAsset(
      url: url,
      generation: generation,
      contentType: contentType as String,
      size: size,
      durationMs: voice ? duration as int : null,
    );
  }

  @override
  Future<void> deleteFamilyMemory({
    required String serverId,
    required String channelId,
    required String memoryId,
    required int expectedRevision,
    required String requestId,
  }) async {
    _requireScopedId(serverId);
    _requireScopedId(channelId);
    _requireScopedId(memoryId);
    if (expectedRevision < 1 || !_safeId.hasMatch(requestId)) {
      throw const ServerFamilyMemoryException(
        ServerFamilyMemoryFailure.invalidInput,
      );
    }
    try {
      final result = await _call('deleteServerFamilyMemoryV1', {
        'serverId': serverId,
        'channelId': channelId,
        'memoryId': memoryId,
        'expectedRevision': expectedRevision,
        'requestId': requestId,
      });
      if (result.length != 7 ||
          result['serverId'] != serverId ||
          result['channelId'] != channelId ||
          result['memoryId'] != memoryId ||
          result['deletionRevision'] is! int ||
          result['deleted'] != true ||
          result['cleanupPending'] != false ||
          result['deletionOperationId'] is! String) {
        throw const ServerFamilyMemoryException(
          ServerFamilyMemoryFailure.corruptData,
        );
      }
      _mediaCache.remove('$serverId/$channelId/$memoryId');
    } on FirebaseFunctionsException catch (error) {
      throw _functionFailure(error.code);
    } on ServerFamilyMemoryException {
      rethrow;
    } catch (_) {
      throw const ServerFamilyMemoryException(
        ServerFamilyMemoryFailure.unavailable,
      );
    }
  }

  Future<Map<Object?, Object?>> _call(
    String callable,
    Map<String, Object?> payload,
  ) async {
    final override = _callOverride;
    if (override != null) return override(callable, payload);
    return (await _functions
            .httpsCallable(callable)
            .call<Map<Object?, Object?>>(payload))
        .data;
  }

  static void _requireScopedId(String value) {
    if (value.trim().isEmpty || value != value.trim() || value.contains('/')) {
      throw const ServerFamilyMemoryException(
        ServerFamilyMemoryFailure.invalidInput,
      );
    }
  }

  static ServerFamilyMemoryException _functionFailure(String code) =>
      ServerFamilyMemoryException(switch (code) {
        'permission-denied' ||
        'unauthenticated' => ServerFamilyMemoryFailure.permission,
        'resource-exhausted' => ServerFamilyMemoryFailure.quota,
        'failed-precondition' => ServerFamilyMemoryFailure.expiredReservation,
        'aborted' || 'already-exists' => ServerFamilyMemoryFailure.changed,
        'not-found' => ServerFamilyMemoryFailure.missing,
        'invalid-argument' => ServerFamilyMemoryFailure.invalidInput,
        'data-loss' => ServerFamilyMemoryFailure.corruptData,
        _ => ServerFamilyMemoryFailure.unavailable,
      });
}
