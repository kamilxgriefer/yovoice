// "See who liked" list, assistive technology and keyboard (ADR-230): the
// reaction tabs are real, activatable, focusable tabs; rows say they open a
// profile; keyboard focus is a 2 px palette.focus ring on rows and tabs;
// high contrast strengthens the tab edges; the loading skeleton has a name;
// the success announcement says "Reactions" on a Server list.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/likers/data/models/likers_page.dart';
import 'package:yovoice/features/likers/data/models/likers_target.dart';
import 'package:yovoice/features/likers/presentation/widgets/likers_list_view.dart';

import 'support/likers_fixtures.dart';

const _moment = VoiceMomentLikersTarget('m1');
const _message = ServerMessageReactorsTarget('s1', 'ch1', 'msg1');

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pumpAndSettle();
}

void main() {
  Future<void> pumpList(
    WidgetTester tester,
    ScriptedLikers script, {
    LikersTarget target = _moment,
    int total = 2,
    Map<String, int> reactionCounts = const {},
    LikerOpener? onOpenLiker,
    bool highContrast = false,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      likersHost(
        Scaffold(
          body: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(highContrast: highContrast),
              child: LikersListView(
                target: target,
                totalCount: total,
                reactionCounts: reactionCounts,
                service: script.service,
                viewerId: 'me',
                onOpenLiker: onOpenLiker,
                identityRepository: identityRepository(vip: {'marta'}),
              ),
            ),
          ),
        ),
      ),
    );
    if (settle) await _settle(tester);
  }

  List<String> captureAnnouncements(WidgetTester tester) {
    final captured = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
      SystemChannels.accessibility,
      (message) async {
        if (message is Map && message['type'] == 'announce') {
          captured.add((message['data'] as Map)['message'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(
            SystemChannels.accessibility,
            null,
          ),
    );
    return captured;
  }

  AppPalette paletteOf(WidgetTester tester) =>
      tester.element(find.byType(LikersListView)).appPalette;

  /// The chip of one reaction tab (the decorated pill inside its target).
  BoxDecoration chipOf(WidgetTester tester, String key) {
    final chip = find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).borderRadius != null,
      ),
    );
    return tester.widget<DecoratedBox>(chip.first).decoration as BoxDecoration;
  }

  /// Moves keyboard focus into the control around [inside].
  Future<void> focusInside(WidgetTester tester, Finder inside) async {
    Focus.of(tester.element(inside)).requestFocus();
    await tester.pumpAndSettle();
  }

  ScriptedLikers serverScript() => ScriptedLikers([
    pageWire([
      likerWire('julia', 'Julia Nowak', reaction: '❤️'),
      likerWire('marta', 'Marta Wiśniewska', reaction: '❤️'),
      likerWire('ola', 'Ola Zielińska', reaction: '😂'),
    ]),
    pageWire([likerWire('ola', 'Ola Zielińska', reaction: '😂')]),
  ]);

  testWidgets('each reaction tab is a focusable, selectable button with a '
      'tap action, and a semantic tap filters the list', (tester) async {
    final semantics = tester.ensureSemantics();
    final script = serverScript();
    await pumpList(
      tester,
      script,
      target: _message,
      total: 3,
      reactionCounts: const {'❤️': 2, '😂': 1},
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('All: 3')),
      isSemantics(
        isButton: true,
        hasTapAction: true,
        isFocusable: true,
        hasSelectedState: true,
        isSelected: true,
        isInMutuallyExclusiveGroup: true,
      ),
    );
    for (final label in <String>['❤️: 2', '😂: 1']) {
      expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          isFocusable: true,
          hasSelectedState: true,
          isSelected: false,
        ),
        reason: label,
      );
    }
    // The visible text is not a second node.
    expect(find.bySemanticsLabel(RegExp(r'^😂 1$')), findsNothing);

    expect(script.calls, hasLength(1));
    tester.semantics.tap(find.semantics.byLabel('😂: 1'));
    await _settle(tester);
    expect(script.calls, hasLength(2));
    expect(script.calls.last.payload['emoji'], '😂');
    expect(find.text('Julia Nowak'), findsNothing);
    expect(find.text('Ola Zielińska'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('😂: 1')),
      isSemantics(isSelected: true),
    );
    semantics.dispose();
  });

  testWidgets('a row that opens a profile is a button with an "Open profile" '
      'hint; its label is unchanged', (tester) async {
    final semantics = tester.ensureSemantics();
    Liker? opened;
    final script = ScriptedLikers([
      pageWire([likerWire('marta', 'Marta Wiśniewska')]),
    ]);
    await pumpList(
      tester,
      script,
      onOpenLiker: (context, liker) async => opened = liker,
    );
    final row = find.bySemanticsLabel(RegExp('^Marta Wiśniewska'));
    expect(row, findsOneWidget);
    expect(
      tester.getSemantics(row),
      isSemantics(isButton: true, hasTapAction: true, isFocusable: true),
    );
    final node = tester.getSemantics(row);
    expect(node.label, startsWith('Marta Wiśniewska'));
    expect(node.label, contains('VIP'));
    expect(node.hintOverrides?.onTapHint, 'Open profile');
    tester.semantics.tap(find.semantics.byLabel(RegExp('^Marta Wiśniewska')));
    await _settle(tester);
    expect(opened?.userId, 'marta');
    semantics.dispose();
  });

  testWidgets('a row without an opener is not announced as a button', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpList(
      tester,
      ScriptedLikers([
        pageWire([likerWire('julia', 'Julia Nowak')]),
      ]),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('^Julia Nowak'))),
      isNot(isSemantics(isButton: true)),
    );
    semantics.dispose();
  });

  testWidgets('keyboard focus draws a 2 px palette.focus ring on a row and '
      'on a tab', (tester) async {
    await pumpList(
      tester,
      serverScript(),
      target: _message,
      total: 3,
      reactionCounts: const {'❤️': 2, '😂': 1},
      onOpenLiker: (context, liker) async {},
    );
    final palette = paletteOf(tester);

    BoxDecoration ringOf(String uid) =>
        tester
                .widget<DecoratedBox>(
                  find.byKey(ValueKey('likers-row-focus-$uid')),
                )
                .decoration
            as BoxDecoration;

    expect((ringOf('julia').border as Border?), isNull);
    await focusInside(
      tester,
      find.byKey(const ValueKey('likers-row-focus-julia')),
    );
    final row = ringOf('julia').border! as Border;
    expect(row.top.color, palette.focus);
    expect(row.top.width, 2);

    final before = chipOf(tester, 'likers-tab-😂').border! as Border;
    expect(before.top.color, isNot(palette.focus));
    await focusInside(
      tester,
      find
          .descendant(
            of: find.byKey(const ValueKey('likers-tab-😂')),
            matching: find.byType(ConstrainedBox),
          )
          .first,
    );
    final tab = chipOf(tester, 'likers-tab-😂').border! as Border;
    expect(tab.top.color, palette.focus);
    expect(tab.top.width, 2);
    // Focus left the row: its ring is gone.
    expect((ringOf('julia').border as Border?), isNull);
  });

  testWidgets('high contrast strengthens an unselected tab edge', (
    tester,
  ) async {
    await pumpList(
      tester,
      serverScript(),
      target: _message,
      total: 3,
      reactionCounts: const {'❤️': 2, '😂': 1},
      highContrast: true,
    );
    final palette = paletteOf(tester);
    final edge = chipOf(tester, 'likers-tab-❤️').border! as Border;
    expect(edge.top.color, palette.borderStrong);
    // The idle fill is the surface, not transparent, under high contrast.
    expect(chipOf(tester, 'likers-tab-❤️').color, palette.surface);
  });

  testWidgets('the loading skeleton is a named live region; a Server list '
      'announces "Reactions loaded"', (tester) async {
    final semantics = tester.ensureSemantics();
    final announcements = captureAnnouncements(tester);
    final pending = Completer<Object?>();
    final script = ScriptedLikers([pending]);
    await pumpList(
      tester,
      script,
      target: _message,
      total: 3,
      reactionCounts: const {'❤️': 2, '😂': 1},
      settle: false,
    );
    await tester.pump();
    final loading = find.bySemanticsLabel('Loading');
    expect(loading, findsOneWidget);
    expect(tester.getSemantics(loading), isSemantics(isLiveRegion: true));
    pending.complete(
      pageWire([
        likerWire('julia', 'Julia Nowak', reaction: '❤️'),
        likerWire('ola', 'Ola Zielińska', reaction: '😂'),
      ]),
    );
    await _settle(tester);
    expect(find.bySemanticsLabel('Loading'), findsNothing);
    expect(announcements, contains('Reactions loaded: 2'));
    expect(announcements, isNot(contains('Likes loaded: 2')));
    semantics.dispose();
  });

  testWidgets('the next page skeleton is named too', (tester) async {
    final semantics = tester.ensureSemantics();
    final next = Completer<Object?>();
    final script = ScriptedLikers([
      pageWire([likerWire('julia', 'Julia Nowak')], cursor: kTestCursor),
      next,
    ]);
    await pumpList(tester, script, total: 5);
    await tester.tap(find.byKey(const ValueKey('likers-load-more')));
    await tester.pump();
    expect(find.byKey(const ValueKey('likers-more-skeleton')), findsOneWidget);
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    next.complete(pageWire([likerWire('marta', 'Marta Wiśniewska')]));
    await _settle(tester);
    expect(find.bySemanticsLabel('Loading'), findsNothing);
    semantics.dispose();
  });
}
