// refine-look B10 (spec §4, §5 W1, §8.7, §10 handoff): the real logo freed
// and lit on Startup, Auth, TOTP and the auth-gate failures; the launch's one
// glint; the auth chain's R5 primary action and the tonal mode-rail tile.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/screens/auth_gate.dart';
import 'package:yovoice/features/auth/presentation/screens/responsive_auth_screen.dart';
import 'package:yovoice/features/auth/presentation/widgets/startup_loading_screen.dart';
import 'package:yovoice/features/auth/providers/auth_provider.dart';
import 'package:yovoice/services/firestore_service.dart';
import 'package:yovoice/shared/widgets/branding/yo_logo.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';

import 'totp_challenge_test_support.dart';

const _startupLogo = ValueKey('startup-logo');
const _startupBloom = ValueKey('startup-logo-bloom');
const _startupGlint = ValueKey('startup-logo-glint');
const _authGlint = ValueKey('auth-logo-glint');

class _FakeFirebaseApp extends FirebaseAppPlatform {
  _FakeFirebaseApp()
    : super(
        defaultFirebaseAppName,
        const FirebaseOptions(
          apiKey: 'refine-test-key',
          appId: 'refine-test-app',
          messagingSenderId: 'refine-test-sender',
          projectId: 'refine-test-project',
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

class _FakeAuthService extends AuthService {
  _FakeAuthService({this.pendingLogin})
    : super(
        firebaseAuth: MockFirebaseAuth(),
        firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      );

  final Completer<UserCredential>? pendingLogin;

  @override
  Future<AppleSignInAvailability> getAppleSignInAvailability() async =>
      AppleSignInAvailability.available;

  @override
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) => pendingLogin!.future;
}

MediaQueryData _media(
  BuildContext context, {
  double textScale = 1,
  bool disableAnimations = false,
  bool highContrast = false,
}) => MediaQuery.of(context).copyWith(
  textScaler: TextScaler.linear(textScale),
  disableAnimations: disableAnimations,
  accessibleNavigation: disableAnimations,
  highContrast: highContrast,
);

Widget _app(
  Widget home, {
  double textScale = 1,
  bool disableAnimations = false,
  bool highContrast = false,
  bool pearl = false,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: pearl ? AppTheme.lightTheme : AppTheme.darkTheme,
  locale: const Locale('pl'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, child) => MediaQuery(
    data: _media(
      context,
      textScale: textScale,
      disableAnimations: disableAnimations,
      highContrast: highContrast,
    ),
    child: child!,
  ),
  home: home,
);

void _viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Rect _painted(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

double _bloomOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find.descendant(
        of: find.byKey(_startupBloom),
        matching: find.byType(Opacity),
      ),
    )
    .opacity;

Future<Uint8List> _rasterBand(
  WidgetTester tester, {
  required double x,
  required Size size,
}) async {
  return (await tester.runAsync(() async {
    final bounds = Offset.zero & size;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      bounds,
      ui.Paint()..shader = LaunchGlint.band(bounds, x: x, alpha: 1),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return bytes!.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }))!;
}

int _brightestColumn(Uint8List rgba, int width, int row) {
  var best = 0;
  var bestAlpha = -1;
  for (var column = 0; column < width; column++) {
    final alpha = rgba[(row * width + column) * 4 + 3];
    if (alpha > bestAlpha) {
      bestAlpha = alpha;
      best = column;
    }
  }
  return best;
}

String? _assetOf(Image image) {
  final provider = image.image;
  final asset = provider is ResizeImage ? provider.imageProvider : provider;
  return asset is AssetImage ? asset.assetName : null;
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeFirebasePlatform();
    await Firebase.initializeApp();
  });

  setUp(LaunchGlint.debugReset);
  tearDown(LaunchGlint.debugReset);

  group('Startup (W1)', () {
    testWidgets('frame 0 is the bare native mark; the bloom rides the '
        'fly-in inside the same transform and fades in with it', (
      tester,
    ) async {
      const size = Size(390, 844);
      _viewport(tester, size);
      await tester.pumpWidget(
        _app(const StartupLoadingScreen(headlineKey: 'Good to hear you.')),
      );

      final mark = _painted(tester, find.byKey(_startupLogo));
      expect(mark.width, closeTo(170, .01));
      expect(mark.center.dx, closeTo(size.width / 2, .01));
      expect(mark.center.dy, closeTo(size.height / 2, .01));
      expect(
        _bloomOpacity(tester),
        0,
        reason: 'frame 0 must equal the native splash: no bloom yet',
      );
      final bloom = _painted(tester, find.byKey(_startupBloom));
      expect(bloom.width, closeTo(170 * 1.5, .01));
      expect(bloom.center.dx, closeTo(mark.center.dx, .01));
      expect(bloom.center.dy, closeTo(mark.center.dy, .01));

      await tester.pump(const Duration(milliseconds: 260));
      final settled = _painted(tester, find.byKey(_startupLogo));
      expect(settled.width, closeTo(208, .01));
      final settledBloom = _painted(tester, find.byKey(_startupBloom));
      expect(settledBloom.width, closeTo(312, .01));
      expect(settledBloom.center.dy, closeTo(settled.center.dy, .01));
      expect(_bloomOpacity(tester), inInclusiveRange(.34, .50));

      final opacities = <double>{};
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 300));
        final value = _bloomOpacity(tester);
        expect(value, inInclusiveRange(.34, .50));
        opacities.add(value);
      }
      expect(
        opacities.length,
        greaterThan(1),
        reason: 'the bloom breathes with the existing 3.6 s breath',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('compact sizes keep 160 / 128 marks with a 1.5x bloom', (
      tester,
    ) async {
      for (final (size, mark) in const [
        (Size(390, 667), 160.0),
        (Size(320, 568), 128.0),
      ]) {
        _viewport(tester, size);
        await tester.pumpWidget(
          _app(
            StartupLoadingScreen(
              key: ValueKey(size),
              headlineKey: 'Good to hear you.',
            ),
            disableAnimations: true,
          ),
        );
        await tester.pump();
        expect(tester.getSize(find.byKey(_startupLogo)), Size(mark, mark));
        expect(
          tester.getSize(find.byKey(_startupBloom)),
          Size(mark * 1.5, mark * 1.5),
        );
      }
    });

    testWidgets('Reduce Motion: a static .42 bloom, no glint, no ticker', (
      tester,
    ) async {
      _viewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        _app(const StartupLoadingScreen(), disableAnimations: true),
      );
      await tester.pump();
      expect(_bloomOpacity(tester), .42);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byKey(_startupGlint), findsNothing);
      }
      expect(_bloomOpacity(tester), .42);
      expect(tester.binding.transientCallbackCount, 0);
      expect(LaunchGlint.spent, isFalse);
    });

