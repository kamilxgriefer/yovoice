import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/settings/presentation/screens/settings_screen.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';

/// S-11: the Settings header title ran off the right edge at large text.
///
/// The header `Row` is `[YoIconButton(40), SizedBox(6), Text(fontSize: 26)]`.
/// The title was the last child with no flex, no `maxLines` and no `overflow`,
/// so once a reader asked for 200 % text the ~52 px "Ustawienia" simply kept
/// going: `RenderFlex` reported an overflow and the word was cut by the screen
/// edge rather than by an ellipsis.
///
/// These tests pump [SettingsHeaderBar] rather than [SettingsScreen] — the
/// screen constructs its own `ProfileService`/`AuthService` and its profile
/// stream throws `Bad state: User is not signed in` the moment `build()` runs
/// under `flutter test`, so the whole screen renders nothing. The header is the
/// widget that overflowed, and it pumps with no Firebase app at all.
///
/// The assertions are deliberately font-independent: they demand that the title
/// stay *inside* the row, not that any particular string fit. `flutter test`
/// substitutes a fallback face whose glyphs are far wider than shipped Inter,
/// so a "does it fit" assertion would be measuring the harness.
void main() {
  Future<void> pumpHeader(
    WidgetTester tester, {
    required Size size,
    required String locale,
    required bool showBackButton,
    required TextScaler textScaler,
    VoidCallback? onBack,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        debugShowCheckedModeBanner: false,
        locale: Locale(locale),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: Scaffold(
          body: Column(
            children: [
              SettingsHeaderBar(
                showBackButton: showBackButton,
                onBack: onBack ?? () {},
              ),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  String titleFor(String locale) => locale == 'pl' ? 'Ustawienia' : 'Settings';

  /// The header's own `Row`, which is what reported the overflow.
  Finder headerRow() => find
      .descendant(
        of: find.byType(SettingsHeaderBar),
        matching: find.byType(Row),
      )
      .first;

  void expectTitleInsideRow(WidgetTester tester, String title) {
    final titleFinder = find.text(title);
    expect(titleFinder, findsOneWidget, reason: 'the title must still render');

    final rowRect = tester.getRect(headerRow());
    final titleRect = tester.getRect(titleFinder);
    expect(
      titleRect.right,
      lessThanOrEqualTo(rowRect.right + 0.01),
      reason:
          'the title ends at ${titleRect.right} but the header row ends at '
          '${rowRect.right} — the title is running past the right edge',
    );
    expect(
      titleRect.left,
      greaterThanOrEqualTo(rowRect.left - 0.01),
      reason: 'the title starts outside the header row',
    );
  }

  // 320 is the narrowest phone the app ships to, 390 a current iPhone, 834 an
  // iPad in portrait and 1440 the desktop shell. The header must behave at all
  // four; only the narrow ones could overflow, and the wide ones prove the fix
  // did not turn the title into a stretched or re-aligned block.
  const viewports = <({String name, Size size})>[
    (name: 'narrow 320', size: Size(320, 720)),
    (name: 'phone 390', size: Size(390, 844)),
    (name: 'tablet 834', size: Size(834, 1112)),
    (name: 'desktop 1440', size: Size(1440, 900)),
  ];

  for (final viewport in viewports) {
    for (final locale in <String>['en', 'pl']) {
      for (final showBackButton in <bool>[true, false]) {
        testWidgets('${viewport.name} · $locale · '
            '${showBackButton ? 'pushed route' : 'root tab'}: the title stays '
            'inside the header at 200 % text', (tester) async {
          await pumpHeader(
            tester,
            size: viewport.size,
            locale: locale,
            showBackButton: showBackButton,
            textScaler: const TextScaler.linear(2),
          );

          expectTitleInsideRow(tester, titleFor(locale));
          expect(
            tester.takeException(),
            isNull,
            reason: 'the header row must not overflow at 200 % text',
          );
        });
      }
    }

    testWidgets(
      '${viewport.name}: the default text size renders the header unchanged',
      (tester) async {
        await pumpHeader(
          tester,
          size: viewport.size,
          locale: 'en',
          showBackButton: true,
          textScaler: TextScaler.noScaling,
        );

        // Still flush against the 6 px gap after the Back button: the fix
        // must not have shifted, centred or indented the title.
        expect(
          tester.getTopLeft(find.text('Settings')).dx,
          closeTo(tester.getRect(find.byType(YoIconButton)).right + 6, 0.01),
        );
        expectTitleInsideRow(tester, 'Settings');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a root tab draws no Back button, a pushed route does', (
    tester,
  ) async {
    await pumpHeader(
      tester,
      size: const Size(390, 844),
      locale: 'en',
      showBackButton: false,
      textScaler: TextScaler.noScaling,
    );
    expect(find.byType(YoIconButton), findsNothing);
    expect(tester.getTopLeft(find.text('Settings')).dx, 6);

    await pumpHeader(
      tester,
      size: const Size(390, 844),
      locale: 'en',
      showBackButton: true,
      textScaler: TextScaler.noScaling,
    );
    expect(find.byType(YoIconButton), findsOneWidget);
  });

  testWidgets('the Back button still calls back', (tester) async {
    var pops = 0;
    await pumpHeader(
      tester,
      size: const Size(390, 844),
      locale: 'en',
      showBackButton: true,
      textScaler: TextScaler.noScaling,
      onBack: () => pops += 1,
    );

    await tester.tap(find.byType(YoIconButton));
    await tester.pump();

    expect(pops, 1);
  });
}
