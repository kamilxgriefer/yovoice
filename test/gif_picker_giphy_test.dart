import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_giphy.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/media/data/models/gif_asset.dart';
import 'package:yovoice/features/media/data/services/gif_catalog_service.dart';
import 'package:yovoice/features/media/data/services/giphy_client.dart';
import 'package:yovoice/features/media/data/services/giphy_pingbacks.dart';
import 'package:yovoice/shared/widgets/inputs/yo_gif_picker.dart';
import 'package:yovoice/shared/widgets/inputs/yo_gif_recents.dart';
import 'package:yovoice/shared/widgets/media/yo_giphy_attribution.dart';

import 'support/fake_gif_transport.dart';
import 'support/fake_giphy_http.dart';

const _testKey = 'placeholder-key-for-tests';

const _giphyCatalog = GifCatalog(
  available: true,
  reason: null,
  provider: 'yovoice',
  attribution: GifAttribution(text: 'YO Voice Originals', required: false),
  categories: <String>['trending'],
  pageSize: 24,
  minimumQueryLength: 2,
  ratingLabel: 'g',
  resolvableProviders: <String>['giphy'],
);

class _MemoryRandomIdStore implements GiphyRandomIdStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
}

Widget _app(Widget home, {ThemeData? theme}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: theme ?? AppTheme.darkTheme,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: home,
);

