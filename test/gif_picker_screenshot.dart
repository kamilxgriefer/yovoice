// Developer-only VISUAL harness: renders the composer panel's GIF tab to real
// PNG files, at both narrow widths, in both themes, in every state that
// matters — plus the other end of the feature, a reported GIF in the
// Moderation Center, at a phone width and a desktop one.
//
// Why this exists. The project's rule is that a visual claim needs visual
// proof, and `flutter analyze` plus a green widget test prove code health, not
// that a screen renders correctly. This harness gets the evidence from the
// widget layer: real widgets, real fonts, exact viewport, real layout.
//
// It is NOT a test and deliberately does not end in `_test.dart`, so
// `flutter test` never picks it up. Run it explicitly:
//
//   flutter test test/gif_picker_screenshot.dart
//
// PNGs land in test/.screenshots/ (git-ignored). OPEN THEM. The point is to
// look at what the code actually draws, not to watch a script succeed.
//
// A NOTE ON WHAT THE IMAGES CANNOT SHOW. The grid renders GifAssets whose
// URLs point at `fake.invalid`, so every cell paints its error placeholder
// rather than an animation — a widget test has no network and a fixture must
// never cause a real fetch. What these captures DO prove is the layout: column
// count at each width, the tab strip, the search field, the attribution
// footer, the banners, the disabled state, and that nothing overflows at 200%
// text scale. The animation itself is a one-line Image.network and is verified
// by `test/gif_view_test.dart` plus a device run once a key exists.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/media/data/models/gif_asset.dart';
import 'package:yovoice/features/media/data/services/gif_catalog_service.dart';
import 'package:yovoice/features/media/data/services/gif_transport.dart';
import 'package:yovoice/features/moderation/data/services/moderation_service.dart';
import 'package:yovoice/features/moderation/presentation/screens/moderation_center_screen.dart';
import 'package:yovoice/shared/widgets/inputs/yo_composer_panel.dart';
import 'package:yovoice/shared/widgets/inputs/yo_gif_recents.dart';

import 'support/fake_gif_transport.dart';

String _resolveFontRoot() {
  final configuredRoot = Platform.environment['FLUTTER_ROOT'];
  if (configuredRoot != null) {
    final configured = '$configuredRoot/bin/cache/artifacts/material_fonts';
    if (File('$configured/Roboto-Regular.ttf').existsSync()) return configured;
  }

  var directory = File(Platform.resolvedExecutable).parent;
  while (directory.parent.path != directory.path) {
    final candidate = '${directory.path}/bin/cache/artifacts/material_fonts';
    if (File('$candidate/Roboto-Regular.ttf').existsSync()) return candidate;
    directory = directory.parent;
  }

  throw StateError('Could not locate Flutter material fonts.');
}

final String _fontRoot = _resolveFontRoot();
final _capture = GlobalKey();

Future<void> _loadRealFonts() async {
  // Without the app's REAL family every glyph renders as a filled box and
  // "look at it" proves nothing at all. AppTypography.fontFamily is `Inter`,
  // so loading Roboto alone is not enough — that mistake produced a first
  // round of captures that were entirely tofu.
  Future<ByteData> read(String path) async {
    final bytes = File(path).readAsBytesSync();
    final typed = Uint8List.fromList(bytes);
    return ByteData.view(
      typed.buffer,
      typed.offsetInBytes,
      typed.lengthInBytes,
    );
  }

  final inter = FontLoader('Inter')
    ..addFont(read('assets/fonts/InterVariable.ttf'))
    ..addFont(read('assets/fonts/InterVariable-Italic.ttf'));
  await inter.load();

  final roboto = FontLoader('Roboto')
    ..addFont(read('$_fontRoot/Roboto-Regular.ttf'))
    ..addFont(read('$_fontRoot/Roboto-Medium.ttf'))
    ..addFont(read('$_fontRoot/Roboto-Bold.ttf'));
  await roboto.load();

  final icons = FontLoader('MaterialIcons')
    ..addFont(read('$_fontRoot/MaterialIcons-Regular.otf'));
  await icons.load();
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
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

/// The composer above, the panel below — exactly the arrangement all three
/// real composers use.
class _PanelHarness extends StatefulWidget {
  const _PanelHarness({
    required this.tab,
    this.service,
    this.gifUnavailableReason,
    this.recents = const <GifAsset>[],
    this.height,
  });

  final YoComposerPanelTab tab;
  final GifCatalogService? service;
  final GifUnavailableReason? gifUnavailableReason;
  final List<GifAsset> recents;
  final double? height;

  @override
  State<_PanelHarness> createState() => _PanelHarnessState();
}

class _PanelHarnessState extends State<_PanelHarness> {
  final TextEditingController controller = TextEditingController();
  final FocusNode focusNode = FocusNode();
  late YoComposerPanelTab tab = widget.tab;

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context);
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: palette.colorScheme.surface,
              alignment: Alignment.center,
              child: Text(
                'conversation',
                style: TextStyle(
                  color: palette.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            color: palette.colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Message',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                YoEmojiComposerButton(open: true, onPressed: () {}),
                IconButton.filled(
                  onPressed: () {},
                  icon: const Icon(Icons.send_rounded, size: 18),
                ),
              ],
            ),
          ),
          YoComposerPanel(
            tab: tab,
            height: widget.height,
            compact: widget.height != null,
            onTabChanged: (next) => setState(() => tab = next),
            emojiRecentsStore: YoEmojiRecentsStore.inMemory(),
            onEmojiSelected: (emoji) => yoInsertEmojiAtCaret(controller, emoji),
            onBackspace: () => yoDeleteBackAtCaret(controller),
            gifService: widget.service,
            gifRecentsStore: YoGifRecentsStore.inMemory(
              initial: widget.recents,
            ),
            gifUnavailableReason: widget.gifUnavailableReason,
            onGifSelected: widget.service == null ? null : (_) {},
          ),
        ],
      ),
    );
  }
}

