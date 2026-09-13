// The voice-reply mini-player inside a thread: it allocates nothing until
// it is tapped, it says what it is doing, it is honest when the grant
// fails, and it obeys the arbiter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/moments/presentation/widgets/reply_playback_arbiter.dart';
import 'package:yovoice/features/moments/presentation/widgets/voice_reply_mini_player.dart';

import 'voice_moment_test_doubles.dart';

void main() {
  Future<void> pumpPlayer(
    WidgetTester tester, {
    required Future<Uri> Function() resolve,
    ReplyPlaybackArbiter? arbiter,
    List<FakePreviewAudioPlayer>? created,
    String commentId = 'c1',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: VoiceReplyMiniPlayer(
                commentId: commentId,
                authorName: 'Ola',
                durationSeconds: 12,
                resolveMediaUri: resolve,
                arbiter: arbiter,
                playerFactory: () {
                  final player = FakePreviewAudioPlayer(
                    duration: const Duration(seconds: 12),
                  );
                  created?.add(player);
                  return player;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a thread of voice replies allocates no player until one is '
      'tapped', (tester) async {
    final created = <FakePreviewAudioPlayer>[];
    await pumpPlayer(
      tester,
      resolve: () async => Uri.parse('https://storage.googleapis.com/a.m4a'),
      created: created,
    );

    expect(created, isEmpty);
    expect(find.text('0:12'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('voice-reply-mini-player-c1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(created, hasLength(1));
    expect(created.single.playCalls, 1);
  });

  testWidgets('the whole row is one toggled button naming the author and '
      'the length', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpPlayer(
      tester,
      resolve: () async => Uri.parse('https://storage.googleapis.com/a.m4a'),
    );

    expect(
      find.bySemanticsLabel('Play voice reply from Ola, 0:12'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('voice-reply-mini-player-c1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.bySemanticsLabel('Pause voice reply from Ola, 0:12'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('a refused grant says so and leaves the row stopped', (
    tester,
  ) async {
    final created = <FakePreviewAudioPlayer>[];
    await pumpPlayer(
      tester,
      resolve: () async => throw StateError('no grant'),
      created: created,
    );

    await tester.tap(find.byKey(const ValueKey('voice-reply-mini-player-c1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('This voice reply is unavailable right now.'),
      findsOneWidget,
    );
    expect(created.single.playCalls, 0);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('losing the floor to another reply pauses this one', (
    tester,
  ) async {
    final arbiter = ReplyPlaybackArbiter();
    addTearDown(arbiter.dispose);
    final created = <FakePreviewAudioPlayer>[];
    await pumpPlayer(
      tester,
      resolve: () async => Uri.parse('https://storage.googleapis.com/a.m4a'),
      arbiter: arbiter,
      created: created,
    );

    await tester.tap(find.byKey(const ValueKey('voice-reply-mini-player-c1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(arbiter.activeReplyId, 'c1');
    expect(created.single.pauseCalls, 0);

    // Another row in the same thread takes over.
    arbiter.replyStarted('c2');
    await tester.pump();

    expect(created.single.pauseCalls, 1);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('the main recording starting stops the reply', (tester) async {
    final arbiter = ReplyPlaybackArbiter();
    addTearDown(arbiter.dispose);
    final created = <FakePreviewAudioPlayer>[];
    await pumpPlayer(
      tester,
      resolve: () async => Uri.parse('https://storage.googleapis.com/a.m4a'),
      arbiter: arbiter,
      created: created,
    );

    await tester.tap(find.byKey(const ValueKey('voice-reply-mini-player-c1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    arbiter.mainPlaybackStarted();
    await tester.pump();

    expect(created.single.pauseCalls, 1);
  });

  testWidgets('leaving the thread disposes the player and releases the floor', (
    tester,
  ) async {
    final arbiter = ReplyPlaybackArbiter();
    addTearDown(arbiter.dispose);
    final created = <FakePreviewAudioPlayer>[];
    await pumpPlayer(
      tester,
      resolve: () async => Uri.parse('https://storage.googleapis.com/a.m4a'),
      arbiter: arbiter,
      created: created,
    );

    await tester.tap(find.byKey(const ValueKey('voice-reply-mini-player-c1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    await tester.pump();

    expect(created.single.disposeCalls, 1);
    expect(arbiter.activeReplyId, isNull);
  });

  testWidgets('a second tap pauses instead of re-resolving the grant', (
    tester,
  ) async {
    var grants = 0;
    final created = <FakePreviewAudioPlayer>[];
    await pumpPlayer(
      tester,
      resolve: () async {
        grants++;
        return Uri.parse('https://storage.googleapis.com/a.m4a');
      },
      created: created,
    );

    final row = find.byKey(const ValueKey('voice-reply-mini-player-c1'));
    await tester.tap(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(row);
    await tester.pump();
    await tester.tap(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(grants, 1, reason: 'a resumed reply does not mint a second grant');
    expect(created.single.pauseCalls, 1);
    expect(created.single.resumeCalls, 1);
  });
}
