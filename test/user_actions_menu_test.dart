import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/presentation/widgets/user_actions_menu.dart';

/// The shared ••• user-actions menu — the client half of the sanction
/// system. The server is the authority (functions/test/sanctions);
/// these tests pin what each tier SEES and what each dialog SENDS.
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  void useSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  const personalLabels = ['Report user', 'Block user', 'Mute for me'];
  const staffLabels = [
    'Warn user…',
    'Mute communication…',
    'Suspend account…',
    'Lift communication mute…',
    'Lift suspension…',
    'Ban permanently…',
    'Unban account…',
  ];

  const moderator = StaffCapabilities(
    staffRole: 'moderator',
    warnUsers: true,
    suspendUsers: true,
    suspensionLimitHours: 24,
  );
  const superMod = StaffCapabilities(
    staffRole: 'superModerator',
    warnUsers: true,
    suspendUsers: true,
    suspensionLimitHours: 720,
    liftSuspensions: true,
  );
  const owner = StaffCapabilities(
    staffRole: 'superAdmin',
    isOwner: true,
    warnUsers: true,
    suspendUsers: true,
    liftSuspensions: true,
    permanentBan: true,
    sanctionStaff: true,
  );

  Future<void> open(
    WidgetTester tester,
    StaffCapabilities caps, {
    FirebaseFunctions? functions,
  }) async {
    await tester.pumpWidget(
      host(
        UserActionsMenu(
          targetUid: 'target-uid',
          targetName: 'Ola',
          capabilities: caps,
          currentUid: 'me-uid',
          functions: functions ?? _RecordingFunctions(),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
  }

  group('per-tier menus', () {
    testWidgets('ordinary, VIP, auditor, support and guideMaster get the '
        'personal section ONLY — no staff trace', (tester) async {
      useSize(tester, const Size(1440, 900));
      const nonStaff = [
        StaffCapabilities.none,
        StaffCapabilities(staffRole: 'user', isVip: true),
        StaffCapabilities(staffRole: 'auditor', readAuditLogs: true),
        StaffCapabilities(staffRole: 'support', supportLookup: true),
        StaffCapabilities(staffRole: 'guideMaster', guideMode: true),
      ];
      for (final caps in nonStaff) {
        await open(tester, caps);
        for (final label in personalLabels) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
        for (final label in staffLabels) {
          expect(
            find.text(label),
            findsNothing,
            reason: '${caps.staffRole} must not see "$label"',
          );
        }
        await tester.tapAt(const Offset(700, 800));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('a moderator gets warn/mute/suspend and NO lift, ban or '
        'unban', (tester) async {
      useSize(tester, const Size(1440, 900));
      await open(tester, moderator);
      for (final label in [
        ...personalLabels,
        'Warn user…',
        'Mute communication…',
        'Suspend account…',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      for (final label in [
        'Lift communication mute…',
        'Lift suspension…',
        'Ban permanently…',
        'Unban account…',
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
    });

    testWidgets('a super moderator adds the lifts; the owner adds ban and '
        'unban', (tester) async {
      useSize(tester, const Size(1440, 900));
      await open(tester, superMod);
      expect(find.text('Lift communication mute…'), findsOneWidget);
      expect(find.text('Lift suspension…'), findsOneWidget);
      expect(find.text('Ban permanently…'), findsNothing);
      await tester.tapAt(const Offset(700, 800));
      await tester.pumpAndSettle();

      await open(tester, owner);
      for (final label in staffLabels) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('your own sheet renders NO menu at all', (tester) async {
      useSize(tester, const Size(1440, 900));
      await tester.pumpWidget(
        host(
          UserActionsMenu(
            targetUid: 'me-uid',
            targetName: 'Me',
            capabilities: owner,
            currentUid: 'me-uid',
            functions: _RecordingFunctions(),
          ),
        ),
      );
      expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
    });

    testWidgets('the menu fits the mobile sheet width', (tester) async {
      useSize(tester, const Size(390, 844));
      await open(tester, owner);
      expect(find.text('Ban permanently…'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('duration bounds', () {
    Future<void> openMuteDialog(
      WidgetTester tester,
      StaffCapabilities caps,
    ) async {
      await open(tester, caps);
      await tester.tap(find.text('Mute communication…'));
      await tester.pumpAndSettle();
    }

    testWidgets('a moderator is offered nothing past 24h and no '
        'Indefinite', (tester) async {
      useSize(tester, const Size(1440, 1100));
      await openMuteDialog(tester, moderator);
      await tester.tap(find.text('1 hours'));
      await tester.pumpAndSettle();
      expect(find.text('24 hours'), findsOneWidget);
      expect(find.text('72 hours'), findsNothing);
      expect(find.text('Indefinite'), findsNothing);
    });

    testWidgets('a super moderator reaches 720h but not Indefinite; the '
        'owner gets Indefinite', (tester) async {
      useSize(tester, const Size(1440, 1100));
      await openMuteDialog(tester, superMod);
      await tester.tap(find.text('1 hours'));
      await tester.pumpAndSettle();
      expect(find.text('720 hours'), findsOneWidget);
      expect(find.text('Indefinite'), findsNothing);
      // Dismiss dropdown and dialog.
      await tester.tap(find.text('720 hours').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(700, 800));
      await tester.pumpAndSettle();

      await openMuteDialog(tester, owner);
      await tester.tap(find.text('1 hours'));
      await tester.pumpAndSettle();
      expect(find.text('Indefinite'), findsOneWidget);
    });
  });

  group('dialog contract', () {
    testWidgets('a communication mute sends applySanction with reason and '
        'duration, shows target and expiry, and blocks double submission', (
      tester,
    ) async {
      useSize(tester, const Size(1440, 1100));
      final functions = _RecordingFunctions();
      await open(tester, moderator, functions: functions);
      await tester.tap(find.text('Mute communication…'));
      await tester.pumpAndSettle();

      // Target, scope and expiry are all stated before the button.
      expect(find.text('Target: Ola'), findsOneWidget);
      expect(
        find.textContaining('platform-wide public communication'),
        findsOneWidget,
      );
      expect(find.textContaining('Expiry: 1h'), findsOneWidget);

      final confirm = find.widgetWithText(FilledButton, 'Apply mute');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.enterText(
        find.widgetWithText(TextField, 'Reason (required)'),
        'spamming the global channel',
      );
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump();
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 120));

      expect(functions.calls, hasLength(1), reason: 'no double submission');
      final call = functions.calls.single;
      expect(call.name, 'applySanction');
      expect(call.payload['action'], 'communicationMute');
      expect(call.payload['uid'], 'target-uid');
      expect(call.payload['durationHours'], 1);
      expect(call.payload['reason'], 'spamming the global channel');
    });

    testWidgets('a suspension routes to setUserBan; a failure keeps the '
        'dialog open with the error and allows retry', (tester) async {
      useSize(tester, const Size(1440, 1100));
      final functions = _RecordingFunctions()..failNext = true;
      await open(tester, superMod, functions: functions);
      await tester.tap(find.text('Suspend account…'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Reason (required)'),
        'ban evasion',
      );
      await tester.pump();
      final confirm = find.widgetWithText(FilledButton, 'Suspend account');
      await tester.tap(confirm);
      await tester.pump(const Duration(milliseconds: 120));

      expect(
        find.text('Could not complete this action. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('rejected by the server'), findsNothing);
      expect(find.byType(SanctionDialog), findsOneWidget);

      await tester.tap(confirm);
      await tester.pump(const Duration(milliseconds: 120));
      expect(functions.calls, hasLength(2));
      final call = functions.calls.last;
      expect(call.name, 'setUserBan');
      expect(call.payload['banned'], true);
      expect(call.payload['durationHours'], 1);
    });

    testWidgets('the owner\'s permanent ban goes to setUserBan with '
        'duration 0', (tester) async {
      useSize(tester, const Size(1440, 1100));
      final functions = _RecordingFunctions();
      await open(tester, owner, functions: functions);
      await tester.tap(find.text('Ban permanently…'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Reason (required)'),
        'severe repeated abuse',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Ban permanently'));
      await tester.pump(const Duration(milliseconds: 120));

      final call = functions.calls.single;
      expect(call.name, 'setUserBan');
      expect(call.payload['banned'], true);
      expect(call.payload['durationHours'], 0);
    });
  });
}

class _Call {
  _Call(this.name, this.payload);
  final String name;
  final Map<String, dynamic> payload;
}

class _RecordingFunctions implements FirebaseFunctions {
  final calls = <_Call>[];
  bool failNext = false;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _RecordingCallable(this, name);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingCallable implements HttpsCallable {
  _RecordingCallable(this.owner, this.name);
  final _RecordingFunctions owner;
  final String name;

  @override
  Future<HttpsCallableResult<T>> call<T>([Object? parameters]) async {
    // A short real delay so the busy state is observable.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // Recorded BEFORE the failure branch: a call that reached the server
    // is a call, whatever the server answered.
    owner.calls.add(_Call(name, Map<String, dynamic>.from(parameters as Map)));
    if (owner.failNext) {
      owner.failNext = false;
      throw Exception('rejected by the server');
    }
    return _FakeResult<T>({'outcome': 'ok'} as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResult<T> implements HttpsCallableResult<T> {
  _FakeResult(this.data);
  @override
  final T data;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
