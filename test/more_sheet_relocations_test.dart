// Home "Tu i teraz" — server cutover. Servers owns the former space
// destinations while Friends and Find creators remain secondary actions.
// Legacy Discover/Clubs identities stay parseable but are never listed.
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
    // Friends and Find creators retain their existing surfaces.
    expect(
      moreDestinationScreen(
        MoreDestination.friends,
        isRootTab: true,
      ).runtimeType.toString(),
      'FriendsScreen',
    );
    // Compatibility identities can still be handed to the router, but may
    // never resurrect either retired standalone surface.
    for (final legacy in [MoreDestination.discover, MoreDestination.clubs]) {
      final redirected = moreDestinationScreen(legacy, isRootTab: true);
      expect(redirected, isA<ServersScreen>(), reason: legacy.name);
      expect((redirected as ServersScreen).isRootTab, isTrue);
    }
    expect(
      moreDestinationScreen(
        MoreDestination.findCreators,
        isRootTab: true,
      ).runtimeType.toString(),
      'FindCreatorsScreen',
    );
  });

  testWidgets(
    'the desktop popover lists secondary people destinations exactly once '
    'and no retired space surface',
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

      // People destinations remain available, each once.
      for (final entry in const {
        'Friends': 'Your circle',
        'Find creators': 'People to follow',
      }.entries) {
        expect(find.text(entry.key), findsOneWidget, reason: entry.key);
        expect(find.text(entry.value), findsOneWidget, reason: entry.value);
      }
      for (final label in ['Creator Studio', 'Awards', 'Alerts']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // Rail-owned destinations and retired standalone surfaces never appear
      // in the popover.
      for (final absent in [
        'Discover',
        'Clubs',
        'Rooms',
        'Moments',
        'YO Moments',
        'Servers',
      ]) {
        expect(find.text(absent), findsNothing, reason: absent);
      }
      // Reading order remains stable for the retained rows.
      expect(
        tester.getCenter(find.text('Friends')).dy,
        lessThan(tester.getCenter(find.text('Find creators')).dy),
      );
      expect(
        tester.getCenter(find.text('Find creators')).dy,
        lessThan(tester.getCenter(find.text('Creator Studio')).dy),
      );

      await tester.tap(find.text('Friends'));
      await tester.pumpAndSettle();
      expect(picked, MoreDestination.friends);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the mobile More sheet exposes no Rooms or Clubs entry', (
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

    // The retained destinations keep their order after the two space aliases
    // leave the launcher.
    const expected = [
      MoreDestination.friends,
      MoreDestination.profile,
      MoreDestination.findCreators,
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
            (topLeft.dy - previous.dy).abs() <= .5 && topLeft.dx > previous.dx;
        expect(
          laterRow || sameRowLater,
          isTrue,
          reason: '${destination.name} keeps its position in reading order',
        );
      }
      previous = topLeft;
    }
    // Servers is a dock root (cell 1), Moments a dock root (cell 3), while
    // Discover, Clubs and Reels are compatibility identities only.
    for (final absent in ['discover', 'clubs', 'servers', 'moments', 'reels']) {
      expect(
        find.byKey(ValueKey('more-destination-$absent')),
        findsNothing,
        reason: absent,
      );
    }
    expect(find.text('Servers'), findsNothing);
    expect(find.text('Discover'), findsNothing);
    expect(find.text('Clubs'), findsNothing);
    expect(find.text('Rooms'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
