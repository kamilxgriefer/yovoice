import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/moments/data/services/moment_service.dart';

Map<Object?, Object?> _grant({
  String host = 'storage.googleapis.com',
  int? expiresAtMillis,
}) => <Object?, Object?>{
  'schemaVersion': 1,
  'url': 'https://$host/yovoice-private/moment.m4a?X-Goog-Signature=test',
  'expiresAtMillis':
      expiresAtMillis ??
      DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
  'mediaGeneration': '1700000000000001',
  'mediaContentType': 'audio/mp4',
  'mediaSize': 4096,
};

MomentService _service({
  required MockFirebaseAuth auth,
  required MomentMediaAccessInvoker invoker,
}) => MomentService(
  firestore: FakeFirebaseFirestore(),
  auth: auth,
  storage: MockFirebaseStorage(),
  mediaAccessInvoker: invoker,
);

void main() {
  setUp(MomentService.clearAllMediaAccessCaches);

  test(
    'media access is account-bound, deduplicated and briefly cached',
    () async {
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'viewer-a'),
      );
      final gate = Completer<void>();
      var calls = 0;
      final service = _service(
        auth: auth,
        invoker: (request) async {
          calls += 1;
          expect(request, <String, Object?>{'momentId': 'moment-1'});
          await gate.future;
          return _grant();
        },
      );

      final first = service.resolveMediaUri(momentId: 'moment-1');
      final second = service.resolveMediaUri(momentId: 'moment-1');
      gate.complete();
      expect(await first, await second);
      expect(calls, 1);

      await service.resolveMediaUri(momentId: 'moment-1');
      expect(calls, 1);
      service.clearMediaAccessCache();
    },
  );

  test(
    'central cache clear invalidates every service and in-flight grant',
    () async {
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'viewer-a'),
      );
      var calls = 0;
      final firstService = _service(
        auth: auth,
        invoker: (_) async {
          calls += 1;
          return _grant();
        },
      );
      final secondService = _service(
        auth: auth,
        invoker: (_) async {
          calls += 1;
          return _grant();
        },
      );

      await firstService.resolveMediaUri(momentId: 'moment-shared');
      await secondService.resolveMediaUri(momentId: 'moment-shared');
      expect(calls, 1);
      MomentService.clearAllMediaAccessCaches();
      await secondService.resolveMediaUri(momentId: 'moment-shared');
      expect(calls, 2);

      final started = Completer<void>();
      final release = Completer<void>();
      final inFlightService = _service(
        auth: auth,
        invoker: (_) async {
          started.complete();
          await release.future;
          return _grant();
        },
      );
      final pending = inFlightService.resolveMediaUri(
        momentId: 'moment-flight',
      );
      await started.future;
      MomentService.clearAllMediaAccessCaches();
      release.complete();
      await expectLater(pending, throwsA(isA<StateError>()));
    },
  );

  test('comment access carries only canonical ids', () async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'viewer-a'),
    );
    Map<String, Object?>? captured;
    final service = _service(
      auth: auth,
      invoker: (request) async {
        captured = request;
        return _grant();
      },
    );
    await service.resolveMediaUri(momentId: 'moment-1', commentId: 'comment-1');
    expect(captured, <String, Object?>{
      'momentId': 'moment-1',
      'commentId': 'comment-1',
    });
  });

  test('unsafe hosts and expired grants fail closed', () async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'viewer-a'),
    );
    final unsafe = _service(
      auth: auth,
      invoker: (_) async => _grant(host: 'attacker.example'),
    );
    await expectLater(
      unsafe.resolveMediaUri(momentId: 'moment-1'),
      throwsFormatException,
    );

    final nonDefaultPort = _service(
      auth: auth,
      invoker: (_) async => _grant(host: 'storage.googleapis.com:444'),
    );
    await expectLater(
      nonDefaultPort.resolveMediaUri(momentId: 'moment-1'),
      throwsFormatException,
    );

    final expired = _service(
      auth: auth,
      invoker: (_) async => _grant(
        expiresAtMillis: DateTime.now()
            .subtract(const Duration(seconds: 1))
            .millisecondsSinceEpoch,
      ),
    );
    await expectLater(
      expired.resolveMediaUri(momentId: 'moment-1'),
      throwsFormatException,
    );
  });

  test(
    'malformed ids and signed-out access never reach the callable',
    () async {
      var calls = 0;
      final auth = MockFirebaseAuth(signedIn: false);
      final service = _service(
        auth: auth,
        invoker: (_) async {
          calls += 1;
          return _grant();
        },
      );
      expect(
        () => service.resolveMediaUri(momentId: 'moment/escape'),
        throwsA(isA<StateError>()),
      );

      final signedInService = _service(
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'viewer-a'),
        ),
        invoker: (_) async {
          calls += 1;
          return _grant();
        },
      );
      expect(
        () => signedInService.resolveMediaUri(momentId: 'moment/escape'),
        throwsFormatException,
      );
      expect(calls, 0);
    },
  );

  test('a lost media grant response is bounded and replayed once', () async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'viewer-a'),
    );
    var calls = 0;
    final service = MomentService(
      firestore: FakeFirebaseFirestore(),
      auth: auth,
      storage: MockFirebaseStorage(),
      callableTimeout: const Duration(milliseconds: 5),
      mediaAccessInvoker: (_) {
        calls += 1;
        if (calls == 1) return Completer<Map<Object?, Object?>>().future;
        return Future<Map<Object?, Object?>>.value(_grant());
      },
    );

    expect(
      await service.resolveMediaUri(momentId: 'moment-timeout'),
      isA<Uri>(),
    );
    expect(calls, 2);
  });
}
