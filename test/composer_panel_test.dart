import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/media/data/models/gif_asset.dart';
import 'package:yovoice/features/media/data/services/gif_catalog_service.dart';
import 'package:yovoice/shared/widgets/inputs/yo_composer_panel.dart';
import 'package:yovoice/shared/widgets/inputs/yo_gif_recents.dart';

import 'support/fake_gif_transport.dart';

/// Mirrors how all three real composers host the panel: it is the sibling
/// BELOW the composer, so the send button is laid out first and can never be
/// covered, and the screen holds ONE nullable enum rather than one bool per
/// picker.
class _ComposerHarness extends StatefulWidget {
  const _ComposerHarness({
    this.gifService,
    this.gifRecents,
    this.emojiRecents,
    this.gifUnavailableReason,
    this.onGifSelected,
    this.panelHeight,
    this.compact = false,
  });

  final GifCatalogService? gifService;
  final YoGifRecentsStore? gifRecents;
  final YoEmojiRecentsStore? emojiRecents;
  final GifUnavailableReason? gifUnavailableReason;
  final ValueChanged<GifAsset>? onGifSelected;
  final double? panelHeight;
  final bool compact;

  @override
  State<_ComposerHarness> createState() => _ComposerHarnessState();
}

class _ComposerHarnessState extends State<_ComposerHarness> {
  final TextEditingController controller = TextEditingController();
  final FocusNode focusNode = FocusNode();
  YoComposerPanelTab? panel;
  final List<GifAsset> chosen = <GifAsset>[];

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Expanded(child: SizedBox.expand()),
          Row(
            children: [
              Expanded(
                child: TextField(controller: controller, focusNode: focusNode),
              ),
              YoEmojiComposerButton(
                open: panel != null,
                onPressed: () => setState(
                  () => panel = panel == null ? YoComposerPanelTab.emoji : null,
                ),
              ),
              IconButton(
                key: const ValueKey('harness-send'),
                onPressed: () {},
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
          if (panel != null)
            YoComposerPanel(
              tab: panel!,
              height: widget.panelHeight,
              compact: widget.compact,
              onTabChanged: (tab) => setState(() => panel = tab),
              emojiRecentsStore: widget.emojiRecents,
              onEmojiSelected: (emoji) =>
                  yoInsertEmojiAtCaret(controller, emoji),
              onBackspace: () => yoDeleteBackAtCaret(controller),
              gifService: widget.gifService,
              gifRecentsStore: widget.gifRecents,
              gifUnavailableReason: widget.gifUnavailableReason,
              onGifSelected: widget.onGifSelected == null
                  ? null
                  : (asset) {
                      chosen.add(asset);
                      widget.onGifSelected!(asset);
                    },
            ),
        ],
      ),
    );
  }
}

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

const _emoji = ValueKey('emoji-picker');
const _gif = ValueKey('gif-picker');
const _gifDisabled = ValueKey('gif-picker-disabled');
const _toggle = ValueKey('emoji-picker-toggle');
const _emojiTab = ValueKey('composer-panel-tab-emoji');
const _gifTab = ValueKey('composer-panel-tab-gif');

