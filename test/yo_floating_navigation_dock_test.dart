import 'dart:ui' show PointerDeviceKind, SemanticsAction;

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderBox, RenderParagraph, SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_preserving_tab_transition.dart';

const _labels = ['Home', 'Rooms', 'Chats', 'Your Moments', 'More'];
Finder _target(int slot) => find.byKey(ValueKey('yo-destination-$slot'));
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
  double safeBottom = 0,
  double textScale = 1,
  double keyboardInset = 0,
  bool reduceMotion = false,
  ValueListenable<bool>? reduceMotionListenable,
  ThemeData? theme,
  Locale locale = const Locale('en'),
  int initialSelected = 0,
  int unreadConversationCount = 0,
  bool autoAccept = true,
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
          data: MediaQueryData(
            size: Size(width, height),
            padding: EdgeInsets.only(bottom: safeBottom),
            viewPadding: EdgeInsets.only(bottom: safeBottom),
            viewInsets: EdgeInsets.only(bottom: keyboardInset),
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disabled,
          ),
          child: child!,
        ),
        child: _DockHarness(
          key: harnessKey,
          initialSelected: initialSelected,
          unreadConversationCount: unreadConversationCount,
          autoAccept: autoAccept,
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
    required this.autoAccept,
    this.onRequested,
    this.tourDestinationKeys,
    super.key,
  });
  final int initialSelected, unreadConversationCount;
  final bool autoAccept;
  final ValueChanged<int>? onRequested;
  final Map<int, GlobalKey>? tourDestinationKeys;
  @override
  State<_DockHarness> createState() => _DockHarnessState();
}

class _DockHarnessState extends State<_DockHarness> {
  late int selected;
  int voiceActions = 0, moreActions = 0;
  bool moreSelected = false;
  @override
  void initState() {
    super.initState();
    selected = widget.initialSelected;
  }

