import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/clubs/data/models/club_invite.dart';
import 'package:yovoice/features/servers/data/models/server_invite.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/servers/presentation/screens/server_invite_response_screen.dart';

const _serverId = 'family-hub';
const _inviteeId = 'invitee';
final _now = DateTime.utc(2026, 9, 13, 12);

Map<String, Object?> _inviteData({
  String serverId = _serverId,
  String inviteeId = _inviteeId,
  String status = 'pending',
  DateTime? expiresAt,
}) => {
  'serverSchemaVersion': 1,
  'serverId': serverId,
  'inviteeId': inviteeId,
  'inviterId': 'owner',
  'inviterAuthorizationRevision': 3,
  'status': status,
  'generation': 2,
  'expiresAt': Timestamp.fromDate(
    expiresAt ?? _now.add(const Duration(days: 2)),
  ),
  'serverName': 'Rodzina Nowaków',
  'inviterName': 'Marta',
  'createdAt': Timestamp.fromDate(_now.subtract(const Duration(hours: 1))),
  'updatedAt': Timestamp.fromDate(_now.subtract(const Duration(hours: 1))),
};

Future<void> _seedInvite(
  FakeFirebaseFirestore firestore, {
  Map<String, Object?>? data,
}) => firestore
    .doc('clubs/$_serverId/invites/$_inviteeId')
    .set(data ?? _inviteData());

MockFirebaseAuth _auth() => MockFirebaseAuth(
  signedIn: true,
  mockUser: MockUser(uid: _inviteeId, email: 'invitee@yovoice.app'),
);

