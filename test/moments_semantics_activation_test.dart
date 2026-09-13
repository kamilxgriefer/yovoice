// Boards 06 / 07 / 08 — a button the accessibility bridge can actually press.
//
// A `flutter_test` pointer tap does not go through the accessibility bridge,
// which is why nine passing cases on the transport, seven on the mini-player
// and nine on the hand-off list all missed the same defect: four controls
// announced themselves as buttons, carried correct bilingual names, and
// declared NO `SemanticsAction.tap`. TalkBack does not mark such a node
// clickable, Switch Access skips it when scanning, and iOS
// `accessibilityActivate` returns NO.
//
// Everything below operates the control the way the PLATFORM does —
// `SemanticsOwner.performAction(id, SemanticsAction.tap)`, exactly what
// Android's AccessibilityBridge dispatches for ACTION_CLICK — and then asks
// the app whether anything happened. The last group is the class-wide guard:
// every enabled button node on these surfaces has to carry the action, so the
// idiom cannot come back somewhere new.

import 'dart:ui' show Tristate;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';
import 'package:yovoice/features/moments/presentation/widgets/reply_playback_arbiter.dart';
import 'package:yovoice/features/moments/presentation/widgets/voice_reply_mini_player.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';

import 'moment_listen_test_support.dart';
import 'moments_overview_test_support.dart';
import 'reel_stage_test_support.dart';
import 'voice_moment_test_doubles.dart';

/// Activates [finder]'s node the way the platform bridge does.
Future<void> activateBySemantics(WidgetTester tester, Finder finder) async {
  final node = tester.getSemantics(finder);
  expect(
    node.getSemanticsData().hasAction(SemanticsAction.tap),
    isTrue,
    reason:
        'the node announces itself as a button ("${node.label}") but declares '
        'no tap action, so no screen reader or switch can operate it',
  );
  node.owner!.performAction(node.id, SemanticsAction.tap);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));
}

/// Every node in the rendered tree, in traversal order.
///
/// `tester.getSemantics` walks UP from a widget's render object, so a node
/// produced by a `Semantics` INSIDE a keyed widget is not reachable through
/// that key. These cases look nodes up by what they announce, which is what
/// a screen reader does too.
List<SemanticsNode> _allNodes(WidgetTester tester) {
  final found = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    found.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  SemanticsNode? root;
  void visitOwner(PipelineOwner owner) {
    root ??= owner.semanticsOwner?.rootSemanticsNode;
    owner.visitChildren(visitOwner);
  }

  visitOwner(tester.binding.rootPipelineOwner);
  expect(root, isNotNull, reason: 'semantics were not enabled');
  visit(root!);
  return found;
}

/// Every node in the rendered tree that claims to be an enabled button.
List<SemanticsNode> _enabledButtons(WidgetTester tester) {
  return _allNodes(tester).where((node) {
    final flags = node.getSemanticsData().flagsCollection;
    // `isEnabled` is a tristate: `none` means the node never declared an
    // enabled state at all, which is not the same as being disabled.
    return flags.isButton && flags.isEnabled != Tristate.isFalse;
  }).toList();
}

/// The first node that announces [what], found the way a reader finds it.
SemanticsNode _nodeWhere(
  WidgetTester tester,
  bool Function(SemanticsData data) test,
  String what,
) {
  final matches = _allNodes(
    tester,
  ).where((node) => test(node.getSemanticsData())).toList();
  expect(matches, isNotEmpty, reason: 'no semantics node $what');
  return matches.first;
}

/// Activates [node] the way Android's AccessibilityBridge does for
/// ACTION_CLICK, after proving the platform would offer the action at all.
Future<void> _activateNode(WidgetTester tester, SemanticsNode node) async {
  final data = node.getSemanticsData();
  expect(
    data.hasAction(SemanticsAction.tap),
    isTrue,
    reason:
        'the node announces itself as a button ("${data.label}") but declares '
        'no tap action, so no screen reader or switch can operate it',
  );
  node.owner!.performAction(node.id, SemanticsAction.tap);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));
}

