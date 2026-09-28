import 'dart:async';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/screens/reels_feed_screen.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_composition_canvas.dart';
import 'package:yovoice/features/reels/presentation/widgets/reels_toolbar.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_feed_chrome.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_overlay_atoms.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/states/yo_empty_state.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';

import 'moments_overview_test_support.dart';
import 'reel_stage_test_support.dart';

/// Y3: the Yeels chrome below the local-panel width is ONE row.
///
/// Discover: [host Back] [Głos | Yeels] … [your avatar] [+]. The avatar opens
/// "Twoje Yeels", which is a page of its own: [‹ Wróć do Odkrywaj] [Twoje
/// Yeels] … [Odśwież] [+], left by its chevron, a system Back or Escape. In
/// Discover the already selected "Yeels" tab is the refresh, and says so. The
/// row stacks when the switch cannot keep its width. From 1100 the wide
/// header and the toolbar / local panel are unchanged.
void main() {
  setUpAll(loadInterFont);
  late VoidCallback restoreIdentity;
  setUp(() => restoreIdentity = installIdentityStub());
  tearDown(() => restoreIdentity());

  const ownScope = ValueKey<String>('reels-own-scope');
  const ownBack = ValueKey<String>('reels-own-back');
  const ownTitle = ValueKey<String>('reels-own-title');
  const chromeKey = ValueKey<String>('reels-chrome');
  const scrimKey = ValueKey<String>('reels-chrome-scrim');
  const reelsTab = ValueKey<String>('yo-moments-format-reels');
  const voiceTab = ValueKey<String>('yo-moments-format-voice');
  const formatTabs = ValueKey<String>('yo-moments-format-tabs');
  const createCta = ValueKey<String>('moments-create-cta');
  const refreshKey = ValueKey<String>('reels-refresh');

  Future<void> pumpMoments(
    WidgetTester tester,
    _Feed feed, {
    Size size = const Size(390, 844),
    Locale locale = const Locale('pl'),
    bool light = false,
    double textScale = 1,
  }) async {
    useSurface(tester, size);
    await tester.pumpWidget(
      overviewHost(
        _moments(feed),
        locale: locale,
        light: light,
        textScale: textScale,
        size: size,
      ),
    );
    await settleOverview(tester);
  }

  Future<void> openOwn(WidgetTester tester) async {
    await tester.tap(find.byKey(ownScope));
    await settleOverview(tester);
  }

  group('discover row', () {
    testWidgets('the phone overlay is one row: switch, avatar, +', (
      tester,
    ) async {
      final feed = _Feed();
      await pumpMoments(tester, feed);

      // The chips and the refresh plate of the old second row are gone.
      expect(find.byKey(const ValueKey('reels-discover-filter')), findsNothing);
      expect(find.byKey(const ValueKey('reels-own-filter')), findsNothing);
      expect(find.byKey(const ValueKey('reels-refresh')), findsNothing);
      expect(find.text('Odkrywaj'), findsNothing);

      final chrome = tester.getRect(find.byKey(chromeKey));
      // One 48 px row plus the chrome's own padding (2 + 10).
      expect(chrome.height, lessThanOrEqualTo(62));
      final tabs = tester.getRect(find.byKey(formatTabs));
      final avatar = tester.getRect(find.byKey(ownScope));
      final create = tester.getRect(find.byKey(createCta));
      for (final rect in <Rect>[avatar, create]) {
        expect(rect.center.dy, closeTo(tabs.center.dy, 1));
      }
      expect(tabs.right, lessThanOrEqualTo(avatar.left));
      expect(avatar.right, lessThanOrEqualTo(create.left));
      expect(create.right, lessThanOrEqualTo(390 - 12 + .5));

      // A full target around a 32 px avatar in a 2 px white ring.
      expect(avatar.width, greaterThanOrEqualTo(48));
      expect(avatar.height, greaterThanOrEqualTo(48));
      final ring = find.byKey(const ValueKey<String>('reels-own-scope-ring'));
      expect(tester.getSize(ring), const Size.square(36));
      final decoration =
          tester.widget<Container>(ring).decoration! as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.border, Border.all(color: Colors.white, width: 2));
      final user = tester.widget<UserAvatar>(
        find.descendant(
          of: find.byKey(ownScope),
          matching: find.byType(UserAvatar),
        ),
      );
      expect(user.radius, 16);
      expect(user.userId, _viewer, reason: 'the viewer, resolved by uid');
      expect(user.displayName, 'Kamil');
      expect(user.fallbackIcon, Icons.person_rounded);
      expect(tester.takeException(), isNull);
    });

    testWidgets('RTL mirrors the row and the Back chevron', (tester) async {
      final feed = _Feed();
      useSurface(tester, const Size(390, 844));
      await tester.pumpWidget(
        overviewHost(_moments(feed), locale: const Locale('pl'), rtl: true),
      );
      await settleOverview(tester);
      final tabs = tester.getRect(find.byKey(formatTabs));
      final avatar = tester.getRect(find.byKey(ownScope));
      final create = tester.getRect(find.byKey(createCta));
      expect(create.right, lessThanOrEqualTo(avatar.left));
      expect(avatar.right, lessThanOrEqualTo(tabs.left));
      await openOwn(tester);
      final back = tester.getRect(find.byKey(ownBack));
      final title = tester.getRect(find.byKey(ownTitle));
      expect(back.left, greaterThanOrEqualTo(title.right));
      expect(back.center.dx, greaterThan(195));
      expect(tester.takeException(), isNull);
    });

    testWidgets('without a name the avatar falls back to the person glyph', (
      tester,
    ) async {
      final feed = _Feed(displayName: null);
      await pumpMoments(tester, feed);
      final user = tester.widget<UserAvatar>(
        find.descendant(
          of: find.byKey(ownScope),
          matching: find.byType(UserAvatar),
        ),
      );
      expect(user.displayName, isNull);
      expect(
        find.descendant(
          of: find.byKey(ownScope),
          matching: find.byIcon(Icons.person_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the mute plate sits right under the one-row chrome', (
      tester,
    ) async {
      final feed = _Feed();
      await pumpMoments(tester, feed);
      final chrome = tester.getRect(find.byKey(chromeKey));
      final sound = tester.getRect(find.byKey(reelSoundKey).first);
      // Anchored to the measured chrome: clear of it, and right under it.
      expect(sound.top, greaterThanOrEqualTo(chrome.bottom));
      expect(sound.top, lessThanOrEqualTo(chrome.bottom + 16));
      expect(sound.top, lessThan(80), reason: 'it moved up with the row');
    });
  });

  group('Twoje Yeels', () {
    testWidgets('the avatar opens the own pool under its own header, and '
        'the chevron returns to Discover', (tester) async {
      final feed = _Feed();
      await pumpMoments(tester, feed);
      expect(feed.scopes, <String>['discover']);

      await openOwn(tester);
      expect(feed.scopes.last, 'own');
      expect(find.byKey(ownTitle), findsOneWidget);
      expect(find.text('Twoje Yeels'), findsOneWidget);
      expect(find.byKey(ownBack), findsOneWidget);
      expect(find.byKey(formatTabs), findsNothing);
      expect(find.byKey(ownScope), findsNothing);
      expect(find.byKey(createCta), findsOneWidget, reason: 'create stays');
      expect(find.byKey(refreshKey), findsOneWidget, reason: 'own refresh');
      expect(find.text('Kamil'), findsWidgets, reason: 'the own Yeel');
      expect(find.text('Creator 1'), findsNothing);

      final back = tester.getRect(find.byKey(ownBack));
      final title = tester.getRect(find.byKey(ownTitle));
      final create = tester.getRect(find.byKey(createCta));
      expect(back.width, greaterThanOrEqualTo(44));
      expect(back.height, greaterThanOrEqualTo(44));
      expect(back.right, lessThanOrEqualTo(title.left));
      final refresh = tester.getRect(find.byKey(refreshKey));
      expect(title.center.dy, closeTo(back.center.dy, 1));
      expect(create.center.dy, closeTo(back.center.dy, 1));
      expect(refresh.center.dy, closeTo(back.center.dy, 1));
      expect(title.right, lessThanOrEqualTo(refresh.left));
      expect(refresh.right, lessThanOrEqualTo(create.left));
      expect(refresh.width, greaterThanOrEqualTo(48));
      // Switching scope never moves the stage the chrome sits on.
      expect(tester.getSize(find.byKey(chromeKey)).height, lessThan(62.5));
      final style = tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(ownTitle),
              matching: find.byType(Text),
            ),
          )
          .style!;
      expect(style.fontSize, 17);
      expect(style.fontWeight, FontWeight.w800);
      expect(style.color, Colors.white);
      expect(style.shadows, isNotEmpty);

      await tester.tap(find.byKey(ownBack));
      await settleOverview(tester);
      expect(feed.scopes.last, 'discover');
      expect(find.byKey(formatTabs), findsOneWidget);
      expect(find.byKey(ownScope), findsOneWidget);
      expect(find.byKey(ownTitle), findsNothing);
      expect(find.text('Creator 1'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the own pool keeps its empty state under the header', (
      tester,
    ) async {
      final feed = _Feed(ownCount: 0);
      await pumpMoments(tester, feed);
      await openOwn(tester);
      expect(find.byType(YoEmptyState), findsOneWidget);
      expect(find.text('Nie masz jeszcze własnych Yeels'), findsOneWidget);
      expect(find.byKey(ownTitle), findsOneWidget);
      // Not overlaid: the header stands above the state, not on it.
      expect(
        tester.getRect(find.byKey(chromeKey)).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(YoEmptyState)).top),
      );
      // Nothing to fade, and the row is drawn for the page canvas.
      expect(find.byKey(scrimKey), findsNothing);
      final palette = tester.element(find.byKey(ownTitle)).appPalette;
      final style = tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(ownTitle),
              matching: find.byType(Text),
            ),
          )
          .style!;
      expect(style.color, palette.textPrimary);
      expect(style.shadows, isNull);
      await tester.tap(find.byKey(ownBack));
      await settleOverview(tester);
      expect(find.byKey(ownScope), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the own pool keeps its error state and retry', (tester) async {
      final feed = _Feed(failOwn: true);
      await pumpMoments(tester, feed);
      await openOwn(tester);
      expect(find.byType(YoErrorState), findsOneWidget);
      expect(find.byKey(ownTitle), findsOneWidget);
      final calls = feed.scopes.length;
      await tester.tap(
        find.descendant(
          of: find.byType(YoErrorState),
          matching: find.text('Spróbuj ponownie'),
        ),
      );
      await settleOverview(tester);
      expect(feed.scopes.length, calls + 1);
      expect(feed.scopes.last, 'own');
    });

    testWidgets('system Back leaves Twoje Yeels before it leaves the route', (
      tester,
    ) async {
      final feed = _Feed();
      final navigator = GlobalKey<NavigatorState>();
      useSurface(tester, const Size(390, 844));
      await tester.pumpWidget(
        overviewHost(
          const Scaffold(body: Text('Start')),
          navigatorKey: navigator,
          locale: const Locale('pl'),
        ),
      );
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => _moments(feed, isRootTab: false),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await settleOverview(tester);

      // Pushed: the host's Back plate leads the discover row.
      final routeBack = find.byTooltip('Wstecz');
      expect(routeBack, findsOneWidget);
      await openOwn(tester);
      expect(find.byTooltip('Wstecz'), findsNothing);

      await tester.binding.handlePopRoute();
      await settleOverview(tester);
      expect(find.byKey(ownScope), findsOneWidget, reason: 'back to Discover');
      expect(feed.scopes.last, 'discover');
      expect(find.text('Start'), findsNothing, reason: 'the route stayed');

      // Discover claims nothing: the next Back is the route's.
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Start'), findsOneWidget);
      expect(find.byType(MomentsScreen), findsNothing);
    });

    testWidgets('the pushed route keeps its own Back plate in Discover', (
      tester,
    ) async {
      final feed = _Feed();
      final navigator = GlobalKey<NavigatorState>();
      useSurface(tester, const Size(390, 844));
      await tester.pumpWidget(
        overviewHost(
          const Scaffold(body: Text('Start')),
          navigatorKey: navigator,
          locale: const Locale('pl'),
        ),
      );
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => _moments(feed, isRootTab: false),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await settleOverview(tester);
      final back = tester.getRect(find.byTooltip('Wstecz'));
      final tabs = tester.getRect(find.byKey(formatTabs));
      expect(back.right, lessThanOrEqualTo(tabs.left));
      await tester.tap(find.byTooltip('Wstecz'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('Escape inside Twoje Yeels returns to Discover', (
      tester,
    ) async {
      final feed = _Feed();
      await pumpMoments(tester, feed);
      await openOwn(tester);
      Focus.of(
        tester.element(
          find.descendant(
            of: find.byKey(ownBack),
            matching: find.byType(OverlayPlate),
          ),
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleOverview(tester);
      expect(find.byKey(ownScope), findsOneWidget);
      expect(feed.scopes.last, 'discover');
    });

    testWidgets('a hidden feed claims no Back', (tester) async {
      // The shell hides the destination (another tab is showing) while the
      // own pool is open: Back belongs to whatever is on screen now.
      final feed = _Feed();
      final visible = ValueNotifier<bool>(true);
      addTearDown(visible.dispose);
      final navigator = GlobalKey<NavigatorState>();
      useSurface(tester, const Size(390, 844));
      await tester.pumpWidget(
        overviewHost(
          const Scaffold(body: Text('Start')),
          navigatorKey: navigator,
          locale: const Locale('pl'),
        ),
      );
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: ReelsFeedScreen(
                embedded: true,
                immersive: true,
                isVisible: visible,
                service: feed.service,
                videoBuilder: _footage,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await settleOverview(tester);
      await openOwn(tester);

      visible.value = false;
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Start'), findsOneWidget);
      expect(find.byType(ReelsFeedScreen), findsNothing);
    });

    testWidgets('a visible own pool claims Back again when it returns', (
      tester,
    ) async {
      final feed = _Feed();
      final visible = ValueNotifier<bool>(true);
      addTearDown(visible.dispose);
      final navigator = GlobalKey<NavigatorState>();
      useSurface(tester, const Size(390, 844));
      await tester.pumpWidget(
        overviewHost(
          const Scaffold(body: Text('Start')),
          navigatorKey: navigator,
          locale: const Locale('pl'),
        ),
      );
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: ReelsFeedScreen(
                embedded: true,
                immersive: true,
                isVisible: visible,
                service: feed.service,
                videoBuilder: _footage,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await settleOverview(tester);
      await openOwn(tester);
      visible.value = false;
      await tester.pump();
      visible.value = true;
      await tester.pump();
      await tester.binding.handlePopRoute();
      await settleOverview(tester);
      expect(find.byKey(ownScope), findsOneWidget);
      expect(find.text('Start'), findsNothing);
    });
  });

  group('refresh', () {
    testWidgets('the selected Yeels tab reads the pool again, once per load', (
      tester,
    ) async {
      final feed = _Feed();
      await pumpMoments(tester, feed);
      expect(feed.scopes, <String>['discover']);

      final gate = feed.gate = Completer<void>();
      await tester.tap(find.byKey(reelsTab));
      await tester.pump();
      expect(feed.scopes, <String>['discover', 'discover']);
      expect(find.text('Ładowanie Yeels'), findsOneWidget);

      // A second activation while that load runs is not a second request.
      await tester.tap(find.byKey(reelsTab));
      await tester.pump();
      expect(feed.scopes.length, 2);

      feed.gate = null;
      gate.complete();
      await settleOverview(tester);
      expect(find.text('Creator 1'), findsWidgets);
      // Still Yeels: re-selecting is not a format change.
      expect(find.byKey(ownScope), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('assistive technology hears the refresh and can use it', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        final feed = _Feed();
        await pumpMoments(tester, feed);
        final node = tester.getSemantics(find.byKey(reelsTab));
        final data = node.getSemanticsData();
        expect(data.label, 'Yeels');
        expect(data.hint, 'Odśwież');
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await settleOverview(tester);
        expect(feed.scopes, <String>['discover', 'discover']);

        // The unselected Głos tab is a plain format choice.
        final voice = tester
            .getSemantics(find.byKey(voiceTab))
            .getSemanticsData();
        expect(voice.hint, isEmpty);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('a standalone immersive feed with no format switch keeps a '
        'refresh plate on its one row', (tester) async {
      final players = FakeReelPlayers();
      final calls = <String>[];
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(390, 844),
        immersive: true,
        onCreate: () async {},
        service: reelStageService(calls: calls),
      );
      final refresh = find.byKey(const ValueKey('reels-refresh'));
      expect(refresh, findsOneWidget);
      expect(find.byKey(ownScope), findsOneWidget);
      final chrome = tester.getRect(find.byKey(chromeKey));
      expect(chrome.height, lessThanOrEqualTo(62));
      final before = calls.where((name) => name == 'listReelsV2').length;
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(calls.where((name) => name == 'listReelsV2').length, before + 1);
    });
  });

  group('semantics and focus', () {
    testWidgets('Polish labels, roles and actions', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final feed = _Feed();
        await pumpMoments(tester, feed);
        final avatar = tester.getSemantics(_buttonNode(ownScope));
        final data = avatar.getSemanticsData();
        expect(data.label, 'Twoje Yeels');
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(
          find.byTooltip('Twoje Yeels'),
          findsOneWidget,
          reason: 'a pointer reader gets the name too',
        );

        await openOwn(tester);
        final back = tester
            .getSemantics(_buttonNode(ownBack))
            .getSemanticsData();
        expect(back.label, 'Wróć do Odkrywaj');
        expect(back.flagsCollection.isButton, isTrue);
        expect(back.hasAction(SemanticsAction.tap), isTrue);
        final title = tester
            .getSemantics(find.byKey(ownTitle))
            .getSemanticsData();
        expect(title.label, 'Twoje Yeels');
        expect(title.flagsCollection.isHeader, isTrue);
        expect(title.headingLevel, 1);
        expect(title.flagsCollection.isButton, isFalse);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('English labels', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final feed = _Feed();
        await pumpMoments(tester, feed, locale: const Locale('en'));
        expect(
          tester.getSemantics(_buttonNode(ownScope)).getSemanticsData().label,
          'Your Yeels',
        );
        expect(
          tester.getSemantics(find.byKey(reelsTab)).getSemanticsData().hint,
          'Refresh',
        );
        await openOwn(tester);
        expect(
          tester.getSemantics(_buttonNode(ownBack)).getSemanticsData().label,
          'Back to Discover',
        );
        expect(find.text('Your Yeels'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('Tab walks Głos, Yeels, the avatar, then +; the keyboard '
        'crosses between the scopes without losing focus', (tester) async {
      final feed = _Feed();
      await pumpMoments(tester, feed);
      const watched = <String>[
        'yo-moments-format-voice',
        'yo-moments-format-reels',
        'reels-own-scope',
        'moments-create-cta',
        'reels-own-back',
        'reels-refresh',
      ];
      final order = <String>[];
      for (var i = 0; i < 12 && order.length < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final owner = _focusedKey(watched);
        if (owner != null && (order.isEmpty || order.last != owner)) {
          order.add(owner);
        }
      }
      expect(order, <String>[
        'yo-moments-format-voice',
        'yo-moments-format-reels',
        'reels-own-scope',
        'moments-create-cta',
      ]);

      // Back to the avatar, and open the pool from the keyboard.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(_focusedKey(watched), 'reels-own-scope');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleOverview(tester);
      expect(find.byKey(ownTitle), findsOneWidget);
      expect(_focusedKey(watched), 'reels-own-back');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focusedKey(watched), 'reels-refresh');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focusedKey(watched), 'moments-create-cta');
      for (var i = 0; i < 2; i++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
        await tester.pump();
      }
      expect(_focusedKey(watched), 'reels-own-back');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleOverview(tester);
      expect(find.byKey(ownScope), findsOneWidget);
      expect(_focusedKey(watched), 'reels-own-scope');
    });

    testWidgets('a Yeel that expires under keyboard focus hands focus to the '
        'avatar', (tester) async {
      // The service drops an already expired Yeel against the real clock,
      // so the fixture's deadline is real-time too.
      var now = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().toUtc().millisecondsSinceEpoch,
        isUtc: true,
      );
      final deadline = now.add(const Duration(minutes: 1));
      final timers = <_FakeTimer>[];
      final players = FakeReelPlayers();
      final service = ReelService(
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: _viewer, isEmailVerified: true),
        ),
        callableInvoker: (name, payload) async {
          if (name == 'listReelsV2') {
            return <Object?, Object?>{
              'schemaVersion': 2,
              'items': <Object?>[
                reelWire(1)
                  ..['availability'] = <String, Object?>{
                    'schemaVersion': 2,
                    'availabilityHours': 24,
                    'expiresAtMillis': deadline.millisecondsSinceEpoch,
                  },
                reelWire(2),
              ],
              'nextCursor': null,
            };
          }
          return _grant(name, payload);
        },
      );
      useSurface(tester, const Size(390, 844));
      await tester.pumpWidget(
        _plainHost(
          ReelsFeedScreen(
            embedded: true,
            immersive: true,
            service: service,
            now: () => now,
            expiryTimerFactory: (_, callback) {
              final timer = _FakeTimer(callback);
              timers.add(timer);
              return timer;
            },
            videoPlaybackFactory: (uri, reel) => players.of(reel.id),
            audioPlaybackFactory: FakeReelAudioPlayback.new,
            videoBuilder: _footage,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final like = find
          .descendant(
            of: find.byKey(reelLikeKey).first,
            matching: find.byType(Icon),
          )
          .first;
      Focus.of(tester.element(like)).requestFocus();
      await tester.pump();
      expect(
        _focusedKey(const <String>['reel-like-action']),
        'reel-like-action',
      );

      now = deadline;
      timers.last.fire();
      await tester.pump();
      await tester.pump();
      expect(find.text('Creator 1'), findsNothing);
      expect(_focusedKey(const <String>['reels-own-scope']), 'reels-own-scope');
    });
  });

  group('refresh in both scopes', () {
    for (final width in const <double>[390, 768]) {
      testWidgets('Twoje Yeels at ${width.toInt()} px has its own Odśwież, '
          'which reads the own pool once', (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final feed = _Feed();
          await pumpMoments(tester, feed, size: Size(width, 1024));
          await openOwn(tester);
          final before = feed.scopes.length;
          final node = tester.getSemantics(_buttonNode(refreshKey));
          final data = node.getSemanticsData();
          expect(data.label, 'Odśwież');
          expect(data.flagsCollection.isButton, isTrue);
          expect(data.hasAction(SemanticsAction.tap), isTrue);
          node.owner!.performAction(node.id, SemanticsAction.tap);
          await settleOverview(tester);
          expect(feed.scopes.sublist(before), <String>['own']);
          expect(find.byKey(ownTitle), findsOneWidget, reason: 'still own');
        } finally {
          semantics.dispose();
        }
      });
    }

    testWidgets('in Discover the selected Yeels tab carries an Odśwież '
        'tooltip; Głos does not', (tester) async {
      final feed = _Feed();
      await pumpMoments(tester, feed);
      final tip = find.byTooltip('Odśwież');
      expect(tip, findsOneWidget);
      expect(
        find.descendant(of: find.byKey(reelsTab), matching: tip),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(voiceTab), matching: tip),
        findsNothing,
      );
      // The tooltip is the pointer's cue only; the spoken hint stays single.
      final semantics = tester.ensureSemantics();
      try {
        expect(
          tester.getSemantics(find.byKey(reelsTab)).getSemanticsData().hint,
          'Odśwież',
        );
      } finally {
        semantics.dispose();
      }
    });
  });

  group('scope switch lands focus and speech', () {
    testWidgets('a screen reader activation lands on the counterpart and '
        'names the new page', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final semantics = tester.ensureSemantics();
      try {
        final feed = _Feed();
        await pumpMoments(tester, feed);
        tester.takeAnnouncements();
        final avatar = tester.getSemantics(_buttonNode(ownScope));
        avatar.owner!.performAction(avatar.id, SemanticsAction.tap);
        await settleOverview(tester);
        expect(find.byKey(ownTitle), findsOneWidget);
        expect(_focusedKey(const <String>['reels-own-back']), 'reels-own-back');
        expect(
          tester.takeAnnouncements().map((a) => a.message),
          contains('Twoje Yeels'),
        );

        final back = tester.getSemantics(_buttonNode(ownBack));
        back.owner!.performAction(back.id, SemanticsAction.tap);
        await settleOverview(tester);
        expect(find.byKey(ownScope), findsOneWidget);
        expect(
          _focusedKey(const <String>['reels-own-scope']),
          'reels-own-scope',
        );
        expect(
          tester.takeAnnouncements().map((a) => a.message),
          contains('Odkrywaj'),
        );
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('English names the pages in English', (tester) async {
      final feed = _Feed();
      await pumpMoments(tester, feed, locale: const Locale('en'));
      tester.takeAnnouncements();
      await openOwn(tester);
      expect(
        tester.takeAnnouncements().map((a) => a.message),
        contains('Your Yeels'),
      );
      await tester.tap(find.byKey(ownBack));
      await settleOverview(tester);
      expect(
        tester.takeAnnouncements().map((a) => a.message),
        contains('Discover'),
      );
    });

    testWidgets('Escape from a Yeel control in Twoje Yeels lands on the '
        'avatar, not on the route', (tester) async {
      final feed = _Feed();
      await pumpMoments(tester, feed);
      await openOwn(tester);
      final like = find
          .descendant(
            of: find.byKey(reelLikeKey).first,
            matching: find.byType(Icon),
          )
          .first;
      Focus.of(tester.element(like)).requestFocus();
      await tester.pump();
      expect(
        _focusedKey(const <String>['reel-like-action']),
        'reel-like-action',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleOverview(tester);
      expect(find.byKey(ownScope), findsOneWidget);
      expect(_focusedKey(const <String>['reels-own-scope']), 'reels-own-scope');
    });

    testWidgets('a mouse click keeps focus in the feed without a ring, and '
        'Escape still returns to Discover', (tester) async {
      final feed = _Feed();
      await pumpMoments(tester, feed);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byKey(ownScope)));
      await mouse.down(tester.getCenter(find.byKey(ownScope)));
      await mouse.up();
      await settleOverview(tester);
      expect(find.byKey(ownTitle), findsOneWidget);
      // A mouse is a traditional-focus pointer: the chevron takes focus.
      expect(_focusedKey(const <String>['reels-own-back']), 'reels-own-back');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleOverview(tester);
      expect(find.byKey(ownScope), findsOneWidget);
      expect(feed.scopes.last, 'discover');
    });

    testWidgets('a finger tap moves focus into the feed but paints no ring '
        'on the chevron it did not touch', (tester) async {
      final feed = _Feed();
      await pumpMoments(tester, feed);
      await openOwn(tester);
      expect(FocusManager.instance.highlightMode, FocusHighlightMode.touch);
      final focus = FocusManager.instance.primaryFocus;
      expect(focus?.debugLabel, 'Yeels: feed');
      expect(_focusedKey(const <String>['reels-own-back']), isNull);
      // Escape (a hardware keyboard on a tablet) still works from here.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleOverview(tester);
      expect(find.byKey(ownScope), findsOneWidget);
    });
  });

  testWidgets('a refresh after paging lands on the first Yeel, and that '
      'Yeel is the active one', (tester) async {
    final feed = _Feed();
    await pumpMoments(tester, feed);
    await tester.fling(find.byType(PageView), const Offset(0, -600), 2000);
    await settleOverview(tester);
    await tester.pump(const Duration(milliseconds: 500));
    final second = tester
        .widgetList<ReelCard>(find.byType(ReelCard))
        .firstWhere((card) => card.isActive);
    expect(second.reel.id, 'reel_2');

    await tester.tap(find.byKey(reelsTab));
    await settleOverview(tester);
    await tester.pump(const Duration(milliseconds: 500));
    final view = tester.getRect(find.byType(PageView));
    final visible = tester.widgetList<ReelCard>(find.byType(ReelCard)).where((
      card,
    ) {
      final rect = tester.getRect(find.byWidget(card));
      return rect.center.dy > view.top && rect.center.dy < view.bottom;
    }).toList();
    expect(visible, hasLength(1));
    expect(visible.single.reel.id, 'reel_1');
    expect(visible.single.isActive, isTrue);
  });

  testWidgets('Twoje Yeels survives the create round trip', (tester) async {
    final feed = _Feed();
    await pumpMoments(tester, feed);
    await openOwn(tester);
    await tester.tap(find.byKey(createCta));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('create-reel-choice')));
    await tester.pumpAndSettle();
    await settleOverview(tester);
    expect(find.byKey(ownTitle), findsOneWidget);
    expect(find.byKey(ownScope), findsNothing);
    expect(feed.scopes.last, 'own', reason: 'the re-created feed reads own');
  });

  group('stacked row order and width', () {
    testWidgets('at 200 % on a 320 px phone, screen reader and Tab both read '
        'the stacked row top line first', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final feed = _Feed();
        await pumpMoments(
          tester,
          feed,
          size: const Size(320, 640),
          textScale: 2,
        );
        const labels = <String>['Twoje Yeels', 'UTWÓRZ', 'Głos', 'Yeels'];
        final spoken = tester.semantics
            .simulatedAccessibilityTraversal()
            .map((node) => node.label)
            .where(labels.contains)
            .toList();
        expect(spoken, labels);

        const watched = <String>[
          'reels-own-scope',
          'moments-create-cta',
          'yo-moments-format-voice',
          'yo-moments-format-reels',
        ];
        final tabbed = <String>[];
        for (var i = 0; i < 12 && tabbed.length < 4; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          final owner = _focusedKey(watched);
          if (owner != null && !tabbed.contains(owner)) tabbed.add(owner);
        }
        expect(tabbed, watched);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('pushed at 320 px, the row stacks rather than cut "Yeels"', (
      tester,
    ) async {
      final feed = _Feed();
      final navigator = GlobalKey<NavigatorState>();
      useSurface(tester, const Size(320, 640));
      await tester.pumpWidget(
        overviewHost(
          const Scaffold(body: Text('Start')),
          navigatorKey: navigator,
          locale: const Locale('pl'),
          size: const Size(320, 640),
        ),
      );
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => _moments(feed, isRootTab: false),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await settleOverview(tester);
      for (final word in <Finder>[find.text('Głos'), find.text('Yeels')]) {
        final paragraph = tester.renderObject<RenderParagraph>(word);
        expect(paragraph.didExceedMaxLines, isFalse, reason: '$word');
        final rect = tester.getRect(word);
        expect(rect.right, lessThanOrEqualTo(320.5), reason: '$word');
      }
      final back = tester.getRect(find.byTooltip('Wstecz'));
      final avatar = tester.getRect(find.byKey(ownScope));
      final tabs = tester.getRect(find.byKey(formatTabs));
      expect(avatar.center.dy, closeTo(back.center.dy, 1));
      expect(tabs.top, greaterThanOrEqualTo(back.bottom), reason: 'stacked');
      expect(tester.takeException(), isNull);
    });

    testWidgets('where the switch fits, the row stays one line', (
      tester,
    ) async {
      for (final width in const <double>[320, 390]) {
        final feed = _Feed();
        await pumpMoments(tester, feed, size: Size(width, 640));
        final tabs = tester.getRect(find.byKey(formatTabs));
        final avatar = tester.getRect(find.byKey(ownScope));
        expect(avatar.center.dy, closeTo(tabs.center.dy, 1), reason: '$width');
      }
    });
  });

  group('the row on the page canvas', () {
    testWidgets('768 px Pearl draws the whole row in palette roles', (
      tester,
    ) async {
      final feed = _Feed();
      await pumpMoments(tester, feed, size: const Size(768, 1024), light: true);
      final palette = tester.element(find.byKey(chromeKey)).appPalette;
      final switcher = tester.widget<ImmersiveSegmentedSwitch>(
        find.byKey(formatTabs),
      );
      expect(switcher.onCanvas, isTrue);
      final disc = tester.widget<OverlayBrandDiscButton>(find.byKey(createCta));
      expect(disc.onMedia, isFalse);
      final ring =
          tester
                  .widget<Container>(
                    find.byKey(const ValueKey<String>('reels-own-scope-ring')),
                  )
                  .decoration!
              as BoxDecoration;
      expect(ring.border, Border.all(color: palette.hairlineControl));
      expect(ring.boxShadow, isNull);

      await openOwn(tester);
      final title = tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(ownTitle),
              matching: find.byType(Text),
            ),
          )
          .style!;
      expect(title.color, palette.textPrimary);
      expect(title.shadows, isNull);
      final back = tester.widget<OverlayPlateButton>(
        find.descendant(
          of: find.byKey(ownBack),
          matching: find.byType(OverlayPlateButton),
        ),
      );
      expect(back.glyphColor, palette.textPrimary);
      expect(back.plateColor, Colors.transparent);
      expect(
        find.byKey(const ValueKey<String>('reels-refresh-ring')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('over a Yeel the same row keeps the media plates', (
      tester,
    ) async {
      final feed = _Feed();
      await pumpMoments(tester, feed, light: true);
      expect(
        tester
            .widget<ImmersiveSegmentedSwitch>(find.byKey(formatTabs))
            .onCanvas,
        isFalse,
      );
      expect(
        tester.widget<OverlayBrandDiscButton>(find.byKey(createCta)).onMedia,
        isTrue,
      );
      await openOwn(tester);
      final back = tester.widget<OverlayPlateButton>(
        find.descendant(
          of: find.byKey(ownBack),
          matching: find.byType(OverlayPlateButton),
        ),
      );
      expect(back.plateColor, isNull, reason: 'the media plate');
      expect(
        find.byKey(const ValueKey<String>('reels-refresh-ring')),
        findsNothing,
      );
    });
  });

  group('text size, contrast and widths', () {
    for (final width in const <double>[320, 390]) {
      for (final own in const <bool>[false, true]) {
        testWidgets('200 % text at ${width.toInt()} px keeps '
            '${own ? 'Twoje Yeels' : 'Discover'} whole', (tester) async {
          final feed = _Feed();
          await pumpMoments(tester, feed, size: Size(width, 844), textScale: 2);
          if (own) await openOwn(tester);
          expect(tester.takeException(), isNull);
          final words = own
              ? <Finder>[find.text('Twoje Yeels')]
              : <Finder>[find.text('Głos'), find.text('Yeels')];
          for (final word in words) {
            final paragraph = tester.renderObject<RenderParagraph>(word);
            expect(paragraph.didExceedMaxLines, isFalse, reason: '$word');
            final rect = tester.getRect(word);
            expect(rect.left, greaterThanOrEqualTo(-.5), reason: '$word');
            expect(rect.right, lessThanOrEqualTo(width + .5), reason: '$word');
          }
          for (final key in <Key>[own ? ownBack : ownScope, createCta]) {
            final rect = tester.getRect(find.byKey(key));
            expect(rect.left, greaterThanOrEqualTo(-.5), reason: '$key');
            expect(rect.right, lessThanOrEqualTo(width + .5), reason: '$key');
            expect(rect.height, greaterThanOrEqualTo(44), reason: '$key');
          }
          // The chrome may wrap, and the mute plate still clears it.
          final chrome = tester.getRect(find.byKey(chromeKey));
          final sound = find.byKey(reelSoundKey);
          if (sound.evaluate().isNotEmpty) {
            expect(tester.getRect(sound.first).top, greaterThan(chrome.bottom));
          }
          // The fade follows the measured chrome, wrapped or not (a global
          // rect: the media canvas is scaled to the phone's width).
          expect(
            tester.getRect(find.byKey(scrimKey).first).height,
            closeTo(chrome.height + 70, .5),
          );
        });
      }
    }

    testWidgets('a scrim that fades to nothing keeps the phone chrome '
        'legible in both appearances', (tester) async {
      for (final light in const <bool>[false, true]) {
        final feed = _Feed();
        await pumpMoments(tester, feed, light: light);
        final chrome = tester.getRect(find.byKey(chromeKey));
        final scrim = find.byKey(scrimKey).first;
        final rect = tester.getRect(scrim);
        expect(rect.top, 0);
        expect(rect.height, closeTo(chrome.height + 70, .5));
        // It lives in the Yeel's MEDIA layer: the composition canvas holds
        // it, and none of the card's controls — the sound plate, the rail,
        // the footer — is inside that layer, so nothing the reader can
        // focus or press is ever painted under the fade.
        final media = find.ancestor(
          of: scrim,
          matching: find.byType(ReelCompositionCanvas),
        );
        expect(media, findsOneWidget);
        for (final control in <Key>[reelSoundKey, reelLikeKey, reelMoreKey]) {
          expect(
            find.descendant(of: media, matching: find.byKey(control)),
            findsNothing,
            reason: '$control',
          );
        }
        final sound = tester.getRect(find.byKey(reelSoundKey).first);
        expect(rect.overlaps(sound), isTrue, reason: 'the case this guards');
        final gradient =
            (tester.widget<DecoratedBox>(scrim).decoration as BoxDecoration)
                    .gradient!
                as LinearGradient;
        // Theme-invariant black: 42 % at the top, easing out to fully
        // transparent at the bottom, never darker further down.
        expect(gradient.colors.first, const Color(0x6B000000));
        expect(gradient.colors.last.a, 0);
        for (var i = 0; i < gradient.colors.length; i++) {
          final color = gradient.colors[i];
          expect(color.r + color.g + color.b, 0, reason: 'pure black');
          if (i > 0) {
            expect(color.a, lessThan(gradient.colors[i - 1].a));
          }
        }
        expect(gradient.begin, Alignment.topCenter);
        expect(gradient.end, Alignment.bottomCenter);
        // Painted behind the chrome and never in the way of a tap.
        expect(
          find.ancestor(of: scrim, matching: find.byType(IgnorePointer)),
          findsWidgets,
        );
      }
    });

    testWidgets('high contrast trades the fade for a solid band behind the '
        'row, and a solid edge around the avatar ring', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final feed = _Feed();
      await pumpMoments(tester, feed);
      final chrome = tester.getRect(find.byKey(chromeKey));
      final scrim = find.byKey(scrimKey).first;
      expect(tester.getRect(scrim).height, closeTo(chrome.height, .5));
      final decoration =
          tester.widget<DecoratedBox>(scrim).decoration as BoxDecoration;
      expect(decoration.gradient, isNull);
      expect(decoration.color, overlayPlateColor);
      final ring =
          tester
                  .widget<Container>(
                    find.byKey(const ValueKey<String>('reels-own-scope-ring')),
                  )
                  .decoration!
              as BoxDecoration;
      expect(ring.boxShadow!.single.color, Colors.black);
      await openOwn(tester);
      expect(
        tester.getRect(find.byKey(scrimKey).first).height,
        closeTo(chrome.height, .5),
      );
    });

    testWidgets('600-1099: the same one row stands above the card, with no '
        'scrim', (tester) async {
      for (final width in const <double>[600, 768, 1024]) {
        final feed = _Feed();
        await pumpMoments(tester, feed, size: Size(width, 1024));
        final chrome = tester.getRect(find.byKey(chromeKey));
        expect(chrome.height, lessThanOrEqualTo(62), reason: '$width');
        expect(find.byKey(ownScope), findsOneWidget);
        expect(find.byKey(const ValueKey('reels-own-filter')), findsNothing);
        expect(find.byKey(scrimKey), findsNothing);
        final viewport = tester.getRect(
          find.byKey(const ValueKey('reel-viewport')).first,
        );
        expect(viewport.top, greaterThanOrEqualTo(chrome.bottom));
        await openOwn(tester);
        expect(find.byKey(ownTitle), findsOneWidget);
        expect(find.byKey(refreshKey), findsOneWidget);
        expect(feed.scopes.last, 'own');
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('from 1100 the wide header, toolbar and panel are unchanged', (
      tester,
    ) async {
      for (final width in const <double>[1100, 1280, 1440]) {
        final feed = _Feed();
        await pumpMoments(tester, feed, size: Size(width, 900));
        expect(find.byKey(ownScope), findsNothing, reason: '$width');
        expect(find.byKey(ownBack), findsNothing);
        expect(find.byKey(scrimKey), findsNothing);
        expect(
          find.byKey(const ValueKey('reels-discover-filter')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('reels-own-filter')), findsOneWidget);
        expect(find.byKey(const ValueKey('reels-refresh')), findsOneWidget);
        final panel = find.byKey(const ValueKey('yo-moments-local-panel'));
        expect(
          panel.evaluate().isNotEmpty ||
              find.byType(ReelsToolbar).evaluate().isNotEmpty,
          isTrue,
        );
        // The pool is a filter here, as before: no header, no Back.
        await tester.tap(find.byKey(const ValueKey('reels-own-filter')));
        await settleOverview(tester);
        expect(feed.scopes.last, 'own');
        expect(find.byKey(ownTitle), findsNothing);
        expect(tester.takeException(), isNull);
      }
    });
  });
}

const _viewer = 'viewer';

Widget _footage(BuildContext context, Uri uri, Object reel) =>
    const ColoredBox(color: Color(0xFFEFE6DA));

/// YO Moments on Yeels, with the Voice half's doubles so switching format
/// never reaches Firebase. A fresh key per pump: a loop that pumps twice
/// must not inherit the previous pool or scope.
Widget _moments(_Feed feed, {bool isRootTab = true}) {
  final auth = authAs(_viewer);
  return MomentsScreen(
    key: UniqueKey(),
    isRootTab: isRootTab,
    initialFormat: YoMomentsFormat.reels,
    auth: auth,
    discoveryService: StaticDiscovery(populatedPool()),
    feedService: QuietFeed(firestore: fakeFirestore(), auth: auth),
    viewsService: StaticViews(const <String>{}),
    playerFactory: SilentPlayer.new,
    reelService: feed.service,
    reelVideoBuilder: _footage,
    onCreateReel: () async {},
  );
}

/// The real service over a scripted transport, recording which pool every
/// feed request asked for.
class _Feed {
  _Feed({this.ownCount = 1, this.displayName = 'Kamil', this.failOwn = false});

  final int ownCount;
  final String? displayName;
  final bool failOwn;
  final List<String> scopes = <String>[];

  /// Holds the next feed responses open while set.
  Completer<void>? gate;

  late final ReelService service = ReelService(
    auth: MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
        uid: _viewer,
        displayName: displayName,
        isEmailVerified: true,
      ),
    ),
    callableInvoker: (name, payload) async {
      if (name != 'listReelsV2') return _grant(name, payload);
      final own = payload['scope'] == 'own';
      scopes.add(own ? 'own' : 'discover');
      final hold = gate;
      if (hold != null) await hold.future;
      if (own && failOwn) {
        throw StateError('The own pool is unavailable.');
      }
      return <String, Object?>{
        'schemaVersion': 2,
        'items': own
            ? <Object?>[
                for (var i = 1; i <= ownCount; i++)
                  reelWire(
                    10 + i,
                    authorId: _viewer,
                    sameAuthor: true,
                    authorName: 'Kamil',
                  ),
              ]
            : <Object?>[reelWire(1), reelWire(2)],
        'nextCursor': null,
      };
    },
  );
}

Future<Map<Object?, Object?>> _grant(
  String name,
  Map<String, Object?> payload,
) async {
  if (name == 'getReelMediaAccessV2') {
    return <Object?, Object?>{
      'schemaVersion': 2,
      'url': 'https://storage.googleapis.com/yovoice/${payload['reelId']}.mp4',
      'expiresAtMillis': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 5))
          .millisecondsSinceEpoch,
      'generation': '7',
      'availabilityHours': 'permanent',
      'contentExpiresAtMillis': null,
    };
  }
  throw StateError('Unexpected callable $name with $payload');
}

/// The control's own button node: the [Semantics] inside the keyed control
/// that carries the button role (the tooltip wraps the control in a
/// semantics widget of its own, which owns no labelled node).
Finder _buttonNode(Key key) => find
    .descendant(
      of: find.byKey(key),
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.button == true,
      ),
    )
    .first;

/// The key of the watched control that owns primary focus, if any.
String? _focusedKey(List<String> watched) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  String? found;
  context.visitAncestorElements((element) {
    final key = element.widget.key;
    if (key is ValueKey<String> && watched.contains(key.value)) {
      found = key.value;
      return false;
    }
    return true;
  });
  return found;
}

Widget _plainHost(Widget child) => MaterialApp(
  theme: AppTheme.darkTheme,
  locale: const Locale('pl'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

class _FakeTimer implements Timer {
  _FakeTimer(this._callback);

  final void Function() _callback;
  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick = 1;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}
