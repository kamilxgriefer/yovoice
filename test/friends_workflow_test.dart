import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/presentation/screens/friends_screen.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';

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

  Widget app({TextScaler textScaler = TextScaler.noScaling}) {
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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: FriendsScreen(
        showRequestsInitially: true,
        friendService: friends,
        messageService: MessageService(firestore: db, auth: auth),
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

  testWidgets('request actions reflow at 320px and 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await seedRequest(name: 'A deliberately long friend name');

    await tester.pumpWidget(app(textScaler: const TextScaler.linear(2)));
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
}
