import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/core/security/ephemeral_media_access_registry.dart';

typedef ProfileMediaCallableInvoker =
    Future<Map<Object?, Object?>> Function(
      String callable,
      Map<String, Object?> request,
    );

typedef ProfileMediaClock = DateTime Function();

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

class ProfileMediaAccess {
  const ProfileMediaAccess({required this.uri, required this.expiresAt});

  final Uri? uri;
  final DateTime expiresAt;
}

class ProfileMediaAccessBoundary {
  const ProfileMediaAccessBoundary({this.userId});

  /// Null means every mounted grant must be dropped, for example on logout.
  final String? userId;
}

class ProfileMediaService {
  ProfileMediaService({
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    ProfileMediaCallableInvoker? invoker,
    ProfileMediaClock? clock,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _functionsOverride = functions,
       _invoker = invoker,
       _clock = clock ?? DateTime.now {
    _registerCacheBoundary();
  }

  final FirebaseAuth _auth;
  final FirebaseFunctions? _functionsOverride;
  final ProfileMediaCallableInvoker? _invoker;
  final ProfileMediaClock _clock;

  static const int maxCacheEntries = 256;
  static final Map<String, ProfileMediaAccess> _cache = {};
  static final Map<String, Future<ProfileMediaAccess>> _pending = {};
  static final Map<String, int> _targetEpochs = {};
  static final StreamController<ProfileMediaAccessBoundary> _accessBoundaries =
      StreamController<ProfileMediaAccessBoundary>.broadcast(sync: true);
  static int _cacheEpoch = 0;
  static bool _registered = false;

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  DateTime get nowUtc => _clock().toUtc();

  static Stream<ProfileMediaAccessBoundary> get accessBoundaries =>
      _accessBoundaries.stream;

  static int get debugCacheEntryCount => _cache.length;

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
    _targetEpochs.clear();
    _cache.clear();
    _pending.clear();
    _accessBoundaries.add(const ProfileMediaAccessBoundary());
  }

  static void evictUser(String userId) {
    final clean = userId.trim();
    if (clean.isEmpty) return;
    _targetEpochs[clean] = (_targetEpochs[clean] ?? 0) + 1;
    _cache.removeWhere((key, _) => key.contains(':$clean:'));
    _pending.removeWhere((key, _) => key.contains(':$clean:'));
    _accessBoundaries.add(ProfileMediaAccessBoundary(userId: clean));
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
    Object? revision,
  }) => resolveAccess(
    userId: userId,
    kind: kind,
    revision: revision,
  ).then((access) => access.uri);

  Future<ProfileMediaAccess> resolveAccess({
    required String userId,
    required ProfileMediaKind kind,
    Object? revision,
  }) {
    final viewerId = _auth.currentUser?.uid ?? '';
    final targetId = userId.trim();
    if (viewerId.isEmpty) {
      throw StateError('You must be signed in to view profile media.');
    }
    if (targetId.isEmpty || targetId.contains('/') || targetId.length > 128) {
      throw const FormatException('The profile-media user id is invalid.');
    }
    final key = '$viewerId:$targetId:${kind.name}:${_revisionKey(revision)}';
    final now = nowUtc;
    final cached = _cache[key];
    if (cached != null &&
        cached.expiresAt.isAfter(now.add(const Duration(seconds: 15)))) {
      // Dart maps retain insertion order. Reinsert the requested entry to make
      // this a bounded O(1) LRU without scanning every avatar on every build.
      _cache.remove(key);
      _cache[key] = cached;
      return Future.value(cached);
    }
    _cache.remove(key);
    final epoch = _cacheEpoch;
    final targetEpoch = _targetEpochs[targetId] ?? 0;
    // Epochs are part of the in-flight key, not the persisted cache key. A
    // target-scoped eviction can therefore start a fresh request immediately
    // without a stale future deleting or poisoning the new single-flight.
    final pendingKey = '$key:epoch-$epoch-$targetEpoch';
    return _pending.putIfAbsent(pendingKey, () async {
      try {
        final response = await _call('getProfileMediaAccess', {
          'userId': targetId,
          'kind': kind.name,
        });
        if (_auth.currentUser?.uid != viewerId ||
            _cacheEpoch != epoch ||
            (_targetEpochs[targetId] ?? 0) != targetEpoch) {
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
        final receivedAt = nowUtc;
        if (!expiresAt.isAfter(receivedAt) ||
            expiresAt.isAfter(receivedAt.add(const Duration(seconds: 91)))) {
          throw const FormatException('Unsafe profile-media grant expiry.');
        }
        if (!available) {
          final access = ProfileMediaAccess(uri: null, expiresAt: expiresAt);
          _storeCache(key, access);
          return access;
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
        final access = ProfileMediaAccess(uri: uri, expiresAt: expiresAt);
        _storeCache(key, access);
        return access;
      } finally {
        _pending.remove(pendingKey);
      }
    });
  }

  static void _storeCache(String key, ProfileMediaAccess access) {
    _cache.remove(key);
    while (_cache.length >= maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = access;
  }

  static String _revisionKey(Object? revision) {
    if (revision == null) return 'legacy';
    if (revision case DateTime value) {
      return 'date-${value.toUtc().microsecondsSinceEpoch}';
    }
    if (revision case String value) {
      final parsed = DateTime.tryParse(value.trim());
      if (parsed != null) {
        return 'date-${parsed.toUtc().microsecondsSinceEpoch}';
      }
    }
    if (revision case int value) return 'int-$value';
    if (revision case num value when value.isFinite) {
      return 'num-${value.toString()}';
    }
    final value = revision.toString();
    // Revisions only namespace an in-memory cache entry; they are never sent
    // to the server. Bounding the value prevents an accidental large object
    // from becoming retained cache-key data.
    return 'value-${value.length <= 96 ? value : value.substring(0, 96)}';
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
