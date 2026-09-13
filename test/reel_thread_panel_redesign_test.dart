import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/reels/presentation/widgets/reel_comments_view.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_engagement_bar.dart';

import 'reel_stage_test_support.dart';

/// The "Rozmowa" column and sheet of board 08.
///
/// One name for one thing at both widths, real rows with the moderation
/// control the backend actually has, and nothing that the backend does not:
/// no hearts on a comment (there is no like edge), and no microphone (voice
/// comments on Reels are a later slice — drawing the control before the
/// backend exists would promise something the app cannot do).
void main() {
  final comments = <Map<String, Object?>>[
    reelCommentWire(id: 'c1', authorId: 'creator_1', authorName: 'Creator 1'),
    reelCommentWire(
      id: 'c2',
      authorId: 'viewer',
      authorName: 'You',
      text: 'Mine to delete.',
    ),
  ];

  testWidgets('the docked column is the conversation, named once', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(1440, 900),
      service: reelStageService(count: 2, comments: comments),
    );

    expect(find.text('Conversation'), findsOneWidget);
    // The count beside the heading is the server's, rendered once.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('reels-thread-slot')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    // No second engagement bar: the card's footer owns the counts.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('reels-thread-slot')),
        matching: find.byType(ReelEngagementBar),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(reelPanelThreadToggleKey));
    await tester.pumpAndSettle();

    expect(find.byType(ReelCommentsView), findsOneWidget);
    expect(find.text('Great one.'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('rows carry their real moderation control and no heart', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(1440, 900),
      service: reelStageService(count: 2, comments: comments),
    );
    await tester.tap(find.byKey(reelPanelThreadToggleKey));
    await tester.pumpAndSettle();

    final thread = find.byType(ReelCommentsView);
    // D7: there is no like edge on a Reel comment, so no heart is drawn.
    for (final icon in <IconData>[
      Icons.favorite_border,
      Icons.favorite_border_rounded,
      Icons.favorite_rounded,
    ]) {
      expect(
        find.descendant(of: thread, matching: find.byIcon(icon)),
        findsNothing,
        reason: '$icon',
      );
    }
    // Someone else's comment offers Report; your own offers Delete. Each is
    // a labelled control rather than an unlabelled menu with one entry.
    expect(
      find.byKey(const ValueKey<String>('reel-comment-report-c1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('reel-comment-delete-c2')),
      findsOneWidget,
    );
  });

  testWidgets('the Reel’s author gets the ⋯ menu with both actions', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(1440, 900),
      service: reelStageService(
        count: 2,
        viewerUid: 'creator_1',
        comments: <Map<String, Object?>>[
          reelCommentWire(
            id: 'c1',
            authorId: 'stranger',
            authorName: 'Stranger',
          ),
        ],
      ),
    );
    await tester.tap(find.byKey(reelPanelThreadToggleKey));
    await tester.pumpAndSettle();

    final menu = find.byKey(const ValueKey<String>('reel-comment-actions-c1'));
    expect(menu, findsOneWidget);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text('Report comment'), findsOneWidget);
    expect(find.text('Remove from my Reel'), findsOneWidget);
  });

  testWidgets('the composer posts text and now carries the voice mic', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(1440, 900),
      service: reelStageService(count: 2, comments: comments),
    );
    await tester.tap(find.byKey(reelPanelThreadToggleKey));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('reel-comment-composer')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('reel-comment-post')),
      findsOneWidget,
    );
    // Slice 3 drew nothing here, because the voice backend did not exist.
    // Slice 5 shipped it, and the mic is now present and HONEST: this
    // service accepts the voice contract, so the control is live. Against a
    // backend that refuses it the same control is disabled and says
    // "coming soon" — see reel_voice_comment_support_probe_test.dart. It
    // still opens a recorder, never a microphone.
    final mic = find.byKey(const ValueKey<String>('reel-comment-voice'));
    expect(mic, findsOneWidget);
    expect(tester.widget<IconButton>(mic).onPressed, isNotNull);
    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
    // The RECORDING control belongs to the recorder screen, not here.
    expect(find.byIcon(Icons.mic_rounded), findsNothing);
  });

  testWidgets('the phone sheet carries the same heading and the same list', (
    tester,
  ) async {
    final players = FakeReelPlayers();
    await pumpReelStage(
      tester,
      players: players,
      size: const Size(390, 844),
      immersive: true,
      service: reelStageService(count: 2, comments: comments),
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('reels-stage')),
        matching: find.byKey(reelCommentsKey),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Conversation'), findsWidgets);
    expect(find.text('Great one.'), findsOneWidget);
    // The sheet hosts the same composer as the panel, mic included, and no
    // recording control of its own.
    expect(
      find.byKey(const ValueKey<String>('reel-comment-voice')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.mic_rounded), findsNothing);
  });
}
