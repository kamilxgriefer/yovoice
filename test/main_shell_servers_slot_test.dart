// Home "Tu i teraz" — Foundation. Content slot 13 is the Servers
// destination: dock cell 1 (Serwery) and the rail's second row. These tests
// pin the slot map, the mobile order and Back history, the hosted dock's
// slot-1 routing and the rail highlight without mounting the Firebase-backed
// MainShell.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/navigation/mobile_destination_history.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';

int _slotOf(MoreDestination destination) => MainShell.desktopSlots.entries
    .firstWhere((entry) => entry.value == destination)
    .key;

bool _selected(WidgetTester tester, String label) => tester
    .widgetList<Semantics>(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == label,
      ),
    )
    .any((widget) => widget.properties.selected == true);

/// A stand-in for the shell's dock host: accepts every request, exactly as
/// the shell does for a retained root, and passes the Servers slot through
/// `roomsTabIndex` the way both shells do.
class _DockStub extends StatefulWidget {
  const _DockStub({required this.initialSelected, required this.onRequested});
  final int initialSelected;
  final ValueChanged<int> onRequested;
  @override
  State<_DockStub> createState() => _DockStubState();
}

class _DockStubState extends State<_DockStub> {
  late int _selected = widget.initialSelected;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: const SizedBox.expand(),
    bottomNavigationBar: YoFloatingNavigationDock(
      selectedTabIndex: _selected,
      roomsTabIndex: 13,
      momentsTabIndex: 5,
      unreadConversationCount: 0,
      onDestinationSelected: (index) {
        widget.onRequested(index);
        setState(() => _selected = index);
      },
      onVoicePressed: () {},
      onMorePressed: () {},
    ),
  );
}

Future<SemanticsHandle> _pumpPhone(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final semantics = tester.ensureSemantics();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: home,
        ),
      ),
    ),
  );
  await tester.pump();
  return semantics;
}

void main() {
  group('content slot 13 = Servers', () {
    test('desktopSlots[13] is Servers and the slots stay contiguous 3…13', () {
      expect(MainShell.desktopSlots[13], MoreDestination.servers);
      expect(_slotOf(MoreDestination.servers), 13);
      expect(
        MainShell.desktopSlots.keys.toList()..sort(),
        List.generate(11, (index) => index + 3),
        reason: 'appended, never inserted: no existing slot renumbers',
      );
      // The retained roots keep their identities.
      expect(MainShell.desktopSlots[3], MoreDestination.discover);
      expect(MainShell.desktopSlots[5], MoreDestination.moments);
      expect(MainShell.desktopSlots[12], MoreDestination.findCreators);
    });

    test(
      'mobile retains 13 (and still 3) and orders the dock '
      'Start · Serwery · Czaty · Momenty',
      () {
        expect(MainShell.mobileIndexFor(13), 13);
        expect(
          MainShell.mobileIndexFor(3),
          3,
          reason: 'Discover stays a retained root reached from More',
        );
        expect(MainShell.mobileIndexFor(2), 2);
        expect([0, 13, 1, 5].map(MainShell.mobileNavigationOrder), [
          0,
          1,
          2,
          3,
        ]);
        expect(
          MainShell.mobileNavigationOrder(3),
          4,
          reason: 'no dock cell: Discover sorts with More',
        );
        expect(MainShell.mobileNavigationOrder(2), 4);
        for (final desktopOnly in [4, 6, 7, 8, 9, 10, 11, 12]) {
          expect(
            MainShell.mobileIndexFor(desktopOnly),
            0,
            reason: 'slot $desktopOnly is desktop-only',
          );
        }
      },
    );

    test(
      'mobile history records Servers as a Back entry, keeps Discover, and '
      'survives the desktop↔mobile reset',
      () {
        final history = MobileDestinationHistory();
        history.select(13);
        expect(history.current, 13);
        expect(history.canGoBack, isTrue);
        // Odkrywaj opened from Więcej is still a Back entry, as today.
        history.select(3);
        expect(history.current, 3);
        expect(history.back(), 13);
        expect(history.back(), 0);
        expect(history.canGoBack, isFalse);
        // A desktop-only slot is never recorded.
        history.select(12);
        expect(history.current, 0);
        // The shell resets through `mobileIndexFor` when the layout flips;
        // a Serwery selection comes back as Serwery, not Home.
        history.resetTo(MainShell.mobileIndexFor(13));
        expect(history.current, 13);
        expect(history.canGoBack, isTrue);
      },
    );

    test(
      'the rail lights Servers for slot 13 and More for Friends, Discover '
      'and Find creators',
      () {
        expect(MainShell.desktopNavItemForSlot(13), DesktopNavItem.servers);
        expect(MainShell.desktopNavItemForSlot(0), DesktopNavItem.home);
        expect(MainShell.desktopNavItemForSlot(1), DesktopNavItem.chats);
        expect(MainShell.desktopNavItemForSlot(5), DesktopNavItem.moments);
        expect(
          MainShell.desktopNavItemForSlot(4),
          DesktopNavItem.notifications,
        );
        for (final slot in [2, 3, 12, 6, 7, 8, 9, 10, 11]) {
          expect(
            MainShell.desktopNavItemForSlot(slot),
            DesktopNavItem.more,
            reason: 'slot $slot has no rail row: More stays lit',
          );
        }
      },
    );
  });

  group('dock cell 1 = Servers', () {
    testWidgets(
      'a dock given roomsTabIndex: 13 requests [13, 1, 5, 0] in visual order '
      'and lights Servers for 13',
      (tester) async {
        final requests = <int>[];
        final semantics = await _pumpPhone(
          tester,
          _DockStub(initialSelected: 0, onRequested: requests.add),
        );
        for (final slot in [1, 2, 3, 0]) {
          await tester.tap(find.byKey(ValueKey('yo-destination-$slot')));
          await tester.pumpAndSettle();
        }
        expect(requests, [13, 1, 5, 0]);
        await tester.tap(find.byKey(const ValueKey('yo-destination-1')));
        await tester.pumpAndSettle();
        expect(_selected(tester, 'Servers'), isTrue);
        expect(_selected(tester, 'Home'), isFalse);
        expect(find.text('Rooms'), findsNothing);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );

    testWidgets(
      'MoreDestinationHost: cell 1 reports 13, selectedIndex 13 lights '
      'Servers, and Discover (3) lights nothing rather than lying',
      (tester) async {
        int? selected;
        final semantics = await _pumpPhone(
          tester,
          MoreDestinationHost(
            body: const Text('BODY'),
            selectedIndex: 13,
            unreadConversationCount: 0,
            onDestinationSelected: (index) => selected = index,
            onVoicePressed: () {},
            onMorePressed: () {},
          ),
        );
        expect(_selected(tester, 'Servers'), isTrue);
        await tester.tap(find.byKey(const ValueKey('yo-destination-1')));
        await tester.pumpAndSettle();
        expect(selected, 13);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: MoreDestinationHost(
              body: const Text('BODY'),
              selectedIndex: 3,
              unreadConversationCount: 0,
              onDestinationSelected: (_) {},
              onVoicePressed: () {},
              onMorePressed: () {},
            ),
          ),
        );
        await tester.pump();
        for (final label in ['Home', 'Servers', 'Chats', 'Moments', 'More']) {
          expect(_selected(tester, label), isFalse, reason: label);
        }
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  });
}
