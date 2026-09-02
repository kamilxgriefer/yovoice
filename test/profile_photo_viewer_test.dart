import 'dart:convert';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/shared/widgets/profile/profile_photo_viewer.dart';

void main() {
  setUp(ProfileMediaService.clearAllMediaAccessCaches);

  testWidgets(
    'profile-photo viewer resolves by uid, is zoomable and closes accessibly',
    (tester) async {
      final requests = <Map<String, Object?>>[];
      final service = ProfileMediaService(
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'viewer'),
        ),
        invoker: (callable, request) async {
          expect(callable, 'getProfileMediaAccess');
          requests.add(request);
          return <Object?, Object?>{
            'schemaVersion': 1,
            'available': true,
            'expiresAtMillis': DateTime.now()
                .toUtc()
                .add(const Duration(seconds: 80))
                .millisecondsSinceEpoch,
            'url': 'https://storage.googleapis.com/test/avatar?signature=short',
            'generation': '42',
            'contentType': 'image/png',
            'size': 256,
          };
        },
      );
      final pixel = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2nKsAAAAASUVORK5CYII=',
      );
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('pl'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: ProfilePhotoButton(
                userId: 'target-user',
                displayName: 'Maja',
                mediaRevision: DateTime.utc(2026, 9, 1),
                mediaService: service,
                imageProvider: (_) => MemoryImage(pixel),
                child: const CircleAvatar(child: Text('M')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final launcher = find.bySemanticsLabel('Zdjęcie profilowe: Maja');
      expect(launcher, findsOneWidget);
      await tester.tap(launcher);
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(
        find.byKey(const ValueKey('profile-photo-viewer-image')),
        findsOneWidget,
      );
      expect(requests, [
        {'userId': 'target-user', 'kind': 'avatar'},
      ]);
      expect(
        requests.single.keys,
        unorderedEquals(['userId', 'kind']),
        reason: 'no durable or bearer media URL may enter the request',
      );

      final close = find.byTooltip('Zamknij zdjęcie profilowe');
      expect(close, findsOneWidget);
      expect(tester.getSize(close), const Size(48, 48));
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
      semantics.dispose();
    },
  );
}
