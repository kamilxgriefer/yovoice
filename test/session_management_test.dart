import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/settings/data/services/session_management_service.dart';
import 'package:yovoice/features/settings/presentation/screens/device_sessions_screen.dart';

SessionManagementService service({
  Future<Map<String, dynamic>> Function()? revoke,
  Future<CurrentSessionInfo> Function()? session,
}) => SessionManagementService(
  currentSessionLoader:
      session ??
      () async => CurrentSessionInfo(
        signedInAt: DateTime(2026, 8, 18, 7),
        providerLabels: const ['Google'],
      ),
  revokeSessionsCall:
      revoke ?? () async => {'revoked': true, 'completeWithinSeconds': 3600},
);

Widget app(Widget child, {Size size = const Size(390, 844)}) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: MediaQuery(
    data: MediaQueryData(size: size),
    child: child,
  ),
);

void main() {
  test('session service accepts only a bounded canonical response', () async {
    final result = await service().signOutEverywhere();
    expect(result.completeWithin, const Duration(hours: 1));

    for (final response in <Map<String, dynamic>>[
      {},
      {'revoked': false, 'completeWithinSeconds': 3600},
      {'revoked': true, 'completeWithinSeconds': 0},
      {'revoked': true, 'completeWithinSeconds': 100000},
    ]) {
      await expectLater(
        service(revoke: () async => response).signOutEverywhere(),
        throwsA(isA<SessionManagementFailure>()),
      );
    }
  });

  testWidgets('shows only the real current session and the global action', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        DeviceSessionsScreen(
          service: service(),
          signOutCurrentDevice: () async {},
          deviceLabel: 'This test device',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Devices & sessions'), findsOneWidget);
    expect(find.text('This test device'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Google'), findsOneWidget);
    expect(
      find.textContaining('does not receive a trustworthy'),
      findsOneWidget,
    );
    expect(find.text('Sign out everywhere'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('global action confirms, revokes, then signs out locally', (
    tester,
  ) async {
    var revoked = false;
    var signedOut = false;
    await tester.pumpWidget(
      app(
        DeviceSessionsScreen(
          service: service(
            revoke: () async {
              revoked = true;
              return {'revoked': true, 'completeWithinSeconds': 3600};
            },
          ),
          signOutCurrentDevice: () async => signedOut = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign out everywhere'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out on every device?'), findsOneWidget);
    await tester.tap(find.text('Sign out everywhere').last);
    await tester.pumpAndSettle();

    expect(revoked, isTrue);
    expect(signedOut, isTrue);
  });

  testWidgets('failure stays on-screen in a live error region', (tester) async {
    await tester.pumpWidget(
      app(
        DeviceSessionsScreen(
          service: service(
            revoke: () async => throw FirebaseFunctionsException(
              code: 'unavailable',
              message: 'private backend detail',
            ),
          ),
          signOutCurrentDevice: () async {
            fail('must not sign out after a failed revocation');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out everywhere'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out everywhere').last);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('could not sign out every device'),
      findsOneWidget,
    );
    expect(find.textContaining('private backend detail'), findsNothing);
  });

  testWidgets('phone-width layout scrolls without overflow', (tester) async {
    await tester.pumpWidget(
      app(
        DeviceSessionsScreen(
          service: service(),
          signOutCurrentDevice: () async {},
        ),
        size: const Size(320, 568),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
