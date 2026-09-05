import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/app/app.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/auth/presentation/navigation/auth_epoch_route_resetter.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/presentation/widgets/yo_top_notification_host.dart';

const _cardKey = ValueKey('yo-top-notification-card');

YoTopNotification _notification(
  String title, {
  VoidCallback? onOpen,
  Object? source,
}) => YoTopNotification(
  title: title,
  body: 'A private message',
  type: NotificationType.directMessage,
  source: source,
  onOpen: onOpen ?? () {},
);

Widget _host(
  YoTopNotificationController controller, {
  MediaQueryData? media,
  Widget? body,
  GlobalKey<NavigatorState>? navigatorKey,
  GlobalKey<ScaffoldMessengerState>? messengerKey,
  VoidCallback? onReady,
  TargetPlatform? platform,
}) => MaterialApp(
  theme: AppTheme.darkTheme.copyWith(platform: platform),
  navigatorKey: navigatorKey,
  scaffoldMessengerKey: messengerKey,
  builder: (context, child) => MediaQuery(
    data: media ?? MediaQuery.of(context),
    child: YoTopNotificationHost(
      controller: controller,
      onReady: onReady,
      child: child!,
    ),
  ),
  home: Scaffold(body: body ?? const SizedBox.expand()),
);

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('F6 hint follows keyboard input on ${platform.name}', (
      tester,
    ) async {
      final previousStrategy = FocusManager.instance.highlightStrategy;
      addTearDown(
        () => FocusManager.instance.highlightStrategy = previousStrategy,
      );
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      final controller = YoTopNotificationController();
      await tester.pumpWidget(_host(controller, platform: platform));
      controller.show(_notification('Touch notification'));
      await tester.pumpAndSettle();
      expect(find.text('F6'), findsNothing);
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      await tester.pumpAndSettle();
      expect(find.text('F6'), findsOneWidget);
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      await tester.pumpAndSettle();
      expect(find.text('F6'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  }

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets('F6 hint stays discoverable on ${platform.name}', (
      tester,
    ) async {
      final previousStrategy = FocusManager.instance.highlightStrategy;
      addTearDown(
        () => FocusManager.instance.highlightStrategy = previousStrategy,
      );
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      final controller = YoTopNotificationController();
      await tester.pumpWidget(_host(controller, platform: platform));
      controller.show(_notification('Desktop notification'));
      await tester.pumpAndSettle();
      expect(find.text('F6'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  }

  testWidgets(
    'keyboard footer remains reachable just above minimum height at 200%',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = YoTopNotificationController();
      await tester.pumpWidget(
        _host(
          controller,
          media: const MediaQueryData(
            size: Size(320, 640),
            viewInsets: EdgeInsets.only(bottom: 474),
            textScaler: TextScaler.linear(2),
          ),
        ),
      );
      expect(
        controller.show(
          _notification('A long notification above the keyboard'),
        ),
        isTrue,
      );
      await tester.pumpAndSettle();
      final card = tester.getRect(find.byKey(_cardKey));
      expect(card.bottom, lessThanOrEqualTo(156));
      for (final key in [
        'yo-top-notification-close',
        'yo-top-notification-open',
      ]) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        expect(rect.width, greaterThanOrEqualTo(44));
        expect(rect.height, greaterThanOrEqualTo(44));
        expect(rect.bottom, lessThanOrEqualTo(card.bottom));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets(
    'F6 reaches controls from populated route and returns exact focus',
    (tester) async {
      final controller = YoTopNotificationController();
      final field = FocusNode();
      await tester.pumpWidget(
        _host(
          controller,
          body: Column(
            children: [
              TextField(focusNode: field),
              TextButton(
                onPressed: () {},
                child: const Text('Underlying button'),
              ),
            ],
          ),
        ),
      );
      field.requestFocus();
      await tester.pump();
      controller.show(_notification('Keyboard region'));
      await tester.pumpAndSettle();
      expect(field.hasFocus, isTrue);
      final close = tester
          .widget<IconButton>(
            find.byKey(const ValueKey('yo-top-notification-close')),
          )
          .focusNode!;
      final open = tester
          .widget<TextButton>(
            find.byKey(const ValueKey('yo-top-notification-open')),
          )
          .focusNode!;
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(controller.isShowing, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pump();
      expect(close.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(open.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(close.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pump();
      expect(field.hasPrimaryFocus, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pump();
      expect(close.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(field.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(controller.isShowing, isFalse);
      expect(field.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pump();
      expect(field.hasPrimaryFocus, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      field.dispose();
      controller.dispose();
    },
  );

  testWidgets('F6 returns into dialog without weakening its focus trap', (
    tester,
  ) async {
    final controller = YoTopNotificationController();
    final navigator = GlobalKey<NavigatorState>();
    final dialogField = FocusNode();
    await tester.pumpWidget(_host(controller, navigatorKey: navigator));
    showDialog<void>(
      context: navigator.currentContext!,
      builder: (_) => AlertDialog(
        content: TextField(focusNode: dialogField, autofocus: true),
        actions: [
          TextButton(onPressed: () {}, child: const Text('Dialog action')),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(dialogField.hasPrimaryFocus, isTrue);
    controller.show(_notification('Over modal'));
    await tester.pumpAndSettle();
    expect(dialogField.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('yo-top-notification-close')),
          )
          .focusNode!
          .hasPrimaryFocus,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.pump();
    expect(dialogField.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(dialogField.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    dialogField.dispose();
    controller.dispose();
  });

  testWidgets(
    'replacement resets content scroll but retains controls and F6 return',
    (tester) async {
      final controller = YoTopNotificationController();
      final field = FocusNode();
      final pageScroll = ScrollController();
      await tester.pumpWidget(
        _host(
          controller,
          media: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
            accessibleNavigation: true,
          ),
          body: SingleChildScrollView(
            controller: pageScroll,
            child: SizedBox(height: 1600, child: TextField(focusNode: field)),
          ),
        ),
      );
      field.requestFocus();
      await tester.pump();
      YoTopNotification long(String title) => YoTopNotification(
        title: title,
        body: List.filled(40, 'A deliberately long message.').join(' '),
        type: NotificationType.directMessage,
        onOpen: () {},
      );
      controller.show(long('First title'));
      await tester.pumpAndSettle();
      final scroll = find.byKey(const ValueKey('yo-top-notification-scroll'));
      final scrollable = find.descendant(
        of: scroll,
        matching: find.byType(Scrollable),
      );
      await tester.drag(scroll, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(
        tester.state<ScrollableState>(scrollable).position.pixels,
        greaterThan(0),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pump();
      final beforeKeyboard = tester
          .state<ScrollableState>(scrollable)
          .position
          .pixels;
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pump();
      expect(
        tester.state<ScrollableState>(scrollable).position.pixels,
        greaterThan(beforeKeyboard),
      );
      final beforeArrow = tester
          .state<ScrollableState>(scrollable)
          .position
          .pixels;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(
        tester.state<ScrollableState>(scrollable).position.pixels,
        greaterThan(beforeArrow),
      );
      expect(pageScroll.offset, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final originalOpen = tester
          .widget<TextButton>(
            find.byKey(const ValueKey('yo-top-notification-open')),
          )
          .focusNode!;
      expect(originalOpen.hasPrimaryFocus, isTrue);
      controller.show(long('Second title'));
      await tester.pumpAndSettle();
      expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('yo-top-notification-open')),
            )
            .focusNode,
        same(originalOpen),
      );
      expect(originalOpen.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pump();
      expect(field.hasPrimaryFocus, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      field.dispose();
      pageScroll.dispose();
      controller.dispose();
    },
  );

  testWidgets(
    'Open leaves focus to destination and clear discards old return intent',
    (tester) async {
      final controller = YoTopNotificationController();
      final oldField = FocusNode();
      final destination = FocusNode();
      await tester.pumpWidget(
        _host(
          controller,
          body: Column(
            children: [
              TextField(focusNode: oldField),
              TextField(focusNode: destination),
            ],
          ),
        ),
      );
      oldField.requestFocus();
      await tester.pump();
      controller.show(
        _notification(
          'Open destination',
          onOpen: () {
            expect(controller.isShowing, isFalse);
            destination.requestFocus();
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(destination.hasPrimaryFocus, isTrue);
      expect(controller.isShowing, isFalse);
      controller.show(_notification('Before external clear'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pump();
      controller.clear();
      oldField.requestFocus(); // Represents the new route's chosen focus.
      await tester.pumpAndSettle();
      controller.show(_notification('After external clear'));
      await tester.pumpAndSettle();
      expect(oldField.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(oldField.hasPrimaryFocus, isTrue);
      expect(destination.hasPrimaryFocus, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      oldField.dispose();
      destination.dispose();
      controller.dispose();
    },
  );

  testWidgets('rejects unmounted/background/disposed shows without queue', (
    tester,
  ) async {
    final controller = YoTopNotificationController();
    expect(controller.show(_notification('unmounted')), isFalse);
    await tester.pumpWidget(_host(controller));
    expect(find.text('unmounted'), findsNothing);
    expect(controller.show(_notification('visible')), isTrue);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(controller.isShowing, isFalse);
    await tester.pump();
    expect(find.byKey(_cardKey), findsNothing);
    expect(controller.show(_notification('background')), isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(_cardKey), findsNothing);
    expect(controller.show(_notification('resumed')), isTrue);
    controller.dispose();
    await tester.pump();
    expect(find.byKey(_cardKey), findsNothing);
    expect(controller.show(_notification('disposed')), isFalse);
    await tester.pump(const Duration(seconds: 20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('newest replaces one card and old timeout cannot close it', (
    tester,
  ) async {
    final controller = YoTopNotificationController();
    await tester.pumpWidget(_host(controller));
    controller.show(_notification('first'));
    await tester.pump(const Duration(seconds: 4));
    controller.show(_notification('second'));
    await tester.pumpAndSettle();
    expect(find.text('first'), findsNothing);
    expect(find.byKey(_cardKey), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('second'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byKey(_cardKey), findsNothing);
    controller.dispose();
  });

  testWidgets('source cleanup cannot remove a newer unrelated card', (
    tester,
  ) async {
    final controller = YoTopNotificationController();
    final shell = Object();
    await tester.pumpWidget(_host(controller));
    controller.show(_notification('shell', source: shell));
    controller.show(_notification('global'));
    controller.clear(source: shell);
    await tester.pumpAndSettle();
    expect(find.text('global'), findsOneWidget);
    controller.clear();
    await tester.pump();
    expect(find.byKey(_cardKey), findsNothing);
    controller.dispose();
  });

  testWidgets('reduced motion enters, replaces and dismisses instantly', (
    tester,
  ) async {
    final controller = YoTopNotificationController();
    await tester.pumpWidget(
      _host(
        controller,
        media: const MediaQueryData(
          size: Size(390, 844),
          disableAnimations: true,
        ),
      ),
    );
    controller.show(_notification('instant'));
    await tester.pump();
    final opacity = tester.widget<Opacity>(
      find
          .ancestor(of: find.byKey(_cardKey), matching: find.byType(Opacity))
          .first,
    );
    expect(opacity.opacity, 1);
    expect(tester.binding.transientCallbackCount, 0);
    controller.show(_notification('replaced'));
    await tester.pump();
    expect(find.text('instant'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('yo-top-notification-close')));
    await tester.pump();
    expect(find.byKey(_cardKey), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    controller.dispose();
  });

  testWidgets('one-shot motion settles and clearing entrance leaves no ghost', (
    tester,
  ) async {
    final controller = YoTopNotificationController();
    await tester.pumpWidget(_host(controller));
    controller.show(_notification('moving'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    controller.clear();
    await tester.pump();
    expect(find.byKey(_cardKey), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.transientCallbackCount, 0);
    controller.show(_notification('settled'));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    controller.clear();
    await tester.pump();
    controller.dispose();
  });

  testWidgets('accessible navigation persists and does not steal focus', (
    tester,
  ) async {
    final controller = YoTopNotificationController();
    final fieldFocus = FocusNode();
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        controller,
        media: const MediaQueryData(
          size: Size(390, 844),
          accessibleNavigation: true,
        ),
        body: Center(child: TextField(focusNode: fieldFocus)),
      ),
    );
    fieldFocus.requestFocus();
    await tester.pump();
    controller.show(_notification('Read this once'));
    await tester.pump();
    expect(fieldFocus.hasFocus, isTrue);
    final liveRegions = tester
        .widgetList<Semantics>(
          find.descendant(
            of: find.byKey(_cardKey),
            matching: find.byType(Semantics),
          ),
        )
        .where((widget) => widget.properties.liveRegion == true);
    expect(liveRegions, hasLength(1));
    await tester.pump(const Duration(seconds: 30));
    expect(find.byKey(_cardKey), findsOneWidget);
    controller.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    fieldFocus.dispose();
    controller.dispose();
    semantics.dispose();
  });

  testWidgets('route rootOverlay barriers stay below notification controls', (
    tester,
  ) async {
    final controller = YoTopNotificationController();
    late BuildContext routeContext;
    var barrierTaps = 0;
    var opened = 0;
    await tester.pumpWidget(
      _host(
        controller,
        body: Builder(
          builder: (context) {
            routeContext = context;
            return const Text('Route');
          },
        ),
      ),
    );
    final entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: BlockSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => barrierTaps++,
            child: const Align(
              alignment: Alignment.bottomCenter,
              child: Text('Mini chat'),
            ),
          ),
        ),
      ),
    );
    Overlay.of(routeContext, rootOverlay: true).insert(entry);
    controller.show(
      _notification('Above root overlay', onOpen: () => opened++),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('yo-top-notification-open')));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(barrierTaps, 0);
    expect(find.text('Mini chat'), findsOneWidget);
    controller.show(_notification('Close above root overlay'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('yo-top-notification-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(_cardKey), findsNothing);
    expect(barrierTaps, 0);
    entry.remove();
    entry.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('hover and keyboard focus suspend timeout', (tester) async {
    final controller = YoTopNotificationController();
    await tester.pumpWidget(_host(controller));
    controller.show(_notification('hover'));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.byKey(_cardKey)));
    await tester.pump(const Duration(seconds: 8));
    expect(find.text('hover'), findsOneWidget);
    await mouse.moveTo(const Offset(799, 599));
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.byKey(_cardKey), findsNothing);
    controller.show(_notification('keyboard'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    expect(find.text('keyboard'), findsOneWidget);
    controller.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await mouse.removePointer();
    controller.dispose();
  });

  testWidgets(
    'overlay is above dialogs, outside taps pass through, open clears first',
    (tester) async {
      final controller = YoTopNotificationController();
      final navigator = GlobalKey<NavigatorState>();
      var taps = 0;
      var opened = 0;
      await tester.pumpWidget(
        _host(
          controller,
          navigatorKey: navigator,
          body: Center(
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('Underlying action'),
            ),
          ),
        ),
      );
      controller.show(_notification('while reading'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Underlying action'));
      expect(taps, 1);
      showDialog<void>(
        context: navigator.currentContext!,
        builder: (_) => const AlertDialog(content: Text('Modal')),
      );
      await tester.pumpAndSettle();
      controller.show(
        _notification(
          'above dialog',
          onOpen: () {
            expect(controller.isShowing, isFalse);
            opened++;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('yo-top-notification-open')));
      await tester.pump();
      expect(opened, 1);
      expect(find.text('Modal'), findsOneWidget);
      expect(find.byKey(_cardKey), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('undersized keyboard viewport rejects and metrics wake retry', (
    tester,
  ) async {
    final controller = YoTopNotificationController();
    var ready = 0;
    await tester.pumpWidget(
      _host(
        controller,
        media: const MediaQueryData(
          size: Size(768, 320),
          viewInsets: EdgeInsets.only(bottom: 220),
          textScaler: TextScaler.linear(2),
        ),
        onReady: () => ready++,
      ),
    );
    expect(controller.show(_notification('no room')), isFalse);
    expect(controller.isShowing, isFalse);
    final before = ready;
    await tester.pumpWidget(
      _host(
        controller,
        media: const MediaQueryData(
          size: Size(768, 320),
          textScaler: TextScaler.linear(2),
        ),
        onReady: () => ready++,
      ),
    );
    await tester.pump();
    expect(ready, greaterThan(before));
    expect(find.text('no room'), findsNothing);
    expect(controller.show(_notification('explicit retry')), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('explicit retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
    controller.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'auth epoch clears notification and business SnackBar before new root',
    (tester) async {
      final controller = YoTopNotificationController();
      final navigator = GlobalKey<NavigatorState>();
      final messenger = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(
        _host(controller, navigatorKey: navigator, messengerKey: messenger),
      );
      final resetter = AuthEpochRouteResetter(
        navigatorKey: navigator,
        onPrincipalExit: () {
          controller.clear();
          clearSessionSnackBars(messenger.currentState!);
        },
        routeFactory: (_) {
          expect(controller.isShowing, isFalse);
          return PageRouteBuilder<void>(
            transitionDuration: Duration.zero,
            pageBuilder: (_, _, _) =>
                const Scaffold(body: Text('Next account')),
          );
        },
      );
      resetter.handlePrincipal('account-a');
      controller.show(_notification('Private account A'));
      messenger.currentState!.showSnackBar(
        const SnackBar(content: Text('A saved')),
      );
      await tester.pumpAndSettle();
      resetter.handlePrincipal('account-b');
      await tester.pump();
      expect(find.text('Private account A'), findsNothing);
      expect(find.text('A saved'), findsNothing);
      expect(find.text('Next account'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
