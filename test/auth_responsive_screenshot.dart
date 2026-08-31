// Developer-only visual QA harness for the responsive YO Voice auth shell.
//
// Run explicitly:
//   flutter test \
//     --dart-define=AUTH_SCREENSHOT_DIR=/private/tmp/yovoice-auth-visual-qa \
//     test/auth_responsive_screenshot.dart
//
// This file deliberately does not end in `_test.dart`, so routine test runs
// never create artifacts. Accounts and provider responses are synthetic.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/screens/responsive_auth_screen.dart';
import 'package:yovoice/services/firestore_service.dart';

const _screenshotDirectory = String.fromEnvironment(
  'AUTH_SCREENSHOT_DIR',
  defaultValue: '/private/tmp/yovoice-auth-visual-qa',
);

final _captureKey = GlobalKey();

class _VisualAuthService extends AuthService {
  _VisualAuthService()
    : super(
        firebaseAuth: MockFirebaseAuth(),
        firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      );

  @override
  Future<AppleSignInAvailability> getAppleSignInAvailability() async =>
      AppleSignInAvailability.available;
}

class _ShotConfiguration {
  const _ShotConfiguration({
    required this.filename,
    required this.size,
    required this.mode,
    this.locale = const Locale('en'),
    this.textScaler = TextScaler.noScaling,
    this.captureCurtain = false,
  });

  final String filename;
  final Size size;
  final AuthMode mode;
  final Locale locale;
  final TextScaler textScaler;
  final bool captureCurtain;
}

List<_ShotConfiguration> _shots() {
  final shots = <_ShotConfiguration>[];
  for (final (name, size) in <(String, Size)>[
    ('320x568', const Size(320, 568)),
    ('390x667', const Size(390, 667)),
    ('430x844', const Size(430, 844)),
    ('600x960', const Size(600, 960)),
    ('999x800', const Size(999, 800)),
    ('1000x700', const Size(1000, 700)),
    ('1440x900', const Size(1440, 900)),
  ]) {
    for (final mode in AuthMode.values) {
      shots.add(
        _ShotConfiguration(
          filename: '$name-${mode.name}',
          size: size,
          mode: mode,
        ),
      );
    }
  }
  shots.addAll(const <_ShotConfiguration>[
    _ShotConfiguration(
      filename: '320x568-login-text-200',
      size: Size(320, 568),
      mode: AuthMode.login,
      textScaler: TextScaler.linear(2),
    ),
    _ShotConfiguration(
      filename: '320x568-register-text-200',
      size: Size(320, 568),
      mode: AuthMode.register,
      textScaler: TextScaler.linear(2),
    ),
    _ShotConfiguration(
      filename: '430x844-register-pl',
      size: Size(430, 844),
      mode: AuthMode.register,
      locale: Locale('pl'),
    ),
    _ShotConfiguration(
      filename: '1000x700-curtain',
      size: Size(1000, 700),
      mode: AuthMode.login,
      captureCurtain: true,
    ),
  ]);
  return shots;
}

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

Widget _visualApp(_ShotConfiguration configuration) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.darkTheme,
    locale: configuration.locale,
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
          accessibleNavigation: !configuration.captureCurtain,
          disableAnimations: !configuration.captureCurtain,
          textScaler: configuration.textScaler,
        ),
        child: child!,
      ),
    ),
    home: ResponsiveAuthScreen(
      initialMode: configuration.mode,
      authService: _VisualAuthService(),
    ),
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
    final file = File('$_screenshotDirectory/$filename.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    // ignore: avoid_print
    print('wrote ${file.path}');
  } finally {
    image.dispose();
  }
}

void main() {
  setUpAll(_loadRealFonts);

  for (final configuration in _shots()) {
    testWidgets('Auth visual evidence — ${configuration.filename}', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(configuration.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_visualApp(configuration));
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/images/yo-voice-favicon-512.png'),
          _captureKey.currentContext!,
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump(const Duration(milliseconds: 40));

      if (configuration.captureCurtain) {
        await tester.tap(find.byKey(const ValueKey('auth-mode-register')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
      }

      expect(
        tester.takeException(),
        isNull,
        reason: 'A captured auth frame must not overflow or throw.',
      );
      await tester.runAsync(() => _capturePng(configuration.filename));
    });
  }
}
