// Developer-only visual QA harness for the YO Voice TOTP challenge.
//
// Run explicitly:
//   flutter test \
//     --dart-define=TOTP_SCREENSHOT_DIR=/private/tmp/yovoice-totp-visual-qa \
//     test/totp_challenge_screenshot.dart
//
// This file deliberately does not end in `_test.dart`, so the normal test
// suite never emits screenshots. All identities and codes are synthetic.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/auth/data/totp_mfa_service.dart';
import 'package:yovoice/features/auth/presentation/screens/totp_challenge_screen.dart';

import 'totp_challenge_test_support.dart';

const _screenshotDirectory = String.fromEnvironment(
  'TOTP_SCREENSHOT_DIR',
  defaultValue: '/private/tmp/yovoice-totp-visual-qa',
);

final _captureKey = GlobalKey();

enum _ShotState {
  empty,
  threeDigits,
  midOrbit,
  success,
  invalid,
  reducedMotion,
  multipleFactors,
}

extension on _ShotState {
  String get filename => switch (this) {
    _ShotState.empty => 'empty',
    _ShotState.threeDigits => 'three-digits',
    _ShotState.midOrbit => 'mid-orbit',
    _ShotState.success => 'success',
    _ShotState.invalid => 'invalid-red-x',
    _ShotState.reducedMotion => 'reduced-motion',
    _ShotState.multipleFactors => 'multiple-factors',
  };
}

class _ShotConfiguration {
  const _ShotConfiguration({
    required this.name,
    required this.size,
    required this.state,
    this.textScaler = TextScaler.noScaling,
  });

  final String name;
  final Size size;
  final _ShotState state;
  final TextScaler textScaler;
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

Widget _visualApp({
  required TotpSignInChallengeClient challenge,
  required _ShotConfiguration configuration,
}) {
  final reducedMotion = configuration.state == _ShotState.reducedMotion;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.darkTheme,
    builder: (context, child) => RepaintBoundary(
      key: _captureKey,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          accessibleNavigation: reducedMotion,
          disableAnimations: reducedMotion,
          textScaler: configuration.textScaler,
        ),
        child: child!,
      ),
    ),
    home: TotpChallengeScreen(challenge: challenge),
  );
}

