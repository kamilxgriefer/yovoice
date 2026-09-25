import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_header.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
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
            // Re-based deliberately: the 16:9 cap now wins over this floor
            // (a phone always shows the whole banner, never a side crop), so
            // where the floor would need more height than 16:9 allows — only
            // a very narrow phone under a tall status bar — the pin is the
            // whole banner plus a text line below the toolbar instead.
            final tierFade = width < 600
                ? ProfileHeroGeometry.narrowFade
                : width < 1100
                ? ProfileHeroGeometry.mediumFade
                : ProfileHeroGeometry.wideFade;
            final floor =
                top +
                ProfileHeroGeometry.toolbarExtent +
                ProfileHeroGeometry.minimumClearBand +
                tierFade * ProfileHeroGeometry.textFadeShare;
            if (floor > width * 9 / 16) {
              expect(hero.height, closeTo(width * 9 / 16, 1e-9));
              expect(
                hero.textLine,
                greaterThan(top + ProfileHeroGeometry.toolbarExtent),
                reason: '$width x $viewport, status bar $top',
              );
            } else {
              expect(
                hero.textLine - top - ProfileHeroGeometry.toolbarExtent,
                greaterThanOrEqualTo(
                  ProfileHeroGeometry.minimumClearBand - 1e-9,
                ),
                reason: '$width x $viewport, status bar $top',
              );
            }
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

    // The crop editor's guide is only worth drawing if it is true at every
    // size the hero can take — short desktop windows, landscape phones,
    // narrow phones under tall status bars — so this maps the stored 16:9
    // rows onto the hero for each of them instead of re-deriving the
    // guide's own formula.
    test('the crop guide holds at every size: its band is on screen and its '
        'upper part stays above the melt', () {
      final visible = ProfileHeroGeometry.alwaysVisibleFraction;
      final clear = ProfileHeroGeometry.alwaysClearFraction;
      expect(ProfileHeader.bannerClearBandFraction, clear);
      expect(clear, lessThan(visible));
      final bandTop = .5 - visible / 2;
      final bandBottom = .5 + visible / 2;
      final clearBottom = bandTop + clear;
      var tightestMelt = double.infinity;
      final widths = <double>[
        for (var width = 280.0; width <= 3840; width += 7) width,
        320,
        390,
        393,
        599,
        600,
        1099,
        1100,
        1440,
        2560,
      ];
      for (final width in widths) {
        for (final top in const <double>[0, 20, 24, 47, 59]) {
          for (final viewport in const <double>[
            320,
            400,
            500,
            600,
            700,
            844,
            1000,
            1440,
          ]) {
            final hero = ProfileHeroGeometry.resolve(
              width: width,
              topInset: top,
              viewportHeight: viewport,
              windowWidth: width,
            );
            final reason = '$width x $viewport, status bar $top';
            // Never narrower than 16:9: a phone shows the whole banner and
            // nothing is ever cropped at the sides.
            final drawn = hero.backdropWidth * 9 / 16;
            expect(
              hero.height,
              lessThanOrEqualTo(drawn + 1e-9),
              reason: reason,
            );
            // BoxFit.cover + Alignment.center: stored row s sits at
            // y = offset + s * drawn.
            final offset = (hero.height - drawn) / 2;
            double rowAt(double y) => (y - offset) / drawn;
            expect(rowAt(0), lessThanOrEqualTo(bandTop + 1e-9), reason: reason);
            expect(
              rowAt(hero.height),
              greaterThanOrEqualTo(bandBottom - 1e-9),
              reason: reason,
            );
            final meltStart = rowAt(hero.height - hero.fade);
            expect(
              meltStart,
              greaterThanOrEqualTo(clearBottom - 1e-9),
              reason: reason,
            );
            tightestMelt = math.min(tightestMelt, meltStart);
          }
        }
      }
      // The guide is not slack either: somewhere the melt starts right at
      // the bottom of its clear part (the 1440 desktop).
      expect(tightestMelt, closeTo(clearBottom, 1e-6));
    });

    test('the melt never takes more of the hero than at the widest size', () {
      for (final (width, top, viewport) in const [
        (390.0, 0.0, 844.0),
        (320.0, 20.0, 568.0),
        (844.0, 0.0, 390.0),
        (1440.0, 0.0, 900.0),
        (1440.0, 0.0, 500.0),
      ]) {
        final hero = ProfileHeroGeometry.resolve(
          width: width,
          topInset: top,
          viewportHeight: viewport,
          windowWidth: width,
        );
        expect(
          hero.fade / hero.height,
          lessThanOrEqualTo(ProfileHeroGeometry.maxFadeShare + 1e-9),
          reason: '$width x $viewport',
        );
      }
      // The phones people carry keep the full melt.
      expect(
        ProfileHeroGeometry.resolve(width: 393, topInset: 59).fade,
        ProfileHeroGeometry.narrowFade,
      );
      expect(ProfileHeroGeometry.resolve(width: 1440).fade, 112);
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
      // Measured canvas beats the window heuristic: a 1704 window minus the
      // 264 sidebar is exactly the 1440 workbench, so no canvas is left.
      expect(
        ProfileHeroGeometry.resolve(
          width: 1440,
          windowWidth: 1704,
          sideCanvas: 0,
        ).sideFade,
        0,
      );
      expect(
        ProfileHeroGeometry.resolve(
          width: 1440,
          windowWidth: 1800,
          sideCanvas: 24,
        ).sideFade,
        0,
        reason: 'a gutter narrower than the melt would fade into the sidebar',
      );
      expect(
        ProfileHeroGeometry.resolve(
          width: 1440,
          windowWidth: 2560,
          sideCanvas: 428,
        ).sideFade,
        ProfileHeroGeometry.sideFadeExtent,
      );
    });
  });

  group('own profile header', () {
    Future<void> pumpHeader(
      WidgetTester tester, {
      double top = 0,
      EdgeInsets? safe,
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
              padding: safe ?? EdgeInsets.only(top: top),
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

    testWidgets('keyboard focus starts on Back and reaches the banner last', (
      tester,
    ) async {
      _size(tester, const Size(390, 844));
      await pumpHeader(tester, top: 47);

      String? focusedControl() {
        final context = FocusManager.instance.primaryFocus?.context;
        if (context == null) return null;
        final icon = context.findAncestorWidgetOfExactType<IconButton>();
        if (icon != null) return icon.tooltip;
        if (context.findAncestorWidgetOfExactType<ProfileBannerButton>() !=
            null) {
          return 'banner';
        }
        if (context.findAncestorWidgetOfExactType<ProfilePhotoButton>() !=
            null) {
          return 'avatar';
        }
        return context.widget.runtimeType.toString();
      }

      final order = <String?>[];
      for (var i = 0; i < 8; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        order.add(focusedControl());
        if (order.last == 'banner') break;
      }
      expect(order.first, 'Back', reason: 'first Tab: $order');
      expect(order, contains('Edit profile'));
      expect(order, contains('avatar'));
      expect(order.last, 'banner', reason: 'the banner comes last: $order');
      expect(
        order.indexOf('Edit profile'),
        lessThan(order.indexOf('avatar')),
        reason: '$order',
      );
    });

    testWidgets('screen readers hear Back, the page name and the identity '
        'before the banner', (tester) async {
      final semantics = tester.ensureSemantics();
      _size(tester, const Size(390, 844));
      await pumpHeader(tester, top: 47);

      final labels = [
        for (final node in tester.semantics.simulatedAccessibilityTraversal())
          // IconButtons announce their tooltip.
          node.label.isEmpty ? node.tooltip : node.label,
      ];
      int at(bool Function(String label) test, String what) {
        final index = labels.indexWhere(test);
        expect(index, isNonNegative, reason: '$what missing from $labels');
        return index;
      }

      final back = at((l) => l == 'Back', 'Back');
      final route = at((l) => l == 'Profile', 'page name');
      final name = at((l) => l == 'Ada Lovelace', 'name');
      final handle = at((l) => l == '@ada', 'handle');
      final banner = at(
        (l) => l == 'Background photo of Ada Lovelace',
        'banner',
      );
      expect(back, lessThan(route), reason: '$labels');
      expect(route, lessThan(name), reason: '$labels');
      expect(name, lessThan(handle), reason: '$labels');
      expect(handle, lessThan(banner), reason: '$labels');
      semantics.dispose();
    });

    testWidgets('the banner focus ring stays on the visible photo, clear of '
        'the status bar and the handle', (tester) async {
      _size(tester, const Size(390, 844));
      await pumpHeader(tester, top: 47, theme: AppTheme.lightTheme);

      final bannerButton = find.byType(ProfileBannerButton);
      Focus.of(
        tester.element(
          find.descendant(
            of: bannerButton,
            matching: find.byType(ProfileHeroBackdrop),
          ),
        ),
      ).requestFocus();
      await tester.pumpAndSettle();

      final geometry = ProfileHeroGeometry.resolve(
        width: 390,
        topInset: 47,
        viewportHeight: 844,
        windowWidth: 390,
      );
      final rings = find.descendant(
        of: bannerButton,
        matching: find.byType(AnimatedContainer),
      );
      expect(rings, findsNWidgets(2));
      final handle = tester.getRect(find.text('@ada'));
      for (final ring in rings.evaluate()) {
        final rect = tester.getRect(find.byWidget(ring.widget));
        expect(rect.top, greaterThanOrEqualTo(47), reason: 'under the notch');
        expect(
          rect.bottom,
          lessThanOrEqualTo(geometry.textLine - 4 + 1e-6),
          reason: 'above the text line',
        );
        expect(rect.bottom, lessThanOrEqualTo(handle.top));
        expect(rect.left, greaterThanOrEqualTo(4));
        expect(rect.right, lessThanOrEqualTo(390 - 4));
        final decoration =
            (ring.widget as AnimatedContainer).decoration! as BoxDecoration;
        expect(
          (decoration.border! as Border).top.color,
          isNot(Colors.transparent),
          reason: 'the ring is drawn while focused',
        );
      }
    });

    testWidgets('a landscape iPhone keeps Back and the identity clear of the '
        'notch insets', (tester) async {
      _size(tester, const Size(844, 390));
      await pumpHeader(
        tester,
        safe: const EdgeInsets.only(left: 47, right: 47, bottom: 21),
      );

      expect(tester.getRect(find.byType(ProfileBannerButton)).left, 0);
      expect(tester.getRect(find.byType(ProfileBannerButton)).width, 844);
      expect(
        tester.getRect(find.byTooltip('Back')).left,
        greaterThanOrEqualTo(47 + 6 - .01),
      );
      expect(
        tester.getRect(find.byTooltip('Edit profile')).right,
        lessThanOrEqualTo(844 - 47 - ProfileHeader.gutter + .01),
      );
      final avatar = tester.getRect(
        find.byKey(const Key('profile-header-avatar')),
      );
      expect(
        avatar.left,
        greaterThanOrEqualTo(47 + ProfileHeader.gutter - .01),
      );
      expect(
        tester.getRect(find.text('Ada Lovelace')).left,
        greaterThan(avatar.right),
      );
      expect(
        tester.getRect(find.text('Ada Lovelace')).right,
        lessThanOrEqualTo(844 - 47 - ProfileHeader.gutter + .01),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('beside the desktop sidebar the photo melts only into real '
        'canvas', (tester) async {
      Future<void> pumpShell(double window) async {
        _size(tester, Size(window, 900));
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: Row(
                children: [
                  const SizedBox(width: 264),
                  Expanded(
                    child: ResponsiveContentFrame(
                      width: ResponsiveContentWidth.workbench,
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          ProfileHeader(
                            profile: _profile(),
                            onEdit: () {},
                            mediaService: _service(available: false),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      // 1704 − 264 is exactly the 1440 workbench: no canvas beside it.
      await pumpShell(1704);
      expect(tester.getRect(find.byType(ProfileBannerButton)).width, 1440);
      expect(
        find.byKey(const ValueKey('profile-hero-side-melt')),
        findsNothing,
      );
      // 2560 − 264 leaves 428 pt of canvas on each side of the column.
      await pumpShell(2560);
      expect(
        find.byKey(const ValueKey('profile-hero-side-melt')),
        findsOneWidget,
      );
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

    testWidgets('the soft focus is a pre-blurred copy drawn over the bottom '
        'band only — nothing filters per frame', (tester) async {
      await pumpBackdrop(
        tester,
        theme: AppTheme.darkTheme,
        service: _service(available: true),
      );
      await decode(tester);

      final band = tester.getRect(
        find.byKey(const ValueKey('profile-hero-soft-focus')),
      );
      final hero = tester.getRect(find.byType(ProfileHeroBackdrop));
      expect(band.bottom, closeTo(hero.bottom, .01));
      expect(
        band.height,
        closeTo(geometry.fade + ProfileHeroBackdrop.softFocusLead, .01),
      );
      expect(band.height, lessThan(hero.height * .6));
      expect(
        find.descendant(
          of: find.byType(ProfileHeroBackdrop),
          matching: find.byType(ImageFiltered),
        ),
        findsNothing,
      );
      final copy = tester.widget<RawImage>(
        find.byKey(const ValueKey('profile-hero-soft-focus-copy')),
      );
      expect(copy.image, isNotNull, reason: 'rendered from the cached photo');
      expect(
        copy.image!.width,
        (390 / ProfileHeroBackdrop.softFocusTexel).ceil(),
      );
      // Laid out at the full hero size, so it lines up with the photo.
      expect(
        tester.getRect(
          find.byKey(const ValueKey('profile-hero-soft-focus-copy')),
        ),
        hero,
      );
    });

    for (final (themeName, theme) in [
      ('Dark', AppTheme.darkTheme),
      ('Pearl', AppTheme.lightTheme),
    ]) {
      testWidgets('$themeName: the status bar stays legible over a white '
          'banner across the whole inset', (tester) async {
        final white = MemoryImage(
          img.encodePng(
            img.Image(width: 16, height: 9)
              ..clear(img.ColorRgb8(255, 255, 255)),
          ),
        );
        final boundary = GlobalKey();
        _size(tester, const Size(390, 844));
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(390, 844),
                disableAnimations: true,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: RepaintBoundary(
                  key: boundary,
                  child: SizedBox(
                    width: 390,
                    height: geometry.height,
                    child: ProfileHeroBackdrop(
                      geometry: geometry,
                      userId: 'u1',
                      mediaService: _service(available: true),
                      imageProvider: (_) => white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.runAsync(
          () => precacheImage(
            white,
            tester.element(find.byType(ProfileHeroBackdrop)),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final pixels = await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage();
          try {
            final data = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            return (data!, image.width);
          } finally {
            image.dispose();
          }
        });
        final (data, width) = pixels!;
        double luminance(int x, int y) {
          final i = (y * width + x) * 4;
          double channel(int value) {
            final c = value / 255;
            return c <= .04045
                ? c / 12.92
                : math.pow((c + .055) / 1.055, 2.4).toDouble();
          }

          return .2126 * channel(data.getUint8(i)) +
              .7152 * channel(data.getUint8(i + 1)) +
              .0722 * channel(data.getUint8(i + 2));
        }

        final inset = geometry.topInset;
        for (final y in [(inset / 2).round(), (inset - 8).round()]) {
          for (final x in const [40, 195, 350]) {
            final contrast = 1.05 / (luminance(x, y) + .05);
            expect(
              contrast,
              greaterThanOrEqualTo(4.5),
              reason:
                  'white clock text at ($x, $y): '
                  '${contrast.toStringAsFixed(2)}:1',
            );
          }
        }
      });
    }

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

  // Kamil, after the first frames: the photo must stand BEHIND the avatar,
  // the name and the handle, covering the whole header, with a stronger fade
  // under the text. These pin that the picture really reaches behind the
  // identity, and that every text role still meets contrast over the worst
  // photo for its theme.
  group('the photo stands behind the identity', () {
    test('the avatar rises into the photo and the text sits on its veil', () {
      for (final (width, top) in const [
        (360.0, 24.0),
        (390.0, 47.0),
        (393.0, 59.0),
        (430.0, 47.0),
        (768.0, 24.0),
        (1100.0, 0.0),
        (1440.0, 0.0),
        (2560.0, 0.0),
      ]) {
        final hero = ProfileHeroGeometry.resolve(
          width: width,
          topInset: top,
          viewportHeight: 1440,
          windowWidth: width,
        );
        final reason = '$width, status bar $top';
        // The text keeps the line the identity had when it stood below the
        // photo, so the header never grows.
        expect(
          hero.nameLine,
          closeTo(
            hero.height - hero.fade * ProfileHeroGeometry.textFadeShare,
            1e-9,
          ),
          reason: reason,
        );
        expect(hero.textLine, lessThanOrEqualTo(hero.nameLine));
        expect(
          hero.nameOffset,
          closeTo(ProfileHeroGeometry.nameDrop, 1e-9),
          reason: reason,
        );
        // The avatar's top clears the floating toolbar …
        expect(
          hero.textLine - top - ProfileHeroGeometry.toolbarExtent,
          greaterThanOrEqualTo(ProfileHeroGeometry.minimumClearBand - 1e-9),
          reason: reason,
        );
        // … and stands inside the photo's box, as does the name.
        expect(hero.nameLine, lessThan(hero.height), reason: reason);
        // The photo continues below its box behind the identity.
        expect(
          hero.extent,
          greaterThanOrEqualTo(
            hero.nameLine + ProfileHeroGeometry.narrowVeilTail - 1e-9,
          ),
          reason: reason,
        );
      }
      // On the phones people carry, the 80 pt phone avatar stands on the
      // photo's box: its centre, and more, is inside it.
      for (final top in const <double>[47, 59]) {
        final hero = ProfileHeroGeometry.resolve(width: 393, topInset: top);
        expect(hero.textLine + 40, lessThan(hero.height - 20));
      }
    });

    testWidgets('own profile: avatar on the photo, name and handle on the '
        'veil, the photo continued below its box', (tester) async {
      for (final (size, top) in const [
        (Size(390, 844), 47.0),
        (Size(768, 1024), 24.0),
        (Size(1440, 900), 0.0),
      ]) {
        _size(tester, size);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                padding: EdgeInsets.only(top: top),
              ),
              child: Scaffold(
                body: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    ProfileHeader(
                      key: ValueKey(size),
                      profile: _profile(),
                      onEdit: () {},
                      mediaService: _service(available: false),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final geometry = ProfileHeroGeometry.resolve(
          width: size.width,
          topInset: top,
          viewportHeight: size.height,
          windowWidth: size.width,
        );
        final reason = '${size.width}';
        final photo = tester.getRect(find.byType(ProfileBannerButton));
        final avatar = tester.getRect(
          find.byKey(const Key('profile-header-avatar')),
        );
        final name = tester.getRect(find.text('Ada Lovelace'));
        final handle = tester.getRect(find.text('@ada'));
        expect(photo.height, closeTo(geometry.height, .01), reason: reason);
        expect(avatar.top, closeTo(geometry.textLine, .01), reason: reason);
        expect(avatar.top, lessThan(photo.bottom), reason: reason);
        expect(
          avatar.center.dy,
          lessThan(photo.bottom),
          reason: '$reason: the avatar stands on the photo, not below it',
        );
        expect(
          name.top,
          greaterThanOrEqualTo(geometry.nameLine - .01),
          reason: '$reason: no text above the veil',
        );
        expect(name.top, lessThan(photo.bottom), reason: reason);
        expect(
          handle.top,
          greaterThanOrEqualTo(
            geometry.nameLine + ProfileHeroBackdrop.nameVeilBand - .01,
          ),
          reason: '$reason: the handle stands on the stronger veil',
        );
        expect(tester.takeException(), isNull, reason: reason);
      }
    });

    testWidgets('the avatar ring holds 3:1 against its cut-out in both '
        'themes', (tester) async {
      for (final (theme, palette) in [
        (AppTheme.darkTheme, AppPalette.dark),
        (AppTheme.lightTheme, AppPalette.light),
      ]) {
        expect(
          _contrast(palette.borderStrong, palette.background),
          greaterThanOrEqualTo(3),
        );
        _size(tester, const Size(390, 844));
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: ListView(
                children: [
                  ProfileHeader(
                    key: ValueKey(theme.brightness),
                    profile: _profile(),
                    onEdit: () {},
                    mediaService: _service(available: false),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final ring =
            tester
                    .widget<Container>(
                      find.byKey(const Key('profile-header-avatar')),
                    )
                    .decoration!
                as BoxDecoration;
        expect(ring.color, palette.background);
        expect((ring.border! as Border).top.color, palette.borderStrong);
      }
    });

    testWidgets('the continuation below the photo box has no seam', (
      tester,
    ) async {
      final geometry = ProfileHeroGeometry.resolve(width: 390, topInset: 47);
      // Dark rows over white ones, on the Dark canvas: the white rows at the
      // photo's bottom edge are what the continuation must pick up, and a
      // gap in it shows as a dark hairline.
      final source = img.Image(width: 160, height: 90);
      for (var y = 0; y < 90; y++) {
        for (var x = 0; x < 160; x++) {
          final v = (255 * y / 89).round();
          source.setPixelRgb(x, y, v, v, v);
        }
      }
      final photo = MemoryImage(img.encodePng(source));
      final pixels = await _renderHero(
        tester,
        theme: AppTheme.darkTheme,
        canvas: AppPalette.dark.background,
        geometry: geometry,
        photo: photo,
      );
      // 390 × 9 / 16 = 219.375: the box ends on a fractional row, where two
      // anti-aliased edges could leave a hairline.
      final edge = geometry.height.floor();
      for (final x in const [20, 195, 370]) {
        for (var y = edge - 3; y <= edge + 3; y++) {
          final upper = pixels.at(x, y);
          final lower = pixels.at(x, y + 1);
          // Row to row the veil changes a pixel by about 0.2%; a missing,
          // misplaced or hairline-split continuation by far more.
          expect(
            _distance(upper, lower),
            lessThan(.006),
            reason: 'seam at ($x, $y): $upper -> $lower',
          );
        }
      }
    });

    for (final (themeName, theme, palette) in [
      ('Dark', AppTheme.darkTheme, AppPalette.dark),
      ('Pearl', AppTheme.lightTheme, AppPalette.light),
    ]) {
      for (final (photoName, photoColor) in [
        ('white', img.ColorRgb8(255, 255, 255)),
        ('black', img.ColorRgb8(0, 0, 0)),
      ]) {
        for (final highContrast in const [false, true]) {
          testWidgets('$themeName, $photoName photo'
              '${highContrast ? ', high contrast' : ''}: text meets contrast '
              'on the veil', (tester) async {
            final geometry = ProfileHeroGeometry.resolve(
              width: 390,
              topInset: 47,
            );
            final photo = MemoryImage(
              img.encodePng(img.Image(width: 16, height: 9)..clear(photoColor)),
            );
            final pixels = await _renderHero(
              tester,
              theme: theme,
              canvas: palette.background,
              geometry: geometry,
              photo: photo,
              highContrast: highContrast,
            );
            final canvas = palette.background;
            // The picture really reaches behind the avatar and below its
            // own box — unless high contrast took it away.
            final avatarTop = pixels.at(40, geometry.textLine.round() + 2);
            final belowBox = pixels.at(40, geometry.height.round() + 6);
            if (highContrast) {
              for (
                var y = geometry.textLine.round() - 7;
                y < geometry.extent.round();
                y += 3
              ) {
                for (final x in const [10, 195, 380]) {
                  expect(
                    _distance(pixels.at(x, y), canvas),
                    lessThan(.02),
                    reason: 'no photo behind the identity at ($x, $y)',
                  );
                }
              }
              return;
            }
            final photoInk = photoName == 'white'
                ? AppColors.white
                : AppColors.black;
            expect(
              _distance(avatarTop, canvas),
              greaterThan(_distance(photoInk, canvas) * .5),
              reason: 'the photo stands behind the top of the avatar',
            );
            if (_distance(photoInk, canvas) > .5) {
              expect(
                _distance(belowBox, canvas),
                greaterThan(.01),
                reason: 'the photo continues below its box',
              );
            }
            for (
              var y = geometry.nameLine.round();
              y < geometry.extent.round() + 4;
              y += 2
            ) {
              final large =
                  y < geometry.nameLine + ProfileHeroBackdrop.nameVeilBand;
              for (final x in const [10, 120, 195, 300, 380]) {
                final ground = pixels.at(x, y);
                if (large) {
                  expect(
                    _contrast(palette.textPrimary, ground),
                    greaterThanOrEqualTo(3),
                    reason: 'name (large text) at ($x, $y)',
                  );
                } else {
                  for (final (role, ink) in [
                    ('textPrimary', palette.textPrimary),
                    ('textSecondary', palette.textSecondary),
                  ]) {
                    expect(
                      _contrast(ink, ground),
                      greaterThanOrEqualTo(4.5),
                      reason: '$role at ($x, $y)',
                    );
                  }
                }
              }
            }
            // Fully dissolved into the page at the extent.
            expect(
              _distance(pixels.at(195, geometry.extent.round() + 2), canvas),
              lessThan(.01),
            );
          });
        }
      }
    }
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

double _linear(double channel) => channel <= .04045
    ? channel / 12.92
    : math.pow((channel + .055) / 1.055, 2.4).toDouble();

double _luminance(Color color) =>
    .2126 * _linear(color.r) +
    .7152 * _linear(color.g) +
    .0722 * _linear(color.b);

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + .05) / (math.min(la, lb) + .05);
}

double _distance(Color a, Color b) =>
    ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs()) / 3;

class _Pixels {
  _Pixels(this.data, this.width);

  final ByteData data;
  final int width;

  Color at(int x, int y) {
    final i = (y * width + x) * 4;
    return Color.fromARGB(
      255,
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    );
  }
}

/// Renders the hero backdrop the way the header hosts it — its box is the
/// photo, on the page canvas, with room below for what it paints past that
/// box — and returns the pixels.
Future<_Pixels> _renderHero(
  WidgetTester tester, {
  required ThemeData theme,
  required Color canvas,
  required ProfileHeroGeometry geometry,
  required ImageProvider<Object> photo,
  bool highContrast = false,
}) async {
  final boundary = GlobalKey();
  final width = geometry.width;
  final height = geometry.extent + 24;
  _size(tester, Size(width, 844));
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 844),
          disableAnimations: true,
          highContrast: highContrast,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: RepaintBoundary(
            key: boundary,
            child: ColoredBox(
              color: canvas,
              child: SizedBox(
                width: width,
                height: height,
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: geometry.height,
                      child: ProfileHeroBackdrop(
                        geometry: geometry,
                        userId: 'u1',
                        mediaService: _service(available: true),
                        imageProvider: (_) => photo,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.runAsync(
    () =>
        precacheImage(photo, tester.element(find.byType(ProfileHeroBackdrop))),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  final result = await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return _Pixels(data!, image.width);
    } finally {
      image.dispose();
    }
  });
  return result!;
}
