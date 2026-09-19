// Developer-only visual QA harness for Settings → Account → Delete account.
//
// The filename deliberately has no `_test` suffix, so the ordinary suite
// skips it. Run explicitly:
//
//   flutter test test/delete_account_screenshot.dart
//
// PNGs land in test/.screenshots/ (git-ignored), named
// `app-delete-{width}-{locale}-{textScalePercent}-{state}.png`.
//
// THE MATRIX IS THE ONE docs/TESTING.md PUBLISHES: 320 / 402 / 834 / 1400,
// English and Polish, 100 % and 200 % text — and it covers all four states of
// the flow, not only the first. An earlier revision of this file captured
// 390/820/1440 and the review stage only, which is how a pending panel whose
// sentence contradicted the code went four rounds without anyone seeing it.
// The widths are device widths a reviewer actually uses: the narrowest phone
// still supported, a current iPhone, an iPad portrait, and a desktop shell.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/account/data/account_deletion_service.dart';
import 'package:yovoice/features/auth/data/reauthentication_service.dart';
import 'package:yovoice/features/settings/presentation/screens/delete_account_screen.dart';

final _capture = GlobalKey();

String get _fontRoot {
  const candidates = [
    '/opt/homebrew/Caskroom/flutter/3.44.6/flutter/bin/cache/artifacts/material_fonts',
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts',
    '/usr/local/share/flutter/bin/cache/artifacts/material_fonts',
  ];
  return candidates.firstWhere(
    (path) => File('$path/Roboto-Regular.ttf').existsSync(),
  );
}

Future<void> _loadFonts() async {
  Future<ByteData> read(String name) async {
    final bytes = File('$_fontRoot/$name').readAsBytesSync();
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }

  final roboto = FontLoader('Roboto');
  for (final face in const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]) {
    roboto.addFont(read(face));
  }
  await roboto.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(read('MaterialIcons-Regular.otf'))).load();

  // The product typeface. Without it every glyph renders as a tofu box and
  // the capture proves nothing about the real screen.
  final inter = FontLoader('Inter')
    ..addFont(
      Future.value(
        ByteData.view(
          Uint8List.fromList(
            File('assets/fonts/InterVariable.ttf').readAsBytesSync(),
          ).buffer,
        ),
      ),
    );
  await inter.load();
}

class _Reauth implements ReauthenticationClient {
  @override
  List<String> get providerIds => const ['password'];
  @override
  Future<void> reauthenticateWithApple() async {}
  @override
  Future<void> reauthenticateWithGoogle() async {}
  @override
  Future<void> reauthenticateWithPassword(String password) async {}
}

class _Deletion implements AccountDeletionClient {
  @override
  Future<AccountDeletionReceipt> requestDeletion() async =>
      const AccountDeletionReceipt(state: AccountDeletionState.pending);
}

/// The RepaintBoundary wraps the WHOLE MaterialApp so dialog overlays are
/// inside the captured tree.
Widget _host({
  required bool isRootTab,
  required double textScale,
  required Locale locale,
}) => RepaintBoundary(
  key: _capture,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: locale,
    theme: AppTheme.darkTheme,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: DeleteAccountScreen(
      isRootTab: isRootTab,
      reauthentication: _Reauth(),
      deletionClient: _Deletion(),
      signOut: () async {},
      openUrl: (_) async {},
    ),
  ),
);

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('test/.screenshots/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path}');
    } finally {
      image.dispose();
    }
  });
}

/// Scrolls the review column to its end, so the frame shows the destructive
/// button and the e-mail fallback rather than only the top of the page. At
/// 200 % text this is where the long sentences actually land.
Future<void> _toBottom(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable).first;
  await tester.drag(scrollable, const Offset(0, -4000));
  await tester.pumpAndSettle();
}

/// The four device sizes docs/TESTING.md names. The heights are the real
/// companions of those widths; at 200 % text the canvas is made taller so a
/// dialog has somewhere to be rather than being clipped by the viewport, which
/// would make the frame useless as evidence of the dialog's own layout.
const _viewports = <(String, double, double)>[
  ('320', 320, 640),
  ('402', 402, 874),
  ('834', 834, 1112),
  ('1400', 1400, 900),
];

