// INDEPENDENT REVIEW PROBE — Senior Product Designer (UX/UI), 2026-09-12.
//
// Measures `ServerTemplateSelector` against the accepted selector
// `yovoice-server-concepts-2026-09-10/index.html` (CSS is quoted beside every
// number) and against contract section 4.1. Soft assertions: every mismatch is
// collected and printed together, so one run yields the whole delta list.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/servers/data/models/server_creation.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/screens/create_server_screen.dart';
import 'package:yovoice/features/servers/presentation/theme/server_identity.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_template_selector.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_type_symbol.dart';

import 'server_test_support.dart';

Finder _card(ServerType type) =>
    find.byKey(ValueKey('server-template-${type.name}'));

class _Soft {
  final failures = <String>[];
  void near(String what, double actual, double expected, {double eps = 1}) {
    if ((actual - expected).abs() > eps) {
      failures.add('$what: expected $expected, measured $actual');
    }
  }

  void equals(String what, Object? actual, Object? expected) {
    if (actual != expected) {
      failures.add('$what: expected $expected, measured $actual');
    }
  }

  void report() {
    if (failures.isEmpty) return;
    for (final line in failures) {
      // ignore: avoid_print
      print('DELTA  $line');
    }
    fail('${failures.length} deltas:\n${failures.join('\n')}');
  }
}

AnimatedContainer _shell(WidgetTester tester, ServerType type) =>
    tester.widget<AnimatedContainer>(_card(type));

Rect _tile(WidgetTester tester, ServerType type) => tester.getRect(
  find
      .ancestor(
        of: find.descendant(
          of: _card(type),
          matching: find.byType(ServerTypeSymbol),
        ),
        matching: find.byType(Container),
      )
      .first,
);

