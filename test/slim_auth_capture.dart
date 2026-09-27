// Developer-only visual evidence harness for Slim redesign phase 7 (sign-in
// chain). It renders the real auth widgets at exact viewports with real fonts
// and writes PNGs named `<screen>_<width>_<dark|pearl>_<locale>_<text>_<state>`.
//
// Run explicitly (the file deliberately does not end in `_test.dart`, so
// routine test runs never create artifacts):
//   flutter test --dart-define=SLIM_CAPTURE_DIR=<absolute dir> \
//     test/slim_auth_capture.dart
//
// Accounts, addresses and provider responses are synthetic. `Dark` / `Pearl`
// is the app theme around the route; the auth chain itself is an immersive
// dark atom (`YoImmersiveDarkSurface`) and must look identical in both.
//
// refine-look B10 adds 768, Pearl and 200 % across the matrix, high-contrast
// (`-hc`) frames, the busy and locked primary action, Reduce Motion, the
// launch glint mid-pass, TOTP, the auth-gate failure and the profile-bootstrap
// failure, scrolled 200 % frames that show the primary action, and two
// 50 ms frame sequences (`sequence/`): a signed-out cold launch through the
// startup → sign-in handoff, and the sign-in screen's first paint. Every
// frame but the glint, Reduce Motion and sequence frames renders with the
// launch glint already spent, so the frames are deterministic.
//
// The test framework paints every BoxShadow as a hard, unblurred block
// (`debugDisableShadows`, meant for golden stability). It is switched off
// while a frame is captured and restored before the case ends, so the R5
// lift under the primary action renders as it does on a device.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/screens/auth_gate.dart';
import 'package:yovoice/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:yovoice/features/auth/presentation/screens/responsive_auth_screen.dart';
import 'package:yovoice/features/auth/presentation/screens/totp_challenge_screen.dart';
import 'package:yovoice/features/auth/presentation/screens/verify_email_screen.dart';
import 'package:yovoice/features/auth/presentation/widgets/startup_loading_screen.dart';
import 'package:yovoice/features/auth/providers/auth_provider.dart';
import 'package:yovoice/services/firestore_service.dart';
import 'package:yovoice/shared/widgets/branding/yo_logo.dart';

import 'totp_challenge_test_support.dart';

const _outputDirectory = String.fromEnvironment(
  'SLIM_CAPTURE_DIR',
  defaultValue: 'build/slim-auth-capture',
);

final _captureKey = GlobalKey();

class _VisualAuthService extends AuthService {
  _VisualAuthService({
    this.appleAvailability = AppleSignInAvailability.available,
  }) : super(
         firebaseAuth: MockFirebaseAuth(),
         firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
       );

  final AppleSignInAvailability appleAvailability;

  /// Never completes, so a submitted sign-in stays busy for the frame.
  final Completer<UserCredential> _pendingSignIn = Completer();

  /// Never completes, so the chain stays locked behind a running provider.
  final Completer<UserCredential> _pendingGoogle = Completer();

  @override
  Future<AppleSignInAvailability> getAppleSignInAvailability() async =>
      appleAvailability;

  @override
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) => _pendingSignIn.future;

  @override
  Future<UserCredential> signInWithGoogle() => _pendingGoogle.future;
}

