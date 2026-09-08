import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/screens/reels_feed_screen.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_comments_view.dart';

/// On the wide layout the docked panel owns the only way into a Reel's
/// conversation. These tests hold that control on screen when the panel's
/// header — an author row, a caption of any length, an engagement bar — is
/// large enough to want the whole column, and hold the conversation itself
/// readable once that control has been used.
const _threadToggle = ValueKey<String>('reel-panel-thread-toggle');
const _closedThread = ValueKey<String>('reel-panel-thread-closed');
const _commentList = ValueKey<String>('reel-comment-thread');
const _composer = ValueKey<String>('reel-comment-composer');

/// The one comment the fake backend serves into the opened thread.
const _commentBody = 'Great one.';

/// A caption a person really can publish: at 200 % text it fills the panel's
/// caption block to its cap on its own.
const _longCaption =
    'Night shift stories from the harbour, recorded between two calls and '
    'edited on the way home while the city was still awake and the last '
    'ferry had not left yet.';

Map<String, Object?> _reelWire(String caption) {
  const millis = 1725000000000;
  return <String, Object?>{
    'id': 'reel_1',
    'authorId': 'creator_1',
    'authorName': 'Creator One',
    'media': <String, Object?>{
      'kind': 'video',
      'contentType': 'video/mp4',
      'size': 4096,
      'generation': '7',
      'durationMs': 10000,
    },
    'backingAudio': null,
    'composition': ReelComposition(
      trimStartMs: 0,
      trimEndMs: 10000,
      caption: caption,
    ).toWire(),
    'publishedAtMillis': millis,
    'sortKey': '${millis}_reel_1',
    'availability': <String, Object?>{
      'schemaVersion': 1,
      'availabilityHours': 'permanent',
      'expiresAtMillis': null,
    },
    'likeCount': 4,
    'commentCount': 2,
    'callerLiked': false,
  };
}

ReelService _service(String caption) {
  return ReelService(
    auth: MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'viewer', isEmailVerified: true),
    ),
    callableInvoker: (name, payload) async {
      switch (name) {
        case 'listReelsV2':
          return <Object?, Object?>{
            'schemaVersion': 2,
            'items': <Object?>[_reelWire(caption)],
            'nextCursor': null,
          };
        case 'getReelMediaAccessV2':
          return <Object?, Object?>{
            'schemaVersion': 2,
            'url': 'https://storage.googleapis.com/yovoice/reel.mp4?token=t',
            'expiresAtMillis': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 5))
                .millisecondsSinceEpoch,
            'generation': '7',
            'availabilityHours': 'permanent',
            'contentExpiresAtMillis': null,
          };
        case 'getReelViewV2':
          return <Object?, Object?>{
            'schemaVersion': 2,
            'reel': _reelWire(caption),
            'comments': <Object?>[
              <String, Object?>{
                'schemaVersion': 1,
                'commentId': 'c1',
                'type': 'text',
                'authorId': 'creator_1',
                'authorName': 'Creator One',
                'authorPhotoUrl': null,
                'text': _commentBody,
                'durationSeconds': null,
                'createdAtMillis': 1725000000000,
              },
            ],
            'commentsTruncated': false,
            'nextCommentCursor': null,
          };
      }
      throw StateError('Unexpected callable $name');
    },
  );
}

