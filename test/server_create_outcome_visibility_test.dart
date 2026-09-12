import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/screens/create_server_screen.dart';

import 'server_test_support.dart';

/// A submit that fails answers at the END of a scrolling form, while the only
/// thing that changes near the thumb is the action bar's own label. On a real
/// phone that reads as "nothing happened": the sentence saying the server was
/// not created, and that nothing was lost, is below the fold with no cue to
/// scroll for it. These tests pin both halves of the answer — that the reason
/// is brought into view, and that a screen reader is told about it — for the
/// refusal as well as for the ordinary error.
Finder get submit => find.byKey(const ValueKey('server-create-submit'));
Finder get unavailable =>
    find.byKey(const ValueKey('server-create-unavailable'));
Finder get errorPanel => find.byKey(const ValueKey('server-create-error'));

void main() {
  /// True when [finder]'s box lies inside the viewport that scrolls it.
  ///
  /// The window is the wrong frame to measure against here: the form scrolls
  /// inside a viewport that starts below the app bar and stops above the
  /// action bar, and "visible" means inside THAT.
  bool isRevealed(WidgetTester tester, Finder finder) {
    final viewport = find
        .ancestor(of: finder, matching: find.byType(Scrollable))
        .first;
    final box = tester.getRect(finder);
    final frame = tester.getRect(viewport);
    return box.top >= frame.top && box.bottom <= frame.bottom;
  }

  Future<void> fillAndSubmit(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('server-name')),
      'Nasza ekipa',
    );
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
  }

  Future<void> pumpForm(
    WidgetTester tester,
    TestServerRepository repository,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      CreateServerScreen(
        repository: repository,
        initialType: ServerType.friends,
        onCreated: (_) {},
      ),
    );
  }

  group('the answer to a submit is visible where the person is looking', () {
    testWidgets('a refusal scrolls itself into view on a phone', (
      tester,
    ) async {
      final repository = TestServerRepository()
        ..alwaysFailWith = FirebaseFunctionsException(
          code: 'not-found',
          message: 'NOT FOUND',
        );
      await pumpForm(tester, repository);
      await fillAndSubmit(tester);

      expect(unavailable, findsOneWidget);
      expect(
        isRevealed(tester, unavailable),
        isTrue,
        reason:
            'the person tapped and the form dimmed; the reason must be on '
            'screen, not below the fold',
      );
    });

    testWidgets('an ordinary error scrolls itself into view too', (
      tester,
    ) async {
      final repository = TestServerRepository()
        ..alwaysFailWith = FirebaseFunctionsException(
          code: 'unavailable',
          message: 'down',
        );
      await pumpForm(tester, repository);
      await fillAndSubmit(tester);

      expect(errorPanel, findsOneWidget);
      expect(isRevealed(tester, errorPanel), isTrue);
    });

    testWidgets('the refusal is announced, not merely drawn', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        final repository = TestServerRepository()
          ..alwaysFailWith = FirebaseFunctionsException(
            code: 'not-found',
            message: 'NOT FOUND',
          );
        await pumpForm(tester, repository);
        await fillAndSubmit(tester);

        final live = find.ancestor(
          of: unavailable,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.liveRegion == true,
          ),
        );
        expect(
          live,
          findsAtLeastNWidgets(1),
          reason:
              'the error path already announced itself; a refusal is just as '
              'much an answer to the tap',
        );
        expect(
          tester
              .getSemantics(unavailable)
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('a viewport with no scrollable outcome still answers', (
      tester,
    ) async {
      // A desktop-height window shows the whole form at once. Revealing must
      // be a no-op there rather than an exception from a missing Scrollable.
      await tester.binding.setSurfaceSize(const Size(1440, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..alwaysFailWith = FirebaseFunctionsException(
          code: 'not-found',
          message: 'NOT FOUND',
        );
      await pumpServers(
        tester,
        CreateServerScreen(
          repository: repository,
          initialType: ServerType.friends,
          onCreated: (_) {},
        ),
      );
      await fillAndSubmit(tester);

      expect(unavailable, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
