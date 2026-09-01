import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'package:yovoice/features/moments/data/models/downloaded_voice_moment.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';

import 'offline_audio_storage.dart';

typedef OfflineAudioFetcher = Future<Uint8List> Function(Uri uri);

class OfflineAudioException implements Exception {
  const OfflineAudioException(this.message);
  final String message;

  @override
  String toString() => message;
}

class OfflineVoiceMomentService {
  OfflineVoiceMomentService._({
    required OfflineAudioStorage storage,
    required String? Function() currentUserId,
    required OfflineAudioFetcher fetcher,
  }) : _storage = storage,
       _currentUserId = currentUserId,
       _fetcher = fetcher;

  static final OfflineVoiceMomentService instance = OfflineVoiceMomentService._(
    storage: OfflineAudioStorage(),
    currentUserId: () => FirebaseAuth.instance.currentUser?.uid,
    fetcher: _downloadBytes,
  );

  factory OfflineVoiceMomentService.forTest({
    required OfflineAudioStorage storage,
    required String? Function() currentUserId,
    required OfflineAudioFetcher fetcher,
  }) => OfflineVoiceMomentService._(
    storage: storage,
    currentUserId: currentUserId,
    fetcher: fetcher,
  );

  static const int maximumBytes = 12 * 1024 * 1024;
  static const int minimumBytes = 1024;
  static const int maximumTotalBytes = 250 * 1024 * 1024;

  final OfflineAudioStorage _storage;
  final String? Function() _currentUserId;
  final OfflineAudioFetcher _fetcher;
  Future<void> _mutation = Future<void>.value();
  final Map<String, Set<String>> _downloadIndex = {};
  final Map<String, Future<Set<String>>> _indexLoads = {};
  final Set<String> _clearingAccountKeys = {};

  String _requireUid() {
    final uid = _currentUserId() ?? '';
    if (uid.trim().isEmpty) {
      throw const OfflineAudioException(
        'Sign in to manage downloaded Voice Moments.',
      );
    }
    return uid;
  }

  String _accountKey(String uid) => sha256.convert(utf8.encode(uid)).toString();

  void _requireSameUid(String expectedUid) {
    if (_requireUid() != expectedUid) {
      throw const OfflineAudioException(
        'Your account changed while offline audio was being accessed. Try again.',
      );
    }
  }

  Future<({List<DownloadedVoiceMoment> items, OfflineAudioInventory inventory})>
  _catalogFor(String uid) async {
    _requireSameUid(uid);
    final key = _accountKey(uid);
    final source = await _storage.readManifest(key);
    final inventory = await _storage.inventory(key);
    _requireSameUid(uid);
    _downloadIndex[key] = inventory.byteLengths.keys.toSet();
    final items = source == null
        ? <DownloadedVoiceMoment>[]
        : DownloadedVoiceMoment.decodeManifest(source).toList();
    var manifestNeedsRepair = false;
    final visible =
        items
            .where((item) {
              final physicalLength =
                  inventory.byteLengths[_objectKey(item.momentId)];
              return physicalLength != null &&
                  physicalLength >= minimumBytes &&
                  physicalLength <= maximumBytes;
            })
            .map((item) {
              final physicalLength =
                  inventory.byteLengths[_objectKey(item.momentId)]!;
              if (physicalLength == item.byteLength) return item;
              manifestNeedsRepair = true;
              return DownloadedVoiceMoment(
                momentId: item.momentId,
                authorId: item.authorId,
                authorName: item.authorName,
                caption: item.caption,
                durationSeconds: item.durationSeconds,
                byteLength: physicalLength,
                downloadedAt: item.downloadedAt,
              );
            })
            .toList()
          ..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
    final expected = visible.map((item) => _objectKey(item.momentId)).toSet();
    for (final objectKey in inventory.byteLengths.keys) {
      if (!expected.contains(objectKey)) {
        await _storage.deleteAudio(key, objectKey);
      }
    }
    if (visible.length != items.length || manifestNeedsRepair) {
      await _storage.writeManifest(key, _encodeManifest(visible));
    }
    _requireSameUid(uid);
    final reconciledLengths = <String, int>{
      for (final item in visible)
        _objectKey(item.momentId):
            inventory.byteLengths[_objectKey(item.momentId)]!,
    };
    _downloadIndex[key] = reconciledLengths.keys.toSet();
    return (
      items: visible,
      inventory: OfflineAudioInventory(Map.unmodifiable(reconciledLengths)),
    );
  }

  Future<List<DownloadedVoiceMoment>> list() => _serial(() async {
    final uid = _requireUid();
    return (await _catalogFor(uid)).items;
  });

