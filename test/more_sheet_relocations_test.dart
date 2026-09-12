// Home "Tu i teraz" — Foundation. Friends, Discover and Find creators left
// the desktop rail for the More popover (kept, never deleted); Servers joined
// Moments as a rail-owned destination; the mobile More sheet is unchanged.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';

class _NoStaffCapabilities extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      StaffCapabilities.none;
}

void main() {
  test('the rail owns exactly Moments and Servers', () {
    expect(desktopRailDestinations, {
      MoreDestination.moments,
      MoreDestination.servers,
    });
  });

  test('slot 13 resolves to ServersScreen with isRootTab forwarded', () {
    // The one call site for the servers feature from Home: the shell's
    // existing More-destination mechanism. Hosted in a content slot the
    // screen draws no app bar; pushed as a mobile route it keeps one.
    final asRoot = moreDestinationScreen(
      MoreDestination.servers,
      isRootTab: true,
    );
    final asPushed = moreDestinationScreen(MoreDestination.servers);
    expect(asRoot, isA<ServersScreen>());
    expect((asRoot as ServersScreen).isRootTab, isTrue);
    expect(asPushed, isA<ServersScreen>());
    expect((asPushed as ServersScreen).isRootTab, isFalse);
    // The relocated three still resolve to their real screens.
    expect(
      moreDestinationScreen(
        MoreDestination.friends,
        isRootTab: true,
      ).runtimeType.toString(),
      'FriendsScreen',
    );
    expect(
      moreDestinationScreen(
        MoreDestination.discover,
        isRootTab: true,
      ).runtimeType.toString(),
      'DiscoverScreen',
    );
    expect(
      moreDestinationScreen(
        MoreDestination.findCreators,
        isRootTab: true,
      ).runtimeType.toString(),
      'FindCreatorsScreen',
    );
  });

  testWidgets(
    'the desktop popover lists Friends, Discover and Find creators exactly '
    'once, never Moments or Servers',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      MoreDestination? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await showDesktopMoreMenu(
                    context,
                    anchor: const Offset(80, 200),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The mobile sheet's exact labels and subtitles, each once.
      for (final entry in const {
        'Friends': 'Your circle',
        'Discover': 'Find rooms',
        'Find creators': 'People to follow',
      }.entries) {
        expect(find.text(entry.key), findsOneWidget, reason: entry.key);
        expect(find.text(entry.value), findsOneWidget, reason: entry.value);
      }
      // Everything that was already there is still there.
      for (final label in ['Clubs', 'Creator Studio', 'Awards', 'Alerts']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // Rail-owned destinations never appear twice.
      for (final absent in ['Moments', 'YO Moments', 'Servers']) {
        expect(find.text(absent), findsNothing, reason: absent);
      }
      // Reading order: the three relocated rows lead the popover.
      expect(
        tester.getCenter(find.text('Friends')).dy,
        lessThan(tester.getCenter(find.text('Discover')).dy),
      );
      expect(
        tester.getCenter(find.text('Discover')).dy,
        lessThan(tester.getCenter(find.text('Find creators')).dy),
      );
      expect(
        tester.getCenter(find.text('Find creators')).dy,
        lessThan(tester.getCenter(find.text('Clubs')).dy),
      );

      await tester.tap(find.text('Friends'));
      await tester.pumpAndSettle();
      expect(picked, MoreDestination.friends);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the mobile More sheet keeps its entries and lists no Servers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: MoreSheet(
              capabilityService: _NoStaffCapabilities(),
              currentUid: 'ordinary-user',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Byte-identical entries: the same nine destinations as before the
    // Foundation slice, in the same order.
    const expected = [
      MoreDestination.friends,
      MoreDestination.profile,
      MoreDestination.discover,
      MoreDestination.findCreators,
      MoreDestination.clubs,
      MoreDestination.notifications,
      MoreDestination.achievements,
      MoreDestination.creatorStudio,
      MoreDestination.settings,
    ];
    // Reading order (row, then column): at 1x text the sheet is a grid, so
    // two entries may share a row.
    Offset? previous;
    for (final destination in expected) {
      final target = find.byKey(
        ValueKey('more-destination-${destination.name}'),
      );
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      expect(target, findsOneWidget, reason: destination.name);
      final topLeft = tester.getTopLeft(target);
      if (previous != null) {
        final laterRow = topLeft.dy > previous.dy + .5;
        final sameRowLater =
            (topLeft.dy - previous.dy).abs() <= .5 &&
            topLeft.dx > previous.dx;
        expect(
          laterRow || sameRowLater,
          isTrue,
          reason: '${destination.name} keeps its position in reading order',
        );
      }
      previous = topLeft;
    }
    // Servers is a dock root (cell 1), Moments a dock root (cell 3), Reels a
    // compatibility deep link — none is a sheet entry.
    for (final absent in ['servers', 'moments', 'reels']) {
      expect(
        find.byKey(ValueKey('more-destination-$absent')),
        findsNothing,
        reason: absent,
      );
    }
    expect(find.text('Servers'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
