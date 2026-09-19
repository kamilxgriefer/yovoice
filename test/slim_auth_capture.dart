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

import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:yovoice/features/auth/presentation/screens/responsive_auth_screen.dart';
import 'package:yovoice/features/auth/presentation/screens/verify_email_screen.dart';
import 'package:yovoice/services/firestore_service.dart';

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

  @override
  Future<AppleSignInAvailability> getAppleSignInAvailability() async =>
      appleAvailability;
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

enum _Screen { login, register, forgotPassword, checkInbox, verifyEmail }

enum _Interaction {
  none,
  focusSubmit,
  focusRail,
  focusGoogle,
  focusField,
  validationError,
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
  });

  final _Screen screen;
  final double width;
  final bool pearl;
  final double textScale;
  final String state;
  final _Interaction interaction;
  final AppleSignInAvailability appleAvailability;

  Size get size => Size(width, width >= 1000 ? 900 : 844);

  String get filename {
    final name = switch (screen) {
      _Screen.login => 'login',
      _Screen.register => 'register',
      _Screen.forgotPassword => 'forgot_password',
      _Screen.checkInbox => 'check_inbox',
      _Screen.verifyEmail => 'verify_email',
    };
    final theme = pearl ? 'pearl' : 'dark';
    final text = (textScale * 100).round();
    return '${name}_${width.toInt()}_${theme}_pl_${text}_$state';
  }
}

List<_Shot> _shots() => <_Shot>[
  for (final screen in const [_Screen.login, _Screen.register])
    for (final width in const [390.0, 1440.0])
      for (final pearl in const [false, true])
        _Shot(screen: screen, width: width, pearl: pearl),
  const _Shot(screen: _Screen.forgotPassword, width: 390),
  const _Shot(screen: _Screen.checkInbox, width: 390),
  const _Shot(screen: _Screen.verifyEmail, width: 390),
  // Focus, validation, availability and 200 % text evidence.
  const _Shot(
    screen: _Screen.login,
    width: 1440,
    state: 'focus-submit',
    interaction: _Interaction.focusSubmit,
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
  const _Shot(screen: _Screen.login, width: 390, textScale: 2),
  const _Shot(screen: _Screen.forgotPassword, width: 390, textScale: 2),
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

Widget _home(_Shot shot, AuthService service) {
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
  };
}

Widget _visualApp(_Shot shot, AuthService service) {
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
          disableAnimations: true,
          textScaler: TextScaler.linear(shot.textScale),
        ),
        child: child!,
      ),
    ),
    home: _home(shot, service),
  );
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
      _focusNearest(tester, find.byKey(const ValueKey('auth-login-submit')));
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

      final service = _VisualAuthService(
        appleAvailability: shot.appleAvailability,
      );
      await tester.pumpWidget(_visualApp(shot, service));
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/images/yo-voice-favicon-512.png'),
          _captureKey.currentContext!,
        ),
      );
      await _settle(tester);

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
      await tester.runAsync(() => _capturePng(shot.filename));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
