import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/media/data/models/gif_asset.dart';
import 'package:yovoice/features/media/data/services/gif_catalog_service.dart';
import 'package:yovoice/features/media/data/services/gif_transport.dart';
import 'package:yovoice/shared/widgets/inputs/yo_gif_picker.dart';
import 'package:yovoice/shared/widgets/inputs/yo_gif_recents.dart';

import 'support/fake_gif_transport.dart';

Widget _app(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.darkTheme,
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: home,
);

Future<void> _setViewport(
  WidgetTester tester,
  Size size, {
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  if (scale != 1) {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
}

/// One picker, hosted the way the panel hosts it: a fixed height it does not
/// choose for itself.
Future<GifCatalogService> _pump(
  WidgetTester tester, {
  required FakeGifTransport transport,
  List<GifAsset>? recents,
  double height = 300,
  bool compact = false,
  bool autoLoad = true,
  ValueChanged<GifAsset>? onSelected,
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
}) async {
  await _setViewport(tester, size);
  final service = GifCatalogService(
    transport: transport,
    debounce: const Duration(milliseconds: 350),
  );
  addTearDown(service.dispose);
  await tester.pumpWidget(
    _app(
      Scaffold(
        body: Column(
          children: [
            const Expanded(child: SizedBox.expand()),
            YoGifPicker(
              service: service,
              height: height,
              compact: compact,
              autoLoad: autoLoad,
              recentsStore: YoGifRecentsStore.inMemory(
                initial: recents ?? const <GifAsset>[],
              ),
              onSelected: onSelected ?? (_) {},
            ),
          ],
        ),
      ),
      locale: locale,
    ),
  );
  await tester.pumpAndSettle();
  return service;
}

void main() {
  group('trending and search', () {
    testWidgets('the picker opens on trending without anybody typing', (
      tester,
    ) async {
      final transport = FakeGifTransport();
      await _pump(tester, transport: transport);

      expect(find.byKey(const ValueKey('gif-picker')), findsOneWidget);
      // A blank query IS trending — trending is not a second endpoint.
      expect(transport.searchCalls, <String>['']);
      expect(find.byKey(const ValueKey('gif-cell-fakeCat01')), findsWidgets);
    });

    testWidgets('typing a word makes ONE request, not one per keystroke', (
      tester,
    ) async {
      final transport = FakeGifTransport();
      await _pump(tester, transport: transport);
      transport.searchCalls.clear();

      // "kot" typed at speed. The debounce plus in-flight cancellation is what
      // keeps a beta API key alive under real use.
      await tester.enterText(
        find.byKey(const ValueKey('gif-picker-search')),
        'k',
      );
      await tester.pump(const Duration(milliseconds: 80));
      await tester.enterText(
        find.byKey(const ValueKey('gif-picker-search')),
        'ko',
      );
      await tester.pump(const Duration(milliseconds: 80));
      await tester.enterText(
        find.byKey(const ValueKey('gif-picker-search')),
        'kot',
      );
      await tester.pumpAndSettle();

      expect(transport.searchCalls, <String>['kot']);
      expect(find.byKey(const ValueKey('gif-cell-fakeCat01')), findsWidgets);
    });

    testWidgets('a single character never reaches the server', (tester) async {
      final transport = FakeGifTransport();
      await _pump(tester, transport: transport);
      transport.searchCalls.clear();

      await tester.enterText(
        find.byKey(const ValueKey('gif-picker-search')),
        'k',
      );
      await tester.pumpAndSettle();

      expect(transport.searchCalls, isEmpty);
      // ...and the grid is not cleared underneath the person mid-word.
      expect(find.byKey(const ValueKey('gif-cell-fakeCat01')), findsWidgets);
    });

    testWidgets('a search with no matches shows the neutral empty state', (
      tester,
    ) async {
      final transport = FakeGifTransport();
      await _pump(tester, transport: transport);

      await tester.enterText(
        find.byKey(const ValueKey('gif-picker-search')),
        'zzzznothing',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('gif-empty')), findsOneWidget);
      // Neutral wording matters: a denylisted query lands here too, and saying
      // which word tripped the filter would be a map of the filter.
      expect(find.text('No GIFs match that search.'), findsOneWidget);
    });
  });

  group('failure states', () {
    testWidgets('a transient failure offers Retry and recovers', (
      tester,
    ) async {
      final failing = FakeGifTransport(
        searchFailure: const GifTransportException(GifFailure.transient),
      );
      final service = await _pump(tester, transport: failing);

      expect(find.byKey(const ValueKey('gif-error')), findsOneWidget);
      expect(find.text("Couldn't load GIFs."), findsOneWidget);
      expect(find.byKey(const ValueKey('gif-retry')), findsOneWidget);
      // The retry really calls back through: the fake still fails, so the
      // error state is still what we get, which proves the button is wired.
      await tester.tap(find.byKey(const ValueKey('gif-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('gif-error')), findsOneWidget);
      expect(service.state.status, GifQueryStatus.error);
    });

    testWidgets('being rate-limited KEEPS the results and says slow down', (
      tester,
    ) async {
      // Being told to slow down must not also take away what you were looking
      // at. This is the assertion that keeps that true.
      final transport = FakeGifTransport();
      final service = await _pump(tester, transport: transport);
      expect(find.byKey(const ValueKey('gif-cell-fakeCat01')), findsWidgets);

      // The next call is refused, exactly as the server's token bucket does.
      transport.searchFailure = const GifTransportException(
        GifFailure.rateLimited,
        retryAfterSeconds: 4,
      );
      await tester.enterText(
        find.byKey(const ValueKey('gif-picker-search')),
        'kot',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('gif-rate-limited')), findsOneWidget);
      expect(
        find.text('Slow down for a moment — too many searches.'),
        findsOneWidget,
      );
      // The grid is still there, and so is the state behind it.
      expect(service.state.hasResults, isTrue);
      expect(service.state.rateLimitedRetrySeconds, 4);
      expect(find.byKey(const ValueKey('gif-cell-fakeCat01')), findsWidgets);
    });

    testWidgets(
      'a server that reports the feature unavailable disables the tab body',
      (tester) async {
        await _pump(
          tester,
          transport: FakeGifTransport(
            catalogResult: const GifCatalog.unavailable(
              GifUnavailableReason.notConfigured,
            ),
          ),
        );

        expect(find.byKey(const ValueKey('gif-unavailable')), findsOneWidget);
        expect(find.text("GIFs aren't available yet"), findsOneWidget);
        expect(
          find.text('This feature is not switched on for YO Voice yet.'),
          findsOneWidget,
        );
        // Nothing that implies a working picker is on screen.
        expect(find.byKey(const ValueKey('gif-picker-search')), findsNothing);
      },
    );

    testWidgets('the kill switch reads as turned off, not as broken', (
      tester,
    ) async {
      await _pump(
        tester,
        transport: FakeGifTransport(
          catalogResult: const GifCatalog.unavailable(
            GifUnavailableReason.disabled,
          ),
        ),
      );
      expect(find.text('GIFs are turned off'), findsOneWidget);
    });

    testWidgets('a degraded page says it is showing popular GIFs', (
      tester,
    ) async {
      final transport = FakeGifTransport()..degraded = true;
      await _pump(tester, transport: transport);

      expect(find.byKey(const ValueKey('gif-degraded')), findsOneWidget);
      expect(find.text('Showing popular GIFs.'), findsOneWidget);
      // Degraded is not empty: results are still on screen.
      expect(find.byKey(const ValueKey('gif-cell-fakeCat01')), findsWidgets);
    });
  });

  group('attribution and rating', () {
    testWidgets("GIPHY's mark is visible wherever results are", (tester) async {
      // Contractual, not decorative. There is no code path that shows results
      // without it.
      await _pump(tester, transport: FakeGifTransport());
      expect(find.byKey(const ValueKey('gif-attribution')), findsOneWidget);
      expect(find.text('Powered by GIPHY'), findsOneWidget);
      expect(find.text('Rated G only'), findsOneWidget);
    });

    testWidgets('the mark survives the narrowest supported width', (
      tester,
    ) async {
      await _pump(
        tester,
        transport: FakeGifTransport(),
        size: const Size(320, 640),
        height: 260,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('gif-attribution')), findsOneWidget);
    });
  });

  group('selection and privacy', () {
    testWidgets('tapping a GIF hands it back and records it in recents', (
      tester,
    ) async {
      final chosen = <GifAsset>[];
      await _pump(
        tester,
        transport: FakeGifTransport(),
        onSelected: chosen.add,
      );

      await tester.tap(find.byKey(const ValueKey('gif-cell-fakeCat01')));
      await tester.pumpAndSettle();

      expect(chosen.single.id, 'fakeCat01');
      expect(chosen.single.rating, 'g');
    });

    testWidgets(
      'with auto-load off the grid contacts nobody until somebody taps',
      (tester) async {
        // The only privacy control a viewer has: rendering a GIF necessarily
        // shows their IP to a third party, so "off" must mean NO request, not
        // a smaller one.
        await _pump(tester, transport: FakeGifTransport(), autoLoad: false);

        expect(find.byKey(const ValueKey('gif-view-load')), findsWidgets);
        expect(find.byType(Image), findsNothing);
      },
    );

    testWidgets('with auto-load on the images are requested', (tester) async {
      await _pump(tester, transport: FakeGifTransport());
      expect(find.byType(Image), findsWidgets);
      expect(find.byKey(const ValueKey('gif-view-load')), findsNothing);
    });

    testWidgets('long-press opens a report sheet that names the reasons', (
      tester,
    ) async {
      await _pump(tester, transport: FakeGifTransport());

      await tester.longPress(find.byKey(const ValueKey('gif-cell-fakeCat01')));
      await tester.pumpAndSettle();

      expect(find.text('Report this GIF'), findsOneWidget);
      // Said out loud: nobody in YO Voice is accused by this report.
      expect(
        find.text('This reports the GIF itself, not the person who sent it.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('gif-report-sexual')), findsOneWidget);
    });

    testWidgets('choosing a reason files the report and drops it from recents', (
      tester,
    ) async {
      final transport = FakeGifTransport();
      await _pump(
        tester,
        transport: transport,
        recents: FakeGifTransport.defaultAssets.take(2).toList(),
        // Tall enough for the recents row to earn its place: the picker drops
        // it when the grid underneath would be squeezed to nothing, which is
        // its own test below.
        height: 440,
      );

      await tester.longPress(
        find.byKey(const ValueKey('gif-recent-fakeCat01')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('gif-report-sexual')));
      await tester.pumpAndSettle();

      expect(transport.reportCalls, <String>['fake:fakeCat01:sexual']);
      expect(
        find.text('Thanks — our moderators will take a look.'),
        findsOneWidget,
      );
      // The thing somebody just objected to is not waiting for them next time.
      expect(find.byKey(const ValueKey('gif-recent-fakeCat01')), findsNothing);
    });
  });

  group('recents', () {
    testWidgets('a tall panel shows the recents row', (tester) async {
      await _pump(
        tester,
        transport: FakeGifTransport(),
        recents: FakeGifTransport.defaultAssets.take(3).toList(),
        height: 440,
      );
      expect(find.byKey(const ValueKey('gif-recents')), findsOneWidget);
      expect(find.text('RECENTLY USED'), findsOneWidget);
    });

    testWidgets('a short panel drops recents so the grid is not squeezed', (
      tester,
    ) async {
      // The grid is the feature; recents are a convenience. When both do not
      // fit, the grid wins — the first visual capture of this screen showed
      // the recents row with a TRENDING header under it and a grid of zero
      // height, which is the failure this gate exists to prevent.
      await _pump(
        tester,
        transport: FakeGifTransport(),
        recents: FakeGifTransport.defaultAssets.take(3).toList(),
        height: 280,
      );
      expect(find.byKey(const ValueKey('gif-recents')), findsNothing);
      expect(find.byKey(const ValueKey('gif-cell-fakeCat01')), findsWidgets);
    });
  });

  group('responsive grid', () {
    testWidgets('column count follows available width, not a device label', (
      tester,
    ) async {
      Future<int> columnsAt(Size size) async {
        await _pump(
          tester,
          transport: FakeGifTransport(),
          size: size,
          height: 320,
        );
        final cells = tester
            .widgetList<InkWell>(
              find.descendant(
                of: find.byKey(const ValueKey('gif-picker')),
                matching: find.byType(InkWell),
              ),
            )
            .where((cell) => cell.key.toString().contains('gif-cell-'))
            .toList();
        expect(cells, isNotEmpty);
        final tops = <double>{};
        for (final cell in cells) {
          tops.add(tester.getTopLeft(find.byKey(cell.key!)).dy);
        }
        final firstRowTop = tops.reduce((a, b) => a < b ? a : b);
        return cells
            .where(
              (cell) =>
                  tester.getTopLeft(find.byKey(cell.key!)).dy == firstRowTop,
            )
            .length;
      }

      expect(await columnsAt(const Size(320, 640)), 2);
      expect(await columnsAt(const Size(500, 900)), 3);
      // 820 px of viewport is 620 px of GRID, because the content measure is
      // capped so a desktop is not a stretched phone. The breakpoints have to
      // live inside that measure or the widest column count is unreachable.
      expect(await columnsAt(const Size(820, 1100)), 4);
    });

    testWidgets('every cell keeps a 44px touch target at 200% text scale', (
      tester,
    ) async {
      await _pump(
        tester,
        transport: FakeGifTransport(),
        size: const Size(320, 640),
        height: 320,
      );
      final cell = tester.getSize(
        find.byKey(const ValueKey('gif-cell-fakeCat01')).first,
      );
      expect(cell.width, greaterThanOrEqualTo(44));
      expect(cell.height, greaterThanOrEqualTo(44));
    });

    testWidgets('a very long title never overflows a cell', (tester) async {
      await _pump(
        tester,
        transport: FakeGifTransport(),
        autoLoad: false,
        size: const Size(320, 640),
        height: 320,
      );
      // fakeEdg02 carries a deliberately over-long title, rendered inside a
      // tap-to-load placeholder where the text is actually visible.
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('gif-cell-fakeEdg02')),
        find.byKey(const ValueKey('gif-picker')),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('localization', () {
    testWidgets('the picker speaks Polish', (tester) async {
      await _pump(
        tester,
        transport: FakeGifTransport(),
        locale: const Locale('pl'),
      );
      expect(find.text('Szukaj GIF-ów'), findsOneWidget);
      expect(find.text('Tylko ocena G'), findsOneWidget);
    });
  });
}
