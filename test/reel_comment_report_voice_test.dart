import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moderation/data/services/report_service.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_comment_report_sheet.dart';

/// Reporting a VOICE comment.
///
/// The report itself is unchanged — one reason, an optional note, one
/// deliberate Send — but what the reporter is shown is not: a voice comment's
/// caption is optional, so quoting it can show an empty box, and confirming a
/// blank quote tells somebody nothing about what they are about to send to a
/// staff queue.
void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    required String commentText,
    int? voiceDurationSeconds,
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
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
          body: ReelCommentReportSheet(
            authorName: 'Creator One',
            commentText: commentText,
            voiceDurationSeconds: voiceDurationSeconds,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a voice target is named and timed, never quoted blank', (
    tester,
  ) async {
    await pumpSheet(tester, commentText: '', voiceDurationSeconds: 42);

    expect(
      find.byKey(const ValueKey<String>('reel-comment-report-target-voice')),
      findsOneWidget,
    );
    expect(find.text('Voice comment · 0:42'), findsOneWidget);
    // No empty quote block pretending there are words to report.
    expect(
      find.byKey(const ValueKey<String>('reel-comment-report-target')),
      findsNothing,
    );
    expect(find.text('Creator One'), findsOneWidget);
  });

  testWidgets('a caption, when there is one, follows the recording', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      commentText: 'Listen to the bridge',
      voiceDurationSeconds: 7,
    );

    expect(find.text('Voice comment · 0:07'), findsOneWidget);
    expect(find.text('Listen to the bridge'), findsOneWidget);
  });

  testWidgets('a minute-long recording prints a real clock', (tester) async {
    await pumpSheet(tester, commentText: '', voiceDurationSeconds: 60);
    expect(find.text('Voice comment · 1:00'), findsOneWidget);
  });

  testWidgets('a text target is unchanged: the words are still quoted', (
    tester,
  ) async {
    await pumpSheet(tester, commentText: 'These exact words');

    expect(
      find.byKey(const ValueKey<String>('reel-comment-report-target')),
      findsOneWidget,
    );
    expect(find.text('These exact words'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('reel-comment-report-target-voice')),
      findsNothing,
    );
  });

  testWidgets('every reason is reachable for a voice target too', (
    tester,
  ) async {
    await pumpSheet(tester, commentText: '', voiceDurationSeconds: 12);

    // The eight reasons are built eagerly in a Column inside one scroll
    // view — deliberately, so the note keeps its text while scrolled away —
    // so every one of them is in the tree whether or not it is on screen.
    for (final reason in ReportReason.values) {
      expect(
        find.byKey(
          ValueKey<String>('reel-comment-report-reason-${reason.name}'),
        ),
        findsOneWidget,
        reason: reason.name,
      );
    }
  });

  testWidgets('200% text on a 320 px window still renders the target', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      commentText: '',
      voiceDurationSeconds: 12,
      size: const Size(320, 720),
      textScale: 2,
    );

    expect(
      find.byKey(const ValueKey<String>('reel-comment-report-target-voice')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
