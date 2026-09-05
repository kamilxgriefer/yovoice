import 'dart:math' as math;
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
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_preserving_tab_transition.dart';

const _momentsTab = 5;

double _contrastRatio(Color first, Color second) {
  final lighter = first.computeLuminance() > second.computeLuminance()
      ? first.computeLuminance()
      : second.computeLuminance();
  final darker = first.computeLuminance() > second.computeLuminance()
      ? second.computeLuminance()
      : first.computeLuminance();
  return (lighter + .05) / (darker + .05);
}

bool _selected(WidgetTester tester, String label) {
  return tester
      .widgetList<Semantics>(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == label,
        ),
      )
      .any((widget) => widget.properties.selected == true);
}

void _expectFullyScaledText(WidgetTester tester, Finder finder) {
  final text = tester.widget<Text>(finder);
  final context = tester.element(finder);
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final effectiveStyle = DefaultTextStyle.of(context).style.merge(text.style);
  final painter = TextPainter(
    text: TextSpan(text: text.data, style: effectiveStyle),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: text.maxLines,
  )..layout(maxWidth: paragraph.size.width);

  expect(
    painter.didExceedMaxLines,
    isFalse,
    reason: '${text.data} was clipped',
  );
  expect(
    painter.height,
    lessThanOrEqualTo(paragraph.size.height + .01),
    reason: '${text.data} did not receive its full scaled line height',
  );
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
  ValueListenable<bool>? reduceMotionListenable,
  ThemeData? theme,
  Locale locale = const Locale('en'),
  int initialSelected = 0,
  int unreadConversationCount = 3,
  bool autoAccept = true,
  ValueChanged<int>? onRequested,
  GlobalKey<_DockHarnessState>? harnessKey,
  Map<int, GlobalKey>? tourDestinationKeys,
  GlobalKey? tourVoiceKey,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final semantics = tester.ensureSemantics();
  final ownedReduceMotion = reduceMotionListenable == null
      ? ValueNotifier<bool>(reduceMotion)
      : null;
  final effectiveReduceMotion = reduceMotionListenable ?? ownedReduceMotion!;
  if (ownedReduceMotion != null) addTearDown(ownedReduceMotion.dispose);

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
        valueListenable: effectiveReduceMotion,
        builder: (context, animationsDisabled, child) => MediaQuery(
          data: MediaQueryData(
            size: Size(width, height),
            padding: EdgeInsets.only(bottom: safeBottom),
            viewPadding: EdgeInsets.only(bottom: safeBottom),
            viewInsets: EdgeInsets.only(bottom: keyboardInset),
            textScaler: TextScaler.linear(textScale),
            disableAnimations: animationsDisabled,
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
          tourVoiceKey: tourVoiceKey,
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
    this.tourVoiceKey,
    super.key,
  });

  final int initialSelected;
  final int unreadConversationCount;
  final bool autoAccept;
  final ValueChanged<int>? onRequested;
  final Map<int, GlobalKey>? tourDestinationKeys;
  final GlobalKey? tourVoiceKey;

  @override
  State<_DockHarness> createState() => _DockHarnessState();
}

class _DockHarnessState extends State<_DockHarness> {
  late int selected;
  int voiceActions = 0;
  bool moreSelected = false;

  @override
  void initState() {
    super.initState();
    selected = widget.initialSelected;
  }

  void acceptDestination(int index) {
    setState(() {
      selected = index;
      moreSelected = false;
    });
  }

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
        unreadConversationCount: widget.unreadConversationCount,
        moreSelected: moreSelected,
        onDestinationSelected: (index) {
          widget.onRequested?.call(index);
          if (widget.autoAccept) acceptDestination(index);
        },
        onVoicePressed: () => setState(() => voiceActions += 1),
        onMorePressed: () => setState(() => moreSelected = true),
      ),
    );
  }
}

