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
  }) => {
    'schemaVersion': 1,
    'available': available,
    'expiresAtMillis': DateTime.now()
        .toUtc()
        .add(const Duration(seconds: 80))
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
}

final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
