import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';

enum AppPermissionKind { notifications, microphone, camera }

/// App-neutral view of the operating system's permission state.
///
/// The status is always re-read from the platform before a decision. Local
/// preferences only remember whether the optional setup has already been
/// shown; they never stand in for an OS grant.
enum AppPermissionAccess {
  granted,
  limited,
  denied,
  permanentlyDenied,
  restricted,
  unavailable,
}

extension AppPermissionAccessState on AppPermissionAccess {
  bool get isUsable =>
      this == AppPermissionAccess.granted ||
      this == AppPermissionAccess.limited;

  bool get canRequest => this == AppPermissionAccess.denied;

  bool get requiresSettings => this == AppPermissionAccess.permanentlyDenied;
}

final class PermissionReadinessSnapshot {
  PermissionReadinessSnapshot(Map<AppPermissionKind, AppPermissionAccess> value)
    : statuses = Map<AppPermissionKind, AppPermissionAccess>.unmodifiable(
        value,
      );

  final Map<AppPermissionKind, AppPermissionAccess> statuses;

  AppPermissionAccess operator [](AppPermissionKind permission) =>
      statuses[permission] ?? AppPermissionAccess.unavailable;

  bool get hasSettingsOnlyPermission =>
      statuses.values.any((status) => status.requiresSettings);
}

enum PermissionSetupOutcome { skipped, completed }

abstract interface class PermissionSetupProgressStore {
  Future<PermissionSetupOutcome?> readOutcome({
    required String userId,
    required int version,
  });

  Future<void> writeOutcome({
    required String userId,
    required int version,
    required PermissionSetupOutcome outcome,
  });
}