// VerifyEmailScreen reads FirebaseAuth.instance directly. A bare core
// platform lets Firebase.app() resolve; the auth delegate's native listener
// registration fails silently in tests and currentUser stays null.
class _FakeFirebaseApp extends FirebaseAppPlatform {
  _FakeFirebaseApp()
    : super(
        defaultFirebaseAppName,
        const FirebaseOptions(
          apiKey: 'capture-api-key',
          appId: 'capture-app-id',
          messagingSenderId: 'capture-sender-id',
          projectId: 'capture-project-id',
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

enum _Screen {
  login,
  register,
  forgotPassword,
  checkInbox,
  verifyEmail,
  totp,
  authGateError,
  profileBootstrap,
}

enum _Interaction {
  none,
  focusSubmit,
  focusRail,
  focusGoogle,
  focusField,
  validationError,
  busy,

  /// Another provider (Google) runs: the primary action is locked.
  locked,

  /// Scrolls the form until its primary action is in view (200 % text).
  scrollToSubmit,
}

class _Shot {
  const _Shot({
    required this.screen,
    required this.width,
    this.pearl = false,
    this.textScale = 1,
    this.state = 'populated',
    this.interaction = _Interaction.none,
    this.appleAvailability = AppleSignInAvailability.available,
    this.highContrast = false,
    this.glint = false,
    this.reducedMotion = false,
  });

  final _Screen screen;
  final double width;
  final bool pearl;
  final double textScale;
  final String state;
  final _Interaction interaction;
  final AppleSignInAvailability appleAvailability;
  final bool highContrast;

  /// Renders with motion on and the launch glint unspent, captured mid-pass.
  final bool glint;

  /// Reduce Motion and accessible navigation on, with the launch glint
  /// unspent: the frame proves the static bloom and that nothing glints.
  final bool reducedMotion;

  /// Whether the launch glint starts unspent for this frame.
  bool get glintUnspent => glint || reducedMotion;

  Size get size => Size(
    width,
    width >= 1000
        ? 900
        : width >= 600
        ? 1024
        : width < 360
        ? 568
        : 844,
  );

  String get filename {
    final name = switch (screen) {
      _Screen.login => 'login',
      _Screen.register => 'register',
      _Screen.forgotPassword => 'forgot_password',
      _Screen.checkInbox => 'check_inbox',
      _Screen.verifyEmail => 'verify_email',
      _Screen.totp => 'totp',
      _Screen.authGateError => 'auth_gate_error',
      _Screen.profileBootstrap => 'profile_bootstrap',
    };
    final theme = pearl ? 'pearl' : 'dark';
    final text = (textScale * 100).round();
    return '${name}_${width.toInt()}_${theme}_pl_${text}_$state'
        '${highContrast ? '-hc' : ''}';
  }
}

List<_Shot> _shots() => <_Shot>[
  for (final screen in const [_Screen.login, _Screen.register])
    for (final width in const [390.0, 768.0, 1440.0])
      for (final pearl in const [false, true])
        for (final textScale in const [1.0, 2.0])
          _Shot(
            screen: screen,
            width: width,
            pearl: pearl,
            textScale: textScale,
          ),
  const _Shot(screen: _Screen.forgotPassword, width: 390),
  const _Shot(screen: _Screen.checkInbox, width: 390),
  const _Shot(screen: _Screen.verifyEmail, width: 390),
  // refine-look B10: TOTP and the auth-gate failure across the matrix.
  for (final screen in const [_Screen.totp, _Screen.authGateError])
    for (final width in const [390.0, 768.0, 1440.0])
      for (final pearl in const [false, true])
        _Shot(
          screen: screen,
          width: width,
          pearl: pearl,
          state: screen == _Screen.totp ? 'populated' : 'error',
        ),
  for (final width in const [320.0, 390.0, 1440.0])
    _Shot(screen: _Screen.totp, width: width, textScale: 2),
  const _Shot(
    screen: _Screen.authGateError,
    width: 390,
    textScale: 2,
    state: 'error',
  ),
  const _Shot(
    screen: _Screen.authGateError,
    width: 1440,
    textScale: 2,
    state: 'error',
  ),
  // The primary action while its own sign-in runs.
  for (final width in const [390.0, 1440.0])
    _Shot(
      screen: _Screen.login,
      width: width,
      state: 'busy',
      interaction: _Interaction.busy,
    ),
  // High contrast: solid rail tile, no lift, no bloom.
  for (final width in const [390.0, 1440.0])
    _Shot(screen: _Screen.login, width: width, highContrast: true),
  const _Shot(
    screen: _Screen.authGateError,
    width: 390,
    state: 'error',
    highContrast: true,
  ),
  const _Shot(screen: _Screen.totp, width: 390, highContrast: true),
  // The launch glint mid-pass (UNVERIFIED until seen on a device).
  for (final width in const [390.0, 1440.0])
    _Shot(screen: _Screen.login, width: width, state: 'glint', glint: true),
  // Focus, validation, availability and 200 % text evidence. The primary
  // action's focus indicator in both app themes (the chain is the same
  // immersive dark atom in each), and under high contrast, where it gains
  // its outer `focus` band.
  for (final pearl in const [false, true])
    for (final highContrast in const [false, true])
      _Shot(
        screen: _Screen.login,
        width: 1440,
        pearl: pearl,
        state: 'focus-submit',
        interaction: _Interaction.focusSubmit,
        highContrast: highContrast,
      ),
  const _Shot(
    screen: _Screen.login,
    width: 1440,
    state: 'focus-rail',
    interaction: _Interaction.focusRail,
  ),
  const _Shot(
    screen: _Screen.login,
    width: 1440,
    state: 'focus-field',
    interaction: _Interaction.focusField,
  ),
  const _Shot(
    screen: _Screen.login,
    width: 390,
    state: 'focus-google-apple-soon',
    interaction: _Interaction.focusGoogle,
    appleAvailability: AppleSignInAvailability.notConfigured,
  ),
  const _Shot(
    screen: _Screen.register,
    width: 390,
    state: 'validation-error',
    interaction: _Interaction.validationError,
  ),
  // (Login and register at 200 % are part of the matrix above.)
  const _Shot(screen: _Screen.forgotPassword, width: 390, textScale: 2),
  const _Shot(screen: _Screen.forgotPassword, width: 320, textScale: 2),
  // Review round 2 ---------------------------------------------------------
  // 200 % text, scrolled until the primary action is in view.
  for (final screen in const [_Screen.login, _Screen.register])
    for (final width in const [320.0, 390.0, 768.0, 1440.0])
      _Shot(
        screen: screen,
        width: width,
        textScale: 2,
        state: 'scrolled',
        interaction: _Interaction.scrollToSubmit,
      ),
  // The busy action at 200 % (a wrapped label beside the spinner).
  const _Shot(
    screen: _Screen.login,
    width: 390,
    textScale: 2,
    state: 'busy',
    interaction: _Interaction.busy,
  ),
  // Locked while another provider runs: the gradient stays, no lift.
  for (final width in const [390.0, 1440.0])
    _Shot(
      screen: _Screen.login,
      width: width,
      state: 'locked',
      interaction: _Interaction.locked,
    ),
  // Reduce Motion: the static .45 bloom and no glint, with the glint unspent.
  for (final width in const [390.0, 1440.0])
    _Shot(
      screen: _Screen.login,
      width: width,
      state: 'reduced-motion',
      reducedMotion: true,
    ),
  // The auth-gate failure at the narrowest phone and 200 %, and high
  // contrast at every width.
  const _Shot(
    screen: _Screen.authGateError,
    width: 320,
    textScale: 2,
    state: 'error',
  ),
  const _Shot(
    screen: _Screen.authGateError,
    width: 768,
    textScale: 2,
    state: 'error',
  ),
  for (final width in const [768.0, 1440.0])
    _Shot(
      screen: _Screen.authGateError,
      width: width,
      state: 'error',
      highContrast: true,
    ),
  // The profile-bootstrap failure (flat retry, no lift).
  for (final width in const [390.0, 768.0, 1440.0])
    for (final pearl in const [false, true])
      _Shot(
        screen: _Screen.profileBootstrap,
        width: width,
        pearl: pearl,
        state: 'error',
      ),
  for (final width in const [320.0, 390.0, 1440.0])
    _Shot(
      screen: _Screen.profileBootstrap,
      width: width,
      textScale: 2,
      state: 'error',
    ),
  const _Shot(
    screen: _Screen.profileBootstrap,
    width: 390,
    state: 'error',
    highContrast: true,
  ),
  const _Shot(
    screen: _Screen.profileBootstrap,
    width: 390,
    state: 'focus-retry',
    interaction: _Interaction.focusSubmit,
  ),
  const _Shot(
    screen: _Screen.authGateError,
    width: 390,
    state: 'focus-retry',
    interaction: _Interaction.focusSubmit,
  ),
];

String _resolveMaterialFontRoot() {
  final configuredRoot = Platform.environment['FLUTTER_ROOT'];
  if (configuredRoot != null) {
    final configured = '$configuredRoot/bin/cache/artifacts/material_fonts';
    if (File('$configured/MaterialIcons-Regular.otf').existsSync()) {
      return configured;
    }
  }

  var directory = File(Platform.resolvedExecutable).parent;
  while (directory.parent.path != directory.path) {
    final candidate = '${directory.path}/bin/cache/artifacts/material_fonts';
    if (File('$candidate/MaterialIcons-Regular.otf').existsSync()) {
      return candidate;
    }
    directory = directory.parent;
  }
  throw StateError('Could not locate Flutter material fonts.');
}

ByteData _asByteData(List<int> bytes) {
  final typed = Uint8List.fromList(bytes);
  return ByteData.view(typed.buffer, typed.offsetInBytes, typed.lengthInBytes);
}

Future<void> _loadRealFonts() async {
  Future<ByteData> read(String path) async =>
      _asByteData(File(path).readAsBytesSync());

  final inter = FontLoader('Inter')
    ..addFont(read('assets/fonts/InterVariable.ttf'))
    ..addFont(read('assets/fonts/InterVariable-Italic.ttf'));
  await inter.load();

  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(read('${_resolveMaterialFontRoot()}/MaterialIcons-Regular.otf'));
  await materialIcons.load();
}

Widget _home(_Shot shot, _VisualAuthService service) {
  return switch (shot.screen) {
    _Screen.login => ResponsiveAuthScreen(
      initialMode: AuthMode.login,
      authService: service,
    ),
    _Screen.register => ResponsiveAuthScreen(
      initialMode: AuthMode.register,
      authService: service,
    ),
    _Screen.forgotPassword || _Screen.checkInbox => ForgotPasswordScreen(
      initialEmail: 'ola.nowak@example.com',
      authService: service,
    ),
    _Screen.verifyEmail => const VerifyEmailScreen(),
    _Screen.totp => TotpChallengeScreen(challenge: FakeTotpChallenge()),
    _Screen.authGateError => ProviderScope(
      overrides: [
        authStateChangesProvider.overrideWith(
          (ref) => const Stream<User?>.empty(),
        ),
      ],
      child: AuthGate(
        initialAuthError: FirebaseAuthException(code: 'network-request-failed'),
      ),
    ),
    _Screen.profileBootstrap => ProfileBootstrapErrorScreen(
      onRetry: () {},
      onSignOut: () async {},
    ),
  };
}

Widget _visualApp(_Shot shot, Widget home) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: shot.pearl ? AppTheme.lightTheme : AppTheme.darkTheme,
    locale: const Locale('pl'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => RepaintBoundary(
      key: _captureKey,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: !shot.glint || shot.reducedMotion,
          accessibleNavigation: shot.reducedMotion,
          highContrast: shot.highContrast,
          textScaler: TextScaler.linear(shot.textScale),
        ),
        child: child!,
      ),
    ),
    home: home,
  );
}

