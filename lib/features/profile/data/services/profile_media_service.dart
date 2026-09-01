import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/core/security/ephemeral_media_access_registry.dart';

typedef ProfileMediaCallableInvoker =
    Future<Map<Object?, Object?>> Function(
      String callable,
      Map<String, Object?> request,
    );

enum ProfileMediaKind { avatar, banner }

class ProfileMediaUploadReservation {
  const ProfileMediaUploadReservation({
    required this.uploadId,
    required this.storagePath,
    required this.expiresAt,
  });

  final String uploadId;
  final String storagePath;
  final DateTime expiresAt;
}

class ProfileMediaService {
  ProfileMediaService({
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    ProfileMediaCallableInvoker? invoker,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _functionsOverride = functions,
       _invoker = invoker {
    _registerCacheBoundary();
  }

  final FirebaseAuth _auth;
  final FirebaseFunctions? _functionsOverride;
  final ProfileMediaCallableInvoker? _invoker;

  static final Map<String, _CachedProfileMediaAccess> _cache = {};
  static final Map<String, Future<Uri?>> _pending = {};
  static int _cacheEpoch = 0;
  static bool _registered = false;

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  static void _registerCacheBoundary() {
    if (_registered) return;
    EphemeralMediaAccessRegistry.register(
      'profile-media',
      clearAllMediaAccessCaches,
    );
    _registered = true;
  }

  static void clearAllMediaAccessCaches() {
    _cacheEpoch += 1;
    _cache.clear();
    _pending.clear();
  }

  static void evictUser(String userId) {
    final clean = userId.trim();
    if (clean.isEmpty) return;
    _cacheEpoch += 1;
    _cache.removeWhere((key, _) => key.contains(':$clean:'));
    _pending.removeWhere((key, _) => key.contains(':$clean:'));
  }

  Future<ProfileMediaUploadReservation> reserveUpload({
    required ProfileMediaKind kind,
    required String uploadId,
    required String contentType,
    required int size,
  }) async {
    final response = await _call('reserveProfileMediaUpload', {
      'kind': kind.name,
      'uploadId': uploadId,
      'contentType': contentType,
      'size': size,
    });
    final path = response['storagePath'];
    final returnedId = response['uploadId'];
    final expiry = response['expiresAtMillis'];
    if (response['schemaVersion'] != 1 ||
        path is! String ||
        path.isEmpty ||
        path.length > 1024 ||
        returnedId != uploadId ||
        expiry is! int) {
      throw const FormatException('Malformed profile upload reservation.');
    }
    final expectedPrefix =
        'users/${_auth.currentUser?.uid ?? ''}/profile/${kind.name}_$uploadId.';
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiry, isUtc: true);
    if (!path.startsWith(expectedPrefix) ||
        path.contains('..') ||
        !expiresAt.isAfter(DateTime.now().toUtc())) {
      throw const FormatException('Unsafe profile upload reservation.');
    }
    return ProfileMediaUploadReservation(
      uploadId: uploadId,
      storagePath: path,
      expiresAt: expiresAt,
    );
  }

  Future<void> finalizeUpload({
    required String uploadId,
    required String objectGeneration,
  }) async {
    final response = await _call('finalizeProfileMediaUpload', {
      'uploadId': uploadId,
      'objectGeneration': objectGeneration,
    });
    if (response['schemaVersion'] != 1 ||
        response['userId'] != _auth.currentUser?.uid ||
        response['generation'] != objectGeneration ||
        response['kind'] is! String ||
        response['contentType'] is! String ||
        response['size'] is! int) {
      throw const FormatException('Malformed profile upload finalization.');
    }
    evictUser(response['userId'] as String);
  }

  Future<Uri?> resolve({
    required String userId,
    required ProfileMediaKind kind,
  }) {
    final viewerId = _auth.currentUser?.uid ?? '';
    final targetId = userId.trim();
    if (viewerId.isEmpty) {
      throw StateError('You must be signed in to view profile media.');
    }
    if (targetId.isEmpty || targetId.contains('/') || targetId.length > 128) {
      throw const FormatException('The profile-media user id is invalid.');
    }
    final key = '$viewerId:$targetId:${kind.name}';
    final now = DateTime.now().toUtc();
    final cached = _cache[key];
    if (cached != null &&
        cached.expiresAt.isAfter(now.add(const Duration(seconds: 15)))) {
      return Future.value(cached.uri);
    }
    final epoch = _cacheEpoch;
    return _pending.putIfAbsent(key, () async {
      try {
        final response = await _call('getProfileMediaAccess', {
          'userId': targetId,
          'kind': kind.name,
        });
        if (_auth.currentUser?.uid != viewerId || _cacheEpoch != epoch) {
          throw StateError(
            'Profile-media access was cleared before it could be used.',
          );
        }
        final available = response['available'];
        final rawExpiry = response['expiresAtMillis'];
        if (response['schemaVersion'] != 1 ||
            available is! bool ||
            rawExpiry is! int) {
          throw const FormatException('Malformed profile-media grant.');
        }
        final expiresAt = DateTime.fromMillisecondsSinceEpoch(
          rawExpiry,
          isUtc: true,
        );
        final receivedAt = DateTime.now().toUtc();
        if (!expiresAt.isAfter(receivedAt) ||
            expiresAt.isAfter(receivedAt.add(const Duration(seconds: 91)))) {
          throw const FormatException('Unsafe profile-media grant expiry.');
        }
        if (!available) {
          _cache[key] = _CachedProfileMediaAccess(
            uri: null,
            expiresAt: expiresAt,
          );
          return null;
        }
        final rawUrl = response['url'];
        final generation = response['generation'];
        final contentType = response['contentType'];
        final size = response['size'];
        if (rawUrl is! String ||
            rawUrl.length > 4096 ||
            generation is! String ||
            !RegExp(r'^[0-9]{1,30}$').hasMatch(generation) ||
            !const {
              'image/jpeg',
              'image/png',
              'image/webp',
            }.contains(contentType) ||
            size is! int ||
            size < 128 ||
            size > 2 * 1024 * 1024) {
          throw const FormatException('Malformed profile-media grant.');
        }
        final uri = Uri.tryParse(rawUrl);
        if (uri == null ||
            uri.scheme != 'https' ||
            uri.host != 'storage.googleapis.com' ||
            uri.hasPort ||
            uri.userInfo.isNotEmpty) {
          throw const FormatException('Unsafe profile-media grant URL.');
        }
        _cache[key] = _CachedProfileMediaAccess(uri: uri, expiresAt: expiresAt);
        return uri;
      } finally {
        _pending.remove(key);
      }
    });
  }

  Future<Map<Object?, Object?>> _call(
    String name,
    Map<String, Object?> request,
  ) async {
    if (_invoker != null) return _invoker(name, request);
    final result = await _functions
        .httpsCallable(name)
        .call<Map<Object?, Object?>>(request);
    return result.data;
  }
}

class _CachedProfileMediaAccess {
  const _CachedProfileMediaAccess({required this.uri, required this.expiresAt});

  final Uri? uri;
  final DateTime expiresAt;
}