void _expectEveryEnabledButtonIsOperable(WidgetTester tester, String where) {
  final dead = <String>[];
  for (final node in _enabledButtons(tester)) {
    final data = node.getSemanticsData();
    if (data.hasAction(SemanticsAction.tap)) continue;
    if (data.hasAction(SemanticsAction.increase) ||
        data.hasAction(SemanticsAction.decrease)) {
      continue; // A value control is operated by its own actions.
    }
    dead.add('"${data.label}" (${node.rect.width}x${node.rect.height})');
  }
  expect(
    dead,
    isEmpty,
    reason:
        'on $where these nodes announce an enabled button and carry no tap '
        'action, so assistive technology cannot press them: ${dead.join(', ')}',
  );
}

void main() {
  group('board 07 — the control the screen exists for', () {
    testWidgets('the play/pause disc really starts playback from the bridge', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      final harness = await pumpListenDetail(
        tester,
        moment: listenMoment('m-a11y-play'),
      );
      expect(harness.players, isEmpty, reason: 'opening starts nothing');

      await activateBySemantics(
        tester,
        find.byKey(const ValueKey<String>('moment-detail-play')),
      );

      expect(
        harness.players,
        hasLength(1),
        reason: 'the bridge, not a finger, allocated the transport',
      );
      expect(harness.player.playCalls, 1);
      final after = tester
          .getSemantics(
            find.byKey(const ValueKey<String>('moment-detail-play')),
          )
          .getSemanticsData();
      expect(
        after.flagsCollection.isToggled,
        Tristate.isTrue,
        reason: 'and the control now says it is playing',
      );
      handle.dispose();
    });

    testWidgets('every enabled button on the expanded player is operable', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      for (final size in <Size>[const Size(390, 844), const Size(1440, 900)]) {
        await pumpListenDetail(
          tester,
          moment: listenMoment('m-a11y-${size.width.toInt()}', comments: 1),
          size: size,
          seed: (db) => seedListenComment(
            db,
            momentId: 'm-a11y-${size.width.toInt()}',
            id: 'c1',
          ),
        );
        _expectEveryEnabledButtonIsOperable(
          tester,
          'the expanded player at ${size.width.toInt()}',
        );
      }
      handle.dispose();
    });
  });

  group('board 07 — the hand-off list', () {
    testWidgets('a "KOLEJNE MOMENTY" row opens its Moment from the bridge', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      final next = listenMoment(
        'm-a11y-next',
        author: 'bartek',
        authorName: 'Bartek',
        caption: 'The neighbour',
      );
      await pumpListenDetail(
        tester,
        moment: listenMoment('m-a11y-current', caption: 'The current one'),
        neighbours: <VoiceMoment>[next],
        // The neighbour is a real document: the hand-off re-reads the view.
        seed: (FakeFirebaseFirestore db) => db
            .collection('voiceMoments')
            .doc(next.id)
            .set(listenMomentDoc(next)),
        // The hand-off list is a wide-3 column.
        size: const Size(1440, 900),
      );

      final row = find.byKey(
        const ValueKey<String>('moments-queue-item-m-a11y-next'),
      );
      expect(row, findsOneWidget);
      await tester.ensureVisible(row);
      await tester.pump();
      await activateBySemantics(tester, row);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(
        find.text('The neighbour'),
        findsWidgets,
        reason: 'the bridge handed off to the neighbour, as a finger does',
      );
      handle.dispose();
    });
  });

  group('board 07 — the voice-reply row', () {
    testWidgets('the mini-player plays from the bridge and is its own node', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      final players = <FakePreviewAudioPlayer>[];
      final arbiter = ReplyPlaybackArbiter();
      addTearDown(arbiter.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: VoiceReplyMiniPlayer(
                  commentId: 'c-a11y',
                  authorName: 'Bartek',
                  durationSeconds: 12,
                  arbiter: arbiter,
                  resolveMediaUri: () async =>
                      Uri.parse('https://cdn.example/c-a11y.m4a'),
                  playerFactory: () {
                    final player = FakePreviewAudioPlayer(
                      duration: const Duration(seconds: 12),
                    );
                    players.add(player);
                    return player;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(players, isEmpty, reason: 'no decoder until it is asked for');

      final row = find.byKey(
        const ValueKey<String>('voice-reply-mini-player-c-a11y'),
      );
      await activateBySemantics(tester, row);
      await tester.pump(const Duration(milliseconds: 60));

      expect(players, hasLength(1));
      expect(players.single.playCalls, 1);
      expect(arbiter.activeReplyId, 'c-a11y');
      handle.dispose();
    });

    testWidgets('at a phone width each comment is its own node, not one blob', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await pumpListenDetail(
        tester,
        moment: listenMoment('m-a11y-thread', comments: 2),
        size: const Size(390, 844),
        seed: (db) async {
          await seedListenComment(
            db,
            momentId: 'm-a11y-thread',
            id: 'c-text',
            authorName: 'Ola',
            text: 'I needed that morning too.',
          );
          await seedListenComment(
            db,
            momentId: 'm-a11y-thread',
            id: 'c-voice',
            authorId: 'bartek',
            authorName: 'Bartek',
            voice: true,
            durationSeconds: 12,
          );
        },
      );

      final row = find.byKey(
        const ValueKey<String>('voice-reply-mini-player-c-voice'),
      );
      await tester.scrollUntilVisible(
        row,
        240,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey<String>('moment-detail-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump();

      final node = tester.getSemantics(row);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(
        node.label,
        isNot(contains('I needed that morning too.')),
        reason:
            'the reply row is its own node; the whole conversation must '
            'not collapse into one 143-px "button" holding every author, '
            'every timestamp and every word',
      );
      handle.dispose();
    });
  });

  group('board 08 — the Yeels stage', () {
    testWidgets('the "Następny moment" card advances from the bridge', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      final players = FakeReelPlayers();
      await pumpReelStage(tester, players: players, count: 3);

      final card = find.byKey(reelNextCardKey);
      expect(card, findsOneWidget);
      await tester.ensureVisible(card);
      await tester.pump();
      await activateBySemantics(tester, card);
      await tester.pumpAndSettle();

      expect(
        find.text('Creator 2'),
        findsWidgets,
        reason: 'the bridge paged to the next Yeel, as the chevron does',
      );
      handle.dispose();
    });

    testWidgets('every enabled button on the Yeels stage is operable', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      for (final size in <Size>[const Size(390, 844), const Size(1440, 900)]) {
        final players = FakeReelPlayers();
        await pumpReelStage(
          tester,
          players: players,
          size: size,
          immersive: size.width < 600,
          count: 3,
        );
        _expectEveryEnabledButtonIsOperable(
          tester,
          'the Yeels stage at ${size.width.toInt()}',
        );
      }
      handle.dispose();
    });
  });

  group('board 06 — the overview card body', () {
    late VoidCallback restoreIdentity;
    setUp(() => restoreIdentity = installIdentityStub());
    tearDown(() => restoreIdentity());

    Future<void> pumpOverview(
      WidgetTester tester, {
      required double slot,
      double height = 900,
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
                friends: [friend('ola'), friend('bartek')],
              ),
              followService: FollowService(firestore: firestore, auth: auth),
              playerFactory: SilentPlayer.new,
            ),
          ),
          size: size,
        ),
      );
      await settleOverview(tester);
    }

    testWidgets('the named card body really opens its Moment from the '
        'bridge', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpOverview(tester, slot: 1200);

      expect(find.byType(BottomSheet), findsNothing, reason: 'nothing open');
      final card = _nodeWhere(
        tester,
        (data) => data.label.startsWith('Open Voice Moment: '),
        'names the card body the way the visual contract §7 asks',
      );
      expect(
        card.getSemanticsData().flagsCollection.isButton,
        isTrue,
        reason: 'the largest target on board 06 announces a button',
      );

      await _activateNode(tester, card);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(
        find.byType(BottomSheet),
        findsOneWidget,
        reason:
            'a button the bridge cannot press is the B1 defect: the card '
            'announced "Open Voice Moment: …, button" and activating it did '
            'nothing, because `explicitChildNodes` left the InkWell\'s tap '
            'action on a CHILD node',
      );
      handle.dispose();
    });

    testWidgets('every enabled button on the overview is operable', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      // 390 is the phone the boards were drawn at; 1200 is the wide-3 slot
      // the Home shell hands Moments, which is where the card body lives
      // beside the local and calm panels.
      for (final slot in <double>[390, 1200]) {
        await pumpOverview(tester, slot: slot);
        _expectEveryEnabledButtonIsOperable(
          tester,
          'the overview at ${slot.toInt()}',
        );
      }
      handle.dispose();
    });
  });
}
