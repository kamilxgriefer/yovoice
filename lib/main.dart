import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yovoice/app/app.dart';
import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';
import 'package:yovoice/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  _installCrashReporting();
  await _activateAppCheck();
  _registerBackgroundMessageHandler();

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
// Web is deliberately skipped: activate() requires a providerWeb
// (ReCaptchaV3Provider) backed by a reCAPTCHA site key registered through
// Google's reCAPTCHA admin console + Firebase Console's App Check settings
// — a real external-service registration step, not something to fake here.
// Without it, the web plugin's activate() throws (confirmed via `flutter
// run -d chrome`: "TypeError: Cannot read properties of null (reading
// 'initialize')" deep in firebase_app_check_web), and since that call was
// unguarded, the exception was escaping main() entirely and runApp() never
// executed — the actual cause of the blank white page in production, not a
// build, deploy, or asset problem. The try/catch below is additional
// defense in depth so App Check can never again take the whole app down on
// any platform if it fails for some other reason (e.g. attestation being
// briefly unavailable) — enforcement is off, so a missing token is not
// something worth blocking startup over.
Future<void> _activateAppCheck() async {
  if (kIsWeb) return;

  try {
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