/// Warms the marks of the chain: auth header 56 (44 is the same decode,
/// scaled), wide brand panel 96, auth-gate 64, TOTP 76; and, for a cold
/// launch, the startup mark and its 1.5x bloom and the startup artwork.
Future<void> _precacheMarks(WidgetTester tester, {double? startupMark}) async {
  await tester.runAsync(() async {
    final context = _captureKey.currentContext!;
    for (final size in const [56.0, 64.0, 76.0, 96.0]) {
      await YoBrandMark.precache(context, size: size);
    }
    if (startupMark != null) {
      await YoBrandMark.precache(context, size: startupMark, bloomScale: 1.5);
      if (!context.mounted) return;
      await precacheImage(
        const AssetImage('assets/images/startup_voice_glass_v1.webp'),
        context,
      );
    }
  });
}

Future<void> _capturePng(String filename) async {
  final boundary =
      _captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final warmup = await boundary.toImage(pixelRatio: 1);
  warmup.dispose();
  await Future<void>.delayed(const Duration(milliseconds: 16));

  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_outputDirectory/$filename.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    // ignore: avoid_print
    print('wrote ${file.path}');
  } finally {
    image.dispose();
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 120)),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void _focusNearest(WidgetTester tester, Finder within) {
  final text = find.descendant(of: within, matching: find.byType(Text)).first;
  Focus.of(tester.element(text)).requestFocus();
}

