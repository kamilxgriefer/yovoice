import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/theme/server_identity.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_template_selector.dart';

import 'server_test_support.dart';

/// The widths the accepted specification names, plus the two breakpoints
/// themselves and the pixel either side of each.
const _acceptanceWidths = <double>[320, 390, 768, 1100, 1440, 1920];

Finder _card(ServerType type) =>
    find.byKey(ValueKey('server-template-${type.name}'));

void main() {
  testWidgets('the selector carries the three approved Polish lines verbatim', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in _acceptanceWidths) {
      await pumpServers(
        tester,
        Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
        size: Size(width, 1400),
      );
      expect(find.text('Stwórz swój serwer.'), findsOneWidget);
      // The question and the lead are one block in the reference, separated
      // by a line break rather than by a paragraph gap.
      expect(
        find.text(
          'Dla kogo tworzysz miejsce?\n'
          'Wybierz początek. Potem nadaj mu własny charakter.',
        ),
        findsOneWidget,
      );
      // The concept gallery's affordance must not reach the product.
      expect(find.text('Zobacz koncepcję'), findsNothing);
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
  });

  testWidgets('cards keep the accepted order and per-type accent', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const accents = <ServerType, Color>{
      ServerType.friends: Color(0xFF5CE1E6),
      ServerType.community: Color(0xFFC026FF),
      ServerType.podcast: Color(0xFFFF6B81),
      ServerType.family: Color(0xFF35E58D),
      ServerType.company: Color(0xFF63C7FF),
    };
    expect(ServerType.values, [
      ServerType.friends,
      ServerType.community,
      ServerType.podcast,
      ServerType.family,
      ServerType.company,
    ]);
    for (final entry in accents.entries) {
      expect(
        ServerIdentity.of(entry.key).accent,
        entry.value,
        reason: '${entry.key} accent',
      );
    }

    await pumpServers(
      tester,
      Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
      size: const Size(1440, 1200),
    );
    final lefts = [
      for (final type in ServerType.values) tester.getRect(_card(type)).left,
    ];
    final sorted = [...lefts]..sort();
    expect(lefts, sorted, reason: 'friends → community → podcast → family → company');
  });

  testWidgets('each acceptance width lands on its approved arrangement', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in _acceptanceWidths) {
      await pumpServers(
        tester,
        Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
        size: Size(width, 1400),
      );
      final rects = [
        for (final type in ServerType.values) tester.getRect(_card(type)),
      ];
      if (width <= ServerSelectorMetrics.compactBreakpoint) {
        // Vertical compact: every card on its own row, in order.
        for (var index = 1; index < rects.length; index++) {
          expect(
            rects[index].top,
            greaterThan(rects[index - 1].bottom),
            reason: 'width $width card $index',
          );
        }
        // The compact card is a list row, not a 390-tall tile.
        expect(rects.first.height, lessThan(320), reason: 'width $width');
      } else if (width <= ServerSelectorMetrics.wideBreakpoint) {
        // 3 + 2, with the second row centred under the first.
        expect(rects[0].top, rects[1].top, reason: 'width $width');
        expect(rects[1].top, rects[2].top, reason: 'width $width');
        expect(rects[3].top, greaterThan(rects[2].bottom));
        expect(rects[3].top, rects[4].top);
        final firstRow = Rect.fromLTRB(
          rects[0].left,
          rects[0].top,
          rects[2].right,
          rects[2].bottom,
        );
        final secondRow = Rect.fromLTRB(
          rects[3].left,
          rects[3].top,
          rects[4].right,
          rects[4].bottom,
        );
        expect(
          secondRow.center.dx,
          moreOrLessEquals(firstRow.center.dx, epsilon: 1),
          reason: 'second row centred at width $width',
        );
      } else {
        // Five across, one row, equal widths.
        expect(rects.map((rect) => rect.top).toSet().length, 1);
        expect(
          rects.map((rect) => rect.width.roundToDouble()).toSet().length,
          1,
          reason: 'width $width',
        );
      }
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
  });

  testWidgets('the features line only appears where the reference shows it', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const friendsFeatures = 'Kanały głosowe i tekstowe\nWydarzenia dla ekipy';
    await pumpServers(
      tester,
      Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
      size: const Size(1440, 1200),
    );
    expect(find.text(friendsFeatures), findsOneWidget);
    expect(find.text('Wybierz'), findsNWidgets(ServerType.values.length));

    // At and below 640 the reference hides the feature list and collapses the
    // link to a bare arrow.
    await pumpServers(
      tester,
      Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
      size: const Size(640, 1400),
    );
    expect(find.text(friendsFeatures), findsNothing);
    expect(find.text('Wybierz'), findsNothing);
  });

  testWidgets('every card stays a 48 logical pixel target in both themes', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final light in [false, true]) {
      for (final width in _acceptanceWidths) {
        for (final scale in [1.0, 2.0]) {
          await pumpServers(
            tester,
            Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
            size: Size(width, 1600),
            textScale: scale,
            light: light,
          );
          for (final type in ServerType.values) {
            final rect = tester.getRect(_card(type));
            expect(
              rect.height,
              greaterThanOrEqualTo(ServerSelectorMetrics.touchTarget),
              reason: '$type $width ${scale}x light=$light',
            );
            expect(
              rect.width,
              greaterThanOrEqualTo(ServerSelectorMetrics.touchTarget),
              reason: '$type $width ${scale}x light=$light',
            );
          }
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets('doubled text still selects every template at every width', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in _acceptanceWidths) {
      final selected = <ServerType>[];
      await pumpServers(
        tester,
        Scaffold(body: ServerTemplateSelector(onSelected: selected.add)),
        size: Size(width, 900),
        textScale: 2,
      );
      for (final type in ServerType.values) {
        final card = _card(type);
        await tester.ensureVisible(card);
        await tester.pump();
        await tester.tap(card, warnIfMissed: false);
        await tester.pump();
      }
      expect(selected, ServerType.values, reason: 'width $width at 200%');
      expect(tester.takeException(), isNull, reason: 'width $width at 200%');
    }
  });

  testWidgets('arriving focus rings the card without moving its copy', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
      size: const Size(1440, 1200),
    );
    final title = find.text('Dla znajomych');
    final before = tester.getRect(title);
    final card = tester.getRect(_card(ServerType.friends));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    // The reference focuses with an outline, which by definition takes no
    // layout space. A wider border would nudge every line of copy inward.
    expect(tester.getRect(title), before);
    expect(tester.getRect(_card(ServerType.friends)), card);
  });
}
