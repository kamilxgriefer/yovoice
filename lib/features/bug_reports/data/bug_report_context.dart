import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/features/bug_reports/data/bug_report_route_tracker.dart';

/// The device context sent with a bug report — exactly the allowlist
/// `submitBugReportV1` accepts (functions/bug_reports/contract.js).
///
/// Everything here describes the APP and the DEVICE, never a person or a
/// conversation: no message text, no ids of chats, servers or other users, no
/// tokens, no e-mail address, no device identifiers. The reporter's uid is
/// added by the server from the signed-in session, never by the client.
@immutable
class BugReportContext {
  const BugReportContext({
    required this.appVersion,
    required this.buildNumber,
    required this.platform,
    required this.osVersion,
    required this.locale,
    required this.theme,
    required this.brightness,
    required this.route,
    required this.routeDepth,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.textScale,
  });

  final String appVersion;
  final String buildNumber;
  final String platform;
  final String osVersion;
  final String locale;
  final String theme;
  final String brightness;
  final String route;
  final int routeDepth;
  final int viewportWidth;
  final int viewportHeight;
  final double textScale;

  Map<String, Object> toJson() => <String, Object>{
    'appVersion': appVersion,
    'buildNumber': buildNumber,
    'platform': platform,
    'osVersion': osVersion,
    'locale': locale,
    'theme': theme,
    'brightness': brightness,
    'route': route,
    'routeDepth': routeDepth,
    'viewportWidth': viewportWidth,
    'viewportHeight': viewportHeight,
    'textScale': textScale,
  };
}

final RegExp _appVersion = RegExp(r'^[0-9A-Za-z.+_-]{1,32}$');
final RegExp _buildNumber = RegExp(r'^[0-9]{1,10}$');
final RegExp _locale = RegExp(r'^[A-Za-z]{2,3}(?:[-_][A-Za-z0-9]{2,8}){0,3}$');

String bugReportPlatformName() {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 'ios',
    TargetPlatform.android => 'android',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    TargetPlatform.linux => 'linux',
    TargetPlatform.fuchsia => 'fuchsia',
  };
}

/// Printable ASCII only, at most 120 characters (the server's bound).
@visibleForTesting
String sanitizeOsVersion(String raw) {
  final printable = raw.replaceAll(RegExp(r'[^\x20-\x7e]'), '').trim();
  if (printable.isEmpty) return 'unknown';
  return printable.length > 120 ? printable.substring(0, 120) : printable;
}

String _osVersion() {
  if (kIsWeb) return 'web';
  try {
    return sanitizeOsVersion(Platform.operatingSystemVersion);
  } catch (_) {
    return 'unknown';
  }
}

/// Collects the context for a report opened from [context].
///
/// [route] and [routeDepth] are captured by the caller BEFORE the reporter
/// itself is pushed, so they describe the screen the person was looking at.
Future<BugReportContext> collectBugReportContext(
  BuildContext context, {
  required String route,
  required int routeDepth,
  Future<PackageInfo> Function()? packageInfo,
}) async {
  final media = MediaQuery.of(context);
  final locale = Localizations.maybeLocaleOf(context)?.toLanguageTag() ?? 'und';
  final theme =
      AppPreferencesScope.maybeOf(context)?.value.theme.name ??
      AppThemePreference.system.name;
  final brightness = Theme.of(context).brightness.name;
  final textScale = media.textScaler.scale(1).clamp(0.5, 5.0).toDouble();
  var version = 'unknown';
  var build = '0';
  try {
    final info = await (packageInfo ?? PackageInfo.fromPlatform)();
    if (_appVersion.hasMatch(info.version)) version = info.version;
    if (_buildNumber.hasMatch(info.buildNumber)) build = info.buildNumber;
  } catch (_) {
    // Version is diagnostic; a missing plugin never blocks a report.
  }
  return BugReportContext(
    appVersion: version,
    buildNumber: build,
    platform: bugReportPlatformName(),
    osVersion: _osVersion(),
    locale: _locale.hasMatch(locale) ? locale : 'und',
    theme: theme,
    brightness: brightness,
    route: isSafeScreenName(route) ? route : 'unknown',
    routeDepth: routeDepth.clamp(0, 64),
    viewportWidth: media.size.width.round().clamp(0, 20000),
    viewportHeight: media.size.height.round().clamp(0, 20000),
    textScale: (textScale * 100).round() / 100,
  );
}
