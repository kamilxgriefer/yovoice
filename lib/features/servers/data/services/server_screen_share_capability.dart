import 'package:flutter/foundation.dart';

/// Why this device can or cannot start a screen share.
///
/// Receiving a share is never in question — it is an ordinary remote video
/// track and works everywhere (contract §3). This enum is only about the
/// publishing half.
enum ServerScreenShareReason {
  /// The browser's own `getDisplayMedia` picker. The only surface where the
  /// company template's share works today with no native work.
  browser,

  /// Android has no `FOREGROUND_SERVICE_MEDIA_PROJECTION` permission and no
  /// `mediaProjection` foreground service; iOS has no Broadcast Upload
  /// Extension target. Both are signing-affecting platform changes outside
  /// the Flutter layer.
  mobileNotBuilt,

  /// The desktop app has no verified capture path and no CI build behind it.
  /// It is refused rather than offered on a guess.
  desktopUnverified,
}

/// Contract decision D: one capability query answers "can this platform start
/// a share". Web returns true; everything else returns false with the reason,
/// so the company template can label the control truthfully instead of hiding
/// it or drawing one that fails inside the provider.
@immutable
class ServerScreenShareCapability {
  const ServerScreenShareCapability._(this.canStartShare, this.reason);

  final bool canStartShare;
  final ServerScreenShareReason reason;

  /// Test seam. Production code reads [serverScreenShareCapability].
  static const web = ServerScreenShareCapability._(
    true,
    ServerScreenShareReason.browser,
  );
  static const mobile = ServerScreenShareCapability._(
    false,
    ServerScreenShareReason.mobileNotBuilt,
  );
  static const desktop = ServerScreenShareCapability._(
    false,
    ServerScreenShareReason.desktopUnverified,
  );
}

/// The real query. [isWeb] and [platform] exist so a test can ask for another
/// device's answer without the answer itself ever being faked in production.
ServerScreenShareCapability serverScreenShareCapability({
  bool isWeb = kIsWeb,
  TargetPlatform? platform,
}) {
  if (isWeb) return ServerScreenShareCapability.web;
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS => ServerScreenShareCapability.mobile,
    _ => ServerScreenShareCapability.desktop,
  };
}
