import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/firebase_options.dart';

void main() {
  group('Google Sign-In configuration', () {
    test('web OAuth uses the Firebase-managed redirect handler', () {
      expect(
        DefaultFirebaseOptions.web.authDomain,
        'yovoice-ec54a.firebaseapp.com',
      );
    });

    test('web login keeps the real Firebase popup flow wired', () {
      final source = File(
        'lib/features/auth/data/auth_service.dart',
      ).readAsStringSync();

      expect(source, contains('final googleProvider = GoogleAuthProvider();'));
      expect(
        source,
        contains(
          "googleProvider.setCustomParameters({'prompt': 'select_account'});",
        ),
      );
      expect(source, contains('_firebaseAuth.signInWithPopup(googleProvider)'));
    });

    test('Android config has package, release and web OAuth clients', () {
      final config =
          jsonDecode(
                File('android/app/google-services.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final clients = config['client'] as List<dynamic>;
      final appClient = clients.cast<Map<String, dynamic>>().singleWhere((
        client,
      ) {
        final info = client['client_info'] as Map<String, dynamic>;
        final androidInfo = info['android_client_info'] as Map<String, dynamic>;
        return androidInfo['package_name'] == 'app.yovoice';
      });
      final oauthClients = (appClient['oauth_client'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      expect(
        oauthClients.any((client) => client['client_type'] == 3),
        isTrue,
        reason:
            'google_sign_in_android reads its server client ID from the '
            'client_type 3 entry.',
      );
      expect(
        oauthClients.any((client) {
          final androidInfo = client['android_info'];
          return client['client_type'] == 1 &&
              androidInfo is Map<String, dynamic> &&
              androidInfo['package_name'] == 'app.yovoice' &&
              androidInfo['certificate_hash'] ==
                  'afe0bf45dc1336c2cc1d72ee554bd9aec7094485';
        }),
        isTrue,
        reason:
            'Release Google Sign-In must be registered for the upload '
            'keystore SHA-1 used by this repository.',
      );
    });

    test('iOS config and callback scheme describe the same OAuth client', () {
      final googleServiceInfo = File(
        'ios/Runner/GoogleService-Info.plist',
      ).readAsStringSync();
      final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
      final clientId = _plistString(googleServiceInfo, 'CLIENT_ID');
      final reversedClientId = _plistString(
        googleServiceInfo,
        'REVERSED_CLIENT_ID',
      );

      expect(_plistString(googleServiceInfo, 'BUNDLE_ID'), 'app.yovoice');
      expect(clientId, isNotEmpty);
      expect(
        reversedClientId,
        'com.googleusercontent.apps.'
        '${clientId.replaceFirst('.apps.googleusercontent.com', '')}',
      );
      expect(infoPlist, contains('<string>$reversedClientId</string>'));
      expect(
        _plistString(infoPlist, 'GIDClientID'),
        clientId,
        reason:
            'google_sign_in_ios requires GIDClientID in Runner/Info.plist '
            'when initialize() does not receive a clientId in Dart.',
      );
    });
  });
}

String _plistString(String plist, String key) {
  final match = RegExp(
    '<key>${RegExp.escape(key)}</key>\\s*<string>([^<]+)</string>',
  ).firstMatch(plist);

  expect(match, isNotNull, reason: '$key is missing from the plist.');
  return match!.group(1)!;
}
