import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_header.dart';
import 'package:yovoice/shared/widgets/profile/profile_banner.dart';
import 'package:yovoice/shared/widgets/profile/profile_photo_viewer.dart';

/// The banner ("zdjęcie w tle") had no fullscreen viewer anywhere in the app:
/// `ProfileBanner` rendered the image and nothing ever opened it. These tests
/// pin the viewer's contract — banner grants, the 16:9 frame the upload
/// pipeline actually stores, localized copy — and that the header's banner is
/// what opens it without stealing taps from the controls drawn over it.
void main() {
  setUp(ProfileMediaService.clearAllMediaAccessCaches);

  final pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2nKsAAAAASUVORK5CYII=',
  );

  Widget host(Widget child, {Locale locale = const Locale('pl')}) =>
      MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.darkTheme,
        home: Scaffold(body: child),
      );

  ProfileMediaService serviceWith(ProfileMediaCallableInvoker invoker) =>
      ProfileMediaService(
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'viewer'),
        ),
        invoker: invoker,
      );

  Map<Object?, Object?> availableGrant() => <Object?, Object?>{
    'schemaVersion': 1,
    'available': true,
    'expiresAtMillis': DateTime.now()
        .toUtc()
        .add(const Duration(seconds: 90))
        .millisecondsSinceEpoch,
    'url': 'https://storage.googleapis.com/test/banner?signature=short',
    'generation': '7',
    'contentType': 'image/png',
    'size': 4096,
  };

  Map<Object?, Object?> absentGrant() => <Object?, Object?>{
    'schemaVersion': 1,
    'available': false,
    'expiresAtMillis': DateTime.now()
        .toUtc()
        .add(const Duration(seconds: 90))
        .millisecondsSinceEpoch,
  };

  testWidgets('the banner viewer asks for a banner grant by uid and zooms', (
    tester,
  ) async {
    final requests = <Map<String, Object?>>[];
    await tester.pumpWidget(
      host(
        Center(
          child: ProfileBannerButton(
            userId: 'target-user',
            displayName: 'Maja',
            mediaRevision: DateTime.utc(2026, 9, 1),
            mediaService: serviceWith((callable, request) async {
              requests.add(request);
              return availableGrant();
            }),
            imageProvider: (_) => MemoryImage(pixel),
            child: const SizedBox(width: 200, height: 80),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Zdjęcie w tle: Maja'));
    await tester.pumpAndSettle();

    expect(requests, [
      {'userId': 'target-user', 'kind': 'banner'},
    ]);
    expect(
      requests.single.keys,
      unorderedEquals(['userId', 'kind']),
      reason: 'no durable or bearer media URL may enter the request',
    );
    expect(find.text('Zdjęcie w tle: Maja'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-photo-viewer-image')),
      findsOneWidget,
    );

    final frame = tester.widget<AspectRatio>(
      find.ancestor(
        of: find.byType(InteractiveViewer),
        matching: find.byType(AspectRatio),
      ),
    );
    expect(
      frame.aspectRatio,
      closeTo(16 / 9, 0.0001),
      reason: 'the viewer frame must match ProfileImageRules.banner',
    );

    await tester.tap(find.byTooltip('Zamknij zdjęcie w tle'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('a profile with no banner says so instead of showing a letter', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Center(
          child: ProfileBannerButton(
            userId: 'target-user',
            displayName: 'Maja',
            mediaService: serviceWith((_, _) async => absentGrant()),
            child: const SizedBox(width: 200, height: 80),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Zdjęcie w tle: Maja'));
    await tester.pumpAndSettle();

    expect(find.text('Brak zdjęcia w tle'), findsOneWidget);
    expect(find.text('Brak zdjęcia profilowego'), findsNothing);
  });

  testWidgets('the header banner opens the viewer without stealing controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var edits = 0;
    await tester.pumpWidget(
      host(
        ListView(
          children: [
            ProfileHeader(
              profile: _ownerProfile,
              onEdit: () => edits += 1,
              mediaService: serviceWith((_, _) async => absentGrant()),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The Edit control sits above the banner band in the same Stack; it must
    // keep its own tap.
    await tester.tap(find.byTooltip('Edytuj profil'));
    await tester.pumpAndSettle();
    expect(edits, 1);
    expect(find.text('Zdjęcie w tle: Ada Lovelace'), findsNothing);

    await tester.tap(find.byType(ProfileBannerButton));
    await tester.pumpAndSettle();
    expect(find.text('Zdjęcie w tle: Ada Lovelace'), findsOneWidget);
  });

  testWidgets('the name plate never falls through to the banner viewer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(
        ListView(
          children: [
            ProfileHeader(
              profile: _ownerProfile,
              onEdit: () {},
              mediaService: serviceWith((_, _) async => absentGrant()),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final plate = tester.getRect(
      find.byKey(const Key('profile-header-name-plate')),
    );
    final banner = tester.getRect(find.byType(ProfileBannerButton));
    // The plate deliberately rides over the banner's lower edge. That overlap
    // is what makes a fall-through possible at all, so pin it: if the header
    // ever stops overlapping, this test stops proving anything.
    expect(
      plate.top,
      lessThan(banner.bottom),
      reason: 'the name plate must still overlap the banner band',
    );

    // On the plate's own surface, clear of every glyph, and inside the
    // banner's rectangle: what the user sees at this point is the name plate,
    // so nothing here may open the banner. `BoxDecoration.hitTest` is what
    // makes the plate answer for itself; a plate rebuilt without its own
    // decoration would start leaking taps to the banner underneath.
    final onPlateOverBanner = plate.topRight + const Offset(-14, 8);
    expect(
      banner.contains(onPlateOverBanner),
      isTrue,
      reason:
          'the probe point must really be over the banner to prove anything',
    );

    await tester.tapAt(onPlateOverBanner);
    await tester.pumpAndSettle();

    expect(find.text('Zdjęcie w tle: Ada Lovelace'), findsNothing);
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('a nameless profile is named the same way by the launcher and '
      'by the frame it opens', (tester) async {
    // `UserProfile.fromFirestore` only substitutes a name when the field is
    // missing, so a legacy document carrying `displayName: ''` reaches the UI
    // with an empty name. The dialog has always resolved that to "Użytkownik
    // YO Voice"; the launchers interpolated the raw value, so the button
    // announced a dangling "Zdjęcie w tle:" with nothing after the colon.
    await tester.pumpWidget(
      host(
        Center(
          child: ProfileBannerButton(
            userId: 'target-user',
            displayName: '   ',
            mediaService: serviceWith((_, _) async => absentGrant()),
            child: const SizedBox(width: 200, height: 80),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Zdjęcie w tle: Użytkownik YO Voice'),
      findsOneWidget,
      reason: 'a screen reader must be given a name, not a bare colon',
    );
    expect(
      find.byTooltip('Powiększ zdjęcie w tle: Użytkownik YO Voice'),
      findsOneWidget,
    );

    await tester.tap(find.byType(ProfileBannerButton));
    await tester.pumpAndSettle();

    // The launcher and the dialog it opened must agree: one photo, one name.
    expect(find.text('Zdjęcie w tle: Użytkownik YO Voice'), findsOneWidget);
    expect(find.text('Zdjęcie w tle: '), findsNothing);
  });

  // The banner fallback paints `kProfileBannerFallbackGradient` — a fixed
  // dark gradient — in BOTH appearances, so its foreground cannot come from
  // the theme palette. In Pearl it did, and the copy read 1.54:1 against the
  // gradient's brightest stop.
  group('the banner fallback is legible on its own fixed-dark backdrop', () {
    double relativeLuminance(Color color) {
      double channel(double value) => value <= 0.03928
          ? value / 12.92
          : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * channel(color.r) +
          0.7152 * channel(color.g) +
          0.0722 * channel(color.b);
    }

    double contrast(Color a, Color b) {
      final la = relativeLuminance(a);
      final lb = relativeLuminance(b);
      final hi = math.max(la, lb);
      final lo = math.min(la, lb);
      return (hi + 0.05) / (lo + 0.05);
    }

    final stops = kProfileBannerFallbackGradient.colors;

    Future<void> openBannerFallback(
      WidgetTester tester, {
      required ThemeData theme,
      required bool failing,
    }) async {
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
          theme: theme,
          home: Scaffold(
            body: Center(
              child: ProfileBannerButton(
                userId: 'target-user',
                displayName: 'Maja',
                mediaService: serviceWith((_, _) async {
                  if (failing) throw StateError('network down');
                  return absentGrant();
                }),
                child: const SizedBox(width: 200, height: 80),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Zdjęcie w tle: Maja'));
      await tester.pumpAndSettle();
    }

    for (final (name, theme) in <(String, ThemeData)>[
      ('Pearl', AppTheme.lightTheme),
      ('Dark', AppTheme.darkTheme),
    ]) {
      testWidgets('$name: the empty-state copy and glyph clear WCAG on every '
          'gradient stop', (tester) async {
        await openBannerFallback(tester, theme: theme, failing: false);

        final message = tester.widget<Text>(find.text('Brak zdjęcia w tle'));
        final messageColor = message.style!.color!;
        final iconColor = tester
            .widget<Icon>(find.byIcon(Icons.image_outlined))
            .color!;

        for (final stop in stops) {
          expect(
            contrast(messageColor, stop),
            greaterThanOrEqualTo(4.5),
            reason:
                '$name: 15 px w700 is not WCAG large text, so 1.4.3 needs '
                '4.5:1 on stop $stop',
          );
          expect(
            contrast(iconColor, stop),
            greaterThanOrEqualTo(3),
            reason: '$name: 1.4.11 needs 3:1 for the glyph on stop $stop',
          );
        }
      });

      testWidgets('$name: the failed-state retry label clears WCAG on every '
          'gradient stop', (tester) async {
        await openBannerFallback(tester, theme: theme, failing: true);

        expect(find.text('Nie udało się wczytać zdjęcia'), findsOneWidget);
        final retry = tester.widget<TextButton>(
          find.byKey(const ValueKey('profile-photo-viewer-retry')),
        );
        final foreground = retry.style!.foregroundColor!.resolve(
          <WidgetState>{},
        )!;
        for (final stop in stops) {
          expect(
            contrast(foreground, stop),
            greaterThanOrEqualTo(4.5),
            reason: '$name: the only recovery control must be readable',
          );
        }
      });
    }
  });

  // The banner's content is boxed at 16:9 — ~157 dp tall at 320 dp. At 200 %
  // text the icon, the wrapped message and the retry button ask for far more
  // than that: the column overflowed and clipped the retry button away, so a
  // transient grant failure became a dead end.
  group('the banner fallback survives 320 dp at 200 % text', () {
    for (final failing in <bool>[false, true]) {
      final state = failing ? 'failed' : 'absent';
      testWidgets(
        '$state: no overflow, and the retry control stays reachable',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          var calls = 0;
          await tester.pumpWidget(
            MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 640),
                textScaler: TextScaler.linear(2),
              ),
              child: host(
                Center(
                  child: ProfileBannerButton(
                    userId: 'target-user',
                    displayName: 'Maja',
                    mediaService: serviceWith((_, _) async {
                      calls += 1;
                      if (failing && calls == 1) {
                        throw StateError('network down');
                      }
                      return absentGrant();
                    }),
                    child: const SizedBox(width: 200, height: 80),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.bySemanticsLabel('Zdjęcie w tle: Maja'));
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason: 'a RenderFlex overflow paints a hazard stripe over content',
          );

          if (failing) {
            final retry = find.byKey(
              const ValueKey('profile-photo-viewer-retry'),
            );
            expect(retry, findsOneWidget);
            // Present is not enough: a clipped button is still in the tree.
            expect(
              tester.getRect(retry).isEmpty,
              isFalse,
              reason: 'the retry control must occupy real space',
            );

            // This case only proves something while the content really does
            // exceed the 16:9 box. Measured here: a 288x162 dp viewport holding
            // a 387 dp column, with the retry button ~150 dp below the fold.
            final viewport = tester.getRect(find.byType(SingleChildScrollView));
            final column = tester.getRect(
              find.byKey(const ValueKey('profile-photo-viewer-error')),
            );
            expect(
              column.height,
              greaterThan(viewport.height),
              reason:
                  'at this size the message must overflow the banner frame, '
                  'otherwise the regression cannot reproduce',
            );

            // Reachable, not merely present: the scroll view is what makes the
            // viewer's only recovery affordance available at all. Before the
            // fix it was clipped away under a RenderFlex overflow stripe and no
            // gesture could reach it.
            await tester.ensureVisible(retry);
            await tester.pumpAndSettle();
            expect(
              viewport.contains(tester.getRect(retry).center),
              isTrue,
              reason: 'scrolling must bring the retry control into the frame',
            );
            await tester.tap(retry, warnIfMissed: true);
            await tester.pumpAndSettle();
            expect(
              calls,
              2,
              reason: 'the tap must actually reach the retry control',
            );
          } else {
            expect(find.text('Brak zdjęcia w tle'), findsOneWidget);
          }
        },
      );
    }
  });

  testWidgets('the avatar launcher resolves a missing name the same way', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Center(
          child: ProfilePhotoButton(
            userId: 'target-user',
            displayName: '',
            mediaService: serviceWith((_, _) async => absentGrant()),
            child: const SizedBox(width: 60, height: 60),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Zdjęcie profilowe: Użytkownik YO Voice'),
      findsOneWidget,
    );

    await tester.tap(find.byType(ProfilePhotoButton));
    await tester.pumpAndSettle();

    expect(find.text('Zdjęcie profilowe: Użytkownik YO Voice'), findsOneWidget);
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
