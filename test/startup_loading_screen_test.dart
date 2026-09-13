import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/translations_startup.dart';
import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/features/auth/presentation/screens/auth_gate.dart';
import 'package:yovoice/features/auth/presentation/screens/login_screen.dart';
import 'package:yovoice/features/auth/presentation/widgets/startup_loading_screen.dart';
import 'package:yovoice/features/auth/providers/auth_provider.dart';

const _headline = ValueKey('startup-headline');
const _hairline = ValueKey('startup-bottom-hairline');

class _FakeFirebaseApp extends FirebaseAppPlatform {
  _FakeFirebaseApp()
    : super(
        defaultFirebaseAppName,
        const FirebaseOptions(
          apiKey: 'startup-test-key',
          appId: 'startup-test-app',
          messagingSenderId: 'startup-test-sender',
          projectId: 'startup-test-project',
        ),
      );
}

class _FakeFirebasePlatform extends FirebasePlatform {
  final _app = _FakeFirebaseApp();

  @override
  List<FirebaseAppPlatform> get apps => [_app];

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _app;

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async => _app;
}

Widget _startupHost({
  Locale locale = const Locale('en'),
  String? headlineKey = 'Where conversation begins.',
  double textScale = 1,
  bool disableAnimations = false,
  bool accessibleNavigation = false,
  bool highContrast = false,
  bool boldText = false,
  bool tickersEnabled = true,
  bool offstage = false,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
        accessibleNavigation: accessibleNavigation,
        highContrast: highContrast,
        boldText: boldText,
      ),
      child: TickerMode(
        enabled: tickersEnabled,
        child: Offstage(
          offstage: offstage,
          child: StartupLoadingScreen(headlineKey: headlineKey),
        ),
      ),
    ),
  ),
);

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Rect _paintedRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

List<double> _backgroundTransform(WidgetTester tester) => tester
    .widget<Transform>(
      find.byKey(
        const ValueKey('startup-background-drift'),
        skipOffstage: false,
      ),
    )
    .transform
    .storage
    .toList();

Future<List<int>> _paintedHairline(WidgetTester tester) async {
  final finder = find.byKey(_hairline, skipOffstage: false);
  final painter = tester.widget<CustomPaint>(finder).painter!;
  final size = tester.getSize(finder);
  return (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    painter.paint(ui.Canvas(recorder), size);
    final picture = recorder.endRecording();
    final frame = await picture.toImage(size.width.ceil(), size.height.ceil());
    try {
      final bytes = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
      return bytes!.buffer.asUint8List().toList();
    } finally {
      frame.dispose();
      picture.dispose();
    }
  }))!;
}

/// Rasterize the production mask's shader, not a guessed animation phase.
Future<List<int>> _paintedBackgroundLight(WidgetTester tester) async {
  final mask = tester.widget<ShaderMask>(
    find.byKey(const ValueKey('startup-background-light'), skipOffstage: false),
  );
  return (await tester.runAsync(() async {
    const bounds = Rect.fromLTWH(0, 0, 96, 96);
    final recorder = ui.PictureRecorder();
    ui.Canvas(
      recorder,
    ).drawRect(bounds, ui.Paint()..shader = mask.shaderCallback(bounds));
    final picture = recorder.endRecording();
    final frame = await picture.toImage(96, 96);
    try {
      final bytes = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
      return bytes!.buffer.asUint8List().toList();
    } finally {
      frame.dispose();
      picture.dispose();
    }
  }))!;
}

