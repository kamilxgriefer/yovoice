import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';

class _NoStaffCapabilities extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      StaffCapabilities.none;
}

void main() {
  testWidgets(
    '320px and 2x text use readable rows with reachable named 44px actions',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SizedBox.expand(
                child: MoreSheet(
                  capabilityService: _NoStaffCapabilities(),
                  currentUid: 'ordinary-user',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        tester.getCenter(find.text('Clubs')).dy,
        greaterThan(tester.getCenter(find.text('Profile')).dy),
        reason: 'large text must use full-width rows in reading order',
      );
      expect(
        tester
            .getCenter(find.byKey(const ValueKey('more-destination-clubs')))
            .dx,
        closeTo(
          tester
              .getCenter(find.byKey(const ValueKey('more-destination-profile')))
              .dx,
          1,
        ),
      );
      expect(find.text('Communities'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('more-sheet-scroll-view')),
        findsOneWidget,
      );

      final actions = <MoreDestination, String>{
        MoreDestination.friends: 'Friends, Your circle',
        MoreDestination.profile: 'Profile, You',
        MoreDestination.discover: 'Discover, Find rooms',
        MoreDestination.findCreators: 'Find creators, People to follow',
        MoreDestination.reels: 'Reels, Create and watch',
        MoreDestination.clubs: 'Clubs, Communities, Premium required',
        MoreDestination.notifications: 'Alerts, Updates',
        MoreDestination.achievements: 'Awards, Progress',
        MoreDestination.creatorStudio: 'Creator, Studio, Premium required',
        MoreDestination.settings:
            'Settings, Privacy, account and application preferences',
      };

      for (final entry in actions.entries) {
        final target = find.byKey(
          ValueKey('more-destination-${entry.key.name}'),
        );
        expect(target, findsOneWidget, reason: entry.key.name);
        final size = tester.getSize(target);
        expect(size.width, greaterThanOrEqualTo(44), reason: entry.key.name);
        expect(size.height, greaterThanOrEqualTo(44), reason: entry.key.name);

        final data = tester.getSemantics(target).getSemanticsData();
        expect(data.label, entry.value, reason: entry.key.name);
        expect(
          data.hasAction(ui.SemanticsAction.tap),
          isTrue,
          reason: entry.key.name,
        );

        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(target.hitTestable(), findsOneWidget, reason: entry.key.name);
      }

      expect(tester.takeException(), isNull);
      expect(
        find.text('Privacy, account and application preferences'),
        findsOne,
      );
      semantics.dispose();
    },
  );
}
