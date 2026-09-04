import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/shared/widgets/profile/profile_media_image.dart';

void main() {
  MockFirebaseAuth auth(String uid) => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: uid, email: '$uid@example.invalid'),
  );

  Map<Object?, Object?> grant({
    bool available = true,
    String url = 'https://storage.googleapis.com/test-bucket/object?sig=x',
    DateTime? now,
    Duration lifetime = const Duration(seconds: 80),
  }) => {
    'schemaVersion': 1,
    'available': available,
    'expiresAtMillis': (now ?? DateTime.now())
        .toUtc()
        .add(lifetime)
        .millisecondsSinceEpoch,
    if (available) ...{
      'url': url,
      'generation': '123',
      'contentType': 'image/jpeg',
      'size': 4096,
    },
  };

  setUp(ProfileMediaService.clearAllMediaAccessCaches);

  test('deduplicates and caches grants by viewer, target and kind', () async {
    var calls = 0;
    final service = ProfileMediaService(
      auth: auth('viewer-a'),
      invoker: (name, request) async {
        calls += 1;
        expect(name, 'getProfileMediaAccess');
        return grant();
      },
    );
    final values = await Future.wait([
      service.resolve(userId: 'target', kind: ProfileMediaKind.avatar),
      service.resolve(userId: 'target', kind: ProfileMediaKind.avatar),
    ]);
    expect(values.first, values.last);
    expect(calls, 1);
    await service.resolve(userId: 'target', kind: ProfileMediaKind.avatar);
    expect(calls, 1);

    final otherViewer = ProfileMediaService(
      auth: auth('viewer-b'),
      invoker: (_, __) async {
        calls += 1;
        return grant();
      },
    );
    await otherViewer.resolve(userId: 'target', kind: ProfileMediaKind.avatar);
    expect(calls, 2);
  });

  test(
    'a new public-profile revision cannot reuse a stale media grant',
    () async {
      var calls = 0;
      final service = ProfileMediaService(
        auth: auth('viewer'),
        invoker: (_, __) async {
          calls += 1;
          return grant();
        },
      );
      final firstRevision = DateTime.utc(2026, 9, 1, 12);
      final secondRevision = firstRevision.add(const Duration(seconds: 1));

      await service.resolve(
        userId: 'target',
        kind: ProfileMediaKind.avatar,
        revision: firstRevision,
      );
      await service.resolve(
        userId: 'target',
        kind: ProfileMediaKind.avatar,
        revision: firstRevision,
      );
      expect(calls, 1);

      await service.resolve(
        userId: 'target',
        kind: ProfileMediaKind.avatar,
        revision: secondRevision,
      );
      expect(
        calls,
        2,
        reason: 'a changed revision must obtain a fresh viewer grant',
      );
    },
  );

  test('equivalent DateTime and ISO revisions share one grant', () async {
    var calls = 0;
    final service = ProfileMediaService(
      auth: auth('viewer'),
      invoker: (_, __) async {
        calls += 1;
        return grant();
      },
    );
    final revision = DateTime.utc(2026, 9, 3, 8, 30, 15, 250);

    await service.resolve(
      userId: 'target',
      kind: ProfileMediaKind.avatar,
      revision: revision,
    );
    await service.resolve(
      userId: 'target',
      kind: ProfileMediaKind.avatar,
      revision: revision.toIso8601String(),
    );

    expect(calls, 1);
  });

  test('profile-media cache is a bounded LRU under high cardinality', () async {
    final now = DateTime.utc(2026, 9, 4, 12);
    var calls = 0;
    final service = ProfileMediaService(
      auth: auth('viewer'),
      clock: () => now,
      invoker: (_, __) async {
        calls += 1;
        return grant(now: now);
      },
    );

    for (
      var index = 0;
      index < ProfileMediaService.maxCacheEntries + 24;
      index++
    ) {
      await service.resolve(
        userId: 'target-$index',
        kind: ProfileMediaKind.avatar,
      );
    }

    expect(
      ProfileMediaService.debugCacheEntryCount,
      ProfileMediaService.maxCacheEntries,
    );
    final callsBeforeOldestLookup = calls;
    await service.resolve(userId: 'target-0', kind: ProfileMediaKind.avatar);
    expect(
      calls,
      callsBeforeOldestLookup + 1,
      reason: 'the oldest grant must be evicted instead of growing the cache',
    );
  });

  test(
    'negative grants cache null and never fall back to legacy URLs',
    () async {
      var calls = 0;
      final service = ProfileMediaService(
        auth: auth('viewer'),
        invoker: (_, __) async {
          calls += 1;
          return grant(available: false);
        },
      );
      expect(
        await service.resolve(userId: 'target', kind: ProfileMediaKind.banner),
        isNull,
      );
      expect(
        await service.resolve(userId: 'target', kind: ProfileMediaKind.banner),
        isNull,
      );
      expect(calls, 1);
    },
  );

  test('rejects non-Google or overlong capability grants', () async {
    final service = ProfileMediaService(
      auth: auth('viewer'),
      invoker: (_, __) async => grant(url: 'https://evil.example/avatar.jpg'),
    );
    await expectLater(
      service.resolve(userId: 'target', kind: ProfileMediaKind.avatar),
      throwsA(isA<FormatException>()),
    );
  });

  test('global clear invalidates a response already in flight', () async {
    final response = Completer<Map<Object?, Object?>>();
    final service = ProfileMediaService(
      auth: auth('viewer'),
      invoker: (_, __) => response.future,
    );
    final pending = service.resolve(
      userId: 'target',
      kind: ProfileMediaKind.avatar,
    );
    ProfileMediaService.clearAllMediaAccessCaches();
    response.complete(grant());
    await expectLater(pending, throwsA(isA<StateError>()));
  });

  test(
    'target eviction does not invalidate another avatar in flight',
    () async {
      final targetA = Completer<Map<Object?, Object?>>();
      final targetB = Completer<Map<Object?, Object?>>();
      final service = ProfileMediaService(
        auth: auth('viewer'),
        invoker: (_, request) => switch (request['userId']) {
          'target-a' => targetA.future,
          'target-b' => targetB.future,
          _ => throw StateError('unexpected target'),
        },
      );
      final pendingA = service.resolve(
        userId: 'target-a',
        kind: ProfileMediaKind.avatar,
      );
      final pendingB = service.resolve(
        userId: 'target-b',
        kind: ProfileMediaKind.avatar,
      );

      ProfileMediaService.evictUser('target-a');
      targetA.complete(grant());
      targetB.complete(grant());

      await expectLater(pendingA, throwsA(isA<StateError>()));
      await expectLater(pendingB, completion(isA<Uri>()));
    },
  );

  test(
    'target eviction starts a clean single-flight while stale work completes',
    () async {
      final responses = <Completer<Map<Object?, Object?>>>[];
      var calls = 0;
      final service = ProfileMediaService(
        auth: auth('viewer'),
        invoker: (_, __) {
          calls += 1;
          final response = Completer<Map<Object?, Object?>>();
          responses.add(response);
          return response.future;
        },
      );
      final stale = service.resolve(
        userId: 'target',
        kind: ProfileMediaKind.avatar,
      );
      ProfileMediaService.evictUser('target');
      final fresh = service.resolve(
        userId: 'target',
        kind: ProfileMediaKind.avatar,
      );
      expect(calls, 2);

      responses.first.complete(grant());
      await expectLater(stale, throwsA(isA<StateError>()));

      final freshDuplicate = service.resolve(
        userId: 'target',
        kind: ProfileMediaKind.avatar,
      );
      expect(calls, 2, reason: 'stale completion must not remove fresh work');
      responses.last.complete(grant());
      await expectLater(Future.wait([fresh, freshDuplicate]), completes);
    },
  );

  testWidgets(
    'a public-profile revision retains the resolved avatar while its new grant loads',
    (tester) async {
      final second = Completer<Map<Object?, Object?>>();
      var calls = 0;
      final service = ProfileMediaService(
        auth: auth('viewer'),
        invoker: (_, __) {
          calls++;
          return calls == 1 ? Future.value(grant()) : second.future;
        },
      );
      var revision = DateTime.utc(2026, 9, 2, 8);
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return ProfileMediaImage(
                userId: 'target',
                kind: ProfileMediaKind.avatar,
                fit: BoxFit.cover,
                service: service,
                revision: revision,
                fallback: const Text('T'),
                imageProvider: (_) => MemoryImage(_onePixelPng),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('T'), findsNothing);

      rebuild(() => revision = revision.add(const Duration(seconds: 1)));
      await tester.pump();
      expect(calls, 2);
      expect(
        find.byType(Image),
        findsOneWidget,
        reason: 'a transient grant refresh must not flash the initial',
      );
      expect(find.text('T'), findsNothing);

      second.complete(grant(available: false));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(
        find.text('T'),
        findsOneWidget,
        reason: 'an authoritative removal still clears the retained avatar',
      );
    },
  );

  testWidgets(
    'an expired mounted grant evicts its decoded image and reauthorizes',
    (tester) async {
      var now = DateTime.utc(2026, 9, 4, 12);
      var calls = 0;
      final provider = MemoryImage(_onePixelPng);
      final service = ProfileMediaService(
        auth: auth('viewer'),
        clock: () => now,
        invoker: (_, __) async {
          calls += 1;
          return calls == 1
              ? grant(now: now, lifetime: const Duration(seconds: 1))
              : grant(available: false, now: now);
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileMediaImage(
            userId: 'target',
            kind: ProfileMediaKind.avatar,
            fit: BoxFit.cover,
            service: service,
            fallback: const Text('T'),
            imageProvider: (_) => provider,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(PaintingBinding.instance.imageCache.containsKey(provider), isTrue);

      now = now.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.byType(Image), findsNothing);
      expect(find.text('T'), findsOneWidget);
      expect(
        PaintingBinding.instance.imageCache.containsKey(provider),
        isFalse,
        reason: 'expired bearer images must not survive in Flutter ImageCache',
      );
    },
  );

  testWidgets(
    'a global auth boundary clears mounted media without refetching',
    (tester) async {
      var calls = 0;
      final provider = MemoryImage(_onePixelPng);
      final service = ProfileMediaService(
        auth: auth('viewer'),
        invoker: (_, __) async {
          calls += 1;
          return grant();
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileMediaImage(
            userId: 'target',
            kind: ProfileMediaKind.avatar,
            fit: BoxFit.cover,
            service: service,
            fallback: const Text('T'),
            imageProvider: (_) => provider,
          ),
        ),
      );
      await tester.pumpAndSettle();

      ProfileMediaService.clearAllMediaAccessCaches();
      await tester.pump();

      expect(calls, 1, reason: 'logout boundaries must fail closed');
      expect(find.byType(Image), findsNothing);
      expect(find.text('T'), findsOneWidget);
      expect(
        PaintingBinding.instance.imageCache.containsKey(provider),
        isFalse,
      );
    },
  );

  testWidgets(
    'sibling avatar widgets share one refresh when their revision changes',
    (tester) async {
      final second = Completer<Map<Object?, Object?>>();
      var calls = 0;
      final service = ProfileMediaService(
        auth: auth('viewer'),
        invoker: (_, __) {
          calls += 1;
          return calls == 1 ? Future.value(grant()) : second.future;
        },
      );
      var revision = DateTime.utc(2026, 9, 2, 9);
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              Widget avatar(String label) => ProfileMediaImage(
                userId: 'target',
                kind: ProfileMediaKind.avatar,
                fit: BoxFit.cover,
                service: service,
                revision: revision,
                fallback: Text(label),
                imageProvider: (_) => MemoryImage(_onePixelPng),
              );
              return Row(children: [avatar('A'), avatar('B')]);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);

      rebuild(() => revision = revision.add(const Duration(seconds: 1)));
      await tester.pump();
      expect(calls, 2, reason: 'both widgets must share the fresh grant');

      second.complete(grant());
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNWidgets(2));
    },
  );
}

final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
