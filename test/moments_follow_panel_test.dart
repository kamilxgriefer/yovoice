import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_follow_panel.dart';
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';

import 'moments_overview_test_support.dart';

/// The calm context panel of board 06: the friends-minus-following pool,
/// hidden when empty, the honest heading, a real Follow with a
/// double-submit guard, never for the viewer, and the ADR-110 alternative.
void main() {
  late VoidCallback restoreIdentity;

  setUp(() => restoreIdentity = installIdentityStub());
  tearDown(() => restoreIdentity());

  FollowUser followed(String uid) => FollowUser(
    uid: uid,
    displayName: uid,
    username: '',
    photoUrl: null,
    followedAt: DateTime.now(),
  );

  Future<({FollowService follows, List<Map<String, dynamic>> calls, Completer<void> gate, List<bool> pool})>
  pumpPanel(
    WidgetTester tester, {
    required List<FriendUser> friends,
    List<FollowUser> following = const [],
    bool inlineFollow = true,
    Locale locale = const Locale('en'),
    int recordTaps = 0,
  }) async {
    useSurface(tester, const Size(400, 900));
    final auth = authAs();
    final firestore = fakeFirestore();
    final calls = <Map<String, dynamic>>[];
    final gate = Completer<void>();
    final follows = FollowService(
      firestore: firestore,
      auth: auth,
      mutationInvoker: (data) async {
        calls.add(data);
        await gate.future;
        final target = data['targetUserId'] as String;
        final edge = firestore
            .collection('users')
            .doc(viewerUid)
            .collection('following')
            .doc(target);
        if (data['following'] == true) {
          await edge.set(<String, dynamic>{'uid': target});
        } else {
          await edge.delete();
        }
        return <String, dynamic>{};
      },
    );
    final pool = <bool>[];
    await tester.pumpWidget(
      overviewHost(
        Scaffold(
          body: SizedBox(
            width: 320,
            child: MomentsFollowPanel(
              onRecord: () {},
              onPoolChanged: pool.add,
              auth: auth,
              followService: follows,
              friendsStream: Stream.value(friends),
              followingStream: Stream.value(following),
              inlineFollow: inlineFollow,
            ),
          ),
        ),
        locale: locale,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    return (follows: follows, calls: calls, gate: gate, pool: pool);
  }

  testWidgets('pool = friends minus following minus the viewer, under the '
      'honest heading', (tester) async {
    final harness = await pumpPanel(
      tester,
      friends: [
        friend('ola', name: 'Ola', username: 'ola.codziennie'),
        friend('bartek', name: 'Bartek'),
        friend(viewerUid, name: 'Me'),
        friend('zuzia', name: 'Zuzia'),
      ],
      following: [followed('bartek')],
    );
    expect(find.byKey(const ValueKey('moments-follow-panel')), findsOneWidget);
    expect(find.text('Friends you do not follow yet'), findsOneWidget);
    expect(find.textContaining('ecommend'), findsNothing);
    expect(find.byKey(const ValueKey('moments-follow-row-ola')), findsOneWidget);
    expect(find.byKey(const ValueKey('moments-follow-row-zuzia')), findsOneWidget);
    expect(find.byKey(const ValueKey('moments-follow-row-bartek')), findsNothing);
    expect(find.byKey(const ValueKey('moments-follow-row-$viewerUid')), findsNothing);
    expect(find.text('@ola.codziennie'), findsOneWidget);
    expect(harness.pool, [true]);
    expect(find.byKey(const ValueKey('moments-follow-panel-record')), findsOneWidget);
    expect(find.text('Add your moment'), findsOneWidget);
    expect(find.text('Record a Voice Moment'), findsOneWidget);
  });

  testWidgets('Polish heading and CTA copy', (tester) async {
    await pumpPanel(
      tester,
      friends: [friend('ola', name: 'Ola')],
      locale: const Locale('pl'),
    );
    expect(find.text('Znajomi, których jeszcze nie obserwujesz'), findsOneWidget);
    expect(find.text('Obserwuj'), findsOneWidget);
    expect(find.text('Dodaj swoją chwilę'), findsOneWidget);
    expect(find.text('Nagraj Voice Moment'), findsOneWidget);
  });

  testWidgets('hidden — not skeletonised — when the pool is empty, and the '
      'host is told', (tester) async {
    final harness = await pumpPanel(
      tester,
      friends: [friend('bartek'), friend(viewerUid)],
      following: [followed('bartek')],
    );
    expect(find.byKey(const ValueKey('moments-follow-panel')), findsNothing);
    expect(find.byKey(const ValueKey('moments-follow-panel-record')), findsNothing);
    expect(find.byKey(const ValueKey('moments-follow-panel-empty')), findsOneWidget);
    expect(harness.pool, [false]);
  });

  testWidgets('Obserwuj calls follow exactly once per tap, then reads back '
      'as following and unfollows on the next tap', (tester) async {
    final harness = await pumpPanel(tester, friends: [friend('ola', name: 'Ola')]);
    final button = find.byKey(const ValueKey('moments-follow-ola'));
    expect(button, findsOneWidget);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    expect(find.text('Follow'), findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    await tester.tap(button, warnIfMissed: false);
    await tester.pump();
    expect(harness.calls, hasLength(1), reason: 'double-submit guard');
    expect(harness.calls.single, {'targetUserId': 'ola', 'following': true});

    harness.gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Following'), findsOneWidget);

    final semantics = tester.ensureSemantics();
    try {
      final data = tester.getSemantics(button).getSemanticsData();
      expect(data.label, contains('Unfollow Ola'));
    } finally {
      semantics.dispose();
    }

    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(harness.calls, hasLength(2));
    expect(harness.calls.last, {'targetUserId': 'ola', 'following': false});
    expect(tester.takeException(), isNull);
  });

  testWidgets('the ADR-110 alternative draws no Follow control; the tile '
      'is one named profile button', (tester) async {
    await pumpPanel(
      tester,
      friends: [friend('ola', name: 'Ola')],
      inlineFollow: false,
    );
    expect(find.byKey(const ValueKey('moments-follow-ola')), findsNothing);
    expect(find.text('Follow'), findsNothing);
    final semantics = tester.ensureSemantics();
    try {
      expect(find.bySemanticsLabel('Open profile of Ola'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('a friends stream error hides the panel rather than guessing',
      (tester) async {
    useSurface(tester, const Size(400, 900));
    final auth = authAs();
    final firestore = fakeFirestore();
    final pool = <bool>[];
    await tester.pumpWidget(
      overviewHost(
        Scaffold(
          body: MomentsFollowPanel(
            onRecord: () {},
            onPoolChanged: pool.add,
            auth: auth,
            followService: FollowService(firestore: firestore, auth: auth),
            friendsStream: Stream<List<FriendUser>>.error(StateError('down')),
            followingStream: Stream.value(const <FollowUser>[]),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byKey(const ValueKey('moments-follow-panel')), findsNothing);
    expect(pool, [false]);
    expect(tester.takeException(), isNull);
  });
}
