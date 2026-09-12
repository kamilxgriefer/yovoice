// Home "Tu i teraz" — independent QA probe over the Foundation slice.
// Pins what the slice's own suites do not: the value-identical `tertiary`
// migration (nothing recoloured), the new palette role surviving
// copyWith/lerp, counter boundaries the brief's table skips, dock targets
// under a real safe inset at 320 px / 200 % text / RTL, instant settle under
// Reduce Motion, the mobile tour anchor on Home's create pill, and the
// Servers slot's gating and aliasing invariants. Read-only over lib/.
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
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_overview_sections.dart';

Color _audio(ThemeExtension<AppPalette> palette) =>
    (palette as AppPalette).audioAccent;

class _DockHost extends StatefulWidget {
  const _DockHost({required this.selected, this.onSelect});
  final int selected;
  final ValueChanged<int>? onSelect;
  @override
  State<_DockHost> createState() => _DockHostState();
}

class _DockHostState extends State<_DockHost> {
  late int _selected = widget.selected;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: const SizedBox.expand(),
    bottomNavigationBar: YoFloatingNavigationDock(
      selectedTabIndex: _selected,
      roomsTabIndex: 13,
      momentsTabIndex: 5,
      unreadConversationCount: 3,
      onDestinationSelected: (index) {
        widget.onSelect?.call(index);
        setState(() => _selected = index);
      },
      onVoicePressed: () {},
      onMorePressed: () {},
    ),
  );
}

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

Finder _cell(int slot) => find.byKey(ValueKey('yo-destination-$slot'));
Finder get _surface => find.byKey(const ValueKey('yo-dock-surface'));
Finder get _wash => find.byKey(const ValueKey('yo-dock-active-indicator'));

void main() {
  group('central tokens: added once, nothing recoloured', () {
    test('tertiary now reads the palette and keeps its former values', () {
      expect(AppTheme.darkTheme.colorScheme.tertiary, AppColors.accent);
      expect(
        AppTheme.lightTheme.colorScheme.tertiary,
        const Color(0xFF007C83),
      );
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
      expect(AppSizing.audioControl, greaterThan(AppSizing.audioControlCompact));
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
        expect(MainShell.desktopSlots.values, contains(destination));
      }
      expect(MainShell.mobileIndexFor(13), 13);
    });
  });

  group('flat dock under a real safe inset', () {
    testWidgets('320 px + 34 px inset: five ≥ 48 px cells, full-bleed, '
        'reserved height honoured', (tester) async {
      await _pumpApp(
        tester,
        const _DockHost(selected: 0),
        size: const Size(320, 568),
        safeBottom: 34,
      );
      expect(tester.takeException(), isNull);
      final surface = tester.getSize(_surface);
      expect(surface.width, 320);
      expect(
        surface.height,
        YoFloatingNavigationDock.reservedHeightFor(safeBottom: 34),
      );
      for (var slot = 0; slot < 5; slot++) {
        final size = tester.getSize(_cell(slot));
        expect(size.width, greaterThanOrEqualTo(48), reason: 'cell $slot');
        expect(size.height, greaterThanOrEqualTo(48), reason: 'cell $slot');
        // The cell never sits under the home-indicator inset.
        expect(
          tester.getRect(_cell(slot)).bottom,
          lessThanOrEqualTo(tester.getRect(_surface).bottom - 34 + .01),
          reason: 'cell $slot',
        );
      }
      // The wash sits inside cell 0 and inside the bar.
      final wash = tester.getRect(_wash);
      final cell0 = tester.getRect(_cell(0));
      expect(wash.center.dx, closeTo(cell0.center.dx, .5));
      expect(wash.width, lessThanOrEqualTo(cell0.width + .01));
      expect(wash.top, greaterThanOrEqualTo(cell0.top - .01));
      expect(wash.bottom, lessThanOrEqualTo(cell0.bottom + .01));
      expect(find.text('Serwery'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('200 % text: no overflow, cells keep ≥ 48 px, one expanded '
        'label row, height from the same formula', (tester) async {
      await _pumpApp(
        tester,
        const _DockHost(selected: 13),
        size: const Size(360, 740),
        safeBottom: 34,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(_surface).height,
        YoFloatingNavigationDock.reservedHeightFor(
          safeBottom: 34,
          textScale: 2,
        ),
      );
      for (var slot = 0; slot < 5; slot++) {
        expect(tester.getSize(_cell(slot)).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(_cell(slot)).width, greaterThanOrEqualTo(48));
      }
      expect(
        find.byKey(const ValueKey('yo-meniscus-accessible-label')),
        findsOneWidget,
      );
      expect(find.text('Serwery'), findsOneWidget);
    });

    testWidgets('RTL mirrors the cell order; Reduce Motion settles the wash '
        'on the tapped cell without animation time', (tester) async {
      final requests = <int>[];
      await _pumpApp(
        tester,
        _DockHost(selected: 0, onSelect: requests.add),
        size: const Size(390, 844),
        safeBottom: 34,
        direction: TextDirection.rtl,
      );
      expect(
        tester.getCenter(_cell(0)).dx,
        greaterThan(tester.getCenter(_cell(4)).dx),
        reason: 'Home is the trailing (right) cell in RTL',
      );
      await tester.tap(_cell(1));
      await tester.pump();
      await tester.pump();
      expect(requests, [13]);
      expect(
        tester.getCenter(_wash).dx,
        closeTo(tester.getCenter(_cell(1)).dx, .5),
        reason: 'no spring, no slide: the wash is already on Serwery',
      );
      expect(tester.takeException(), isNull);
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
          matching: find.byKey(const ValueKey('home-quick-create-room')),
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
      expect(find.byKey(const ValueKey('home-quick-create-room')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------
  // Second independent gate (Principal Code and Release Reviewer, 11:2x).
  // Probes for two behaviours the slice's own suites do not exercise.
  // ---------------------------------------------------------------------

  group('dock with no cell for the selected destination', () {
    testWidgets('1x text still labels every cell', (tester) async {
      await _pumpApp(
        tester,
        const _DockHost(selected: 3),
        size: const Size(390, 844),
        safeBottom: 34,
      );
      expect(_wash, findsNothing, reason: 'nothing is lit, nothing lies');
      for (final label in ['Start', 'Serwery', 'Czaty', 'Momenty', 'Więcej']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('200 % text: the expanded label row is the ONLY label, so a '
        'slot without a dock cell leaves the bar unlabelled', (tester) async {
      // Selected content slot 3 (Odkrywaj) has no dock cell after the
      // Foundation remap. Documents today's behaviour so a fix is visible
      // as a change here.
      await _pumpApp(
        tester,
        const _DockHost(selected: 3),
        size: const Size(390, 844),
        safeBottom: 34,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('yo-meniscus-accessible-label')),
        findsNothing,
      );
      final visibleLabels = [
        for (final label in ['Start', 'Serwery', 'Czaty', 'Momenty', 'Więcej'])
          if (find.text(label).evaluate().isNotEmpty) label,
      ];
      expect(
        visibleLabels,
        isEmpty,
        reason: 'no per-cell label and no expanded row: the bar is glyph-only',
      );
      // The spoken labels survive, so a screen reader is unaffected.
      for (var slot = 0; slot < 5; slot++) {
        expect(
          tester.widget<Semantics>(
            find
                .ancestor(of: _cell(slot), matching: find.byType(Semantics))
                .first,
          ).properties.label,
          isNotNull,
          reason: 'cell $slot keeps a spoken label',
        );
      }
    });
  });

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