void main() {
  testWidgets(
    'compact dock is icon-only while semantics and 48px targets remain',
    (tester) async {
      for (final width in [320.0, 390.0, 430.0]) {
        for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
          final semantics = await _pumpDock(
            tester,
            width: width,
            height: 700,
            theme: theme,
            reduceMotion: true,
          );
          for (final label in ['Home', 'Chats', 'YO Moments', 'More']) {
            expect(find.text(label), findsNothing);
          }
          for (final slot in [0, 1, 3, 4]) {
            final target = tester.getSize(
              find.byKey(ValueKey('yo-destination-$slot')),
            );
            expect(target.width, greaterThanOrEqualTo(48));
            expect(target.height, greaterThanOrEqualTo(48));
          }
          expect(find.bySemanticsLabel('Home'), findsOneWidget);
          expect(
            find.bySemanticsLabel('Chats, 3 unread conversations'),
            findsOneWidget,
          );
          expect(find.bySemanticsLabel('YO Moments'), findsOneWidget);
          expect(find.bySemanticsLabel('More'), findsOneWidget);
          expect(tester.takeException(), isNull);
          semantics.dispose();
        }
      }
    },
  );

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
          find.byKey(const ValueKey('yo-center-action-hit-target')),
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

      final dock = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('yo-floating-navigation-dock')),
      );
      final dockDecoration = dock.decoration as ShapeDecoration;
      expect(dockDecoration.gradient, isA<LinearGradient>());
      expect(dockDecoration.color, isNull);
      expect(dockDecoration.shape.dimensions.horizontal, closeTo(2.3, .01));
      expect(
        YoFloatingNavigationDock.outlineSideFor(palette).color,
        palette.navigationOutline,
      );

      final clip = tester.widget<ClipPath>(
        find.byKey(const ValueKey('yo-dock-sculpted-clip')),
      );
      final dockSize = tester.getSize(
        find.byKey(const ValueKey('yo-floating-navigation-dock')),
      );
      final path = clip.clipper!.getClip(dockSize);
      expect(
        path.contains(Offset(dockSize.width / 2, 2)),
        isTrue,
        reason: 'the centre rise belongs to the one continuous shell path',
      );
      expect(
        path.contains(const Offset(20, 2)),
        isFalse,
        reason: 'the side body begins below the central rise',
      );
      expect(
        path.contains(Offset(dockSize.width / 2, dockSize.height - 4)),
        isTrue,
      );
      expect(find.byKey(const ValueKey('yo-center-cradle')), findsNothing);

      final active = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('yo-active-capsule-reduced-motion')),
      );
      final activeDecoration = active.decoration as BoxDecoration;
      expect(activeDecoration.gradient, isA<LinearGradient>());
      expect(activeDecoration.borderRadius, BorderRadius.circular(18));
      expect(
        tester.getSize(
          find.byKey(const ValueKey('yo-active-capsule-position')),
        ),
        const Size.square(52),
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
      expect(_selected(tester, 'YO Moments'), isFalse);
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
      expect(_selected(tester, 'YO Moments'), isTrue);

      await tester.tap(find.byKey(const ValueKey('yo-destination-4')));
      await tester.pump();
      expect(_selected(tester, 'More'), isTrue);
      expect(_selected(tester, 'YO Moments'), isFalse);
      expect(haptics, hasLength(3));
      expect(
        haptics.map((call) => call.arguments),
        everyElement('HapticFeedbackType.selectionClick'),
      );

      await tester.tap(find.text('Close More'));
      await tester.pump();
      expect(_selected(tester, 'YO Moments'), isTrue);
      expect(_selected(tester, 'More'), isFalse);
      semantics.dispose();
    },
  );

  testWidgets(
    'selected More remains axis-aligned while the pointer hovers it',
    (tester) async {
      final semantics = await _pumpDock(tester, reduceMotion: false);
      final moreTarget = find.byKey(const ValueKey('yo-destination-4'));

      await tester.tap(moreTarget);
      await tester.pumpAndSettle();

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(moreTarget));
      await tester.pump(const Duration(milliseconds: 120));

      final selectedIcon = find.byKey(const ValueKey('4-true'));
      final iconBox = tester.renderObject<RenderBox>(selectedIcon);
      final targetBox = tester.renderObject<RenderBox>(moreTarget);
      final iconTransform = iconBox.getTransformTo(targetBox);
      expect(
        find.descendant(
          of: moreTarget,
          matching: find.byType(AnimatedRotation),
        ),
        findsNothing,
      );
      expect(iconTransform.storage[1], closeTo(0, .000001));
      expect(iconTransform.storage[4], closeTo(0, .000001));

      final capsuleTransform = tester
          .widget<Transform>(
            find.byKey(const ValueKey('yo-active-capsule-scale')),
          )
          .transform;
      expect(capsuleTransform.storage[1], closeTo(0, .000001));
      expect(capsuleTransform.storage[4], closeTo(0, .000001));
      expect(_selected(tester, 'More'), isTrue);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('parent acceptance, not a tap, commits the shared capsule', (
    tester,
  ) async {
    final requested = <int>[];
    final harnessKey = GlobalKey<_DockHarnessState>();
    final semantics = await _pumpDock(
      tester,
      autoAccept: false,
      onRequested: requested.add,
      harnessKey: harnessKey,
      reduceMotion: false,
    );
    final before = tester.getRect(
      find.byKey(const ValueKey('yo-active-capsule-position')),
    );

    await tester.tap(find.byKey(const ValueKey('yo-destination-1')));
    await tester.pump(const Duration(milliseconds: 180));
    final rejected = tester.getRect(
      find.byKey(const ValueKey('yo-active-capsule-position')),
    );
    expect(requested, [1]);
    expect(_selected(tester, 'Home'), isTrue);
    expect(rejected.center.dx, closeTo(before.center.dx, .01));

    harnessKey.currentState!.acceptDestination(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 330));
    final accepted = tester.getRect(
      find.byKey(const ValueKey('yo-active-capsule-position')),
    );
    final chats = tester.getRect(
      find.byKey(const ValueKey('yo-destination-1')),
    );
    expect(_selected(tester, 'Chats, 3 unread conversations'), isTrue);
    expect(accepted.center.dx, closeTo(chats.center.dx, .5));
    semantics.dispose();
  });

  testWidgets('capsule stretches adjacent and disappears while crossing YO', (
    tester,
  ) async {
    final semantics = await _pumpDock(tester);

    await tester.tap(find.byKey(const ValueKey('yo-destination-1')));
    await tester.pump();
    var maximumScaleX = 1.0;
    for (var elapsed = 0; elapsed < 330; elapsed += 30) {
      await tester.pump(const Duration(milliseconds: 30));
      final transform = tester.widget<Transform>(
        find.byKey(const ValueKey('yo-active-capsule-scale')),
      );
      maximumScaleX = math.max(maximumScaleX, transform.transform.storage[0]);
    }
    expect(maximumScaleX, inInclusiveRange(1.05, 1.12));

    await tester.tap(find.byKey(const ValueKey('yo-destination-3')));
    await tester.pump();
    var minimumOpacity = 1.0;
    for (var elapsed = 0; elapsed < 480; elapsed += 20) {
      await tester.pump(const Duration(milliseconds: 20));
      final opacity = tester.widget<Opacity>(
        find.byKey(const ValueKey('yo-active-capsule-opacity')),
      );
      minimumOpacity = math.min(minimumOpacity, opacity.opacity);
      expect(_selected(tester, 'Open voice actions'), isFalse);
    }
    expect(minimumOpacity, lessThan(.15));
    final finalCapsule = tester.getRect(
      find.byKey(const ValueKey('yo-active-capsule-position')),
    );
    final moments = tester.getRect(
      find.byKey(const ValueKey('yo-destination-3')),
    );
    expect(finalCapsule.center.dx, closeTo(moments.center.dx, .5));
    semantics.dispose();
  });

  testWidgets(
    'unread badge caps visually at 99+ but announces the real count',
    (tester) async {
      final semantics = await _pumpDock(
        tester,
        unreadConversationCount: 100,
        reduceMotion: true,
      );
      expect(find.text('99+'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Chats, 100 unread conversations'),
        findsOneWidget,
      );
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

  testWidgets(
    'the whole visible YO mark including its lower edge is tappable',
    (tester) async {
      var expectedActivations = 0;
      for (final width in [320.0, 390.0]) {
        final semantics = await _pumpDock(
          tester,
          width: width,
          height: 700,
          reduceMotion: true,
        );
        final logo = tester.getRect(find.byKey(const ValueKey('dock-logo')));
        final hitTarget = tester.getRect(
          find.byKey(const ValueKey('yo-center-action-hit-target')),
        );
        final visualBoundary = tester.getRect(
          find.byKey(const ValueKey('yo-center-action-boundary')),
        );
        final semanticsNode = tester.getSemantics(
          find.bySemanticsLabel('Open voice actions'),
        );

        expect(hitTarget.center.dx, closeTo(logo.center.dx, .01));
        expect(
          hitTarget.width,
          greaterThan(logo.width * .814),
          reason: 'the target must cover the visible horizontal logo alpha',
        );
        expect(hitTarget.bottom, closeTo(logo.bottom, .01));
        expect(hitTarget.bottom, greaterThan(visualBoundary.bottom));
        expect(semanticsNode.rect.size, hitTarget.size);
        for (final slot in [1, 3]) {
          final neighbour = tester.getRect(
            find.byKey(ValueKey('yo-destination-$slot')),
          );
          expect(
            hitTarget.overlaps(neighbour),
            isFalse,
            reason: 'the expanded YO target must not cover slot $slot',
          );
        }

        await tester.tapAt(Offset(logo.center.dx, logo.bottom - 1));
        await tester.pump();
        expectedActivations += 1;
        expect(find.text('Voice $expectedActivations'), findsOneWidget);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      }
    },
  );

  testWidgets('all five controls expose an actionable semantics tap', (
    tester,
  ) async {
    final semantics = await _pumpDock(tester, reduceMotion: true);

    for (final label in [
      'Home',
      'Chats, 3 unread conversations',
      'Open voice actions',
      'YO Moments',
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
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'YO dock 0');
      final homeFocus = tester.widget<Material>(
        find.byKey(const ValueKey('yo-destination-focus-0')),
      );
      final homeFocusShape = homeFocus.shape! as RoundedRectangleBorder;
      expect(homeFocusShape.side.color, AppPalette.dark.focus);
      expect(homeFocusShape.side.width, 2);

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

  testWidgets(
    'the YO focus boundary uses the semantic focus colour in Dark and Pearl',
    (tester) async {
      for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
        final semantics = await _pumpDock(
          tester,
          theme: theme,
          reduceMotion: true,
        );
        final home = tester.widget<InkWell>(
          find.byKey(const ValueKey('yo-destination-0')),
        );
        home.focusNode!.requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();

        final outline = tester.widget<AnimatedContainer>(
          find.byKey(const ValueKey('yo-center-focus-outline')),
        );
        final decoration = outline.decoration! as BoxDecoration;
        final ring = (decoration.border! as Border).top.color;
        final palette = theme.extension<AppPalette>()!;
        expect(ring, palette.focus);
        expect(
          _contrastRatio(ring, palette.navigationSurface),
          greaterThanOrEqualTo(3),
          reason: '${theme.brightness.name} focus ring must clear the shell',
        );
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'the exposed top and side edges of the transparent YO target tap',
    (tester) async {
      final semantics = await _pumpDock(tester, reduceMotion: true);
      final button = tester.getRect(
        find.byKey(const ValueKey('yo-center-action-boundary')),
      );
      final dock = tester.getRect(
        find.byKey(const ValueKey('yo-floating-navigation-dock')),
      );
      expect(button.top, closeTo(dock.top, .01));
      expect(button.center.dx, closeTo(dock.center.dx, .01));
      expect(find.byKey(const ValueKey('yo-center-cradle')), findsNothing);

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
    },
  );

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

  testWidgets('320x640, 200% text and a home indicator work in both themes', (
    tester,
  ) async {
    for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
      final semantics = await _pumpDock(
        tester,
        width: 320,
        height: 640,
        safeBottom: 34,
        textScale: 2,
        unreadConversationCount: 100,
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
      expect(capsule.size, const Size.square(52));
      expect(button.width, 64);
      final badge = tester.getRect(
        find.byKey(const ValueKey('yo-chats-unread-badge')),
      );
      expect(badge.width, lessThanOrEqualTo(36));
      expect(
        badge.overlaps(button),
        isFalse,
        reason: 'the clamped 99+ badge must stay outside the YO action',
      );
      for (final slot in [0, 1, 3, 4]) {
        final target = tester.getRect(
          find.byKey(ValueKey('yo-destination-$slot')),
        );
        expect(target.width, greaterThanOrEqualTo(48));
        expect(target.height, greaterThanOrEqualTo(48));
        expect(
          target.overlaps(button),
          isFalse,
          reason: 'destination $slot must not enter the central YO zone',
        );
        expect(
          find.descendant(
            of: find.byKey(ValueKey('yo-destination-label-$slot')),
            matching: find.byType(FittedBox),
          ),
          findsNothing,
          reason: 'destination $slot must not scale its label down',
        );
      }
      for (final label in ['Home', 'Chats', 'YO Moments', 'More']) {
        final finder = find.text(label);
        final text = tester.widget<Text>(find.text(label));
        expect(text.maxLines, 3);
        expect(text.overflow, TextOverflow.visible);
        expect(text.textScaler, isNull);
        _expectFullyScaledText(tester, finder);
        expect(
          tester.getRect(finder).overlaps(button),
          isFalse,
          reason: '$label must remain clear of the central YO control',
        );
      }

      for (final slot in [0, 1, 3, 4]) {
        await tester.tap(find.byKey(ValueKey('yo-destination-$slot')));
        await tester.pump();
        final selectedCapsule = tester.getRect(
          find.byKey(const ValueKey('yo-active-capsule-position')),
        );
        expect(
          selectedCapsule.overlaps(button),
          isFalse,
          reason: 'active capsule for slot $slot must clear the YO control',
        );
      }
      expect(tester.takeException(), isNull);
      semantics.dispose();
    }
    expect(YoFloatingNavigationDock.reservedHeightFor(safeBottom: 34), 142);
    expect(
      YoFloatingNavigationDock.reservedHeightFor(safeBottom: 34, textScale: 2),
      234,
    );
  });

  testWidgets(
    'RTL mirrors the dock and keeps logical Home to More focus traversal',
    (tester) async {
      final semantics = await _pumpDock(
        tester,
        locale: const Locale('ar'),
        width: 390,
        height: 700,
        reduceMotion: true,
      );

      final home = tester.getRect(
        find.byKey(const ValueKey('yo-destination-0')),
      );
      final chats = tester.getRect(
        find.byKey(const ValueKey('yo-destination-1')),
      );
      final center = tester.getRect(
        find.byKey(const ValueKey('yo-center-action-hit-target')),
      );
      final moments = tester.getRect(
        find.byKey(const ValueKey('yo-destination-3')),
      );
      final more = tester.getRect(
        find.byKey(const ValueKey('yo-destination-4')),
      );
      expect(home.center.dx, greaterThan(chats.center.dx));
      expect(chats.center.dx, greaterThan(center.center.dx));
      expect(center.center.dx, greaterThan(moments.center.dx));
      expect(moments.center.dx, greaterThan(more.center.dx));

      final badge = tester.getRect(
        find.byKey(const ValueKey('yo-chats-unread-badge')),
      );
      expect(
        badge.center.dx,
        lessThan(chats.center.dx),
        reason: 'the unread badge belongs on the directional end in RTL',
      );

      final homeInk = tester.widget<InkWell>(
        find.byKey(const ValueKey('yo-destination-0')),
      );
      homeInk.focusNode!.requestFocus();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'YO dock 0');
      for (final expected in <String>[
        'YO dock 1',
        'YO dock 2',
        'YO dock 3',
        'YO dock 4',
      ]) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus?.debugLabel, expected);
      }
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

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

  testWidgets('rapid reversal inside the YO fade zone never flashes', (
    tester,
  ) async {
    final semantics = await _pumpDock(tester, initialSelected: 1);

    await tester.tap(find.byKey(const ValueKey('yo-destination-3')));
    await tester.pump();
    double opacity = 1;
    for (var elapsed = 0; elapsed < 360 && opacity >= .4; elapsed += 20) {
      await tester.pump(const Duration(milliseconds: 20));
      opacity = tester
          .widget<Opacity>(
            find.byKey(const ValueKey('yo-active-capsule-opacity')),
          )
          .opacity;
    }
    expect(opacity, lessThan(.4));

    await tester.tap(find.byKey(const ValueKey('yo-destination-1')));
    await tester.pump();
    final reversedOpacity = tester
        .widget<Opacity>(
          find.byKey(const ValueKey('yo-active-capsule-opacity')),
        )
        .opacity;
    expect(reversedOpacity, lessThan(.55));
    expect(reversedOpacity, lessThanOrEqualTo(opacity + .12));

    await tester.pump(const Duration(milliseconds: 620));
    final capsule = tester.getRect(
      find.byKey(const ValueKey('yo-active-capsule-position')),
    );
    final chats = tester.getRect(
      find.byKey(const ValueKey('yo-destination-1')),
    );
    expect(capsule.center.dx, closeTo(chats.center.dx, .5));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('active capsule and ripple dispose without lifecycle errors', (
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

  testWidgets('enabling reduced motion mid-flight settles immediately', (
    tester,
  ) async {
    final reduceMotion = ValueNotifier<bool>(false);
    addTearDown(reduceMotion.dispose);
    final semantics = await _pumpDock(
      tester,
      reduceMotionListenable: reduceMotion,
    );

    await tester.tap(find.bySemanticsLabel('Open voice actions'));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.tap(find.byKey(const ValueKey('yo-destination-4')));
    await tester.pump(const Duration(milliseconds: 80));
    reduceMotion.value = true;
    await tester.pump();

    final capsule = tester.getRect(
      find.byKey(const ValueKey('yo-active-capsule-position')),
    );
    final more = tester.getRect(find.byKey(const ValueKey('yo-destination-4')));
    expect(capsule.center.dx, closeTo(more.center.dx, .5));
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const ValueKey('yo-active-capsule-opacity')),
          )
          .opacity,
      1,
    );
    expect(find.byKey(const ValueKey('yo-center-ripple')), findsNothing);
    await tester.pump(const Duration(milliseconds: 120));
    final settled = tester.getRect(
      find.byKey(const ValueKey('yo-active-capsule-position')),
    );
    expect(settled.center.dx, closeTo(more.center.dx, .5));
    semantics.dispose();
  });

  testWidgets('Friends keeps destination geometry fresh across resize', (
    tester,
  ) async {
    final harnessKey = GlobalKey<_DockHarnessState>();
    final semantics = await _pumpDock(
      tester,
      width: 390,
      height: 700,
      initialSelected: 2,
      harnessKey: harnessKey,
    );
    expect(
      find.byKey(const ValueKey('yo-active-capsule-position')),
      findsNothing,
    );

    tester.view.physicalSize = const Size(320, 700);
    await tester.pump();
    await tester.pump();
    harnessKey.currentState!.acceptDestination(1);
    await tester.pump();

    final capsule = tester.getRect(
      find.byKey(const ValueKey('yo-active-capsule-position')),
    );
    final chats = tester.getRect(
      find.byKey(const ValueKey('yo-destination-1')),
    );
    expect(capsule.center.dx, closeTo(chats.center.dx, .5));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('Polish dock semantics localize unread and voice state', (
    tester,
  ) async {
    final semantics = await _pumpDock(
      tester,
      locale: const Locale('pl'),
      unreadConversationCount: 23,
      reduceMotion: true,
    );

    expect(
      find.bySemanticsLabel('Czaty, 23 nieprzeczytane rozmowy'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Otwórz opcje głosowe'), findsOneWidget);
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