Future<void> _primeFrame(WidgetTester tester) async {
  for (var frame = 0; frame < 5; frame++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<void> _capturePng(WidgetTester tester, String filename) async {
  await tester.runAsync(() async {
    final boundary =
        _captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;

    // Prime the font, icon and logo atlases before collecting evidence.
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
  });
}

Future<void> _enterSyntheticCode(
  WidgetTester tester, {
  required String code,
}) async {
  await tester.enterText(find.byKey(totpCodeInputKey), code);
  await tester.pump();
}

Future<void> _reachOrbitEntry(WidgetTester tester) async {
  // 120 ms auto-submit debounce + 120 ms compression.
  await tester.pump(const Duration(milliseconds: 121));
  await tester.pump(const Duration(milliseconds: 120));
}

Future<void> _driveState(
  WidgetTester tester,
  _ShotState state,
  Completer<void>? pending,
) async {
  switch (state) {
    case _ShotState.empty:
      expect(find.byKey(totpMotionStageKey), findsOneWidget);
    case _ShotState.threeDigits:
      await _enterSyntheticCode(tester, code: '123');
      await tester.pump(const Duration(milliseconds: 140));
      expect(find.byKey(totpDigitCellKey(2)), findsOneWidget);
    case _ShotState.midOrbit:
      await _enterSyntheticCode(tester, code: '123456');
      await _reachOrbitEntry(tester);
      await tester.pump(const Duration(milliseconds: 160));
      expect(find.byKey(totpNodeKey(0)), findsOneWidget);
    case _ShotState.success:
      await _enterSyntheticCode(tester, code: '123456');
      await _reachOrbitEntry(tester);
      await tester.pump(const Duration(milliseconds: 320));
      await tester.pump(const Duration(milliseconds: 180));
      pending!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 660));
      expect(find.byKey(totpSuccessBadgeKey), findsOneWidget);
      expect(find.byKey(totpSuccessCheckKey), findsOneWidget);
    case _ShotState.invalid:
      await _enterSyntheticCode(tester, code: '123456');
      await _reachOrbitEntry(tester);
      await tester.pump(const Duration(milliseconds: 180));
      pending!.completeError(
        FirebaseAuthException(
          code: 'invalid-verification-code',
          message: 'Synthetic invalid-code response.',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Invalid feedback is intentionally a red X, never the green success
      // check. The later interaction assertion verifies clear + refocus.
      expect(find.byKey(totpInvalidBadgeKey), findsOneWidget);
      expect(find.byKey(totpInvalidXKey), findsOneWidget);
      expect(find.byKey(totpSuccessBadgeKey), findsNothing);
    case _ShotState.reducedMotion:
      await _enterSyntheticCode(tester, code: '123456');
      await tester.pump(const Duration(milliseconds: 121));
      await tester.pump(const Duration(milliseconds: 140));
      expect(find.byKey(totpStatusChannelKey), findsOneWidget);
      expect(find.text('Verifying code'), findsOneWidget);
    case _ShotState.multipleFactors:
      expect(find.byKey(totpFactorDropdownKey), findsOneWidget);
  }
}

List<_ShotConfiguration> _configurations() {
  final configurations = <_ShotConfiguration>[];
  for (final (name, size) in <(String, Size)>[
    ('390x844', const Size(390, 844)),
    ('1440x900', const Size(1440, 900)),
  ]) {
    for (final state in _ShotState.values) {
      configurations.add(
        _ShotConfiguration(name: name, size: size, state: state),
      );
    }
  }
  configurations.addAll(const <_ShotConfiguration>[
    _ShotConfiguration(
      name: '320x640-text-200',
      size: Size(320, 640),
      state: _ShotState.threeDigits,
      textScaler: TextScaler.linear(2),
    ),
    _ShotConfiguration(
      name: '320x640-text-200',
      size: Size(320, 640),
      state: _ShotState.multipleFactors,
      textScaler: TextScaler.linear(2),
    ),
  ]);
  return configurations;
}

void main() {
  setUpAll(_loadRealFonts);

  for (final configuration in _configurations()) {
    testWidgets(
      'TOTP visual evidence — ${configuration.name} ${configuration.state.filename}',
      (tester) async {
        useTotpSurface(tester, configuration.size);

        final requiresPending = <_ShotState>{
          _ShotState.midOrbit,
          _ShotState.success,
          _ShotState.invalid,
          _ShotState.reducedMotion,
        }.contains(configuration.state);
        final factors = configuration.state == _ShotState.multipleFactors
            ? const <TotpSignInFactor>[
                TotpSignInFactor(
                  uid: 'synthetic-primary',
                  displayName: 'Synthetic authenticator',
                ),
                TotpSignInFactor(
                  uid: 'synthetic-secondary',
                  displayName:
                      'Synthetic studio authenticator with a long label',
                ),
              ]
            : null;
        final challenge = FakeTotpChallenge(factors: factors);
        final pending = requiresPending ? challenge.enqueuePending() : null;

        await tester.pumpWidget(
          _visualApp(challenge: challenge, configuration: configuration),
        );
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/images/yo-voice-favicon-512.png'),
            _captureKey.currentContext!,
          ),
        );
        await _primeFrame(tester);
        await _driveState(tester, configuration.state, pending);

        expect(
          tester.takeException(),
          isNull,
          reason: 'A captured TOTP frame must not overflow or throw.',
        );
        await _capturePng(
          tester,
          '${configuration.name}-${configuration.state.filename}',
        );

        if (configuration.state == _ShotState.invalid) {
          await tester.pump(const Duration(milliseconds: 900));
          final editable = tester.widget<EditableText>(
            find.descendant(
              of: find.byKey(totpCodeInputKey),
              matching: find.byType(EditableText),
            ),
          );
          expect(editable.controller.text, isEmpty);
          expect(editable.focusNode.hasFocus, isTrue);
        }

        if (pending != null && !pending.isCompleted) {
          await tester.pumpWidget(const SizedBox.shrink());
          pending.complete();
          await tester.pump();
        }
      },
    );
  }
}
