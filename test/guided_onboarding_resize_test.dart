import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';
import 'package:yovoice/features/onboarding/presentation/guided_onboarding_tour.dart';

void main() {
  testWidgets(
    'open Create step follows the active anchor across desktop-mobile resize',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final anchors = {
        for (final target in GuidedOnboardingTarget.values)
          target: GlobalKey(debugLabel: 'responsive-tour-${target.name}'),
      };
      final preparedLayouts = <bool>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: _ResponsiveTourHarness(
            anchors: anchors,
            onLayoutChanged: preparedLayouts.add,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('desktop-anchor-layout')), findsOne);
      await tester.tap(find.byKey(const ValueKey('open-guided-tour')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guided-tour-next')));
      await tester.pumpAndSettle();

      expect(find.text('Use your voice'), findsOneWidget);
      expect(
        find.text('Create a Voice Moment or start a Voice Room here.'),
        findsOneWidget,
      );
      _expectCreateHighlightMatches(tester, anchors);
      expect(preparedLayouts, [true]);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('mobile-anchor-layout')), findsOne);
      expect(find.byKey(const ValueKey('desktop-anchor-layout')), findsNothing);
      expect(find.text('Use your voice'), findsOneWidget);
      expect(
        find.text(
          'Create a Voice Room here. Open Your Moments to record a Voice Moment.',
        ),
        findsOneWidget,
      );
      _expectCreateHighlightMatches(tester, anchors);
      expect(preparedLayouts, [true, false]);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(1200, 800);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('desktop-anchor-layout')), findsOne);
      expect(find.byKey(const ValueKey('mobile-anchor-layout')), findsNothing);
      expect(find.text('Use your voice'), findsOneWidget);
      _expectCreateHighlightMatches(tester, anchors);
      expect(preparedLayouts, [true, false, true]);
      expect(tester.takeException(), isNull);
    },
  );
}

void _expectCreateHighlightMatches(
  WidgetTester tester,
  Map<GuidedOnboardingTarget, GlobalKey> anchors,
) {
  final target = find.byKey(anchors[GuidedOnboardingTarget.create]!);
  final highlight = find.byKey(const ValueKey('guided-tour-highlight-create'));

  expect(target, findsOneWidget);
  expect(highlight, findsOneWidget);

  final targetRect = tester.getRect(target);
  final highlightRect = tester.getRect(highlight);
  final expected = targetRect.inflate(8);
  expect(highlightRect.left, closeTo(expected.left, .01));
  expect(highlightRect.top, closeTo(expected.top, .01));
  expect(highlightRect.right, closeTo(expected.right, .01));
  expect(highlightRect.bottom, closeTo(expected.bottom, .01));
}

class _ResponsiveTourHarness extends StatefulWidget {
  const _ResponsiveTourHarness({
    required this.anchors,
    required this.onLayoutChanged,
  });

  final Map<GuidedOnboardingTarget, GlobalKey> anchors;
  final ValueChanged<bool> onLayoutChanged;

  @override
  State<_ResponsiveTourHarness> createState() => _ResponsiveTourHarnessState();
}

class _ResponsiveTourHarnessState extends State<_ResponsiveTourHarness> {
  void _openTour() {
    unawaited(
      showGuidedOnboardingTour(
        context,
        anchors: widget.anchors,
        desktop: MainShell.usesDesktopLayout(MediaQuery.sizeOf(context)),
        desktopLayoutFor: MainShell.usesDesktopLayout,
        onLayoutChanged: widget.onLayoutChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MainShell.usesDesktopLayout(MediaQuery.sizeOf(context));
    return desktop
        ? _DesktopAnchorLayout(anchors: widget.anchors, onOpen: _openTour)
        : _MobileAnchorLayout(anchors: widget.anchors, onOpen: _openTour);
  }
}

class _DesktopAnchorLayout extends StatelessWidget {
  const _DesktopAnchorLayout({required this.anchors, required this.onOpen});

  final Map<GuidedOnboardingTarget, GlobalKey> anchors;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('desktop-anchor-layout'),
      body: Row(
        children: [
          DesktopSidebar(
            active: DesktopNavItem.home,
            unreadConversationCount: 0,
            unreadNotificationCount: 0,
            onSelect: (_) {},
            onCreateRoom: () {},
            onCreateMoment: () {},
            onOpenProfile: () {},
            onOpenProfileSettings: () {},
            tourItemKeys: {
              DesktopNavItem.moments: anchors[GuidedOnboardingTarget.moments]!,
              DesktopNavItem.chats: anchors[GuidedOnboardingTarget.chats]!,
              DesktopNavItem.more: anchors[GuidedOnboardingTarget.more]!,
            },
            tourCreateKey: anchors[GuidedOnboardingTarget.create],
          ),
          Expanded(
            child: Center(
              child: FilledButton(
                key: const ValueKey('open-guided-tour'),
                onPressed: onOpen,
                child: const Text('Open tour'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileAnchorLayout extends StatelessWidget {
  const _MobileAnchorLayout({required this.anchors, required this.onOpen});

  final Map<GuidedOnboardingTarget, GlobalKey> anchors;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('mobile-anchor-layout'),
      body: Column(
        children: [
          FilledButton.tonalIcon(
            key: anchors[GuidedOnboardingTarget.create],
            onPressed: () {},
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create room'),
          ),
          FilledButton(
            key: const ValueKey('open-guided-tour'),
            onPressed: onOpen,
            child: const Text('Open tour'),
          ),
        ],
      ),
      bottomNavigationBar: YoFloatingNavigationDock(
        selectedTabIndex: 3,
        momentsTabIndex: 5,
        unreadConversationCount: 0,
        onDestinationSelected: (_) {},
        onVoicePressed: () {},
        onMorePressed: () {},
        tourDestinationKeys: {
          2: anchors[GuidedOnboardingTarget.chats]!,
          3: anchors[GuidedOnboardingTarget.moments]!,
          4: anchors[GuidedOnboardingTarget.more]!,
        },
      ),
    );
  }
}
