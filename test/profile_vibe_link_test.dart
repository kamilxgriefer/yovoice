import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
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
      expect(
        (focusedSurface.shape! as RoundedRectangleBorder).side,
        const BorderSide(color: Color(0xFFD986FF), width: 2),
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
}) async {
  tester.view.physicalSize = Size(width, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFF09050F),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: ProfileVibeHeadline(vibe: vibe, launcher: launcher),
        ),
      ),
    ),
  );
  await tester.pump();
}