/// Label, locale, a string that appears ONLY when the retained set is open,
/// and the word the confirmation dialog demands.
const _locales = <(String, Locale, String, String)>[
  (
    'en',
    Locale('en'),
    'Payment records we are required by law to keep. They contain no card '
        'details.',
    'DELETE',
  ),
  (
    'pl',
    Locale('pl'),
    'Dokumenty płatnicze, które musimy przechowywać zgodnie z prawem. '
        'Nie zawierają danych karty.',
    'USUŃ',
  ),
];

void main() {
  setUpAll(_loadFonts);

  for (final (widthLabel, width, height) in _viewports) {
    for (final (localeLabel, locale, retainedProbe, confirmWord) in _locales) {
      for (final scale in const [1.0, 2.0]) {
        final scaleLabel = (scale * 100).round().toString();
        final name = 'app-delete-$widthLabel-$localeLabel-$scaleLabel';

        testWidgets(name, (tester) async {
          tester.view.devicePixelRatio = 1;
          // A 200 % canvas gets the extra room a real device gets from its
          // own scrolling, so the dialogs below are captured whole.
          tester.view.physicalSize = Size(width, scale > 1 ? height * 1.6 : height);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            _host(
              // The desktop shell owns navigation at and above the screen's
              // own wide breakpoint (1024).
              isRootTab: width >= 1024,
              textScale: scale,
              locale: locale,
            ),
          );
          await tester.pumpAndSettle();

          // 1. Consequences — the list of what deletion does.
          await _shoot(tester, '$name-review');

          // 2. Consequences with the retained set open: the part a store
          //    reviewer has to be able to read.
          // Scroll to it BEFORE tapping. At 320 dp and 200 % text the expander
          // sits far below the fold, and a tap aimed at a widget whose centre
          // is outside the viewport lands on nothing: the first version of
          // this harness captured sixteen frames of a tile it had never
          // managed to open.
          await tester.ensureVisible(
            find.byKey(const ValueKey('delete-account-retained')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('delete-account-retained')));
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const ValueKey('delete-account-retained')),
          );
          await tester.pumpAndSettle();
          // The tile must actually be open, or the frame documents nothing.
          expect(
            find.text(retainedProbe),
            findsOneWidget,
            reason: 'the retained set must be expanded in $name-retained',
          );
          await _shoot(tester, '$name-retained');

          // 3. The bottom of the same column: destructive button, web link,
          //    e-mail fallback.
          await _toBottom(tester);
          await _shoot(tester, '$name-bottom');

          // 4. Re-authentication.
          await tester.ensureVisible(
            find.byKey(const ValueKey('delete-account-primary')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('delete-account-primary')));
          await tester.pumpAndSettle();
          await _shoot(tester, '$name-password');

          await tester.enterText(
            find.byKey(const ValueKey('delete-account-password-field')),
            'hunter2',
          );
          await tester.tap(
            find.byKey(const ValueKey('delete-account-password-submit')),
          );
          await tester.pumpAndSettle();

          // 5. Confirmation, inert then armed — the destructive control is
          //    disabled until the word is typed, and that must be visible.
          await _shoot(tester, '$name-confirm-inert');
          await tester.enterText(
            find.byKey(const ValueKey('delete-account-confirm-field')),
            confirmWord,
          );
          await tester.pumpAndSettle();
          await _shoot(tester, '$name-confirm-armed');

          // 6. The pending panel. THE FRAME THIS HARNESS EXISTS FOR: its
          //    sentence is a claim about the session, and a frame is the only
          //    thing that shows the claim as the person reads it.
          await tester.tap(
            find.byKey(const ValueKey('delete-account-confirm-submit')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('delete-account-pending')),
            findsOneWidget,
          );
          await _shoot(tester, '$name-pending');
        });
      }
    }
  }
}