  Future<bool> isDownloaded(String momentId) async {
    final uid = _requireUid();
    final cleanId = _validateMomentId(momentId);
    final key = _accountKey(uid);
    final objectKey = _objectKey(cleanId);
    final downloaded = (await _indexFor(key)).contains(objectKey);
    _requireSameUid(uid);
    return downloaded;
  }

  Future<Set<String>> _indexFor(String accountKey) {
    if (_clearingAccountKeys.contains(accountKey)) {
      return Future<Set<String>>.value(const <String>{});
    }
    final cached = _downloadIndex[accountKey];
    if (cached != null) return Future.value(cached);
    return _indexLoads.putIfAbsent(accountKey, () async {
      try {
        final inventory = await _storage.inventory(accountKey);
        final index = <String>{};
        for (final entry in inventory.byteLengths.entries) {
          if (_isSupportedPhysicalLength(entry.value)) {
            index.add(entry.key);
          } else {
            await _storage.deleteAudio(accountKey, entry.key);
          }
        }
        if (_clearingAccountKeys.contains(accountKey)) {
          return const <String>{};
        }
        _downloadIndex[accountKey] = index;
        return index;
      } finally {
        _indexLoads.remove(accountKey);
      }
    });
  }

  Future<OfflineAudioPlayback?> readPlayback(String momentId) async {
    final uid = _requireUid();
    final cleanId = _validateMomentId(momentId);
    final accountKey = _accountKey(uid);
    final objectKey = _objectKey(cleanId);
    final inventory = await _storage.inventory(accountKey);
    final physicalLength = inventory.byteLengths[objectKey];
    if (physicalLength == null || !_isSupportedPhysicalLength(physicalLength)) {
      if (physicalLength != null) {
        await _storage.deleteAudio(accountKey, objectKey);
      }
      _downloadIndex[accountKey]?.remove(objectKey);
      _requireSameUid(uid);
      return null;
    }
    final playback = await _storage.readPlayback(accountKey, objectKey);
    if (playback == null) {
      _downloadIndex[accountKey]?.remove(objectKey);
    }
    _requireSameUid(uid);
    return playback;
  }

  Future<void> download(
    VoiceMoment moment, {
    required Uri authorizedUri,
  }) => _serial(() async {
    final uid = _requireUid();
    final momentId = _validateMomentId(moment.id);
    final authorId = moment.authorId;
    final authorName = moment.authorName.trim();
    final caption = moment.caption;
    if (!moment.isPublished ||
        moment.isDeleted ||
        authorId.trim().isEmpty ||
        utf8.encode(authorId).length > 1500 ||
        authorName.isEmpty ||
        authorName.length > 80 ||
        caption.length > 500 ||
        moment.durationSeconds < 1 ||
        moment.durationSeconds > 60 ||
        authorizedUri.scheme != 'https' ||
        authorizedUri.host != 'storage.googleapis.com' ||
        authorizedUri.hasPort ||
        authorizedUri.userInfo.isNotEmpty) {
      throw const OfflineAudioException(
        'This Voice Moment is not available for offline download.',
      );
    }
    final bytes = await _fetcher(authorizedUri);
    if (bytes.length < minimumBytes || bytes.length > maximumBytes) {
      throw const OfflineAudioException(
        'The audio file has an unsupported size.',
      );
    }
    if (_requireUid() != uid) {
      throw const OfflineAudioException(
        'Your account changed before the download finished. Try again.',
      );
    }

    final key = _accountKey(uid);
    final catalog = await _catalogFor(uid);
    final current = catalog.items;
    final isNew = !current.any((entry) => entry.momentId == momentId);
    if (isNew && current.length >= DownloadedVoiceMoment.maximumManifestItems) {
      throw const OfflineAudioException(
        'Offline audio is limited to 250 downloads on each device. Remove an older download and try again.',
      );
    }
    final objectKey = _objectKey(momentId);
    final existingBytes = catalog.inventory.byteLengths[objectKey] ?? 0;
    final totalAfterDownload =
        catalog.inventory.totalBytes - existingBytes + bytes.length;
    if (totalAfterDownload > maximumTotalBytes) {
      throw const OfflineAudioException(
        'Offline audio is limited to 250 MB on each device. Remove an older download and try again.',
      );
    }
    final item = DownloadedVoiceMoment(
      momentId: momentId,
      authorId: authorId,
      authorName: authorName,
      caption: caption,
      durationSeconds: moment.durationSeconds,
      byteLength: bytes.length,
      downloadedAt: DateTime.now().toUtc(),
    );
    final next = <DownloadedVoiceMoment>[
      item,
      ...current.where((entry) => entry.momentId != momentId),
    ];
    final nextManifest = _encodeManifest(next);
    _requireSameUid(uid);
    await _storage.writeAudio(key, objectKey, bytes);
    if (_requireUid() != uid) {
      if (isNew) await _storage.deleteAudio(key, objectKey);
      throw const OfflineAudioException(
        'Your account changed before the download finished. Try again.',
      );
    }
    try {
      await _storage.writeManifest(key, nextManifest);
      _downloadIndex[key] = {...?_downloadIndex[key], objectKey};
      _requireSameUid(uid);
    } catch (_) {
      if (isNew) await _storage.deleteAudio(key, objectKey);
      rethrow;
    }
  });

