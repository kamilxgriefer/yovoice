// Refine-look B9 (spec §8.6): More sheet + desktop popover, Settings,
// Friends, Notifications and Find creators adopt the finish recipes.
//
// These tests pin the values the batch deliberately introduced — the Pearl
// sheet surface and its shadow pair, R16 tiles and glyph boxes, R2 Settings
// groups with the one tinted doorway, the logo on the Wersja row and on the
// actor-less system notice, R8 chips (36 in 48, ink inversion), R7 neutral
// actions and the R10 brand avatars — plus their high-contrast twins.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_icons.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/creator/data/services/creator_directory_service.dart';
import 'package:yovoice/features/creator/presentation/screens/find_creators_screen.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/friends/presentation/screens/blocked_users_screen.dart';
import 'package:yovoice/features/friends/presentation/screens/friends_screen.dart';
import 'package:yovoice/features/friends/presentation/widgets/friend_suggestion_card.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/marketing/data/services/public_showcase_consent_service.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/settings/data/services/message_privacy_service.dart';
import 'package:yovoice/features/settings/presentation/screens/settings_screen.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/services/firestore_service.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';
import 'package:yovoice/shared/widgets/branding/yo_logo.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

const _me = 'me';

class _Caps extends StaffCapabilityService {
  _Caps(this.capabilities);

  final StaffCapabilities capabilities;

  @override
  Future<StaffCapabilities> load({bool refresh = false}) async => capabilities;
}

class _StubGraph extends SocialGraphService {
  @override
  Future<List<SuggestedFriend>> getFriendSuggestions({int limit = 10}) async =>
      const [
        SuggestedFriend(
          uid: 'szymon',
          displayName: 'Szymon',
          photoUrl: null,
          mutualCount: 2,
        ),
      ];
}

class _MemoryPreferencesStore implements AppPreferencesStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

Future<Map<String, dynamic>> _noMutation(
  String name,
  Map<String, dynamic> data,
) async => const <String, dynamic>{'changed': false};

Future<void> _pumps(WidgetTester tester, [int count = 12]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _localized(
  Widget home, {
  required ThemeData theme,
  bool highContrast = false,
  TextScaler textScaler = TextScaler.noScaling,
  AppPreferencesController? preferences,
  TextDirection? textDirection,
}) {
  return MaterialApp(
    theme: theme,
    locale: const Locale('pl'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) {
      Widget media = MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(highContrast: highContrast, textScaler: textScaler),
        child: child!,
      );
      if (textDirection != null) {
        media = Directionality(textDirection: textDirection, child: media);
      }
      if (preferences == null) return media;
      return AppPreferencesScope(controller: preferences, child: media);
    },
    home: home,
  );
}

void _useSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _seedFriends(FakeFirebaseFirestore db) async {
  await db.collection('users').doc(_me).set(<String, dynamic>{
    'uid': _me,
    'displayName': 'Kamil Jaguszewski',
    'username': 'kamil',
    'email': 'kamil@yovoice.app',
    'createdAt': Timestamp.fromDate(DateTime(2025, 3, 14)),
    'accountType': 'creator',
  });
  for (final (id, name, online) in const [
    ('ola', 'Ola Nowak', true),
    ('piotr', 'Piotr Kowalczyk', false),
  ]) {
    await db.collection('users').doc(_me).collection('friends').doc(id).set(
      <String, dynamic>{'displayName': name},
    );
    await db.collection('publicProfiles').doc(id).set(<String, dynamic>{
      'uid': id,
      'displayName': name,
      'username': id,
    });
    await db.collection('socialPresence').doc(id).set(<String, dynamic>{
      'isOnline': online,
      'availability': online ? 'available' : 'offline',
      'lastSeen': Timestamp.now(),
    });
  }
}

BoxDecoration? _boxDecoration(WidgetTester tester, Finder finder) {
  final widget = tester.widget(finder);
  if (widget is Container) return widget.decoration as BoxDecoration?;
  if (widget is DecoratedBox) return widget.decoration as BoxDecoration?;
  return null;
}

