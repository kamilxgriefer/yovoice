import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_preserving_tab_transition.dart';

const _momentsTab = 5;

bool _selected(WidgetTester tester, String label) {
  return tester
      .widgetList<Semantics>(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == label,
        ),
      )
      .any((widget) => widget.properties.selected == true);
}

int _actionableButtonCount(SemanticsNode root) {
  var count = 0;
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.hasAction(SemanticsAction.tap) && data.flagsCollection.isButton) {
      count += 1;
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
  ThemeData? theme,
  Map<int, GlobalKey>? tourDestinationKeys,
  GlobalKey? tourVoiceKey,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final semantics = tester.ensureSemantics();

  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          padding: EdgeInsets.only(bottom: safeBottom),
          viewPadding: EdgeInsets.only(bottom: safeBottom),
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: _DockHarness(
          tourDestinationKeys: tourDestinationKeys,
          tourVoiceKey: tourVoiceKey,
        ),
      ),
    ),
  );
  await tester.pump();
  return semantics;
}

class _DockHarness extends StatefulWidget {
  const _DockHarness({this.tourDestinationKeys, this.tourVoiceKey});

  final Map<int, GlobalKey>? tourDestinationKeys;
  final GlobalKey? tourVoiceKey;

  @override
  State<_DockHarness> createState() => _DockHarnessState();
}

class _DockHarnessState extends State<_DockHarness> {
  int selected = 0;
  int voiceActions = 0;
  bool moreSelected = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Selected $selected'),
            Text('Voice $voiceActions'),
            TextButton(
              onPressed: () => setState(() => moreSelected = false),
              child: const Text('Close More'),
            ),
          ],
        ),
      ),
      bottomNavigationBar: YoFloatingNavigationDock(
        tourDestinationKeys: widget.tourDestinationKeys,
        tourVoiceKey: widget.tourVoiceKey,
        selectedTabIndex: selected,
        momentsTabIndex: _momentsTab,
        unreadConversationCount: 3,
        moreSelected: moreSelected,
        onDestinationSelected: (index) {
          setState(() {
            selected = index;
            moreSelected = false;
          });
        },
        onVoicePressed: () => setState(() => voiceActions += 1),
        onMorePressed: () => setState(() => moreSelected = true),
      ),
    );
  }
}