  void acceptDestination(int index) => setState(() {
    selected = index;
    moreSelected = false;
  });
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
      momentsTabIndex: 5,
      unreadConversationCount: widget.unreadConversationCount,
      moreSelected: moreSelected,
      onDestinationSelected: (index) {
        widget.onRequested?.call(index);
        if (widget.autoAccept) acceptDestination(index);
      },
      onVoicePressed: () => setState(() => voiceActions++),
      onMorePressed: () => setState(() {
        moreActions++;
        if (widget.autoAccept) moreSelected = true;
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

Future<TestGesture> _startBeadDrag(
  WidgetTester tester, {
  double direction = 1,
}) async {
  final gesture = await tester.startGesture(tester.getCenter(_bead));
  await gesture.moveBy(Offset(20 * direction, 0));
  await tester.pump();
  return gesture;
}

void main() {
  test(
    'visual order maps to stable domain destinations without renumbering',
    () {
      expect(
        [0, 3, 1, 5].map(
          (tab) => YoFloatingNavigationDock.visualSlotForTab(
            tab,
            momentsTabIndex: 5,
          ),
        ),
        [0, 1, 2, 3],
      );
      expect(
        YoFloatingNavigationDock.visualSlotForTab(2, momentsTabIndex: 5),
        isNull,
      );
      expect(
        YoFloatingNavigationDock.visualSlotForTab(
          8,
          momentsTabIndex: 9,
          roomsTabIndex: 8,
        ),
        1,
      );
    },
  );
  for (final width in [320.0, 390.0, 430.0, 768.0]) {
    for (final light in [false, true]) {
      testWidgets(
        'five destinations, 48px targets and bounded dock at $width light=$light',
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
            5,
          );
          var previousX = 0.0;
          for (var slot = 0; slot < 5; slot++) {
            final rect = tester.getRect(_target(slot));
            expect(rect.width, greaterThanOrEqualTo(48));
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(rect.center.dx, greaterThan(previousX));
            previousX = rect.center.dx;
            expect(find.bySemanticsLabel(_labels[slot]), findsOneWidget);
          }
          expect(tester.getSize(_dock).width, lessThanOrEqualTo(460));
          expect(find.text('Home'), findsOneWidget);
          expect(find.text('Rooms'), findsNothing);
          expect(find.byKey(const ValueKey('dock-logo')), findsNothing);
          expect(find.bySemanticsLabel('Open voice actions'), findsNothing);
          _expectBeadAt(tester, 0);
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  }
  testWidgets(
    'all taps route correctly and dismissing More restores selection',
    (tester) async {
      final requests = <int>[];
      final key = GlobalKey<_DockHarnessState>();
      final semantics = await _pumpDock(
        tester,
        reduceMotion: true,
        onRequested: requests.add,
        harnessKey: key,
      );
      for (final slot in [1, 2, 3, 0]) {
        await tester.tap(_target(slot));
        await tester.pump();
        expect(_selected(tester, _labels[slot]), isTrue);
        _expectBeadAt(tester, slot);
      }
      expect(requests, [3, 1, 5, 0]);
      await tester.tap(_target(3));
      await tester.pump();
      await tester.tap(_target(4));
      await tester.pump();
      expect(_selected(tester, 'More'), isTrue);
      _expectBeadAt(tester, 4);
      await tester.tap(find.text('Close More'));
      await tester.pump();
      expect(_selected(tester, 'Your Moments'), isTrue);
      _expectBeadAt(tester, 3);
      expect(key.currentState!.voiceActions, 0);
      expect(key.currentState!.moreActions, 1);
      semantics.dispose();
    },
  );
  testWidgets(
    'accepted change provides one selection haptic but retapping does not',
    (tester) async {
      final calls = <MethodCall>[];
      final requests = <int>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final semantics = await _pumpDock(
        tester,
        reduceMotion: true,
        onRequested: requests.add,
      );
      await tester.tap(_target(0));
      await tester.pump();
      expect(calls, isEmpty);
      expect(requests, [
        0,
      ], reason: 'A same-tab tap still lets hosted routes return home.');
      expect(_selected(tester, 'Home'), isTrue);
      _expectBeadAt(tester, 0);
      await tester.tap(_target(1));
      await tester.pump();
      expect(calls.map((call) => call.arguments), [
        'HapticFeedbackType.selectionClick',
      ]);
      semantics.dispose();
    },
  );
  testWidgets('denied or delayed taps never falsely select requested tab', (
    tester,
  ) async {
    final requests = <int>[];
    final key = GlobalKey<_DockHarnessState>();
    final semantics = await _pumpDock(
      tester,
      autoAccept: false,
      onRequested: requests.add,
      harnessKey: key,
    );
    await tester.tap(_target(2));
    await tester.pumpAndSettle();
    expect(requests, [1]);
    expect(_selected(tester, 'Home'), isTrue);
    _expectBeadAt(tester, 0);
    key.currentState!.acceptDestination(1);
    await tester.pumpAndSettle();
    expect(_selected(tester, 'Chats'), isTrue);
    _expectBeadAt(tester, 2);
    semantics.dispose();
  });
  testWidgets(
    'rapid reversal retargets from live position without teleporting',
    (tester) async {
      final requests = <int>[];
      final semantics = await _pumpDock(tester, onRequested: requests.add);
      final homeX = tester.getCenter(_bead).dx;
      await tester.tap(_target(3));
      await tester.pump();
      // The first tick establishes the simulation clock after post-frame
      // acceptance settlement. Sample actual elapsed animation on the next.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 80));
      final movingX = tester.getCenter(_bead).dx;
      expect(movingX, greaterThan(homeX + 1));
      await tester.tap(_target(1));
      await tester.pump();
      expect(tester.getCenter(_bead).dx, closeTo(movingX, 1));
      await tester.tap(_target(2));
      await tester.pumpAndSettle();
      expect(requests, [5, 3, 1]);
      _expectBeadAt(tester, 2);
      expect(_selected(tester, 'Chats'), isTrue);
      semantics.dispose();
    },
  );
  testWidgets(
    'drag previews paint only; release requests exactly one destination',
    (tester) async {
      final requests = <int>[];
      final semantics = await _pumpDock(tester, onRequested: requests.add);
      final gesture = await _startBeadDrag(tester);
      final y = tester.getCenter(_bead).dy;
      for (final slot in [1, 2, 3]) {
        await gesture.moveTo(Offset(tester.getCenter(_target(slot)).dx, y));
        await tester.pump();
        expect(requests, isEmpty);
        expect(_selected(tester, 'Home'), isTrue);
        _expectBeadAt(tester, slot);
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(requests, [5]);
      expect(_selected(tester, 'Your Moments'), isTrue);
      _expectBeadAt(tester, 3);
      semantics.dispose();
    },
  );
  testWidgets('cancelled drag restores accepted state without navigation', (
    tester,
  ) async {
    final requests = <int>[];
    final semantics = await _pumpDock(tester, onRequested: requests.add);
    final gesture = await _startBeadDrag(tester);
    await gesture.moveTo(
      Offset(tester.getCenter(_target(3)).dx, tester.getCenter(_bead).dy),
    );
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    expect(_selected(tester, 'Home'), isTrue);
    _expectBeadAt(tester, 0);
    semantics.dispose();
  });

  testWidgets('drag ending back on its starting tab is paint-only', (
    tester,
  ) async {
    final requests = <int>[];
    final semantics = await _pumpDock(tester, onRequested: requests.add);
    final gesture = await _startBeadDrag(tester);
    final y = tester.getCenter(_bead).dy;
    await gesture.moveTo(Offset(tester.getCenter(_target(2)).dx, y));
    await tester.pump();
    await gesture.moveTo(Offset(tester.getCenter(_target(0)).dx, y));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(requests, isEmpty, reason: 'A returned drag is not a same-tab tap.');
    expect(_selected(tester, 'Home'), isTrue);
    _expectBeadAt(tester, 0);
    semantics.dispose();
  });
  testWidgets('denied drag snaps back; delayed acceptance later updates once', (
    tester,
  ) async {
    final requests = <int>[];
    final key = GlobalKey<_DockHarnessState>();
    final semantics = await _pumpDock(
      tester,
      autoAccept: false,
      onRequested: requests.add,
      harnessKey: key,
    );
    final gesture = await _startBeadDrag(tester);
    await gesture.moveTo(
      Offset(tester.getCenter(_target(2)).dx, tester.getCenter(_bead).dy),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(requests, [1]);
    expect(_selected(tester, 'Home'), isTrue);
    _expectBeadAt(tester, 0);
    key.currentState!.acceptDestination(1);
    await tester.pumpAndSettle();
    _expectBeadAt(tester, 2);
    expect(requests, [1]);
    semantics.dispose();
  });
  testWidgets('drag bounds clamp at end slots', (tester) async {
    final key = GlobalKey<_DockHarnessState>();
    final semantics = await _pumpDock(
      tester,
      initialSelected: 1,
      harnessKey: key,
    );
    final gesture = await _startBeadDrag(tester);
    final y = tester.getCenter(_bead).dy;
    await gesture.moveTo(Offset(900, y));
    await tester.pump();
    _expectBeadAt(tester, 4);
    await gesture.moveTo(Offset(-500, y));
    await tester.pump();
    _expectBeadAt(tester, 0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(key.currentState!.selected, 0);
    expect(key.currentState!.moreActions, 0);
    semantics.dispose();
  });

  testWidgets('fast first drag movement retains the original bead hit target', (
    tester,
  ) async {
    final requests = <int>[];
    final semantics = await _pumpDock(tester, onRequested: requests.add);
    final origin = tester.getCenter(_bead);
    final gesture = await tester.startGesture(origin);
    await gesture.moveTo(Offset(tester.getCenter(_target(2)).dx, origin.dy));
    await tester.pump();
    await gesture.moveBy(const Offset(1, 0));
    await tester.pump();
    expect(requests, isEmpty);
    expect(
      tester.getCenter(_bead).dx,
      closeTo(tester.getCenter(_target(2)).dx, 2),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(requests, [1]);
    semantics.dispose();
  });
  testWidgets('inactive icon swipe does not initiate bead navigation', (
    tester,
  ) async {
    final requests = <int>[];
    final semantics = await _pumpDock(tester, onRequested: requests.add);
    await tester.drag(_target(3), const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    _expectBeadAt(tester, 0);
    semantics.dispose();
  });

  testWidgets('external route change cancels pending drag preview', (
    tester,
  ) async {
    final requests = <int>[];
    final key = GlobalKey<_DockHarnessState>();
    final semantics = await _pumpDock(
      tester,
      onRequested: requests.add,
      harnessKey: key,
    );
    final gesture = await _startBeadDrag(tester);
    await gesture.moveTo(
      Offset(tester.getCenter(_target(3)).dx, tester.getCenter(_bead).dy),
    );
    await tester.pump();
    key.currentState!.acceptDestination(3);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    expect(_selected(tester, 'Rooms'), isTrue);
    _expectBeadAt(tester, 1);
    semantics.dispose();
  });

  testWidgets('denied More drag restores current tab without voice action', (
    tester,
  ) async {
    final key = GlobalKey<_DockHarnessState>();
    final semantics = await _pumpDock(
      tester,
      autoAccept: false,
      harnessKey: key,
    );
    final gesture = await _startBeadDrag(tester);
    await gesture.moveTo(
      Offset(tester.getCenter(_target(4)).dx, tester.getCenter(_bead).dy),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(key.currentState!.moreActions, 1);
    expect(key.currentState!.voiceActions, 0);
    expect(_selected(tester, 'More'), isFalse);
    _expectBeadAt(tester, 0);
    semantics.dispose();
  });
  testWidgets(
    'socket follows bead as one closed continuous concave bounded path',
    (tester) async {
      final semantics = await _pumpDock(tester, reduceMotion: true);
      for (var slot = 0; slot < 5; slot++) {
        await tester.tap(_target(slot));
        await tester.pump();
        final painter = _painter(tester),
            size = tester.getSize(_dock),
            path = painter.pathFor(size);
        final metrics = path.computeMetrics().toList();
        expect(metrics, hasLength(1));
        expect(metrics.single.isClosed, isTrue);
        expect(path.getBounds().left, greaterThanOrEqualTo(-.001));
        expect(path.getBounds().right, lessThanOrEqualTo(size.width + .001));
        expect(
          path.contains(
            Offset(
              painter.center!,
              YoFloatingNavigationDock.bodyTop + painter.radius - 1,
            ),
          ),
          isFalse,
        );
        expect(
          path.contains(
            Offset(
              painter.center!,
              YoFloatingNavigationDock.bodyTop + painter.radius + 1,
            ),
          ),
          isTrue,
        );
        expect(path.contains(Offset(size.width / 2, size.height - 2)), isTrue);
        _expectBeadAt(tester, slot);
      }
      semantics.dispose();
    },
  );
  for (final count in [0, 1, 99, 100, 1234]) {
    testWidgets('badge $count caps visual count but announces full count', (
      tester,
    ) async {
      final semantics = await _pumpDock(
        tester,
        unreadConversationCount: count,
        reduceMotion: true,
      );
      expect(
        find.byKey(const ValueKey('yo-chats-unread-badge')),
        count == 0 ? findsNothing : findsOneWidget,
      );
      final copy = AppLocalizations.of(tester.element(_dock));
      expect(
        find.bySemanticsLabel(
          count == 0 ? 'Chats' : copy.navigationUnreadLabel('Chats', count),
        ),
        findsOneWidget,
      );
      if (count > 0) {
        expect(find.text(count > 99 ? '99+' : '$count'), findsOneWidget);
      }
      semantics.dispose();
    });
  }
  for (final locale in ['en', 'pl', 'de', 'ru', 'uk', 'ar']) {
    testWidgets(
      'translated caption receives complete 200% text at 320px: $locale',
      (tester) async {
        final semantics = await _pumpDock(
          tester,
          width: 320,
          height: 700,
          textScale: 2,
          locale: Locale(locale),
          reduceMotion: true,
        );
        for (var slot = 0; slot < 5; slot++) {
          await tester.tap(_target(slot));
          await tester.pump();
          final finder = find.byKey(
            const ValueKey('yo-meniscus-accessible-label'),
          );
          final text = tester.widget<Text>(finder),
              paragraph = tester.renderObject<RenderParagraph>(finder),
              context = tester.element(finder);
          final painter = TextPainter(
            text: TextSpan(
              text: text.data,
              style: DefaultTextStyle.of(context).style.merge(text.style),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(maxWidth: paragraph.size.width);
          expect(
            painter.height,
            lessThanOrEqualTo(paragraph.size.height + .01),
          );
          expect(paragraph.textScaler.scale(12), 24);
          expect(
            tester.getRect(finder).bottom,
            lessThanOrEqualTo(tester.getRect(_dock).bottom),
          );
          expect(tester.takeException(), isNull);
          painter.dispose();
        }
        semantics.dispose();
      },
    );
  }

  for (final configuration in [
    ('vi', 1.0),
    ('vi', 1.29),
    ('es', 1.29),
    ('pt', 1.29),
    ('nl', 1.29),
    ('pl', 1.29),
  ]) {
    testWidgets('long caption stays complete below large-text threshold: '
        '${configuration.$1} ${configuration.$2}x at 320px', (tester) async {
      final requests = <int>[];
      final key = GlobalKey<_DockHarnessState>();
      final semantics = await _pumpDock(
        tester,
        width: 320,
        height: 700,
        locale: Locale(configuration.$1),
        textScale: configuration.$2,
        onRequested: requests.add,
        harnessKey: key,
        reduceMotion: true,
      );
      final copy = AppLocalizations.of(tester.element(_dock));
      final expectedLabels = [
        copy.home,
        copy.navigationRooms,
        copy.chats,
        copy.navigationYourMoments,
        copy.more,
      ];
      for (final slot in [1, 2, 3, 4, 0]) {
        await tester.tap(_target(slot));
        await tester.pump();
        final fullWidth = find.byKey(
          const ValueKey('yo-meniscus-accessible-label'),
        );
        final caption = fullWidth.evaluate().isNotEmpty
            ? fullWidth
            : find.byKey(ValueKey('yo-destination-label-$slot'));
        final text = tester.widget<Text>(caption);
        final paragraph = tester.renderObject<RenderParagraph>(caption);
        final context = tester.element(caption);
        final painter = TextPainter(
          text: TextSpan(
            text: text.data,
            style: DefaultTextStyle.of(context).style.merge(text.style),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: text.maxLines,
        )..layout(maxWidth: paragraph.size.width);
        expect(text.data, expectedLabels[slot]);
        expect(painter.didExceedMaxLines, isFalse);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(
          painter.height,
          lessThanOrEqualTo(paragraph.size.height + .01),
          reason: 'The complete scaled caption must fit vertically.',
        );
        expect(
          paragraph.textScaler.scale(10),
          closeTo(configuration.$2 * 10, .001),
          reason: 'Do not shrink user text scaling to hide overflow.',
        );
        final captionRect = tester.getRect(caption);
        final dockRect = tester.getRect(_dock);
        expect(captionRect.left, greaterThanOrEqualTo(dockRect.left));
        expect(captionRect.right, lessThanOrEqualTo(dockRect.right));
        expect(captionRect.bottom, lessThanOrEqualTo(dockRect.bottom));
        expect(_selected(tester, expectedLabels[slot]), isTrue);
        _expectBeadAt(tester, slot);
        expect(tester.takeException(), isNull);
        painter.dispose();
      }
      expect(requests, [3, 1, 5, 0]);
      expect(key.currentState!.moreActions, 1);
      expect(key.currentState!.voiceActions, 0);
      semantics.dispose();
    });
  }

  for (final width in [320.0, 390.0, 430.0]) {
    for (final locale in ['en', 'ar']) {
      testWidgets(
        'active Chats 99+ badge does not cover glyph at $width $locale',
        (tester) async {
          final semantics = await _pumpDock(
            tester,
            width: width,
            locale: Locale(locale),
            initialSelected: 1,
            unreadConversationCount: 1234,
            reduceMotion: true,
          );
          final badge = tester.getRect(
            find.byKey(const ValueKey('yo-chats-unread-badge')),
          );
          final icon = tester.getRect(
            find.descendant(of: _target(2), matching: find.byType(Icon)),
          );
          expect(
            badge.overlaps(icon),
            isFalse,
            reason: 'The unread badge may touch but never obscure Chats.',
          );
          expect(
            locale == 'ar'
                ? badge.center.dx < icon.center.dx
                : badge.center.dx > icon.center.dx,
            isTrue,
            reason: 'Badge placement follows the logical trailing edge.',
          );
          expect(find.text('99+'), findsOneWidget);
          _expectBeadAt(tester, 2);
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  }
  for (final locale in ['en', 'ar']) {
    for (final selected in [3, 5]) {
      testWidgets(
        'inactive Chats badge stays clear of adjacent bead: $locale tab$selected',
        (tester) async {
          final semantics = await _pumpDock(
            tester,
            width: 320,
            locale: Locale(locale),
            initialSelected: selected,
            unreadConversationCount: 1234,
            reduceMotion: true,
          );
          final badge = tester.getRect(
            find.byKey(const ValueKey('yo-chats-unread-badge')),
          );
          final chatsSlot = tester.getRect(_target(2));
          expect(badge.left, greaterThanOrEqualTo(chatsSlot.left));
          expect(badge.right, lessThanOrEqualTo(chatsSlot.right));
          expect(badge.overlaps(tester.getRect(_bead)), isFalse);
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  }

  testWidgets('RTL mirrors visual ordering, drag and socket', (tester) async {
    final requests = <int>[];
    final semantics = await _pumpDock(
      tester,
      locale: const Locale('ar'),
      onRequested: requests.add,
    );
    for (var slot = 0; slot < 4; slot++) {
      expect(
        tester.getCenter(_target(slot)).dx,
        greaterThan(tester.getCenter(_target(slot + 1)).dx),
      );
    }
    final gesture = await _startBeadDrag(tester, direction: -1);
    await gesture.moveTo(
      Offset(tester.getCenter(_target(2)).dx, tester.getCenter(_bead).dy),
    );
    await tester.pump();
    expect(requests, isEmpty);
    _expectBeadAt(tester, 2);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(requests, [1]);
    _expectBeadAt(tester, 2);
    semantics.dispose();
  });

  testWidgets('RTL unread badge sits at the logical trailing edge of Chats', (
    tester,
  ) async {
    final semantics = await _pumpDock(
      tester,
      locale: const Locale('ar'),
      unreadConversationCount: 10,
    );
    final badge = tester.getRect(
      find.byKey(const ValueKey('yo-chats-unread-badge')),
    );
    expect(badge.center.dx, lessThan(tester.getCenter(_target(2)).dx));
    semantics.dispose();
  });
  testWidgets(
    'keyboard visits five destinations in logical order and activates',
    (tester) async {
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
        expect(
          find.byKey(ValueKey('yo-destination-focus-$slot')),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(_selected(tester, _labels[slot]), isTrue);
      }
      expect(requests, [0, 3, 1, 5]);
      semantics.dispose();
    },
  );
  testWidgets('hover never rotates selected More icon', (tester) async {
    final semantics = await _pumpDock(tester);
    await tester.tap(_target(4));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(_target(4)));
    await tester.pump();
    final icon = find
        .descendant(of: _target(4), matching: find.byType(Icon))
        .first;
    final transform = tester
        .renderObject<RenderBox>(icon)
        .getTransformTo(tester.renderObject<RenderBox>(_target(4)));
    expect(transform.storage[1], closeTo(0, .000001));
    expect(transform.storage[4], closeTo(0, .000001));
    expect(find.byType(AnimatedRotation), findsNothing);
    await mouse.removePointer();
    semantics.dispose();
  });
  testWidgets('enabling reduced motion mid-travel settles immediately', (
    tester,
  ) async {
    final disabled = ValueNotifier(false);
    addTearDown(disabled.dispose);
    final semantics = await _pumpDock(tester, reduceMotionListenable: disabled);
    await tester.tap(_target(3));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 70));
    expect(
      tester.getCenter(_bead).dx,
      greaterThan(tester.getCenter(_target(0)).dx),
    );
    expect(
      tester.getCenter(_bead).dx,
      lessThan(tester.getCenter(_target(3)).dx),
    );
    disabled.value = true;
    await tester.pump();
    _expectBeadAt(tester, 3);
    expect(_painter(tester).velocity, 0);
    await tester.tap(_target(2));
    await tester.pump();
    _expectBeadAt(tester, 2);
    await tester.pump(const Duration(seconds: 2));
    _expectBeadAt(tester, 2);
    semantics.dispose();
  });
  testWidgets('hidden Friends tab has no false selection; resizing is safe', (
    tester,
  ) async {
    final key = GlobalKey<_DockHarnessState>();
    final semantics = await _pumpDock(
      tester,
      initialSelected: 2,
      harnessKey: key,
    );
    expect(_bead, findsNothing);
    for (final label in _labels) {
      expect(_selected(tester, label), isFalse);
    }
    tester.view.physicalSize = const Size(320, 700);
    await tester.pump();
    key.currentState!.acceptDestination(3);
    await tester.pumpAndSettle();
    _expectBeadAt(tester, 1);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
    'reduced motion enabled during drag cancels preview without navigating',
    (tester) async {
      final disabled = ValueNotifier(false);
      addTearDown(disabled.dispose);
      final requests = <int>[];
      final semantics = await _pumpDock(
        tester,
        reduceMotionListenable: disabled,
        onRequested: requests.add,
      );
      final gesture = await _startBeadDrag(tester);
      await gesture.moveTo(
        Offset(tester.getCenter(_target(3)).dx, tester.getCenter(_bead).dy),
      );
      await tester.pump();
      disabled.value = true;
      await tester.pump();
      _expectBeadAt(tester, 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      semantics.dispose();
    },
  );
  testWidgets('onboarding anchors remain attached to five actual targets', (
    tester,
  ) async {
    final keys = {for (var slot = 0; slot < 5; slot++) slot: GlobalKey()};
    final semantics = await _pumpDock(tester, tourDestinationKeys: keys);
    for (var slot = 0; slot < 5; slot++) {
      expect(
        tester.getRect(find.byKey(keys[slot]!)),
        tester.getRect(_target(slot)),
      );
    }
    semantics.dispose();
  });
  testWidgets(
    'tablet width and safe area remain bounded with raised keyboard',
    (tester) async {
      final semantics = await _pumpDock(
        tester,
        width: 768,
        height: 700,
        safeBottom: 24,
        keyboardInset: 300,
        reduceMotion: true,
      );
      expect(tester.getRect(_dock).bottom, 676);
      expect(tester.getSize(_dock).width, 460);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
  testWidgets('disposing during spring does not leak callbacks or tickers', (
    tester,
  ) async {
    final semantics = await _pumpDock(tester);
    await tester.tap(_target(3));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
  testWidgets('host reserves dock height and final row stays reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: MoreDestinationHost(
          body: ListView.builder(
            itemExtent: 52,
            itemCount: 50,
            itemBuilder: (_, index) => Text('Final row $index'),
          ),
          selectedIndex: 0,
          unreadConversationCount: 0,
          onDestinationSelected: (_) {},
          onVoicePressed: () {},
          onMorePressed: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Final row 49'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(
      tester.getRect(find.text('Final row 49')).bottom,
      lessThanOrEqualTo(tester.getRect(_dock).top),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'tab fade-through preserves page state and never offsets or ghosts pages',
    (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: _TransitionHarness()));
      await tester.tap(find.text('Increment page zero'));
      await tester.pump();
      expect(find.text('Page zero count 1'), findsOneWidget);
      await tester.tap(find.text('Show one'));
      await tester.pump();
      // The incoming page starts fully transparent and slightly scaled
      // down, with NO horizontal offset — an offset left a strip of the
      // outgoing tab visible along one edge ("torn screen").
      final incoming = tester.widget<Transform>(
        find.byKey(const ValueKey('yo-tab-translation-1')),
      );
      expect(incoming.transform.getTranslation().x, 0);
      expect(incoming.transform.getTranslation().y, 0);
      expect(incoming.transform.entry(0, 0), closeTo(.96, .001));
      expect(
        tester
            .widget<Opacity>(find.byKey(const ValueKey('yo-tab-opacity-1')))
            .opacity,
        0,
      );
      // Half-way through, the outgoing page is already fully transparent —
      // the two pages are never both translucent over each other.
      await tester.pump(const Duration(milliseconds: 125));
      expect(
        tester
            .widget<Opacity>(find.byKey(const ValueKey('yo-tab-opacity-0')))
            .opacity,
        0,
      );
      await tester.pump(const Duration(milliseconds: 125));
      final settled = tester.widget<Transform>(
        find.byKey(const ValueKey('yo-tab-translation-1')),
      );
      expect(settled.transform.entry(0, 0), closeTo(1, .001));
      expect(
        tester
            .widget<Opacity>(find.byKey(const ValueKey('yo-tab-opacity-1')))
            .opacity,
        1,
      );
      await tester.tap(find.text('Show zero'));
      await tester.pump();
      expect(
        tester
            .widget<Transform>(
              find.byKey(const ValueKey('yo-tab-translation-0')),
            )
            .transform
            .getTranslation()
            .x,
        0,
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Page zero count 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _TransitionHarness extends StatefulWidget {
  const _TransitionHarness();
  @override
  State<_TransitionHarness> createState() => _TransitionHarnessState();
}

class _TransitionHarnessState extends State<_TransitionHarness>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
    value: 1,
  );
  int _selected = 0, _previous = 0, _direction = 1;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _show(int index) {
    if (_selected == index) return;
    setState(() {
      _previous = _selected;
      _direction = index > _selected ? 1 : -1;
      _selected = index;
    });
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Row(
          children: [
            TextButton(
              onPressed: () => _show(0),
              child: const Text('Show zero'),
            ),
            TextButton(
              onPressed: () => _show(1),
              child: const Text('Show one'),
            ),
          ],
        ),
        Expanded(
          child: YoPreservingTabTransition(
            selectedIndex: _selected,
            previousIndex: _previous,
            direction: _direction,
            animation: _controller,
            children: const [
              _StatefulPageZero(),
              Center(child: Text('Page one')),
            ],
          ),
        ),
      ],
    ),
  );
}

class _StatefulPageZero extends StatefulWidget {
  const _StatefulPageZero();
  @override
  State<_StatefulPageZero> createState() => _StatefulPageZeroState();
}

class _StatefulPageZeroState extends State<_StatefulPageZero> {
  int _count = 0;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Page zero count $_count'),
        TextButton(
          onPressed: () => setState(() => _count++),
          child: const Text('Increment page zero'),
        ),
      ],
    ),
  );
}