Widget _app(
  Widget home, {
  required ThemeData theme,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: theme,
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: RepaintBoundary(key: _capture, child: home),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(_loadRealFonts);

  final themes = <String, ThemeData>{
    'dark': AppTheme.darkTheme,
    'pearl': AppTheme.lightTheme,
  };

  for (final width in const [320.0, 390.0]) {
    for (final entry in themes.entries) {
      final label = '${width.toInt()}-${entry.key}';

      testWidgets('GIF tab populated at $label', (tester) async {
        tester.view.physicalSize = Size(width, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.binding.setSurfaceSize(Size(width, 780));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final service = GifCatalogService(
          transport: FakeGifTransport(),
          debounce: Duration.zero,
        );
        addTearDown(service.dispose);
        await tester.pumpWidget(
          _app(
            _PanelHarness(
              tab: YoComposerPanelTab.gif,
              service: service,
              recents: FakeGifTransport.defaultAssets.take(4).toList(),
            ),
            theme: entry.value,
          ),
        );
        await _settle(tester);
        await _shoot(tester, 'gif-picker-$label');
      });

      testWidgets('GIF tab disabled at $label', (tester) async {
        tester.view.physicalSize = Size(width, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.binding.setSurfaceSize(Size(width, 780));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _app(
            const _PanelHarness(
              tab: YoComposerPanelTab.gif,
              gifUnavailableReason: GifUnavailableReason.surfaceUnsupported,
            ),
            theme: entry.value,
          ),
        );
        await _settle(tester);
        await _shoot(tester, 'gif-picker-disabled-$label');
      });

      testWidgets('emoji tab at $label, for the swap comparison', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.binding.setSurfaceSize(Size(width, 780));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final service = GifCatalogService(
          transport: FakeGifTransport(),
          debounce: Duration.zero,
        );
        addTearDown(service.dispose);
        await tester.pumpWidget(
          _app(
            _PanelHarness(tab: YoComposerPanelTab.emoji, service: service),
            theme: entry.value,
          ),
        );
        await _settle(tester);
        await _shoot(tester, 'gif-picker-emoji-tab-$label');
      });
    }
  }

  testWidgets('GIF tab at 320 dark, 200% text scale', (tester) async {
    // The state most likely to overflow, and the one a screenshot catches
    // that an assertion does not describe.
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.binding.setSurfaceSize(const Size(320, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = GifCatalogService(
      transport: FakeGifTransport(),
      debounce: Duration.zero,
    );
    addTearDown(service.dispose);
    await tester.pumpWidget(
      _app(
        _PanelHarness(tab: YoComposerPanelTab.gif, service: service),
        theme: AppTheme.darkTheme,
      ),
    );
    await _settle(tester);
    await _shoot(tester, 'gif-picker-320-dark-x2');
  });

  testWidgets('GIF tab in the room sheet cap (260px) at 390 dark', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = GifCatalogService(
      transport: FakeGifTransport(),
      debounce: Duration.zero,
    );
    addTearDown(service.dispose);
    await tester.pumpWidget(
      _app(
        _PanelHarness(
          tab: YoComposerPanelTab.gif,
          service: service,
          height: 260,
        ),
        theme: AppTheme.darkTheme,
      ),
    );
    await _settle(tester);
    await _shoot(tester, 'gif-picker-room-sheet-390-dark');
  });

  testWidgets('GIF tab rate-limited and degraded banners at 390 dark', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final transport = FakeGifTransport()..degraded = true;
    final service = GifCatalogService(
      transport: transport,
      debounce: Duration.zero,
    );
    addTearDown(service.dispose);
    await tester.pumpWidget(
      _app(
        _PanelHarness(tab: YoComposerPanelTab.gif, service: service),
        theme: AppTheme.darkTheme,
      ),
    );
    await _settle(tester);
    // Now provoke the "slow down" line on top of the degraded one — both
    // banners at once is the densest the header ever gets.
    transport.searchFailure = const GifTransportException(
      GifFailure.rateLimited,
      retryAfterSeconds: 5,
    );
    service.query('kot');
    await _settle(tester);
    await _shoot(tester, 'gif-picker-banners-390-dark');
  });

  testWidgets('GIF empty and error states at 390 dark', (tester) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = GifCatalogService(
      transport: FakeGifTransport(
        searchFailure: const GifTransportException(GifFailure.transient),
      ),
      debounce: Duration.zero,
    );
    addTearDown(service.dispose);
    await tester.pumpWidget(
      _app(
        _PanelHarness(tab: YoComposerPanelTab.gif, service: service),
        theme: AppTheme.darkTheme,
      ),
    );
    await _settle(tester);
    await _shoot(tester, 'gif-picker-error-390-dark');
  });

  // ------------------------------------------------------------------
  // The OTHER end of the feature: what a moderator sees when somebody
  // reports one of these. `reportGifAsset` files into the queue that already
  // exists, and the detail panel has to show the picture (staff cannot read
  // `gifAssets`), say honestly that no account is at fault, and offer the
  // block. Captured at both layouts because the panel is a narrow
  // single-column flow on a phone and a master-detail split on desktop.

  Future<FakeFirebaseFirestore> seedGifReport() async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('mod-uid').set(<String, dynamic>{
      'uid': 'mod-uid',
      'displayName': 'mod-uid',
      'role': 'moderator',
    });
    await db.collection('reports').doc('gif-shot').set(<String, dynamic>{
      'schemaVersion': 2,
      'reporterId': 'reporter-uid',
      'targetType': 'gifAsset',
      'targetId': 'giphy:abc123',
      'reportedUserId': '',
      'gifProvider': 'giphy',
      'gifId': 'abc123',
      'targetTextSnapshot':
          'giphy:abc123 — Dancing cat with a very long '
          'provider title that has to wrap somewhere sensible',
      // fake.invalid, never a real CDN: a capture must not make a network
      // request. The placeholder it paints is itself the dead-URL state.
      'targetMediaUrl': 'https://fake.invalid/media/abc123/200h.gif',
      'reason': 'sexual',
      'note': 'Not safe for a G rating.',
      'createdAt': Timestamp.now(),
      'status': 'open',
    });
    return db;
  }

  Widget moderationCenter(FakeFirebaseFirestore db) => ModerationCenterScreen(
    moderationService: ModerationService(
      firestore: db,
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
          uid: 'mod-uid',
          email: 'mod-uid@yovoice.app',
          displayName: 'Tester',
          customClaim: const {'role': 'moderator'},
        ),
      ),
    ),
  );

  testWidgets('a reported GIF in the Moderation Center at 390 dark', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final db = await seedGifReport();
    await tester.pumpWidget(
      _app(moderationCenter(db), theme: AppTheme.darkTheme),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('GIF').first);
    await tester.pumpAndSettle();
    await _shoot(tester, 'gif-moderation-detail-390-dark');
  });

  testWidgets('a reported GIF in the Moderation Center at 1440 dark', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final db = await seedGifReport();
    await tester.pumpWidget(
      _app(moderationCenter(db), theme: AppTheme.darkTheme),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('GIF').first);
    await tester.pumpAndSettle();
    await _shoot(tester, 'gif-moderation-detail-1440-dark');
  });
}
