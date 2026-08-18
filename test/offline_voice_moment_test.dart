import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/moments/data/models/downloaded_voice_moment.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/offline_audio_storage.dart';
import 'package:yovoice/features/moments/data/services/offline_voice_moment_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/settings/presentation/screens/downloaded_audio_screen.dart';

VoiceMoment _moment(String id, {String caption = 'A useful thought'}) =>
    VoiceMoment(
      id: id,
      authorId: 'creator-1',
      authorName: 'Creator One',
      authorPhotoUrl: null,
      caption: caption,
      audioUrl: 'https://example.invalid/$id.m4a',
      durationSeconds: 42,
      likeCount: 3,
      commentCount: 1,
      isPublished: true,
      createdAt: DateTime.utc(2026, 8, 18),
      schemaVersion: 2,
      status: 'published',
    );

OfflineVoiceMomentService _service(
  _MemoryOfflineStorage storage, {
  String? Function()? currentUid,
  Future<Uint8List> Function(Uri)? fetcher,
}) => OfflineVoiceMomentService.forTest(
  storage: storage,
  currentUserId: currentUid ?? () => 'account-a',
  fetcher: fetcher ?? (_) async => Uint8List(2048),
);

void main() {
  test('downloads are account-scoped and removable', () async {
    final storage = _MemoryOfflineStorage();
    var uid = 'opaque użytkownik';
    final service = _service(storage, currentUid: () => uid);

    await service.download(_moment('moment-ą'));
    expect(await service.isDownloaded('moment-ą'), isTrue);
    expect((await service.list()).single.caption, 'A useful thought');

    uid = 'account-b';
    expect(await service.list(), isEmpty);
    expect(await service.isDownloaded('moment-ą'), isFalse);

    uid = 'opaque użytkownik';
    await service.delete('moment-ą');
    expect(await service.list(), isEmpty);
  });

  test(
    'account changes fail closed while local inventory is loading',
    () async {
      final storage = _MemoryOfflineStorage();
      var uid = 'account-a';
      final seed = _service(storage, currentUid: () => uid);
      await seed.download(_moment('private-audio'));

      final inventoryStarted = Completer<void>();
      final releaseInventory = Completer<void>();
      storage.onInventoryStarted = inventoryStarted;
      storage.inventoryGate = releaseInventory;
      final reader = _service(storage, currentUid: () => uid);
      final pending = reader.isDownloaded('private-audio');
      await inventoryStarted.future;
      uid = 'account-b';
      releaseInventory.complete();

      await expectLater(pending, throwsA(isA<OfflineAudioException>()));
    },
  );

  test(
    'account changes during download never write into another account',
    () async {
      final storage = _MemoryOfflineStorage();
      var uid = 'account-a';
      final fetchStarted = Completer<void>();
      final releaseFetch = Completer<void>();
      final service = _service(
        storage,
        currentUid: () => uid,
        fetcher: (_) async {
          fetchStarted.complete();
          await releaseFetch.future;
          return Uint8List(2048);
        },
      );

      final pending = service.download(_moment('switching-account'));
      await fetchStarted.future;
      uid = 'account-b';
      releaseFetch.complete();

      await expectLater(pending, throwsA(isA<OfflineAudioException>()));
      expect(storage.audio, isEmpty);
      expect(storage.manifests, isEmpty);
    },
  );

  test(
    'catalog reconciles evicted files and deletes physical orphans',
    () async {
      final storage = _MemoryOfflineStorage();
      final service = _service(storage);
      await service.download(_moment('evicted'));
      final accountKey = storage.lastAccountKey!;
      storage.audio.remove('$accountKey/${_objectKey('evicted')}');

      expect(await service.list(), isEmpty);
      expect(
        DownloadedVoiceMoment.decodeManifest(storage.manifests[accountKey]!),
        isEmpty,
      );

      storage.audio['$accountKey/${_objectKey('orphan')}'] =
          OfflineAudioPlayback.bytes(Uint8List(2048));
      expect(await service.list(), isEmpty);
      expect(storage.audio, isEmpty);
    },
  );

  test('manifest encoder refuses any payload it could not read back', () {
    final items = <DownloadedVoiceMoment>[
      for (
        var index = 0;
        index < DownloadedVoiceMoment.maximumManifestItems;
        index++
      )
        DownloadedVoiceMoment(
          momentId: '${'m' * 1400}$index',
          authorId: '${'a' * 1400}$index',
          authorName: 'Creator',
          caption: 'c' * 400,
          durationSeconds: 60,
          byteLength: 2048,
          downloadedAt: DateTime.utc(2026, 8, 18),
        ),
    ];

    expect(
      () => DownloadedVoiceMoment.encodeManifest(items),
      throwsFormatException,
    );
  });

  test('catalog removes truncated and oversized physical audio', () async {
    final storage = _MemoryOfflineStorage();
    final service = _service(storage);
    await service.download(_moment('valid'));
    final accountKey = storage.lastAccountKey!;
    final manifest = storage.manifests[accountKey]!;
    final objectKey = _objectKey('valid');

    storage.audio['$accountKey/$objectKey'] = OfflineAudioPlayback.bytes(
      Uint8List(0),
    );
    final coldReader = _service(storage);
    expect(await coldReader.isDownloaded('valid'), isFalse);
    expect(await coldReader.readPlayback('valid'), isNull);
    expect(await coldReader.list(), isEmpty);
    expect(storage.audio, isEmpty);

    storage.manifests[accountKey] = manifest;
    storage.audio['$accountKey/$objectKey'] = OfflineAudioPlayback.bytes(
      Uint8List(OfflineVoiceMomentService.maximumBytes + 1),
    );
    final secondColdReader = _service(storage);
    expect(await secondColdReader.isDownloaded('valid'), isFalse);
    expect(await secondColdReader.readPlayback('valid'), isNull);
    expect(await secondColdReader.list(), isEmpty);
    expect(storage.audio, isEmpty);
  });

  test('download operations are serialized and never overlap', () async {
    final storage = _MemoryOfflineStorage();
    var active = 0;
    var maximumActive = 0;
    final first = Completer<void>();
    final service = _service(
      storage,
      fetcher: (_) async {
        active += 1;
        maximumActive = active > maximumActive ? active : maximumActive;
        if (!first.isCompleted) await first.future;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        active -= 1;
        return Uint8List(2048);
      },
    );

    final one = service.download(_moment('one'));
    final two = service.download(_moment('two'));
    await Future<void>.delayed(Duration.zero);
    first.complete();
    await Future.wait([one, two]);

    expect(maximumActive, 1);
    expect(await service.list(), hasLength(2));
  });

  test('250 MB device cap is enforced before writing new audio', () async {
    final storage = _MemoryOfflineStorage();
    final service = _service(storage);
    // Discover the hashed account namespace without exposing the UID in local
    // storage keys, then seed a valid manifest close to the quota.
    await service.download(_moment('seed'));
    final accountKey = storage.lastAccountKey!;
    final entries = <Map<String, Object>>[
      for (var index = 0; index < 21; index++)
        <String, Object>{
          'schemaVersion': 1,
          'momentId': 'existing-$index',
          'authorId': 'creator',
          'authorName': 'Creator',
          'caption': '',
          'durationSeconds': 60,
          'byteLength': 12 * 1024 * 1024,
          'downloadedAt': DateTime.utc(2026, 8, 18).toIso8601String(),
        },
    ];
    storage.manifests[accountKey] = jsonEncode(<String, Object>{
      'schemaVersion': 1,
      'items': entries,
    });
    for (var index = 0; index < 21; index++) {
      storage.audio['$accountKey/${_objectKey('existing-$index')}'] =
          const OfflineAudioPlayback.deviceFile('/fake');
    }
    await expectLater(
      service.download(_moment('over-limit')),
      throwsA(
        isA<OfflineAudioException>().having(
          (error) => error.message,
          'message',
          contains('250 MB'),
        ),
      ),
    );
    expect(
      storage.audio.containsKey('$accountKey/${_objectKey('over-limit')}'),
      isFalse,
    );
  });

  testWidgets('Moment card downloads real audio with a 44px action', (
    tester,
  ) async {
    final service = _service(_MemoryOfflineStorage());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MomentCard(
            moment: _moment('card-download'),
            onComments: () {},
            offlineService: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final action = find.byKey(const ValueKey('download-moment-card-download'));
    expect(action, findsOneWidget);
    expect(tester.getSize(action).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(action).height, greaterThanOrEqualTo(44));

    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(await service.isDownloaded('card-download'), isTrue);
    expect(find.textContaining('downloaded for offline'), findsOneWidget);
  });

  testWidgets('moment cards share one bounded local inventory lookup', (
    tester,
  ) async {
    final storage = _MemoryOfflineStorage();
    final service = _service(storage);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              for (var index = 0; index < 20; index++)
                MomentCard(
                  moment: _moment('moment-$index'),
                  onComments: () {},
                  offlineService: service,
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(storage.inventoryCalls, 1);
  });

  for (final width in <double>[320, 390, 768, 1100, 1440]) {
    testWidgets('download manager fits ${width.toInt()}px at 200% text', (
      tester,
    ) async {
      final service = _service(_MemoryOfflineStorage());
      await service.download(_moment('screen-$width'));
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 844),
              textScaler: const TextScaler.linear(2),
            ),
            child: DownloadedAudioScreen(service: service),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A useful thought'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

class _MemoryOfflineStorage implements OfflineAudioStorage {
  final Map<String, String> manifests = <String, String>{};
  final Map<String, OfflineAudioPlayback> audio =
      <String, OfflineAudioPlayback>{};
  String? lastAccountKey;
  int inventoryCalls = 0;
  Completer<void>? inventoryGate;
  Completer<void>? onInventoryStarted;

  String _key(String accountKey, String momentId) => '$accountKey/$momentId';

  @override
  Future<void> clear(String accountKey) async {
    manifests.remove(accountKey);
    audio.removeWhere((key, _) => key.startsWith('$accountKey/'));
  }

  @override
  Future<void> deleteAudio(String accountKey, String momentId) async {
    audio.remove(_key(accountKey, momentId));
  }

  @override
  Future<bool> hasAudio(String accountKey, String momentId) async =>
      audio.containsKey(_key(accountKey, momentId));

  @override
  Future<OfflineAudioInventory> inventory(String accountKey) async {
    inventoryCalls += 1;
    if (onInventoryStarted case final started?) {
      if (!started.isCompleted) started.complete();
    }
    if (inventoryGate case final gate?) await gate.future;
    final prefix = '$accountKey/';
    return OfflineAudioInventory({
      for (final entry in audio.entries)
        if (entry.key.startsWith(prefix))
          entry.key.substring(prefix.length):
              entry.value.bytes?.length ?? 12 * 1024 * 1024,
    });
  }

  @override
  Future<OfflineAudioPlayback?> readPlayback(
    String accountKey,
    String momentId,
  ) async => audio[_key(accountKey, momentId)];

  @override
  Future<String?> readManifest(String accountKey) async {
    lastAccountKey = accountKey;
    return manifests[accountKey];
  }

  @override
  Future<void> writeAudio(
    String accountKey,
    String momentId,
    Uint8List bytes,
  ) async {
    lastAccountKey = accountKey;
    audio[_key(accountKey, momentId)] = OfflineAudioPlayback.bytes(bytes);
  }

  @override
  Future<void> writeManifest(String accountKey, String manifest) async {
    lastAccountKey = accountKey;
    manifests[accountKey] = manifest;
  }
}

String _objectKey(String momentId) =>
    sha256.convert(utf8.encode(momentId)).toString();