void main() {
  const dark = AppPalette.dark;

  testWidgets('QA1 card geometry matches the reference CSS', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final soft = _Soft();

    // ---- wide, < 1600: .card{min-height:390;border-radius:26;padding:30 23}
    await pumpServers(
      tester,
      Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
      size: const Size(1440, 1400),
    );
    var shell = _shell(tester, ServerType.friends);
    soft.near('wide min-height', shell.constraints!.minHeight, 390);
    soft.equals(
      'wide radius',
      (shell.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(26),
    );
    var card = tester.getRect(_card(ServerType.friends));
    var tile = _tile(tester, ServerType.friends);
    soft.near('wide padding-left', tile.left - card.left, 23);
    // .symbol{width:64;height:64;margin:8 0 35}
    soft.near('wide symbol width', tile.width, 64);
    soft.near('wide symbol height', tile.height, 64);
    soft.near('wide padding-top + symbol margin-top', tile.top - card.top, 38);
    var title = tester.getRect(
      find.descendant(
        of: _card(ServerType.friends),
        matching: find.text('Dla znajomych'),
      ),
    );
    soft.near('wide symbol margin-bottom', title.top - tile.bottom, 35, eps: 4);
    // .cards{gap:16}
    final friends = tester.getRect(_card(ServerType.friends));
    final community = tester.getRect(_card(ServerType.community));
    soft.near('wide column gap', community.left - friends.right, 16);
    // main{max-width:1540;padding:45 48 48}
    soft.near('wide side padding', friends.left, 48);
    final eyebrow = tester.getRect(
      find.text('TWOJA PRZESTRZEŃ ZACZYNA SIĘ TUTAJ'),
    );
    soft.near('wide padding-top', eyebrow.top, 45, eps: 2);

    // ---- >= 1600: main{padding-top:80}  .card{min-height:435}
    await pumpServers(
      tester,
      Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
      size: const Size(1920, 1600),
    );
    shell = _shell(tester, ServerType.friends);
    soft.near('>=1600 min-height', shell.constraints!.minHeight, 435);
    soft.near(
      '>=1600 padding-top',
      tester.getRect(find.text('TWOJA PRZESTRZEŃ ZACZYNA SIĘ TUTAJ')).top,
      80,
      eps: 2,
    );
    // max-width:1540 centred, then 48 padding.
    soft.near(
      '>=1600 first card left (1540 frame + 48)',
      tester.getRect(_card(ServerType.friends)).left,
      (1920 - 1540) / 2 + 48,
    );

    // ---- <= 1150: .card{min-height:320}  .symbol{margin-bottom:22}
    await pumpServers(
      tester,
      Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
      size: const Size(1100, 1600),
    );
    shell = _shell(tester, ServerType.friends);
    soft.near('medium min-height', shell.constraints!.minHeight, 320);
    card = tester.getRect(_card(ServerType.friends));
    tile = _tile(tester, ServerType.friends);
    title = tester.getRect(
      find.descendant(
        of: _card(ServerType.friends),
        matching: find.text('Dla znajomych'),
      ),
    );
    soft.near(
      'medium symbol margin-bottom',
      title.top - tile.bottom,
      22,
      eps: 4,
    );

    // ---- <= 640: .card{min-height:110;border-radius:22;padding:19}
    //      .symbol{width:49;height:49;border-radius:16}  .cards{gap:11}
    await pumpServers(
      tester,
      Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
      size: const Size(390, 1600),
    );
    shell = _shell(tester, ServerType.friends);
    soft.near('compact min-height', shell.constraints!.minHeight, 110);
    soft.equals(
      'compact radius',
      (shell.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(22),
    );
    card = tester.getRect(_card(ServerType.friends));
    tile = _tile(tester, ServerType.friends);
    soft.near('compact padding-left', tile.left - card.left, 19);
    soft.near('compact symbol width', tile.width, 49);
    soft.near('compact symbol height', tile.height, 49);
    soft.near('compact column gap', tile.left - card.left, 19);
    soft.near(
      'compact row gap',
      tester.getRect(_card(ServerType.community)).top - card.bottom,
      11,
    );
    soft.near('compact side padding', card.left, 20);
    soft.near(
      'compact padding-top',
      tester.getRect(find.text('TWOJA PRZESTRZEŃ ZACZYNA SIĘ TUTAJ')).top,
      25,
      eps: 2,
    );
    soft.report();
  });

  testWidgets('QA2 the arrangement switches exactly at 640 and 1150', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final soft = _Soft();
    Future<String> arrangement(double width) async {
      await pumpServers(
        tester,
        Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
        size: Size(width, 1800),
      );
      final rects = [
        for (final type in ServerType.values) tester.getRect(_card(type)),
      ];
      final tops = rects.map((r) => r.top.round()).toSet();
      if (tops.length == 5) return 'stacked';
      if (tops.length == 2) return '3+2';
      if (tops.length == 1) return 'five';
      return 'unknown(${tops.length})';
    }

    soft.equals('639', await arrangement(639), 'stacked');
    soft.equals('640', await arrangement(640), 'stacked');
    soft.equals('641', await arrangement(641), '3+2');
    soft.equals('1150', await arrangement(1150), '3+2');
    soft.equals('1151', await arrangement(1151), 'five');
    soft.report();
  });

  testWidgets('QA3 every card string is the reference string, verbatim', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const titles = {
      ServerType.friends: 'Dla znajomych',
      ServerType.community: 'Dla społeczności',
      ServerType.podcast: 'Dla podcastu',
      ServerType.family: 'Dla rodziny',
      ServerType.company: 'Dla firmy',
    };
    const bodies = {
      ServerType.friends: 'Wasze rozmowy, wspólne plany i wieczory bez końca.',
      ServerType.community:
          'Jedno miejsce dla ludzi, których łączy wspólna pasja.',
      ServerType.podcast:
          'Twoja audycja, zaproszeni goście i uważni słuchacze.',
      ServerType.family:
          'Bliskość na co dzień. Nawet kiedy dzielą was kilometry.',
      ServerType.company:
          'Rozmawiajcie, planujcie i twórzcie razem jako zespół.',
    };
    const features = {
      ServerType.friends: 'Kanały głosowe i tekstowe\nWydarzenia dla ekipy',
      ServerType.community:
          'Transmisje video i scena LIVE\nCzat, wydarzenia i moderacja',
      ServerType.podcast:
          'Prowadzący, goście i publiczność\nProgram odcinków i pytania',
      ServerType.family:
          'Wspólny kalendarz i rozmowy\nAlbum wspomnień głosowych',
      ServerType.company:
          'Spotkania i udostępnianie ekranu\nWspólna tablica i kanały zespołów',
    };
    await pumpServers(
      tester,
      Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
      size: const Size(1440, 1600),
    );
    for (final type in ServerType.values) {
      expect(find.text(titles[type]!), findsOneWidget, reason: '$type title');
      expect(find.text(bodies[type]!), findsOneWidget, reason: '$type body');
      expect(
        find.text(features[type]!),
        findsOneWidget,
        reason: '$type features',
      );
    }
    // The concept page's own copy must not have travelled with it.
    expect(find.textContaining('KONCEPCJA'), findsNothing);
    expect(find.textContaining('poglądowych plansz'), findsNothing);
    expect(find.textContaining('propozycją projektu'), findsNothing);
    expect(find.textContaining('Your Moments'), findsNothing);
    expect(
      find.text('Jeden serwer. Wiele kanałów. Twój charakter.'),
      findsOneWidget,
    );
  });

  // Closed in fix round 1 (servers-selector-fixes-1.md); the assertion is the reference.
  testWidgets('QA4 the accent PAIR matches the reference, not just --a', (
    tester,
  ) async {
    final soft = _Soft();
    // `--a` paints icon and link; `--rgb` tints card, orbit and symbol tile.
    const bright = <ServerType, Color>{
      ServerType.friends: Color(0xFF5CE1E6),
      ServerType.community: Color(0xFFC026FF),
      ServerType.podcast: Color(0xFFFF6B81),
      ServerType.family: Color(0xFF35E58D),
      ServerType.company: Color(0xFF63C7FF),
    };
    const wash = <ServerType, Color>{
      ServerType.friends: Color(0xFF5CE1E6), // 92,225,230
      ServerType.community: Color(0xFFC026FF), // 192,38,255
      ServerType.podcast: Color(0xFFFF3D68), // 255,61,104
      ServerType.family: Color(0xFF28D17C), // 40,209,124
      ServerType.company: Color(0xFF4DA3FF), // 77,163,255
    };
    for (final type in ServerType.values) {
      final identity = ServerIdentity.of(type);
      soft.equals('$type --a', identity.accent, bright[type]);
      soft.equals('$type --rgb', identity.primary, wash[type]);
    }
    soft.report();
  });

  // Closed in fix round 1 (servers-selector-fixes-1.md); the assertion is the reference.
  testWidgets('QA5 selector ink matches the reference', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final soft = _Soft();
    await pumpServers(
      tester,
      Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
      size: const Size(1440, 1600),
    );
    Color? inkOf(String text) =>
        tester.widget<Text>(find.text(text)).style?.color;
    // .eyebrow{color:#d986ff}
    soft.equals(
      'eyebrow ink',
      inkOf('TWOJA PRZESTRZEŃ ZACZYNA SIĘ TUTAJ'),
      const Color(0xFFD986FF),
    );
    // h1 inherits :root{color:#f8f5fc}
    soft.equals('h1 ink', inkOf('Stwórz swój serwer.'), dark.textPrimary);
    // .lead{color:#b8afc2}
    soft.equals(
      'lead ink',
      inkOf(
        'Dla kogo tworzysz miejsce?\n'
        'Wybierz początek. Potem nadaj mu własny charakter.',
      ),
      dark.textSecondary,
    );
    // .card p{color:#b8afc2}
    soft.equals(
      'card body ink',
      inkOf('Wasze rozmowy, wspólne plany i wieczory bez końca.'),
      dark.textSecondary,
    );
    // .features{color:#d4cbdc} — contract 4.1 names this as the open delta.
    soft.equals(
      'features ink',
      inkOf('Kanały głosowe i tekstowe\nWydarzenia dla ekipy'),
      const Color(0xFFD4CBDC),
    );
    soft.report();
  });

  // Closed in fix round 1 (servers-selector-fixes-1.md); the assertion is the reference.
  testWidgets('QA6 the lead and the compact h1 keep their reference measure', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final soft = _Soft();
    // .lead{max-width:620;margin:0 auto 48px}
    await pumpServers(
      tester,
      Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
      size: const Size(1440, 1600),
    );
    final lead = tester.getRect(
      find.text(
        'Dla kogo tworzysz miejsce?\n'
        'Wybierz początek. Potem nadaj mu własny charakter.',
      ),
    );
    if (lead.width > 621) {
      soft.failures.add(
        'lead measure: CSS caps .lead at 620, the line box is ${lead.width}',
      );
    }
    // @media(max-width:640){h1{max-width:350px}}
    await pumpServers(
      tester,
      Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
      size: const Size(640, 1800),
    );
    final heading = tester.getRect(find.text('Stwórz swój serwer.'));
    if (heading.width > 351) {
      soft.failures.add(
        'compact h1 measure: CSS caps h1 at 350, the line box is '
        '${heading.width}',
      );
    }
    soft.report();
  });

  // Closed in fix round 1 (servers-selector-fixes-1.md); the assertion is the reference.
  testWidgets('QA7 the feature list reaches assistive technology', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final handle = tester.ensureSemantics();
    await pumpServers(
      tester,
      Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
      size: const Size(1440, 1600),
    );
    final node = tester.getSemantics(_card(ServerType.friends));
    final spoken = '${node.label} ${node.hint}';
    expect(
      spoken,
      contains('Kanały głosowe i tekstowe'),
      reason:
          'sighted people read the feature list on the card; it is inside '
          'excludeSemantics and is not in the card label or hint',
    );
    handle.dispose();
  });

  // -------------------------------------------------------------- creation

  // Closed in fix round 1 (servers-selector-fixes-1.md); the assertion is the reference.
  testWidgets('QA8 the backend refusals the factory actually raises', (
    tester,
  ) async {
    // `functions/servers/creation.js` raises exactly these five codes. Four of
    // them can never be fixed by resending the identical payload, and the
    // fields are locked once a request exists, so they cannot be edited either.
    final soft = _Soft();
    // Each code must land in its own named state — never the generic
    // retryable `unknown` the probe originally measured them falling into.
    const named = <String, ServerCreationFailure>{
      'failed-precondition': ServerCreationFailure
          .precondition, // creation.js:55,73 — second family server
      'permission-denied': ServerCreationFailure.denied,
      'invalid-argument': ServerCreationFailure.rejected,
      'data-loss': ServerCreationFailure.lost, // creation.js:52,66,107
    };
    for (final code in named.keys) {
      final failure = classifyServerCreationFailure(
        FirebaseFunctionsException(code: code, message: 'refused'),
      );
      soft.equals('$code classification', failure, named[code]);
      if (failure == ServerCreationFailure.unknown) {
        soft.failures.add('$code fell through to the generic state');
      }
      if (failure.isRetryable) {
        soft.failures.add(
          '$code offers a retry that resends the identical rejected payload',
        );
      }
    }
    soft.report();
  });

  // Closed in fix round 1 (servers-selector-fixes-1.md); the assertion is the reference.
  testWidgets('QA9 a second family server is refused, not retried', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // capacity.js: FAMILY_SERVER_LIMIT = 1; creation.js:73 answers a second
    // one with `failed-precondition`, never `resource-exhausted`.
    final repository = TestServerRepository()
      ..alwaysFailWith = FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'Your existing family server must be recovered first.',
      );
    await pumpServers(
      tester,
      CreateServerScreen(
        repository: repository,
        initialType: ServerType.family,
        onCreated: (_) {},
      ),
      size: const Size(768, 1800),
    );
    await tester.enterText(
      find.byKey(const ValueKey('server-name')),
      'Nasz dom',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('server-create-submit')),
    );
    await tester.tap(find.byKey(const ValueKey('server-create-submit')));
    await tester.pumpAndSettle();

    final submit = tester.widget<FilledButton>(
      find.byKey(const ValueKey('server-create-submit')),
    );
    // The name field is locked, so the person can neither edit nor succeed.
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('server-name')),
              matching: find.byType(TextField),
            ),
          )
          .enabled,
      isFalse,
    );
    expect(
      submit.onPressed,
      isNull,
      reason:
          'a one-per-owner family refusal can never succeed on a resend, so '
          'the action must not stay armed',
    );
  });

  // Closed in fix round 1 (servers-selector-fixes-1.md); the assertion is the reference.
  testWidgets('QA10 the free allowance line is true for this template', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      CreateServerScreen(
        repository: TestServerRepository(),
        initialType: ServerType.family,
      ),
      size: const Size(768, 1800),
    );
    expect(
      find.text('Możesz utworzyć bezpłatnie do 20 nowych serwerów.'),
      findsNothing,
      reason:
          'FAMILY_SERVER_LIMIT is 1 (functions/servers/capacity.js:21); the '
          '20-server allowance never applies to a family server',
    );
  });
}