List<SemanticsData> _semanticsTree(WidgetTester tester) {
  final result = <SemanticsData>[];
  void visit(SemanticsNode node) {
    result.add(node.getSemanticsData());
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  void visitOwner(PipelineOwner owner) {
    final root = owner.semanticsOwner?.rootSemanticsNode;
    if (root != null) visit(root);
    owner.visitChildren(visitOwner);
  }

  visitOwner(tester.binding.rootPipelineOwner);
  return result;
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeFirebasePlatform();
    await Firebase.initializeApp();
  });

  test(
    'native launch surfaces use the real mark and the Flutter background',
    () {
      final iosAssets = [
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png',
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png',
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png',
      ];
      for (var index = 0; index < iosAssets.length; index++) {
        final path = iosAssets[index];
        final decoded = image.decodePng(File(path).readAsBytesSync());
        expect(decoded, isNotNull, reason: path);
        expect(decoded!.width, 170 * (index + 1), reason: path);
        expect(decoded.height, 170 * (index + 1), reason: path);
      }

      for (final path in [
        'android/app/src/main/res/drawable/launch_background.xml',
        'android/app/src/main/res/drawable-v21/launch_background.xml',
      ]) {
        final source = File(path).readAsStringSync();
        expect(source, contains('@color/splash_background'), reason: path);
        expect(source, contains('@mipmap/launch_image'), reason: path);
      }
      for (final path in [
        'android/app/src/main/res/values-v31/styles.xml',
        'android/app/src/main/res/values-night-v31/styles.xml',
      ]) {
        final android12 = File(path).readAsStringSync();
        expect(
          android12,
          contains('windowSplashScreenBackground'),
          reason: path,
        );
        expect(
          android12,
          contains('windowSplashScreenAnimatedIcon'),
          reason: path,
        );
      }
      final webLaunch = File('web/index.html').readAsStringSync();
      expect(webLaunch, isNot(contains('id="yovoice-bootstrap"')));
      expect(webLaunch, contains('background-color: #0D0618;'));
    },
  );

  for (final size in const [
    Size(320, 568),
    Size(390, 844),
    Size(430, 932),
    Size(768, 1024),
    Size(1100, 900),
    Size(1440, 900),
    Size(2560, 1440),
  ]) {
    testWidgets(
      'approved startup composition fits ${size.width}x${size.height}',
      (tester) async {
        _setViewport(tester, size);
        await tester.pumpWidget(_startupHost());
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('YO VOICE'), findsOneWidget);
        expect(find.text('Where conversation begins.'), findsOneWidget);
        expect(find.text('Opening YO Voice'), findsOneWidget);
        expect(find.byKey(_hairline), findsOneWidget);
        final logoRect = tester.getRect(
          find.byKey(const ValueKey('startup-logo')),
        );
        final titleRect = tester.getRect(
          find.byKey(const ValueKey('startup-title')),
        );
        final headlineRect = tester.getRect(find.byKey(_headline));
        final title = tester.widget<Text>(
          find.byKey(const ValueKey('startup-title')),
        );
        final headline = tester.widget<Text>(find.byKey(_headline));
        expect(
          headline.style!.fontSize,
          lessThan(title.style!.fontSize!),
          reason:
              'the headline is supporting copy below the prominent wordmark',
        );
        expect(
          headline.style!.fontWeight!.value,
          lessThan(title.style!.fontWeight!.value),
        );
        final artOpacity = tester.widget<Opacity>(
          find.ancestor(
            of: find.byKey(const ValueKey('startup-background-art')),
            matching: find.byType(Opacity),
          ),
        );
        expect(artOpacity.opacity, greaterThan(0));
        expect(artOpacity.opacity, lessThanOrEqualTo(.65));
        final statusRect = tester.getRect(
          find.byKey(const ValueKey('startup-status-label')),
        );
        expect(logoRect.left, greaterThanOrEqualTo(0));
        expect(logoRect.right, lessThanOrEqualTo(size.width));
        expect(logoRect.top, greaterThanOrEqualTo(0));
        expect(titleRect.top, greaterThan(logoRect.top));
        expect(headlineRect.top, greaterThan(titleRect.bottom));
        expect(statusRect.top, greaterThan(headlineRect.bottom));
        expect(statusRect.bottom, lessThanOrEqualTo(size.height));
        expect(headlineRect.left, greaterThanOrEqualTo(16));
        expect(headlineRect.right, lessThanOrEqualTo(size.width - 16));
        expect(
          headlineRect.width,
          lessThanOrEqualTo(
            size.width < 600 ? 340 : (size.width < 1100 ? 520 : 560),
          ),
          reason:
              'desktop copy is bounded rather than stretched across the window',
        );
        expect(
          tester.getSize(find.byKey(_hairline)).width,
          size.width < 600 ? 120 : 160,
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('startup-background'))),
          Offset.zero & size,
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Create your space'), findsNothing);
        expect(find.byKey(const ValueKey('startup-sound-wave')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'first Flutter frame preserves native 170px centered logo then settles',
    (tester) async {
      const size = Size(390, 844);
      _setViewport(tester, size);
      await tester.pumpWidget(_startupHost());
      final logo = find.byKey(const ValueKey('startup-logo'));
      final first = _paintedRect(tester, logo);
      expect(first.width, closeTo(170, .01));
      expect(first.height, closeTo(170, .01));
      expect(first.center.dx, closeTo(size.width / 2, .01));
      expect(first.center.dy, closeTo(size.height / 2, .01));

      await tester.pump(const Duration(milliseconds: 120));
      final middle = _paintedRect(tester, logo);
      expect(middle.width, greaterThan(170));
      expect(middle.width, lessThan(208));
      expect(middle.center.dy, lessThan(first.center.dy));

      await tester.pump(const Duration(milliseconds: 120));
      final settled = _paintedRect(tester, logo);
      expect(settled.width, closeTo(208, .01));
      expect(settled.center.dy, closeTo(size.height * .43, .01));
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'every startup phrase resolves through the real app catalog in all43 variants',
    () {
      expect(selectableAppLanguages, hasLength(43));
      for (final language in selectableAppLanguages) {
        final copy = AppLocalizations(language.locale!);
        for (final key in startupTranslationKeys) {
          expect(
            copy.text(key, startupTranslations['pl']![key]!),
            startupTranslations[language.localeKey]![key],
            reason: '${language.localeKey}: $key must not fall back to English',
          );
        }
      }
    },
  );

  for (final language in selectableAppLanguages) {
    testWidgets(
      '${language.localeKey} longest startup phrase stays complete at320px/200%',
      (tester) async {
        _setViewport(tester, const Size(320, 568));
        final translations = startupTranslations[language.localeKey]!;
        final longestKey = startupHeadlineTranslationKeys.reduce(
          (left, right) =>
              translations[left]!.runes.length >=
                  translations[right]!.runes.length
              ? left
              : right,
        );
        final expected = translations[longestKey]!;
        await tester.pumpWidget(
          _startupHost(
            locale: language.locale!,
            headlineKey: longestKey,
            textScale: 2,
            disableAnimations: true,
          ),
        );
        await tester.pump();
        final headline = tester.widget<Text>(find.byKey(_headline));
        expect(headline.data, expected);
        expect(headline.maxLines, isNull);
        expect(headline.overflow, isNot(TextOverflow.ellipsis));
        expect(
          headline.textScaler,
          isNull,
          reason: 'readable copy inherits 200% scaling',
        );
        expect(find.text(translations['Opening YO Voice']!), findsOneWidget);
        final titleRect = tester.getRect(
          find.byKey(const ValueKey('startup-title')),
        );
        final headlineRect = tester.getRect(find.byKey(_headline));
        expect(titleRect.left, greaterThanOrEqualTo(0));
        expect(titleRect.right, lessThanOrEqualTo(320));
        expect(headlineRect.left, greaterThanOrEqualTo(16));
        expect(headlineRect.right, lessThanOrEqualTo(304));
        expect(headlineRect.top, greaterThan(titleRect.bottom));
        expect(
          Directionality.of(tester.element(find.byKey(_headline))),
          const {'ar', 'he', 'fa', 'ur'}.contains(language.locale!.languageCode)
              ? TextDirection.rtl
              : TextDirection.ltr,
        );
        // When unusually large copy needs scrolling, the actual status remains
        // reachable and clear of the headline, rather than clipped or shrunk.
        await tester.ensureVisible(
          find.byKey(const ValueKey('startup-status-label')),
        );
        await tester.pump();
        final statusRect = tester.getRect(
          find.byKey(const ValueKey('startup-status-label')),
        );
        expect(statusRect.top, greaterThanOrEqualTo(0));
        expect(statusRect.bottom, lessThanOrEqualTo(568));
        expect(
          statusRect.top,
          greaterThan(tester.getRect(find.byKey(_headline)).bottom),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final locale in [const Locale('pl'), const Locale('ar')]) {
    testWidgets(
      '${locale.languageCode} 200% Bold Text is measured without overlap',
      (tester) async {
        _setViewport(tester, const Size(320, 568));
        await tester.pumpWidget(
          _startupHost(
            locale: locale,
            headlineKey: 'Every connection starts with a hello.',
            textScale: 2,
            boldText: true,
            disableAnimations: true,
          ),
        );
        await tester.pump();
        expect(
          tester.widget<Text>(find.byKey(_headline)).style!.fontWeight,
          FontWeight.w700,
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('startup-title')))
              .style!
              .fontWeight,
          FontWeight.w700,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('startup-status-label')),
        );
        await tester.pump();
        final status = tester.getRect(
          find.byKey(const ValueKey('startup-status-label')),
        );
        expect(
          status.top,
          greaterThan(tester.getRect(find.byKey(_headline)).bottom),
        );
        expect(status.bottom, lessThanOrEqualTo(568));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'launch-selected phrase survives rebuilds and changes only its translation',
    (tester) async {
      _setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(_startupHost(headlineKey: null));
      await tester.pump(const Duration(milliseconds: 300));
      final english = tester.widget<Text>(find.byKey(_headline)).data!;
      expect(startupHeadlineTranslationKeys, contains(english));
      await tester.pump(const Duration(seconds: 14));
      expect(tester.widget<Text>(find.byKey(_headline)).data, english);
      await tester.pumpWidget(
        _startupHost(headlineKey: null, locale: const Locale('pl')),
      );
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(_headline)).data,
        startupTranslations['pl']![english],
      );
      await tester.pumpWidget(_startupHost(headlineKey: null));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(_headline)).data, english);
    },
  );

  testWidgets(
    'ambient artwork and actual hairline paint both move without changing copy',
    (tester) async {
      _setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(_startupHost());
      await tester.pump(const Duration(milliseconds: 300));
      final drift = _backgroundTransform(tester);
      final hairline = await _paintedHairline(tester);
      final light = await _paintedBackgroundLight(tester);
      await tester.pump(const Duration(milliseconds: 480));
      expect(_backgroundTransform(tester), isNot(orderedEquals(drift)));
      expect(await _paintedHairline(tester), isNot(orderedEquals(hairline)));
      expect(
        await _paintedBackgroundLight(tester),
        isNot(orderedEquals(light)),
      );
      expect(find.text('Where conversation begins.'), findsOneWidget);
      expect(find.text('Opening YO Voice'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in [
    'reduced motion',
    'accessible navigation',
    'high contrast',
  ]) {
    testWidgets('$mode stops entrance and ambient motion and can be reversed', (
      tester,
    ) async {
      _setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        _startupHost(
          disableAnimations: mode == 'reduced motion',
          accessibleNavigation: mode == 'accessible navigation',
          highContrast: mode == 'high contrast',
        ),
      );
      await tester.pump();
      final logo = _paintedRect(
        tester,
        find.byKey(const ValueKey('startup-logo')),
      );
      expect(
        logo.width,
        closeTo(208, .01),
        reason: 'static users see the settled layout immediately',
      );
      final drift = _backgroundTransform(tester);
      final line = await _paintedHairline(tester);
      final light = await _paintedBackgroundLight(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(_backgroundTransform(tester), orderedEquals(drift));
      expect(await _paintedHairline(tester), orderedEquals(line));
      expect(await _paintedBackgroundLight(tester), orderedEquals(light));
      expect(tester.binding.transientCallbackCount, 0);
      if (mode == 'high contrast') {
        final text = tester.widget<Text>(find.byKey(_headline));
        expect(text.style!.color, AppImmersiveColors.textPrimary);
        expect(
          find.ancestor(
            of: find.byKey(_headline),
            matching: find.byType(ShaderMask),
          ),
          findsNothing,
        );
        final opacity = tester.widget<Opacity>(
          find.ancestor(
            of: find.byKey(const ValueKey('startup-background-art')),
            matching: find.byType(Opacity),
          ),
        );
        expect(opacity.opacity, lessThanOrEqualTo(.2));
      }

      await tester.pumpWidget(_startupHost());
      await tester.pump(const Duration(milliseconds: 480));
      expect(_backgroundTransform(tester), isNot(orderedEquals(drift)));
      expect(await _paintedHairline(tester), isNot(orderedEquals(line)));
      expect(
        await _paintedBackgroundLight(tester),
        isNot(orderedEquals(light)),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'runtime reduced-motion preference stops an already running animation',
    (tester) async {
      _setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(_startupHost());
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(_startupHost(disableAnimations: true));
      final drift = _backgroundTransform(tester);
      final line = await _paintedHairline(tester);
      final light = await _paintedBackgroundLight(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(_backgroundTransform(tester), orderedEquals(drift));
      expect(await _paintedHairline(tester), orderedEquals(line));
      expect(await _paintedBackgroundLight(tester), orderedEquals(light));
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  for (final lifecycle in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    testWidgets('$lifecycle freezes both effects and foreground resumes them', (
      tester,
    ) async {
      _setViewport(tester, const Size(390, 844));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      await tester.pumpWidget(_startupHost());
      await tester.pump(const Duration(milliseconds: 300));
      tester.binding.handleAppLifecycleStateChanged(lifecycle);
      await tester.pump();
      final drift = _backgroundTransform(tester);
      final line = await _paintedHairline(tester);
      final light = await _paintedBackgroundLight(tester);
      await tester.pump(const Duration(milliseconds: 800));
      expect(_backgroundTransform(tester), orderedEquals(drift));
      expect(await _paintedHairline(tester), orderedEquals(line));
      expect(await _paintedBackgroundLight(tester), orderedEquals(light));
      expect(tester.binding.transientCallbackCount, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_backgroundTransform(tester), isNot(orderedEquals(drift)));
      expect(await _paintedHairline(tester), isNot(orderedEquals(line)));
      expect(
        await _paintedBackgroundLight(tester),
        isNot(orderedEquals(light)),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'an offstage ticker-disabled startup does not keep either animation running',
    (tester) async {
      _setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(_startupHost());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(
        _startupHost(tickersEnabled: false, offstage: true),
      );
      final drift = _backgroundTransform(tester);
      final line = await _paintedHairline(tester);
      final light = await _paintedBackgroundLight(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(_backgroundTransform(tester), orderedEquals(drift));
      expect(await _paintedHairline(tester), orderedEquals(line));
      expect(await _paintedBackgroundLight(tester), orderedEquals(light));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(_startupHost());
      await tester.pump(const Duration(milliseconds: 300));
      expect(_backgroundTransform(tester), isNot(orderedEquals(drift)));
      expect(await _paintedHairline(tester), isNot(orderedEquals(line)));
      expect(
        await _paintedBackgroundLight(tester),
        isNot(orderedEquals(light)),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'startup exposes one localized status and excludes decorative artwork',
    (tester) async {
      _setViewport(tester, const Size(390, 844));
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(_startupHost(locale: const Locale('pl')));
        await tester.pump(const Duration(milliseconds: 300));
        final nodes = _semanticsTree(tester);
        final liveRegions = nodes
            .where((node) => node.flagsCollection.isLiveRegion)
            .toList();
        expect(liveRegions, hasLength(1));
        expect(liveRegions.single.label, 'Otwieranie YO Voice');
        expect(
          nodes.where((node) => node.label == 'Tu zaczyna się rozmowa.'),
          hasLength(1),
        );
        expect(nodes.where((node) => node.flagsCollection.isImage), isEmpty);
        expect(nodes.where((node) => node.label == 'YO VOICE'), isEmpty);
        expect(nodes.where((node) => node.flagsCollection.isButton), isEmpty);
        expect(nodes.where((node) => node.label.contains('%')), isEmpty);
        await tester.pump(const Duration(seconds: 2));
        expect(
          _semanticsTree(
            tester,
          ).where((node) => node.flagsCollection.isLiveRegion),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      } finally {
        // Flutter verifies outstanding handles before package:test tearDowns.
        semantics.dispose();
      }
    },
  );

  for (final locale in const [Locale('pl'), Locale('ar')]) {
    testWidgets(
      '${locale.languageCode} startup language reaches text and platform semantics',
      (tester) async {
        _setViewport(tester, const Size(390, 844));
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(_startupHost(locale: locale));
          await tester.pump(const Duration(milliseconds: 300));
          final headline = tester.widget<Text>(find.byKey(_headline));
          final status = tester.widget<Text>(
            find.byKey(const ValueKey('startup-status-label')),
          );
          expect(headline.locale, locale);
          expect(status.locale, locale);
          final nodes = _semanticsTree(tester);
          final headlineNodes = nodes
              .where((node) => node.label == headline.data)
              .toList();
          final statusNodes = nodes
              .where((node) => node.label == status.data)
              .toList();
          expect(headlineNodes, hasLength(1));
          expect(statusNodes, hasLength(1));
          expect(headlineNodes.single.locale, locale);
          expect(statusNodes.single.locale, locale);
          expect(statusNodes.single.flagsCollection.isLiveRegion, isTrue);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'removing startup during entrance cancels all animation tickers',
    (tester) async {
      _setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(_startupHost());
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pumpWidget(
        const MaterialApp(home: Text('Destination ready')),
      );
      expect(find.byType(StartupLoadingScreen), findsNothing);
      expect(find.text('Destination ready'), findsOneWidget);
      await tester.pump(const Duration(seconds: 13));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('startup wordmark stays on-screen at 320px and 200% text', (
    tester,
  ) async {
    _setViewport(tester, const Size(320, 640));
    await tester.pumpWidget(_startupHost(textScale: 2));
    await tester.pump(const Duration(milliseconds: 300));
    final titleRect = tester.getRect(
      find.byKey(const ValueKey('startup-title')),
    );
    expect(titleRect.left, greaterThanOrEqualTo(0));
    expect(titleRect.right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AuthGate crossfades from startup instead of cutting frames', (
    tester,
  ) async {
    final auth = StreamController<User?>();
    addTearDown(auth.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateChangesProvider.overrideWith((ref) => auth.stream),
        ],
        child: const MaterialApp(home: AuthGate()),
      ),
    );
    expect(find.byType(StartupLoadingScreen), findsOneWidget);

    auth.addError(StateError('diagnostic auth failure'));
    await tester.pump();
    expect(
      find.byType(StartupLoadingScreen),
      findsOneWidget,
      reason: 'the outgoing frame stays mounted during the fade',
    );
    expect(find.text('Something went wrong'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 230));
    expect(find.byType(StartupLoadingScreen), findsNothing);
    expect(find.text('Something went wrong'), findsOneWidget);
  });

  testWidgets(
    'AuthGate guarantees 1.4 s of startup on a normal signed-out launch',
    (tester) async {
      final auth = StreamController<User?>();
      addTearDown(auth.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateChangesProvider.overrideWith((ref) => auth.stream),
          ],
          child: const MaterialApp(home: AuthGate()),
        ),
      );
      auth.add(null);
      await tester.pump();

      expect(find.byType(StartupLoadingScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);

      await tester.pump(
        authGateInitialStartupMinimumVisibility -
            const Duration(milliseconds: 1),
      );
      expect(find.byType(StartupLoadingScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);

      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        find.byType(StartupLoadingScreen),
        findsOneWidget,
        reason: 'the completed minimum ends with the existing short crossfade',
      );

      await tester.pump(const Duration(milliseconds: 230));
      expect(find.byType(StartupLoadingScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Reduce Motion keeps the content hold but removes its crossfade',
    (tester) async {
      final auth = StreamController<User?>();
      addTearDown(auth.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateChangesProvider.overrideWith((ref) => auth.stream),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: const AuthGate(),
              ),
            ),
          ),
        ),
      );
      auth.add(null);
      await tester.pump();
      await tester.pump(
        authGateInitialStartupMinimumVisibility -
            const Duration(milliseconds: 1),
      );
      expect(find.byType(StartupLoadingScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);

      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byType(StartupLoadingScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a later auth operation releases the cold-launch minimum', (
    tester,
  ) async {
    final auth = StreamController<User?>();
    addTearDown(auth.close);
    final container = ProviderContainer(
      overrides: [authStateChangesProvider.overrideWith((ref) => auth.stream)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AuthGate()),
      ),
    );
    container.read(authLoadingProvider.notifier).state = true;
    await tester.pump();
    auth.add(null);
    await tester.pump();

    expect(
      find.byType(LoginScreen),
      findsOneWidget,
      reason: 'a user-driven auth flow must not inherit the cold-start hold',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing AuthGate cancels its pending startup timer', (
    tester,
  ) async {
    final auth = StreamController<User?>();
    addTearDown(auth.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateChangesProvider.overrideWith((ref) => auth.stream),
        ],
        child: const MaterialApp(home: AuthGate()),
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Text('Replacement boundary')),
    );
    await tester.pump(authGateInitialStartupMinimumVisibility);

    expect(find.text('Replacement boundary'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'AuthGate defers profile bootstrap until registration provisioning ends',
    (tester) async {
      final auth = StreamController<User?>();
      addTearDown(auth.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateChangesProvider.overrideWith((ref) => auth.stream),
            authLoadingProvider.overrideWith((ref) => true),
          ],
          child: const MaterialApp(home: AuthGate()),
        ),
      );

      auth.add(MockUser(uid: 'new-account', email: 'chosen.name@example.com'));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('auth-operation-loading')),
        findsOneWidget,
      );
      expect(
        find.byType(StartupLoadingScreen),
        findsWidgets,
        reason:
            'the previous startup frame may still be fading while the '
            'operation-owned frame is already present',
      );
      expect(
        find.text('Finishing your profile'),
        findsNothing,
        reason:
            'ensureProfile must not race the authoritative registration write',
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('authenticated entry has no fixed welcome delay', () {
    final source = File(
      'lib/features/auth/presentation/screens/auth_gate.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('Duration(seconds: 4)')));
    expect(source, isNot(contains('welcome-screen')));
  });
}