void main() {
  group('the panel swap', () {
    testWidgets('reopening GIF restores the search paired with its results', (
      tester,
    ) async {
      await _setViewport(tester, const Size(390, 844));
      final transport = FakeGifTransport();
      final service = GifCatalogService(
        transport: transport,
        debounce: Duration.zero,
      );
      addTearDown(service.dispose);
      await tester.pumpWidget(
        _app(
          _ComposerHarness(
            gifService: service,
            gifRecents: YoGifRecentsStore.inMemory(),
            emojiRecents: YoEmojiRecentsStore.inMemory(),
            onGifSelected: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_gifTab));
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('gif-picker-search'));
      await tester.enterText(search, 'cat');
      await tester.pumpAndSettle();
      expect(service.state.query, 'cat');
      expect(service.state.items, isNotEmpty);
      transport.searchCalls.clear();

      await tester.tap(find.byKey(_emojiTab));
      await tester.pumpAndSettle();
      expect(find.byKey(_gif), findsNothing);
      await tester.tap(find.byKey(_gifTab));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, 'cat');
      expect(service.state.query, 'cat');
      expect(transport.searchCalls, isEmpty);
      expect(find.byKey(const ValueKey('gif-cell-fakeCat01')), findsWidgets);
      expect(find.byKey(const ValueKey('gif-cell-fakeDog01')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('one composer button opens and closes the whole panel', (
      tester,
    ) async {
      await _setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(_app(const _ComposerHarness()));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('composer-panel')), findsNothing);
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('composer-panel')), findsOneWidget);
      expect(find.byKey(_emoji), findsOneWidget);

      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('composer-panel')), findsNothing);
    });

    testWidgets(
      'the emoji and GIF bodies are NEVER both in the tree, on any tab',
      (tester) async {
        // The whole reason YoComposerPanel exists. Two stacked panels are not
        // "avoided by careful code" here — one nullable enum and one mounted
        // body make the state unrepresentable, and this is the assertion that
        // keeps it that way through every future edit.
        await _setViewport(tester, const Size(390, 844));
        final service = GifCatalogService(
          transport: FakeGifTransport(),
          debounce: Duration.zero,
        );
        addTearDown(service.dispose);
        await tester.pumpWidget(
          _app(
            _ComposerHarness(
              gifService: service,
              gifRecents: YoGifRecentsStore.inMemory(),
              onGifSelected: (_) {},
            ),
          ),
        );
        await tester.tap(find.byKey(_toggle));
        await tester.pumpAndSettle();

        expect(find.byKey(_emoji), findsOneWidget);
        expect(find.byKey(_gif), findsNothing);

        await tester.tap(find.byKey(_gifTab));
        await tester.pumpAndSettle();
        expect(find.byKey(_gif), findsOneWidget);
        expect(find.byKey(_emoji), findsNothing);

        await tester.tap(find.byKey(_emojiTab));
        await tester.pumpAndSettle();
        expect(find.byKey(_emoji), findsOneWidget);
        expect(find.byKey(_gif), findsNothing);
      },
    );

    testWidgets('the composer and its send button are never covered', (
      tester,
    ) async {
      await _setViewport(tester, const Size(320, 640));
      await tester.pumpWidget(_app(const _ComposerHarness()));
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();

      final send = tester.getRect(find.byKey(const ValueKey('harness-send')));
      final panel = tester.getRect(
        find.byKey(const ValueKey('composer-panel')),
      );
      expect(
        panel.top,
        greaterThanOrEqualTo(send.bottom - 0.5),
        reason: 'the panel overlapped the send button',
      );
    });
  });

  group('insertion into the composer', () {
    testWidgets('the emoji tab still inserts at the caret', (tester) async {
      await _setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        _app(_ComposerHarness(emojiRecents: YoEmojiRecentsStore.inMemory())),
      );
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('emoji-cell-😀')));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller!.text, '😀');
    });

    testWidgets('choosing a GIF hands the asset to the host composer', (
      tester,
    ) async {
      await _setViewport(tester, const Size(390, 844));
      final service = GifCatalogService(
        transport: FakeGifTransport(),
        debounce: Duration.zero,
      );
      addTearDown(service.dispose);
      final chosen = <GifAsset>[];
      await tester.pumpWidget(
        _app(
          _ComposerHarness(
            gifService: service,
            gifRecents: YoGifRecentsStore.inMemory(),
            onGifSelected: chosen.add,
          ),
        ),
      );
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_gifTab));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('gif-cell-fakeCat01')));
      await tester.pumpAndSettle();

      expect(chosen, hasLength(1));
      expect(chosen.single.id, 'fakeCat01');
      expect(chosen.single.title, 'Happy cat');
      // The pinned CDN URL travels with it — the composer never builds one.
      expect(chosen.single.url, contains('fakeCat01'));
    });
  });

  group('the disabled GIF tab', () {
    testWidgets(
      'a composer with no GIF path shows the tab, disabled and labelled',
      (tester) async {
        // CLAUDE.md's rule, and the one non-negotiable that survives having no
        // send path: visible and labelled, never hidden, never faked.
        await _setViewport(tester, const Size(390, 844));
        await tester.pumpWidget(
          _app(
            const _ComposerHarness(
              gifUnavailableReason: GifUnavailableReason.surfaceUnsupported,
            ),
          ),
        );
        await tester.tap(find.byKey(_toggle));
        await tester.pumpAndSettle();

        // The tab is present.
        expect(find.byKey(_gifTab), findsOneWidget);
        await tester.tap(find.byKey(_gifTab));
        await tester.pumpAndSettle();

        expect(find.byKey(_gifDisabled), findsOneWidget);
        expect(find.byKey(_gif), findsNothing);
        expect(find.text('GIFs are coming here soon'), findsOneWidget);
        expect(
          find.text(
            'This conversation cannot send GIFs yet. Emoji still work.',
          ),
          findsOneWidget,
        );
        // Emoji is still one tap away.
        await tester.tap(find.byKey(_emojiTab));
        await tester.pumpAndSettle();
        expect(find.byKey(_emoji), findsOneWidget);
      },
    );

    testWidgets('the not-configured label names the real reason, in Polish', (
      tester,
    ) async {
      await _setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        _app(
          const _ComposerHarness(
            gifUnavailableReason: GifUnavailableReason.notConfigured,
          ),
          locale: const Locale('pl'),
        ),
      );
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_gifTab));
      await tester.pumpAndSettle();

      expect(find.text('GIF-y nie są jeszcze dostępne'), findsOneWidget);
    });
  });

  group('responsive', () {
    for (final size in const [
      Size(320, 640),
      Size(390, 844),
      Size(768, 1024),
      Size(1440, 900),
    ]) {
      testWidgets('the panel fits at ${size.width}x${size.height}', (
        tester,
      ) async {
        await _setViewport(tester, size);
        final service = GifCatalogService(
          transport: FakeGifTransport(),
          debounce: Duration.zero,
        );
        addTearDown(service.dispose);
        await tester.pumpWidget(
          _app(
            _ComposerHarness(
              gifService: service,
              gifRecents: YoGifRecentsStore.inMemory(),
              onGifSelected: (_) {},
            ),
          ),
        );
        await tester.tap(find.byKey(_toggle));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_gifTab));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final panel = tester.getRect(
          find.byKey(const ValueKey('composer-panel')),
        );
        expect(panel.width, lessThanOrEqualTo(size.width + 0.5));
        // Desktop is not a stretched phone: the panel's SURFACE spans the
        // width, but its CONTENT keeps a readable measure and centres in the
        // extra space. The search field and the tab strip are both inside that
        // measure, so a 1440 px window does not produce a 1440 px-wide row of
        // controls nobody can reach.
        final search = tester.getRect(
          find.byKey(const ValueKey('gif-picker-search')),
        );
        expect(search.width, lessThanOrEqualTo(620.5));
        final strip = tester.getRect(find.byKey(_gifTab));
        expect(strip.width, lessThanOrEqualTo(620.5));
        if (size.width > 620) {
          expect(
            search.center.dx,
            closeTo(size.width / 2, 1),
            reason: 'the content did not centre on a wide viewport',
          );
        }
      });
    }

    testWidgets('at 200% text scale the panel still lays out and fits', (
      tester,
    ) async {
      await _setViewport(tester, const Size(320, 640), scale: 2);
      final service = GifCatalogService(
        transport: FakeGifTransport(),
        debounce: Duration.zero,
      );
      addTearDown(service.dispose);
      await tester.pumpWidget(
        _app(
          _ComposerHarness(
            gifService: service,
            gifRecents: YoGifRecentsStore.inMemory(),
            onGifSelected: (_) {},
          ),
        ),
      );
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_gifTab));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(_gif), findsOneWidget);
    });

    testWidgets(
      "the room sheet's short capped panel still shows both tabs and a grid",
      (tester) async {
        // 260 px is the exact cap room_chat_sheet.dart applies. The strip has
        // to fit, the grid has to fit under it, and neither may overflow.
        await _setViewport(tester, const Size(360, 720));
        final service = GifCatalogService(
          transport: FakeGifTransport(),
          debounce: Duration.zero,
        );
        addTearDown(service.dispose);
        await tester.pumpWidget(
          _app(
            _ComposerHarness(
              gifService: service,
              gifRecents: YoGifRecentsStore.inMemory(
                initial: FakeGifTransport.defaultAssets.take(3).toList(),
              ),
              onGifSelected: (_) {},
              panelHeight: 260,
              compact: true,
            ),
          ),
        );
        await tester.tap(find.byKey(_toggle));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_gifTab));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final panel = tester.getRect(
          find.byKey(const ValueKey('composer-panel')),
        );
        expect(panel.height, closeTo(260, 1));
        // Compact drops the recents row rather than compressing everything.
        expect(find.byKey(const ValueKey('gif-recents')), findsNothing);
        expect(find.byKey(_emojiTab), findsOneWidget);
        expect(find.byKey(_gifTab), findsOneWidget);
      },
    );
  });
}