void main() {
  testWidgets(
    'guided-tour anchors follow Chats 1, Moments 3, More 4 and central YO',
    (tester) async {
      for (final textScale in [1.0, 2.0]) {
        final destinationKeys = <int, GlobalKey>{
          1: GlobalKey(debugLabel: 'tour-chats-$textScale'),
          3: GlobalKey(debugLabel: 'tour-moments-$textScale'),
          4: GlobalKey(debugLabel: 'tour-more-$textScale'),
        };
        final voiceKey = GlobalKey(debugLabel: 'tour-voice-$textScale');
        final semantics = await _pumpDock(
          tester,
          width: textScale == 2 ? 320 : 390,
          height: 700,
          textScale: textScale,
          reduceMotion: true,
          tourDestinationKeys: destinationKeys,
          tourVoiceKey: voiceKey,
        );

        for (final slot in [1, 3, 4]) {
          final anchorRect = tester.getRect(find.byKey(destinationKeys[slot]!));
          final productionControlRect = tester.getRect(
            find.byKey(ValueKey('yo-destination-$slot')),
          );
          expect(anchorRect.left, closeTo(productionControlRect.left, .01));
          expect(anchorRect.top, closeTo(productionControlRect.top, .01));
          expect(anchorRect.right, closeTo(productionControlRect.right, .01));
          expect(anchorRect.bottom, closeTo(productionControlRect.bottom, .01));
        }

        final voiceAnchorRect = tester.getRect(find.byKey(voiceKey));
        final productionVoiceRect = tester.getRect(
          find.byKey(const ValueKey('yo-center-action-boundary')),
        );
        expect(voiceAnchorRect.left, closeTo(productionVoiceRect.left, .01));
        expect(voiceAnchorRect.top, closeTo(productionVoiceRect.top, .01));
        expect(voiceAnchorRect.right, closeTo(productionVoiceRect.right, .01));
        expect(
          voiceAnchorRect.bottom,
          closeTo(productionVoiceRect.bottom, .01),
        );
        expect(tester.takeException(), isNull);
        semantics.dispose();
      }
    },
  );

  testWidgets('dock chrome and active capsule follow both semantic themes', (
    tester,
  ) async {
    for (final (theme, palette) in [
      (AppTheme.lightTheme, AppPalette.light),
      (AppTheme.darkTheme, AppPalette.dark),
    ]) {
      final semantics = await _pumpDock(
        tester,
        reduceMotion: true,
        theme: theme,
      );
      await tester.pumpAndSettle();

      final dock = tester.widget<Container>(
        find.byKey(const ValueKey('yo-floating-navigation-dock')),
      );
      final dockDecoration = dock.decoration! as ShapeDecoration;
      expect(
        dockDecoration.color,
        palette.navigationSurface.withValues(alpha: .97),
      );
      expect(dockDecoration.shape.dimensions, const EdgeInsets.all(1));

      final clip = tester.widget<ClipPath>(
        find.byKey(const ValueKey('yo-dock-notch-clip')),
      );
      final dockSize = tester.getSize(
        find.byKey(const ValueKey('yo-floating-navigation-dock')),
      );
      final path = clip.clipper!.getClip(dockSize);
      expect(path.contains(Offset(dockSize.width / 2, 2)), isFalse);
      expect(path.contains(const Offset(20, 20)), isTrue);
      expect(
        path.contains(
          Offset(
            dockSize.width / 2,
            YoFloatingNavigationDock.notchCenterFromTop + 46,
          ),
        ),
        isTrue,
      );

      final active = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('yo-active-capsule-reduced-motion')),
      );
      final activeDecoration = active.decoration! as BoxDecoration;
      expect(
        (activeDecoration.gradient! as LinearGradient).colors.last,
        palette.surfaceRaised,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    }
  });

  testWidgets(
    'Home starts selected; Chats, Moments and More move one shared capsule',
    (tester) async {
      final haptics = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final semantics = await _pumpDock(tester, reduceMotion: true);

      expect(_selected(tester, 'Home'), isTrue);
      expect(_selected(tester, 'Chats, 3 unread conversations'), isFalse);
      expect(_selected(tester, 'Moments'), isFalse);
      expect(_selected(tester, 'More'), isFalse);
      expect(
        find.byKey(const ValueKey('yo-active-capsule-position')),
        findsOneWidget,
      );

      // Re-selecting Home is functional but not a selection change, so it
      // must not produce a second haptic event.
      await tester.tap(find.byKey(const ValueKey('yo-destination-0')));
      await tester.pump();
      expect(haptics, isEmpty);

      await tester.tap(find.byKey(const ValueKey('yo-destination-1')));
      await tester.pump();
      expect(find.text('Selected 1'), findsOneWidget);
      expect(_selected(tester, 'Chats, 3 unread conversations'), isTrue);

      await tester.tap(find.byKey(const ValueKey('yo-destination-3')));
      await tester.pump();
      expect(find.text('Selected 5'), findsOneWidget);
      expect(_selected(tester, 'Moments'), isTrue);

      await tester.tap(find.byKey(const ValueKey('yo-destination-4')));
      await tester.pump();
      expect(_selected(tester, 'More'), isTrue);
      expect(_selected(tester, 'Moments'), isFalse);
      expect(haptics, hasLength(3));
      expect(
        haptics.map((call) => call.arguments),
        everyElement('HapticFeedbackType.selectionClick'),
      );

      await tester.tap(find.text('Close More'));
      await tester.pump();
      expect(_selected(tester, 'Moments'), isTrue);
      expect(_selected(tester, 'More'), isFalse);
      semantics.dispose();
    },
  );

  testWidgets('the central YO action fires once without changing the tab', (
    tester,
  ) async {
    final semantics = await _pumpDock(tester, reduceMotion: true);
    await tester.tap(find.bySemanticsLabel('Open voice actions'));
    await tester.pump();

    expect(find.text('Voice 1'), findsOneWidget);
    expect(find.text('Selected 0'), findsOneWidget);
    expect(_selected(tester, 'Home'), isTrue);
    expect(find.byKey(const ValueKey('dock-logo')), findsOneWidget);
    expect(find.byKey(const ValueKey('yo-center-ripple')), findsNothing);
    semantics.dispose();
  });

  testWidgets('all five controls expose an actionable semantics tap', (
    tester,
  ) async {
    final semantics = await _pumpDock(tester, reduceMotion: true);

    for (final label in [
      'Home',
      'Chats, 3 unread conversations',
      'Open voice actions',
      'Moments',
      'More',
    ]) {
      final node = tester.getSemantics(find.bySemanticsLabel(label));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason: '$label must remain activatable by a screen reader',
      );
    }
    final dockSemantics = tester.getSemantics(
      find.byKey(const ValueKey('yo-floating-navigation-semantics')),
    );
    expect(_actionableButtonCount(dockSemantics), 5);
    semantics.dispose();
  });

  testWidgets(
    'keyboard focus follows Home, Chats, YO, Moments, More with a visible YO ring',
    (tester) async {
      final semantics = await _pumpDock(tester, reduceMotion: true);
      final home = tester.widget<InkWell>(
        find.byKey(const ValueKey('yo-destination-0')),
      );
      home.focusNode!.requestFocus();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'YO dock 0');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'YO dock 1');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'YO dock 2');
      final outline = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('yo-center-focus-outline')),
      );
      final outlineDecoration = outline.decoration! as BoxDecoration;
      expect(outlineDecoration.border!.top.color, AppPalette.dark.focus);
      expect(outlineDecoration.border!.top.width, 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('Voice 1'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(find.text('Voice 2'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'YO dock 3');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'YO dock 4');
      semantics.dispose();
    },
  );

  testWidgets('the exposed top and side edges of the YO circle are tappable', (
    tester,
  ) async {
    final semantics = await _pumpDock(tester, reduceMotion: true);
    final button = tester.getRect(
      find.byKey(const ValueKey('yo-center-action-boundary')),
    );
    final dock = tester.getRect(
      find.byKey(const ValueKey('yo-floating-navigation-dock')),
    );
    expect(button.top, lessThan(dock.top));
    expect(button.center.dx, closeTo(dock.center.dx, .01));

    final cradle = tester.getRect(
      find.byKey(const ValueKey('yo-center-cradle')),
    );
    expect(cradle.center, button.center);
    expect(cradle.width, button.width + YoFloatingNavigationDock.notchGap * 2);
    expect(
      tester
          .widget<IgnorePointer>(find.byKey(const ValueKey('yo-center-cradle')))
          .ignoring,
      isTrue,
    );

    await tester.tapAt(Offset(button.center.dx, button.top + 2));
    await tester.pump();
    expect(find.text('Voice 1'), findsOneWidget);
    await tester.tapAt(Offset(button.left + 2, button.center.dy));
    await tester.pump();
    expect(find.text('Voice 2'), findsOneWidget);
    await tester.tapAt(Offset(button.right - 2, button.center.dy));
    await tester.pump();

    expect(find.text('Voice 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('one ripple is reused across rapid central action taps', (
    tester,
  ) async {
    final semantics = await _pumpDock(tester);
    final action = find.bySemanticsLabel('Open voice actions');
    await tester.tap(action);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(action);
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.text('Voice 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('yo-center-ripple')), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('320px, 200% text and a home indicator work in both themes', (
    tester,
  ) async {
    for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
      final semantics = await _pumpDock(
        tester,
        width: 320,
        height: 700,
        safeBottom: 34,
        textScale: 2,
        reduceMotion: true,
        theme: theme,
      );

      final dock = tester.getRect(
        find.byKey(const ValueKey('yo-floating-navigation-dock')),
      );
      final capsule = tester.getRect(
        find.byKey(const ValueKey('yo-active-capsule-position')),
      );
      final button = tester.getRect(
        find.byKey(const ValueKey('yo-center-action-boundary')),
      );
      expect(dock.left, greaterThanOrEqualTo(14));
      expect(dock.right, lessThanOrEqualTo(306));
      expect(dock.height, YoFloatingNavigationDock.accessibleVisualHeight);
      expect(capsule.width, 132);
      expect(button.width, 64);
      for (final slot in [0, 1, 3, 4]) {
        final target = tester.getSize(
          find.byKey(ValueKey('yo-destination-$slot')),
        );
        expect(target.width, greaterThanOrEqualTo(44));
        expect(target.height, greaterThanOrEqualTo(44));
      }
      for (final label in ['Home', 'Chats', 'Moments', 'More']) {
        final text = tester.widget<Text>(find.text(label));
        expect(text.maxLines, 1);
        expect(text.overflow, TextOverflow.visible);
      }
      expect(tester.takeException(), isNull);
      semantics.dispose();
    }
    expect(YoFloatingNavigationDock.reservedHeightFor(safeBottom: 34), 132);
    expect(
      YoFloatingNavigationDock.reservedHeightFor(safeBottom: 34, textScale: 2),
      158,
    );
  });

  testWidgets(
    'the dock is bounded on a tablet and survives a raised keyboard',
    (tester) async {
      final semantics = await _pumpDock(
        tester,
        width: 768,
        height: 700,
        keyboardInset: 300,
        textScale: 1.3,
        reduceMotion: true,
      );

      final dock = tester.getRect(
        find.byKey(const ValueKey('yo-floating-navigation-dock')),
      );
      expect(dock.width, 460);
      expect(dock.bottom, 690);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('rapid destination taps retarget safely and the last tap wins', (
    tester,
  ) async {
    final semantics = await _pumpDock(tester);
    await tester.tap(find.byKey(const ValueKey('yo-destination-1')));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.tap(find.byKey(const ValueKey('yo-destination-3')));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.tap(find.byKey(const ValueKey('yo-destination-0')));
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Selected 0'), findsOneWidget);
    expect(_selected(tester, 'Home'), isTrue);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('active breathing and ripple dispose without lifecycle errors', (
    tester,
  ) async {
    final semantics = await _pumpDock(tester);
    await tester.tap(find.bySemanticsLabel('Open voice actions'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('reduced motion removes breathing, ripple and capsule travel', (
    tester,
  ) async {
    final semantics = await _pumpDock(tester, reduceMotion: true);
    await tester.tap(find.byKey(const ValueKey('yo-destination-1')));
    await tester.pump();

    final capsule = tester.getRect(
      find.byKey(const ValueKey('yo-active-capsule-position')),
    );
    final chats = tester.getRect(
      find.byKey(const ValueKey('yo-destination-1')),
    );
    expect((capsule.center.dx - chats.center.dx).abs(), lessThan(1));
    expect(
      find.byKey(const ValueKey('yo-active-breathing-animation')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('yo-center-ripple')), findsNothing);
    semantics.dispose();
  });

  testWidgets(
    'the Scaffold reserves the dock so the final row stays above it',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              padding: EdgeInsets.only(bottom: 24),
              viewPadding: EdgeInsets.only(bottom: 24),
              disableAnimations: true,
            ),
            child: MoreDestinationHost(
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
        ),
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Final row 49'),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      final finalRow = tester.getRect(find.text('Final row 49'));
      final dock = tester.getRect(
        find.byKey(const ValueKey('yo-floating-navigation-dock')),
      );
      expect(finalRow.bottom, lessThanOrEqualTo(dock.top));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tab fade-through preserves child state and moves horizontally', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: _TransitionHarness()));

    await tester.tap(find.text('Increment page zero'));
    await tester.pump();
    expect(find.text('Page zero count 1'), findsOneWidget);

    await tester.tap(find.text('Show one'));
    await tester.pump();
    final enteringRight = tester.widget<Transform>(
      find.byKey(const ValueKey('yo-tab-translation-1')),
    );
    expect(enteringRight.transform.getTranslation().x, closeTo(12, .01));
    expect(enteringRight.transform.getTranslation().y, 0);
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text('Show zero'));
    await tester.pump();
    final enteringLeft = tester.widget<Transform>(
      find.byKey(const ValueKey('yo-tab-translation-0')),
    );
    expect(enteringLeft.transform.getTranslation().x, closeTo(-12, .01));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Page zero count 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
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
  int _selected = 0;
  int _previous = 0;
  int _direction = 1;

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
  Widget build(BuildContext context) {
    return Scaffold(
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
}

class _StatefulPageZero extends StatefulWidget {
  const _StatefulPageZero();

  @override
  State<_StatefulPageZero> createState() => _StatefulPageZeroState();
}

class _StatefulPageZeroState extends State<_StatefulPageZero> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Page zero count $_count'),
          TextButton(
            onPressed: () => setState(() => _count += 1),
            child: const Text('Increment page zero'),
          ),
        ],
      ),
    );
  }
}
