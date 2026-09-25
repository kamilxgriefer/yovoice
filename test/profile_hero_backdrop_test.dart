import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_header.dart';
import 'package:yovoice/shared/widgets/profile/profile_banner.dart';
import 'package:yovoice/shared/widgets/profile/profile_hero_backdrop.dart';
import 'package:yovoice/shared/widgets/profile/profile_photo_viewer.dart';

/// Pins the full-bleed profile hero: the banner is the background of the
/// whole header (edge to edge, from y = 0 under the status bar), the photo's
/// scrim, blur and light status-bar region exist only while the photo is on
/// screen, and every state keeps one height so nothing jumps.
UserProfile _profile() => UserProfile(
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

final _pixel = MemoryImage(
  img.encodePng(
    img.Image(width: 16, height: 9)..clear(img.ColorRgb8(250, 244, 220)),
  ),
);

ProfileMediaService _service({required bool available}) => ProfileMediaService(
  auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'viewer')),
  invoker: (_, request) async => <Object?, Object?>{
    'schemaVersion': 1,
    'available': available && request['kind'] == 'banner',
    'expiresAtMillis': DateTime.now()
        .toUtc()
        .add(const Duration(seconds: 90))
        .millisecondsSinceEpoch,
    if (available && request['kind'] == 'banner') ...{
      'url': 'https://storage.googleapis.com/test/banner?signature=short',
      'generation': '7',
      'contentType': 'image/png',
      'size': 4096,
    },
  },
);

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

SystemUiOverlayStyle? _statusStyle(WidgetTester tester) => tester
    .binding
    .renderViews
    .first
    .debugLayer!
    .find<SystemUiOverlayStyle>(const Offset(20, 4));

