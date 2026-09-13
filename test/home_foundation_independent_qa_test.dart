// Home "Tu i teraz" — independent QA probe over the Foundation slice.
// Pins what the slice's own suites do not: the value-identical `tertiary`
// migration (nothing recoloured), the new palette role surviving
// copyWith/lerp, counter boundaries the brief's table skips, the mobile tour
// anchor on Home's create pill, and the Servers slot's gating and aliasing
// invariants. Read-only over lib/.
//
// The dock-metrics groups this file used to carry measured the flat
// reference bar; the dock is the bead-and-socket one from 895b0f17 again, and
// test/yo_floating_navigation_dock_test.dart owns its metrics.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_overview_sections.dart';

Color _audio(ThemeExtension<AppPalette> palette) =>
    (palette as AppPalette).audioAccent;

Future<void> _pumpApp(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(390, 844),
  double safeBottom = 0,
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      locale: const Locale('pl'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: EdgeInsets.only(bottom: safeBottom),
          viewPadding: EdgeInsets.only(bottom: safeBottom),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: Directionality(textDirection: direction, child: child!),
      ),
      home: home,
    ),
  );
  await tester.pump();
}

void main() {
  group('central tokens: added once, nothing recoloured', () {
    test('tertiary now reads the palette and keeps its former values', () {
      expect(AppTheme.darkTheme.colorScheme.tertiary, AppColors.accent);
      expect(AppTheme.lightTheme.colorScheme.tertiary, const Color(0xFF007C83));
      expect(AppPalette.dark.audioAccent, AppColors.accent);
      expect(AppPalette.light.audioAccent, const Color(0xFF007C83));
    });

    test('audioAccent survives copyWith and lerp; gradient is derived', () {
      expect(AppPalette.dark.copyWith().audioAccent, AppColors.accent);
      expect(
        AppPalette.dark.copyWith(audioAccent: Colors.red).audioAccent,
        Colors.red,
      );
      expect(
        _audio(AppPalette.dark.lerp(AppPalette.light, 0)),
        AppPalette.dark.audioAccent,
      );
      expect(
        _audio(AppPalette.dark.lerp(AppPalette.light, 1)),
        AppPalette.light.audioAccent,
      );
      for (final palette in [AppPalette.dark, AppPalette.light]) {
        expect(palette.audioProgressGradient.colors, [
          palette.audioAccent,
          palette.interactiveForeground,
        ]);
      }
    });

    test('audio control sizes exceed the minimum touch target', () {
      expect(
        AppSizing.audioControlCompact,
        greaterThanOrEqualTo(AppSizing.minimumTouchTarget),
      );
      expect(
        AppSizing.audioControl,
        greaterThan(AppSizing.audioControlCompact),
      );
    });
  });

  group('Polish counters at the boundaries the brief table skips', () {
    test('peopleCount: 0, 21, 32, 111, 114, 1000', () {
      const pl = AppLocalizations(Locale('pl'));
      expect([0, 21, 32, 111, 114, 1000].map(pl.peopleCount), [
        '0 osób',
        '21 osób',
        '32 osoby',
        '111 osób',
        '114 osób',
        '1000 osób',
      ]);
    });

    test('secondsCount: 0, 21, 23, 113, 1002', () {
      const pl = AppLocalizations(Locale('pl'));
      expect([0, 21, 23, 113, 1002].map(pl.secondsCount), [
        '0 sekund',
        '21 sekund',
        '23 sekundy',
        '113 sekund',
        '1002 sekundy',
      ]);
    });
  });

  group('Servers slot invariants', () {
    test('slot-backed once, not premium-gated on the client, rail-owned', () {
      expect(
        MainShell.desktopSlots.values
            .where((d) => d == MoreDestination.servers)
            .length,
        1,
      );
      expect(
        MainShell.desktopSlots.values.toSet().length,
        MainShell.desktopSlots.length,
        reason: 'no destination aliases two slots',
      );
      expect(premiumFeatureForMoreDestination(MoreDestination.servers), isNull);
      for (final destination in desktopRailDestinations) {
        // Friends is primary tab index 2 — a rail row with a retained
        // content identity rather than a `desktopSlots` entry.
        if (destination == MoreDestination.friends) continue;
        expect(MainShell.desktopSlots.values, contains(destination));
      }
      expect(MainShell.mobileIndexFor(13), 13);
    });
  });

  group('mobile tour anchor', () {
    testWidgets('HomeQuickActions places the shell-owned key on the create '
        'pill and builds without one', (tester) async {
      final key = GlobalKey();
      await _pumpApp(
        tester,
        Scaffold(
          body: HomeQuickActions(
            createRoomKey: key,
            onCreateRoom: () {},
            onFriends: () {},
          ),
        ),
      );
      expect(key.currentContext, isNotNull);
      expect(
        find.descendant(
          of: find.byKey(key),
          matching: find.byKey(const ValueKey('home-quick-create-server')),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(key)).height,
        greaterThanOrEqualTo(AppSizing.minimumTouchTarget),
      );
      await _pumpApp(
        tester,
        Scaffold(
          body: HomeQuickActions(onCreateRoom: () {}, onFriends: () {}),
        ),
      );
      expect(
        find.byKey(const ValueKey('home-quick-create-server')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------
  // Second independent gate (Principal Code and Release Reviewer, 11:2x).
  // Probes for two behaviours the slice's own suites do not exercise.
  // ---------------------------------------------------------------------

  group('mobile tour Create anchor reveal', () {
    testWidgets('the shell-owned key has no context once Home scrolls the '
        'create pill out of the built range', (tester) async {
      // MainShell._prepareGuidedOnboardingLayout reveals the pill with
      // Scrollable.ensureVisible ONLY when the key already has a context.
      // A retained Home scrolled far down detaches it, so the reveal is a
      // no-op and the Create step loses its spotlight.
      final key = GlobalKey();
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pumpApp(
        tester,
        Scaffold(
          body: ListView(
            controller: controller,
            children: [
              HomeQuickActions(
                createRoomKey: key,
                onCreateRoom: () {},
                onFriends: () {},
              ),
              for (var i = 0; i < 30; i++)
                SizedBox(height: 300, child: Text('block $i')),
            ],
          ),
        ),
      );
      expect(key.currentContext, isNotNull);
      controller.jumpTo(4000);
      await tester.pump();
      expect(
        key.currentContext,
        isNull,
        reason: 'ensureVisible cannot be called on a detached anchor',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
