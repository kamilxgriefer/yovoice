// The six-tab ×0.9 dock (Premium Pages, ADR-232; spec premium-pages §4.1).
//
// The five-tab dock stays the production dock until Pages are enabled for
// the signed-in account, and keeps its own suite in
// yo_floating_navigation_dock_test.dart. This suite pins the six-tab mode:
// the width regimes, 48 px targets from 320 px, the R1 geometry, routing
// with Treści at shell slot 14, the expanded 200 % mode, the bead spring
// across 342.8 px, RTL, and the 43-locale compact-label sweep.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show SemanticsAction;

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph, SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';

const _labels = ['Home', 'Servers', 'Chats', 'Content', 'Moments', 'More'];
const _serversTab = 13;
const _contentTab = 14;
const _momentsTab = 5;

Finder _target(int slot) => find.byKey(ValueKey('yo-destination-$slot'));
Finder get _caption =>
    find.byKey(const ValueKey('yo-meniscus-accessible-label'));
Finder get _bead => find.byKey(const ValueKey('yo-meniscus-bead'));
Finder get _dock => find.byKey(const ValueKey('yo-floating-navigation-dock'));

bool _selected(WidgetTester tester, String label) => tester
    .widgetList<Semantics>(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == label,
      ),
    )
    .any((widget) => widget.properties.selected == true);

int _actionableButtonCount(SemanticsNode root) {
  var count = 0;
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.hasAction(SemanticsAction.tap) && data.flagsCollection.isButton) {
      count++;
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return count;
}

Future<SemanticsHandle> _pumpDock(
  WidgetTester tester, {
  double width = 390,
  double height = 844,
  double textScale = 1,
  bool reduceMotion = false,
  ValueListenable<bool>? reduceMotionListenable,
  ThemeData? theme,
  Locale locale = const Locale('en'),
  int initialSelected = 0,
  int unreadConversationCount = 0,
  ValueChanged<int>? onRequested,
  GlobalKey<_DockHarnessState>? harnessKey,
  Map<int, GlobalKey>? tourDestinationKeys,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final semantics = tester.ensureSemantics();
  final owned = reduceMotionListenable == null
      ? ValueNotifier<bool>(reduceMotion)
      : null;
  if (owned != null) addTearDown(owned.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: ValueListenableBuilder<bool>(
        valueListenable: reduceMotionListenable ?? owned!,
        builder: (context, disabled, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disabled,
          ),
          child: child!,
        ),
        child: _DockHarness(
          key: harnessKey,
          initialSelected: initialSelected,
          unreadConversationCount: unreadConversationCount,
          onRequested: onRequested,
          tourDestinationKeys: tourDestinationKeys,
        ),
      ),
    ),
  );
  await tester.pump();
  return semantics;
}

class _DockHarness extends StatefulWidget {
  const _DockHarness({
    required this.initialSelected,
    required this.unreadConversationCount,
    this.onRequested,
    this.tourDestinationKeys,
    super.key,
  });
  final int initialSelected, unreadConversationCount;
  final ValueChanged<int>? onRequested;
  final Map<int, GlobalKey>? tourDestinationKeys;
  @override
  State<_DockHarness> createState() => _DockHarnessState();
}

class _DockHarnessState extends State<_DockHarness> {
  late int selected = widget.initialSelected;
  int moreActions = 0;
  bool moreSelected = false;
  bool contentEnabled = true;

  void setContentEnabled(bool value) => setState(() => contentEnabled = value);

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => setState(() => moreSelected = false),
        child: const Text('Close More'),
      ),
    ),
    bottomNavigationBar: YoFloatingNavigationDock(
      tourDestinationKeys: widget.tourDestinationKeys,
      selectedTabIndex: selected,
      roomsTabIndex: _serversTab,
      momentsTabIndex: _momentsTab,
      contentTabIndex: contentEnabled ? _contentTab : null,
      unreadConversationCount: widget.unreadConversationCount,
      moreSelected: moreSelected,
      onDestinationSelected: (index) {
        widget.onRequested?.call(index);
        setState(() {
          selected = index;
          moreSelected = false;
        });
      },
      onVoicePressed: () {},
      onMorePressed: () => setState(() {
        moreActions++;
        moreSelected = true;
      }),
    ),
  );
}

