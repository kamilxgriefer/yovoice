import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moderation/data/services/report_service.dart';
import 'package:yovoice/features/moderation/presentation/report_content_flow.dart';

double _contrastRatio(Color first, Color second) {
  final lighter = first.computeLuminance() > second.computeLuminance()
      ? first.computeLuminance()
      : second.computeLuminance();
  final darker = first.computeLuminance() > second.computeLuminance()
      ? second.computeLuminance()
      : first.computeLuminance();
  return (lighter + .05) / (darker + .05);
}

void main() {
  Future<void> openFlow(
    WidgetTester tester, {
    required ThemeData theme,
    required ContentReportService service,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              key: const ValueKey('open-report-flow'),
              onPressed: () => unawaited(
                reportContent(
                  context: context,
                  content: const ReportedContent.voiceMoment(momentId: 'm1'),
                  title: 'Report this Voice Moment',
                  subtitle: 'Choose the reason that best fits.',
                  service: service,
                ),
              ),
              child: const Text('Report'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-report-flow')));
    await tester.pumpAndSettle();
  }

  for (final variant in <({String name, ThemeData theme, AppPalette palette})>[
    (name: 'Dark', theme: AppTheme.darkTheme, palette: AppPalette.dark),
    (name: 'Pearl', theme: AppTheme.lightTheme, palette: AppPalette.light),
  ]) {
    testWidgets('${variant.name} report picker uses semantic theme roles', (
      tester,
    ) async {
      await openFlow(
        tester,
        theme: variant.theme,
        service: _StubContentReportService(),
      );

      final sheet = tester.widget<Container>(
        find.byKey(const ValueKey('report-reason-sheet')),
      );
      final decoration = sheet.decoration! as BoxDecoration;
      expect(decoration.color, variant.palette.surface);
      expect(decoration.border!.top.color, variant.palette.border);

      final title = tester.widget<Text>(find.text('Report this Voice Moment'));
      final subtitle = tester.widget<Text>(
        find.text('Choose the reason that best fits.'),
      );
      expect(title.style!.color, variant.palette.textPrimary);
      expect(subtitle.style!.color, variant.palette.textSecondary);

      final selfHarmIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('report-reason-selfHarm')),
          matching: find.byType(Icon),
        ),
      );
      expect(selfHarmIcon.color, variant.palette.dangerForeground);

      final focusSurface = find.byKey(
        const ValueKey('report-reason-focus-spam'),
      );
      final reasonTile = tester.widget<ListTile>(
        find.descendant(of: focusSurface, matching: find.byType(ListTile)),
      );
      reasonTile.focusNode!.requestFocus();
      await tester.pumpAndSettle();

      final focusedDecoration =
          tester.widget<AnimatedContainer>(focusSurface).foregroundDecoration!
              as BoxDecoration;
      final focusBorder = (focusedDecoration.border! as Border).top;
      expect(focusBorder.color, variant.palette.focus);
      expect(focusBorder.width, 2);
      expect(
        _contrastRatio(focusBorder.color, variant.palette.surface),
        greaterThanOrEqualTo(3),
      );
    });
  }

  testWidgets('Pearl success feedback uses the semantic success pair', (
    tester,
  ) async {
    await openFlow(
      tester,
      theme: AppTheme.lightTheme,
      service: _StubContentReportService(),
    );

    await tester.tap(find.byKey(const ValueKey('report-reason-impersonation')));
    await tester.pumpAndSettle();

    final snackBar = tester.widget<SnackBar>(
      find.byKey(const ValueKey('report-result-snackbar')),
    );
    expect(snackBar.backgroundColor, AppPalette.light.successSurface);
    expect(
      (snackBar.shape! as RoundedRectangleBorder).side.color,
      AppPalette.light.successForeground,
    );

    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('report-result-snackbar')),
        matching: find.byIcon(Icons.check_circle_outline_rounded),
      ),
    );
    expect(icon.color, AppPalette.light.successForeground);
  });

  testWidgets('Dark failure feedback uses the semantic danger pair', (
    tester,
  ) async {
    await openFlow(
      tester,
      theme: AppTheme.darkTheme,
      service: _StubContentReportService(fail: true),
    );

    await tester.tap(find.byKey(const ValueKey('report-reason-spam')));
    await tester.pumpAndSettle();

    final snackBar = tester.widget<SnackBar>(
      find.byKey(const ValueKey('report-result-snackbar')),
    );
    expect(snackBar.backgroundColor, AppPalette.dark.dangerSurface);
    expect(
      (snackBar.shape! as RoundedRectangleBorder).side.color,
      AppPalette.dark.dangerForeground,
    );

    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('report-result-snackbar')),
        matching: find.byIcon(Icons.error_outline_rounded),
      ),
    );
    expect(icon.color, AppPalette.dark.dangerForeground);
  });
}

class _StubContentReportService extends ContentReportService {
  _StubContentReportService({this.fail = false});

  final bool fail;

  @override
  Future<void> report({
    required ReportedContent content,
    required ReportReason reason,
  }) async {
    if (fail) throw StateError('synthetic failure');
  }
}
