import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_request.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/presentation/screens/friend_profile_screen.dart';
import 'package:yovoice/features/friends/presentation/screens/friends_screen.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';

void main() {
  const me = 'receiver';
  const sender = 'sender';

  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  late List<({String name, Map<String, dynamic> data})> calls;

  Future<void> seedRequest({String name = 'Ola'}) {
    return db
        .collection('users')
        .doc(me)
        .collection('friendRequests')
        .doc(sender)
        .set({
          'senderId': sender,
          'senderName': name,
          'senderPhotoUrl': null,
          'createdAt': DateTime.now(),
        });
  }

  setUp(() async {
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: me, email: 'receiver@yovoice.app'),
    );
    calls = [];
    await db.collection('users').doc(me).set({
      'uid': me,
      'displayName': 'Receiver',
    });
  });

  tearDown(FriendService.clearSharedReadCaches);

  Widget app({
    TextScaler textScaler = TextScaler.noScaling,
    ThemeData? theme,
    bool showRequestsInitially = true,
    MessageService? messageService,
    ProfileMediaService? profileMediaService,
  }) {
    final friends = FriendService(
      firestore: db,
      auth: auth,
      mutationInvoker: (name, data) async {
        calls.add((name: name, data: data));
        if (name == 'respondToFriendRequest') {
          await db
              .collection('users')
              .doc(me)
              .collection('friendRequests')
              .doc(data['senderId'] as String)
              .delete();
        }
        return const {'changed': true};
      },
    );
    return MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: FriendsScreen(
        showRequestsInitially: showRequestsInitially,
        friendService: friends,
        messageService:
            messageService ?? MessageService(firestore: db, auth: auth),
        profileMediaService: profileMediaService,
        firestore: db,
        auth: auth,
      ),
    );
  }

  testWidgets('deep-linked Requests exposes Accept and clears the request', (
    tester,
  ) async {
    await seedRequest();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Ola'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    expect(find.text('Requests 1'), findsOneWidget);
    final requestShortcut = find.bySemanticsLabel('Friend requests, 1 pending');
    expect(requestShortcut, findsOneWidget);
    expect(tester.getSize(requestShortcut).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(requestShortcut).height, greaterThanOrEqualTo(44));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('friend-request-accept')))
          .height,
      greaterThanOrEqualTo(48),
    );

    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    expect(calls.single.name, 'respondToFriendRequest');
    expect(calls.single.data, {'senderId': sender, 'accept': true});
    expect(find.text('No pending requests'), findsOneWidget);
  });

  testWidgets('Decline is explicit, single-fire, and removes the request', (
    tester,
  ) async {
    await seedRequest(name: 'Marek');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    expect(calls.single.data, {'senderId': sender, 'accept': false});
    expect(find.text('No pending requests'), findsOneWidget);
  });

  testWidgets('opening Requests late replays the existing request snapshot', (
    tester,
  ) async {
    await seedRequest();
    await tester.pumpWidget(app(showRequestsInitially: false));
    await tester.pumpAndSettle();

    expect(find.text('Ola'), findsNothing);
    await tester.tap(find.text('Requests 1'));
    await tester.pumpAndSettle();

    expect(find.text('Ola'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
  });

  testWidgets('request actions reflow at 320px and 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await seedRequest(name: 'A deliberately long friend name');

    await tester.pumpWidget(
      app(textScaler: const TextScaler.linear(2), theme: AppTheme.lightTheme),
    );
    await tester.pumpAndSettle();

    final accept = find.byKey(const ValueKey('friend-request-accept'));
    final decline = find.byKey(const ValueKey('friend-request-decline'));
    expect(
      tester.getTopLeft(accept).dy,
      lessThan(tester.getTopLeft(decline).dy),
    );
    expect(tester.getSize(accept).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(decline).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('friend request chrome uses semantic Pearl and dark palettes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(768, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await seedRequest();

    for (final themeCase in <({ThemeData theme, AppPalette palette})>[
      (theme: AppTheme.lightTheme, palette: AppPalette.light),
      (theme: AppTheme.darkTheme, palette: AppPalette.dark),
    ]) {
      await tester.pumpWidget(app(theme: themeCase.theme));
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(
        find.byKey(const ValueKey('friends-screen')),
      );
      expect(scaffold.backgroundColor, themeCase.palette.background);

      final requestCard = tester.widget<Container>(
        find.byKey(const ValueKey('friend-request-card-sender')),
      );
      final decoration = requestCard.decoration! as BoxDecoration;
      expect(decoration.color, themeCase.palette.surface);
      expect(
        (decoration.border! as Border).top.color,
        themeCase.palette.border,
      );

      final name = tester.widget<Text>(find.text('Ola'));
      expect(name.style!.color, themeCase.palette.textPrimary);
      final subtitle = tester.widget<Text>(
        find.text('Wants to be your friend'),
      );
      expect(subtitle.style!.color, themeCase.palette.textSecondary);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('rapid add-friend taps push only one route', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final addFriend = find.bySemanticsLabel('Add friend');
    expect(addFriend, findsOneWidget);
    await tester.tap(addFriend);
    await tester.tap(addFriend, warnIfMissed: false);
    await tester.tap(addFriend, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('add-friend-screen')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('friends-screen')),
      findsOneWidget,
      reason: 'one back action must return to the originating Friends screen',
    );
    expect(find.byKey(const ValueKey('add-friend-screen')), findsNothing);
  });

  testWidgets('friends reload after a Requests tab round trip', (tester) async {
    await db
        .collection('users')
        .doc(me)
        .collection('friends')
        .doc('friend')
        .set({'displayName': 'Ada'});
    await db.collection('publicProfiles').doc('friend').set({
      'uid': 'friend',
      'displayName': 'Ada',
    });
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('Ada'), findsOneWidget);

    await tester.tap(find.text('Requests'));
    await tester.pumpAndSettle();
    expect(find.text('Ada'), findsNothing);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(
      find.text('Ada'),
      findsOneWidget,
      reason: 'the retired friends fanout must be reacquired on remount',
    );
  });

  testWidgets('friend routes retain the injected Firebase context', (
    tester,
  ) async {
    await db
        .collection('users')
        .doc(me)
        .collection('friends')
        .doc('friend')
        .set({'displayName': 'Ada'});
    await db.collection('publicProfiles').doc('friend').set({
      'uid': 'friend',
      'displayName': 'Ada',
    });
    final messages = MessageService(firestore: db, auth: auth);
    final profileMedia = ProfileMediaService(
      auth: auth,
      invoker: (_, __) async => const <Object?, Object?>{},
    );
    addTearDown(messages.dispose);
    await tester.pumpWidget(
      app(
        showRequestsInitially: false,
        messageService: messages,
        profileMediaService: profileMedia,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ada'));
    await tester.pumpAndSettle();
    final profile = tester.widget<FriendProfileScreen>(
      find.byType(FriendProfileScreen),
    );
    expect(identical(profile.messageService, messages), isTrue);
    expect(identical(profile.profileMediaService, profileMedia), isTrue);
    expect(identical(profile.firestore, db), isTrue);
    expect(identical(profile.auth, auth), isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Message'));
    await tester.pumpAndSettle();
    final chat = tester.widget<ChatScreen>(find.byType(ChatScreen));
    expect(identical(chat.messageService, messages), isTrue);
    expect(identical(chat.profileMediaService, profileMedia), isTrue);
    expect(identical(chat.firestore, db), isTrue);
    expect(identical(chat.auth, auth), isTrue);
  });

  testWidgets('friend row offers Remove friend from its options', (
    tester,
  ) async {
    await db.collection('users').doc(me).collection('friends').doc('ada').set({
      'displayName': 'Ada',
    });
    await db.collection('publicProfiles').doc('ada').set({
      'uid': 'ada',
      'displayName': 'Ada',
    });
    await tester.pumpWidget(app(showRequestsInitially: false));
    await tester.pumpAndSettle();

    // Message stays exactly where it was; the new options button sits next
    // to it and the row's long-press opens the same sheet.
    expect(find.byTooltip('Message'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('friend-options-ada')));
    await tester.pumpAndSettle();
    expect(find.text('Remove friend'), findsOneWidget);
    expect(find.text('View profile'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('friend-remove-action')));
    await tester.pumpAndSettle();
    expect(find.text('Remove friend?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.name == 'removeFriend'), isEmpty);

    await tester.longPress(find.text('Ada'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('friend-remove-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('friend-remove-confirm')));
    await tester.pumpAndSettle();
    final remove = calls.singleWhere((call) => call.name == 'removeFriend');
    expect(remove.data['targetUserId'], 'ada');
    expect(find.text('Ada was removed from your friends.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'default friend route derives its message service from injected Firebase',
    (tester) async {
      await db
          .collection('users')
          .doc(me)
          .collection('friends')
          .doc('friend')
          .set({'displayName': 'Ada'});
      await db.collection('publicProfiles').doc('friend').set({
        'uid': 'friend',
        'displayName': 'Ada',
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: FriendsScreen(
            firestore: db,
            auth: auth,
            showRequestsInitially: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ada'));
      await tester.pumpAndSettle();

      final profile = tester.widget<FriendProfileScreen>(
        find.byType(FriendProfileScreen),
      );
      expect(profile.messageService, isNotNull);
      expect(identical(profile.firestore, db), isTrue);
      expect(identical(profile.auth, auth), isTrue);
    },
  );

  testWidgets('requests recover after a terminal fanout error', (tester) async {
    final source = StreamController<List<FriendRequest>>.broadcast();
    addTearDown(source.close);
    var sourceSubscriptions = 0;
    final friends = FriendService(
      firestore: db,
      auth: auth,
      friendRequestsWatch: (_) {
        sourceSubscriptions += 1;
        return source.stream;
      },
    );
    final messages = MessageService(firestore: db, auth: auth);
    addTearDown(messages.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: FriendsScreen(
          showRequestsInitially: true,
          friendService: friends,
          messageService: messages,
          firestore: db,
          auth: auth,
        ),
      ),
    );
    await tester.pump();
    source.add(const <FriendRequest>[]);
    await tester.pumpAndSettle();
    expect(sourceSubscriptions, 1);

    source.addError(StateError('request listener stopped'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load requests'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(sourceSubscriptions, 2);
    await tester.tap(find.text('Requests'));
    await tester.pump();

    source.add(const [
      FriendRequest(
        senderId: 'recovered-sender',
        senderName: 'Recovered request',
        senderEmail: '',
        senderPhotoUrl: null,
        createdAt: null,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Recovered request'), findsOneWidget);
  });

  testWidgets('search rebuilds keep one pending-request source listener', (
    tester,
  ) async {
    final source = StreamController<List<FriendRequest>>.broadcast();
    addTearDown(source.close);
    var sourceSubscriptions = 0;
    final friends = FriendService(
      firestore: db,
      auth: auth,
      friendRequestsWatch: (_) {
        sourceSubscriptions += 1;
        return source.stream;
      },
    );
    final messages = MessageService(firestore: db, auth: auth);
    addTearDown(messages.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: FriendsScreen(
          friendService: friends,
          messageService: messages,
          firestore: db,
          auth: auth,
        ),
      ),
    );
    await tester.pump();
    source.add(const <FriendRequest>[]);
    await tester.pumpAndSettle();
    expect(sourceSubscriptions, 1);

    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'ada');
    await tester.pump();
    await tester.tap(find.text('Online'));
    await tester.pumpAndSettle();

    expect(
      sourceSubscriptions,
      1,
      reason: 'search/filter rebuilds must not churn the Firestore fanout',
    );
  });
}