void main() {
  setUp(() {
    FriendService.clearSharedReadCaches();
    ProfileService.resetCurrentProfileCache();
    EntitlementService.resetCache();
  });
  tearDown(() {
    FriendService.clearSharedReadCaches();
    ProfileService.resetCurrentProfileCache();
    EntitlementService.resetCache();
  });

  // -------------------------------------------------------------------------
  // More sheet + desktop popover
  // -------------------------------------------------------------------------
  group('More sheet (R16)', () {
    test('Pearl sits on the paper canvas with the new shadow pair', () {
      const pearl = AppPalette.light;
      expect(moreSheetSurface(pearl), pearl.background);
      expect(moreSheetSurface(AppPalette.dark), AppPalette.dark.surfaceRaised);
      expect(moreSheetSurface(pearl, highContrast: true), pearl.surfaceRaised);

      final shadows = moreSheetShadows(pearl);
      expect(shadows, hasLength(2));
      expect(shadows.first.color, pearl.shadow.withValues(alpha: .10));
      expect(shadows.first.blurRadius, 2);
      expect(shadows.first.offset, const Offset(0, 1));
      expect(shadows.last.color, pearl.shadow.withValues(alpha: .24));
      expect(shadows.last.blurRadius, 40);
      expect(shadows.last.offset, const Offset(0, 18));
      expect(shadows.last.spreadRadius, -12);
      // The old @ .34 band is gone from Pearl.
      expect(
        shadows.map((shadow) => shadow.color.a),
        isNot(contains(closeTo(.34, .001))),
      );
      expect(moreSheetShadows(pearl, highContrast: true), isEmpty);
    });

    test('tiles: Dark glass, Pearl lit white with the block shadows', () {
      const dark = AppPalette.dark;
      const pearl = AppPalette.light;
      expect(moreTileDecoration(dark).color, dark.glass);
      expect(moreTileDecoration(dark).borderRadius, AppRadius.tile);
      expect(moreTileDecoration(dark).boxShadow, isEmpty);
      expect(moreTileDecoration(pearl).color, pearl.surfaceRaised);
      expect(moreTileDecoration(pearl).boxShadow, pearl.blockShadows);
      final hc = moreTileDecoration(pearl, highContrast: true);
      expect(hc.color, pearl.surface);
      expect(hc.boxShadow, isNull);
    });

    for (final (theme, palette, label) in [
      (AppTheme.lightTheme, AppPalette.light, 'Pearl'),
      (AppTheme.darkTheme, AppPalette.dark, 'Dark'),
    ]) {
      testWidgets('$label sheet: hairline edge, tiles and glyph boxes', (
        tester,
      ) async {
        _useSize(tester, const Size(390, 844));
        await tester.pumpWidget(
          _localized(
            Scaffold(
              body: SizedBox.expand(
                child: MoreSheet(
                  capabilityService: _Caps(StaffCapabilities.none),
                  currentUid: 'ordinary',
                ),
              ),
            ),
            theme: theme,
          ),
        );
        await tester.pumpAndSettle();

        final surface = _boxDecoration(
          tester,
          find.byKey(const ValueKey('more-sheet-surface')),
        )!;
        expect(surface.color, moreSheetSurface(palette));
        expect((surface.border! as Border).top.color, palette.hairline);
        expect(surface.boxShadow, moreSheetShadows(palette));

        final friendsTile = find.byKey(
          const ValueKey('more-destination-friends'),
        );
        final tileFills = find
            .descendant(of: friendsTile, matching: find.byType(DecoratedBox))
            .evaluate()
            .map((element) => (element.widget as DecoratedBox).decoration)
            .toList();
        expect(tileFills, contains(moreTileDecoration(palette)));
        expect(
          tileFills.whereType<BoxDecoration>().where(
            (decoration) =>
                decoration.border is Border &&
                (decoration.border! as Border).top.color == palette.hairline &&
                decoration.borderRadius == AppRadius.tile,
          ),
          isNotEmpty,
          reason: 'the tile edge is the hairline at radius 16',
        );

        final icon = find.descendant(
          of: friendsTile,
          matching: find.byIcon(Icons.people_rounded),
        );
        expect(tester.widget<Icon>(icon).color, palette.interactiveForeground);
        final glyph = _boxDecoration(
          tester,
          find.ancestor(of: icon, matching: find.byType(Container)).first,
        )!;
        final scheme = theme.colorScheme;
        expect(glyph.borderRadius, AppRadius.card);
        expect((glyph.gradient! as LinearGradient).colors, [
          scheme.primaryContainer,
          scheme.secondaryContainer,
        ]);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('staff rows keep their role colour on the glyph and edge', (
      tester,
    ) async {
      _useSize(tester, const Size(390, 1200));
      await tester.pumpWidget(
        _localized(
          Scaffold(
            body: SizedBox.expand(
              child: MoreSheet(
                capabilityService: _Caps(
                  const StaffCapabilities(
                    staffRole: 'moderator',
                    handleAssignedReports: true,
                  ),
                ),
                currentUid: '',
              ),
            ),
          ),
          theme: AppTheme.darkTheme,
        ),
      );
      await tester.pumpAndSettle();

      final moderation = find.byKey(
        const ValueKey('more-destination-moderation'),
      );
      expect(moderation, findsOneWidget);
      final icon = find.descendant(
        of: moderation,
        matching: find.byIcon(Icons.shield_rounded),
      );
      expect(tester.widget<Icon>(icon).color, AppColors.roleModerator);
      final edges = find
          .descendant(of: moderation, matching: find.byType(DecoratedBox))
          .evaluate()
          .map((element) => (element.widget as DecoratedBox).decoration)
          .whereType<BoxDecoration>()
          .where((decoration) => decoration.border is Border)
          .map((decoration) => (decoration.border! as Border).top.color);
      expect(edges, contains(AppColors.roleModerator.withValues(alpha: .5)));
    });

    testWidgets('high contrast: flat tiles on a borderStrong edge', (
      tester,
    ) async {
      _useSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        _localized(
          Scaffold(
            body: SizedBox.expand(
              child: MoreSheet(
                capabilityService: _Caps(StaffCapabilities.none),
                currentUid: 'ordinary',
              ),
            ),
          ),
          theme: AppTheme.lightHighContrastTheme,
          highContrast: true,
        ),
      );
      await tester.pumpAndSettle();
      final palette = AppTheme.lightHighContrastTheme.extension<AppPalette>()!;
      final surface = _boxDecoration(
        tester,
        find.byKey(const ValueKey('more-sheet-surface')),
      )!;
      expect(surface.boxShadow, isEmpty);
      expect((surface.border! as Border).top.color, palette.borderStrong);
      final fills = find
          .descendant(
            of: find.byKey(const ValueKey('more-destination-friends')),
            matching: find.byType(DecoratedBox),
          )
          .evaluate()
          .map((element) => (element.widget as DecoratedBox).decoration)
          .toList();
      expect(fills, contains(moreTileDecoration(palette, highContrast: true)));
    });

    testWidgets('desktop popover: radius 16, hairline side, glyph boxes', (
      tester,
    ) async {
      _useSize(tester, const Size(1440, 900));
      await tester.pumpWidget(
        _localized(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const ValueKey('open-more'),
                onPressed: () => showDesktopMoreMenu(
                  context,
                  anchor: const Offset(264, 300),
                ),
                child: const Text('open'),
              ),
            ),
          ),
          theme: AppTheme.darkTheme,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-more')));
      await tester.pumpAndSettle();

      const palette = AppPalette.dark;
      final shapes = tester
          .widgetList<Material>(find.byType(Material))
          .map((material) => material.shape)
          .whereType<RoundedRectangleBorder>()
          .where((shape) => shape.borderRadius == AppRadius.tile);
      expect(shapes, isNotEmpty, reason: 'the popover is radius 16');
      expect(shapes.first.side.color, palette.hairline);

      final icon = find.byIcon(Icons.people_rounded);
      expect(tester.widget<Icon>(icon).color, palette.interactiveForeground);
      final glyph = _boxDecoration(
        tester,
        find.ancestor(of: icon, matching: find.byType(Container)).first,
      )!;
      expect(glyph.gradient, isA<LinearGradient>());
      expect(glyph.borderRadius, AppRadius.card);
    });
    for (final (platform, factory, label) in [
      (TargetPlatform.iOS, NoSplash.splashFactory, 'iOS: no ripple'),
      (TargetPlatform.android, InkSparkle.splashFactory, 'Android: sparkle'),
    ]) {
      testWidgets('tile press is the scale and wash ($label)', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        _useSize(tester, const Size(390, 844));
        await tester.pumpWidget(
          _localized(
            Scaffold(
              body: SizedBox.expand(
                child: MoreSheet(
                  capabilityService: _Caps(StaffCapabilities.none),
                  currentUid: 'ordinary',
                ),
              ),
            ),
            theme: AppTheme.darkTheme,
          ),
        );
        await tester.pumpAndSettle();
        final ink = tester.widget<InkWell>(
          find
              .descendant(
                of: find.byKey(const ValueKey('more-destination-friends')),
                matching: find.byType(InkWell),
              )
              .first,
        );
        expect(ink.splashFactory, factory);
        debugDefaultTargetPlatformOverride = null;
      });
    }

    testWidgets('desktop popover at 200 % text: two subtitle lines, wider', (
      tester,
    ) async {
      _useSize(tester, const Size(1440, 900));
      Future<void> open(TextScaler scaler) async {
        await tester.pumpWidget(
          _localized(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  key: const ValueKey('open-more'),
                  onPressed: () => showDesktopMoreMenu(
                    context,
                    anchor: const Offset(264, 60),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
            theme: AppTheme.darkTheme,
            textScaler: scaler,
          ),
        );
        await tester.tap(find.byKey(const ValueKey('open-more')));
        await tester.pumpAndSettle();
      }

      await open(TextScaler.noScaling);
      var subtitle = tester.widget<Text>(find.text('Osoby warte obserwowania'));
      expect(subtitle.maxLines, 1);
      final regular = tester.getSize(
        find.ancestor(
          of: find.text('Osoby warte obserwowania'),
          matching: find.byType(PopupMenuItem<MoreDestination>),
        ),
      );
      expect(regular.width, lessThanOrEqualTo(300));
      await tester.tapAt(const Offset(1400, 880));
      await tester.pumpAndSettle();

      await open(const TextScaler.linear(2));
      subtitle = tester.widget<Text>(find.text('Osoby warte obserwowania'));
      expect(subtitle.maxLines, 2);
      final item = tester.widget<PopupMenuItem<MoreDestination>>(
        find.ancestor(
          of: find.text('Osoby warte obserwowania'),
          matching: find.byType(PopupMenuItem<MoreDestination>),
        ),
      );
      expect(
        item.padding,
        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      );
      final large = tester.getSize(
        find.ancestor(
          of: find.text('Osoby warte obserwowania'),
          matching: find.byType(PopupMenuItem<MoreDestination>),
        ),
      );
      expect(large.width, greaterThan(regular.width));
      expect(large.width, lessThanOrEqualTo(360));
      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Settings
  // -------------------------------------------------------------------------
  group('Settings (R2 groups, one lit doorway, the Wersja logo)', () {
    late FakeFirebaseFirestore db;
    late MockFirebaseAuth auth;

    setUp(() async {
      PackageInfo.setMockInitialValues(
        appName: 'YO Voice',
        packageName: 'app.yovoice',
        version: '3.1.0',
        buildNumber: '36',
        buildSignature: '',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/permissions/methods'),
            (call) async => call.method == 'checkPermissionStatus' ? 1 : null,
          );
      db = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
          uid: _me,
          email: 'kamil@yovoice.app',
          isEmailVerified: true,
        ),
      );
      await _seedFriends(db);
    });

    Future<void> pumpSettings(
      WidgetTester tester, {
      required ThemeData theme,
      bool highContrast = false,
      TextDirection? textDirection,
    }) async {
      // Tall enough that every group of the lazy list is built.
      _useSize(tester, const Size(390, 6000));
      final preferences = AppPreferencesController(
        store: _MemoryPreferencesStore(),
        initialValue: const AppPreferences(),
      );
      addTearDown(preferences.dispose);
      await tester.pumpWidget(
        _localized(
          SettingsScreen(
            isRootTab: true,
            profileService: ProfileService(firestore: db, auth: auth),
            authService: AuthService(
              firebaseAuth: auth,
              firestoreService: FirestoreService(firestore: db),
            ),
            friendService: FriendService(
              firestore: db,
              auth: auth,
              mutationInvoker: _noMutation,
            ),
            entitlementService: EntitlementService(firestore: db, auth: auth),
            showcaseConsentService: PublicShowcaseConsentService(firestore: db),
            messagePrivacyService: MessagePrivacyService(
              firestore: db,
              auth: auth,
            ),
          ),
          theme: theme,
          highContrast: highContrast,
          preferences: preferences,
          textDirection: textDirection,
        ),
      );
      await _pumps(tester);
    }

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('the profile doorway is the page\'s one tinted block', (
      tester,
    ) async {
      await pumpSettings(tester, theme: AppTheme.darkTheme);
      final scheme = AppTheme.darkTheme.colorScheme;

      final hero = tester.widget<YoCard>(
        find.byKey(const ValueKey('settings-profile-hero')),
      );
      expect(hero.tint, scheme.primary);
      expect(hero.radius, AppRadius.block);
      final tinted = tester
          .widgetList<YoCard>(find.byType(YoCard))
          .where((card) => card.tint != null);
      expect(tinted, hasLength(1), reason: 'at most one corner tint');
      expect(find.byType(YoCornerTint), findsOneWidget);

      final avatar = tester.widget<UserAvatar>(
        find.byKey(const ValueKey('settings-profile-hero-avatar')),
      );
      expect(avatar.finish, UserAvatarFinish.brand);
      expect(avatar.userId, _me);
      await unmount(tester);
    });

    for (final (theme, palette, label) in [
      (AppTheme.darkTheme, AppPalette.dark, 'Dark'),
      (AppTheme.lightTheme, AppPalette.light, 'Pearl'),
    ]) {
      testWidgets('$label groups: radius 20, hairline, danger keeps error', (
        tester,
      ) async {
        await pumpSettings(tester, theme: theme);
        final groups = tester
            .widgetList<Material>(find.byType(Material))
            .where(
              (material) =>
                  material.shape is RoundedRectangleBorder &&
                  (material.shape! as RoundedRectangleBorder).borderRadius ==
                      AppRadius.block,
            )
            .map((material) => material.shape! as RoundedRectangleBorder)
            .toList();
        expect(groups.length, greaterThanOrEqualTo(8));
        final error = theme.colorScheme.error.withValues(alpha: .45);
        expect(
          groups.where((shape) => shape.side.color == error),
          hasLength(1),
          reason: 'the danger zone keeps its error edge',
        );
        expect(
          groups.where((shape) => shape.side.color == palette.hairline),
          hasLength(groups.length - 1),
        );

        // The group label starts on the rows' 16 px edge.
        final label = find.text('KONTO');
        final padding = tester.widget<Padding>(
          find.ancestor(of: label, matching: find.byType(Padding)).first,
        );
        expect(padding.padding, const EdgeInsets.fromLTRB(16, 0, 16, 8));

        // Canvas: the shared radial.
        final canvas = tester.widget<YoPageBackground>(
          find.byKey(const ValueKey('settings-canvas')),
        );
        expect(
          (canvas.decoration! as BoxDecoration).gradient,
          palette.canvasGlow(theme.colorScheme.primary),
        );
        await unmount(tester);
      });
    }

    testWidgets('Wersja carries the bare logo at 40, no glyph box', (
      tester,
    ) async {
      await pumpSettings(tester, theme: AppTheme.lightTheme);
      final version = find.byKey(const ValueKey('settings-version'));
      expect(version, findsOneWidget);
      final logo = tester.widget<YoBrandMark>(
        find.byKey(const ValueKey('settings-version-logo')),
      );
      expect(logo.size, 40);
      expect(logo.light, YoBrandLight.none);
      expect(
        find.descendant(
          of: version,
          matching: find.byIcon(Icons.info_outline_rounded),
        ),
        findsNothing,
      );
      expect(find.text('Wersja'), findsOneWidget);
      expect(find.text('3.1.0 (36)'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('high contrast: no canvas glow, no tint, borderStrong edges', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        theme: AppTheme.darkHighContrastTheme,
        highContrast: true,
      );
      final palette = AppTheme.darkHighContrastTheme.extension<AppPalette>()!;
      final canvas = tester.widget<YoPageBackground>(
        find.byKey(const ValueKey('settings-canvas')),
      );
      expect(canvas.decoration, isNull);
      expect(find.byType(YoCornerTint), findsNothing);
      final sides = tester
          .widgetList<Material>(find.byType(Material))
          .map((material) => material.shape)
          .whereType<RoundedRectangleBorder>()
          .where((shape) => shape.borderRadius == AppRadius.block)
          .map((shape) => shape.side.color);
      expect(sides, contains(palette.borderStrong));
      expect(sides, isNot(contains(palette.hairline)));
      await unmount(tester);
    });
    for (final (theme, palette, label) in [
      (AppTheme.darkTheme, AppPalette.dark, 'Dark'),
      (AppTheme.lightTheme, AppPalette.light, 'Pearl'),
    ]) {
      testWidgets('$label keyboard focus paints a 2 px ring inside the row', (
        tester,
      ) async {
        await pumpSettings(tester, theme: theme);
        final ring = find.byKey(const ValueKey('settings-row-focus-ring'));
        expect(ring, findsNothing);
        for (var tab = 0; tab < 12 && ring.evaluate().isEmpty; tab++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        expect(ring, findsOneWidget, reason: 'Tab reaches a Settings row');
        final padding = tester.widget<Padding>(ring);
        expect(padding.padding, const EdgeInsets.all(4));
        final decoration =
            tester
                    .widget<DecoratedBox>(
                      find.descendant(
                        of: ring,
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .decoration
                as BoxDecoration;
        expect(decoration.borderRadius, AppRadius.tile);
        expect((decoration.border! as Border).top.color, palette.focus);
        expect((decoration.border! as Border).top.width, 2);
        // Painted over the row, never around it: the row keeps its size.
        final row = tester.getRect(
          find.ancestor(of: ring, matching: find.byType(Stack)).first,
        );
        expect(
          tester.getRect(ring),
          row,
          reason: 'the ring box fills the row; its padding insets the ring',
        );
        expect(row.height, greaterThanOrEqualTo(64));
        await unmount(tester);
      });
    }

    testWidgets('the root-tab title starts on the 16 px block gutter', (
      tester,
    ) async {
      await pumpSettings(tester, theme: AppTheme.darkTheme);
      final title = tester.getRect(find.text('Ustawienia'));
      final hero = tester.getRect(
        find.byKey(const ValueKey('settings-profile-hero')),
      );
      expect(title.left, 16);
      expect(hero.left, 16);
      await unmount(tester);
    });

    testWidgets('privacy rows: a divider between the website pair and an '
        'outline glyph for recent activity', (tester) async {
      await pumpSettings(tester, theme: AppTheme.lightTheme);
      final activity = find.text('Pokazuj ostatnią aktywność');
      final website = find.text('Pokazuj profil na stronie YO Voice');
      expect(activity, findsOneWidget);
      final pair = find
          .ancestor(of: activity, matching: find.byType(Column))
          .evaluate()
          .firstWhere(
            (element) => find
                .descendant(
                  of: find.byElementPredicate((e) => e == element),
                  matching: website,
                )
                .evaluate()
                .isNotEmpty,
          );
      final pairFinder = find.byElementPredicate((e) => e == pair);
      final divider = find.descendant(
        of: pairFinder,
        matching: find.byType(Divider),
      );
      expect(divider, findsOneWidget);
      final line = tester.widget<Divider>(divider);
      expect(line.color, AppPalette.light.hairline);
      expect(line.indent, 68);
      final row = find.ancestor(of: activity, matching: find.byType(ListTile));
      expect(
        find.descendant(of: row, matching: find.byIcon(Icons.history_rounded)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.byIcon(Icons.circle)),
        findsNothing,
      );
      await unmount(tester);
    });

    testWidgets('the support address may wrap after "@" but reads plainly', (
      tester,
    ) async {
      await pumpSettings(tester, theme: AppTheme.darkTheme);
      final address = find.text('support@\u200Byovoice.app');
      expect(address, findsOneWidget);
      expect(
        tester.widget<Text>(address).semanticsLabel,
        'support@yovoice.app',
      );
      await unmount(tester);
    });

    testWidgets('RTL: the doorway tint sits in the top-end (left) corner', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        theme: AppTheme.darkTheme,
        textDirection: TextDirection.rtl,
      );
      final hero = find.byKey(const ValueKey('settings-profile-hero'));
      final card = tester.getRect(hero);
      final circle = tester.getRect(
        find.descendant(
          of: find.byType(YoCornerTint),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect(circle.size, const Size.square(240));
      expect(circle.left, card.left - 70);
      expect(circle.top, card.top - 90);
      await unmount(tester);
    });
  });

  // -------------------------------------------------------------------------
  // Friends
  // -------------------------------------------------------------------------
  group('Friends (R8 chips, R7 neutral, brand avatars)', () {
    late FakeFirebaseFirestore db;
    late MockFirebaseAuth auth;

    setUp(() async {
      db = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me));
      await _seedFriends(db);
    });

    Future<MessageService> pumpFriends(
      WidgetTester tester, {
      required ThemeData theme,
      bool highContrast = false,
    }) async {
      _useSize(tester, const Size(390, 1400));
      final messages = MessageService(firestore: db, auth: auth);
      await tester.pumpWidget(
        _localized(
          FriendsScreen(
            showRequestsInitially: false,
            friendService: FriendService(
              firestore: db,
              auth: auth,
              mutationInvoker: _noMutation,
            ),
            messageService: messages,
            socialGraphService: _StubGraph(),
            firestore: db,
            auth: auth,
          ),
          theme: theme,
          highContrast: highContrast,
        ),
      );
      await _pumps(tester);
      return messages;
    }

    Future<void> unmount(WidgetTester tester, MessageService messages) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await messages.dispose();
    }

    ({Container chip, AccessibleTapRegion region, Text text}) chip(
      WidgetTester tester,
      String label,
    ) {
      final text = find.text(label);
      return (
        chip: tester.widget<Container>(
          find.ancestor(of: text, matching: find.byType(Container)).first,
        ),
        region: tester.widget<AccessibleTapRegion>(
          find.ancestor(of: text, matching: find.byType(AccessibleTapRegion)),
        ),
        text: tester.widget<Text>(text),
      );
    }

    for (final (theme, palette, label) in [
      (AppTheme.darkTheme, AppPalette.dark, 'Dark'),
      (AppTheme.lightTheme, AppPalette.light, 'Pearl'),
    ]) {
      testWidgets('$label chips: 36 in 48, ink inversion when selected', (
        tester,
      ) async {
        final messages = await pumpFriends(tester, theme: theme);

        final all = chip(tester, 'Wszyscy');
        final allDecoration = all.chip.decoration! as BoxDecoration;
        expect(allDecoration.color, palette.textPrimary);
        expect(allDecoration.border, isNull);
        expect(all.text.style!.color, palette.background);
        expect(all.text.style!.fontWeight, FontWeight.w700);
        expect(all.region.selected, isTrue);
        expect(all.region.selectedBorderColor, Colors.transparent);

        final online = chip(tester, 'Online');
        final onlineDecoration = online.chip.decoration! as BoxDecoration;
        expect(onlineDecoration.color, Colors.transparent);
        expect(
          (onlineDecoration.border! as Border).top.color,
          palette.hairlineControl,
        );
        expect(online.text.style!.color, palette.textSecondary);
        expect(online.text.style!.fontWeight, FontWeight.w600);
        expect(online.text.style!.fontSize, 13);

        final onlineText = find.text('Online');
        final visual = tester.getSize(
          find.ancestor(of: onlineText, matching: find.byType(Container)).first,
        );
        expect(visual.height, 36);
        final target = tester.getSize(
          find.ancestor(
            of: onlineText,
            matching: find.byType(AccessibleTapRegion),
          ),
        );
        expect(target.height, greaterThanOrEqualTo(48));
        expect(target.width, greaterThanOrEqualTo(48));

        await tester.tap(onlineText);
        await _pumps(tester, 4);
        expect(
          (chip(tester, 'Online').chip.decoration! as BoxDecoration).color,
          palette.textPrimary,
        );
        expect(
          (chip(tester, 'Wszyscy').chip.decoration! as BoxDecoration).color,
          Colors.transparent,
        );
        expect(tester.takeException(), isNull);
        await unmount(tester, messages);
      });

      testWidgets('$label rows: glass message disc, brand avatars, canvas', (
        tester,
      ) async {
        final messages = await pumpFriends(tester, theme: theme);

        final message = find.byTooltip('Wiadomość').first;
        final button = tester.widget<IconButton>(
          find.ancestor(of: message, matching: find.byType(IconButton)).first,
        );
        expect(
          button.style!.backgroundColor!.resolve(<WidgetState>{}),
          palette.glass,
        );
        expect(
          button.style!.side!.resolve(<WidgetState>{})!.color,
          palette.hairlineControl,
        );
        expect(
          button.style!.shape!.resolve(<WidgetState>{}),
          isA<CircleBorder>(),
        );
        expect((button.icon as Icon).icon, AppIcons.chat);

        final avatars = tester.widgetList<UserAvatar>(find.byType(UserAvatar));
        expect(avatars, isNotEmpty);
        expect(
          avatars.every((avatar) => avatar.finish == UserAvatarFinish.brand),
          isTrue,
          reason: 'friend rows and suggestions use the R10 brand finish',
        );

        final canvas = tester.widget<YoPageBackground>(
          find.byKey(const ValueKey('friends-canvas')),
        );
        expect(
          (canvas.decoration! as BoxDecoration).gradient,
          palette.canvasGlow(theme.colorScheme.primary),
        );
        await unmount(tester, messages);
      });
    }

    testWidgets('large text: the chip fills its target and never overflows', (
      tester,
    ) async {
      _useSize(tester, const Size(390, 1400));
      final messages = MessageService(firestore: db, auth: auth);
      await tester.pumpWidget(
        _localized(
          FriendsScreen(
            showRequestsInitially: false,
            friendService: FriendService(
              firestore: db,
              auth: auth,
              mutationInvoker: _noMutation,
            ),
            messageService: messages,
            socialGraphService: _StubGraph(),
            firestore: db,
            auth: auth,
          ),
          theme: AppTheme.darkTheme,
          textScaler: const TextScaler.linear(2),
        ),
      );
      await _pumps(tester);
      final text = find.text('Online');
      final visual = tester.getSize(
        find.ancestor(of: text, matching: find.byType(Container)).first,
      );
      expect(visual.height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
      await unmount(tester, messages);
    });
    testWidgets('high contrast: flat chips and disc on borderStrong', (
      tester,
    ) async {
      final theme = AppTheme.darkHighContrastTheme;
      final palette = theme.extension<AppPalette>()!;
      final messages = await pumpFriends(
        tester,
        theme: theme,
        highContrast: true,
      );
      final online = chip(tester, 'Online').chip.decoration! as BoxDecoration;
      expect(online.color, palette.surface);
      expect((online.border! as Border).top.color, palette.borderStrong);
      final all = chip(tester, 'Wszyscy').chip.decoration! as BoxDecoration;
      expect(all.color, palette.textPrimary, reason: 'the inversion stays');

      final message = find.byTooltip('Wiadomość').first;
      final button = tester.widget<IconButton>(
        find.ancestor(of: message, matching: find.byType(IconButton)).first,
      );
      expect(
        button.style!.backgroundColor!.resolve(<WidgetState>{}),
        palette.surface,
      );
      expect(
        button.style!.side!.resolve(<WidgetState>{})!.color,
        palette.borderStrong,
      );
      final canvas = tester.widget<YoPageBackground>(
        find.byKey(const ValueKey('friends-canvas')),
      );
      expect(canvas.decoration, isNull);
      await unmount(tester, messages);
    });

    testWidgets('chip hover lays glass; a press lets go once a drag starts', (
      tester,
    ) async {
      const palette = AppPalette.dark;
      final messages = await pumpFriends(tester, theme: AppTheme.darkTheme);
      Color? fill() =>
          (chip(tester, 'Online').chip.decoration! as BoxDecoration).color;

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Online')));
      await tester.pump();
      expect(fill(), palette.glass);
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(fill(), Colors.transparent);

      final touch = await tester.startGesture(
        tester.getCenter(find.text('Online')),
      );
      await tester.pump();
      expect(fill(), palette.textPrimary.withValues(alpha: .10));
      // Within the slop the press holds (a tap may still follow)…
      await touch.moveBy(const Offset(-(kTouchSlop / 2), 0));
      await tester.pump();
      expect(fill(), palette.textPrimary.withValues(alpha: .10));
      // …past it the row scrolls and no tap can follow: the fill lets go.
      await touch.moveBy(const Offset(-40, 0));
      await tester.pump();
      expect(fill(), Colors.transparent);
      await touch.up();
      await _pumps(tester, 4);
      expect(
        (chip(tester, 'Wszyscy').chip.decoration! as BoxDecoration).color,
        palette.textPrimary,
        reason: 'a drag selects nothing',
      );
      await unmount(tester, messages);
    });

    for (final (theme, palette, label) in [
      (AppTheme.darkTheme, AppPalette.dark, 'Dark'),
      (AppTheme.lightTheme, AppPalette.light, 'Pearl'),
    ]) {
      testWidgets('$label keyboard focus rings a friend row at radius 16', (
        tester,
      ) async {
        final messages = await pumpFriends(tester, theme: theme);
        final ring = find.byKey(const ValueKey('friend-row-focus-ring'));
        expect(ring, findsNothing);
        for (var tab = 0; tab < 30 && ring.evaluate().isEmpty; tab++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        expect(ring, findsOneWidget, reason: 'Tab reaches a friend row');
        final decoration =
            tester.widget<DecoratedBox>(ring).decoration as BoxDecoration;
        expect(decoration.borderRadius, AppRadius.tile);
        expect((decoration.border! as Border).top.color, palette.focus);
        expect((decoration.border! as Border).top.width, 2);
        final row = find.ancestor(of: ring, matching: find.byType(Stack)).first;
        expect(tester.getRect(ring), tester.getRect(row));
        // Moving on to the row's own message button hands the ring over.
        final before = tester.getRect(ring);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focused = FocusManager.instance.primaryFocus!.context!;
        expect(
          before.contains(tester.getCenter(find.byWidget(focused.widget))),
          isTrue,
          reason: 'Tab moves on to a button inside the same row',
        );
        expect(
          ring,
          findsNothing,
          reason:
              'the row lets go of its ring while a button inside it '
              'shows its own',
        );
        await unmount(tester, messages);
      });
    }

    testWidgets('390: the chip row scrolls under the screen edge, not the '
        'content gutter', (tester) async {
      final messages = await pumpFriends(tester, theme: AppTheme.darkTheme);
      final scroller = find.ancestor(
        of: find.text('Wszyscy'),
        matching: find.byType(SingleChildScrollView),
      );
      final view = tester.widget<SingleChildScrollView>(scroller.first);
      expect(view.scrollDirection, Axis.horizontal);
      expect(view.padding, const EdgeInsets.symmetric(horizontal: 18));
      final viewport = tester.getRect(scroller.first);
      expect(viewport.left, 0);
      expect(viewport.right, 390);
      // The first chip still starts on the 18 px gutter.
      final first = find.ancestor(
        of: find.text('Wszyscy'),
        matching: find.byType(AccessibleTapRegion),
      );
      expect(tester.getRect(first).left, 18);
      await unmount(tester, messages);
    });
  });

  group('Friend suggestion "Dodaj" (R7 neutral)', () {
    Widget card(
      ThemeData theme, {
      FriendRelationshipStatus? status,
      bool processing = false,
    }) => _localized(
      Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: FriendSuggestionCard(
              suggestion: const SuggestedFriend(
                uid: 'riley',
                displayName: 'Riley',
                photoUrl: null,
                mutualCount: 2,
              ),
              isProcessing: processing,
              relationshipStatus: status,
              onPressed: () {},
            ),
          ),
        ),
      ),
      theme: theme,
    );

    for (final (theme, palette, label) in [
      (AppTheme.darkTheme, AppPalette.dark, 'Dark'),
      (AppTheme.lightTheme, AppPalette.light, 'Pearl'),
    ]) {
      testWidgets('$label: glass add action; sent keeps its status colour', (
        tester,
      ) async {
        await tester.pumpWidget(card(theme));
        await tester.pump();
        var button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(
          button.style!.backgroundColor!.resolve(<WidgetState>{}),
          palette.glass,
        );
        expect(
          button.style!.foregroundColor!.resolve(<WidgetState>{}),
          palette.interactiveForeground,
        );
        expect(
          button.style!.side!.resolve(<WidgetState>{})!.color,
          palette.hairlineControl,
        );
        expect(find.byType(UserAvatar), findsOneWidget);
        expect(
          tester.widget<UserAvatar>(find.byType(UserAvatar)).finish,
          UserAvatarFinish.brand,
        );

        await tester.pumpWidget(
          card(theme, status: FriendRelationshipStatus.requestSent),
        );
        await tester.pump();
        button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(
          button.style!.backgroundColor!.resolve(<WidgetState>{
            WidgetState.disabled,
          }),
          palette.warningSurface,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('high contrast: the add action is flat on borderStrong', (
      tester,
    ) async {
      final theme = AppTheme.lightHighContrastTheme;
      final palette = theme.extension<AppPalette>()!;
      await tester.pumpWidget(
        _localized(
          Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: FriendSuggestionCard(
                  suggestion: const SuggestedFriend(
                    uid: 'riley',
                    displayName: 'Riley',
                    photoUrl: null,
                    mutualCount: 2,
                  ),
                  isProcessing: false,
                  relationshipStatus: null,
                  onPressed: () {},
                ),
              ),
            ),
          ),
          theme: theme,
          highContrast: true,
        ),
      );
      await tester.pump();
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      for (final states in <Set<WidgetState>>[
        <WidgetState>{},
        <WidgetState>{WidgetState.hovered},
        <WidgetState>{WidgetState.pressed},
      ]) {
        expect(
          button.style!.backgroundColor!.resolve(states),
          palette.surface,
          reason: '$states',
        );
        expect(
          button.style!.side!.resolve(states)!.color,
          palette.borderStrong,
          reason: '$states',
        );
      }
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('blocked users use the brand avatar finish', (tester) async {
    _useSize(tester, const Size(768, 1024));
    final db = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me));
    await db
        .collection('users')
        .doc(_me)
        .collection('blocked')
        .doc('blocked-user')
        .set({'blockedAt': DateTime.now()});
    await db.collection('publicProfiles').doc('blocked-user').set({
      'uid': 'blocked-user',
      'displayName': 'Blocked Person',
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: BlockedUsersScreen(
          friendService: FriendService(
            firestore: db,
            auth: auth,
            mutationInvoker: _noMutation,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<UserAvatar>(find.byType(UserAvatar)).finish,
      UserAvatarFinish.brand,
    );
  });

  // -------------------------------------------------------------------------
  // Notifications
  // -------------------------------------------------------------------------
  group('Notifications (system sender logo, brand avatars)', () {
    testWidgets('only an actor-less system notice shows the bare logo', (
      tester,
    ) async {
      _useSize(tester, const Size(390, 1600));
      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: _me),
      );
      final now = DateTime.now();
      Future<void> seed(
        String id,
        String type,
        String actorId,
        String actorName,
        Duration age,
      ) => db
          .collection('users')
          .doc(_me)
          .collection('notifications')
          .doc(id)
          .set(<String, dynamic>{
            'type': type,
            'actorId': actorId,
            'actorName': actorName,
            'actorPhotoUrl': null,
            'targetId': null,
            'targetLabel': type == 'system' ? 'Nowe zasady' : null,
            'isRead': false,
            'createdAt': Timestamp.fromDate(now.subtract(age)),
            'dedupeKey': id,
            'bellSuppressed': false,
          });
      await seed('sys', 'system', '', '', const Duration(minutes: 1));
      await seed(
        'sys-person',
        'system',
        'ola',
        'Ola Nowak',
        const Duration(minutes: 2),
      );
      await seed(
        'follow',
        'follow',
        'kuba',
        'Kuba',
        const Duration(minutes: 3),
      );

      final notifications = NotificationService(firestore: db, auth: auth);
      final messages = MessageService(
        firestore: db,
        auth: auth,
        notificationService: notifications,
      );
      await tester.pumpWidget(
        _localized(
          NotificationsScreen(
            isRootTab: true,
            acknowledgeOnVisible: false,
            friendService: FriendService(
              firestore: db,
              auth: auth,
              mutationInvoker: _noMutation,
            ),
            messageService: messages,
            notificationService: notifications,
            currentUserId: _me,
            firestore: db,
            auth: auth,
          ),
          theme: AppTheme.darkTheme,
        ),
      );
      await _pumps(tester);

      final logo = find.byKey(
        const ValueKey('notification-system-sender-logo'),
      );
      expect(logo, findsOneWidget);
      final mark = tester.widget<YoBrandMark>(logo);
      expect(mark.size, 40);
      expect(mark.light, YoBrandLight.none);
      expect(
        tester.getSize(
          find.ancestor(of: logo, matching: find.byType(SizedBox)).first,
        ),
        const Size(44, 44),
      );
      // The person-sent system notice keeps its avatar and its type badge;
      // the logo row carries no badge over the mark.
      expect(find.byIcon(Icons.info_rounded), findsOneWidget);

      final avatars = tester.widgetList<UserAvatar>(find.byType(UserAvatar));
      expect(avatars, hasLength(2));
      expect(
        avatars.every((avatar) => avatar.finish == UserAvatarFinish.brand),
        isTrue,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await messages.dispose();
    });

    for (final (theme, highContrast, label) in [
      (AppTheme.darkTheme, false, 'Dark'),
      (AppTheme.lightTheme, false, 'Pearl'),
      (AppTheme.darkHighContrastTheme, true, 'Dark high contrast'),
      (AppTheme.lightHighContrastTheme, true, 'Pearl high contrast'),
    ]) {
      testWidgets('$label: shared canvas, flat cards, AA mark-all action', (
        tester,
      ) async {
        _useSize(tester, const Size(390, 1600));
        final palette = theme.extension<AppPalette>()!;
        final db = FakeFirebaseFirestore();
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: _me),
        );
        final now = DateTime.now();
        for (final (id, read) in const [('unread', false), ('read', true)]) {
          await db
              .collection('users')
              .doc(_me)
              .collection('notifications')
              .doc(id)
              .set(<String, dynamic>{
                'type': 'follow',
                'actorId': 'kuba-$id',
                'actorName': 'Kuba',
                'actorPhotoUrl': null,
                'targetId': null,
                'targetLabel': null,
                'isRead': read,
                'createdAt': Timestamp.fromDate(now),
                'dedupeKey': id,
                'bellSuppressed': false,
              });
        }
        await db
            .collection('users')
            .doc(_me)
            .collection('friendRequests')
            .doc('ola')
            .set(<String, dynamic>{
              'senderId': 'ola',
              'senderName': 'Ola',
              'senderPhotoUrl': null,
              'createdAt': Timestamp.now(),
            });
        final notifications = NotificationService(firestore: db, auth: auth);
        final messages = MessageService(
          firestore: db,
          auth: auth,
          notificationService: notifications,
        );
        await tester.pumpWidget(
          _localized(
            NotificationsScreen(
              isRootTab: true,
              acknowledgeOnVisible: false,
              friendService: FriendService(
                firestore: db,
                auth: auth,
                mutationInvoker: _noMutation,
              ),
              messageService: messages,
              notificationService: notifications,
              currentUserId: _me,
              firestore: db,
              auth: auth,
            ),
            theme: theme,
            highContrast: highContrast,
          ),
        );
        await _pumps(tester);

        final canvas = tester.widget<YoPageBackground>(
          find.byKey(const ValueKey('notifications-background')),
        );
        if (highContrast) {
          expect(canvas.decoration, isNull);
        } else {
          expect(
            (canvas.decoration! as BoxDecoration).gradient,
            palette.canvasGlow(theme.colorScheme.primary),
          );
        }

        final markAll = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('notifications-mark-all-read')),
            matching: find.byType(Text),
          ),
        );
        expect(markAll.style!.color, palette.interactiveForeground);

        Color edgeOf(Finder card) {
          final box = tester
              .widgetList<Container>(
                find.descendant(
                  of: card,
                  matching: find.byType(Container),
                  matchRoot: true,
                ),
              )
              .map((container) => container.decoration)
              .whereType<BoxDecoration>()
              .firstWhere(
                (decoration) =>
                    decoration.border is Border &&
                    decoration.borderRadius == BorderRadius.circular(12),
              );
          return (box.border! as Border).top.color;
        }

        final request = find.byKey(
          const ValueKey('notification-request-card-ola'),
        );
        expect(request, findsOneWidget);
        final unread = find.ancestor(
          of: find.byKey(const ValueKey('notification-title-unread')),
          matching: find.byType(InkWell),
        );
        final read = find.ancestor(
          of: find.byKey(const ValueKey('notification-title-read')),
          matching: find.byType(InkWell),
        );
        if (highContrast) {
          expect(edgeOf(request), palette.borderStrong);
          expect(edgeOf(read.first), palette.borderStrong);
          expect(edgeOf(unread.first), palette.interactiveForeground);
        } else {
          expect(edgeOf(request), palette.border);
          expect(edgeOf(read.first), palette.border);
          expect(
            edgeOf(unread.first),
            theme.colorScheme.primary.withValues(alpha: .55),
          );
        }
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        await messages.dispose();
      });
    }
  });

  testWidgets('200 % text never breaks the Notifications title mid-word', (
    tester,
  ) async {
    _useSize(tester, const Size(390, 844));
    final db = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me));
    final notifications = NotificationService(firestore: db, auth: auth);
    final messages = MessageService(
      firestore: db,
      auth: auth,
      notificationService: notifications,
    );
    await tester.pumpWidget(
      _localized(
        NotificationsScreen(
          acknowledgeOnVisible: false,
          friendService: FriendService(
            firestore: db,
            auth: auth,
            mutationInvoker: _noMutation,
          ),
          messageService: messages,
          notificationService: notifications,
          currentUserId: _me,
          firestore: db,
          auth: auth,
        ),
        theme: AppTheme.lightTheme,
        textScaler: const TextScaler.linear(2),
      ),
    );
    await _pumps(tester);
    final title = find.text('Powiadomienia');
    // One line of 22 px × 2 at height 1.15 is ≈ 51 px; a mid-word wrap
    // would make it two.
    expect(tester.getSize(title).height, lessThan(22 * 2 * 1.15 * 1.5));
    expect(tester.getRect(title).right, lessThanOrEqualTo(390));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await messages.dispose();
  });

  // -------------------------------------------------------------------------
  // Find creators
  // -------------------------------------------------------------------------
  testWidgets('Find creators chips: R8 on the immersive canvas', (
    tester,
  ) async {
    _useSize(tester, const Size(390, 844));
    final db = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me));
    await tester.pumpWidget(
      _localized(
        FindCreatorsScreen(
          isRootTab: true,
          directoryService: CreatorDirectoryService(
            searchInvoker: (_) async => const <String, dynamic>{
              'profiles': <Object>[],
            },
          ),
          followService: FollowService(
            firestore: db,
            auth: auth,
            mutationInvoker: (_) async => const <String, dynamic>{},
          ),
        ),
        theme: AppTheme.lightTheme,
      ),
    );
    await tester.pump();

    // The screen is always the immersive dark surface.
    const palette = AppPalette.dark;
    Container visual(String key) => tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(Container),
          )
          .first,
    );
    final all = visual('creator-filter-all').decoration! as BoxDecoration;
    expect(all.color, palette.textPrimary);
    expect(all.border, isNull);
    final verified =
        visual('creator-filter-verified').decoration! as BoxDecoration;
    expect(verified.color, Colors.transparent);
    expect((verified.border! as Border).top.color, palette.hairlineControl);

    final region = tester.widget<AccessibleTapRegion>(
      find.byKey(const ValueKey('creator-filter-all')),
    );
    expect(region.selectedBorderColor, Colors.transparent);
    final target = tester.getSize(
      find.byKey(const ValueKey('creator-filter-all')),
    );
    expect(target.height, greaterThanOrEqualTo(48));
    final chipSize = tester.getSize(
      find
          .descendant(
            of: find.byKey(const ValueKey('creator-filter-all')),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(chipSize.height, 36);
    // Shrink-wrapped to its label (14 px each side), never stretched
    // across the Wrap's width.
    final labelWidth = tester.getSize(find.text('Wszyscy twórcy')).width;
    expect(chipSize.width, labelWidth + 2 * AppFinish.chipPaddingH);
    expect(target.width, chipSize.width);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Find creators chips under high contrast: borderStrong', (
    tester,
  ) async {
    _useSize(tester, const Size(390, 844));
    final db = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me));
    await tester.pumpWidget(
      _localized(
        FindCreatorsScreen(
          isRootTab: true,
          directoryService: CreatorDirectoryService(
            searchInvoker: (_) async => const <String, dynamic>{
              'profiles': <Object>[],
            },
          ),
          followService: FollowService(
            firestore: db,
            auth: auth,
            mutationInvoker: (_) async => const <String, dynamic>{},
          ),
        ),
        theme: AppTheme.darkHighContrastTheme,
        highContrast: true,
      ),
    );
    await tester.pump();
    final region = find.byKey(const ValueKey('creator-filter-verified'));
    final palette = AppPalette.of(tester.element(region));
    final verified =
        tester
                .widget<Container>(
                  find
                      .descendant(of: region, matching: find.byType(Container))
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect(verified.color, palette.surface);
    expect((verified.border! as Border).top.color, palette.borderStrong);
    expect(tester.takeException(), isNull);
  });

  // -------------------------------------------------------------------------
  // Source ratchets for the batch's call sites
  // -------------------------------------------------------------------------
  test('every avatar in the batch opts into the brand finish', () {
    for (final path in const [
      'lib/features/friends/presentation/screens/friends_screen.dart',
      'lib/features/friends/presentation/screens/add_friend_screen.dart',
      'lib/features/friends/presentation/screens/blocked_users_screen.dart',
      'lib/features/friends/presentation/widgets/friend_suggestion_card.dart',
      'lib/features/profile/presentation/screens/follow_list_screen.dart',
      'lib/features/notifications/presentation/screens/notifications_screen.dart',
      'lib/features/settings/presentation/screens/settings_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      final calls = RegExp(r'\bUserAvatar\(').allMatches(source).length;
      final brand = RegExp(
        r'finish:\s*UserAvatarFinish\.brand',
      ).allMatches(source).length;
      expect(calls, greaterThan(0), reason: path);
      expect(brand, calls, reason: '$path: every UserAvatar is brand');
    }
  });

  test('the batch keeps the w700 weight cap', () {
    for (final path in const [
      'lib/features/home/presentation/widgets/more_sheet.dart',
      'lib/features/settings/presentation/screens/settings_screen.dart',
      'lib/features/friends/presentation/screens/friends_screen.dart',
      'lib/features/friends/presentation/screens/add_friend_screen.dart',
      'lib/features/friends/presentation/screens/blocked_users_screen.dart',
      'lib/features/friends/presentation/widgets/friend_suggestion_card.dart',
      'lib/features/profile/presentation/screens/follow_list_screen.dart',
      'lib/features/creator/presentation/screens/find_creators_screen.dart',
      'lib/features/notifications/presentation/screens/notifications_screen.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        isNot(contains(RegExp(r'FontWeight\.w[89]00'))),
        reason: path,
      );
    }
  });

  test('AppFinish chip geometry is what the chips read', () {
    expect(AppFinish.chipHeight, 36);
    expect(AppFinish.chipPaddingH, 14);
    expect(AppFinish.chipFontSize, 13);
  });
}
