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
  testWidgets('320px and 2x text reflow to two columns and remain scrollable', (
    tester,
  ) async {
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
      reason: 'narrow/high-scale layout must use two columns, not three',
    );
    expect(find.text('Communities'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('more-sheet-scroll-view')),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Privacy, account and application preferences'), findsOne);
  });
}
