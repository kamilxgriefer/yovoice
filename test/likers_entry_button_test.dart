// The "See who liked ›" entry (ADR-230, owner variant A) at 320 px and
// 200 % text, measured in the real Inter face: the visible name wraps rather
// than truncating in the languages where it no longer fits one line, and the
// chevron stays with the last word (WCAG 1.4.4).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/likers/presentation/likers_copy.dart';
import 'package:yovoice/features/likers/presentation/widgets/likers_entry_button.dart';

import 'support/likers_fixtures.dart';

Future<void> _loadInter() async {
  ByteData read(String path) {
    final bytes = Uint8List.fromList(File(path).readAsBytesSync());
    return ByteData.view(bytes.buffer);
  }

  final inter = FontLoader('Inter')
    ..addFont(Future.value(read('assets/fonts/InterVariable.ttf')));
  await inter.load();
}

void main() {
  setUpAll(_loadInter);

  const locales = <Locale>[
    Locale('pl'),
    Locale('ru'),
    Locale('uk'),
    Locale('fi'),
    Locale('el'),
    Locale('en'),
    Locale('de'),
  ];

  for (final locale in locales) {
    testWidgets('${locale.languageCode}: 320 px, 200 % text — the label '
        'wraps whole, the chevron stays on its last line', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        likersHost(
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: AlignmentDirectional.topStart,
                child: Builder(
                  builder: (context) => LikersEntryButton(
                    key: const ValueKey('entry'),
                    label: LikersCopy(AppLocalizations.of(context)).seeWhoLiked,
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          ),
          locale: locale,
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      final labelText = find.descendant(
        of: find.byKey(const ValueKey('entry')),
        matching: find.text(LikersCopy(AppLocalizations(locale)).seeWhoLiked),
      );
      expect(labelText, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(labelText);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.maxLines, isNull);
      expect(paragraph.overflow, isNot(TextOverflow.ellipsis));
      // Every glyph is laid out: the paragraph is as tall as its lines need.
      expect(
        paragraph.size.height,
        greaterThanOrEqualTo(
          paragraph.getMaxIntrinsicHeight(paragraph.size.width) - .5,
        ),
      );

      final button = tester.getRect(find.byKey(const ValueKey('entry')));
      expect(button.right, lessThanOrEqualTo(304.5));
      expect(button.height, greaterThanOrEqualTo(48));

      // The chevron stays inside the button beside the label block, never
      // alone on a line of its own.
      final chevron = tester.getRect(find.byIcon(Icons.chevron_right_rounded));
      final text = tester.getRect(labelText);
      expect(chevron.left, greaterThanOrEqualTo(text.right - .5));
      expect(chevron.right, lessThanOrEqualTo(button.right + .5));
      expect(chevron.center.dy, inInclusiveRange(text.top, text.bottom));
    });
  }
}