  Future<void> delete(String momentId) => _serial(() async {
    final uid = _requireUid();
    final cleanId = _validateMomentId(momentId);
    final key = _accountKey(uid);
    final current = (await _catalogFor(uid)).items;
    await _storage.deleteAudio(key, _objectKey(cleanId));
    await _storage.writeManifest(
      key,
      _encodeManifest(
        current.where((item) => item.momentId != cleanId).toList(),
      ),
    );
    _downloadIndex[key]?.remove(_objectKey(cleanId));
    _requireSameUid(uid);
  });

  Future<void> clear() => _serial(() async {
    final uid = _requireUid();
    final key = _accountKey(uid);
    await _storage.clear(key);
    _downloadIndex.remove(key);
    _indexLoads.remove(key);
    _requireSameUid(uid);
  });

  /// Clears one account's offline media even after Firebase Auth has already
  /// removed the active user. Logout coordination must capture the uid before
  /// signing out and pass that exact value here; the hashed account key means
  /// no raw uid is used as a path segment.
  Future<void> clearForUser(String expectedUid) => _serial(() async {
    // Firebase UIDs are opaque and case/whitespace sensitive. Validate the
    // captured value, but never trim or normalize it before deriving the same
    // account key that was used when the file was downloaded.
    final uid = expectedUid;
    if (uid.trim().isEmpty ||
        utf8.encode(uid).length > 1500 ||
        uid.contains('/') ||
        RegExp(r'[\u0000-\u001F\u007F]').hasMatch(uid)) {
      throw const OfflineAudioException(
        'Invalid account identifier for offline media cleanup.',
      );
    }
    final key = _accountKey(uid);
    _clearingAccountKeys.add(key);
    try {
      // Let an inventory read already in flight finish before deleting the
      // directory/database. While the key is marked clearing, it cannot
      // repopulate the cache or start another inventory load.
      try {
        await _indexLoads[key];
      } catch (_) {
        // A failed lookup must never prevent privacy cleanup.
      }
      await _storage.clear(key);
      _downloadIndex.remove(key);
      _indexLoads.remove(key);
    } finally {
      _clearingAccountKeys.remove(key);
    }
  });

  String _validateMomentId(String value) {
    if (value.trim().isEmpty ||
        utf8.encode(value).length > 1500 ||
        value.contains('/')) {
      throw const OfflineAudioException('Invalid Voice Moment identifier.');
    }
    return value;
  }

  String _objectKey(String momentId) =>
      sha256.convert(utf8.encode(momentId)).toString();

  bool _isSupportedPhysicalLength(int length) =>
      length >= minimumBytes && length <= maximumBytes;

  String _encodeManifest(List<DownloadedVoiceMoment> items) {
    try {
      return DownloadedVoiceMoment.encodeManifest(items);
    } on FormatException {
      throw const OfflineAudioException(
        'The offline download list is full on this device. Remove an older download and try again.',
      );
    }
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _mutation = _mutation.catchError((_) {}).then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  static Future<Uint8List> _downloadBytes(Uri uri) async {
    final client = http.Client();
    try {
      final response = await client
          .send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 25));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const OfflineAudioException(
          'The Voice Moment could not be downloaded.',
        );
      }
      final declared = response.contentLength;
      if (declared != null &&
          (declared < minimumBytes || declared > maximumBytes)) {
        throw const OfflineAudioException(
          'The audio file has an unsupported size.',
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 25),
      )) {
        builder.add(chunk);
        if (builder.length > maximumBytes) {
          throw const OfflineAudioException('The audio file is too large.');
        }
      }
      return builder.takeBytes();
    } on TimeoutException {
      throw const OfflineAudioException(
        'The download timed out. Check your connection and try again.',
      );
    } finally {
      client.close();
    }
  }
}
