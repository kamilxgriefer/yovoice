import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/features/permissions/data/permission_readiness_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('setup requests only requestable permissions in stable order', () async {
    final platform =
        _FakePermissionPlatform(<AppPermissionKind, AppPermissionAccess>{
          AppPermissionKind.notifications: AppPermissionAccess.granted,
          AppPermissionKind.microphone: AppPermissionAccess.denied,
          AppPermissionKind.camera: AppPermissionAccess.denied,
        });
    final store = _MemoryProgressStore();
    final service = PermissionReadinessService(
      platform: platform,
      progressStore: store,
    );

    final result = await service.prepareFromUserGesture(userId: 'user-1');

    expect(platform.requests, <AppPermissionKind>[
      AppPermissionKind.microphone,
      AppPermissionKind.camera,
    ]);
    expect(result[AppPermissionKind.notifications].isUsable, isTrue);
    expect(result[AppPermissionKind.microphone].isUsable, isTrue);
    expect(result[AppPermissionKind.camera].isUsable, isTrue);
    expect(store.outcomes['user-1'], PermissionSetupOutcome.completed);
    expect(await service.shouldOfferAutomatically('user-1'), isFalse);
  });

  test(
    'skip is account scoped and suppresses future automatic offers',
    () async {
      final store = _MemoryProgressStore();
      final service = PermissionReadinessService(
        platform: _FakePermissionPlatform(const {}),
        progressStore: store,
      );

      expect(await service.shouldOfferAutomatically('first'), isTrue);
      expect(await service.shouldOfferAutomatically('second'), isTrue);

      await service.skip('first');

      expect(await service.shouldOfferAutomatically('first'), isFalse);
      expect(await service.shouldOfferAutomatically('second'), isTrue);
      expect(store.outcomes['first'], PermissionSetupOutcome.skipped);
    },
  );

  test('a completed setup stays dismissed when access was denied', () async {
    final store = _MemoryProgressStore();
    final platform = _FakePermissionPlatform(
      {
        for (final permission in AppPermissionKind.values)
          permission: AppPermissionAccess.denied,
      },
      requestResults: {
        for (final permission in AppPermissionKind.values)
          permission: AppPermissionAccess.denied,
      },
    );
    final service = PermissionReadinessService(
      platform: platform,
      progressStore: store,
    );

    await service.prepareFromUserGesture(userId: 'denied-user');

    expect(platform.requests, AppPermissionKind.values);
    expect(store.outcomes['denied-user'], PermissionSetupOutcome.completed);
    expect(await service.shouldOfferAutomatically('denied-user'), isFalse);
  });

  test(
    'media status is check-only and explicit preparation requests media',
    () async {
      final platform =
          _FakePermissionPlatform(<AppPermissionKind, AppPermissionAccess>{
            AppPermissionKind.microphone: AppPermissionAccess.denied,
            AppPermissionKind.camera: AppPermissionAccess.denied,
          });
      final service = PermissionReadinessService(platform: platform);

      final before = await service.mediaSnapshot(includeCamera: true);
      expect(before[AppPermissionKind.microphone], AppPermissionAccess.denied);
      expect(platform.requests, isEmpty);

      final after = await service.prepareMediaFromUserGesture(
        includeCamera: true,
      );
      expect(platform.requests, <AppPermissionKind>[
        AppPermissionKind.microphone,
        AppPermissionKind.camera,
      ]);
      expect(after[AppPermissionKind.microphone].isUsable, isTrue);
      expect(after[AppPermissionKind.camera].isUsable, isTrue);
    },
  );

  test(
    'permanently denied permission opens Settings and is never requested',
    () async {
      final platform = _FakePermissionPlatform(
        <AppPermissionKind, AppPermissionAccess>{
          AppPermissionKind.microphone: AppPermissionAccess.permanentlyDenied,
        },
      );
      final service = PermissionReadinessService(platform: platform);

      final status = await service.requestFromUserGesture(
        AppPermissionKind.microphone,
      );

      expect(status, AppPermissionAccess.permanentlyDenied);
      expect(platform.requests, isEmpty);
      expect(platform.settingsOpenCount, 1);
    },
  );

  test(
    'media preparation does not stack camera over microphone Settings',
    () async {
      final platform =
          _FakePermissionPlatform(<AppPermissionKind, AppPermissionAccess>{
            AppPermissionKind.microphone: AppPermissionAccess.permanentlyDenied,
            AppPermissionKind.camera: AppPermissionAccess.denied,
          });
      final service = PermissionReadinessService(platform: platform);

      final snapshot = await service.prepareMediaFromUserGesture(
        includeCamera: true,
      );

      expect(platform.settingsOpenCount, 1);
      expect(platform.requests, isEmpty);
      expect(snapshot[AppPermissionKind.camera], AppPermissionAccess.denied);
    },
  );

  test('SharedPreferences store round-trips setup outcome by UID', () async {
    const store = SharedPreferencesPermissionSetupProgressStore();
    await store.writeOutcome(
      userId: 'user-a',
      version: 1,
      outcome: PermissionSetupOutcome.completed,
    );

    expect(
      await store.readOutcome(userId: 'user-a', version: 1),
      PermissionSetupOutcome.completed,
    );
    expect(await store.readOutcome(userId: 'user-b', version: 1), isNull);
  });
}

final class _FakePermissionPlatform implements AppPermissionPlatformGateway {
  _FakePermissionPlatform(
    Map<AppPermissionKind, AppPermissionAccess> statuses, {
    Map<AppPermissionKind, AppPermissionAccess> requestResults = const {},
  }) : statuses = Map.of(statuses),
       requestResults = Map.of(requestResults);

  final Map<AppPermissionKind, AppPermissionAccess> statuses;
  final Map<AppPermissionKind, AppPermissionAccess> requestResults;
  final List<AppPermissionKind> requests = <AppPermissionKind>[];
  int settingsOpenCount = 0;

  @override
  Future<bool> openSettings() async {
    settingsOpenCount += 1;
    return true;
  }

  @override
  Future<AppPermissionAccess> requestFromUserGesture(
    AppPermissionKind permission,
  ) async {
    requests.add(permission);
    final result = requestResults[permission] ?? AppPermissionAccess.granted;
    statuses[permission] = result;
    return result;
  }

  @override
  Future<AppPermissionAccess> status(AppPermissionKind permission) async =>
      statuses[permission] ?? AppPermissionAccess.unavailable;
}

final class _MemoryProgressStore implements PermissionSetupProgressStore {
  final Map<String, PermissionSetupOutcome> outcomes =
      <String, PermissionSetupOutcome>{};

  @override
  Future<PermissionSetupOutcome?> readOutcome({
    required String userId,
    required int version,
  }) async => outcomes[userId];

  @override
  Future<void> writeOutcome({
    required String userId,
    required int version,
    required PermissionSetupOutcome outcome,
  }) async {
    outcomes[userId] = outcome;
  }
}