class _Harness {
  _Harness(this.service, this.http, this.selected, this.resolveCalls);
  final GifCatalogService service;
  final FakeGiphyHttp? http;
  final List<GifAsset> selected;
  final List<Map<String, Object?>> resolveCalls;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required bool withKey,
  GifCatalog catalog = _giphyCatalog,
  bool autoLoad = false,
  Size size = const Size(390, 844),
  double textScale = 1,
  ThemeData? theme,
  List<GifAsset> recents = const <GifAsset>[],
  Future<Object?> Function(Map<String, Object?> data)? resolve,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (textScale != 1) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  final http = withKey ? FakeGiphyHttp() : null;
  final client = http == null
      ? null
      : GiphyClient(apiKey: _testKey, httpClient: http.client);
  final resolveCalls = <Map<String, Object?>>[];
  final service = GifCatalogService(
    // Two Originals, so the GIPHY section is inside the first viewport of a
    // lazily built grid rather than below the fold.
    transport: FakeGifTransport(
      catalogResult: catalog,
      assets: FakeGifTransport.defaultAssets.take(2).toList(),
    ),
    debounce: const Duration(milliseconds: 10),
    giphy: client,
    useBuildGiphyKey: false,
    giphyPingbacks: client == null
        ? null
        : GiphyPingbacks(client: client, store: _MemoryRandomIdStore()),
    resolveGif: (data) async {
      resolveCalls.add(data);
      if (resolve != null) return resolve(data);
      return {
        'asset': {
          'provider': data['provider'],
          'id': data['id'],
          'title': 'Happy dance',
          'rating': 'g',
          'url': 'https://media.giphy.com/media/${data['id']}/200h.gif',
          'width': 300,
          'height': 200,
        },
      };
    },
  );
  addTearDown(service.dispose);
  final selected = <GifAsset>[];
  await tester.pumpWidget(
    _app(
      Scaffold(
        body: Column(
          children: [
            const Expanded(child: SizedBox.expand()),
            YoGifPicker(
              service: service,
              height: 420,
              autoLoad: autoLoad,
              recentsStore: YoGifRecentsStore.inMemory(initial: recents),
              onSelected: selected.add,
            ),
          ],
        ),
      ),
      theme: theme,
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(service, http, selected, resolveCalls);
}

const _giphyRecent = GifAsset(
  provider: 'giphy',
  id: 'recentGif1',
  title: 'Old favourite',
  rating: 'g',
  previewUrl: 'https://media.giphy.com/media/recentGif1/200h.gif',
  url: 'https://media.giphy.com/media/recentGif1/200h.gif',
  width: 300,
  height: 200,
);

void main() {
  group('YoGifPicker without a GIPHY key', () {
    testWidgets('is exactly the Originals-only picker', (tester) async {
      final harness = await _pump(tester, withKey: false, autoLoad: true);
      expect(harness.service.giphyActive, isFalse);
      expect(harness.service.state.giphyStatus, GiphySectionStatus.off);
      expect(find.byKey(const ValueKey('giphy-section')), findsNothing);
      expect(find.byKey(const ValueKey('gif-originals-section')), findsNothing);
      expect(find.byType(YoGiphyAttribution), findsNothing);
      expect(find.byKey(const ValueKey('gif-cell-fakeCat01')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('gif-cell-fakeCat01')));
      await tester.pump();
      expect(harness.selected.single.id, 'fakeCat01');
      expect(harness.resolveCalls, isEmpty);
    });

    testWidgets('never offers a GIPHY recent it could not send', (
      tester,
    ) async {
      await _pump(tester, withKey: false, recents: const [_giphyRecent]);
      expect(find.byKey(const ValueKey('gif-recent-recentGif1')), findsNothing);
      expect(find.byType(YoGiphyAttribution), findsNothing);
    });
  });

  group('YoGifPicker with a GIPHY key', () {
    testWidgets('stays Originals-only until the server can resolve GIPHY', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        withKey: true,
        autoLoad: true,
        catalog: FakeGifTransport.availableCatalog,
      );
      expect(harness.service.giphyActive, isFalse);
      expect(harness.http!.requests, isEmpty);
      expect(find.byKey(const ValueKey('giphy-section')), findsNothing);
    });

    testWidgets('shows GIPHY beside Originals under the official mark', (
      tester,
    ) async {
      final harness = await _pump(tester, withKey: true, autoLoad: true);
      expect(harness.service.giphyActive, isTrue);
      expect(harness.http!.searches.single.path, '/v1/gifs/trending');
      expect(
        find.byKey(const ValueKey('gif-originals-section')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('giphy-section')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('gif-giphy-giphyOne01')),
        findsOneWidget,
      );
      // Once heading the section, once in the footer.
      expect(find.byType(YoGiphyAttribution), findsNWidgets(2));
      expect(find.bySemanticsLabel('Powered by GIPHY'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a typed search queries Originals and GIPHY together', (
      tester,
    ) async {
      final harness = await _pump(tester, withKey: true);
      await tester.enterText(
        find.byKey(const ValueKey('gif-picker-search')),
        'cat',
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      final search = harness.http!.searches.last;
      expect(search.path, '/v1/gifs/search');
      expect(search.queryParameters['q'], 'cat');
      expect(search.queryParameters['rating'], 'g');
      expect(find.byKey(const ValueKey('gif-cell-fakeCat01')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('gif-giphy-giphyOne01')),
        findsOneWidget,
      );
    });

    testWidgets('with auto-load off, opening the tab does not contact GIPHY', (
      tester,
    ) async {
      final harness = await _pump(tester, withKey: true);
      expect(harness.service.giphyActive, isTrue);
      expect(harness.http!.requests, isEmpty);
      expect(find.byKey(const ValueKey('giphy-section')), findsNothing);
    });

    testWidgets('choosing a GIPHY result resolves {provider, id} first', (
      tester,
    ) async {
      final harness = await _pump(tester, withKey: true, autoLoad: true);
      await tester.tap(find.byKey(const ValueKey('gif-giphy-giphyOne01')));
      await tester.pumpAndSettle();
      expect(harness.resolveCalls, [
        {'provider': 'giphy', 'id': 'giphyOne01'},
      ]);
      expect(harness.selected.single.id, 'giphyOne01');
      expect(harness.selected.single.provider, 'giphy');
    });

    testWidgets('a refused GIPHY result is never handed to the composer', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        withKey: true,
        autoLoad: true,
        resolve: (_) async => throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'refused',
          details: const {'code': 'blocked'},
        ),
      );
      await tester.tap(find.byKey(const ValueKey('gif-giphy-giphyOne01')));
      await tester.pumpAndSettle();
      expect(harness.selected, isEmpty);
      expect(
        find.byKey(const ValueKey('giphy-prepare-failed')),
        findsOneWidget,
      );
      expect(find.text('This GIF is no longer available'), findsOneWidget);
    });

    testWidgets('a GIPHY outage keeps Originals and says so', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      final harness = await _pump(tester, withKey: true);
      harness.http!.status = 500;
      await tester.enterText(
        find.byKey(const ValueKey('gif-picker-search')),
        'cat',
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      expect(harness.service.state.giphyStatus, GiphySectionStatus.error);
      expect(find.byKey(const ValueKey('giphy-unavailable')), findsOneWidget);
      expect(find.byKey(const ValueKey('gif-cell-fakCat01')), findsNothing);
      expect(find.byKey(const ValueKey('gif-cell-fakeCat01')), findsOneWidget);
    });

    for (final (label, theme) in [
      ('dark', AppTheme.darkTheme),
      ('light', AppTheme.lightTheme),
    ]) {
      testWidgets('the mark survives 320 px at 200% text ($label)', (
        tester,
      ) async {
        await _pump(
          tester,
          withKey: true,
          autoLoad: true,
          size: const Size(320, 640),
          textScale: 2,
          theme: theme,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(YoGiphyAttribution), findsWidgets);
        final expected = YoGiphyAttribution.assetFor(theme.brightness);
        final image = tester.widget<Image>(
          find
              .descendant(
                of: find.byType(YoGiphyAttribution).first,
                matching: find.byType(Image),
              )
              .first,
        );
        expect((image.image as AssetImage).assetName, expected);
      });
    }
  });

