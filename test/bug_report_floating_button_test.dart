import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/bug_reports/data/bug_report_route_tracker.dart';
import 'package:yovoice/features/bug_reports/presentation/bug_report_floating_button.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/presentation/widgets/yo_top_notification_host.dart';

/// The testing-period "Bug" button: it must never overlap or move the
/// floating dock, never sit in a system gesture strip, and hide itself when
/// it would get in the way.
class _MemoryStore implements AppPreferencesStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => TextButton(
    key: const ValueKey('counter'),
    onPressed: () => setState(() => taps++),
    child: Text('taps $taps'),
  );
}

const _gestureInset = 24.0;
const _safeBottom = 34.0;

Finder get _button => find.byKey(const ValueKey('bug-report-floating-button'));
Finder get _dock => find.byType(YoFloatingNavigationDock);

Future<({BugReportRouteTracker tracker, List<BuildContext> opened})> _pump(
  WidgetTester tester, {
  required Size size,
  AppPreferencesController? preferences,
  bool signedIn = true,
  YoTopNotificationController? topNotifications,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: _safeBottom);
  tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: _safeBottom);
  tester.view.systemGestureInsets = const FakeViewPadding(
    left: _gestureInset,
    right: _gestureInset,
    bottom: 20,
  );
  addTearDown(tester.view.reset);
  final tracker = BugReportRouteTracker();
  final navigatorKey = GlobalKey<NavigatorState>();
  final opened = <BuildContext>[];
  final controller =
      preferences ?? AppPreferencesController(store: _MemoryStore());
  await tester.pumpWidget(
    AppPreferencesScope(
      controller: controller,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [tracker],
        theme: AppTheme.darkTheme,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) {
          final host = BugReportFloatingButtonHost(
            navigatorKey: navigatorKey,
            available: true,
            initiallySignedIn: signedIn,
            signedInChanges: const Stream<bool>.empty(),
            routeTracker: tracker,
            onOpenReporter: opened.add,
            child: child!,
          );
          // The nesting app.dart uses: the banner layer above the button.
          return topNotifications == null
              ? host
              : YoTopNotificationHost(
                  controller: topNotifications,
                  child: host,
                );
        },
        home: Scaffold(
          body: const Center(child: _Counter()),
          // The real dock, exactly as the mobile shell mounts it. On the
          // desktop layout the shell shows a rail instead; rendering the dock
          // at 1440 as well is the stricter check.
          bottomNavigationBar: YoFloatingNavigationDock(
            selectedTabIndex: 0,
            roomsTabIndex: 13,
            momentsTabIndex: 5,
            unreadConversationCount: 3,
            onDestinationSelected: (_) {},
            onVoicePressed: () {},
            onMorePressed: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (tracker: tracker, opened: opened);
}

void _expectClear(WidgetTester tester, Size size, String reason) {
  expect(_button, findsOneWidget, reason: reason);
  final button = tester.getRect(_button);
  final dock = tester.getRect(_dock);
  expect(
    button.overlaps(dock),
    isFalse,
    reason: '$reason: button $button overlaps dock $dock',
  );
  expect(button.bottom, lessThanOrEqualTo(dock.top), reason: reason);
  // Inside the screen and outside both side gesture strips.
  expect(button.left, greaterThanOrEqualTo(_gestureInset), reason: reason);
  expect(
    button.right,
    lessThanOrEqualTo(size.width - _gestureInset),
    reason: reason,
  );
  expect(button.top, greaterThanOrEqualTo(47 + kToolbarHeight), reason: reason);
  expect(button.width, greaterThanOrEqualTo(44), reason: 'touch target');
}

void main() {
  for (final size in const [Size(390, 844), Size(768, 1024), Size(1440, 900)]) {
    testWidgets('${size.width.toInt()}px: the Bug button never overlaps the '
        'dock or a gesture edge, wherever it is dragged', (tester) async {
      await _pump(tester, size: size);
      final dockBefore = tester.getRect(_dock);
      _expectClear(tester, size, 'resting');

      // Fling it at every corner and past every edge; it clamps and snaps.
      for (final (label, delta) in const [
        ('bottom-left', Offset(-4000, 4000)),
        ('bottom-right', Offset(4000, 4000)),
        ('top-left', Offset(-4000, -4000)),
        ('top-right', Offset(4000, -4000)),
        ('into the dock', Offset(0, 900)),
      ]) {
        await tester.drag(_button, delta);
        await tester.pumpAndSettle();
        _expectClear(tester, size, label);
      }

      // The dock itself never moved or resized.
      expect(tester.getRect(_dock), dockBefore);
    });
  }

  testWidgets('at 390px it snaps to the nearer side edge; on the desktop '
      'layout it stays on the right, clear of the rail', (tester) async {
    await _pump(tester, size: const Size(390, 844));
    await tester.drag(_button, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(tester.getRect(_button).left, lessThan(390 / 2));

    await _pump(tester, size: const Size(1440, 900));
    await tester.drag(_button, const Offset(-1300, 0));
    await tester.pumpAndSettle();
    expect(tester.getRect(_button).left, greaterThan(1440 / 2));
  });

  testWidgets('a top banner paints above a Bug button parked high: a tap on '
      'the banner reaches the banner, never the reporter', (tester) async {
    final banner = YoTopNotificationController();
    addTearDown(banner.dispose);
    final harness = await _pump(
      tester,
      size: const Size(390, 844),
      topNotifications: banner,
    );
    // Park the button as high as it goes, on the right edge.
    await tester.drag(_button, const Offset(0, -900));
    await tester.pumpAndSettle();
    var opened = 0;
    expect(
      banner.show(
        YoTopNotification(
          title: 'Ola sent you a friend request',
          body: 'Tap to see who it is and answer.',
          type: NotificationType.friendRequest,
          onOpen: () => opened++,
        ),
      ),
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 900));

    final card = tester.getRect(
      find.byKey(const ValueKey('yo-top-notification-card')),
    );
    final overlap = card.intersect(tester.getRect(_button));
    expect(
      overlap.width > 0 && overlap.height > 0,
      isTrue,
      reason: 'the scenario needs the button under the banner: '
          'card $card, button ${tester.getRect(_button)}',
    );
    await tester.tapAt(overlap.center);
    await tester.pump(const Duration(milliseconds: 400));
    expect(harness.opened, isEmpty);
    expect(opened, 1);
    banner.clear();
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a tap opens the reporter from the navigator', (tester) async {
    final harness = await _pump(tester, size: const Size(390, 844));
    await tester.tap(_button);
    await tester.pump();
    expect(harness.opened, hasLength(1));
  });

  testWidgets('screen readers can activate it: the node is a button with a '
      'tap action that opens the reporter, and a hide action', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = await _pump(tester, size: const Size(390, 844));
    final node = tester.getSemantics(_button);
    expect(
      node,
      isSemantics(
        label: 'Report a bug',
        hint: 'Drag to move. Touch and hold to hide.',
        isButton: true,
        hasTapAction: true,
        hasLongPressAction: true,
        customActions: const <CustomSemanticsAction>[
          CustomSemanticsAction(label: 'Hide the Bug button'),
        ],
      ),
    );
    // Dispatch the tap the way TalkBack and VoiceOver do: through the
    // semantics tree, not a pointer.
    tester.semantics.tap(find.semantics.byLabel('Report a bug'));
    await tester.pump();
    expect(harness.opened, hasLength(1));
    semantics.dispose();
  });

  testWidgets('hidden while signed out, while a dialog is open and while '
      'the keyboard is up; the app below never rebuilds from scratch', (
    tester,
  ) async {
    await _pump(tester, size: const Size(390, 844), signedIn: false);
    expect(_button, findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, size: const Size(390, 844));
    await tester.tap(find.byKey(const ValueKey('counter')));
    await tester.pump();
    expect(find.text('taps 1'), findsOneWidget);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      showDialog<void>(
        context: navigator.context,
        builder: (_) => const AlertDialog(content: Text('dialog')),
      ),
    );
    await tester.pumpAndSettle();
    expect(_button, findsNothing, reason: 'never over a modal');
    navigator.pop();
    await tester.pumpAndSettle();
    expect(_button, findsOneWidget);
    // The page under the host kept its state through the toggle.
    expect(find.text('taps 1'), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(_button, findsNothing, reason: 'never over the keyboard');
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(_button, findsOneWidget);
  });

  testWidgets('the tester can hide it with a long press, and the preference '
      'controls it', (tester) async {
    final store = _MemoryStore();
    final preferences = AppPreferencesController(store: store);
    await _pump(tester, size: const Size(390, 844), preferences: preferences);
    await tester.longPress(_button);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('bug-button-hide-dialog')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('bug-button-hide-confirm')));
    await tester.pumpAndSettle();
    expect(_button, findsNothing);
    expect(preferences.value.bugReportButtonVisible, isFalse);
    expect(store.values['testing.bug_report_button.visible.v1'], 'false');

    await preferences.setBugReportButtonVisible(true);
    await tester.pumpAndSettle();
    expect(_button, findsOneWidget);
  });

  test('the allowed area always ends above the dock\'s reserved band', () {
    for (final scale in const [1.0, 1.3, 2.0]) {
      const size = Size(390, 844);
      final media = MediaQueryData(
        size: size,
        viewPadding: const EdgeInsets.only(bottom: _safeBottom),
        textScaler: TextScaler.linear(scale),
      );
      final area = bugButtonAllowedArea(media);
      if (area == null) continue;
      final dockTop =
          size.height -
          YoFloatingNavigationDock.reservedHeightFor(
            safeBottom: _safeBottom,
            textScale: scale,
          );
      expect(area.bottom, lessThan(dockTop), reason: '${scale}x');
    }
    // A landscape phone has no room: no button at all.
    expect(
      bugButtonAllowedArea(const MediaQueryData(size: Size(844, 200))),
      isNull,
    );
  });

  group('the glyph is legible in both themes (WCAG 1.4.11, 3:1)', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final high = la > lb ? la : lb;
      final low = la > lb ? lb : la;
      return (high + .05) / (low + .05);
    }

    for (final (name, palette) in const [
      ('Dark', AppPalette.dark),
      ('Pearl', AppPalette.light),
    ]) {
      test(name, () {
        final glyph = bugReportButtonGlyphColor(palette);
        final fill = palette.surfaceRaised.withValues(
          alpha: bugReportButtonFillAlpha,
        );
        // The fill is translucent, so it is measured over the app's own
        // canvas and over the brightest and darkest content behind it.
        for (final backdrop in [
          palette.background,
          Colors.white,
          Colors.black,
        ]) {
          final composited = Color.alphaBlend(fill, backdrop);
          expect(
            contrast(glyph, composited),
            greaterThanOrEqualTo(3),
            reason: '$name glyph on the fill over $backdrop',
          );
        }
      });
    }
  });
}