    testWidgets('high contrast: no bloom and no glint', (tester) async {
      _viewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        _app(const StartupLoadingScreen(), highContrast: true),
      );
      await tester.pump();
      expect(find.byKey(_startupLogo), findsOneWidget);
      expect(find.byKey(_startupBloom), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(_startupGlint), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      expect(LaunchGlint.spent, isFalse);
    });

    for (final width in const [390.0, 1440.0]) {
      testWidgets('at ${width.toInt()} the glint follows the artwork light '
          'across the logo exactly once and claims the launch', (tester) async {
        _viewport(tester, Size(width, width < 600 ? 844 : 900));
        await tester.pumpWidget(_app(const StartupLoadingScreen()));
        await tester.pump(const Duration(milliseconds: 260));

        final seen = <int>[];
        for (var ms = 0; ms < 4500; ms += 20) {
          await tester.pump(const Duration(milliseconds: 20));
          if (find.byKey(_startupGlint).evaluate().isNotEmpty) seen.add(ms);
        }
        expect(seen, isNotEmpty, reason: 'the first light pass glints');
        expect(LaunchGlint.spent, isTrue);
        final window = seen.last - seen.first;
        expect(
          seen.length,
          (window ~/ 20) + 1,
          reason: 'one continuous pass, never a flicker',
        );
        expect(window, inInclusiveRange(100, 1600));

        // The next passes of the artwork light never glint again.
        for (var ms = 0; ms < 9000; ms += 40) {
          await tester.pump(const Duration(milliseconds: 40));
          expect(find.byKey(_startupGlint), findsNothing);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a startup band claims the launch only at the logo centre '
        'and yields to an earlier sign-in claim for good', (tester) async {
      _viewport(tester, const Size(390, 844));
      await tester.pumpWidget(_app(const StartupLoadingScreen()));
      await tester.pump(const Duration(milliseconds: 260));
      var waited = 0;
      while (find.byKey(_startupGlint).evaluate().isEmpty && waited < 5000) {
        await tester.pump(const Duration(milliseconds: 16));
        waited += 16;
      }
      expect(find.byKey(_startupGlint), findsOneWidget);
      expect(
        LaunchGlint.spent,
        isFalse,
        reason: 'a band still left of the centre has not claimed the launch',
      );
      expect(LaunchGlint.claim(), isTrue, reason: 'the sign-in mark claims');
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(_startupGlint), findsNothing);
      for (var ms = 0; ms < 9000; ms += 50) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byKey(_startupGlint), findsNothing);
      }
    });

