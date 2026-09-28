import 'dart:async';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/data/services/yeels_posted_flag.dart';
import 'package:yovoice/features/reels/presentation/widgets/yeels_create_invitation.dart';
import 'package:yovoice/shared/widgets/buttons/yo_create_ring_button.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';

import 'moments_overview_test_support.dart';
import 'reel_stage_test_support.dart';

/// ADR-229: the Yeels / Głos create `+` is a gradient RING (the owner's
/// variant B), and on Yeels it sends a bounded invitation echo: about 3 s
/// into a visit, then every ~40 s, at most three per visit, never on Głos,
/// never once the viewer has posted a Yeel, never under Reduce Motion, high
/// contrast or while disabled.
void main() {
  const createCta = ValueKey<String>('moments-create-cta');
  const faceKey = ValueKey<String>('yo-create-ring-face');
  const glassKey = ValueKey<String>('yo-create-ring-glass');
  const shadowKey = ValueKey<String>('yo-create-ring-shadow');
  const hoverKey = ValueKey<String>('yo-create-ring-hover');
  const echoKey = ValueKey<String>('yo-create-ring-echo');

  Widget host(
    Widget child, {
    bool light = false,
    bool highContrast = false,
    bool disableAnimations = false,
    bool accessibleNavigation = false,
  }) => MaterialApp(
    theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        highContrast: highContrast,
        disableAnimations: disableAnimations,
        accessibleNavigation: accessibleNavigation,
      ),
      child: child!,
    ),
    home: Scaffold(body: Center(child: child)),
  );

  YoCreateRingPainter ringPainter(WidgetTester tester) =>
      tester.widget<CustomPaint>(find.byKey(faceKey)).painter!
          as YoCreateRingPainter;
  YoCreatePlusPainter plusPainter(WidgetTester tester) =>
      tester.widget<CustomPaint>(find.byKey(faceKey)).foregroundPainter!
          as YoCreatePlusPainter;
  CustomPaint echoPaint(WidgetTester tester) =>
      tester.widget<CustomPaint>(find.byKey(echoKey));
  double? echoT(WidgetTester tester) =>
      (echoPaint(tester).painter! as YoCreateEchoPainter).t;
  Finder buttonNode() => find
      .descendant(
        of: find.byKey(createCta),
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.button == true,
        ),
      )
      .first;
  Color glassColor(WidgetTester tester) =>
      tester.widget<ColoredBox>(find.byKey(glassKey)).color;

  group('the ring', () {
    testWidgets('a 40 px ring centred in the 48 px target', (tester) async {
      await tester.pumpWidget(
        host(
          YoCreateRingButton(
            key: createCta,
            semanticLabel: 'UTWÓRZ',
            onTap: () {},
          ),
        ),
      );
      final target = tester.getRect(find.byKey(createCta));
      final face = tester.getRect(find.byKey(faceKey));
      expect(target.size, const Size(48, 48));
      expect(face.size, const Size(40, 40));
      expect(face.center, target.center);
      expect(YoCreateRingButton.ringWidth, 2);
      expect(YoCreateRingButton.glyphSpan, 16);
      expect(YoCreateRingButton.glyphStroke, 2.6);
      expect(ringPainter(tester).enabled, isTrue);
      expect(tester.takeException(), isNull);
    });

    for (final light in <bool>[false, true]) {
      final name = light ? 'Pearl' : 'Dark';
      testWidgets('$name: over media — .28 glass, contact shadow, white +', (
        tester,
      ) async {
        await tester.pumpWidget(
          host(
            YoCreateRingButton(semanticLabel: 'UTWÓRZ', onTap: () {}),
            light: light,
          ),
        );
        expect(glassColor(tester), Colors.black.withValues(alpha: .28));
        final shadow =
            tester.widget<DecoratedBox>(find.byKey(shadowKey)).decoration
                as BoxDecoration;
        expect(shadow.boxShadow!.single.color, const Color(0x2E000000));
        expect(plusPainter(tester).color, Colors.white);
        expect(ringPainter(tester).outerHairline, isNull);
      });

      testWidgets('$name: on the canvas — clear, no shadow, textPrimary +', (
        tester,
      ) async {
        await tester.pumpWidget(
          host(
            YoCreateRingButton(
              semanticLabel: 'UTWÓRZ',
              onTap: () {},
              onMedia: false,
            ),
            light: light,
          ),
        );
        final palette = light ? AppPalette.light : AppPalette.dark;
        expect(find.byKey(glassKey), findsNothing);
        expect(find.byKey(shadowKey), findsNothing);
        expect(find.byKey(hoverKey), findsNothing);
        expect(plusPainter(tester).color, palette.textPrimary);
      });
    }

    testWidgets('hover raises the media glass and fills the canvas circle', (
      tester,
    ) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      await tester.pumpWidget(
        host(
          YoCreateRingButton(
            key: createCta,
            semanticLabel: 'UTWÓRZ',
            onTap: () {},
          ),
        ),
      );
      await mouse.moveTo(tester.getCenter(find.byKey(createCta)));
      await tester.pump();
      expect(glassColor(tester), Colors.black.withValues(alpha: .38));

      await mouse.moveTo(Offset.zero);
      await tester.pumpWidget(
        host(
          YoCreateRingButton(
            key: createCta,
            semanticLabel: 'UTWÓRZ',
            onTap: () {},
            onMedia: false,
          ),
        ),
      );
      await mouse.moveTo(tester.getCenter(find.byKey(createCta)));
      await tester.pump();
      final fill =
          tester.widget<DecoratedBox>(find.byKey(hoverKey)).decoration
              as BoxDecoration;
      expect(fill.color, AppPalette.dark.surfaceMuted);
    });

    for (final onMedia in <bool>[true, false]) {
      testWidgets('keyboard focus draws its own ring (onMedia: $onMedia)', (
        tester,
      ) async {
        final previous = FocusManager.instance.highlightStrategy;
        addTearDown(() => FocusManager.instance.highlightStrategy = previous);
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        final focus = FocusNode();
        addTearDown(focus.dispose);
        await tester.pumpWidget(
          host(
            YoCreateRingButton(
              semanticLabel: 'UTWÓRZ',
              onTap: () {},
              onMedia: onMedia,
              focusNode: focus,
            ),
            light: true,
          ),
        );
        expect(echoPaint(tester).foregroundPainter, isNull);
        focus.requestFocus();
        await tester.pump();
        final ring =
            echoPaint(tester).foregroundPainter! as YoCreateFocusPainter;
        if (onMedia) {
          expect(ring.ring, Colors.white);
          expect(ring.contrast, Colors.black);
        } else {
          expect(ring.ring, AppPalette.light.focus);
          expect(ring.contrast, isNull);
        }
        // The tap region draws no ring of its own on the 48 px edge.
        expect(
          find.descendant(
            of: find.byType(AccessibleTapRegion),
            matching: find.byType(AnimatedContainer),
          ),
          findsNothing,
        );

        // A pointer-driven focus (touch highlight mode) shows no ring.
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTouch;
        await tester.pump();
        expect(echoPaint(tester).foregroundPainter, isNull);
      });
    }

    for (final onMedia in <bool>[true, false]) {
      testWidgets('high contrast: denser glass, hairline (onMedia: $onMedia)', (
        tester,
      ) async {
        await tester.pumpWidget(
          host(
            YoCreateRingButton(
              semanticLabel: 'UTWÓRZ',
              onTap: () {},
              onMedia: onMedia,
            ),
            light: true,
            highContrast: true,
          ),
        );
        expect(find.byKey(shadowKey), findsNothing);
        expect(ringPainter(tester).enabled, isTrue, reason: 'ring stays');
        if (onMedia) {
          expect(glassColor(tester), Colors.black.withValues(alpha: .60));
          expect(ringPainter(tester).outerHairline, Colors.white);
          expect(plusPainter(tester).color, Colors.white);
        } else {
          expect(
            ringPainter(tester).outerHairline,
            AppPalette.light.borderStrong,
          );
        }
      });
    }

    testWidgets('disabled: border ring, tertiary +, no tap', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          const YoCreateRingButton(
            key: createCta,
            semanticLabel: 'UTWÓRZ',
            onTap: null,
          ),
        ),
      );
      expect(ringPainter(tester).enabled, isFalse);
      expect(ringPainter(tester).disabledColor, AppPalette.dark.border);
      expect(plusPainter(tester).color, AppPalette.dark.textTertiary);
      expect(
        tester.getSemantics(buttonNode()),
        matchesSemantics(
          label: 'UTWÓRZ',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          isFocusable: false,
        ),
      );
      handle.dispose();
    });

    testWidgets('one button node, the label, the tap and the tooltip', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(
        host(
          YoCreateRingButton(
            key: createCta,
            semanticLabel: 'UTWÓRZ',
            onTap: () => taps++,
          ),
        ),
      );
      expect(find.bySemanticsLabel('UTWÓRZ'), findsOneWidget);
      expect(
        tester.getSemantics(buttonNode()),
        matchesSemantics(
          label: 'UTWÓRZ',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(find.byType(Tooltip), findsOneWidget);
      await tester.tap(find.byKey(createCta));
      expect(taps, 1);

      // Enter reaches it too.
      final focus = Focus.of(tester.element(find.byKey(faceKey)));
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(taps, 2);
      handle.dispose();
    });
  });

  group('the echo', () {
    test('opacity peaks at .90 28 % in; the radius grows to 1.12', () {
      expect(YoCreateRingButton.echoAlphaAt(0), 0);
      expect(YoCreateRingButton.echoAlphaAt(.28), closeTo(.90, 1e-9));
      expect(YoCreateRingButton.echoAlphaAt(1), closeTo(0, 1e-9));
      expect(YoCreateRingButton.echoScaleAt(0), 1);
      // The approved render's gentle value, not a larger pull.
      expect(YoCreateRingButton.echoScaleAt(1), closeTo(1.12, 1e-9));
      // At its peak the echo line sits about 1.5 px outside the ring
      // (radius 19 → ~20.4); even its fading end centreline stays inside
      // the focus ring's 22 px inner edge.
      expect(19 * YoCreateRingButton.echoScaleAt(.28), closeTo(20.43, .05));
      expect(19 * YoCreateRingButton.echoScale, lessThan(22));
      expect(
        YoCreateRingButton.echoDuration,
        const Duration(milliseconds: 1600),
      );
    });

    testWidgets('one change plays one 1600 ms echo, then nothing ticks', (
      tester,
    ) async {
      final echoes = ValueNotifier<int>(0);
      addTearDown(echoes.dispose);
      await tester.pumpWidget(
        host(
          YoCreateRingButton(
            semanticLabel: 'UTWÓRZ',
            onTap: () {},
            echoes: echoes,
          ),
        ),
      );
      expect(echoT(tester), isNull);
      expect(tester.binding.transientCallbackCount, 0, reason: 'idle');

      echoes.value++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 448));
      expect(echoT(tester), closeTo(.28, .01));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(echoT(tester), isNull);
      expect(tester.binding.transientCallbackCount, 0, reason: 'no loop');
    });

    for (final (name, highContrast, disableAnimations, accessible, enabled)
        in <(String, bool, bool, bool, bool)>[
          ('Reduce Motion', false, true, false, true),
          ('high contrast', true, false, false, true),
          ('accessible navigation', false, false, true, true),
          ('a disabled button', false, false, false, false),
        ]) {
      testWidgets('never under $name', (tester) async {
        final echoes = ValueNotifier<int>(0);
        addTearDown(echoes.dispose);
        await tester.pumpWidget(
          host(
            YoCreateRingButton(
              semanticLabel: 'UTWÓRZ',
              onTap: enabled ? () {} : null,
              echoes: echoes,
            ),
            highContrast: highContrast,
            disableAnimations: disableAnimations,
            accessibleNavigation: accessible,
          ),
        );
        echoes.value++;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(echoT(tester), isNull);
        expect(tester.binding.transientCallbackCount, 0);
      });
    }

    testWidgets('never while its TickerMode is off (a hidden tab)', (
      tester,
    ) async {
      final echoes = ValueNotifier<int>(0);
      addTearDown(echoes.dispose);
      await tester.pumpWidget(
        host(
          TickerMode(
            enabled: false,
            child: YoCreateRingButton(
              semanticLabel: 'UTWÓRZ',
              onTap: () {},
              echoes: echoes,
            ),
          ),
        ),
      );
      echoes.value++;
      await tester.pump(const Duration(milliseconds: 400));
      expect(echoT(tester), isNull);
    });

    testWidgets('never while keyboard focus is on it; focus ends an echo', (
      tester,
    ) async {
      final previous = FocusManager.instance.highlightStrategy;
      addTearDown(() => FocusManager.instance.highlightStrategy = previous);
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final echoes = ValueNotifier<int>(0);
      addTearDown(echoes.dispose);
      await tester.pumpWidget(
        host(
          YoCreateRingButton(
            semanticLabel: 'UTWÓRZ',
            onTap: () {},
            focusNode: focus,
            echoes: echoes,
          ),
        ),
      );

      // Mid-echo, focus arrives: the echo ends at once.
      echoes.value++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(echoT(tester), isNotNull);
      focus.requestFocus();
      await tester.pump();
      expect(echoT(tester), isNull);
      expect(echoPaint(tester).foregroundPainter, isA<YoCreateFocusPainter>());

      // While focused, no new echo starts.
      echoes.value++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(echoT(tester), isNull);
      expect(tester.binding.transientCallbackCount, 0);

      // Focus gone: the next event plays again.
      focus.unfocus();
      await tester.pump();
      echoes.value++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(echoT(tester), isNotNull);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('never under a hovering pointer', (tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      final echoes = ValueNotifier<int>(0);
      addTearDown(echoes.dispose);
      await tester.pumpWidget(
        host(
          YoCreateRingButton(
            key: createCta,
            semanticLabel: 'UTWÓRZ',
            onTap: () {},
            echoes: echoes,
          ),
        ),
      );
      await mouse.moveTo(tester.getCenter(find.byKey(createCta)));
      await tester.pump();
      echoes.value++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(echoT(tester), isNull);
    });

    testWidgets('an echo leaves the semantics tree untouched', (tester) async {
      final handle = tester.ensureSemantics();
      final echoes = ValueNotifier<int>(0);
      addTearDown(echoes.dispose);
      await tester.pumpWidget(
        host(
          YoCreateRingButton(
            key: createCta,
            semanticLabel: 'UTWÓRZ',
            onTap: () {},
            echoes: echoes,
          ),
        ),
      );
      String tree() {
        var node = tester.getSemantics(buttonNode());
        while (node.parent != null) {
          node = node.parent!;
        }
        return node.toStringDeep();
      }

      final atRest = tree();

      echoes.value++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 448));
      expect(echoT(tester), closeTo(.28, .01));
      expect(tree(), atRest);
      // Still one plain button: no live region, nothing announced.
      expect(
        tester.getSemantics(buttonNode()),
        matchesSemantics(
          label: 'UTWÓRZ',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      handle.dispose();
    });

    testWidgets('the echo repaints behind its own boundary', (tester) async {
      await tester.pumpWidget(
        host(YoCreateRingButton(semanticLabel: 'UTWÓRZ', onTap: () {})),
      );
      // One boundary around the echo's box, one around the static face.
      expect(
        find.descendant(
          of: find.byType(AccessibleTapRegion),
          matching: find.ancestor(
            of: find.byKey(echoKey),
            matching: find.byType(RepaintBoundary),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(echoKey),
          matching: find.ancestor(
            of: find.byKey(faceKey),
            matching: find.byType(RepaintBoundary),
          ),
        ),
        findsOneWidget,
      );
    });
  });

  group('the posted flag store', () {
    test('round-trips per account under a versioned key', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const store = SharedPreferencesYeelsPostedStore();
      expect(await store.read('a'), isFalse);
      await store.write('a');
      expect(await store.read('a'), isTrue);
      expect(await store.read('b'), isFalse);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getBool('yeels.create_invitation.posted.v1.a'),
        isTrue,
      );
      expect(
        SharedPreferencesYeelsPostedStore.keyFor('a'),
        'yeels.create_invitation.posted.v1.a',
      );

      // A fresh flag over the same store learns it from disk.
      final flag = YeelsPostedFlag(store: store);
      expect(flag.knows('a'), isFalse);
      expect(await flag.hasPosted('a'), isTrue);
      expect(flag.knows('a'), isTrue);
      expect(await flag.hasPosted('b'), isFalse);
    });
  });

  group('the invitation schedule', () {
    // Each test disposes its schedule itself: testWidgets checks for a
    // pending Timer BEFORE tear-downs run, which is the guarantee we want.
    Future<YeelsCreateInvitation> start(
      WidgetTester tester, {
      _MemoryStore? store,
      String? viewer = 'viewer',
    }) async {
      final invitation = YeelsCreateInvitation(
        postedFlag: YeelsPostedFlag(store: store ?? _MemoryStore()),
      );
      invitation
        ..setViewer(viewer)
        ..update(visible: true, paused: false);
      await tester.pump();
      return invitation;
    }

    testWidgets('3 s in, then every 40 s, at most three per visit', (
      tester,
    ) async {
      final invitation = await start(tester);
      await tester.pump(const Duration(milliseconds: 2900));
      expect(invitation.echoes.value, 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(invitation.echoes.value, 1);
      await tester.pump(const Duration(seconds: 39));
      expect(invitation.echoes.value, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(invitation.echoes.value, 2);
      await tester.pump(const Duration(seconds: 40));
      expect(invitation.echoes.value, 3);
      await tester.pump(const Duration(minutes: 10));
      expect(invitation.echoes.value, 3, reason: 'three per visit');
      expect(invitation.isScheduled, isFalse, reason: 'no timer left');
      invitation.dispose();
    });

    testWidgets('a new visit starts over; a hidden format never echoes', (
      tester,
    ) async {
      final invitation = await start(tester);
      await tester.pump(const Duration(seconds: 4));
      expect(invitation.echoes.value, 1);
      invitation.update(visible: false, paused: false); // Głos selected
      expect(invitation.isScheduled, isFalse);
      await tester.pump(const Duration(minutes: 5));
      expect(invitation.echoes.value, 1, reason: 'nothing while hidden');
      invitation.update(visible: true, paused: false); // Yeels again
      await tester.pump(const Duration(milliseconds: 3100));
      expect(invitation.echoes.value, 2);
      expect(invitation.echoesThisVisit, 1, reason: 'the count restarted');
      invitation.dispose();
    });

    testWidgets('backgrounding the app ends the visit', (tester) async {
      final invitation = await start(tester);
      await tester.pump(const Duration(seconds: 4));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(invitation.isScheduled, isFalse);
      await tester.pump(const Duration(minutes: 2));
      expect(invitation.echoes.value, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 3100));
      expect(invitation.echoes.value, 2);
      expect(invitation.echoesThisVisit, 1);
      invitation.dispose();
    });

    testWidgets('a covering sheet pauses without restarting the visit', (
      tester,
    ) async {
      final invitation = await start(tester);
      await tester.pump(const Duration(seconds: 4));
      invitation.update(visible: true, paused: true);
      await tester.pump(const Duration(minutes: 3));
      expect(invitation.echoes.value, 1, reason: 'nothing under a sheet');
      invitation.update(visible: true, paused: false);
      await tester.pump(const Duration(seconds: 39));
      expect(invitation.echoes.value, 1, reason: 're-timed from uncovering');
      await tester.pump(const Duration(seconds: 2));
      expect(invitation.echoes.value, 2);
      expect(invitation.echoesThisVisit, 2);
      invitation.dispose();
    });

    testWidgets('never once the viewer has posted; never without a viewer', (
      tester,
    ) async {
      final posted = await start(
        tester,
        store: _MemoryStore(<String>{'viewer'}),
      );
      await tester.pump(const Duration(minutes: 3));
      expect(posted.echoes.value, 0, reason: 'the stored flag');

      final signedOut = await start(tester, viewer: null);
      await tester.pump(const Duration(minutes: 3));
      expect(signedOut.echoes.value, 0);
      posted.dispose();
      signedOut.dispose();
    });

    testWidgets('a publish mid-visit stops the rest, and is persisted', (
      tester,
    ) async {
      final store = _MemoryStore();
      final invitation = await start(tester, store: store);
      await tester.pump(const Duration(seconds: 4));
      expect(invitation.echoes.value, 1);
      invitation.markViewerPosted();
      await tester.pump();
      expect(invitation.isScheduled, isFalse);
      expect(store.posted, contains('viewer'));
      invitation
        ..update(visible: false, paused: false)
        ..update(visible: true, paused: false);
      await tester.pump(const Duration(minutes: 3));
      expect(invitation.echoes.value, 1);
      invitation.dispose();
    });

    testWidgets('engaging ends the visit; the next visit may invite', (
      tester,
    ) async {
      final invitation = await start(tester);
      await tester.pump(const Duration(seconds: 4));
      expect(invitation.echoes.value, 1);
      invitation
        ..noteEngaged() // the chooser opened
        ..update(visible: true, paused: true)
        ..update(visible: true, paused: false); // and closed again
      expect(invitation.isScheduled, isFalse);
      await tester.pump(const Duration(minutes: 3));
      expect(invitation.echoes.value, 1, reason: 'no nagging after a tap');
      invitation
        ..update(visible: false, paused: false)
        ..update(visible: true, paused: false);
      await tester.pump(const Duration(milliseconds: 3100));
      expect(invitation.echoes.value, 2);
      invitation.dispose();
    });

    testWidgets('an account switch re-reads the flag for the new viewer', (
      tester,
    ) async {
      final invitation = await start(
        tester,
        store: _MemoryStore(<String>{'viewer'}),
      );
      await tester.pump(const Duration(minutes: 2));
      expect(invitation.echoes.value, 0, reason: 'viewer has posted');
      invitation.setViewer('someone-new');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 3100));
      expect(invitation.echoes.value, 1, reason: 'the new viewer has not');
      invitation.setViewer('viewer');
      await tester.pump(const Duration(minutes: 2));
      expect(invitation.echoes.value, 1);
      invitation.dispose();
    });

    testWidgets('an unreadable store still invites (never blocks)', (
      tester,
    ) async {
      final invitation = await start(tester, store: _MemoryStore.broken());
      await tester.pump(const Duration(milliseconds: 3100));
      expect(invitation.echoes.value, 1);
      invitation.dispose();
    });

    testWidgets('dispose leaves no timer behind', (tester) async {
      final invitation =
          YeelsCreateInvitation(
              postedFlag: YeelsPostedFlag(store: _MemoryStore()),
            )
            ..setViewer('viewer')
            ..update(visible: true, paused: false);
      await tester.pump();
      expect(invitation.isScheduled, isTrue);
      invitation.dispose();
      expect(invitation.isScheduled, isFalse);
      // testWidgets itself fails on a Timer still pending at the end.
    });
  });

  group('on the Moments screen', () {
    late VoidCallback restoreIdentity;
    setUp(() => restoreIdentity = installIdentityStub());
    tearDown(() => restoreIdentity());

    Future<void> pumpMoments(
      WidgetTester tester, {
      YoMomentsFormat initialFormat = YoMomentsFormat.reels,
      _MemoryStore? store,
      bool ownYeelInDiscover = false,
      bool emptyPool = false,
      ReelService? reelService,
      ValueNotifier<bool>? isVisible,
      bool disableAnimations = false,
      bool highContrast = false,
      bool rtl = false,
      double textScale = 1,
      Size size = const Size(390, 844),
    }) async {
      useSurface(tester, size);
      final auth = authAs('viewer');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          locale: const Locale('pl'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          navigatorObservers: <NavigatorObserver>[appRouteObserver],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: disableAnimations,
              highContrast: highContrast,
              textScaler: TextScaler.linear(textScale),
            ),
            child: Directionality(
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              child: child!,
            ),
          ),
          home: MomentsScreen(
            isRootTab: true,
            isVisible: isVisible,
            initialFormat: initialFormat,
            auth: auth,
            discoveryService: StaticDiscovery(populatedPool()),
            feedService: QuietFeed(firestore: fakeFirestore(), auth: auth),
            viewsService: StaticViews(const <String>{}),
            playerFactory: SilentPlayer.new,
            reelService:
                reelService ??
                _service(
                  ownYeelInDiscover: ownYeelInDiscover,
                  empty: emptyPool,
                ),
            reelVideoBuilder: (context, uri, reel) =>
                const ColoredBox(color: Color(0xFF202020)),
            onCreateReel: () async {},
            yeelsPostedFlag: YeelsPostedFlag(store: store ?? _MemoryStore()),
          ),
        ),
      );
      await settleOverview(tester);
    }

    ValueListenable<int>? echoesOf(WidgetTester tester) => tester
        .widget<YoCreateRingButton>(
          find.byKey(createCta, skipOffstage: false).last,
        )
        .echoes;

    testWidgets('Yeels phone row: the ring over media, echoing on schedule', (
      tester,
    ) async {
      await pumpMoments(tester);
      final ring = tester.widget<YoCreateRingButton>(find.byKey(createCta));
      expect(ring.onMedia, isTrue);
      expect(tester.getSize(find.byKey(createCta)), const Size(48, 48));
      final echoes = ring.echoes!;
      expect(echoes.value, 0);

      await tester.pump(const Duration(seconds: 3));
      expect(echoes.value, 1);
      // The ring actually plays it.
      await tester.pump(const Duration(milliseconds: 400));
      expect(echoT(tester), isNotNull);
      await tester.pump(const Duration(seconds: 40));
      expect(echoes.value, 2);
      await tester.pump(const Duration(seconds: 40));
      expect(echoes.value, 3);
      await tester.pump(const Duration(seconds: 90));
      expect(echoes.value, 3, reason: 'at most three per visit');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Głos: the same ring on the canvas that never echoes', (
      tester,
    ) async {
      await pumpMoments(tester, initialFormat: YoMomentsFormat.voice);
      final ring = tester.widget<YoCreateRingButton>(find.byKey(createCta));
      expect(ring.onMedia, isFalse);
      expect(ring.echoes, isNull);
      await tester.pump(const Duration(minutes: 2));
      expect(echoT(tester), isNull);
    });

    testWidgets('switching to Głos ends the visit; Yeels again restarts it', (
      tester,
    ) async {
      await pumpMoments(tester);
      final echoes = echoesOf(tester)!;
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const ValueKey('yo-moments-format-voice')));
      await settleOverview(tester);
      await tester.pump(const Duration(minutes: 2));
      expect(echoes.value, 0, reason: 'never while Głos is the visible one');

      await tester.tap(find.byKey(const ValueKey('yo-moments-format-reels')));
      await settleOverview(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(echoes.value, 1);
    });

    testWidgets('another shell tab ends the visit', (tester) async {
      final visible = ValueNotifier<bool>(true);
      addTearDown(visible.dispose);
      await pumpMoments(tester, isVisible: visible);
      final echoes = echoesOf(tester)!;
      visible.value = false;
      await tester.pump(const Duration(minutes: 2));
      expect(echoes.value, 0);
      visible.value = true;
      await tester.pump(const Duration(seconds: 3, milliseconds: 100));
      expect(echoes.value, 1);
    });

    testWidgets('the create sheet pauses it', (tester) async {
      await pumpMoments(tester);
      final echoes = echoesOf(tester)!;
      await tester.tap(find.byKey(createCta));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const ValueKey<String>('yo-moments-create-sheet')),
        findsOneWidget,
      );
      await tester.pump(const Duration(minutes: 2));
      expect(echoes.value, 0, reason: 'nothing while the sheet is open');

      // Closed without choosing: the viewer already answered the
      // invitation, so the rest of this visit stays quiet.
      Navigator.of(
        tester.element(
          find.byKey(const ValueKey<String>('yo-moments-create-sheet')),
        ),
      ).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(minutes: 2));
      expect(echoes.value, 0, reason: 'no pulse right after a tap');

      // A later visit may invite again.
      await tester.tap(find.byKey(const ValueKey('yo-moments-format-voice')));
      await settleOverview(tester);
      await tester.tap(find.byKey(const ValueKey('yo-moments-format-reels')));
      await settleOverview(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(echoes.value, 1);
    });

    testWidgets('the empty feed offers "Create Yeel"; the ring stays quiet', (
      tester,
    ) async {
      await pumpMoments(tester, emptyPool: true);
      expect(find.text('Utwórz Yeel'), findsOneWidget);
      final echoes = echoesOf(tester)!;
      await tester.pump(const Duration(minutes: 2));
      expect(echoes.value, 0);
    });

    testWidgets('at 1100+ the ring is not drawn, so no visit counts', (
      tester,
    ) async {
      await pumpMoments(tester, size: const Size(1440, 900));
      await tester.pump(const Duration(minutes: 2));
      useSurface(tester, const Size(390, 844));
      await settleOverview(tester);
      final echoes = echoesOf(tester)!;
      expect(echoes.value, 0, reason: 'nothing was emitted with no ring');
      await tester.pump(const Duration(seconds: 3));
      expect(echoes.value, 1, reason: 'the ring appeared: a new visit');
    });

    testWidgets('an account switch lets a new viewer be invited', (
      tester,
    ) async {
      final service = _SwitchableReelService();
      addTearDown(service.changes.close);
      await pumpMoments(
        tester,
        reelService: service,
        store: _MemoryStore(<String>{'viewer'}),
      );
      final echoes = echoesOf(tester)!;
      await tester.pump(const Duration(minutes: 2));
      expect(echoes.value, 0, reason: 'viewer has posted');
      service.switchTo('someone-new');
      await settleOverview(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(echoes.value, 1);
    });

    for (final highContrast in <bool>[false, true]) {
      for (final rtl in <bool>[false, true]) {
        testWidgets('Tab reaches the ring and shows its focus ring '
            '(hc: $highContrast, rtl: $rtl)', (tester) async {
          await pumpMoments(tester, highContrast: highContrast, rtl: rtl);
          bool focused() =>
              echoPaint(tester).foregroundPainter is YoCreateFocusPainter;
          for (var i = 0; i < 40 && !focused(); i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
          }
          expect(focused(), isTrue);
          final ring =
              echoPaint(tester).foregroundPainter! as YoCreateFocusPainter;
          expect(ring.ring, Colors.white);
          expect(ring.contrast, Colors.black);
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final width in <double>[320, 390]) {
      for (final rtl in <bool>[false, true]) {
        testWidgets('200 % text at $width (rtl: $rtl): a whole 48 px ring', (
          tester,
        ) async {
          await pumpMoments(
            tester,
            size: Size(width, 844),
            textScale: 2,
            rtl: rtl,
          );
          final rect = tester.getRect(find.byKey(createCta));
          expect(rect.size, const Size(48, 48));
          expect(
            (Offset.zero & Size(width, 844)).intersect(rect),
            rect,
            reason: 'fully inside the viewport',
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('a viewer who has posted gets no echo', (tester) async {
      await pumpMoments(tester, store: _MemoryStore(<String>{'viewer'}));
      await tester.pump(const Duration(minutes: 2));
      expect(echoesOf(tester)!.value, 0);
    });

    testWidgets('an own Yeel the feed already loaded retires it for good', (
      tester,
    ) async {
      final store = _MemoryStore();
      await pumpMoments(tester, store: store, ownYeelInDiscover: true);
      await tester.pump(const Duration(minutes: 2));
      expect(echoesOf(tester)!.value, 0);
      expect(store.posted, contains('viewer'));
    });

    testWidgets('Reduce Motion: the schedule runs, the ring stays still', (
      tester,
    ) async {
      await pumpMoments(tester, disableAnimations: true);
      final echoes = echoesOf(tester)!;
      await tester.pump(const Duration(seconds: 3));
      expect(echoes.value, 1);
      await tester.pump(const Duration(milliseconds: 400));
      expect(echoT(tester), isNull);
    });

    testWidgets('leaving the screen cancels everything', (tester) async {
      await pumpMoments(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      // testWidgets fails on any Timer still pending after this.
    });
  });
}

/// The real service over a scripted transport: a Discover pool of two
/// Yeels by other authors, plus (optionally) one by the viewer — or an
/// empty pool.
ReelService _service({required bool ownYeelInDiscover, bool empty = false}) =>
    ReelService(
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'viewer', displayName: 'Kamil'),
      ),
      callableInvoker: _invoker(
        ownYeelInDiscover: ownYeelInDiscover,
        empty: empty,
      ),
    );

/// The same transport, with the signed-in account switchable.
class _SwitchableReelService extends ReelService {
  _SwitchableReelService()
    : super(
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'viewer', displayName: 'Kamil'),
        ),
        callableInvoker: _invoker(ownYeelInDiscover: false),
      );

  String? uid = 'viewer';
  final StreamController<String?> changes = StreamController<String?>.broadcast(
    sync: true,
  );

  @override
  String? get currentUserId => uid;

  @override
  Stream<String?> get identityChanges => changes.stream;

  void switchTo(String? value) {
    uid = value;
    changes.add(value);
  }
}

ReelCallableInvoker _invoker({
  required bool ownYeelInDiscover,
  bool empty = false,
}) => (name, payload) async {
  if (name == 'listReelsV2') {
    return <String, Object?>{
      'schemaVersion': 2,
      'items': <Object?>[
        if (!empty) ...<Object?>[reelWire(1), reelWire(2)],
        if (ownYeelInDiscover)
          reelWire(3, authorId: 'viewer', sameAuthor: true),
      ],
      'nextCursor': null,
    };
  }
  if (name == 'getReelMediaAccessV2') {
    return <Object?, Object?>{
      'schemaVersion': 2,
      'url': 'https://storage.googleapis.com/yovoice/${payload['reelId']}.mp4',
      'expiresAtMillis': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch,
      'generation': '7',
      'availabilityHours': 'permanent',
      'contentExpiresAtMillis': null,
    };
  }
  throw StateError('Unexpected callable $name');
};

class _MemoryStore implements YeelsPostedStore {
  _MemoryStore([Set<String>? posted]) : posted = posted ?? <String>{};
  _MemoryStore.broken() : posted = <String>{}, _broken = true;

  final Set<String> posted;
  bool _broken = false;

  @override
  Future<bool> read(String userId) async {
    if (_broken) throw StateError('unreadable');
    return posted.contains(userId);
  }

  @override
  Future<void> write(String userId) async {
    if (_broken) throw StateError('unwritable');
    posted.add(userId);
  }
}