Future<void> _pumpInvite(
  WidgetTester tester, {
  required FakeFirebaseFirestore firestore,
  required ServerService service,
  Size size = const Size(390, 844),
  double textScale = 1,
  LegacyServerInviteAction? acceptLegacyInvite,
  LegacyServerInviteAction? declineLegacyInvite,
}) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('pl'),
      theme: AppTheme.darkTheme,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: ServerInviteResponseScreen(
        serverId: _serverId,
        firestore: firestore,
        auth: _auth(),
        service: service,
        now: () => _now,
        acceptLegacyInvite: acceptLegacyInvite,
        declineLegacyInvite: declineLegacyInvite,
        workspaceBuilder: (serverId) => Scaffold(
          body: Center(
            child: Text(
              'workspace:$serverId',
              key: const ValueKey('accepted-server-workspace'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('invite preview accepts only the exact V1 path-bound contract', () {
    final invite = ServerInvite.fromMap(
      serverId: _serverId,
      inviteeId: _inviteeId,
      data: _inviteData(),
    );
    expect(invite.serverId, _serverId);
    expect(invite.inviteeId, _inviteeId);
    expect(invite.serverName, 'Rodzina Nowaków');
    expect(invite.isActionableAt(_now), isTrue);
    expect(
      () => ServerInvite.fromMap(
        serverId: 'different-path',
        inviteeId: _inviteeId,
        data: _inviteData(),
      ),
      throwsFormatException,
    );
    expect(
      () => ServerInvite.fromMap(
        serverId: _serverId,
        inviteeId: _inviteeId,
        data: {..._inviteData(), 'inviterAuthorizationRevision': 0},
      ),
      throwsFormatException,
    );
    for (final requiredTimestamp in ['expiresAt', 'createdAt', 'updatedAt']) {
      expect(
        () => ServerInvite.fromMap(
          serverId: _serverId,
          inviteeId: _inviteeId,
          data: {..._inviteData(), requiredTimestamp: null},
        ),
        throwsFormatException,
        reason: requiredTimestamp,
      );
    }
  });

  testWidgets(
    'accept calls the exact V1 endpoint and opens the confirmed server',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedInvite(firestore);
      final calls = <(String, Map<String, Object?>)>[];
      final service = ServerService(
        firestore: firestore,
        auth: _auth(),
        call: (name, data) async {
          calls.add((name, data));
          return {
            'serverId': _serverId,
            'joined': true,
            'alreadyMember': false,
            'membershipRevision': 1,
            'inviteGeneration': 2,
          };
        },
      );
      await _pumpInvite(tester, firestore: firestore, service: service);

      expect(find.text('Rodzina Nowaków'), findsOneWidget);
      expect(find.text('Marta zaprasza Cię do tego serwera.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('accept-server-invite')));
      await tester.pumpAndSettle();

      expect(calls, hasLength(1));
      expect(calls.single.$1, 'respondToServerInviteV1');
      expect(calls.single.$2['serverId'], _serverId);
      expect(calls.single.$2['response'], 'accept');
      expect(
        calls.single.$2['requestId'],
        isA<String>().having(
          (value) => value,
          '48 lowercase hexadecimal characters',
          matches(RegExp(r'^[0-9a-f]{48}$')),
        ),
      );
      expect(
        find.byKey(const ValueKey('accepted-server-workspace')),
        findsOneWidget,
      );
      expect(find.text('workspace:$_serverId'), findsOneWidget);
    },
  );

  testWidgets('an ambiguous accept retries with the same request id', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _seedInvite(firestore);
    final calls = <Map<String, Object?>>[];
    final service = ServerService(
      firestore: firestore,
      auth: _auth(),
      call: (name, data) async {
        expect(name, 'respondToServerInviteV1');
        calls.add(data);
        if (calls.length == 1) {
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'Connection dropped after commit.',
          );
        }
        return {
          'serverId': _serverId,
          'joined': true,
          'alreadyMember': true,
          'membershipRevision': 1,
          'inviteGeneration': 2,
        };
      },
    );
    await _pumpInvite(tester, firestore: firestore, service: service);

    await tester.tap(find.byKey(const ValueKey('accept-server-invite')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('server-invite-error')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('accept-server-invite')));
    await tester.pumpAndSettle();

    expect(calls, hasLength(2));
    expect(calls[1]['requestId'], calls[0]['requestId']);
    expect(
      find.byKey(const ValueKey('accepted-server-workspace')),
      findsOneWidget,
    );
  });

  testWidgets('decline uses the V1 response and closes the active preview', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _seedInvite(firestore);
    final calls = <(String, Map<String, Object?>)>[];
    final service = ServerService(
      firestore: firestore,
      auth: _auth(),
      call: (name, data) async {
        calls.add((name, data));
        return {
          'serverId': _serverId,
          'response': 'decline',
          'inviteGeneration': 2,
        };
      },
    );
    await _pumpInvite(tester, firestore: firestore, service: service);

    await tester.tap(find.byKey(const ValueKey('decline-server-invite')));
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    expect(calls.single.$1, 'respondToServerInviteV1');
    expect(calls.single.$2['response'], 'decline');
    expect(
      find.byKey(const ValueKey('server-invite-unavailable')),
      findsOneWidget,
    );
  });

  testWidgets('expired invites fail closed before any mutation', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _seedInvite(
      firestore,
      data: _inviteData(expiresAt: _now.subtract(const Duration(seconds: 1))),
    );
    var called = false;
    final service = ServerService(
      firestore: firestore,
      auth: _auth(),
      call: (name, data) async {
        called = true;
        return <Object?, Object?>{};
      },
    );
    await _pumpInvite(tester, firestore: firestore, service: service);

    expect(
      find.byKey(const ValueKey('server-invite-unavailable')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('accept-server-invite')), findsNothing);
    expect(called, isFalse);
  });

  testWidgets(
    'a pending legacy invitation keeps working through the Server UI',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedInvite(
        firestore,
        data: {
          'clubId': _serverId,
          'clubName': 'Rodzina Nowaków',
          'clubAvatarUrl': null,
          'inviteeId': _inviteeId,
          'inviterId': 'owner',
          'inviterName': 'Marta',
          'status': 'pending',
          'createdAt': Timestamp.fromDate(_now),
        },
      );
      ClubInvite? accepted;
      var v1Called = false;
      final service = ServerService(
        firestore: firestore,
        auth: _auth(),
        call: (name, data) async {
          v1Called = true;
          return <Object?, Object?>{};
        },
      );
      await _pumpInvite(
        tester,
        firestore: firestore,
        service: service,
        acceptLegacyInvite: (invite) async => accepted = invite,
        declineLegacyInvite: (_) async {},
      );

      expect(find.text('Zaproszenie do serwera'), findsOneWidget);
      expect(find.textContaining('klubu'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('accept-server-invite')));
      await tester.pumpAndSettle();

      expect(accepted?.clubId, _serverId);
      expect(v1Called, isFalse);
      expect(
        find.byKey(const ValueKey('accepted-server-workspace')),
        findsOneWidget,
      );
    },
  );

  testWidgets('a path-mismatched legacy invitation fails closed', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _seedInvite(
      firestore,
      data: {
        'clubId': 'another-server',
        'clubName': 'Wrong',
        'inviteeId': _inviteeId,
        'inviterId': 'owner',
        'inviterName': 'Marta',
        'status': 'pending',
        'createdAt': Timestamp.fromDate(_now),
      },
    );
    final service = ServerService(
      firestore: firestore,
      auth: _auth(),
      call: (name, data) async => <Object?, Object?>{},
    );
    await _pumpInvite(tester, firestore: firestore, service: service);

    expect(
      find.byKey(const ValueKey('server-invite-unavailable')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('accept-server-invite')), findsNothing);
  });

  testWidgets('actions remain usable at phone width and 200 percent text', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _seedInvite(firestore);
    final service = ServerService(
      firestore: firestore,
      auth: _auth(),
      call: (name, data) async => <Object?, Object?>{},
    );
    await _pumpInvite(
      tester,
      firestore: firestore,
      service: service,
      size: const Size(320, 760),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    final accept = find.byKey(const ValueKey('accept-server-invite'));
    final decline = find.byKey(const ValueKey('decline-server-invite'));
    expect(accept, findsOneWidget);
    expect(decline, findsOneWidget);
    expect(tester.getSize(accept).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(decline).height, greaterThanOrEqualTo(48));
    expect(
      tester.getTopLeft(accept).dy,
      lessThan(tester.getTopLeft(decline).dy),
    );
  });
}
