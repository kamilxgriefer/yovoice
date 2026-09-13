import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_moments_strip.dart';

/// Preserves the useful empty-state regression from fb7874a.
///
/// The former room-banner and roster cases described a Home surface removed by
/// the server-first redesign. Current server states, callbacks and desktop
/// reflow are covered by the dedicated Home and server-overview suites.
void main() {
  group('Moments avatar-only empty state', () {
    testWidgets(
      'keeps only the own avatar and its accessible record action',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        var created = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DesktopMomentsStrip(
                onOpenMoment: (_) {},
                onCreateMoment: () => created++,
                onSeeAll: () {},
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 60));

        expect(find.text('YO Moments from your circle'), findsOneWidget);
        expect(find.byKey(const ValueKey('home-your-moment')), findsOneWidget);
        expect(
          find.textContaining('No Moments from your circle yet'),
          findsNothing,
        );
        expect(find.text('Find creators'), findsNothing);

        final plus = find.byKey(const ValueKey('home-record-moment'));
        expect(plus, findsOneWidget);
        expect(tester.getSize(plus), const Size(44, 44));
        await tester.tap(plus);
        await tester.pump();
        expect(created, 1);

        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}
