import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yovoice/app/app.dart';
import 'package:yovoice/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Debug builds use the debug provider (prints a token to the console that
  // must be registered in Firebase Console > App Check > Apps > Manage
  // debug tokens — real device attestation doesn't work in
  // simulators/emulators). Release builds use real device attestation.
  // Cloud Functions still have enforceAppCheck: false, so this only starts
  // attaching tokens to requests — it doesn't reject anything yet.
  await FirebaseAppCheck.instance.activate(
    providerAndroid: kDebugMode
        ? AndroidDebugProvider()
        : AndroidPlayIntegrityProvider(),
    providerApple: kDebugMode
        ? AppleDebugProvider()
        : AppleAppAttestWithDeviceCheckFallbackProvider(),
  );

  runApp(const ProviderScope(child: YoVoiceApp()));
}
