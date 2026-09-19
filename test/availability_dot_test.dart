import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/profile/availability_dot.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';

/// The one presence dot (Slim redesign, phase 0): every avatar that used to
/// draw its own online / away / busy / offline disc now mounts
/// `AvailabilityDot`, so the colour source and the halo contract are pinned
/// here once, in both themes.
void main() {
  Future<void> pumpDot(
    WidgetTester tester, {
    required ThemeData theme,
    required Widget dot,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(body: Center(child: dot)),
      ),
    );
    await tester.pump();
  }

  BoxDecoration decorationOf(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(AvailabilityDot),
        matching: find.byType(Container),
      ),
    );
    return container.decoration! as BoxDecoration;
  }

  for (final themeCase
      in <({String name, ThemeData theme, AppPalette palette})>[
        (name: 'Dark', theme: AppTheme.darkTheme, palette: AppPalette.dark),
        (name: 'Pearl', theme: AppTheme.lightTheme, palette: AppPalette.light),
      ]) {
    testWidgets(
      '${themeCase.name}: every status paints PeopleStatus.foreground — '
      'the same ink the ring uses',
      (tester) async {
        for (final status in <PeopleStatus>[
          PeopleStatus.online,
          PeopleStatus.brb,
          PeopleStatus.busy,
          PeopleStatus.away,
        ]) {
          await pumpDot(
            tester,
            theme: themeCase.theme,
            dot: AvailabilityDot(status: status),
          );
          final decoration = decorationOf(tester);
          expect(decoration.shape, BoxShape.circle, reason: status.name);
          expect(
            decoration.color,
            status.foreground(themeCase.palette),
            reason: '${status.name} must be the ring colour as a dot',
          );
        }
        // Offline is textTertiary — one grey for the dot and the ring.
        await pumpDot(
          tester,
          theme: themeCase.theme,
          dot: const AvailabilityDot(status: PeopleStatus.away),
        );
        expect(decorationOf(tester).color, themeCase.palette.textTertiary);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${themeCase.name}: the defaults reproduce the picker dot — '
      '10 px, surfaceRaised halo 1.5',
      (tester) async {
        await pumpDot(
          tester,
          theme: themeCase.theme,
          dot: const AvailabilityDot(status: PeopleStatus.online),
        );
        final size = tester.getSize(find.byType(AvailabilityDot));
        expect(size, const Size(10, 10));
        final border = decorationOf(tester).border! as Border;
        expect(border.top.color, themeCase.palette.surfaceRaised);
        expect(border.top.width, 1.5);
      },
    );

    testWidgets(
      '${themeCase.name}: the caller owns the halo — its surface colour and '
      'width, or none at all',
      (tester) async {
        await pumpDot(
          tester,
          theme: themeCase.theme,
          dot: AvailabilityDot(
            status: PeopleStatus.busy,
            size: 16,
            borderColor: themeCase.palette.background,
            borderWidth: 3,
          ),
        );
        expect(tester.getSize(find.byType(AvailabilityDot)), const Size(16, 16));
        final halo = decorationOf(tester).border! as Border;
        expect(halo.top.color, themeCase.palette.background);
        expect(halo.top.width, 3);

        await pumpDot(
          tester,
          theme: themeCase.theme,
          dot: const AvailabilityDot(
            status: PeopleStatus.online,
            size: 8,
            borderWidth: 0,
          ),
        );
        expect(tester.getSize(find.byType(AvailabilityDot)), const Size(8, 8));
        expect(decorationOf(tester).border, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'the dot carries no semantics and no key of its own — the row that '
    'mounts it already voices the state',
    (tester) async {
      final handle = tester.ensureSemantics();
      await pumpDot(
        tester,
        theme: AppTheme.darkTheme,
        dot: const AvailabilityDot(status: PeopleStatus.online),
      );
      expect(find.bySemanticsLabel(RegExp('.+')), findsNothing);
      expect(find.byKey(const ValueKey('presence')), findsNothing);
      handle.dispose();
    },
  );

  testWidgets(
    'a caller key passes through to exactly one element',
    (tester) async {
      await pumpDot(
        tester,
        theme: AppTheme.darkTheme,
        dot: const AvailabilityDot(
          key: ValueKey('presence'),
          status: PeopleStatus.online,
        ),
      );
      expect(find.byKey(const ValueKey('presence')), findsOneWidget);
    },
  );
}
