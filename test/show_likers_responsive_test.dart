import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/likers/data/models/likers_target.dart';
import 'package:yovoice/features/likers/data/services/likers_access_service.dart';
import 'package:yovoice/features/likers/presentation/show_likers.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'support/likers_fixtures.dart';

const _moment = VoiceMomentLikersTarget('m1');

class _FakeAccess extends LikersAccessService {
  _FakeAccess({required this.cached, bool? fresh}) : fresh = fresh ?? cached;

  final bool cached;
  final bool fresh;
  int freshReads = 0;

  @override
  Stream<bool> watchCanSeeLikers() => Stream<bool>.value(cached);

  @override
  Future<bool> canSeeLikers() async {
    freshReads++;
    return fresh;
  }
}

Future<void> settleAll(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pumpAndSettle();
}

void main() {
  late PublicIdentityRepository repository;

  setUp(() => repository = identityRepository(vip: {'marta'}));

  void size(WidgetTester tester, Size logical) {
    tester.view.physicalSize = logical * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// A host with one focusable "Likes" button that opens the flow.
  Future<FocusNode> pumpHost(
    WidgetTester tester, {
    required LikersAccessService access,
    required ScriptedLikers script,
    LikersTarget target = _moment,
    int total = 24,
    VoidCallback? onOpened,
    VoidCallback? onClosed,
    LikerOpener? onOpenLiker,
    bool pearl = false,
  }) async {
    final node = FocusNode(debugLabel: 'invoker');
    addTearDown(node.dispose);
    await tester.pumpWidget(
      likersHost(
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                key: const ValueKey('open-likers'),
                focusNode: node,
                onPressed: () => showLikers(
                  context,
                  target,
                  totalCount: total,
                  access: access,
                  service: script.service,
                  returnFocus: node,
                  onSheetOpened: onOpened,
                  onSheetClosed: onClosed,
                  onOpenLiker: onOpenLiker,
                  viewerId: 'me',
                  identityRepository: repository,
                ),
                child: const Text('Likes'),
              ),
            ),
          ),
        ),
        pearl: pearl,
      ),
    );
    return node;
  }

  Future<void> open(WidgetTester tester, FocusNode node) async {
    node.requestFocus();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('open-likers')));
    await settleAll(tester);
  }

  for (final width in const [390.0, 800.0, 1280.0]) {
    testWidgets('list sheet at $width px', (tester) async {
      const height = 900.0;
      size(tester, const Size(0, height) + Offset(width, 0));
      final script = ScriptedLikers([
        pageWire([
          likerWire('julia', 'Julia Nowak'),
          likerWire('marta', 'Marta Wiśniewska'),
        ]),
      ]);
      final node = await pumpHost(
        tester,
        access: _FakeAccess(cached: true),
        script: script,
        total: 2,
      );
      await open(tester, node);
      final surface = tester.getRect(
        find.byKey(const ValueKey('likers-sheet-surface')),
      );
      expect(surface.width, lessThanOrEqualTo(math.min(width, 520)));
      if (width < 600) {
        expect(
          find.byKey(const ValueKey('likers-sheet-draggable')),
          findsOneWidget,
        );
        expect(surface.width, width);
      } else {
        expect(
          find.byKey(const ValueKey('likers-sheet-fixed')),
          findsOneWidget,
        );
        expect(surface.height, closeTo(math.min(640, height * .8), 1));
        expect((surface.center.dx - width / 2).abs(), lessThan(1));
      }
      expect(find.text('Julia Nowak'), findsOneWidget);
      expect(find.byKey(const ValueKey('modal-sheet-close')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a VIP sees the list; Esc closes; focus returns; hooks fire', (
    tester,
  ) async {
    size(tester, const Size(390, 844));
    var opened = 0;
    var closed = 0;
    final script = ScriptedLikers([
      pageWire([likerWire('julia', 'Julia Nowak')]),
    ]);
    final node = await pumpHost(
      tester,
      access: _FakeAccess(cached: true),
      script: script,
      onOpened: () => opened++,
      onClosed: () => closed++,
    );
    await open(tester, node);
    expect(opened, 1);
    expect(closed, 0);
    expect(find.text('Julia Nowak'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleAll(tester);
    expect(find.text('Julia Nowak'), findsNothing);
    expect(closed, 1);
    expect(node.hasFocus, isTrue);
  });

  testWidgets('a non-VIP gets the U1 upsell: public count, no buy CTA', (
    tester,
  ) async {
    size(tester, const Size(390, 844));
    var closed = 0;
    final access = _FakeAccess(cached: false);
    final script = ScriptedLikers(const []);
    final node = await pumpHost(
      tester,
      access: access,
      script: script,
      onClosed: () => closed++,
    );
    await open(tester, node);
    expect(access.freshReads, 1);
    expect(script.calls, isEmpty);
    expect(find.byKey(const ValueKey('likers-upsell-surface')), findsOneWidget);
    expect(find.text('24 people liked this Moment'), findsOneWidget);
    expect(find.text('See who liked — a Premium feature'), findsOneWidget);
    expect(
      find.text('Premium isn\'t available to buy yet. It\'s coming soon.'),
      findsOneWidget,
    );
    expect(find.textContaining('Explore'), findsNothing);
    // One neutral action only.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('likers-upsell-surface')),
        matching: find.byType(FilledButton),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('likers-upsell-close')));
    await settleAll(tester);
    expect(find.byKey(const ValueKey('likers-upsell-surface')), findsNothing);
    expect(closed, 1);
    expect(node.hasFocus, isTrue);
  });

  testWidgets('Polish upsell count uses the right plural', (tester) async {
    size(tester, const Size(390, 844));
    for (final (count, expected) in const [
      (1, '1 osoba polubiła ten Moment'),
      (24, '24 osoby polubiły ten Moment'),
      (25, '25 osób polubiło ten Moment'),
      (12, '12 osób polubiło ten Moment'),
    ]) {
      await tester.pumpWidget(
        likersHost(
          Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showLikersUpsell(context, _moment, totalCount: count),
              child: const Text('open'),
            ),
          ),
          locale: const Locale('pl'),
        ),
      );
      await tester.tap(find.text('open'));
      await settleAll(tester);
      expect(find.text(expected), findsOneWidget);
      expect(
        find.text('Zobacz, kto polubił — funkcja Premium'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('likers-upsell-close')));
      await settleAll(tester);
    }
  });

  testWidgets('cached no + fresh yes (grant pre-read failed) opens the list', (
    tester,
  ) async {
    size(tester, const Size(390, 844));
    final access = _FakeAccess(cached: false, fresh: true);
    final script = ScriptedLikers([
      pageWire([likerWire('julia', 'Julia Nowak')]),
    ]);
    final node = await pumpHost(tester, access: access, script: script);
    await open(tester, node);
    expect(access.freshReads, 1);
    expect(find.text('Julia Nowak'), findsOneWidget);
    expect(find.byKey(const ValueKey('likers-upsell-surface')), findsNothing);
  });

  testWidgets('server says accessRequired: the list closes into the upsell', (
    tester,
  ) async {
    size(tester, const Size(800, 900));
    var opened = 0;
    var closed = 0;
    final script = ScriptedLikers([
      functionsError('failed-precondition', reason: 'likersAccessRequired'),
    ]);
    final node = await pumpHost(
      tester,
      access: _FakeAccess(cached: true),
      script: script,
      onOpened: () => opened++,
      onClosed: () => closed++,
    );
    await open(tester, node);
    expect(find.byKey(const ValueKey('likers-sheet-surface')), findsNothing);
    expect(find.byKey(const ValueKey('likers-upsell-surface')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('likers-upsell-close')));
    await settleAll(tester);
    expect(opened, 1);
    expect(closed, 1);
  });

  testWidgets('a row stacks the profile over the list, which survives', (
    tester,
  ) async {
    size(tester, const Size(390, 844));
    final script = ScriptedLikers([
      pageWire([likerWire('julia', 'Julia Nowak')]),
    ]);
    final node = await pumpHost(
      tester,
      access: _FakeAccess(cached: true),
      script: script,
      onOpenLiker: (context, liker) => showModalBottomSheet<void>(
        context: context,
        builder: (_) => SizedBox(
          height: 200,
          child: Center(child: Text('profile ${liker.userId}')),
        ),
      ),
    );
    await open(tester, node);
    final row = find.byKey(const ValueKey('likers-row-julia'));
    // Keyboard path: focus the row, activate it.
    Focus.of(tester.element(find.text('Julia Nowak'))).requestFocus();
    await tester.pump();
    await tester.tap(row);
    await settleAll(tester);
    expect(find.text('profile julia'), findsOneWidget);
    expect(find.text('Julia Nowak'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await settleAll(tester);
    expect(find.text('profile julia'), findsNothing);
    expect(find.text('Julia Nowak'), findsOneWidget);
    expect(script.calls, hasLength(1));
  });

  testWidgets('a second tap while opening is ignored', (tester) async {
    size(tester, const Size(390, 844));
    final script = ScriptedLikers([
      pageWire([likerWire('julia', 'Julia Nowak')]),
    ]);
    await pumpHost(tester, access: _FakeAccess(cached: true), script: script);
    await tester.tap(find.byKey(const ValueKey('open-likers')));
    await tester.tap(
      find.byKey(const ValueKey('open-likers')),
      warnIfMissed: false,
    );
    await settleAll(tester);
    expect(find.byKey(const ValueKey('likers-sheet-surface')), findsOneWidget);
    expect(script.calls, hasLength(1));
  });

  testWidgets('Pearl renders both sheets without errors', (tester) async {
    size(tester, const Size(1280, 900));
    final script = ScriptedLikers([
      pageWire([likerWire('marta', 'Marta Wiśniewska')]),
    ]);
    final node = await pumpHost(
      tester,
      access: _FakeAccess(cached: true),
      script: script,
      pearl: true,
    );
    await open(tester, node);
    expect(find.text('Marta Wiśniewska'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