/// Pumps the wide feed under [chrome] pixels of destination chrome.
///
/// In the product the feed is embedded: YO Moments draws its own header above
/// it and the desktop shell draws its own around that. [chrome] stands in for
/// exactly that — the height the panel really gets, not the height of the
/// window — because that is what decides whether the docked thread control
/// survives.
Future<void> _pumpWideFeed(
  WidgetTester tester, {
  required ThemeData theme,
  required double textScale,
  double chrome = 0,
  Size size = const Size(1440, 900),
  String caption = _longCaption,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Column(
          children: <Widget>[
            SizedBox(height: chrome),
            Expanded(
              child: ReelsFeedScreen(
                embedded: true,
                service: _service(caption),
                videoBuilder: (_, _, _) =>
                    const ColoredBox(color: Colors.black),
                onOpenAuthor: (_) {},
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final themeEntry in <String, ThemeData>{
    'Dark': AppTheme.darkTheme,
    'Pearl': AppTheme.lightTheme,
  }.entries) {
    // 0 is the bare window; 220 is the destination chrome the feed really
    // sits under, which is where the header first outgrows the column.
    for (final chrome in const <double>[0, 220]) {
      testWidgets(
        '${themeEntry.key} 1440x900 at 200 % keeps the thread control whole '
        'under ${chrome.toInt()} px of chrome',
        (tester) async {
          await _pumpWideFeed(
            tester,
            theme: themeEntry.value,
            textScale: 2,
            chrome: chrome,
          );

          // The panel is docked and closed: no sheet, no thread yet.
          expect(find.byKey(_closedThread), findsOneWidget);
          expect(find.byType(ReelCommentsView), findsNothing);
          // A RenderFlex overflow is reported as an exception on this frame.
          expect(tester.takeException(), isNull);

          final toggle = find.byKey(_threadToggle);
          expect(toggle, findsOneWidget);
          // Painted is not enough: the control has to be what a pointer
          // actually lands on at that spot.
          expect(toggle.hitTestable(), findsOneWidget);

          final target = tester.getRect(toggle);
          expect(target.height, greaterThanOrEqualTo(44));
          // Whole inside the block it lives in, so nothing clips it.
          final block = tester.getRect(find.byKey(_closedThread));
          expect(target.top, greaterThanOrEqualTo(block.top - .01));
          expect(target.bottom, lessThanOrEqualTo(block.bottom + .01));
          // And inside the window, so nothing clips the block either.
          expect(target.bottom, lessThanOrEqualTo(900.01));

          await tester.tap(toggle);
          await tester.pumpAndSettle();

          // The callback still opens the thread beside the feed.
          expect(find.byType(ReelCommentsView), findsOneWidget);
          expect(find.byType(BottomSheet), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }

    // Opening the thread has to buy the thread room. 320 is past the point
    // where the header alone wants the whole column, so it is where reserving
    // for the closed block would leave the composer sitting on the
    // conversation.
    for (final chrome in const <double>[0, 220, 320]) {
      testWidgets(
        '${themeEntry.key} 1440x900 at 200 % reads the opened thread under '
        '${chrome.toInt()} px of chrome',
        (tester) async {
          await _pumpWideFeed(
            tester,
            theme: themeEntry.value,
            textScale: 2,
            chrome: chrome,
          );
          await tester.tap(find.byKey(_threadToggle));
          await tester.pumpAndSettle();
          expect(find.byType(ReelCommentsView), findsOneWidget);
          expect(tester.takeException(), isNull);

          // The composer is whole and inside the window: it is pinned to the
          // bottom of the thread and is the first thing a too-small
          // reservation squeezes.
          final composer = tester.getRect(find.byKey(_composer));
          expect(composer.height, greaterThan(0));
          expect(composer.bottom, lessThanOrEqualTo(900.01));

          // And the conversation the reader just asked for is legible without
          // scrolling: a whole comment — author line and body — inside the
          // list's own viewport, not clipped to a sliver above the composer.
          final viewport = tester.getRect(find.byKey(_commentList));
          final body = tester.getRect(find.text(_commentBody));
          expect(body.top, greaterThanOrEqualTo(viewport.top - .01));
          expect(body.bottom, lessThanOrEqualTo(viewport.bottom + .01));
          expect(
            viewport.height,
            greaterThanOrEqualTo(body.height),
            reason: 'the thread viewport must hold more than a line of text',
          );
        },
      );
    }

    testWidgets(
      '${themeEntry.key} opening the thread costs a roomy header nothing',
      (tester) async {
        // Reserving for the open thread caps how tall the header may be; it
        // must not start scrolling a header that still fits.
        await _pumpWideFeed(tester, theme: themeEntry.value, textScale: 2);
        await tester.tap(find.byKey(_threadToggle));
        await tester.pumpAndSettle();

        final header = find.ancestor(
          of: find.text(_longCaption),
          matching: find.byType(SingleChildScrollView),
        );
        expect(header, findsOneWidget);
        final position = tester
            .state<ScrollableState>(
              find.descendant(of: header, matching: find.byType(Scrollable)),
            )
            .position;
        expect(position.maxScrollExtent, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${themeEntry.key} short wide window at 200 % still reaches the thread',
      (tester) async {
        // A desktop window this short at this text size leaves the panel less
        // room than its header alone wants. The header is what gives way.
        await _pumpWideFeed(
          tester,
          theme: themeEntry.value,
          textScale: 2,
          size: const Size(1440, 420),
        );

        expect(tester.takeException(), isNull);
        final toggle = find.byKey(_threadToggle);
        expect(toggle.hitTestable(), findsOneWidget);
        final target = tester.getRect(toggle);
        expect(target.height, greaterThanOrEqualTo(44));
        expect(target.bottom, lessThanOrEqualTo(420.01));
        final block = tester.getRect(find.byKey(_closedThread));
        expect(target.bottom, lessThanOrEqualTo(block.bottom + .01));
        // The thread is not opened here on purpose: a column this short
        // cannot host ReelCommentsView at 200 % text, and that widget's own
        // layout is not what this test is about.
      },
    );

    testWidgets(
      '${themeEntry.key} panel header keeps its natural height when the '
      'column is roomy',
      (tester) async {
        await _pumpWideFeed(tester, theme: themeEntry.value, textScale: 1);

        expect(tester.takeException(), isNull);
        // Nothing is given up at an ordinary text size: the whole header is
        // painted and the caption is not cut short by the fix.
        expect(find.text(_longCaption), findsOneWidget);
        expect(find.text('Creator One'), findsOneWidget);
        expect(find.byKey(_threadToggle).hitTestable(), findsOneWidget);
        expect(
          tester.getRect(find.byKey(_threadToggle)).height,
          greaterThanOrEqualTo(44),
        );
      },
    );
  }
}