final class SharedPreferencesPermissionSetupProgressStore
    implements PermissionSetupProgressStore {
  const SharedPreferencesPermissionSetupProgressStore();

  static String _key(String userId, int version) =>
      'onboarding.permission_setup.v$version.$userId.outcome';

  @override
  Future<PermissionSetupOutcome?> readOutcome({
    required String userId,
    required int version,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    return switch (preferences.getString(_key(userId, version))) {
      'skipped' => PermissionSetupOutcome.skipped,
      'completed' => PermissionSetupOutcome.completed,
      _ => null,
    };
  }

  @override
  Future<void> writeOutcome({
    required String userId,
    required int version,
    required PermissionSetupOutcome outcome,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _key(userId, version),
      outcome.name,
    );
    if (!saved) throw StateError('Could not persist permission setup.');
  }
}

abstract interface class AppPermissionPlatformGateway {
  Future<AppPermissionAccess> status(AppPermissionKind permission);

  /// Must only be called from an explicit user gesture.
  Future<AppPermissionAccess> requestFromUserGesture(
    AppPermissionKind permission,
  );

  Future<bool> openSettings();
}

final class PermissionHandlerPlatformGateway
    implements AppPermissionPlatformGateway {
  PermissionHandlerPlatformGateway({PushNotificationService? push})
    : _push = push;

  final PushNotificationService? _push;

  @override
  Future<AppPermissionAccess> status(AppPermissionKind permission) async {
    if (permission == AppPermissionKind.notifications &&
        kIsWeb &&
        !PushNotificationService.webPushConfigured) {
      return AppPermissionAccess.unavailable;
    }
    try {
      return _mapStatus(await _permission(permission).status);
    } catch (_) {
      // Safari versions without the Permissions API can still ask for media
      // from a user gesture. Treat an unreadable web status as requestable,
      // not as a fabricated grant or a permanent denial.
      return kIsWeb
          ? AppPermissionAccess.denied
          : AppPermissionAccess.unavailable;
    }
  }

  @override
  Future<AppPermissionAccess> requestFromUserGesture(
    AppPermissionKind permission,
  ) async {
    final current = await status(permission);
    if (current.isUsable || !current.canRequest) return current;

    try {
      final requested = _mapStatus(await _permission(permission).request());
      if (permission == AppPermissionKind.notifications && requested.isUsable) {
        // Permission Handler owns the explicit system dialog. Push setup then
        // registers the token/listeners without asking for permission again.
        await (_push ?? PushNotificationService.instance)
            .activateAfterNotificationPermission();
      }
      return requested;
    } catch (_) {
      return AppPermissionAccess.unavailable;
    }
  }

  @override
  Future<bool> openSettings() => openAppSettings();

  static Permission _permission(AppPermissionKind permission) =>
      switch (permission) {
        AppPermissionKind.notifications => Permission.notification,
        AppPermissionKind.microphone => Permission.microphone,
        AppPermissionKind.camera => Permission.camera,
      };

  static AppPermissionAccess _mapStatus(PermissionStatus status) =>
      switch (status) {
        PermissionStatus.granted => AppPermissionAccess.granted,
        PermissionStatus.limited ||
        PermissionStatus.provisional => AppPermissionAccess.limited,
        PermissionStatus.denied => AppPermissionAccess.denied,
        PermissionStatus.permanentlyDenied =>
          AppPermissionAccess.permanentlyDenied,
        PermissionStatus.restricted => AppPermissionAccess.restricted,
      };
}

/// One intentional setup flow shared by onboarding, Settings and voice calls.
///
/// Automatic presentation is account-scoped and happens at most once for this
/// version. Calls use [status] only; system dialogs are reached exclusively
/// through [prepareFromUserGesture] or [requestFromUserGesture].
final class PermissionReadinessService {
  PermissionReadinessService({
    AppPermissionPlatformGateway? platform,
    PermissionSetupProgressStore? progressStore,
  }) : _platform = platform ?? PermissionHandlerPlatformGateway(),
       _progressStore =
           progressStore ??
           const SharedPreferencesPermissionSetupProgressStore();

  static final PermissionReadinessService instance =
      PermissionReadinessService();

  static const int currentSetupVersion = 1;

  final AppPermissionPlatformGateway _platform;
  final PermissionSetupProgressStore _progressStore;
  final Set<String> _dismissedThisSession = <String>{};

  Future<PermissionReadinessSnapshot> snapshot({
    Iterable<AppPermissionKind> permissions = AppPermissionKind.values,
  }) async {
    final kinds = permissions.toList(growable: false);
    final results = await Future.wait(kinds.map(_platform.status));
    return PermissionReadinessSnapshot(<AppPermissionKind, AppPermissionAccess>{
      for (var index = 0; index < kinds.length; index++)
        kinds[index]: results[index],
    });
  }

  Future<AppPermissionAccess> status(AppPermissionKind permission) =>
      _platform.status(permission);

  Future<bool> shouldOfferAutomatically(String userId) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return false;
    if (_dismissedThisSession.contains(normalizedUserId)) return false;
    try {
      return await _progressStore.readOutcome(
            userId: normalizedUserId,
            version: currentSetupVersion,
          ) ==
          null;
    } catch (error) {
      // A broken local store must never turn a permission sheet into a modal
      // shown on every launch.
      debugPrint('Permission setup progress could not be read: $error');
      return false;
    }
  }

  /// Sequentially checks and, where still requestable, requests all three
  /// capabilities. The caller must invoke this directly from a button press.
  Future<PermissionReadinessSnapshot> prepareFromUserGesture({
    required String userId,
  }) async {
    final statuses = <AppPermissionKind, AppPermissionAccess>{};
    for (final permission in AppPermissionKind.values) {
      final current = await _platform.status(permission);
      statuses[permission] = current.canRequest
          ? await _platform.requestFromUserGesture(permission)
          : current;
    }
    await _writeOutcome(userId, PermissionSetupOutcome.completed);
    return PermissionReadinessSnapshot(statuses);
  }

  /// Explicit single-capability retry for call controls and Settings.
  Future<AppPermissionAccess> requestFromUserGesture(
    AppPermissionKind permission,
  ) async {
    final current = await _platform.status(permission);
    if (current.requiresSettings) {
      await _platform.openSettings();
      return current;
    }
    return current.canRequest
        ? _platform.requestFromUserGesture(permission)
        : current;
  }

  Future<PermissionReadinessSnapshot> mediaSnapshot({
    required bool includeCamera,
  }) => snapshot(
    permissions: <AppPermissionKind>[
      AppPermissionKind.microphone,
      if (includeCamera) AppPermissionKind.camera,
    ],
  );

  /// Explicit call/prejoin action. Unlike the onboarding sequence this does
  /// not mark the full three-permission setup complete.
  Future<PermissionReadinessSnapshot> prepareMediaFromUserGesture({
    required bool includeCamera,
  }) async {
    final statuses = <AppPermissionKind, AppPermissionAccess>{};
    final microphone = await requestFromUserGesture(
      AppPermissionKind.microphone,
    );
    statuses[AppPermissionKind.microphone] = microphone;
    if (includeCamera) {
      // A call cannot proceed without audio. If the microphone remains off,
      // do not stack a camera dialog over a denial or over device Settings.
      statuses[AppPermissionKind.camera] = microphone.isUsable
          ? await requestFromUserGesture(AppPermissionKind.camera)
          : await _platform.status(AppPermissionKind.camera);
    }
    return PermissionReadinessSnapshot(statuses);
  }

  Future<void> skip(String userId) =>
      _writeOutcome(userId, PermissionSetupOutcome.skipped);

  Future<bool> openSettings() => _platform.openSettings();

  Future<void> _writeOutcome(
    String userId,
    PermissionSetupOutcome outcome,
  ) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return;
    _dismissedThisSession.add(normalizedUserId);
    await _progressStore.writeOutcome(
      userId: normalizedUserId,
      version: currentSetupVersion,
      outcome: outcome,
    );
  }
}
