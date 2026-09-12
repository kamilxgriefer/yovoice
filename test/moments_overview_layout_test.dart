import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';
import 'package:yovoice/features/moments/presentation/widgets/yo_moments_chrome.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';

import 'moments_overview_test_support.dart';

/// The 06 column plan measured on the SLOT the feed receives
/// (moments-contract-visual.md §2.1, brief C33/C34/C36): 16/24 gutters, a
/// 640 measure, the local panel from 1100, the calm panel from 1200 — and
/// only while its pool has someone in it.
void main() {
  late VoidCallback restoreIdentity;

  setUp(() => restoreIdentity = installIdentityStub());
  tearDown(() => restoreIdentity());

  Future<void> pumpFeed(
    WidgetTester tester, {
    required double slot,
    double height = 900,
    double textScale = 1,
    bool withPool = true,
  }) async {
    final size = Size(slot, height);
    useSurface(tester, size);
    final auth = authAs();
    final firestore = fakeFirestore();
    await tester.pumpWidget(
      overviewHost(
        Scaffold(
          body: MomentsFeedView(
            auth: auth,
            onRecord: () {},
            onCreate: () {},
            discoveryService: StaticDiscovery(populatedPool()),
            feedService: QuietFeed(firestore: firestore, auth: auth),
            viewsService: StaticViews(const <String>{}),
            friendService: StaticFriends(
              firestore: firestore,
              auth: auth,
              friends: withPool ? [friend('ola'), friend('bartek')] : null,
            ),
            followService: FollowService(firestore: firestore, auth: auth),
            playerFactory: SilentPlayer.new,
          ),
        ),
        textScale: textScale,
        size: size,
      ),
    );
    await settleOverview(tester);
  }

  double gutterFor(double slot) => slot < 600 ? 16 : 24;

  testWidgets('599 / 600 / 1099: one column, 16 then 24 gutters, 640 measure',
      (tester) async {
    for (final slot in <double>[599, 600, 1099]) {
      await pumpFeed(tester, slot: slot);
      final list = tester.getRect(
        find.byKey(const ValueKey('moments-feed-scroll')),
      );
      final gutter = gutterFor(slot);
      final expectedList = math.min(slot, 640 + 2 * gutter);
      expect(list.width, expectedList, reason: 'slot $slot');
      expect(list.left, (slot - expectedList) / 2, reason: 'slot $slot');
      final card = tester.getRect(find.byKey(const ValueKey('moment-row-m4')));
      expect(card.left, list.left + gutter, reason: 'slot $slot');
      expect(card.width, expectedList - 2 * gutter, reason: 'slot $slot');
      expect(card.width, lessThanOrEqualTo(640));
      expect(
        find.byKey(const ValueKey<String>('yo-moments-local-panel')),
        findsNothing,
        reason: 'slot $slot',
      );
      expect(find.byKey(const ValueKey('moments-follow-panel')), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('1100 / 1199: wide-2 — local panel 240, no calm panel even '
      'with a pool', (tester) async {
    for (final slot in <double>[1100, 1199]) {
      await pumpFeed(tester, slot: slot);
      final panel = find.byKey(const ValueKey<String>('yo-moments-local-panel'));
      expect(panel, findsOneWidget, reason: 'slot $slot');
      final panelRect = tester.getRect(panel);
      expect(panelRect.left, 0);
      expect(panelRect.width, 240);
      expect(find.byKey(const ValueKey('moments-follow-panel')), findsNothing);
      final list = tester.getRect(
        find.byKey(const ValueKey('moments-feed-scroll')),
      );
      final mainSlot = slot - 240 - 24;
      final expectedList = math.min(mainSlot, 640 + 48);
      expect(list.width, expectedList, reason: 'slot $slot');
      expect(list.left, 264 + (mainSlot - expectedList) / 2, reason: '$slot');
      final card = tester.getRect(find.byKey(const ValueKey('moment-row-m4')));
      expect(card.width, expectedList - 48);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('1200 / 1656: wide-3 — the calm panel takes 320 beside the '
      'column, and only while the pool is non-empty', (tester) async {
    for (final slot in <double>[1200, 1656]) {
      await pumpFeed(tester, slot: slot);
      final calm = find.byKey(const ValueKey('moments-follow-panel'));
      expect(calm, findsOneWidget, reason: 'slot $slot');
      final calmRect = tester.getRect(calm);
      expect(calmRect.width, 320);
      expect(calmRect.right, slot - 24, reason: 'trailing gutter 24');
      final list = tester.getRect(
        find.byKey(const ValueKey('moments-feed-scroll')),
      );
      final mainSlot = slot - 240 - 24 - 24 - 320 - 24;
      final expectedList = math.min(mainSlot, 640 + 48);
      expect(list.width, expectedList, reason: 'slot $slot');
      final card = tester.getRect(find.byKey(const ValueKey('moment-row-m4')));
      expect(card.width, greaterThanOrEqualTo(480));
      expect(card.width, lessThanOrEqualTo(640));
      expect(tester.takeException(), isNull);

      await pumpFeed(tester, slot: slot, withPool: false);
      expect(find.byKey(const ValueKey('moments-follow-panel')), findsNothing);
      final wideList = tester.getRect(
        find.byKey(const ValueKey('moments-feed-scroll')),
      );
      final wideMain = slot - 240 - 24;
      final wideExpected = math.min(wideMain, 640 + 48);
      expect(wideList.width, wideExpected, reason: 'no empty third column');
      expect(wideList.left, 264 + (wideMain - wideExpected) / 2);
    }
  });

  testWidgets('200 % text doubles the local panel and moves wide-3 to 1440',
      (tester) async {
    await pumpFeed(tester, slot: 1400, textScale: 2);
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('yo-moments-local-panel'))).width,
      480,
    );
    expect(find.byKey(const ValueKey('moments-follow-panel')), findsNothing);

    await pumpFeed(tester, slot: 1440, textScale: 2);
    expect(find.byKey(const ValueKey('moments-follow-panel')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('the layout resolver is slot-based and text-scale aware', () {
    expect(YoMomentsLayout.of(599).tier, YoMomentsLayoutTier.narrow);
    expect(YoMomentsLayout.of(599).gutter, 16);
    expect(YoMomentsLayout.of(600).tier, YoMomentsLayoutTier.medium);
    expect(YoMomentsLayout.of(600).gutter, 24);
    expect(YoMomentsLayout.of(1099).tier, YoMomentsLayoutTier.medium);
    expect(YoMomentsLayout.of(1100).tier, YoMomentsLayoutTier.wide2);
    expect(YoMomentsLayout.of(1199).tier, YoMomentsLayoutTier.wide2);
    expect(YoMomentsLayout.of(1200).tier, YoMomentsLayoutTier.wide3);
    expect(YoMomentsLayout.of(1440).tier, YoMomentsLayoutTier.wide3);
    expect(YoMomentsLayout.of(1439, textScale: 2).tier, YoMomentsLayoutTier.wide2);
    expect(YoMomentsLayout.of(1440, textScale: 2).tier, YoMomentsLayoutTier.wide3);
    expect(YoMomentsLayout.of(1440, textScale: 2).localPanelWidth, 480);
    expect(YoMomentsLayout.of(1440).mainColumnOuterWidth, 688);
  });
}