Future<void> _interact(WidgetTester tester, _Shot shot) async {
  switch (shot.interaction) {
    case _Interaction.none:
      return;
    case _Interaction.focusSubmit:
      _focusNearest(
        tester,
        find.byKey(
          ValueKey(
            shot.screen == _Screen.authGateError ||
                    shot.screen == _Screen.profileBootstrap
                ? 'auth-gate-retry'
                : 'auth-login-submit',
          ),
        ),
      );
    case _Interaction.focusRail:
      _focusNearest(tester, find.byKey(const ValueKey('auth-mode-login')));
    case _Interaction.focusGoogle:
      _focusNearest(tester, find.byKey(const ValueKey('auth-google-provider')));
    case _Interaction.focusField:
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('auth-login-email')),
          matching: find.byType(EditableText),
        ),
        'ola.nowak@example.com',
      );
    case _Interaction.validationError:
      final submit = find.byKey(const ValueKey('auth-register-submit'));
      await tester.ensureVisible(submit);
      await tester.pump();
      await tester.tap(submit);
    case _Interaction.scrollToSubmit:
      final submit = find.byKey(
        ValueKey(
          shot.screen == _Screen.register
              ? 'auth-register-submit'
              : 'auth-login-submit',
        ),
      );
      // Centred where the form allows, so the lift below it is in view.
      await Scrollable.ensureVisible(tester.element(submit), alignment: .5);
      await tester.pump();
    case _Interaction.locked:
      final google = find.byKey(const ValueKey('auth-google-provider'));
      await tester.ensureVisible(google);
      await tester.pump();
      await tester.tap(google);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final submit = find.byKey(const ValueKey('auth-login-submit'));
      await tester.ensureVisible(submit);
      await tester.pump();
      // The Google spinner never settles; capture after its first turn.
      await tester.pump(const Duration(milliseconds: 300));
      return;
    case _Interaction.busy:
      for (final (key, value) in const [
        ('auth-login-email', 'ola.nowak@example.com'),
        ('auth-login-password', 'Haslo1234'),
      ]) {
        await tester.enterText(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(EditableText),
          ),
          value,
        );
      }
      final submit = find.byKey(const ValueKey('auth-login-submit'));
      await tester.ensureVisible(submit);
      await tester.pump();
      await tester.tap(submit);
      await tester.pump();
      // The spinner never settles; capture after its first turn.
      await tester.pump(const Duration(milliseconds: 300));
      return;
  }
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    await _loadRealFonts();
    FirebasePlatform.instance = _FakeFirebasePlatform();
    await Firebase.initializeApp();
  });

  for (final shot in _shots()) {
    testWidgets('Slim auth evidence — ${shot.filename}', (tester) async {
      await tester.binding.setSurfaceSize(shot.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final previousStrategy = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy = previousStrategy,
      );
      LaunchGlint.debugReset(spent: !shot.glintUnspent);
      addTearDown(LaunchGlint.debugReset);
      debugDisableShadows = false;
      try {
        await _captureShot(tester, shot);
      } finally {
        debugDisableShadows = true;
      }
    });
  }

  // The launch glint in motion (UNVERIFIED until seen on a device): 50 ms
  // frames of a signed-out cold launch through the startup → sign-in
  // handoff, and of the sign-in screen's first paint.
  for (final width in const [390.0, 1440.0]) {
    testWidgets(
      'Slim auth evidence — cold launch sequence at ${width.toInt()}',
      (tester) async {
        final shot = _Shot(screen: _Screen.login, width: width, glint: true);
        await tester.binding.setSurfaceSize(shot.size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        LaunchGlint.debugReset();
        addTearDown(LaunchGlint.debugReset);
        final auth = StreamController<User?>();
        addTearDown(auth.close);
        debugDisableShadows = false;
        try {
          await tester.pumpWidget(
            _visualApp(
              shot,
              ProviderScope(
                overrides: [
                  authStateChangesProvider.overrideWith((ref) => auth.stream),
                ],
                child: const AuthGate(),
              ),
            ),
          );
          await _precacheMarks(
            tester,
            startupMark: tester
                .getSize(find.byKey(const ValueKey('startup-logo')))
                .width,
          );
          // Paint the first frame again, with no time elapsed, now that the
          // decoded images are in place (the native splash hands over here).
          tester.binding.scheduleFrame();
          await tester.pump(Duration.zero);
          auth.add(null);
          await _captureSequence(
            tester,
            'cold_launch_${width.toInt()}_dark_pl_100',
            length: const Duration(milliseconds: 3000),
            note: () {
              final startup = find.byType(StartupLoadingScreen);
              final notes = <String>[
                if (startup.evaluate().isNotEmpty) 'startup',
                if (find.byType(ResponsiveAuthScreen).evaluate().isNotEmpty)
                  'sign-in',
                if (find
                    .byKey(const ValueKey('startup-logo-glint'))
                    .evaluate()
                    .isNotEmpty)
                  'STARTUP GLINT',
                if (find
                    .byKey(const ValueKey('auth-logo-glint'))
                    .evaluate()
                    .isNotEmpty)
                  'AUTH GLINT',
              ];
              return notes.join(' + ');
            },
          );
          expect(LaunchGlint.spent, isTrue, reason: 'one glint this launch');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          debugDisableShadows = true;
        }
      },
    );

    testWidgets('Slim auth evidence — sign-in first paint sequence at '
        '${width.toInt()}', (tester) async {
      final shot = _Shot(screen: _Screen.login, width: width, glint: true);
      await tester.binding.setSurfaceSize(shot.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      LaunchGlint.debugReset();
      addTearDown(LaunchGlint.debugReset);
      debugDisableShadows = false;
      try {
        await tester.pumpWidget(
          _visualApp(shot, _home(shot, _VisualAuthService())),
        );
        await _precacheMarks(tester);
        tester.binding.scheduleFrame();
        await tester.pump(Duration.zero);
        await _captureSequence(
          tester,
          'auth_first_paint_${width.toInt()}_dark_pl_100',
          length: const Duration(milliseconds: 1250),
          note: () =>
              find
                  .byKey(const ValueKey('auth-logo-glint'))
                  .evaluate()
                  .isNotEmpty
              ? 'AUTH GLINT'
              : '',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}

/// Captures a frame every 50 ms of fake time from now through [length],
/// named `sequence/<name>_t<ms>ms`, and prints what each frame shows.
Future<void> _captureSequence(
  WidgetTester tester,
  String name, {
  required Duration length,
  required String Function() note,
}) async {
  const step = Duration(milliseconds: 50);
  for (var t = Duration.zero; t <= length; t += step) {
    if (t > Duration.zero) await tester.pump(step);
    final ms = t.inMilliseconds.toString().padLeft(4, '0');
    // ignore: avoid_print
    print('$name t=${ms}ms: ${note()}');
    await tester.runAsync(() => _capturePng('sequence/${name}_t${ms}ms'));
  }
}

Future<void> _captureShot(WidgetTester tester, _Shot shot) async {
  final service = _VisualAuthService(appleAvailability: shot.appleAvailability);
  await tester.pumpWidget(_visualApp(shot, _home(shot, service)));
  await _precacheMarks(tester);
  if (shot.glint || shot.reducedMotion) {
    // The pass is at the mark's centre 650 ms after first paint.
    for (var ms = 0; ms < 650; ms += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      find.byKey(const ValueKey('auth-logo-glint')),
      shot.reducedMotion ? findsNothing : findsOneWidget,
      reason: shot.reducedMotion
          ? 'Reduce Motion never glints'
          : 'the glint is mid-pass',
    );
    if (shot.reducedMotion) {
      expect(LaunchGlint.spent, isFalse, reason: 'the glint is left unused');
    }
  } else {
    await _settle(tester);
  }

  if (shot.screen == _Screen.checkInbox) {
    await tester.tap(find.byKey(const Key('send-reset-link')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }
  await _interact(tester, shot);

  expect(
    tester.takeException(),
    isNull,
    reason: 'A captured auth frame must not overflow or throw.',
  );
  if (shot.screen == _Screen.login &&
      shot.interaction == _Interaction.none &&
      shot.textScale == 1) {
    String height(String key) =>
        tester.getSize(find.byKey(ValueKey(key))).height.toStringAsFixed(1);
    // ignore: avoid_print
    print(
      '${shot.filename}: field ${height('auth-login-email')} px, '
      'submit ${height('auth-login-submit')} px, '
      'google ${height('auth-google-provider')} px, '
      'rail ${height('auth-mode-rail')} px',
    );
  }
  for (final key in const ['auth-login-submit', 'auth-gate-retry']) {
    final action = find.byKey(ValueKey(key));
    if (action.evaluate().isEmpty) continue;
    final label = find.descendant(of: action, matching: find.byType(Text));
    if (label.evaluate().isEmpty) continue;
    final box = tester.getRect(action);
    final text = tester.getRect(label.first);
    // ignore: avoid_print
    print(
      '${shot.filename}: $key ${box.width.toStringAsFixed(1)} x '
      '${box.height.toStringAsFixed(1)} px, label clearance top '
      '${(text.top - box.top).toStringAsFixed(1)} / bottom '
      '${(box.bottom - text.bottom).toStringAsFixed(1)} px',
    );
  }
  await tester.runAsync(() => _capturePng(shot.filename));
  await tester.pumpWidget(const SizedBox.shrink());
}
