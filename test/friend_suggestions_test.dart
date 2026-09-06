import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/friends/presentation/screens/friends_screen.dart';
import 'package:yovoice/features/friends/presentation/widgets/friend_suggestion_card.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';

/// "People you may know" on the Friends screen: the rail, its states, and
/// proof that the row affordances it sits above still work.
void main() {
  const me = 'receiver';

  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  late List<({String name, Map<String, dynamic> data})> calls;
  late List<MessageService> ownedServices;

  SuggestedFriend suggestion(String uid, String name, {int mutualCount = 2}) =>
      SuggestedFriend(
        uid: uid,
        displayName: name,
        photoUrl: null,
        mutualCount: mutualCount,
      );

  Future<void> seedFriend(String id, String name) async {
    await db.collection('users').doc(me).collection('friends').doc(id).set({
      'displayName': name,
    });
    await db.collection('publicProfiles').doc(id).set({
      'uid': id,
      'displayName': name,
    });
  }

  setUp(() async {
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: me, email: 'receiver@yovoice.app'),
    );
    calls = [];
    ownedServices = [];
    await db.collection('users').doc(me).set({
      'uid': me,
      'displayName': 'Receiver',
    });
  });

  tearDown(() {
    for (final service in ownedServices) {
      unawaited(service.dispose());
    }
    FriendService.clearSharedReadCaches();
  });

  Widget app({
    required SocialGraphService graph,
    FriendMutationInvoker? invoker,
    TextScaler textScaler = TextScaler.noScaling,
    ThemeData? theme,
  }) {
    final friends = FriendService(
      firestore: db,
      auth: auth,
      mutationInvoker:
          invoker ??
          (name, data) async {
            calls.add((name: name, data: data));
            return const {'outcome': 'requested', 'changed': true};
          },
    );
    final messages = MessageService(firestore: db, auth: auth);
    ownedServices.add(messages);
    return MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: FriendsScreen(
        showRequestsInitially: false,
        friendService: friends,
        messageService: messages,
        socialGraphService: graph,
        firestore: db,
        auth: auth,
      ),
    );
  }

  testWidgets('the rail renders suggestions with their mutual-friend counts', (
    tester,
  ) async {
    await seedFriend('ada', 'Ada');
    await tester.pumpWidget(
      app(
        graph: _StubGraph([
          suggestion('riley', 'Riley', mutualCount: 3),
          suggestion('sam', 'Sam', mutualCount: 1),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('People you may know'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('friend-suggestions-rail')),
      findsOneWidget,
    );
    expect(find.text('Riley'), findsOneWidget);
    expect(find.text('3 mutual friends'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('1 mutual friend'), findsOneWidget);
    // The rail sits between the summary row and the friend list.
    final railTop = tester
        .getTopLeft(find.byKey(const ValueKey('friend-suggestions-rail')))
        .dy;
    expect(
      railTop,
      greaterThan(tester.getBottomLeft(find.text('1 friend')).dy),
    );
    expect(railTop, lessThan(tester.getTopLeft(find.text('Ada')).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Add sends the request for that uid and confirms with Sent', (
    tester,
  ) async {
    final gate = Completer<Map<String, dynamic>>();
    final reloadGate = Completer<void>();
    await seedFriend('ada', 'Ada');
    await tester.pumpWidget(
      app(
        graph: _StubGraph([
          suggestion('riley', 'Riley'),
          suggestion('sam', 'Sam'),
        ], reloadGate: reloadGate.future),
        invoker: (name, data) {
          calls.add((name: name, data: data));
          return gate.future;
        },
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('friend-suggestion-rail-riley'));
    expect(card, findsOneWidget);
    final add = find.descendant(
      of: card,
      matching: find.widgetWithText(FilledButton, 'Add'),
    );
    expect(tester.getSize(add).height, greaterThanOrEqualTo(44));

    await tester.tap(add);
    await tester.pump();

    // Busy: a spinner inside the card, and the action refuses further taps.
    expect(
      find.descendant(
        of: card,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(of: card, matching: find.byType(FilledButton)),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(
      find.descendant(of: card, matching: find.byType(FilledButton)),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(calls, hasLength(1));

    gate.complete(const {'outcome': 'requested', 'changed': true});
    await tester.pumpAndSettle();

    expect(calls.single.name, 'sendFriendRequest');
    expect(calls.single.data, {'targetUserId': 'riley'});
    expect(
      find.descendant(of: card, matching: find.text('Sent')),
      findsOneWidget,
      reason: 'the confirmation is visible before the reload lands',
    );
    expect(find.text('Friend request sent to Riley.'), findsOneWidget);

    reloadGate.complete();
    await tester.pumpAndSettle();
    expect(
      card,
      findsNothing,
      reason: 'the refreshed rail drops the person who was just added',
    );
    expect(find.text('Sam'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a reciprocal accept renders Friends instead of Sent', (
    tester,
  ) async {
    await seedFriend('ada', 'Ada');
    await tester.pumpWidget(
      app(
        graph: _StubGraph([suggestion('riley', 'Riley')]),
        invoker: (name, data) async {
          calls.add((name: name, data: data));
          return const {'outcome': 'accepted', 'changed': true};
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('Friends'), findsWidgets);
    expect(find.text('Sent'), findsNothing);
    expect(find.text('You and Riley are now friends.'), findsOneWidget);
  });

  testWidgets('a failed send restores the action and never claims success', (
    tester,
  ) async {
    await seedFriend('ada', 'Ada');
    await tester.pumpWidget(
      app(
        graph: _StubGraph([suggestion('riley', 'Riley')]),
        invoker: (name, data) async {
          calls.add((name: name, data: data));
          throw StateError('boom');
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('Sent'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Add'), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
  });

  testWidgets('a refused send names the refusal with the shared copy', (
    tester,
  ) async {
    await seedFriend('ada', 'Ada');
    await tester.pumpWidget(
      app(
        graph: _StubGraph([suggestion('riley', 'Riley')]),
        invoker: (name, data) async =>
            throw StateError('You are already friends.'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('You are already friends.'), findsOneWidget);
  });

  testWidgets('a successful send reloads the rail without that person', (
    tester,
  ) async {
    await seedFriend('ada', 'Ada');
    final graph = _StubGraph([
      suggestion('riley', 'Riley'),
      suggestion('sam', 'Sam'),
    ]);
    await tester.pumpWidget(app(graph: graph));
    await tester.pumpAndSettle();
    expect(graph.calls, 1);

    await tester.tap(find.widgetWithText(FilledButton, 'Add').first);
    await tester.pumpAndSettle();

    expect(graph.calls, 2, reason: 'the rail refreshes after a successful add');
    expect(find.text('Riley'), findsNothing);
    expect(find.text('Sam'), findsOneWidget);
  });

  testWidgets('a rate-limited refresh keeps the rail and the Sent state', (
    tester,
  ) async {
    await seedFriend('ada', 'Ada');
    final graph = _StubGraph([
      suggestion('riley', 'Riley'),
      suggestion('sam', 'Sam'),
    ], failAfterFirst: true);
    await tester.pumpWidget(app(graph: graph));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Add').first);
    await tester.pumpAndSettle();

    expect(graph.calls, 2);
    expect(find.text('Could not load suggestions'), findsNothing);
    expect(find.text('Riley'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
  });

  testWidgets('a failure offers Retry and never claims there is nobody', (
    tester,
  ) async {
    await seedFriend('ada', 'Ada');
    final graph = _StubGraph([suggestion('riley', 'Riley')], failFirst: true);
    await tester.pumpWidget(app(graph: graph));
    await tester.pumpAndSettle();

    expect(find.text('People you may know'), findsOneWidget);
    expect(find.text('Could not load suggestions'), findsOneWidget);
    expect(find.text('No users found'), findsNothing);
    expect(find.text('No friends yet'), findsNothing);
    expect(find.byKey(const ValueKey('friend-suggestions-rail')), findsNothing);

    final retry = find.byKey(const ValueKey('friend-suggestions-retry'));
    expect(tester.getSize(retry).height, greaterThanOrEqualTo(44));
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(graph.calls, 2);
    expect(find.text('Riley'), findsOneWidget);
    expect(find.text('Could not load suggestions'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty suggestion result renders nothing at all', (
    tester,
  ) async {
    await seedFriend('ada', 'Ada');
    await tester.pumpWidget(app(graph: _StubGraph(const [])));
    await tester.pumpAndSettle();

    expect(find.text('People you may know'), findsNothing);
    expect(find.byKey(const ValueKey('friend-suggestions-rail')), findsNothing);
    expect(
      find.byKey(const ValueKey('friend-suggestions-error')),
      findsNothing,
    );
    expect(find.text('Ada'), findsOneWidget);
  });

  testWidgets('a suggestion who is already a friend is filtered out', (
    tester,
  ) async {
    await seedFriend('ada', 'Ada');
    await tester.pumpWidget(
      app(
        graph: _StubGraph([suggestion('ada', 'Ada'), suggestion('sam', 'Sam')]),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('friend-suggestion-rail-ada')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('friend-suggestion-rail-sam')),
      findsOneWidget,
    );
  });

  testWidgets('the rail is offered inside the no-friends empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(graph: _StubGraph([suggestion('riley', 'Riley')])),
    );
    await tester.pumpAndSettle();

    // The existing empty message is preserved, not replaced.
    expect(find.text('No friends yet'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add friend'), findsOneWidget);
    expect(find.text('People you may know'), findsOneWidget);
    expect(find.text('Riley'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('People you may know')).dy,
      greaterThan(tester.getBottomLeft(find.text('No friends yet')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('search and the Online filter suppress the rail', (tester) async {
    await seedFriend('ada', 'Ada');
    await tester.pumpWidget(
      app(graph: _StubGraph([suggestion('riley', 'Riley')])),
    );
    await tester.pumpAndSettle();
    expect(find.text('People you may know'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ad');
    await tester.pumpAndSettle();
    expect(find.text('People you may know'), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Online'));
    await tester.pumpAndSettle();
    expect(find.text('People you may know'), findsNothing);
  });

  testWidgets(
    'the rail never restarts its callable across filter round trips',
    (tester) async {
      await seedFriend('ada', 'Ada');
      final graph = _StubGraph([suggestion('riley', 'Riley')]);
      await tester.pumpWidget(app(graph: graph));
      await tester.pumpAndSettle();
      expect(graph.calls, 1);

      await tester.tap(find.text('Requests'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();

      expect(
        graph.calls,
        1,
        reason:
            'a rate-limited callable must not refire on every filter change',
      );
      expect(find.text('Riley'), findsOneWidget);
    },
  );

  testWidgets('a deep link into Requests defers the suggestions callable', (
    tester,
  ) async {
    await seedFriend('ada', 'Ada');
    final graph = _StubGraph([suggestion('riley', 'Riley')]);
    final friends = FriendService(
      firestore: db,
      auth: auth,
      mutationInvoker: (name, data) async {
        calls.add((name: name, data: data));
        return const {'outcome': 'requested', 'changed': true};
      },
    );
    final messages = MessageService(firestore: db, auth: auth);
    ownedServices.add(messages);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: FriendsScreen(
          showRequestsInitially: true,
          friendService: friends,
          messageService: messages,
          socialGraphService: graph,
          firestore: db,
          auth: auth,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      graph.calls,
      0,
      reason: 'the quota-limited callable is not spent on an unrendered rail',
    );

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(graph.calls, 1);
    expect(find.text('Riley'), findsOneWidget);
  });

  testWidgets('Message, the options sheet and Remove friend still work', (
    tester,
  ) async {
    await seedFriend('ada', 'Ada');
    await tester.pumpWidget(
      app(graph: _StubGraph([suggestion('riley', 'Riley')])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Riley'), findsOneWidget);
    expect(find.byTooltip('Message'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('friend-options-ada')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('friend-options-ada')));
    await tester.pumpAndSettle();
    expect(find.text('View profile'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('friend-remove-action')));
    await tester.pumpAndSettle();
    expect(find.text('Remove friend?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('friend-remove-confirm')));
    await tester.pumpAndSettle();

    final remove = calls.singleWhere((call) => call.name == 'removeFriend');
    expect(remove.data['targetUserId'], 'ada');
    expect(find.text('Ada was removed from your friends.'), findsOneWidget);

    await tester.ensureVisible(find.text('Ada'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Ada'));
    await tester.pumpAndSettle();
    expect(find.text('Remove friend'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the loading skeleton shows no fabricated person', (
    tester,
  ) async {
    final gate = Completer<List<SuggestedFriend>>();
    await seedFriend('ada', 'Ada');
    await tester.pumpWidget(app(graph: _PendingGraph(gate.future)));
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('friend-suggestions-loading')),
      findsOneWidget,
    );
    expect(find.text('People you may know'), findsOneWidget);
    expect(find.byType(FriendSuggestionCard), findsNothing);

    gate.complete([suggestion('riley', 'Riley')]);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('friend-suggestions-loading')),
      findsNothing,
    );
    expect(find.text('Riley'), findsOneWidget);
  });

  for (final layout in const <({String name, Size size, double scale})>[
    (name: 'narrow at 200% text', size: Size(320, 720), scale: 2),
    (name: 'medium', size: Size(834, 1000), scale: 1),
    (name: 'wide', size: Size(1440, 900), scale: 1),
  ]) {
    testWidgets('the rail survives ${layout.name}', (tester) async {
      tester.view.physicalSize = layout.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await seedFriend('ada', 'Ada');
      await tester.pumpWidget(
        app(
          textScaler: TextScaler.linear(layout.scale),
          graph: _StubGraph([
            suggestion(
              'riley',
              'Riley With A Deliberately Long Display Name That Wraps',
              mutualCount: 12,
            ),
            suggestion('sam', 'Sam'),
            suggestion('nina', 'Nina', mutualCount: 0),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      final rail = find.byKey(const ValueKey('friend-suggestions-rail'));
      // At 320 px and 200% text the screen's own header, search field and
      // filter row already fill the viewport, so the rail lives below the
      // fold. It must still be reachable and intact, not clipped away.
      await tester.scrollUntilVisible(
        rail,
        220,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(rail, findsOneWidget);
      // Every card in the rail is the same height and stays inside it.
      final railRect = tester.getRect(rail);
      for (final uid in const ['riley', 'sam', 'nina']) {
        final card = find.byKey(ValueKey('friend-suggestion-rail-$uid'));
        expect(card, findsOneWidget);
        expect(tester.getSize(card).height, closeTo(railRect.height, 0.5));
      }
      expect(tester.getSize(rail).width, lessThanOrEqualTo(layout.size.width));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('rail chrome uses the semantic Pearl and dark palettes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(768, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final themeCase in <({ThemeData theme, AppPalette palette})>[
      (theme: AppTheme.lightTheme, palette: AppPalette.light),
      (theme: AppTheme.darkTheme, palette: AppPalette.dark),
    ]) {
      await tester.pumpWidget(
        app(
          theme: themeCase.theme,
          graph: _StubGraph([suggestion('riley', 'Riley')]),
        ),
      );
      await tester.pumpAndSettle();

      final card = tester.widget<Container>(
        find.byKey(const ValueKey('friend-suggestion-rail-riley')),
      );
      final decoration = card.decoration! as BoxDecoration;
      expect(decoration.color, themeCase.palette.surface);
      expect(
        (decoration.border! as Border).top.color,
        themeCase.palette.border,
      );
      expect(
        tester.widget<Text>(find.text('People you may know')).style!.color,
        themeCase.palette.textPrimary,
      );
      expect(
        tester.widget<Text>(find.text('2 mutual friends')).style!.color,
        themeCase.palette.textSecondary,
      );
      expect(tester.takeException(), isNull);
    }
  });
}

class _StubGraph implements SocialGraphService {
  _StubGraph(
    this.suggestions, {
    this.failFirst = false,
    this.failAfterFirst = false,
    this.reloadGate,
  });

  final List<SuggestedFriend> suggestions;

  /// Fails the initial load so the error state and Retry can be exercised.
  final bool failFirst;

  /// Fails every reload, standing in for the callable's per-minute quota.
  final bool failAfterFirst;

  /// Holds the post-send reload open so the "Sent" confirmation can be
  /// observed before the refreshed rail replaces it.
  final Future<void>? reloadGate;

  int calls = 0;

  @override
  Future<List<SuggestedFriend>> getFriendSuggestions({int limit = 10}) async {
    calls += 1;
    if (failFirst && calls == 1) {
      throw StateError('resource-exhausted');
    }
    if (failAfterFirst && calls > 1) {
      throw StateError('resource-exhausted');
    }
    if (calls > 1 && reloadGate != null) {
      await reloadGate;
    }
    return suggestions.take(limit).toList(growable: false);
  }

  @override
  Future<MutualFriendsSummary> getMutualFriends(String targetUserId) async =>
      MutualFriendsSummary.empty;
}

class _PendingGraph implements SocialGraphService {
  _PendingGraph(this.pending);

  final Future<List<SuggestedFriend>> pending;

  @override
  Future<List<SuggestedFriend>> getFriendSuggestions({int limit = 10}) =>
      pending;

  @override
  Future<MutualFriendsSummary> getMutualFriends(String targetUserId) async =>
      MutualFriendsSummary.empty;
}
