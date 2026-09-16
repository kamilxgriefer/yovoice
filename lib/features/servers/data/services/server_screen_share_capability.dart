import 'package:flutter/foundation.dart';

/// Why this device can or cannot start a screen share.
///
/// Receiving a share is never in question — it is an ordinary remote video
/// track and works everywhere (contract §3). This enum is only about the
/// publishing half.
enum ServerScreenShareReason {
  /// The browser's own `getDisplayMedia` picker.
  browser,

  /// iOS can publish the YO Voice app surface through ReplayKit. Capturing
  /// other applications still needs a separately signed Broadcast Upload
  /// Extension, which this target intentionally does not claim to have.
  iosInApp,

  /// Android uses the platform MediaProjection consent dialog and YO Voice's
  /// foreground media service before LiveKit starts capture.
  androidMediaProjection,

  /// The desktop app has no verified capture path and no CI build behind it.
  /// It is refused rather than offered on a guess.
  desktopUnverified,
}

/// One capability query answers "can this platform start a share". Browser,
/// iOS in-app capture and Android MediaProjection are supported. Unverified
/// desktop targets stay disabled so the UI never offers a capture that has no
/// tested platform path.
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
  @Deprecated('Use ios or android so the capture contract stays explicit.')
  static const mobile = ServerScreenShareCapability._(
    true,
    ServerScreenShareReason.iosInApp,
  );
  static const android = ServerScreenShareCapability._(
    true,
    ServerScreenShareReason.androidMediaProjection,
  );
  static const ios = ServerScreenShareCapability._(
    true,
    ServerScreenShareReason.iosInApp,
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
    TargetPlatform.android => ServerScreenShareCapability.android,
    TargetPlatform.iOS => ServerScreenShareCapability.ios,
    _ => ServerScreenShareCapability.desktop,
  };
}
