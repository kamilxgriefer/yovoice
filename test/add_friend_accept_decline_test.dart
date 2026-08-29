import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
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

  FriendService buildService({String? sendOutcome}) {
    return FriendService(
      firestore: db,
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: meUid)),
      mutationInvoker: (name, data) async {
        calls.add((name: name, data: data));
        await mutationGate?.future;
        if (name == 'sendFriendRequest') {
          return <String, dynamic>{
            'changed': true,
            'outcome': sendOutcome ?? 'requested',
          };
        }
        return const <String, dynamic>{'changed': true};
      },
      searchInvoker: (query, limit) async => [
        {'uid': otherUid, 'displayName': 'Riley', 'username': 'riley'},
      ],
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    FriendService service, {
    TextScaler textScaler = TextScaler.noScaling,
    SocialGraphService? socialGraphService,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: AddFriendScreen(
          friendService: service,
          socialGraphService: socialGraphService ?? _StubSocialGraphService(),
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

  testWidgets('Accept on a received request invokes acceptFriendRequest, '
      'never sendFriendRequest', (tester) async {
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
      reason: 'accepting must never route through the reciprocal-send branch',
    );

    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('You and Riley are now friends.'), findsOneWidget);
  });

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
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
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

  testWidgets('received actions remain reachable at 320px and 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpScreen(
      tester,
      buildService(),
      textScaler: const TextScaler.linear(2),
      theme: AppTheme.lightTheme,
    );
    await searchForRiley(tester);

    expect(find.text('Accept'), findsOneWidget);
    expect(find.byTooltip('Decline friend request'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('suggestion failure is honest and Retry loads the list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final graph = _RetrySocialGraphService();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: AddFriendScreen(
          friendService: buildService(),
          socialGraphService: graph,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load suggestions'), findsOneWidget);
    final retry = find.widgetWithText(FilledButton, 'Retry');
    expect(retry, findsOneWidget);
    expect(tester.getSize(retry).height, greaterThanOrEqualTo(44));

    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.text('Suggested for you'), findsOneWidget);
    expect(find.text('Riley'), findsOneWidget);
    expect(graph.calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reciprocal suggestion acceptance renders Friends, not Sent', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      buildService(sendOutcome: 'accepted'),
      socialGraphService: _SingleSuggestionGraphService(),
    );

    expect(find.text('Riley'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    expect(calls.single.name, 'sendFriendRequest');
    expect(calls.single.data, {'targetUserId': otherUid});
    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('Sent'), findsNothing);
    expect(find.text('You and Riley are now friends.'), findsOneWidget);
  });

  testWidgets('search result chrome follows Pearl and dark semantic palettes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(768, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final themeCase in <({ThemeData theme, AppPalette palette})>[
      (theme: AppTheme.lightTheme, palette: AppPalette.light),
      (theme: AppTheme.darkTheme, palette: AppPalette.dark),
    ]) {
      await pumpScreen(tester, buildService(), theme: themeCase.theme);
      await searchForRiley(tester);

      final scaffold = tester.widget<Scaffold>(
        find.byKey(const ValueKey('add-friend-screen')),
      );
      expect(scaffold.backgroundColor, themeCase.palette.background);

      final card = tester.widget<Container>(
        find.byKey(const ValueKey('friend-search-result-riley-uid')),
      );
      final decoration = card.decoration! as BoxDecoration;
      expect(decoration.color, themeCase.palette.surface);
      expect(
        (decoration.border! as Border).top.color,
        themeCase.palette.border,
      );

      final name = tester.widget<Text>(find.text('Riley'));
      expect(name.style!.color, themeCase.palette.textPrimary);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration!.fillColor, themeCase.palette.surface);
      expect(tester.takeException(), isNull);
    }
  });

  test('unknown friend-request outcomes fail closed', () async {
    final service = buildService(sendOutcome: 'unexpected');

    await expectLater(
      service.sendFriendRequest(
        const FriendUser(
          id: otherUid,
          displayName: 'Riley',
          email: '',
          photoUrl: null,
          isOnline: false,
          lastSeen: null,
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'The friend request returned an invalid response.',
        ),
      ),
    );
  });
}

/// Suggestions are not under test; the screen only needs the future to
/// settle without a Firebase app.
class _StubSocialGraphService extends SocialGraphService {
  @override
  Future<List<SuggestedFriend>> getFriendSuggestions({int limit = 10}) async =>
      const <SuggestedFriend>[];
}

class _SingleSuggestionGraphService extends SocialGraphService {
  @override
  Future<List<SuggestedFriend>> getFriendSuggestions({int limit = 10}) async {
    return const [
      SuggestedFriend(
        uid: 'riley-uid',
        displayName: 'Riley',
        photoUrl: null,
        mutualCount: 2,
      ),
    ];
  }
}

class _RetrySocialGraphService extends SocialGraphService {
  int calls = 0;

  @override
  Future<List<SuggestedFriend>> getFriendSuggestions({int limit = 10}) async {
    calls += 1;
    if (calls == 1) throw StateError('offline');
    return const [
      SuggestedFriend(
        uid: 'riley-uid',
        displayName: 'Riley',
        photoUrl: null,
        mutualCount: 2,
      ),
    ];
  }
}