    testWidgets('on a cold signed-out launch the glint plays on the sign-in '
        'screen, not on the startup being cross-faded away', (tester) async {
      _viewport(tester, const Size(390, 844));
      final auth = StreamController<User?>();
      addTearDown(auth.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateChangesProvider.overrideWith((ref) => auth.stream),
          ],
          child: _app(const AuthGate()),
        ),
      );
      auth.add(null);
      await tester.pump();
      var signInGlintFrames = 0;
      for (var ms = 0; ms < 3400; ms += 16) {
        await tester.pump(const Duration(milliseconds: 16));
        if (find.byKey(_authGlint).evaluate().isNotEmpty) signInGlintFrames++;
      }
      expect(signInGlintFrames, greaterThan(20));
      expect(LaunchGlint.spent, isTrue);
      expect(find.byType(StartupLoadingScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a launch whose glint is spent shows the bloom alone', (
      tester,
    ) async {
      LaunchGlint.debugReset(spent: true);
      _viewport(tester, const Size(390, 844));
      await tester.pumpWidget(_app(const StartupLoadingScreen()));
      for (var ms = 0; ms < 5000; ms += 40) {
        await tester.pump(const Duration(milliseconds: 40));
        expect(find.byKey(_startupGlint), findsNothing);
      }
      expect(find.byKey(_startupBloom), findsOneWidget);
    });

