import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_header.dart';
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

  Widget host(Widget child, {Locale locale = const Locale('pl')}) => MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: AppTheme.darkTheme,
    home: Scaffold(body: Center(child: child)),
  );

  ProfileMediaService serviceWith(ProfileMediaCallableInvoker invoker) =>
      ProfileMediaService(
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'viewer')),
        invoker: invoker,
      );

  Map<Object?, Object?> absentGrant() => <Object?, Object?>{
    'schemaVersion': 1,
    'available': false,
    'expiresAtMillis': DateTime.now()
        .toUtc()
        .add(const Duration(seconds: 90))
        .millisecondsSinceEpoch,
  };

  Map<Object?, Object?> availableGrant() => <Object?, Object?>{
    'schemaVersion': 1,
    'available': true,
    'expiresAtMillis': DateTime.now()
        .toUtc()
        .add(const Duration(seconds: 90))
        .millisecondsSinceEpoch,
    'url': 'https://storage.googleapis.com/test/avatar?signature=short',
    'generation': '42',
    'contentType': 'image/png',
    'size': 256,
  };

  final pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2nKsAAAAASUVORK5CYII=',
  );

  Future<void> openViewer(
    WidgetTester tester, {
    required ProfileMediaService service,
    Locale locale = const Locale('pl'),
  }) async {
    await tester.pumpWidget(
      host(
        ProfilePhotoButton(
          userId: 'target-user',
          displayName: 'Maja',
          mediaService: service,
          imageProvider: (_) => MemoryImage(pixel),
          child: const CircleAvatar(child: Text('M')),
        ),
        locale: locale,
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(ProfilePhotoButton));
    await tester.pump();
  }

  testWidgets('an account with no photo gets a named empty state, not a letter', (
    tester,
  ) async {
    await openViewer(tester, service: serviceWith((_, _) async => absentGrant()));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('profile-photo-viewer-empty')),
      findsOneWidget,
    );
    expect(find.text('Brak zdjęcia profilowego'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-photo-viewer-image')),
      findsNothing,
    );
  });

  testWidgets('the empty state is localized in English too', (tester) async {
    await openViewer(
      tester,
      service: serviceWith((_, _) async => absentGrant()),
      locale: const Locale('en'),
    );
    await tester.pumpAndSettle();

    expect(find.text('No profile photo yet'), findsOneWidget);
  });

  testWidgets('a pending grant shows progress, never "no photo"', (
    tester,
  ) async {
    final gate = Completer<Map<Object?, Object?>>();
    await openViewer(tester, service: serviceWith((_, _) => gate.future));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('profile-photo-viewer-loading')),
      findsOneWidget,
    );
    expect(find.text('Brak zdjęcia profilowego'), findsNothing);

    gate.complete(availableGrant());
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('profile-photo-viewer-image')),
      findsOneWidget,
    );
  });

  testWidgets('a failed grant offers a retry that re-requests the photo', (
    tester,
  ) async {
    var calls = 0;
    await openViewer(
      tester,
      service: serviceWith((_, _) async {
        calls += 1;
        if (calls == 1) throw StateError('network down');
        return availableGrant();
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nie udało się wczytać zdjęcia'), findsOneWidget);
    expect(
      find.text('Brak zdjęcia profilowego'),
      findsNothing,
      reason: 'a failed grant must not be mislabelled as an empty profile',
    );

    await tester.tap(find.byKey(const ValueKey('profile-photo-viewer-retry')));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(
      find.byKey(const ValueKey('profile-photo-viewer-image')),
      findsOneWidget,
    );
  });

  testWidgets('the owner can open their own profile photo from the header', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(
        ProfileHeader(
          profile: _ownerProfile,
          onEdit: () {},
          mediaService: serviceWith((_, _) async => absentGrant()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profile-header-avatar')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('profile-photo-viewer-close')),
      findsOneWidget,
    );
    expect(find.text('Zdjęcie profilowe: Ada Lovelace'), findsOneWidget);
  });
}

final _ownerProfile = UserProfile(
  uid: 'u1',
  email: 'ada@yovoice.app',
  displayName: 'Ada Lovelace',
  username: 'ada',
  bio: 'bio',
  country: '',
  nativeLanguage: '',
  spokenLanguages: const [],
  learningLanguages: const [],
  photoUrl: null,
  bannerUrl: null,
  website: '',
  accountType: AccountType.personal,
  friendCount: 0,
  followerCount: 0,
  followingCount: 0,
  roomCount: 0,
  communityCount: 0,
  voiceMinutes: 0,
  messageCount: 0,
  activeDays: 0,
  momentCount: 0,
  reactionCount: 0,
  hostMinutes: 0,
  selectedTitleId: null,
  unlockedTitleIds: const [],
  unlockedTitleTimestamps: const {},
  createdAt: DateTime(2026),
);
