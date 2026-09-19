import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/badges/yo_badge.dart';

/// The one NA ŻYWO marker (Slim redesign, phase 0): every surface that used
/// to draw its own live pill now mounts `YoBadge(variant: live)`, so the
/// contracts those surfaces' tests rely on are pinned here once.
void main() {
  for (final themeCase in <({String name, ThemeData theme})>[
    (name: 'Dark', theme: AppTheme.darkTheme),
    (name: 'Pearl', theme: AppTheme.lightTheme),
  ]) {
    testWidgets(
      '${themeCase.name}: the live badge paints the liveness tokens and '
      'renders its label verbatim under the caller\'s key',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: themeCase.theme,
            home: const Scaffold(
              body: Center(
                child: YoBadge(
                  key: ValueKey('live-marker'),
                  label: 'Na żywo',
                  variant: YoBadgeVariant.live,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // The key belongs to the caller: exactly one element carries it.
        expect(find.byKey(const ValueKey('live-marker')), findsOneWidget);
        // No case transform inside the widget — callers own the copy.
        expect(find.text('Na żywo'), findsOneWidget);
        expect(find.text('NA ŻYWO'), findsNothing);

        final container = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(YoBadge),
                matching: find.byType(Container),
              )
              .first,
        );
        final decoration = container.decoration! as BoxDecoration;
        expect(decoration.color, AppColors.live);
        expect(decoration.border, isNull);
        final label = tester.widget<Text>(find.text('Na żywo'));
        expect(label.style?.color, AppColors.onLive);
        expect(label.style?.fontSize, 10);
        expect(label.style?.fontWeight, FontWeight.w800);
        expect(label.maxLines, 1);
        expect(label.softWrap, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'the pulse stops for reduced motion and for a disabled TickerMode',
    (tester) async {
      var reduced = false;
      var active = true;
      late StateSetter change;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: StatefulBuilder(
            builder: (context, setState) {
              change = setState;
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduced),
                child: TickerMode(
                  enabled: active,
                  child: const Scaffold(
                    body: Center(
                      child: YoBadge(
                        label: 'LIVE',
                        variant: YoBadgeVariant.live,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isTrue);

      change(() => reduced = true);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);

      change(() {
        reduced = false;
        active = false;
      });
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);

      change(() => active = true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'at 200 percent text the badge stays one line, taller than 26 px, and '
    'elides instead of overflowing a tight slot',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                YoBadge(
                  key: ValueKey('free'),
                  label: 'NA ŻYWO',
                  variant: YoBadgeVariant.live,
                ),
                SizedBox(
                  width: 56,
                  child: YoBadge(
                    key: ValueKey('tight'),
                    label: 'TERAZ NA ŻYWO',
                    variant: YoBadgeVariant.live,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final free = tester.getRect(find.byKey(const ValueKey('free')));
      expect(free.height, greaterThan(26));
      expect(free.height, lessThan(40), reason: 'a single line, no wrap');

      final tight = tester.getRect(find.byKey(const ValueKey('tight')));
      expect(tight.width, lessThanOrEqualTo(56));
      expect(tight.height, lessThan(40), reason: 'elides, never wraps');
      expect(tester.takeException(), isNull, reason: 'no overflow');
    },
  );
}