void main() {
  setUp(() {
    ProfileMediaService.clearAllMediaAccessCaches();
    // The photo fixture is one provider: a copy cached by an earlier test
    // would arrive synchronously and skip the fade this suite pins.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  group('ProfileHeroGeometry', () {
    test('a phone under a status bar shows the whole 16:9 banner', () {
      final hero = ProfileHeroGeometry.resolve(
        width: 390,
        topInset: 47,
        viewportHeight: 844,
        windowWidth: 390,
      );
      expect(hero.backdropLeft, 0);
      expect(hero.backdropWidth, 390);
      expect(hero.height, closeTo(390 * 9 / 16, 1e-9));
      expect(hero.sideFade, 0);
    });

    test('tiers grow with width, and past 1440 the height scales with it', () {
      double h(double w, {double top = 0}) => ProfileHeroGeometry.resolve(
        width: w,
        topInset: top,
        viewportHeight: 1440,
        windowWidth: w,
      ).height;
      expect(h(768, top: 24), 24 + 56 + 156);
      expect(h(1440), 232);
      expect(h(2560), closeTo(232 * 2560 / 1440, 1e-9));
      expect(h(390), lessThan(h(768, top: 24)));
    });

    test('a landscape phone spends at most 45% of its height on imagery', () {
      final hero = ProfileHeroGeometry.resolve(
        width: 844,
        viewportHeight: 390,
        windowWidth: 844,
      );
      expect(hero.height, lessThanOrEqualTo(390 * .45 + 1e-9));
    });

    test('the text line always leaves the toolbar a clear band of photo', () {
      for (final width in const <double>[
        320,
        360,
        390,
        430,
        600,
        768,
        1100,
        3840,
      ]) {
        for (final top in const <double>[0, 20, 24, 47, 59]) {
          for (final viewport in const <double>[320, 568, 844, 1440]) {
            final hero = ProfileHeroGeometry.resolve(
              width: width,
              topInset: top,
              viewportHeight: viewport,
              windowWidth: width,
            );
            expect(
              hero.textLine - top - ProfileHeroGeometry.toolbarExtent,
              greaterThanOrEqualTo(ProfileHeroGeometry.minimumClearBand - 1e-9),
              reason: '$width x $viewport, status bar $top',
            );
            expect(hero.textLine, lessThan(hero.height));
          }
        }
      }
    });

    test('the crop guide fraction is the smallest share any width shows', () {
      expect(
        ProfileHeroGeometry.alwaysVisibleFraction,
        closeTo((16 / 9) / (1440 / 232), 1e-9),
      );
      expect(
        ProfileHeader.bannerSafeBandFraction,
        ProfileHeroGeometry.alwaysVisibleFraction,
      );
      for (final width in const <double>[
        320,
        390,
        600,
        768,
        1100,
        1440,
        2560,
      ]) {
        final hero = ProfileHeroGeometry.resolve(
          width: width,
          viewportHeight: 1440,
          windowWidth: width,
        );
        final shown = (16 / 9) / (hero.backdropWidth / hero.height);
        expect(
          shown.clamp(0, 1),
          greaterThanOrEqualTo(
            ProfileHeroGeometry.alwaysVisibleFraction - 1e-9,
          ),
          reason: '$width',
        );
      }
    });

    test('the side melt appears only when a host capped the column', () {
      expect(
        ProfileHeroGeometry.resolve(width: 1440, windowWidth: 2560).sideFade,
        ProfileHeroGeometry.sideFadeExtent,
      );
      expect(
        ProfileHeroGeometry.resolve(width: 1440, windowWidth: 1440).sideFade,
        0,
      );
      expect(
        ProfileHeroGeometry.resolve(width: 2560, windowWidth: 2560).sideFade,
        0,
      );
      expect(
        ProfileHeroGeometry.resolve(width: 1176, windowWidth: 1440).sideFade,
        0,
        reason: 'beside the desktop sidebar the photo meets the sidebar',
      );
    });
  });

  group('own profile header', () {
    Future<void> pumpHeader(
      WidgetTester tester, {
      double top = 0,
      ScrollPhysics? physics,
      bool disableAnimations = false,
      ThemeData? theme,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme ?? AppTheme.darkTheme,
          home: const Scaffold(body: Text('previous-route')),
        ),
      );
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: EdgeInsets.only(top: top),
              disableAnimations: disableAnimations,
            ),
            child: Scaffold(
              body: ListView(
                physics: physics,
                padding: EdgeInsets.zero,
                children: [
                  ProfileHeader(
                    profile: _profile(),
                    onEdit: () {},
                    mediaService: _service(available: false),
                  ),
                  const SizedBox(height: 1200),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final size in const [
      Size(320, 568),
      Size(390, 844),
      Size(768, 1024),
      Size(1100, 800),
      Size(1440, 900),
      Size(2560, 1440),
    ]) {
      testWidgets('the banner is full bleed at ${size.width.toInt()}', (
        tester,
      ) async {
        _size(tester, size);
        await pumpHeader(tester);

        final band = tester.getRect(find.byType(ProfileBannerButton));
        expect(band.left, 0);
        expect(band.top, 0);
        expect(band.width, size.width);
        expect(
          find.ancestor(
            of: find.byType(ProfileBanner),
            matching: find.byType(ClipRRect),
          ),
          findsNothing,
          reason: 'no rounded card around the banner any more',
        );
        // Readable content stays on the centred 1040pt feed measure.
        final column = size.width > 1040 ? 1040.0 : size.width;
        expect(
          tester.getRect(find.byKey(const Key('profile-header-avatar'))).left,
          closeTo((size.width - column) / 2 + ProfileHeader.gutter, .01),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the photo runs under the status bar while Back clears it', (
      tester,
    ) async {
      _size(tester, const Size(390, 844));
      await pumpHeader(tester, top: 47);

      expect(tester.getRect(find.byType(ProfileBannerButton)).top, 0);
      final back = tester.getRect(find.byTooltip('Back'));
      expect(back.top, greaterThanOrEqualTo(47));
      expect(back.height, greaterThanOrEqualTo(44));
    });

    testWidgets('the page is still announced as the profile and the banner '
        'stays a focusable button', (tester) async {
      final semantics = tester.ensureSemantics();
      _size(tester, const Size(390, 844));
      await pumpHeader(tester);

      expect(find.text('Profile'), findsNothing, reason: 'no title on photo');
      final route = tester
          .getSemantics(find.bySemanticsLabel('Profile'))
          .getSemanticsData();
      expect(route.flagsCollection.namesRoute, isTrue);

      final banner = tester
          .getSemantics(
            find.bySemanticsLabel('Background photo of Ada Lovelace'),
          )
          .getSemanticsData();
      expect(banner.flagsCollection.isButton, isTrue);
      expect(banner.hasAction(SemanticsAction.tap), isTrue);

      // Keyboard: the banner's InkWell takes focus like any other control.
      final focusNode = Focus.of(
        tester.element(
          find.descendant(
            of: find.byType(ProfileBannerButton),
            matching: find.byType(ProfileHeroBackdrop),
          ),
        ),
      );
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
      semantics.dispose();
    });

    testWidgets('an iOS bounce keeps the photo under the status bar', (
      tester,
    ) async {
      _size(tester, const Size(390, 844));
      await pumpHeader(tester, physics: const BouncingScrollPhysics());

      final gesture = await tester.startGesture(const Offset(200, 500));
      await gesture.moveBy(const Offset(0, 160));
      await tester.pump();

      final header = tester.getRect(find.byType(ProfileHeader));
      final band = tester.getRect(find.byType(ProfileBannerButton));
      expect(header.top, greaterThan(10), reason: 'the list really bounced');
      expect(band.top, closeTo(0, .5), reason: 'no canvas strip opens above');
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('Reduce Motion drops the bounce stretch', (tester) async {
      _size(tester, const Size(390, 844));
      await pumpHeader(
        tester,
        physics: const BouncingScrollPhysics(),
        disableAnimations: true,
      );

      final gesture = await tester.startGesture(const Offset(200, 500));
      await gesture.moveBy(const Offset(0, 160));
      await tester.pump();

      final header = tester.getRect(find.byType(ProfileHeader));
      final band = tester.getRect(find.byType(ProfileBannerButton));
      expect(band.top, closeTo(header.top, .5));
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('ProfileHeroBackdrop states', () {
    final geometry = ProfileHeroGeometry.resolve(width: 390, topInset: 47);

    Future<void> pumpBackdrop(
      WidgetTester tester, {
      required ThemeData theme,
      required ProfileMediaService service,
      bool highContrast = false,
      bool disableAnimations = false,
    }) async {
      _size(tester, const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              highContrast: highContrast,
              disableAnimations: disableAnimations,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 390,
                height: geometry.height,
                child: ProfileHeroBackdrop(
                  geometry: geometry,
                  userId: 'u1',
                  mediaService: service,
                  imageProvider: (_) => _pixel,
                ),
              ),
            ),
          ),
        ),
      );
    }

    Future<void> decode(WidgetTester tester) async {
      // Resolve the grant and build the Image first, so the photo arrives
      // asynchronously the way it does in production (and fades in).
      await tester.pump();
      await tester.pump();
      await tester.runAsync(
        () => precacheImage(
          _pixel,
          tester.element(find.byType(ProfileHeroBackdrop)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    Gradient baseGradient(WidgetTester tester) =>
        (tester
                    .widget<DecoratedBox>(
                      find.byKey(const ValueKey('profile-hero-base')),
                    )
                    .decoration
                as BoxDecoration)
            .gradient!;

    testWidgets('Pearl: pending and absent share a light wash, no scrim and '
        'the theme status bar', (tester) async {
      await pumpBackdrop(
        tester,
        theme: AppTheme.lightTheme,
        service: _service(available: false),
      );
      // Pending: nothing has answered yet.
      expect(baseGradient(tester), isNot(kProfileBannerFallbackGradient));
      final pendingColors = baseGradient(tester).colors;
      expect(pendingColors.last, AppPalette.light.backgroundTop);

      await decode(tester);
      // Absent: the same wash, still no photo layers.
      expect(baseGradient(tester).colors, pendingColors);
      expect(
        find.byKey(const ValueKey('profile-hero-top-scrim')),
        findsNothing,
      );
      expect(_statusStyle(tester), isNull);
    });

    testWidgets('Dark keeps the brand fallback gradient without a photo', (
      tester,
    ) async {
      await pumpBackdrop(
        tester,
        theme: AppTheme.darkTheme,
        service: _service(available: false),
      );
      await decode(tester);
      expect(baseGradient(tester), kProfileBannerFallbackGradient);
      expect(
        find.byKey(const ValueKey('profile-hero-top-scrim')),
        findsNothing,
      );
    });

    testWidgets('a photo brings its scrim, soft focus and light status icons '
        'with it', (tester) async {
      await pumpBackdrop(
        tester,
        theme: AppTheme.lightTheme,
        service: _service(available: true),
      );
      await decode(tester);

      expect(
        find.byKey(const ValueKey('profile-hero-top-scrim')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('profile-hero-soft-focus')),
        findsOneWidget,
      );
      expect(
        find.byType(BackdropFilter),
        findsNothing,
        reason: 'the blur is ImageFiltered on the photo, never a backdrop',
      );
      expect(find.byType(RepaintBoundary), findsWidgets);
      expect(
        _statusStyle(tester)?.statusBarIconBrightness,
        Brightness.light,
        reason: 'white icons over the photo, even in Pearl',
      );
      final fade = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(ProfileHeroBackdrop),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(fade.duration, const Duration(milliseconds: 180));
    });

    testWidgets('Reduce Motion: the photo appears without a fade', (
      tester,
    ) async {
      await pumpBackdrop(
        tester,
        theme: AppTheme.darkTheme,
        service: _service(available: true),
        disableAnimations: true,
      );
      await decode(tester);
      final fade = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(ProfileHeroBackdrop),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(fade.duration, Duration.zero);
    });

    testWidgets('high contrast keeps the scrim and drops the blur', (
      tester,
    ) async {
      await pumpBackdrop(
        tester,
        theme: AppTheme.darkTheme,
        service: _service(available: true),
        highContrast: true,
      );
      await decode(tester);
      expect(
        find.byKey(const ValueKey('profile-hero-top-scrim')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('profile-hero-soft-focus')),
        findsNothing,
      );
    });
  });

  testWidgets('the edit-profile preview is the phone hero in miniature', (
    tester,
  ) async {
    _size(tester, const Size(390, 844));
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'u1', email: 'ada@yovoice.app'),
    );
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: EditProfileScreen(
          profile: _profile(),
          service: ProfileService(firestore: db, auth: auth),
          entitlements: EntitlementService(firestore: db, auth: auth),
          mediaService: _service(available: false),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final backdrop = tester.getRect(find.byType(ProfileHeroBackdrop));
    expect(
      backdrop.height / backdrop.width,
      closeTo(9 / 16, .005),
      reason: 'a phone shows the whole 16:9 banner, and so does the preview',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('edit-profile-hero-preview')),
        matching: find.byType(ProfileHeroBackdrop),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
