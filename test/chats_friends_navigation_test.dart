import 'dart:ui' show SemanticsAction;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_request.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/friends/presentation/screens/friends_screen.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/messages_screen.dart';

class _EmptySocialGraphService extends SocialGraphService {
  @override
  Future<List<SuggestedFriend>> getFriendSuggestions({int limit = 10}) async =>
      const <SuggestedFriend>[];
}

class _FixedFriendService extends FriendService {
  _FixedFriendService({
    required super.firestore,
    required super.auth,
    required this.friends,
  });

  final List<FriendUser> friends;

  @override
  Stream<List<FriendUser>> watchFriends() => Stream.value(friends);

  @override
  Stream<List<FriendRequest>> watchFriendRequests() =>
      Stream.value(const <FriendRequest>[]);

  @override
  Stream<int> watchPendingFriendRequestCount() => Stream.value(0);
}

Widget _localizedApp({required Locale locale, required Widget home}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: AppTheme.darkTheme,
    home: home,
  );
}

void _usePhone(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  TextScaler textScaler = TextScaler.noScaling,
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScaler.scale(1);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  tearDown(FriendService.clearSharedReadCaches);

  group('Chats to retained Friends destination', () {
    for (final localeCase in const [
      (locale: Locale('en'), add: 'Add friend', message: 'New message'),
      (locale: Locale('pl'), add: 'Dodaj znajomego', message: 'Nowa wiadomość'),
    ]) {
      testWidgets('Chats keeps add-friend and new-message separate in '
          '${localeCase.locale.languageCode}', (tester) async {
        _usePhone(tester);
        final firestore = FakeFirebaseFirestore();
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'me', email: 'me@yovoice.app'),
        );
        final messages = MessageService(firestore: firestore, auth: auth);
        addTearDown(messages.dispose);
        final friends = FriendService(firestore: firestore, auth: auth);
        var selectedSlot = -1;

        await tester.pumpWidget(
          _localizedApp(
            locale: localeCase.locale,
            home: MessagesScreen(
              messageService: messages,
              friendService: friends,
              auth: auth,
              onFindFriends: () => selectedSlot = MainShell.friendsSlot,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final addFriend = find.bySemanticsLabel(localeCase.add);
        final newMessage = find.descendant(
          of: find.byKey(const ValueKey('messages-new-message')),
          matching: find.bySemanticsLabel(localeCase.message),
        );
        expect(addFriend, findsOneWidget);
        expect(newMessage, findsOneWidget);
        expect(
          find.byKey(const ValueKey('messages-add-friend')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('messages-new-message')),
          findsOneWidget,
        );
        expect(tester.getSize(addFriend).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(addFriend).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(newMessage).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(newMessage).height, greaterThanOrEqualTo(48));

        final addFriendNode = tester.getSemantics(addFriend);
        expect(
          addFriendNode.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        addFriendNode.owner!.performAction(
          addFriendNode.id,
          SemanticsAction.tap,
        );
        await tester.pump();

        expect(selectedSlot, MainShell.friendsSlot);
        expect(
          find.byKey(const ValueKey('messages-screen')),
          findsOneWidget,
          reason: 'the CTA delegates to MainShell and pushes no route',
        );
        expect(find.byKey(const ValueKey('friends-screen')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('clear Friends onboarding', () {
    for (final localeCase in const [
      (
        locale: Locale('en'),
        title: 'Friends',
        add: 'Add friend',
        currentSearch: 'Search current friends by name or @username...',
        guide:
            'Use Add friend to find someone new. The field below filters current friends.',
        blocked: 'Blocked users',
        requests: 'Friend requests',
      ),
      (
        locale: Locale('pl'),
        title: 'Znajomi',
        add: 'Dodaj znajomego',
        currentSearch: 'Szukaj obecnych znajomych po nazwie lub @username...',
        guide:
            'Przycisk Dodaj znajomego wyszukuje nowe osoby. Pole niżej filtruje obecnych znajomych.',
        blocked: 'Zablokowani użytkownicy',
        requests: 'Zaproszenia do znajomych',
      ),
    ]) {
      testWidgets('new-person search is distinct from the current list in '
          '${localeCase.locale.languageCode}', (tester) async {
        _usePhone(tester);
        final firestore = FakeFirebaseFirestore();
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'me', email: 'me@yovoice.app'),
        );
        final friends = FriendService(firestore: firestore, auth: auth);
        final messages = MessageService(firestore: firestore, auth: auth);
        addTearDown(messages.dispose);

        await tester.pumpWidget(
          _localizedApp(
            locale: localeCase.locale,
            home: FriendsScreen(
              isRootTab: true,
              friendService: friends,
              messageService: messages,
              socialGraphService: _EmptySocialGraphService(),
              firestore: firestore,
              auth: auth,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(localeCase.title), findsOneWidget);
        expect(find.text(localeCase.guide), findsOneWidget);
        final currentSearch = tester.widget<TextField>(
          find.byKey(const ValueKey('current-friend-search')),
        );
        expect(currentSearch.decoration?.hintText, localeCase.currentSearch);

        final addFriend = find.bySemanticsLabel(localeCase.add);
        final requests = find.bySemanticsLabel(localeCase.requests);
        final blocked = find.bySemanticsLabel(localeCase.blocked);
        expect(addFriend, findsOneWidget);
        expect(requests, findsOneWidget);
        expect(blocked, findsOneWidget);
        expect(tester.getSize(addFriend).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(requests).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(blocked).height, greaterThanOrEqualTo(48));

        final addFriendNode = tester.getSemantics(addFriend);
        expect(
          addFriendNode.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
          reason: 'screen readers must be able to activate the primary CTA',
        );
        addFriendNode.owner!.performAction(
          addFriendNode.id,
          SemanticsAction.tap,
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('add-friend-screen')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Friends remains usable at 320px with 200 percent text', (
      tester,
    ) async {
      _usePhone(
        tester,
        size: const Size(320, 720),
        textScaler: const TextScaler.linear(2),
      );
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'me', email: 'me@yovoice.app'),
      );
      final friends = FriendService(firestore: firestore, auth: auth);
      final messages = MessageService(firestore: firestore, auth: auth);
      addTearDown(messages.dispose);

      await tester.pumpWidget(
        _localizedApp(
          locale: const Locale('pl'),
          home: FriendsScreen(
            isRootTab: true,
            friendService: friends,
            messageService: messages,
            socialGraphService: _EmptySocialGraphService(),
            firestore: firestore,
            auth: auth,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final addFriendAny = find.byKey(
        const ValueKey('friends-find-new-person'),
        skipOffstage: false,
      );
      await tester.scrollUntilVisible(
        addFriendAny,
        160,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('friends-coordinated-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final addFriend = find.byKey(const ValueKey('friends-find-new-person'));
      expect(addFriend, findsOneWidget);
      expect(tester.getSize(addFriend).height, greaterThanOrEqualTo(48));
      expect(
        find.byKey(const ValueKey('friends-coordinated-scroll')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('large-text friends use one lazy sliver viewport', (
      tester,
    ) async {
      _usePhone(
        tester,
        size: const Size(320, 720),
        textScaler: const TextScaler.linear(2),
      );
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'me', email: 'me@yovoice.app'),
      );
      final friends = List<FriendUser>.generate(
        200,
        (index) => FriendUser(
          id: 'friend-$index',
          displayName: 'Friend $index',
          username: 'friend$index',
          email: '',
          photoUrl: null,
          isOnline: index.isEven,
          lastSeen: null,
        ),
      );
      final friendService = _FixedFriendService(
        firestore: firestore,
        auth: auth,
        friends: friends,
      );
      final messages = MessageService(firestore: firestore, auth: auth);
      addTearDown(messages.dispose);

      await tester.pumpWidget(
        _localizedApp(
          locale: const Locale('en'),
          home: FriendsScreen(
            isRootTab: true,
            friendService: friendService,
            messageService: messages,
            socialGraphService: _EmptySocialGraphService(),
            firestore: firestore,
            auth: auth,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final viewport = find.byKey(const ValueKey('friends-coordinated-scroll'));
      expect(viewport, findsOneWidget);
      expect(
        find.descendant(
          of: viewport,
          matching: find.byType(SliverList, skipOffstage: false),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: viewport,
          matching: find.byType(ListView, skipOffstage: false),
          skipOffstage: false,
        ),
        findsNothing,
        reason: 'the result list must not be an eager nested ListView',
      );
      expect(
        find.byKey(const ValueKey('friend-options-friend-199')),
        findsNothing,
        reason: 'an offscreen tail row must remain unbuilt',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
