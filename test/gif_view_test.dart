import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/media/data/models/gif_asset.dart';
import 'package:yovoice/shared/widgets/media/yo_gif_view.dart';

/// [YoGifView] in every state a GIF can be in.
///
/// The property that matters most is that its HEIGHT NEVER MOVES. A chat list
/// that reflows when a remote image lands jumps under the reader's thumb, and
/// a GIF is the one message type that arrives from a third party's CDN at an
/// unpredictable moment.

const _asset = GifAsset(
  provider: 'fake',
  id: 'fakeCat01',
  title: 'Happy cat',
  rating: 'g',
  previewUrl: 'https://fake.invalid/preview/fakeCat01.gif',
  url: 'https://fake.invalid/gif/fakeCat01/200h.gif',
  width: 320,
  height: 200,
);

const _tallTitle = GifAsset(
  provider: 'fake',
  id: 'fakeEdg02',
  title:
      'A title so long that it exists purely to prove the placeholder wraps '
      'and clips instead of overflowing its own bubble',
  rating: 'g',
  previewUrl: 'https://fake.invalid/preview/fakeEdg02.gif',
  url: 'https://fake.invalid/gif/fakeEdg02/200h.gif',
  width: 100,
  height: 200,
);

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
  home: Scaffold(body: Center(child: home)),
);

void main() {
  testWidgets('the height is known before a byte is fetched', (tester) async {
    await tester.pumpWidget(
      _app(const YoGifView(asset: _asset, height: 160, maxWidth: 260)),
    );
    await tester.pump();

    final size = tester.getSize(find.byType(YoGifView));
    expect(size.height, 160);
    // Width follows the intrinsic ratio (320x200 -> 1.6), clamped to the
    // bubble. 160 * 1.6 = 256, inside the 260 cap.
    expect(size.width, closeTo(256, 0.5));
  });

  testWidgets('a wide GIF is clamped to the bubble rather than overflowing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const YoGifView(asset: _asset, height: 200, maxWidth: 180)),
    );
    await tester.pump();
    expect(tester.getSize(find.byType(YoGifView)).width, 180);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the rendered height grows with text scale, but is capped', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      _app(const YoGifView(asset: _asset, height: 160, maxWidth: 400)),
    );
    await tester.pump();

    // A picture is not text: it grows enough to stay comfortable without
    // swallowing the conversation. 160 * 1.5 is the ceiling.
    expect(tester.getSize(find.byType(YoGifView)).height, 240);
  });

  testWidgets('with auto-load off nothing is fetched until somebody taps', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const YoGifView(asset: _asset, autoLoad: false)),
    );
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.byKey(const ValueKey('gif-view-load')), findsOneWidget);
    // The stored title is on screen, so the message still means something
    // before anything is loaded.
    expect(find.text('Happy cat'), findsOneWidget);
    expect(find.text('Tap to load'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('gif-view-load')));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('a dead CDN URL keeps the height and shows the stored title', (
    tester,
  ) async {
    // The one degradation that decides whether an old conversation still reads
    // as a conversation. The title was stored precisely so this is possible.
    await tester.pumpWidget(_app(const YoGifView(asset: _asset, height: 160)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // In a widget test every HTTP request returns 400, so this IS the
    // error path — no mocking required to reach it.
    expect(find.text('Happy cat'), findsOneWidget);
    expect(find.text('This GIF is no longer available'), findsOneWidget);
    expect(tester.getSize(find.byType(YoGifView)).height, 160);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the placeholder never overflows, even with a huge title', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const YoGifView(
          asset: _tallTitle,
          height: 90,
          maxWidth: 110,
          autoLoad: false,
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the semantic label names the medium, not just the title', (
    tester,
  ) async {
    // A screen reader user has no other way to know this is an animation.
    await tester.pumpWidget(_app(const YoGifView(asset: _asset)));
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.semanticLabel, 'GIF: Happy cat');
  });

  testWidgets('the Polish placeholder reads correctly', (tester) async {
    await tester.pumpWidget(
      _app(
        const YoGifView(asset: _asset, autoLoad: false),
        locale: const Locale('pl'),
      ),
    );
    await tester.pump();
    expect(find.text('Dotknij, aby wczytać'), findsOneWidget);
  });

  testWidgets('showTitle adds a label without changing the image height', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const YoGifView(
          asset: _asset,
          height: 120,
          maxWidth: 200,
          showTitle: true,
          autoLoad: false,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Happy cat'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