  group('GIPHY pingbacks in the picker', () {
    testWidgets('are not sent while "Load GIFs automatically" is off', (
      tester,
    ) async {
      final harness = await _pump(tester, withKey: true);
      await tester.enterText(
        find.byKey(const ValueKey('gif-picker-search')),
        'cat',
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      // Visible, tap-to-load cells: the grid built them, onload was offered.
      expect(
        find.byKey(const ValueKey('gif-giphy-giphyOne01')),
        findsOneWidget,
      );
      final asset = harness.service.state.giphyItems.first;
      harness.service.giphyShown(asset);
      final outcome = await harness.service.prepareForSend(asset);
      await tester.pumpAndSettle();
      expect(outcome, GifPrepareOutcome.ready);
      expect(harness.resolveCalls, hasLength(1));
      expect(harness.http!.pings, isEmpty);
      expect(harness.http!.randomIdCalls, 0);
    });

    testWidgets('onload fires once per result and onclick on choice', (
      tester,
    ) async {
      final harness = await _pump(tester, withKey: true);
      harness.service.giphyAutoLoad = true;
      await tester.enterText(
        find.byKey(const ValueKey('gif-picker-search')),
        'cat',
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      final asset = harness.service.state.giphyItems.first;
      harness.service.giphyShown(asset);
      harness.service.giphyShown(asset);
      await tester.pumpAndSettle();
      final seen = harness.http!.pings.where(
        (url) =>
            url.queryParameters['action_type'] == 'SEEN' &&
            url.queryParameters['p'] == asset.id,
      );
      expect(seen, hasLength(1));
    });
  });

  test('GIPHY copy is catalogued in every translated locale', () {
    final locales = appTranslations.keys.toSet();
    expect(giphyTranslations.keys.toSet(), locales);
    expect(giphyTranslations, hasLength(41));
    expect(appTranslationKeys, containsAll(giphyTranslationKeys));
    for (final entry in giphyTranslations.entries) {
      expect(entry.value.keys.toSet(), giphyTranslationKeys.toSet());
      for (final key in giphyTranslationKeys) {
        final value = translatedPhrase(entry.key, key);
        expect(value, isNotNull, reason: '${entry.key}: $key');
        expect(value!.trim(), isNotEmpty);
        expect(value, isNot(key), reason: '${entry.key}: no English fallback');
        // Brand names are never translated.
        expect(
          value,
          contains(key == giphyOriginalsSectionKey ? 'YO Voice' : 'GIPHY'),
          reason: '${entry.key}: $key',
        );
      }
    }
  });
}
