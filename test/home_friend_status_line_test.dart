import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_friend_tile.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';

// Refine-look review round, D4: a friend's status line on Start's rail sits
// in the rail's shared column (avatar radius 28 × 2.4 = 67.2 px). The word
// "przeszkadzać" is wider than that in Inter, and a two-line wrap let
// Flutter split it mid-word ("Nie przeszk / adzać", seen in the Start error
// frame). A label whose longest word does not fit now stays on one line and
// ends in an ellipsis; every other label keeps its two-line word wrap.
//
// Widths only mean something in the font the app ships, so Inter is loaded
// (the default test font draws every glyph as a 1 em square).

const double _radius = 28;

Widget _host(Widget child, {double textScale = 1}) => MaterialApp(
  locale: const Locale('pl'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: AppTheme.darkTheme,
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: Align(alignment: Alignment.topLeft, child: child),
    ),
  ),
);

/// Two neighbouring letters of one word must sit on the same line.
void _expectNoWordBrokenAcrossLines(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final text = paragraph.text.toPlainText();
  double topOf(int index) => paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: index, extentOffset: index + 1),
      )
      .first
      .top;
  for (var index = 1; index < text.length; index++) {
    if (text[index] == ' ' || text[index - 1] == ' ') continue;
    // Past the ellipsis point there are no boxes to compare.
    if (paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: index, extentOffset: index + 1),
        )
        .isEmpty) {
      break;
    }
    expect(
      topOf(index),
      closeTo(topOf(index - 1), 0.5),
      reason: '"$text" broke inside a word before offset $index',
    );
  }
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'));
    await loader.load();
  });

  for (final scale in <double>[1, 2]) {
    testWidgets('"Nie przeszkadzać" in a friend column at ${scale}x is cut '
        'with an ellipsis on one line, never split mid-word', (tester) async {
      await tester.pumpWidget(
        _host(
          HomeFriendTile(
            displayName: 'Marek',
            status: PeopleStatus.busy,
            onOpenProfile: () {},
            avatarRadius: _radius,
            labelWidth: _radius * 2.4 * scale,
          ),
          textScale: scale,
        ),
      );
      expect(tester.takeException(), isNull);
      final status = find.byKey(const ValueKey('home-friend-status'));
      final text = tester.widget<Text>(status);
      expect(text.data, 'Nie przeszkadzać');
      expect(text.maxLines, 1);
      expect(text.softWrap, isFalse);
      expect(text.overflow, TextOverflow.ellipsis);
      final paragraph = tester.renderObject<RenderParagraph>(status);
      expect(paragraph.didExceedMaxLines, isTrue, reason: 'it is ellipsised');
      _expectNoWordBrokenAcrossLines(tester, status);

      // A reader still hears the whole presence word.
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.byType(HomeFriendTile)),
        isSemantics(label: 'Marek', value: 'Nie przeszkadzać'),
      );
      handle.dispose();
    });
  }

  testWidgets('a status whose words fit keeps its two-line word wrap', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        HomeFriendTile(
          displayName: 'Ada',
          status: PeopleStatus.inRoom,
          onOpenProfile: () {},
          avatarRadius: _radius,
          labelWidth: _radius * 2.4,
        ),
      ),
    );
    final status = find.byKey(const ValueKey('home-friend-status'));
    final text = tester.widget<Text>(status);
    expect(text.data, 'Na kanale głosowym');
    expect(text.maxLines, 2);
    expect(text.softWrap, isNot(isFalse));
    _expectNoWordBrokenAcrossLines(tester, status);
  });

  testWidgets('the own tile, whose column widens to its longest word, keeps '
      'the full "Nie przeszkadzać" on two lines', (tester) async {
    late double width;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) {
            width = HomeFriendTile.statusColumnMinimumWidth(
              context,
              'Nie przeszkadzać',
              showCaret: true,
            );
            return HomeFriendTile(
              displayName: 'Ty',
              status: PeopleStatus.busy,
              statusLabel: 'Nie przeszkadzać',
              showChangeCaret: true,
              onOpenProfile: () {},
              avatarRadius: _radius,
              labelWidth: width,
            );
          },
        ),
      ),
    );
    final status = find.byKey(const ValueKey('home-friend-status'));
    final text = tester.widget<Text>(status);
    expect(text.maxLines, 2);
    expect(
      tester.renderObject<RenderParagraph>(status).didExceedMaxLines,
      isFalse,
    );
    _expectNoWordBrokenAcrossLines(tester, status);
  });
}