YoMeniscusPainter _painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.byKey(const ValueKey('yo-meniscus-surface')),
            )
            .painter!
        as YoMeniscusPainter;

void _expectBeadAt(WidgetTester tester, int slot) {
  expect(
    tester.getCenter(_bead).dx,
    closeTo(tester.getCenter(_target(slot)).dx, .6),
  );
  expect(
    _painter(tester).center,
    closeTo(tester.getCenter(_bead).dx - tester.getRect(_dock).left, .6),
  );
}

/// The R1 run (`pages-r/dock/src/run4.log`) measured these rectangles for
/// the approved render: dock width and target width per viewport.
final _r1 = <double, ({double margin, double step, double bead})>{
  320: (margin: 3, step: 48, bead: 39.6),
  340: (margin: 12.6, step: 48.16, bead: 39.6),
  360: (margin: 12.6, step: 49.68, bead: 43.2),
  390: (margin: 12.6, step: 55.68, bead: 43.2),
};

void main() {
  group('six-tab geometry (spec §4.1.1-4.1.2)', () {
    test('metrics are the five-tab dock at ×0.9 with six slots', () {
      const six = YoDockMetrics.sixTab, five = YoDockMetrics.fiveTab;
      expect(six.slots, 6);
      expect(five.slots, 5);
      for (final (a, b) in [
        (six.topClearance, five.topClearance),
        (six.minimumBottomClearance, five.minimumBottomClearance),
        (six.visualHeight, five.visualHeight),
        (six.bodyTop, five.bodyTop),
        (six.corner, five.corner),
        (six.socketPad, five.socketPad),
        (six.iconTop, five.iconTop),
        (six.iconBox, five.iconBox),
        (six.iconSize, five.iconSize),
        (six.momentsIconSize, five.momentsIconSize),
        (six.lift, five.lift),
        (six.labelSize, five.labelSize),
        (six.labelTop, five.labelTop),
        (six.labelOverhang, five.labelOverhang),
        (six.tileRadius, five.tileRadius),
        (six.glow, five.glow),
        (six.accessibleVisualHeight, five.accessibleVisualHeight),
        (six.accessibleGrowthPerScale, five.accessibleGrowthPerScale),
        (six.expandedLabelTop, five.expandedLabelTop),
        (six.expandedLabelInset, five.expandedLabelInset),
      ]) {
        expect(a, closeTo(b * .9, 1e-9));
      }
      expect(six.visualHeight, closeTo(82.8, 1e-9));
      expect(six.accessibleVisualHeight, closeTo(138.6, 1e-9));
      expect(six.expandedMinimumHeight, closeTo(104.4, 1e-9));
      expect(six.compactLabelMaxHeight, closeTo(23.4, 1e-9));
      expect(
        YoFloatingNavigationDock.reservedHeightFor(
          safeBottom: 34,
          sixTabs: true,
        ),
        closeTo(3.6 + 82.8 + 34, 1e-9),
      );
      expect(
        YoFloatingNavigationDock.reservedHeightFor(
          safeBottom: 0,
          sixTabs: true,
        ),
        closeTo(3.6 + 82.8 + 9, 1e-9),
      );
      expect(
        YoFloatingNavigationDock.reservedHeightFor(
          safeBottom: 0,
          textScale: 2,
          sixTabs: true,
        ),
        closeTo(3.6 + 138.6 + 9, 1e-9),
      );
      expect(
        YoFloatingNavigationDock.visualHeightFor(textScale: 3, sixTabs: true),
        closeTo(138.6 + 23.4, 1e-9),
      );
    });

    test('width regimes keep every target at least 48 px wide', () {
      final regular = YoFloatingNavigationDock.sixTabRegimeFor(390);
      expect(regular.name, 'regular');
      expect(regular.bead, 43.2);
      final narrowA = YoFloatingNavigationDock.sixTabRegimeFor(345);
      expect(narrowA.name, 'narrowA');
      expect(narrowA.inset, closeTo((345 - 265.2) / 2, 1e-9));
      expect(narrowA.bead, 43.2);
      final narrowB = YoFloatingNavigationDock.sixTabRegimeFor(320);
      expect(narrowB.name, 'narrowB');
      expect(narrowB.margin, closeTo(3, 1e-9));
      expect(narrowB.inset, 37);
      expect(narrowB.bead, 39.6);
      final floor = YoFloatingNavigationDock.sixTabRegimeFor(300);
      expect(floor.name, 'belowFloor');
      expect(floor.margin, 0);
      expect(floor.inset, closeTo(30, 1e-9));
      expect(
        YoFloatingNavigationDock.sixTabRegimeFor(342.8).name,
        'narrowA',
        reason: '342.8 itself keeps the wide bead',
      );
      expect(YoFloatingNavigationDock.sixTabRegimeFor(342.79).name, 'narrowB');
      for (var w = 288.0; w <= 1400; w += .4) {
        final r = YoFloatingNavigationDock.sixTabRegimeFor(w);
        final dock = math.min(460.0, w - 2 * r.margin);
        final step = (dock - 2 * r.inset) / 5;
        expect(
          step,
          greaterThanOrEqualTo(48 - 1e-9),
          reason: 'step at $w (${r.name}) is $step',
        );
      }
    });

    test('visual slots map Treści at 3 and move Momenty to 4', () {
      int? slot(int tab) => YoFloatingNavigationDock.visualSlotForTab(
        tab,
        momentsTabIndex: _momentsTab,
        roomsTabIndex: _serversTab,
        contentTabIndex: _contentTab,
      );
      expect([0, _serversTab, 1, _contentTab, _momentsTab].map(slot), [
        0,
        1,
        2,
        3,
        4,
      ]);
      expect(slot(2), isNull, reason: 'Friends has no dock slot');
      expect(slot(3), isNull, reason: 'Discover has no dock slot');
      expect(
        YoFloatingNavigationDock.visualSlotForTab(
          _contentTab,
          momentsTabIndex: _momentsTab,
          roomsTabIndex: _serversTab,
        ),
        isNull,
        reason: 'with Pages off slot 14 has no dock destination',
      );
    });
  });

  for (final width in [320.0, 340.0, 360.0, 390.0, 430.0, 768.0]) {
    for (final light in [false, true]) {
      testWidgets(
        'six destinations, 48px targets and R1 geometry at $width light=$light',
        (tester) async {
          final semantics = await _pumpDock(
            tester,
            width: width,
            theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
            reduceMotion: true,
          );
          expect(
            _actionableButtonCount(
              tester.getSemantics(
                find.byKey(const ValueKey('yo-floating-navigation-semantics')),
              ),
            ),
            6,
          );
          final regime = YoFloatingNavigationDock.sixTabRegimeFor(width);
          final dockRect = tester.getRect(_dock);
          expect(dockRect.width, closeTo(math.min(460, width - 2 * regime.margin), .01));
          expect(dockRect.height, closeTo(82.8, .01));
          var previousX = 0.0;
          for (var slot = 0; slot < 6; slot++) {
            final rect = tester.getRect(_target(slot));
            expect(rect.width, greaterThanOrEqualTo(48 - 1e-6));
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(rect.center.dx, greaterThan(previousX));
            expect(rect.left, greaterThanOrEqualTo(dockRect.left - .01));
            expect(rect.right, lessThanOrEqualTo(dockRect.right + .01));
            previousX = rect.center.dx;
            expect(find.bySemanticsLabel(_labels[slot]), findsOneWidget);
          }
          final r1 = _r1[width];
          if (r1 != null) {
            expect(dockRect.left, closeTo(r1.margin, .01));
            expect(tester.getSize(_target(0)).width, closeTo(r1.step, .01));
            expect(tester.getSize(_bead).width, closeTo(r1.bead, .01));
          }
          expect(
            tester
                .widget<Icon>(
                  find.descendant(of: _target(3), matching: find.byType(Icon)),
                )
                .icon,
            Icons.article_outlined,
          );
          expect(
            find.byKey(const ValueKey('yo-destination-label-0')),
            findsOneWidget,
            reason: 'compact mode shows the selected label under the bead',
          );
          expect(_caption, findsNothing);
          _expectBeadAt(tester, 0);
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  }

  testWidgets('taps route to stable shell slots, Treści to slot 14', (
    tester,
  ) async {
    final requests = <int>[];
    final key = GlobalKey<_DockHarnessState>();
    final semantics = await _pumpDock(
      tester,
      width: 320,
      reduceMotion: true,
      onRequested: requests.add,
      harnessKey: key,
    );
    for (final slot in [1, 2, 3, 4, 0]) {
      await tester.tap(_target(slot));
      await tester.pump();
      expect(_selected(tester, _labels[slot]), isTrue);
      _expectBeadAt(tester, slot);
    }
    expect(requests, [_serversTab, 1, _contentTab, _momentsTab, 0]);
    await tester.tap(_target(3));
    await tester.pump();
    await tester.tap(_target(5));
    await tester.pump();
    expect(_selected(tester, 'More'), isTrue);
    _expectBeadAt(tester, 5);
    await tester.tap(find.text('Close More'));
    await tester.pump();
    expect(_selected(tester, 'Content'), isTrue);
    _expectBeadAt(tester, 3);
    expect(key.currentState!.moreActions, 1);
    semantics.dispose();
  });

  testWidgets('dragging the bead clamps at slot 5 and requests More', (
    tester,
  ) async {
    final requests = <int>[];
    final key = GlobalKey<_DockHarnessState>();
    final semantics = await _pumpDock(
      tester,
      initialSelected: _momentsTab,
      onRequested: requests.add,
      harnessKey: key,
    );
    _expectBeadAt(tester, 4);
    final gesture = await tester.startGesture(tester.getCenter(_bead));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveTo(Offset(2000, tester.getCenter(_bead).dy));
    await tester.pump();
    _expectBeadAt(tester, 5);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    expect(key.currentState!.moreActions, 1);
    semantics.dispose();
  });

  testWidgets('bead colour gains the fourth stop at Treści', (tester) async {
    final semantics = await _pumpDock(
      tester,
      initialSelected: _contentTab,
      reduceMotion: true,
    );
    final bead = tester.widget<Container>(_bead);
    final gradient =
        (bead.decoration! as BoxDecoration).gradient! as LinearGradient;
    // The stop between the chats accent and the moments secondary.
    expect(
      gradient.colors.last,
      Color.lerp(AppColors.accent, AppColors.secondary, .5),
    );
    semantics.dispose();
  });

  for (final width in [320.0, 390.0]) {
    for (final locale in ['en', 'pl', 'ar']) {
      testWidgets('200% text: expanded 138.6 bar with a 12 px caption at '
          '$width $locale', (tester) async {
        final semantics = await _pumpDock(
          tester,
          width: width,
          height: 700,
          textScale: 2,
          locale: Locale(locale),
          initialSelected: _contentTab,
          reduceMotion: true,
        );
        final dockRect = tester.getRect(_dock);
        expect(dockRect.height, greaterThanOrEqualTo(138.6 - .01));
        final copy = AppLocalizations.of(tester.element(_dock));
        for (var slot = 0; slot < 6; slot++) {
          expect(tester.getSize(_target(slot)).width, greaterThanOrEqualTo(48));
          expect(
            find.byKey(ValueKey('yo-destination-label-$slot')),
            findsNothing,
          );
        }
        for (final slot in [3, 0, 1, 2, 4]) {
          await tester.tap(_target(slot));
          await tester.pump();
          final text = tester.widget<Text>(_caption);
          final paragraph = tester.renderObject<RenderParagraph>(_caption);
          expect(text.data, [
            copy.home,
            copy.navigationServers,
            copy.chats,
            copy.navigationContent,
            copy.navigationYourMoments,
          ][slot]);
          expect(paragraph.textScaler.scale(12), 24);
          expect(paragraph.didExceedMaxLines, isFalse);
          final rect = tester.getRect(_caption);
          expect(rect.left, greaterThanOrEqualTo(dockRect.left));
          expect(rect.right, lessThanOrEqualTo(dockRect.right));
          expect(rect.bottom, lessThanOrEqualTo(dockRect.bottom));
          expect(tester.takeException(), isNull);
        }
        semantics.dispose();
      });
    }
  }

  testWidgets('Polish Treści stays compact at 320 px and 1.0x', (
    tester,
  ) async {
    final semantics = await _pumpDock(
      tester,
      width: 320,
      locale: const Locale('pl'),
      initialSelected: _contentTab,
      reduceMotion: true,
    );
    expect(_caption, findsNothing);
    expect(find.text('Treści'), findsOneWidget);
    expect(tester.getSize(_dock).height, closeTo(82.8, .01));
    semantics.dispose();
  });

  group('bead spring across 342.8 px (spec §4.1.2)', () {
    testWidgets('a width change springs bead and inset, a tab change never '
        'does', (tester) async {
      final semantics = await _pumpDock(tester, width: 360, height: 700);
      expect(tester.getSize(_bead).width, closeTo(43.2, .01));

      tester.view.physicalSize = const Size(330, 700);
      await tester.pump();
      // The frame that sees the new width still draws the old bead…
      expect(tester.getSize(_bead).width, closeTo(43.2, .01));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 60));
      final mid = tester.getSize(_bead).width;
      expect(mid, lessThan(43.2));
      expect(mid, greaterThan(39.6));
      await tester.pumpAndSettle();
      expect(tester.getSize(_bead).width, closeTo(39.6, .01));
      for (var slot = 0; slot < 6; slot++) {
        expect(tester.getSize(_target(slot)).width, greaterThanOrEqualTo(48));
      }

      // Changing tabs at a fixed width keeps the bead size constant.
      await tester.tap(_target(3));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getSize(_bead).width, closeTo(39.6, .01));
      }
      await tester.pumpAndSettle();

      tester.view.physicalSize = const Size(390, 700);
      await tester.pumpAndSettle();
      expect(tester.getSize(_bead).width, closeTo(43.2, .01));
      _expectBeadAt(tester, 3);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('under Reduce Motion the regime switch is instant', (
      tester,
    ) async {
      final semantics = await _pumpDock(
        tester,
        width: 360,
        height: 700,
        reduceMotion: true,
      );
      expect(tester.getSize(_bead).width, closeTo(43.2, .01));
      tester.view.physicalSize = const Size(320, 700);
      await tester.pump();
      expect(tester.getSize(_bead).width, closeTo(39.6, .01));
      expect(tester.getRect(_dock).left, closeTo(3, .01));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getSize(_bead).width, closeTo(39.6, .01));
      expect(tester.hasRunningAnimations, isFalse);
      semantics.dispose();
    });

    testWidgets('the first layout at a narrow width does not animate', (
      tester,
    ) async {
      final semantics = await _pumpDock(tester, width: 320, height: 700);
      expect(tester.getSize(_bead).width, closeTo(39.6, .01));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getSize(_bead).width, closeTo(39.6, .01));
      semantics.dispose();
    });
  });

  testWidgets('switching Pages off mid-session lands on the five-tab dock '
      'without travel', (tester) async {
    final key = GlobalKey<_DockHarnessState>();
    final semantics = await _pumpDock(
      tester,
      width: 390,
      initialSelected: _momentsTab,
      harnessKey: key,
      reduceMotion: true,
    );
    _expectBeadAt(tester, 4);
    expect(_target(5), findsOneWidget);
    key.currentState!.setContentEnabled(false);
    await tester.pump();
    expect(_target(5), findsNothing);
    expect(tester.getSize(_dock).height, YoFloatingNavigationDock.visualHeight);
    _expectBeadAt(tester, 3);
    key.currentState!.setContentEnabled(true);
    await tester.pump();
    await tester.pump();
    _expectBeadAt(tester, 4);
    expect(tester.getSize(_dock).height, closeTo(82.8, .01));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('RTL mirrors six slots and the 99+ badge stays on Chats at 360', (
    tester,
  ) async {
    final semantics = await _pumpDock(
      tester,
      width: 360,
      locale: const Locale('ar'),
      initialSelected: 1,
      unreadConversationCount: 1234,
      reduceMotion: true,
    );
    for (var slot = 0; slot < 5; slot++) {
      expect(
        tester.getCenter(_target(slot)).dx,
        greaterThan(tester.getCenter(_target(slot + 1)).dx),
      );
    }
    final badge = tester.getRect(
      find.byKey(const ValueKey('yo-chats-unread-badge')),
    );
    final icon = tester.getRect(
      find.descendant(of: _target(2), matching: find.byType(Icon)),
    );
    expect(find.text('99+'), findsOneWidget);
    expect(badge.width, closeTo(31 * .9, .01));
    expect(badge.overlaps(icon), isFalse);
    expect(badge.center.dx, lessThan(icon.center.dx));
    _expectBeadAt(tester, 2);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('inactive Chats badge stays inside its slot next to the '
      'Treści bead at 320', (tester) async {
    final semantics = await _pumpDock(
      tester,
      width: 320,
      initialSelected: _contentTab,
      unreadConversationCount: 1234,
      reduceMotion: true,
    );
    final badge = tester.getRect(
      find.byKey(const ValueKey('yo-chats-unread-badge')),
    );
    final chats = tester.getRect(_target(2));
    expect(badge.left, greaterThanOrEqualTo(chats.left));
    expect(badge.right, lessThanOrEqualTo(chats.right));
    expect(badge.overlaps(tester.getRect(_bead)), isFalse);
    semantics.dispose();
  });

  testWidgets('keyboard visits six destinations in logical order', (
    tester,
  ) async {
    final requests = <int>[];
    final semantics = await _pumpDock(
      tester,
      onRequested: requests.add,
      reduceMotion: true,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    for (var slot = 0; slot < 5; slot++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(find.byKey(ValueKey('yo-destination-focus-$slot')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(_selected(tester, _labels[slot]), isTrue);
    }
    expect(requests, [0, _serversTab, 1, _contentTab, _momentsTab]);
    semantics.dispose();
  });

  testWidgets('tour anchors attach to Chats, Moments and More at 2, 4, 5', (
    tester,
  ) async {
    final keys = {2: GlobalKey(), 4: GlobalKey(), 5: GlobalKey()};
    final semantics = await _pumpDock(
      tester,
      tourDestinationKeys: keys,
      reduceMotion: true,
    );
    for (final entry in keys.entries) {
      final anchor = entry.value.currentContext!.findRenderObject()!
          as RenderBox;
      final rect = anchor.localToGlobal(Offset.zero) & anchor.size;
      expect(rect.center.dx, closeTo(tester.getCenter(_target(entry.key)).dx, .6));
    }
    semantics.dispose();
  });

  group('43-locale sweep (spec §4.1.2, §6.3)', () {
    setUpAll(() async {
      final inter = FontLoader('Inter')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('assets/fonts/InterVariable.ttf').readAsBytesSync(),
            ),
          ),
        );
      await inter.load();
    });

    for (final width in [320.0, 340.0, 360.0, 390.0]) {
      testWidgets('no locale flips to expanded at 1.0x, $width px', (
        tester,
      ) async {
        final flipped = <String>[];
        for (final locale in AppLocalizations.supportedLocales) {
          final semantics = await _pumpDock(
            tester,
            width: width,
            locale: locale,
            reduceMotion: true,
          );
          if (_caption.evaluate().isNotEmpty) flipped.add(locale.toString());
          semantics.dispose();
        }
        // Non-Latin scripts the test fonts do not carry measure as square
        // fallback glyphs, which is wider than their real faces; Latin,
        // Cyrillic, Greek and Vietnamese measure with the shipped Inter.
        expect(
          flipped,
          isEmpty,
          reason: 'locales that flip at $width px: $flipped',
        );
      });
    }
  });
}
