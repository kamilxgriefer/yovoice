import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';

class _NoStaffCapabilities extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      StaffCapabilities.none;
}

/// The clipping case measures text, so it has to measure the text the phone
/// actually draws: the default test font is a fixed 1em-per-glyph box, which
/// is far wider than Inter and would answer a question no user ever asks.
/// Declared after the tests that rely on the default font, which run first.
Future<void> _loadInter() async {
  Future<ByteData> read(String path) async {
    final bytes = Uint8List.fromList(File(path).readAsBytesSync());
    return ByteData.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
  }

  final inter = FontLoader('Inter')
    ..addFont(read('assets/fonts/InterVariable.ttf'))
    ..addFont(read('assets/fonts/InterVariable-Italic.ttf'));
  await inter.load();
}

void main() {
  testWidgets(
    '320px and 2x text use readable rows with reachable named 44px actions',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SizedBox.expand(
                child: MoreSheet(
                  capabilityService: _NoStaffCapabilities(),
                  currentUid: 'ordinary-user',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Clubs'), findsNothing);
      expect(find.text('Communities'), findsNothing);
      expect(
        find.byKey(const ValueKey('more-destination-clubs')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('more-destination-discover')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('more-sheet-scroll-view')),
        findsOneWidget,
      );

      final actions = <MoreDestination, String>{
        MoreDestination.friends: 'Friends, Your circle',
        MoreDestination.profile: 'Profile, You',
        MoreDestination.findCreators: 'Find creators, People to follow',
        MoreDestination.notifications: 'Alerts, Updates',
        MoreDestination.achievements: 'Awards, Progress',
        MoreDestination.creatorStudio: 'Creator, Studio, Premium required',
        MoreDestination.settings:
            'Settings, Privacy, account and application preferences',
      };

      expect(
        find.byKey(const ValueKey('more-destination-reels')),
        findsNothing,
      );

      for (final entry in actions.entries) {
        final target = find.byKey(
          ValueKey('more-destination-${entry.key.name}'),
        );
        expect(target, findsOneWidget, reason: entry.key.name);
        final size = tester.getSize(target);
        expect(size.width, greaterThanOrEqualTo(44), reason: entry.key.name);
        expect(size.height, greaterThanOrEqualTo(44), reason: entry.key.name);

        final data = tester.getSemantics(target).getSemanticsData();
        expect(data.label, entry.value, reason: entry.key.name);
        expect(
          data.hasAction(ui.SemanticsAction.tap),
          isTrue,
          reason: entry.key.name,
        );

        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(target.hitTestable(), findsOneWidget, reason: entry.key.name);
      }

      expect(tester.takeException(), isNull);
      expect(
        find.text('Privacy, account and application preferences'),
        findsOne,
      );
      semantics.dispose();
    },
  );

  // R-10: three of the six launcher tiles ellipsised their Polish label on a
  // Redmi Note 8 Pro (392.7dp) — "Znajdź twór…", "Osoby warte obs…" and
  // "Powiadomie…". The tile column is only ~110dp wide there, and the grid
  // cell was a fixed 62dp with room for exactly one line of each.
  group('R-10 — the launcher tiles never clip a label', () {
    setUpAll(_loadInter);

    /// The six product tiles, Polish title -> Polish subtitle. Polish is the
    /// locale that clipped; English is shorter in every one of these strings.
    const tiles = <String, String>{
      'Znajomi': 'Twój krąg',
      'Profil': 'Ty',
      'Znajdź twórców': 'Warto obserwować',
      'Powiadomienia': 'Aktualizacje',
      'Nagrody': 'Postępy',
      'Twórca': 'Studio',
    };

    Future<void> pumpSheet(
      WidgetTester tester, {
      required Size size,
      required double scale,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('pl'),
          theme: AppTheme.darkTheme,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SizedBox.expand(
                  child: MoreSheet(
                    capabilityService: _NoStaffCapabilities(),
                    currentUid: 'ordinary-user',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    void expectWholeLabels(WidgetTester tester, String where) {
      for (final tile in tiles.entries) {
        for (final label in [tile.key, tile.value]) {
          final text = find.text(label);
          expect(text, findsOneWidget, reason: '$label at $where');
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: text, matching: find.byType(RichText)),
          );
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: '"$label" is cut off at $where',
          );
        }
      }
      // A row too short for its own text overflows its column instead of
      // ellipsising, so the row-height fix is pinned by this as well.
      expect(tester.takeException(), isNull, reason: where);
    }

    // 320dp is the smallest phone the app still draws, 392.7dp the reporter's
    // Redmi, 834/1280dp the three-column branch. 1.3x is the top of the
    // compact branch — above it the sheet already switched to full-width
    // rows, which the 2x case above covers.
    const grid = <(Size, double)>[
      (Size(320, 640), 1.0),
      (Size(360, 800), 1.0),
      (Size(360, 800), 1.3),
      (Size(375, 812), 1.0),
      (Size(375, 812), 1.3),
      (Size(392.7, 844), 1.0),
      (Size(392.7, 844), 1.3),
      (Size(430, 932), 1.0),
      (Size(430, 932), 1.3),
      (Size(834, 1112), 1.0),
      (Size(834, 1112), 1.3),
      (Size(1280, 900), 1.0),
      (Size(1280, 900), 1.3),
    ];

    for (final (size, scale) in grid) {
      testWidgets('${size.width}dp at ${scale}x keeps every tile label whole', (
        tester,
      ) async {
        await pumpSheet(tester, size: size, scale: scale);

        // Settings is the only full-width row in the compact branch, so
        // exactly one chevron proves the tile grid is what is on screen
        // and not the enlarged-text fallback.
        expect(
          find.byIcon(Icons.chevron_right_rounded),
          findsOneWidget,
          reason: 'the tile grid should be the branch under test',
        );
        expectWholeLabels(tester, '${size.width}dp / ${scale}x');
      });
    }

    testWidgets(
      '320dp at 1.3x drops to full-width rows rather than a column too '
      'narrow to read',
      (tester) async {
        await pumpSheet(tester, size: const Size(320, 640), scale: 1.3);

        // Six product rows plus Settings: the compact grid cannot give an
        // enlarged title more than ~74dp here, so the sheet stops trying.
        expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(7));
        expectWholeLabels(tester, '320dp / 1.3x');
      },
    );
  });
}
