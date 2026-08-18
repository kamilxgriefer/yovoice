import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/friends/presentation/screens/add_friend_screen.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

/// AddFriendScreen's "Accept" on a received request MUST travel through the
/// explicit accept mutation (`respondToFriendRequest`, accept: true) and
/// never through `sendFriendRequest` — relying on the server's
/// reciprocal-accept branch is exactly how sending auto-created a
/// friendship. The received state also has to carry a visible decline.
void main() {
  const meUid = 'me-uid';
  const otherUid = 'riley-uid';

  late FakeFirebaseFirestore db;
  late List<({String name, Map<String, dynamic> data})> calls;
  Completer<void>? mutationGate;
  late PublicIdentityRepository originalIdentityRepository;

  setUp(() async {
    db = FakeFirebaseFirestore();
    calls = [];
    mutationGate = null;

    // The received request this screen's row reflects: relationship status
    // resolution reads users/{me}/friendRequests/{other}.
    await db
        .collection('users')
        .doc(meUid)
        .collection('friendRequests')
        .doc(otherUid)
        .set({'senderId': otherUid, 'senderName': 'Riley'});

    // The result cards resolve identity badges through the shared
    // singleton; point it at a scripted fetcher so no Firebase app is
    // needed and the row settles deterministically.
    originalIdentityRepository = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: meUid)),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentityRepository;
  });

  FriendService buildService() {
    return FriendService(
      firestore: db,
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: meUid)),
      mutationInvoker: (name, data) async {
        calls.add((name: name, data: data));
        await mutationGate?.future;
        return const <String, dynamic>{'changed': true};
      },
      searchInvoker: (query, limit) async => [
        {'uid': otherUid, 'displayName': 'Riley', 'username': 'riley'},
      ],
    );
  }

  Future<void> pumpScreen(WidgetTester tester, FriendService service) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: AddFriendScreen(
          friendService: service,
          socialGraphService: _StubSocialGraphService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> searchForRiley(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), 'Ri');
    // Past the 450ms search debounce, then let the lookups settle.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Accept on a received request invokes acceptFriendRequest, '
    'never sendFriendRequest',
    (tester) async {
      await pumpScreen(tester, buildService());
      await searchForRiley(tester);

      expect(find.text('Accept'), findsOneWidget);
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();

      expect(calls, hasLength(1));
      expect(calls.single.name, 'respondToFriendRequest');
      expect(calls.single.data, {'senderId': otherUid, 'accept': true});
      expect(
        calls.where((call) => call.name == 'sendFriendRequest'),
        isEmpty,
        reason:
            'accepting must never route through the reciprocal-send branch',
      );

      expect(find.text('Friends'), findsOneWidget);
      expect(find.text('You and Riley are now friends.'), findsOneWidget);
    },
  );

  testWidgets('the received state shows a decline affordance that invokes '
      'declineFriendRequest', (tester) async {
    await pumpScreen(tester, buildService());
    await searchForRiley(tester);

    final decline = find.byTooltip('Decline friend request');
    expect(decline, findsOneWidget);

    await tester.tap(decline);
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    expect(calls.single.name, 'respondToFriendRequest');
    expect(calls.single.data, {'senderId': otherUid, 'accept': false});

    expect(find.text('Friend request declined.'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.byTooltip('Decline friend request'), findsNothing);
  });

  testWidgets('double taps while the accept is in flight cannot double-fire, '
      'and decline is disabled meanwhile', (tester) async {
    mutationGate = Completer<void>();
    await pumpScreen(tester, buildService());
    await searchForRiley(tester);

    await tester.tap(find.text('Accept'));
    await tester.pump();

    // Second tap lands on the row's now-disabled controls.
    await tester.tap(
      find.byType(FilledButton),
      warnIfMissed: false,
    );
    await tester.tap(
      find.byTooltip('Decline friend request'),
      warnIfMissed: false,
    );
    await tester.pump();

    mutationGate!.complete();
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    expect(calls.single.name, 'respondToFriendRequest');
    expect(calls.single.data, {'senderId': otherUid, 'accept': true});
  });
}

/// Suggestions are not under test; the screen only needs the future to
/// settle without a Firebase app.
class _StubSocialGraphService extends SocialGraphService {
  @override
  Future<List<SuggestedFriend>> getFriendSuggestions({int limit = 10}) async =>
      const <SuggestedFriend>[];
}
