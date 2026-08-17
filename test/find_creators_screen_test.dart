import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/creator/data/models/creator_search_result.dart';
import 'package:yovoice/features/creator/data/services/creator_directory_service.dart';
import 'package:yovoice/features/creator/presentation/screens/find_creators_screen.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;

  setUp(() {
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
        uid: 'viewer',
        email: 'viewer@yovoice.app',
        isEmailVerified: true,
      ),
    );
  });

  void useSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Map<String, dynamic> result({
    required String uid,
    required String name,
    required String accountType,
  }) => {
    'uid': uid,
    'displayName': name,
    'username': name.toLowerCase().replaceAll(' ', '.'),
    'photoUrl': null,
    'bio': 'Conversations about sound, culture and creative work.',
    'statusMessage': '',
    'accountType': accountType,
    'premiumIdentity': accountType == 'creator',
    'followerCount': accountType == 'creator' ? 42 : 9,
    // A poisoned response must never become part of the directory model.
    'email': '$uid@private.invalid',
    'role': 'superAdmin',
    'isOnline': true,
  };

  FollowService followService({FollowMutationInvoker? mutationInvoker}) =>
      FollowService(
        firestore: db,
        auth: auth,
        mutationInvoker: mutationInvoker ?? (_) async => const {},
      );

  Widget host({
    required CreatorDirectoryService directory,
    FollowService? follows,
    ValueChanged<CreatorSearchResult>? onOpen,
    TextScaler textScaler = TextScaler.noScaling,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: FindCreatorsScreen(
        isRootTab: true,
        directoryService: directory,
        followService: follows ?? followService(),
        onOpenCreator: onOpen,
      ),
    ),
  );

  test(
    'dedicated model accepts only creator identities and ignores private fields',
    () {
      final creator = CreatorSearchResult.fromMap(
        result(uid: 'c1', name: 'Maya Voice', accountType: 'creator'),
      );
      expect(creator.uid, 'c1');
      expect(creator.accountType, CreatorDirectoryAccountType.creator);
      expect(creator.followerCount, 42);
      expect(
        () => CreatorSearchResult.fromMap(
          result(uid: 'p1', name: 'Personal User', accountType: 'personal'),
        ),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'search and filters stay server-scoped to creator account types',
    (tester) async {
      useSize(tester, const Size(1440, 900));
      final payloads = <Map<String, dynamic>>[];
      final directory = CreatorDirectoryService(
        searchInvoker: (payload) async {
          payloads.add(Map<String, dynamic>.from(payload));
          final types = (payload['accountTypes'] as List).cast<String>();
          return {
            'profiles': [
              if (types.contains('creator'))
                result(uid: 'c1', name: 'Maya Voice', accountType: 'creator'),
              if (types.contains('official'))
                result(
                  uid: 'o1',
                  name: 'YO Editorial',
                  accountType: 'official',
                ),
              result(uid: 'p1', name: 'Private User', accountType: 'personal'),
            ],
          };
        },
      );

      await tester.pumpWidget(host(directory: directory));
      await tester.enterText(
        find.byKey(const ValueKey('find-creators-search')),
        'voice',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      expect(payloads.single['accountTypes'], ['creator', 'official']);
      expect(find.text('Maya Voice'), findsOneWidget);
      expect(find.text('YO Editorial'), findsOneWidget);
      expect(find.text('Private User'), findsNothing);
      expect(find.textContaining('private.invalid'), findsNothing);
      expect(find.textContaining('Online'), findsNothing);

      await tester.tap(find.text('Official').first);
      await tester.pump();
      await tester.pump();
      expect(payloads.last['accountTypes'], ['official']);
      expect(find.text('YO Editorial'), findsOneWidget);
      expect(find.text('Maya Voice'), findsNothing);
    },
  );

  testWidgets(
    'desktop is a bounded two-column directory and mobile is one column',
    (tester) async {
      final directory = CreatorDirectoryService(
        searchInvoker: (_) async => {
          'profiles': [
            result(uid: 'c1', name: 'Maya Voice', accountType: 'creator'),
            result(uid: 'o1', name: 'YO Editorial', accountType: 'official'),
          ],
        },
      );

      useSize(tester, const Size(1440, 900));
      await tester.pumpWidget(host(directory: directory));
      await tester.enterText(
        find.byKey(const ValueKey('find-creators-search')),
        'voice',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      final desktopFirst = tester.getRect(
        find.byKey(const ValueKey('creator-c1')),
      );
      final desktopSecond = tester.getRect(
        find.byKey(const ValueKey('creator-o1')),
      );
      expect(desktopFirst.width, lessThan(440));
      expect(desktopSecond.left, greaterThan(desktopFirst.right));
      expect(desktopSecond.right - desktopFirst.left, lessThanOrEqualTo(880));
      expect(tester.takeException(), isNull);

      useSize(tester, const Size(390, 844));
      await tester.pumpWidget(host(directory: directory));
      await tester.enterText(
        find.byKey(const ValueKey('find-creators-search')),
        'voice',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      final mobileFirst = tester.getRect(
        find.byKey(const ValueKey('creator-c1')),
      );
      final mobileSecond = tester.getRect(
        find.byKey(const ValueKey('creator-o1')),
      );
      expect((mobileFirst.left - mobileSecond.left).abs(), lessThan(1));
      expect(mobileSecond.top, greaterThan(mobileFirst.bottom));
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in const [
    Size(320, 568),
    Size(390, 844),
    Size(768, 900),
    Size(1100, 800),
    Size(1440, 900),
  ]) {
    testWidgets('large text has no overflow at ${size.width.toInt()}px', (
      tester,
    ) async {
      useSize(tester, size);
      final directory = CreatorDirectoryService(
        searchInvoker: (_) async => {
          'profiles': [
            result(
              uid: 'c1',
              name: 'A Creator With A Long Display Name',
              accountType: 'creator',
            ),
          ],
        },
      );
      await tester.pumpWidget(
        host(directory: directory, textScaler: const TextScaler.linear(2)),
      );
      await tester.enterText(
        find.byKey(const ValueKey('find-creators-search')),
        'creator',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('A Creator With A Long Display Name'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('A Creator With A Long Display Name'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('double tapping Follow sends one server mutation', (
    tester,
  ) async {
    useSize(tester, const Size(390, 844));
    final pending = Completer<Map<String, dynamic>>();
    var calls = 0;
    final follows = followService(
      mutationInvoker: (payload) {
        calls += 1;
        return pending.future;
      },
    );
    final directory = CreatorDirectoryService(
      searchInvoker: (_) async => {
        'profiles': [
          result(uid: 'c1', name: 'Maya Voice', accountType: 'creator'),
        ],
      },
    );
    await tester.pumpWidget(host(directory: directory, follows: follows));
    await tester.enterText(
      find.byKey(const ValueKey('find-creators-search')),
      'maya',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    await tester.tap(find.text('Follow'));
    await tester.tap(find.text('Follow'));
    await tester.pump();
    expect(calls, 1);
    pending.complete(const {});
    await tester.pump();
  });
}