    testWidgets('the glint band is white on the logo alpha only, 35 % wide, '
        'centred where it is told', (tester) async {
      const size = Size(200, 200);
      for (final (x, expected) in const [(0.0, 100), (.5, 150), (-.5, 50)]) {
        final rgba = await _rasterBand(tester, x: x, size: size);
        expect(
          _brightestColumn(rgba, 200, 100),
          inInclusiveRange(expected - 2, expected + 2),
        );
        final peak = (100 * 200 + expected) * 4;
        // Premultiplied white: the colour channels equal the alpha.
        final pixel = rgba.sublist(peak, peak + 4);
        expect(pixel[3], greaterThan(240));
        expect(pixel.sublist(0, 3), everyElement(pixel[3]));
      }
      // Tilted "/" by 20°: higher rows peak further right.
      final rgba = await _rasterBand(tester, x: 0, size: size);
      expect(
        _brightestColumn(rgba, 200, 20),
        greaterThan(_brightestColumn(rgba, 200, 180)),
      );
      // Fully off the band 35 % of the width away from its centre.
      expect(rgba[(100 * 200 + 100 + 38) * 4 + 3], lessThan(8));
    });
  });

  group('Auth (W1 glint, R5 action, rail tile)', () {
    Widget login({Completer<UserCredential>? pending, AuthMode? mode}) =>
        ResponsiveAuthScreen(
          initialMode: mode ?? AuthMode.login,
          authService: _FakeAuthService(pendingLogin: pending),
        );

    testWidgets('the header mark is the real logo with its bloom at the '
        'unchanged 56 / 44 sizes', (tester) async {
      LaunchGlint.debugReset(spent: true);
      _viewport(tester, const Size(390, 844));
      await tester.pumpWidget(_app(login()));
      await tester.pump();

      final mark = find.byType(LaunchGlintMark);
      expect(mark, findsOneWidget);
      final box = find
          .ancestor(of: mark, matching: find.byType(AnimatedContainer))
          .first;
      expect(tester.getSize(box), const Size(56, 56));
      final assets = tester
          .widgetList<Image>(
            find.descendant(of: mark, matching: find.byType(Image)),
          )
          .map(_assetOf)
          .toSet();
      expect(assets, {YoBrandMark.markAsset, YoBrandMark.bloomAsset});
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              _assetOf(widget) == 'assets/images/yo-voice-favicon-512.png',
        ),
        findsNothing,
      );

      await tester.pumpWidget(
        _app(
          KeyedSubtree(
            key: const ValueKey('register'),
            child: login(mode: AuthMode.register),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getSize(box), const Size(44, 44));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the wide brand panel mark is the real logo at 96', (
      tester,
    ) async {
      LaunchGlint.debugReset(spent: true);
      _viewport(tester, const Size(1440, 900));
      await tester.pumpWidget(_app(login()));
      await tester.pump();
      expect(find.byKey(const ValueKey('auth-layout-wide')), findsOneWidget);
      final mark = find.descendant(
        of: find.byKey(const ValueKey('auth-desktop-brand-panel')),
        matching: find.byType(LaunchGlintMark),
      );
      expect(tester.getSize(mark), const Size(96, 96));
    });

    testWidgets('one glint shortly after first paint; the screen settles '
        'within 1.2 s and releases its ticker', (tester) async {
      _viewport(tester, const Size(390, 844));
      await tester.pumpWidget(_app(login()));
      expect(LaunchGlint.spent, isTrue);
      expect(find.byKey(_authGlint), findsNothing, reason: 'first paint');

      final pumps = await tester.pumpAndSettle();
      expect(
        pumps * 100,
        lessThanOrEqualTo(1200),
        reason: 'pumpAndSettle settles within 1.2 s',
      );
      expect(find.byKey(_authGlint), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the auth glint crosses the mark once, left to right', (
      tester,
    ) async {
      _viewport(tester, const Size(390, 844));
      await tester.pumpWidget(_app(login()));
      final present = <int>[];
      for (var ms = 16; ms <= 1300; ms += 16) {
        await tester.pump(const Duration(milliseconds: 16));
        if (find.byKey(_authGlint).evaluate().isNotEmpty) present.add(ms);
      }
      expect(present.first, greaterThanOrEqualTo(200));
      expect(present.last, lessThanOrEqualTo(1120));
      expect(present.length, greaterThan(40));
      expect(LaunchGlintMark.bandX(0), isNull);
      expect(LaunchGlintMark.bandX(200 / 1100), closeTo(-1.4, 1e-9));
      expect(LaunchGlintMark.bandX(1), closeTo(1.4, 1e-9));
      expect(LaunchGlintMark.duration, LaunchGlintMark.delay + AppMotion.glint);
    });

    testWidgets('a launch that already glinted shows the auth bloom alone', (
      tester,
    ) async {
      LaunchGlint.debugReset(spent: true);
      _viewport(tester, const Size(390, 844));
      await tester.pumpWidget(_app(login()));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      for (var ms = 0; ms < 1400; ms += 50) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byKey(_authGlint), findsNothing);
      }
    });

    for (final mode in ['reduce motion', 'high contrast', 'tickers off']) {
      testWidgets('$mode: no auth glint and the launch stays unclaimed', (
        tester,
      ) async {
        _viewport(tester, const Size(390, 844));
        Widget screen = login();
        if (mode == 'tickers off') {
          screen = TickerMode(enabled: false, child: screen);
        }
        await tester.pumpWidget(
          _app(
            screen,
            disableAnimations: mode == 'reduce motion',
            highContrast: mode == 'high contrast',
          ),
        );
        // The theme and material implicit animations of first paint end
        // within a few frames; nothing may keep ticking after them.
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byKey(_authGlint), findsNothing);
        expect(tester.binding.transientCallbackCount, 0);
        expect(LaunchGlint.spent, isFalse);
        final images = find.descendant(
          of: find.byType(LaunchGlintMark),
          matching: find.byType(Image),
        );
        expect(
          images,
          mode == 'high contrast' ? findsOneWidget : findsNWidgets(2),
          reason: 'high contrast drops the bloom; the rest keep it static',
        );
      });
    }

    testWidgets('the primary action is the R5 gradient: 52 px, radius 12, '
        'its keys and one semantics node', (tester) async {
      LaunchGlint.debugReset(spent: true);
      _viewport(tester, const Size(390, 844));
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(_app(login()));
        await tester.pump();
        final submit = find.byKey(const ValueKey('auth-login-submit'));
        expect(tester.getSize(submit).height, 52);
        final button = tester.widget<YoGradientFilledButton>(
          find.descendant(
            of: submit,
            matching: find.byType(YoGradientFilledButton),
          ),
        );
        expect(button.busy, isFalse);
        expect(button.emphasis, YoActionEmphasis.lifted);
        expect(
          button.shape,
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        );
        final label = tester
            .widget<Text>(
              find.descendant(of: submit, matching: find.byType(Text)),
            )
            .data!;
        expect(
          tester.getSemantics(submit),
          matchesSemantics(
            label: label,
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
          ),
        );
        final lift = tester
            .widgetList<AnimatedContainer>(
              find.descendant(
                of: submit,
                matching: find.byType(AnimatedContainer),
              ),
            )
            .first;
        final shadows = (lift.decoration! as ShapeDecoration).shadows!;
        expect(shadows.single.color, AppColors.primary.withValues(alpha: .32));
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('keyboard focus paints the 2 px onPrimary edge over the '
        'gradient', (tester) async {
      LaunchGlint.debugReset(spent: true);
      _viewport(tester, const Size(390, 844));
      final strategy = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
      await tester.pumpWidget(_app(login()));
      await tester.pump();
      final submit = find.byKey(const ValueKey('auth-login-submit'));
      final button = find.descendant(
        of: submit,
        matching: find.byType(FilledButton),
      );
      // The edge is painted by the shared primitive, over its own gradient
      // (the button's `side` alone sits beneath the gradient, unseen): read
      // the pixel the screen actually shows, in the second column of the
      // button's left edge, at mid-height.
      Future<List<int>> edgePixel() async {
        final rect = tester.getRect(button);
        final probe = Rect.fromLTWH(
          rect.left.floorToDouble() + 1,
          rect.center.dy.floorToDouble(),
          1,
          1,
        );
        return (await tester.runAsync(() async {
          final layer =
              tester.binding.renderViews.first.debugLayer! as OffsetLayer;
          final image = await layer.toImage(probe);
          try {
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            return bytes.sublist(0, 4);
          } finally {
            image.dispose();
          }
        }))!;
      }

      final rest = await edgePixel();
      expect(
        rest,
        isNot(const [255, 255, 255, 255]),
        reason: 'no edge without focus: the gradient shows',
      );
      final label = tester.getRect(
        find.descendant(of: submit, matching: find.byType(Text)),
      );
      final size = tester.getSize(submit);
      Focus.of(
        tester.element(
          find.descendant(of: submit, matching: find.byType(Text)),
        ),
      ).requestFocus();
      await tester.pump();
      await tester.pump();
      expect(await edgePixel(), [255, 255, 255, 255]);
      // The edge is a foreground: focus moves nothing.
      expect(
        tester.getRect(
          find.descendant(of: submit, matching: find.byType(Text)),
        ),
        label,
      );
      expect(tester.getSize(submit), size);
    });

    testWidgets('busy keeps the gradient, half the lift, the spinner and '
        'says it is loading', (tester) async {
      LaunchGlint.debugReset(spent: true);
      _viewport(tester, const Size(430, 844));
      final pending = Completer<UserCredential>();
      await tester.pumpWidget(_app(login(pending: pending)));
      await tester.pump();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('auth-login-email')),
          matching: find.byType(EditableText),
        ),
        'ola@example.com',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('auth-login-password')),
          matching: find.byType(EditableText),
        ),
        'Secret123',
      );
      final submit = find.byKey(const ValueKey('auth-login-submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final button = tester.widget<YoGradientFilledButton>(
        find.descendant(
          of: submit,
          matching: find.byType(YoGradientFilledButton),
        ),
      );
      expect(button.busy, isTrue);
      expect(button.onPressed, isNotNull, reason: 'keeps its gradient');
      expect(
        find.descendant(
          of: submit,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      final lift = tester
          .widgetList<AnimatedContainer>(
            find.descendant(
              of: submit,
              matching: find.byType(AnimatedContainer),
            ),
          )
          .first;
      final shadows = (lift.decoration! as ShapeDecoration).shadows!;
      expect(shadows.single.color.a, closeTo(.16, .005));
      expect(
        tester.getSemantics(submit).value,
        isNotEmpty,
        reason: 'the button announces that it is loading',
      );
      pending.completeError(StateError('stop'));
      await tester.pump();
    });

    testWidgets('a locked action keeps its gradient, drops its lift and '
        'ignores pointer and focus', (tester) async {
      _viewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: AuthPrimaryButton(
                  key: ValueKey('locked'),
                  label: 'ZALOGUJ SIĘ',
                  loading: false,
                  onPressed: null,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final locked = find.byKey(const ValueKey('locked'));
      final button = tester.widget<YoGradientFilledButton>(
        find.descendant(
          of: locked,
          matching: find.byType(YoGradientFilledButton),
        ),
      );
      expect(button.onPressed, isNotNull, reason: 'the fill is not greyed');
      expect(button.emphasis, YoActionEmphasis.flat);
      expect(button.busy, isFalse);
      expect(
        find.descendant(of: locked, matching: find.byType(Ink)),
        findsOneWidget,
        reason: 'the gradient is still laid',
      );
      expect(locked.hitTestable(), findsNothing);
      final focus = Focus.of(
        tester.element(
          find.descendant(of: locked, matching: find.byType(Text)),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      expect(
        tester.getSemantics(locked),
        isSemantics(
          label: 'ZALOGUJ SIĘ',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasTapAction: false,
        ),
      );
    });

    testWidgets('mode rail: tonal selected tile with a 1.5 px primary edge; '
        'solid primary under high contrast', (tester) async {
      LaunchGlint.debugReset(spent: true);
      _viewport(tester, const Size(390, 844));
      await tester.pumpWidget(_app(login()));
      await tester.pump();
      var tile =
          tester
                  .widget<DecoratedBox>(
                    find.byKey(const ValueKey('auth-mode-rail-tile')),
                  )
                  .decoration
              as BoxDecoration;
      expect(
        tile.color,
        Color.alphaBlend(
          AppColors.primary.withValues(alpha: .26),
          AppImmersiveColors.surface,
        ),
      );
      expect(tile.border, Border.all(color: AppColors.primary, width: 1.5));
      // The edge is the tile's boundary against the track: ≥ 3:1.
      expect(
        _contrast(AppColors.primary, AppImmersiveColors.surface),
        greaterThanOrEqualTo(3),
      );
      expect(
        _contrast(AppImmersiveColors.textPrimary, tile.color!),
        greaterThanOrEqualTo(4.5),
      );

      await tester.pumpWidget(_app(login(), highContrast: true));
      await tester.pump();
      tile =
          tester
                  .widget<DecoratedBox>(
                    find.byKey(const ValueKey('auth-mode-rail-tile')),
                  )
                  .decoration
              as BoxDecoration;
      expect(tile.color, AppColors.primary);
      expect(tile.border, isNull);
    });

    for (final (size, textScale) in const [
      (Size(320, 568), 2.0),
      (Size(390, 844), 2.0),
      (Size(768, 1024), 1.0),
      (Size(1440, 900), 2.0),
    ]) {
      testWidgets('login and register fit ${size.width.toInt()} at '
          '${(textScale * 100).toInt()} % text', (tester) async {
        LaunchGlint.debugReset(spent: true);
        _viewport(tester, size);
        for (final mode in AuthMode.values) {
          await tester.pumpWidget(
            _app(
              ResponsiveAuthScreen(
                key: ValueKey(mode),
                initialMode: mode,
                authService: _FakeAuthService(),
              ),
              textScale: textScale,
            ),
          );
          await tester.pump();
          final submit = find.byKey(
            ValueKey(
              mode == AuthMode.login
                  ? 'auth-login-submit'
                  : 'auth-register-submit',
            ),
          );
          await tester.ensureVisible(submit);
          await tester.pump();
          expect(tester.getSize(submit).height, greaterThanOrEqualTo(52));
          expect(tester.takeException(), isNull);
        }
      });
    }
  });

  group('TOTP and the auth gate', () {
    testWidgets('TOTP shows the real logo at 76 with its bloom and no glint', (
      tester,
    ) async {
      _viewport(tester, const Size(390, 844));
      await tester.pumpWidget(totpTestApp(FakeTotpChallenge()));
      await tester.pump();
      final mark = tester.widget<YoBrandMark>(find.byKey(totpLogoKey));
      expect(mark.size, 76);
      expect(mark.light, YoBrandLight.bloom);
      expect(tester.getSize(find.byKey(totpLogoKey)), const Size(76, 76));
      expect(find.byType(LaunchGlintMark), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(LaunchGlint.spent, isFalse);
    });

    testWidgets('the code stage glow keeps its look and draws nothing under '
        'high contrast (principle 4), without remounting the field', (
      tester,
    ) async {
      _viewport(tester, const Size(390, 844));
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(totpTestApp(FakeTotpChallenge()));
      await tester.pump();
      final glow = find.byKey(totpStageGlowKey);
      BoxDecoration decoration() =>
          tester.widget<DecoratedBox>(glow).decoration as BoxDecoration;
      expect(glow, findsOneWidget);
      final gradient = decoration().gradient! as RadialGradient;
      expect(gradient.radius, .72);
      expect(gradient.colors.first, AppColors.primary.withValues(alpha: .16));
      expect(gradient.colors.last.a, 0);
      final field = find.descendant(
        of: find.byKey(totpCodeInputKey),
        matching: find.byType(EditableText),
      );
      await tester.enterText(field, '12');
      await tester.pump();
      final fieldState = tester.state(field);

      // The system switch flips while the screen is open.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      await tester.pump();
      expect(glow, findsOneWidget);
      final flat = decoration();
      expect(flat.gradient, isNull);
      expect(flat.color, isNull);
      expect(flat.boxShadow, isNull);
      expect(flat.image, isNull);
      expect(flat.border, isNull);
      expect(tester.state(field), same(fieldState));
      expect(tester.widget<EditableText>(field).controller.text, '12');

      // And back: the glow returns exactly.
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await tester.pump();
      expect(decoration().gradient, gradient);
    });

    testWidgets('a TOTP screen opened under high contrast draws no stage '
        'glow', (tester) async {
      _viewport(tester, const Size(390, 844));
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(totpTestApp(FakeTotpChallenge()));
      await tester.pump();
      final decoration =
          tester.widget<DecoratedBox>(find.byKey(totpStageGlowKey)).decoration
              as BoxDecoration;
      expect(decoration.gradient, isNull);
      expect(decoration.color, isNull);
      // The code cells themselves are still there.
      expect(find.byKey(totpNodeKey(0)), findsOneWidget);
    });

    Widget gate({Object? error}) => ProviderScope(
      overrides: [
        authStateChangesProvider.overrideWith(
          (ref) => const Stream<User?>.empty(),
        ),
      ],
      child: AuthGate(initialAuthError: error ?? StateError('offline')),
    );

    for (final (size, textScale) in const [
      (Size(390, 844), 1.0),
      (Size(768, 1024), 1.0),
      (Size(1440, 900), 1.0),
      (Size(320, 568), 2.0),
    ]) {
      testWidgets('auth-gate error at ${size.width.toInt()} / '
          '${(textScale * 100).toInt()} %: backdrop, lit logo, status glyph, '
          'gradient retry', (tester) async {
        _viewport(tester, size);
        await tester.pumpWidget(_app(gate(), textScale: textScale));
        await tester.pump();

        expect(find.byType(AuthBackdrop), findsOneWidget);
        final logo = tester.widget<YoBrandMark>(
          find.byKey(const ValueKey('auth-gate-logo')),
        );
        expect(logo.size, 64);
        expect(logo.light, YoBrandLight.bloom);
        final icon = tester.widget<Icon>(
          find.byKey(const ValueKey('auth-gate-status-icon')),
        );
        expect(icon.size, 20);
        expect(icon.color, AppColors.error);
        expect(find.text('Coś poszło nie tak'), findsOneWidget);
        expect(find.text('SPRÓBUJ PONOWNIE'), findsOneWidget);

        final retry = find.byKey(const ValueKey('auth-gate-retry'));
        await tester.ensureVisible(retry);
        await tester.pump();
        expect(
          find.descendant(
            of: retry,
            matching: find.byType(YoGradientFilledButton),
          ),
          findsOneWidget,
        );
        final rect = tester.getRect(retry);
        expect(rect.height, greaterThanOrEqualTo(52));
        if (size.width >= 600) {
          expect(rect.width, 440);
        } else {
          // The sign-in form's 16 px gutter: as wide as the chain's other
          // primary actions.
          expect(rect.width, size.width - 32);
        }
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(
          _liftOf(tester, retry),
          isNotEmpty,
          reason: 'the auth-gate retry is the screen\'s one lifted action',
        );
        _expectLabelClearance(tester, retry);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('auth-gate retry re-subscribes to the auth state', (
      tester,
    ) async {
      _viewport(tester, const Size(390, 844));
      var subscriptions = 0;
      await tester.pumpWidget(
        _app(
          ProviderScope(
            overrides: [
              authStateChangesProvider.overrideWith((ref) {
                subscriptions++;
                return const Stream<User?>.empty();
              }),
            ],
            child: AuthGate(initialAuthError: StateError('offline')),
          ),
        ),
      );
      await tester.pump();
      expect(subscriptions, 1);
      final retry = find.byKey(const ValueKey('auth-gate-retry'));
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pump();
      expect(subscriptions, 2, reason: 'retry invalidates the auth stream');
      expect(find.text('Coś poszło nie tak'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final (size, textScale) in const [
      (Size(320, 568), 2.0),
      (Size(390, 844), 1.0),
      (Size(390, 844), 2.0),
      (Size(768, 1024), 1.0),
      (Size(1440, 900), 1.0),
      (Size(1440, 900), 2.0),
    ]) {
      testWidgets('profile-bootstrap failure at ${size.width.toInt()} / '
          '${(textScale * 100).toInt()} %: shared layout, flat retry, both '
          'actions work', (tester) async {
        _viewport(tester, size);
        var retries = 0;
        var signOuts = 0;
        await tester.pumpWidget(
          _app(
            ProfileBootstrapErrorScreen(
              onRetry: () => retries++,
              onSignOut: () async => signOuts++,
            ),
            textScale: textScale,
          ),
        );
        await tester.pump();

        expect(find.byType(AuthBackdrop), findsOneWidget);
        final logo = tester.widget<YoBrandMark>(
          find.byKey(const ValueKey('auth-gate-logo')),
        );
        expect(logo.size, 64);
        expect(logo.light, YoBrandLight.bloom);
        final icon = tester.widget<Icon>(
          find.byKey(const ValueKey('auth-gate-status-icon')),
        );
        expect(icon.icon, Icons.cloud_off_rounded);
        expect(icon.size, 20);
        final title = tester.widget<Text>(
          find.text('Kończymy konfigurację profilu'),
        );
        expect(title.style!.fontWeight, FontWeight.w700, reason: '§2.6 cap');
        expect(
          find.text(
            'Twoje konto jest bezpieczne. Sprawdź połączenie i spróbuj '
            'ponownie, aby dokończyć konfigurację YO Voice.',
          ),
          findsOneWidget,
        );

        final retry = find.byKey(const ValueKey('auth-gate-retry'));
        await tester.ensureVisible(retry);
        await tester.pump();
        final button = tester.widget<YoGradientFilledButton>(
          find.descendant(
            of: retry,
            matching: find.byType(YoGradientFilledButton),
          ),
        );
        expect(
          button.emphasis,
          YoActionEmphasis.flat,
          reason: 'R5: no lift on a retry action',
        );
        expect(_liftOf(tester, retry), isEmpty);
        expect(
          find.descendant(of: retry, matching: find.byType(Ink)),
          findsOneWidget,
          reason: 'the gradient is still laid',
        );
        final rect = tester.getRect(retry);
        expect(rect.height, greaterThanOrEqualTo(52));
        expect(
          rect.width,
          size.width >= 600 ? 440 : size.width - 32,
          reason: 'full width in the 16 px gutter; 440 on medium and wide',
        );
        _expectLabelClearance(tester, retry);

        await tester.tap(retry);
        await tester.pump();
        expect(retries, 1);

        final signOut = find.byKey(
          const ValueKey('profile-bootstrap-sign-out'),
        );
        await tester.ensureVisible(signOut);
        await tester.pump();
        expect(find.text('Użyj innego konta'), findsOneWidget);
        final signOutRect = tester.getRect(signOut);
        expect(signOutRect.top, greaterThanOrEqualTo(0));
        expect(signOutRect.bottom, lessThanOrEqualTo(size.height));
        await tester.tap(signOut);
        await tester.pump();
        expect(signOuts, 1);
        expect(retries, 1);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Failure title at large text', () {
    Widget bootstrap() =>
        ProfileBootstrapErrorScreen(onRetry: () {}, onSignOut: () async {});
    Widget gate() => ProviderScope(
      overrides: [
        authStateChangesProvider.overrideWith(
          (ref) => const Stream<User?>.empty(),
        ),
      ],
      child: AuthGate(initialAuthError: StateError('offline')),
    );

    for (final (name, screen, title, message) in [
      (
        'profile bootstrap',
        bootstrap,
        'Kończymy konfigurację profilu',
        'Twoje konto jest bezpieczne. Sprawdź połączenie i spróbuj '
            'ponownie, aby dokończyć konfigurację YO Voice.',
      ),
      (
        'auth gate',
        gate,
        'Coś poszło nie tak',
        'Brak połączenia z internetem.',
      ),
    ]) {
      for (final width in const [390.0, 1440.0]) {
        testWidgets('$name title never breaks mid-word at ${width.toInt()} / '
            '200 %; the message keeps the full scale', (tester) async {
          _viewport(tester, Size(width, 900));
          await tester.pumpWidget(_app(screen(), textScale: 2));
          await tester.pump();
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(title),
          );
          final text = paragraph.text.toPlainText();
          // Every character of a word sits on the same line.
          for (final word in RegExp(r'\S+').allMatches(text)) {
            final lines = {
              for (var i = word.start; i < word.end; i++)
                paragraph
                    .getOffsetForCaret(TextPosition(offset: i), Rect.zero)
                    .dy,
            };
            expect(lines, hasLength(1), reason: '"${word[0]}" breaks');
          }
          // The glyph leads the first line.
          final icon = tester.getRect(
            find.byKey(const ValueKey('auth-gate-status-icon')),
          );
          final titleBox = tester.getRect(find.text(title));
          expect(titleBox.left - icon.right, 8);
          final messages = find.textContaining(message.split(' ').first);
          if (messages.evaluate().isNotEmpty) {
            final messageText = tester.widget<Text>(messages.first);
            expect(messageText.textScaler, isNull, reason: 'full scale');
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('Primary action label at large text', () {
    for (final width in const [320.0, 390.0]) {
      testWidgets('a wrapped label keeps 12 px inside the fill at '
          '${width.toInt()} / 200 %; one line stays 52 px', (tester) async {
        _viewport(tester, Size(width, 844));
        Widget button(double textScale) => _app(
          const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: AuthPrimaryButton(
                    key: ValueKey('action'),
                    label: 'SPRÓBUJ PONOWNIE',
                    loading: false,
                    onPressed: _noop,
                  ),
                ),
              ),
            ),
          ),
          textScale: textScale,
        );
        final action = find.byKey(const ValueKey('action'));

        await tester.pumpWidget(button(1));
        await tester.pump();
        // (The test font's square glyphs are wider than Inter's, so the
        // one-line 100 % label is checked where it fits on one line.)
        if (width >= 390) expect(tester.getSize(action).height, 52);
        _expectLabelClearance(tester, action);

        await tester.pumpWidget(button(2));
        await tester.pump();
        final label = find.descendant(of: action, matching: find.byType(Text));
        expect(
          tester.renderObject<RenderParagraph>(label).size.height,
          greaterThan(2 * 32 * 1.2 - 1),
          reason: 'the label wraps at 200 %',
        );
        _expectLabelClearance(tester, action);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

void _noop() {}

/// The R5 lift under an auth primary action (empty when it is flat).
List<BoxShadow> _liftOf(WidgetTester tester, Finder action) {
  final lift = tester
      .widgetList<AnimatedContainer>(
        find.descendant(of: action, matching: find.byType(AnimatedContainer)),
      )
      .first;
  return (lift.decoration! as ShapeDecoration).shadows ?? const [];
}

/// The label's line boxes sit at least the button's 12 px padding inside
/// its fill, so no accent or descender can reach the edge.
void _expectLabelClearance(WidgetTester tester, Finder action) {
  final fill = tester.getRect(
    find.descendant(of: action, matching: find.byType(FilledButton)),
  );
  final label = tester.getRect(
    find.descendant(of: action, matching: find.byType(Text)).first,
  );
  expect(label.top - fill.top, greaterThanOrEqualTo(12), reason: 'top');
  expect(
    fill.bottom - label.bottom,
    greaterThanOrEqualTo(12),
    reason: 'bottom',
  );
  expect(label.left, greaterThanOrEqualTo(fill.left));
  expect(label.right, lessThanOrEqualTo(fill.right));
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + .05) / (lo + .05);
}
