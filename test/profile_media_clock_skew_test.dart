import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/profile/data/services/profile_media_service.dart';

/// Regression coverage for the production profile-media grant contract.
///
/// `functions/profile/media_contract.js` issues every positive grant with
/// `PROFILE_MEDIA_ACCESS_TTL_MS = 90_000`, measured from the *server* clock.
/// `ProfileMediaService.resolveAccess` used to reject any grant whose expiry
/// was more than 91 s ahead of the *device* clock, which left a 1 s budget for
/// clock skew. A phone running a few seconds behind Google's clock therefore
/// discarded every successful grant and fell back to initials on every avatar
/// and banner in the app, while the server kept returning HTTP 200 with a
/// valid signed URL.
///
/// Measured on the Redmi Note 8 Pro (adb 6tq4g6f6ijrwxwzx, Build 31, Android
/// 11, `auto_time=1`): the device clock trailed server time by ~1.9 s.
///
/// The replacement is a symmetric plausibility window plus a lifetime that is
/// measured on the device clock, so a *fast* device clock cannot stretch a
/// grant past the server's TTL either.
void main() {
  MockFirebaseAuth auth(String uid) => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: uid, email: '$uid@example.invalid'),
  );

  /// A response shaped exactly like the deployed `getProfileMediaAccess`.
  Map<Object?, Object?> productionGrant(DateTime serverNow) => {
    'schemaVersion': 1,
    'available': true,
    'expiresAtMillis': serverNow
        .toUtc()
        .add(const Duration(milliseconds: 90000))
        .millisecondsSinceEpoch,
    'url': 'https://storage.googleapis.com/yovoice-ec54a.firebasestorage.app/'
        'users/u/profile/avatar_1786219699632.jpg?X-Goog-Signature=abc',
    'generation': '1786219700698109',
    'contentType': 'image/jpeg',
    'size': 91396,
  };

  setUp(ProfileMediaService.clearAllMediaAccessCaches);

  final serverNow = DateTime.utc(2026, 9, 18, 20, 45);

  /// Positive [deviceBehindServer] models a slow device clock, negative a
  /// fast one.
  Future<ProfileMediaAccess> accessWithSkew(Duration deviceBehindServer) {
    final deviceNow = serverNow.subtract(deviceBehindServer);
    final service = ProfileMediaService(
      auth: auth('viewer'),
      clock: () => deviceNow,
      invoker: (name, request) async {
        expect(name, 'getProfileMediaAccess');
        return productionGrant(serverNow);
      },
    );
    return service.resolveAccess(
      userId: 'target',
      kind: ProfileMediaKind.avatar,
    );
  }

  Future<Uri?> resolveWithSkew(Duration deviceBehindServer) =>
      accessWithSkew(deviceBehindServer).then((access) => access.uri);

  test('accepts a 90 s grant when the device clock matches the server', () async {
    expect(await resolveWithSkew(Duration.zero), isNotNull);
  });

  test(
    'accepts a 90 s grant when the device clock trails the server by 2 s',
    () async {
      // Reproduces the Redmi Note 8 Pro. Failed before the fix with
      // FormatException('Unsafe profile-media grant expiry.').
      expect(await resolveWithSkew(const Duration(seconds: 2)), isNotNull);
    },
  );

  test(
    'accepts a 90 s grant when the device clock trails the server by 10 s',
    () async {
      expect(await resolveWithSkew(const Duration(seconds: 10)), isNotNull);
    },
  );

  test(
    'accepts a 90 s grant when the device clock runs 2 s ahead of the server',
    () async {
      expect(await resolveWithSkew(const Duration(seconds: -2)), isNotNull);
    },
  );

  test(
    'accepts a 90 s grant when the device clock runs 2 min ahead of the server',
    () async {
      // The signed URL is judged by Google's clock, not the phone's, so a
      // device that thinks the grant already lapsed must not blank the avatar.
      final access = await accessWithSkew(const Duration(minutes: -2));
      expect(access.uri, isNotNull);
      expect(
        access.expiresAt.isAfter(serverNow.add(const Duration(minutes: 2))),
        isTrue,
        reason: 'a fast clock must not cache an already-expired grant, which '
            'would evict and re-request itself in a loop',
      );
    },
  );

  test('a slow device clock cannot stretch the cached lifetime', () async {
    final deviceNow = serverNow.subtract(const Duration(seconds: 10));
    final access = await accessWithSkew(const Duration(seconds: 10));
    expect(
      access.expiresAt.isAfter(
        deviceNow.add(ProfileMediaService.grantTtl),
      ),
      isFalse,
      reason: 'the cached lifetime is clamped to the server TTL on the device '
          'clock, so skew can never extend a grant',
    );
  });

  test('rejects a grant whose expiry is implausible on the device', () async {
    // 10 minutes of skew in either direction is no longer skew: the grant is
    // treated as malformed rather than silently trusted.
    await expectLater(
      resolveWithSkew(const Duration(minutes: -10)),
      throwsA(isA<FormatException>()),
    );
    ProfileMediaService.clearAllMediaAccessCaches();
    await expectLater(
      resolveWithSkew(const Duration(minutes: 10)),
      throwsA(isA<FormatException>()),
    );
  });
}
