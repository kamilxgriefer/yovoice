import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yovoice/app/app.dart';
import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';
import 'package:yovoice/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Seeds LiveKit's audio-session policy before WebRTC builds its audio
  // device module, so a backgrounded iOS call keeps its session active.
  try {
    await LiveKitClient.initialize();
  } catch (error) {
    debugPrint('LiveKit initialization skipped: $error');
  }
  _installCrashReporting();
  await _activateAppCheck();
  _registerBackgroundMessageHandler();

  try {
    await AppPreferencesController.instance.load();
  } catch (error, stackTrace) {
    // A damaged browser/device preferences store must not block sign-in.
    // The controller keeps its safe system defaults for this launch.
    debugPrint('App preferences could not be loaded: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  runApp(const ProviderScope(child: YoVoiceApp()));
}

// Crashlytics is the production crash/error channel — before this, a
// crash in the field left no trace anywhere. Not supported on web (the
// plugin throws), so web keeps the console as its error surface. Debug
// builds don't report: local development crashes are noise, and the
// developer is already looking at the console.
void _installCrashReporting() {
  if (kIsWeb) return;

  try {
    final crashlytics = FirebaseCrashlytics.instance;
    crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);

    // Uncaught Flutter framework errors (build/layout/gesture).
    FlutterError.onError = crashlytics.recordFlutterFatalError;
    // Uncaught async/platform errors that never touch the framework.
    PlatformDispatcher.instance.onError = (error, stack) {
      crashlytics.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (error) {
    // Same posture as App Check below: observability must never be the
    // thing that takes the app down.
    debugPrint('Crashlytics setup failed, continuing without it: $error');
  }
}

// Must be registered before runApp() per FirebaseMessaging's own
// requirement, independent of whether a user is signed in yet — a token
// only gets minted (and background messages only start arriving) once
// PushNotificationService.initialize() runs post-login, but the handler
// itself has to exist from cold start or the plugin errors on Android.
void _registerBackgroundMessageHandler() {
  if (kIsWeb) return;
  try {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (error) {
    debugPrint('FCM background handler registration failed: $error');
  }
}

// Debug builds use the debug provider (prints a token to the console that
// must be registered in Firebase Console > App Check > Apps > Manage debug
// tokens — real device attestation doesn't work in simulators/emulators).
// Release builds use real device attestation. Cloud Functions still have
// enforceAppCheck: false, so this only starts attaching tokens to
// requests — it doesn't reject anything yet.
//
// Web debug builds use Firebase's debug provider. A release web build only
// activates App Check when its public reCAPTCHA v3 site key is supplied with
// `--dart-define=YOVOICE_WEB_RECAPTCHA_SITE_KEY=...`; that key must also be
// registered for the web app in Firebase Console. Keeping the release branch
// explicit prevents the old null-provider startup crash while giving the
// deployment pipeline a concrete, testable prerequisite before server-side
// enforcement is enabled. The catch remains defense in depth: attestation
// outages must not turn the entire client into a blank page during rollout.
Future<void> _activateAppCheck() async {
  try {
    if (kIsWeb) {
      if (kDebugMode) {
        await FirebaseAppCheck.instance.activate(
          providerWeb: WebDebugProvider(),
        );
        return;
      }
      const siteKey = String.fromEnvironment('YOVOICE_WEB_RECAPTCHA_SITE_KEY');
      if (siteKey.isEmpty) {
        debugPrint(
          'Web App Check is not configured for this release build. '
          'Server enforcement must remain disabled.',
        );
        return;
      }
      await FirebaseAppCheck.instance.activate(
        providerWeb: ReCaptchaV3Provider(siteKey),
      );
      return;
    }

    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? AndroidDebugProvider()
          : AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode
          ? AppleDebugProvider()
          : AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
  } catch (error, stackTrace) {
    debugPrint('App Check activation failed, continuing without it: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}
