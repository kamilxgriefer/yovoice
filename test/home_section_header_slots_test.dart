import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/layout/home_section_header.dart';

/// The one section heading (Slim redesign, phase 0): `HomeSectionHeader`
/// grew three slots — `leading`, `subtitle`, `trailing` — and a
/// `seeAllVocabulary` so the notifications inbox, the Awards hub, Discover
/// and the desktop Voice Trending card could drop their private copies.
/// `test/home_rhythm_test.dart` freezes the Home contract (24 / ink / 16,
/// stacking verdicts, a fixed box with or without "View all"); this file
/// pins that the new slots keep it.
void main() {
  const trailerKey = ValueKey('trailer');
  const leadingKey = ValueKey('leading');
  // Short on purpose: the test font draws every glyph one `fontSize` wide,
  // so a long heading would wrap the moment a trailer takes its slot and
  // the box would grow by a whole line for a reason that is not the slot.
  // Wrapping is home_rhythm_test's subject; the slots are this file's.
  const title = 'Live rooms';

  Widget app(
    Widget child, {
    double width = 600,
    double textScale = 1.0,
  }) => MaterialApp(
    theme: AppTheme.darkTheme,
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 900),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );

  Rect headerBox(WidgetTester tester) =>
      tester.getRect(find.byType(HomeSectionHeader));

  Rect titleRect(WidgetTester tester) => tester.getRect(find.text(title));

  for (final scale in HomeSectionHeaderScale.values) {
    for (final textScale in const [1.0, 2.0]) {
      testWidgets(
        '${scale.name} x$textScale: a trailer never changes the box, and '
        'is centred on the title ink at the trailing edge',
        (tester) async {
          await tester.pumpWidget(
            app(
              HomeSectionHeader(title: title, scale: scale),
              textScale: textScale,
            ),
          );
          final bare = headerBox(tester);

          // A 36 px icon box (Discover) and a 48 px control (the inbox's
          // "Mark all read" beside its pill) are both taller than a
          // 17 px title line at 100 %; neither may grow the box.
          for (final trailerHeight in const [36.0, 48.0]) {
            await tester.pumpWidget(
              app(
                HomeSectionHeader(
                  title: title,
                  scale: scale,
                  trailing: SizedBox(
                    key: trailerKey,
                    width: 36,
                    height: trailerHeight,
                    child: const ColoredBox(color: Colors.white),
                  ),
                ),
                textScale: textScale,
              ),
            );
            final box = headerBox(tester);
            final trailer = tester.getRect(find.byKey(trailerKey));
            final heading = titleRect(tester);

            expect(
              box.height,
              closeTo(bare.height, 0.5),
              reason: 'trailer $trailerHeight px grew the box',
            );
            expect(
              heading.top - box.top,
              closeTo(AppRhythm.section, 0.5),
              reason: 'title ink must still start at the section step',
            );
            expect(
              box.bottom - heading.bottom,
              closeTo(AppRhythm.title, 0.5),
              reason: 'title ink must still end a title step above the box',
            );
            expect(
              trailer.center.dy,
              closeTo(heading.center.dy, 0.5),
              reason: 'trailer is centred on the title ink',
            );
            expect(trailer.right, closeTo(box.right, 0.5));
            expect(
              trailer.left - heading.right,
              greaterThanOrEqualTo(AppRhythm.tight - 0.5),
              reason: 'the title yields the trailer its slot',
            );
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }

  testWidgets('a subtitle is part of the heading ink: 24 above the title, '
      '16 below the subtitle', (tester) async {
    const subtitle = 'The busiest conversations right now';
    await tester.pumpWidget(
      app(const HomeSectionHeader(title: title, subtitle: subtitle)),
    );
    final box = headerBox(tester);
    final heading = titleRect(tester);
    final secondary = tester.getRect(find.text(subtitle));

    expect(heading.top - box.top, closeTo(AppRhythm.section, 0.5));
    expect(
      secondary.top - heading.bottom,
      closeTo(AppRhythm.hairline, 0.5),
      reason: 'one lockup: title → subtitle is the hairline step',
    );
    expect(
      box.bottom - secondary.bottom,
      closeTo(AppRhythm.title, 0.5),
      reason: 'the subtitle owns the ink bottom',
    );
    expect(secondary.left, closeTo(heading.left, 0.5));

    // The subtitle is supporting copy, not part of the heading's name.
    final data = tester.getSemantics(find.text(title)).getSemanticsData();
    expect(data.flagsCollection.isHeader, isTrue);
    expect(data.label, title);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a leading glyph rides the title line and adds no ink', (
    tester,
  ) async {
    await tester.pumpWidget(app(const HomeSectionHeader(title: title)));
    final bare = headerBox(tester);

    await tester.pumpWidget(
      app(
        const HomeSectionHeader(
          title: title,
          leading: Icon(Icons.star_rounded, key: leadingKey, size: 16),
        ),
      ),
    );
    final box = headerBox(tester);
    final heading = titleRect(tester);
    final glyph = tester.getRect(find.byKey(leadingKey));

    expect(box.height, closeTo(bare.height, 0.5));
    expect(glyph.left, closeTo(box.left, 0.5));
    expect(glyph.center.dy, closeTo(heading.center.dy, 0.5));
    expect(heading.left - glyph.right, closeTo(AppRhythm.tight, 0.5));
    expect(heading.top - box.top, closeTo(AppRhythm.section, 0.5));
    expect(box.bottom - heading.bottom, closeTo(AppRhythm.title, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a trailer and a View all cannot share the slot',
    (tester) async {
      expect(
        () => HomeSectionHeader(
          title: title,
          onSeeAll: () {},
          trailing: const SizedBox.shrink(),
        ),
        throwsAssertionError,
      );
    },
  );

  testWidgets('seeAllVocabulary decides the arrangement, not the rendered '
      'label', (tester) async {
    const label = 'See all rooms';
    const width = 768.0;

    Future<(Rect title, Rect button)> pump(
      Iterable<String>? vocabulary,
    ) async {
      await tester.pumpWidget(
        app(
          HomeSectionHeader(
            title: title,
            seeAllLabel: label,
            seeAllVocabulary: vocabulary,
            onSeeAll: () {},
          ),
          width: width,
          textScale: 2.0,
        ),
      );
      expect(find.text(label), findsOneWidget);
      return (titleRect(tester), tester.getRect(find.byType(TextButton)));
    }

    // A slate at 200 % keeps a Home-sized action on the heading's line
    // (test/home_rhythm_test.dart pins the same verdict for Home).
    final (homeTitle, homeButton) = await pump(null);
    expect(
      homeButton.top < homeTitle.bottom - 0.5,
      isTrue,
      reason: 'default vocabulary keeps the action beside the title',
    );

    // The same heading, the same rendered label, on a page whose widest
    // action would cost more than a third of the row: it stacks, because
    // the page's vocabulary, not this heading's words, answers the test.
    final (pageTitle, pageButton) = await pump(const [
      'See every single one of the conversations happening right now',
    ]);
    expect(
      pageButton.top >= pageTitle.bottom - 0.5,
      isTrue,
      reason: 'a wide page vocabulary stacks every heading on that page',
    );

    // Either way the rhythm is the same two numbers.
    final box = headerBox(tester);
    expect(pageTitle.top - box.top, closeTo(AppRhythm.section, 0.5));
    expect(tester.takeException(), isNull);
  });
}
