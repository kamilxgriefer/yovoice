import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_layout.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_vibe_headline.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_vibe_link.dart';

void main() {
  group('ProfileVibeLink', () {
    test('classifies YouTube, Spotify, Apple Music and other music links', () {
      final fixtures = <String, String?>{
        'HTTPS://youtu.be/eVTXPUF4Oz4?si=abc': 'YouTube',
        'https://open.spotify.com/track/123?si=abc': 'Spotify',
        'https://music.apple.com/pl/album/title/1?i=2': 'Apple Music',
        'https://artist.bandcamp.com/track/song': 'Bandcamp',
        'https://music.example.com/song': null,
      };

      for (final MapEntry(key: value, value: provider) in fixtures.entries) {
        final links = ProfileVibeLink.fromText('Playing $value now');
        expect(links, hasLength(1), reason: value);
        expect(links.single.provider, provider, reason: value);
      }
    });

    test('preserves Unicode paths, query and balanced URL punctuation', () {
      const source =
          'Live (https://example.com/zażółć/song_(live)?q=głos#teraz).';
      final link = ProfileVibeLink.fromText(source).single;

      expect(
        link.uri,
        Uri.parse('https://example.com/zażółć/song_(live)?q=głos#teraz'),
      );
      expect(profileVibeDescription(source, [link]), 'Live.');
    });

    test('extracts every safe link in source order', () {
      const source =
          'YouTube https://youtu.be/one, Spotify '
          'https://open.spotify.com/track/two!';
      final links = ProfileVibeLink.fromText(source);

      expect(links.map((link) => link.provider), ['YouTube', 'Spotify']);
      expect(links.map((link) => link.uri.toString()), [
        'https://youtu.be/one',
        'https://open.spotify.com/track/two',
      ]);
      expect(profileVibeDescription(source, links), 'YouTube, Spotify!');
    });

    test(
      'rejects non-HTTPS, credentials, local hosts, IPs and custom ports',
      () {
        for (final unsafe in [
          'http://open.spotify.com/track/1',
          'www.youtube.com/watch?v=1',
          'javascript:alert(1)',
          'data:text/html,hello',
          'file:///tmp/song',
          'https://spotify.com@evil.test/song',
          'https://localhost/song',
          'https://music.local/song',
          'https://music.internal/song',
          'https://127.0.0.1/song',
          'https://127.1/song',
          'https://[::1]/song',
          'https://example.com:8443/song',
          'https://músic.example/song',
          'https://music\u200B.example/song',
        ]) {
          expect(
            ProfileVibeLink.fromText(unsafe),
            isEmpty,
            reason: '$unsafe must remain plain text',
          );
        }
      },
    );

    test('a lookalike domain never receives a trusted provider label', () {
      for (final lookalike in [
        'https://youtube.com.evil.test/watch?v=1',
        'https://music.amazon.evil.test/login',
      ]) {
        final link = ProfileVibeLink.fromText(lookalike).single;
        expect(link.provider, isNull, reason: lookalike);
        expect(link.actionLabel, 'External link', reason: lookalike);
      }
    });

    test('strips quoted-link punctuation without changing the destination', () {
      const source =
          "Listen to 'https://open.spotify.com/track/123'… then tell me";
      final link = ProfileVibeLink.fromText(source).single;

      expect(link.uri, Uri.parse('https://open.spotify.com/track/123'));
      expect(profileVibeDescription(source, [link]), 'Listen to… then tell me');
    });
  });

  group('ProfileVibeHeadline', () {
    testWidgets('renders a large semantic link row and launches exact URI', (
      tester,
    ) async {
      final opened = <Uri>[];
      await _pumpVibe(
        tester,
        vibe:
            'Linkin Park - In the End '
            'https://youtu.be/eVTXPUF4Oz4?si=abc',
        launcher: (uri) async {
          opened.add(uri);
          return true;
        },
      );

      expect(find.text('Linkin Park - In the End'), findsOneWidget);
      expect(find.textContaining('https://'), findsNothing);
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('youtu.be'), findsOneWidget);

      final semanticLink = find.bySemanticsLabel('Open in YouTube, youtu.be');
      expect(semanticLink, findsOneWidget);
      final semantics = tester.getSemantics(semanticLink).getSemanticsData();
      expect(semantics.hasAction(ui.SemanticsAction.tap), isTrue);
      expect(semantics.flagsCollection.isLink, isTrue);
      expect(
        semantics.linkUrl,
        Uri.parse('https://youtu.be/eVTXPUF4Oz4?si=abc'),
      );

      final target = find.byKey(
        const ValueKey('profile-vibe-link-https://youtu.be/eVTXPUF4Oz4?si=abc'),
      );
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focusedSurface = tester.widget<Material>(
        find.byKey(
          const ValueKey(
            'profile-vibe-link-surface-https://youtu.be/eVTXPUF4Oz4?si=abc',
          ),
        ),
      );
      // Refine-look §8.5: on the violet sticker the focus ring is a 2 px
      // white ring (the violet focus role would vanish on the sweep).
      expect(
        (focusedSurface.shape! as RoundedRectangleBorder).side,
        const BorderSide(color: Colors.white, width: 2),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(opened, [Uri.parse('https://youtu.be/eVTXPUF4Oz4?si=abc')]);
    });

    testWidgets('same-frame double tap and cooldown launch exactly once', (
      tester,
    ) async {
      final firstLaunch = Completer<bool>();
      var calls = 0;
      await _pumpVibe(
        tester,
        vibe: 'Now playing https://open.spotify.com/track/123',
        launcher: (_) {
          calls++;
          return calls == 1 ? firstLaunch.future : Future.value(true);
        },
      );
      final link = find.byKey(
        const ValueKey('profile-vibe-link-https://open.spotify.com/track/123'),
      );

      await tester.tap(link);
      await tester.tap(link);
      expect(calls, 1);

      firstLaunch.complete(true);
      await tester.pump();
      await tester.tap(link);
      expect(calls, 1, reason: 'successful handoff keeps a short cooldown');

      await tester.pump(const Duration(milliseconds: 651));
      await tester.tap(link);
      expect(calls, 2);
    });

    testWidgets(
      'failed and throwing launchers show inline feedback and retry',
      (tester) async {
        var calls = 0;
        await _pumpVibe(
          tester,
          vibe: 'Listen https://music.apple.com/pl/album/1',
          launcher: (_) async {
            calls++;
            if (calls == 1) return false;
            throw StateError('platform detail must stay private');
          },
        );
        final link = find.byKey(
          const ValueKey(
            'profile-vibe-link-https://music.apple.com/pl/album/1',
          ),
        );

        await tester.tap(link);
        await tester.pump();
        expect(find.text("Couldn't open this link."), findsOneWidget);
        final errorBox = tester.widget<Container>(
          find.byKey(const ValueKey('profile-vibe-error')),
        );
        final errorSurface = (errorBox.decoration! as BoxDecoration).color!;
        final errorText = tester
            .widget<Text>(find.text("Couldn't open this link."))
            .style!
            .color!;
        expect(
          _contrastRatio(errorText, errorSurface),
          greaterThanOrEqualTo(4.5),
        );

        await tester.tap(link);
        await tester.pump();
        expect(calls, 2);
        expect(find.text('platform detail must stay private'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('plain text has no link action', (tester) async {
      await _pumpVibe(tester, vibe: 'Late-night acoustic energy');

      expect(find.text('Late-night acoustic energy'), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-vibe-link')), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.link == true,
        ),
        findsNothing,
      );
    });

    testWidgets('Dark and Pearl paint the vibe sticker with readable ink', (
      tester,
    ) async {
      for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
        final scheme = theme.colorScheme;
        await _pumpVibe(
          tester,
          vibe: 'Now playing https://open.spotify.com/track/123',
          theme: theme,
        );

        // Refine-look §8.5: the sticker is the primary action gradient on
        // a slight diagonal over its primary base, radius `tile`, with no
        // border and no shadow.
        final surface = tester.widget<Material>(
          find.byKey(const ValueKey('profile-vibe-surface')),
        );
        expect(surface.color, scheme.primary);
        final shape = surface.shape! as RoundedRectangleBorder;
        expect(shape.borderRadius, AppRadius.tile);
        expect(shape.side, BorderSide.none);
        expect(surface.elevation, 0);
        final sweep =
            tester
                    .widget<Ink>(
                      find.byKey(const ValueKey('profile-vibe-sweep')),
                    )
                    .decoration!
                as BoxDecoration;
        expect(
          sweep.gradient,
          AppGradients.primaryAction(
            scheme,
            begin: const Alignment(-1, -.35),
            end: const Alignment(1, .35),
          ),
        );
        final stops = <Color>[scheme.primary, scheme.secondary];

        final accentIcon = tester.widget<Icon>(
          find.byKey(const ValueKey('profile-vibe-accent-icon')),
        );
        final label = tester.widget<Text>(
          find.byKey(const ValueKey('profile-vibe-label')),
        );
        final description = tester.widget<Text>(find.text('Now playing'));
        expect(accentIcon.color, Colors.white);
        expect(label.style!.color, Colors.white);
        expect(description.style!.color, Colors.white);
        for (final stop in stops) {
          expect(
            _contrastRatio(Colors.white, stop),
            greaterThanOrEqualTo(4.5),
            reason: 'white ink on $stop',
          );
        }

        const uri = 'https://open.spotify.com/track/123';
        final linkSurface = tester.widget<Material>(
          find.byKey(const ValueKey('profile-vibe-link-surface-$uri')),
        );
        final linkShape = linkSurface.shape! as RoundedRectangleBorder;
        expect(linkShape.borderRadius, AppRadius.card);
        expect(
          linkShape.side,
          BorderSide(color: Colors.white.withValues(alpha: .18)),
        );
        final title = tester.widget<Text>(find.text('Spotify'));
        final host = tester.widget<Text>(find.text('open.spotify.com'));
        for (final stop in stops) {
          // The plate is translucent contrast ink over the sweep.
          final plate = Color.alphaBlend(linkSurface.color!, stop);
          expect(
            _contrastRatio(title.style!.color!, plate),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            _contrastRatio(Color.alphaBlend(host.style!.color!, plate), plate),
            greaterThanOrEqualTo(4.5),
            reason: 'host line on the plate over $stop',
          );
          for (final key in const [
            'profile-vibe-link-leading-$uri',
            'profile-vibe-link-trailing-$uri',
          ]) {
            final icon = tester.widget<Icon>(find.byKey(ValueKey(key)));
            expect(_contrastRatio(icon.color!, plate), greaterThanOrEqualTo(3));
          }
        }
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('a wide column caps the sticker at 560, start-aligned', (
      tester,
    ) async {
      await _pumpVibe(tester, vibe: 'Late-night acoustic energy', width: 1000);
      final rect = tester.getRect(
        find.byKey(const ValueKey('profile-vibe-surface')),
      );
      expect(rect.width, ProfileLayout.vibeMaxWidth);
      expect(rect.left, 18);
      await _pumpVibe(tester, vibe: 'Late-night acoustic energy', width: 700);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('profile-vibe-surface')))
            .width,
        700 - 36,
        reason: 'below a 700 px column the sticker takes the column',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('high contrast flattens the sticker and outlines it', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _pumpVibe(
        tester,
        vibe: 'Now playing https://open.spotify.com/track/123',
      );
      final surface = tester.widget<Material>(
        find.byKey(const ValueKey('profile-vibe-surface')),
      );
      expect(surface.color, AppTheme.darkTheme.colorScheme.primary);
      expect(
        (surface.shape! as RoundedRectangleBorder).side,
        BorderSide(color: AppPalette.dark.borderStrong),
      );
      expect(find.byKey(const ValueKey('profile-vibe-sweep')), findsNothing);
      expect(find.byKey(const ValueKey('profile-vibe-glint')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pending launch can outlive the widget safely', (tester) async {
      final pending = Completer<bool>();
      await _pumpVibe(
        tester,
        vibe: 'Listen https://soundcloud.com/artist/song',
        launcher: (_) => pending.future,
      );
      await tester.tap(
        find.byKey(
          const ValueKey(
            'profile-vibe-link-https://soundcloud.com/artist/song',
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());

      pending.complete(true);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('320px at 200% keeps link visible and overflow-free', (
      tester,
    ) async {
      const vibe =
          'Linkin Park - In the End https://youtu.be/eVTXPUF4Oz4 playing on repeat tonight!';
      expect(vibe.length, 80);
      await _pumpVibe(tester, vibe: vibe, width: 320, textScale: 2);

      expect(
        find.text('Linkin Park - In the End playing on repeat tonight!'),
        findsOneWidget,
      );
      expect(find.text('YouTube'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

double _contrastRatio(Color first, Color second) {
  final lighter = first.computeLuminance() > second.computeLuminance()
      ? first.computeLuminance()
      : second.computeLuminance();
  final darker = first.computeLuminance() > second.computeLuminance()
      ? second.computeLuminance()
      : first.computeLuminance();
  return (lighter + .05) / (darker + .05);
}

Future<void> _pumpVibe(
  WidgetTester tester, {
  required String vibe,
  ProfileVibeLinkLauncher? launcher,
  double width = 390,
  double textScale = 1,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = Size(width, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          backgroundColor: context.appPalette.background,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: ProfileVibeHeadline(vibe: vibe, launcher: launcher),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
