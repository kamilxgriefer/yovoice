import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/data/staff_directory_service.dart';
import 'package:yovoice/features/staff/presentation/sections/staff_users_section.dart';

class _Directory implements StaffDirectoryService {
  @override
  Future<DirectorySearchPage> search({
    String query = '',
    String filter = 'all',
    String? cursor,
  }) async => DirectorySearchPage(
    users: [
      DirectoryUser(
        uid: 'long-user-id-for-copyable-layout-check',
        displayName: 'A deliberately long member display name',
        username: 'long_member_name',
        email: null,
        photoUrl: null,
        staffRole: 'moderator',
        isVip: true,
        banned: false,
        restricted: false,
        createdAt: DateTime(2026, 8, 16),
      ),
    ],
    nextCursor: null,
    mode: 'browse',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('row follows local 320px width and View target stays 44px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 320,
                height: 700,
                child: StaffUsersSection(
                  capabilities: StaffCapabilities.none,
                  currentUid: 'owner',
                  directoryService: _Directory(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final viewButton = find.widgetWithText(FilledButton, 'View');
    expect(viewButton, findsOneWidget);
    expect(tester.getSize(viewButton).height, greaterThanOrEqualTo(44));
    expect(find.text('@long_member_name'), findsOneWidget);
  });
}
