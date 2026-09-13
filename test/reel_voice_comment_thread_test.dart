import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moments/presentation/widgets/reply_playback_arbiter.dart';
import 'package:yovoice/features/moments/presentation/widgets/voice_reply_mini_player.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_comments_view.dart';

import 'voice_moment_test_doubles.dart';

/// A voice comment inside the Reels thread: how it PARSES, how it RENDERS,
/// and what it is allowed to sound over.
typedef _Call = ({String name, Map<String, Object?> payload});

const _viewer = 'viewer';

Map<String, Object?> _reelWire({int commentCount = 0}) {
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
    'composition': const ReelComposition(
      trimStartMs: 0,
      trimEndMs: 10000,
    ).toWire(),
    'publishedAtMillis': millis,
    'sortKey': '${millis}_reel_1',
    'availability': <String, Object?>{
      'schemaVersion': 1,
      'availabilityHours': 'permanent',
      'expiresAtMillis': null,
    },
    'likeCount': 0,
    'commentCount': commentCount,
    'callerLiked': false,
  };
}

Map<String, Object?> _textComment(
  String id, {
  String authorId = 'creator_1',
  String authorName = 'Creator One',
  String text = 'Great one.',
}) => <String, Object?>{
  'schemaVersion': 1,
  'commentId': id,
  'type': 'text',
  'authorId': authorId,
  'authorName': authorName,
  'authorPhotoUrl': null,
  'text': text,
  'durationSeconds': null,
  'createdAtMillis': 1725000000000,
};

Map<String, Object?> _voiceComment(
  String id, {
  String authorId = 'creator_1',
  String authorName = 'Creator One',
  String text = '',
  int durationSeconds = 12,
}) => <String, Object?>{
  'schemaVersion': 1,
  'commentId': id,
  'type': 'voice',
  'authorId': authorId,
  'authorName': authorName,
  'authorPhotoUrl': null,
  'text': text,
  'durationSeconds': durationSeconds,
  'createdAtMillis': 1725000000000,
};

Map<Object?, Object?> _view(List<Map<String, Object?>> comments) =>
    <Object?, Object?>{
      'schemaVersion': 2,
      'reel': _reelWire(commentCount: comments.length),
      'comments': comments,
      'commentsTruncated': false,
      'nextCommentCursor': null,
    };

Map<Object?, Object?> _grant({int durationSeconds = 12}) => <Object?, Object?>{
  'schemaVersion': 2,
  'url': 'https://storage.googleapis.com/bucket/voice?sig=1',
  'expiresAtMillis': DateTime.now()
      .toUtc()
      .add(const Duration(seconds: 90))
      .millisecondsSinceEpoch,
  'generation': '1700000000000001',
  'durationSeconds': durationSeconds,
  'availabilityHours': 'permanent',
  'contentExpiresAtMillis': null,
};

class _Harness {
  _Harness() {
    service = ReelService(
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: _viewer, isEmailVerified: true),
      ),
      callableInvoker: (name, payload) {
        calls.add((name: name, payload: payload));
        final responder = responders[name];
        if (responder == null) throw StateError('Unexpected callable $name');
        return responder(payload);
      },
    );
  }

  final List<_Call> calls = <_Call>[];
  final Map<
    String,
    Future<Map<Object?, Object?>> Function(Map<String, Object?>)
  >
  responders = {};
  final List<Reel> updates = <Reel>[];
  final List<FakePreviewAudioPlayer> players = <FakePreviewAudioPlayer>[];
  late final ReelService service;

  FakePreviewAudioPlayer newPlayer() {
    final player = FakePreviewAudioPlayer();
    players.add(player);
    return player;
  }

  List<_Call> callsTo(String name) =>
      calls.where((call) => call.name == name).toList(growable: false);
}

void main() {
  setUp(ReelService.clearAllMediaAccessCaches);

  Future<void> pumpThread(
    WidgetTester tester,
    _Harness harness, {
    Size size = const Size(390, 844),
    ReplyPlaybackArbiter? arbiter,
    ReelVoiceCommentComposer? composer,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: ReelCommentsView(
            reel: Reel.fromV2Wire(_reelWire()),
            service: harness.service,
            onReelUpdated: harness.updates.add,
            arbiter: arbiter,
            voiceComposer: composer,
            voicePlayerFactory: harness.newPlayer,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the wire contract', () {
    test('a voice comment parses, with its duration and optional caption', () {
      final comment = ReelComment.fromWire(
        _voiceComment('c1', text: 'Have a listen', durationSeconds: 42),
      );
      expect(comment.isVoice, isTrue);
      expect(comment.kind, ReelCommentKind.voice);
      expect(comment.durationSeconds, 42);
      expect(comment.text, 'Have a listen');

      // A voice comment's content IS the recording, so a blank caption is
      // canonical rather than malformed.
      final captionless = ReelComment.fromWire(_voiceComment('c2'));
      expect(captionless.text, isEmpty);
      expect(captionless.isVoice, isTrue);
    });

    test('the old text shape still parses exactly as it did', () {
      final comment = ReelComment.fromWire(_textComment('c1'));
      expect(comment.isVoice, isFalse);
      expect(comment.kind, ReelCommentKind.text);
      expect(comment.durationSeconds, isNull);
      expect(comment.text, 'Great one.');
    });

    test('every off-contract shape is still refused', () {
      final cases = <String, Map<String, Object?>>{
        'a text comment carrying a duration': <String, Object?>{
          ..._textComment('c1'),
          'durationSeconds': 12,
        },
        'an empty text comment': <String, Object?>{
          ..._textComment('c1'),
          'text': '   ',
        },
        'a voice comment with no duration': <String, Object?>{
          ..._voiceComment('c1'),
          'durationSeconds': null,
        },
        'a zero-second recording': <String, Object?>{
          ..._voiceComment('c1'),
          'durationSeconds': 0,
        },
        'a 61-second recording': <String, Object?>{
          ..._voiceComment('c1'),
          'durationSeconds': 61,
        },
        'a fractional duration': <String, Object?>{
          ..._voiceComment('c1'),
          'durationSeconds': 7.5,
        },
        'a caption past the voice bound': <String, Object?>{
          ..._voiceComment('c1'),
          'text': 'x' * 141,
        },
        'a type this build has no presentation for': <String, Object?>{
          ..._voiceComment('c1'),
          'type': 'video',
        },
      };
      for (final entry in cases.entries) {
        expect(
          () => ReelComment.fromWire(entry.value),
          throwsA(isA<FormatException>()),
          reason: entry.key,
        );
      }
      // The bounds are exactly the deployed contract's.
      expect(ReelComment.minVoiceDurationSeconds, 1);
      expect(ReelComment.maxVoiceDurationSeconds, 60);
      expect(
        ReelComment.fromWire(
          _voiceComment('c1', durationSeconds: 1),
        ).durationSeconds,
        1,
      );
      expect(
        ReelComment.fromWire(
          _voiceComment('c1', durationSeconds: 60),
        ).durationSeconds,
        60,
      );
    });
  });

  group('rendering', () {
    testWidgets('a voice row is a player with a real duration, not text', (
      tester,
    ) async {
      final harness = _Harness();
      harness.responders['getReelViewV2'] = (_) async => _view(
        <Map<String, Object?>>[_voiceComment('c1', durationSeconds: 60)],
      );

      await pumpThread(tester, harness);

      expect(
        find.byKey(const ValueKey<String>('reel-voice-comment-c1')),
        findsOneWidget,
      );
      expect(find.byType(VoiceReplyMiniPlayer), findsOneWidget);
      // The projection's own value, printed as a clock rather than a guess:
      // the contract's maximum is 60 seconds and that is 1:00.
      expect(find.text('1:00'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      // NOTHING has been decoded or granted just by opening the thread.
      expect(harness.players, isEmpty);
      expect(harness.callsTo('getReelMediaAccessV2'), isEmpty);
    });

    testWidgets(
      'a caption renders under the player, and a blank one does not',
      (tester) async {
        final harness = _Harness();
        harness.responders['getReelViewV2'] = (_) async =>
            _view(<Map<String, Object?>>[
              _voiceComment('c1', text: 'Listen to the bridge'),
              _voiceComment('c2', text: ''),
            ]);

        await pumpThread(tester, harness);

        expect(find.text('Listen to the bridge'), findsOneWidget);
        expect(find.byType(VoiceReplyMiniPlayer), findsNWidgets(2));
      },
    );

    testWidgets('text and voice comments live in one thread', (tester) async {
      final harness = _Harness();
      harness.responders['getReelViewV2'] = (_) async =>
          _view(<Map<String, Object?>>[
            _textComment('c1', text: 'Words'),
            _voiceComment('c2'),
          ]);

      await pumpThread(tester, harness);

      expect(find.text('Words'), findsOneWidget);
      expect(find.byType(VoiceReplyMiniPlayer), findsOneWidget);
    });

    testWidgets('a voice row names itself for a screen reader', (tester) async {
      final semantics = tester.ensureSemantics();
      final harness = _Harness();
      harness.responders['getReelViewV2'] = (_) async =>
          _view(<Map<String, Object?>>[
            _voiceComment('c1', authorName: 'Creator One', durationSeconds: 9),
          ]);

      await pumpThread(tester, harness);

      // A regex, not an exact node label: the row's own name is merged with
      // the author and timestamp it contains, exactly as a TEXT comment row's
      // has always been. What matters is that the name a screen reader reads
      // says this is a VOICE comment and whose it is.
      expect(
        find.bySemanticsLabel(RegExp(r'Voice comment by Creator One')),
        findsAtLeastNWidgets(1),
      );
      // The player is its own button node with its own action and duration.
      expect(
        find.bySemanticsLabel(
          RegExp(r'Play voice reply from Creator One, 0:09'),
        ),
        findsAtLeastNWidgets(1),
      );
      semantics.dispose();
    });
  });

  group('playback', () {
    testWidgets('playing a comment mints its own comment-scoped grant', (
      tester,
    ) async {
      final harness = _Harness();
      harness.responders['getReelViewV2'] = (_) async =>
          _view(<Map<String, Object?>>[_voiceComment('c1')]);
      harness.responders['getReelMediaAccessV2'] = (_) async => _grant();

      await pumpThread(tester, harness);
      await tester.tap(
        find.byKey(const ValueKey<String>('voice-reply-mini-player-c1')),
      );
      await tester.pumpAndSettle();

      expect(harness.callsTo('getReelMediaAccessV2').single.payload, {
        'reelId': 'reel_1',
        'asset': 'voiceComment',
        'commentId': 'c1',
      });
      expect(harness.players.single.playCalls, 1);
    });

    testWidgets('a voice comment takes the floor from the Reel', (
      tester,
    ) async {
      final arbiter = ReplyPlaybackArbiter();
      addTearDown(arbiter.dispose);
      final floor = <String?>[];
      arbiter.addListener(() => floor.add(arbiter.activeReplyId));
      final harness = _Harness();
      harness.responders['getReelViewV2'] = (_) async =>
          _view(<Map<String, Object?>>[_voiceComment('c1')]);
      harness.responders['getReelMediaAccessV2'] = (_) async => _grant();

      await pumpThread(tester, harness, arbiter: arbiter);
      await tester.tap(
        find.byKey(const ValueKey<String>('voice-reply-mini-player-c1')),
      );
      await tester.pumpAndSettle();

      expect(arbiter.activeReplyId, 'c1');
      expect(floor, <String?>['c1']);
    });

    testWidgets('a second voice comment stops the first', (tester) async {
      final arbiter = ReplyPlaybackArbiter();
      addTearDown(arbiter.dispose);
      final harness = _Harness();
      harness.responders['getReelViewV2'] = (_) async => _view(
        <Map<String, Object?>>[_voiceComment('c1'), _voiceComment('c2')],
      );
      harness.responders['getReelMediaAccessV2'] = (_) async => _grant();

      await pumpThread(tester, harness, arbiter: arbiter);
      await tester.tap(
        find.byKey(const ValueKey<String>('voice-reply-mini-player-c1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('voice-reply-mini-player-c2')),
      );
      await tester.pumpAndSettle();

      expect(arbiter.activeReplyId, 'c2');
      // The first row paused itself rather than sounding under the second.
      expect(harness.players.first.pauseCalls, 1);
      expect(harness.players.last.playCalls, 1);
    });

    testWidgets('the main recording taking over stops a sounding comment', (
      tester,
    ) async {
      final arbiter = ReplyPlaybackArbiter();
      addTearDown(arbiter.dispose);
      final harness = _Harness();
      harness.responders['getReelViewV2'] = (_) async =>
          _view(<Map<String, Object?>>[_voiceComment('c1')]);
      harness.responders['getReelMediaAccessV2'] = (_) async => _grant();

      await pumpThread(tester, harness, arbiter: arbiter);
      await tester.tap(
        find.byKey(const ValueKey<String>('voice-reply-mini-player-c1')),
      );
      await tester.pumpAndSettle();

      arbiter.mainPlaybackStarted();
      await tester.pumpAndSettle();

      expect(arbiter.activeReplyId, isNull);
      expect(harness.players.single.pauseCalls, 1);
    });

    testWidgets('a refused grant says so instead of failing silently', (
      tester,
    ) async {
      final harness = _Harness();
      harness.responders['getReelViewV2'] = (_) async =>
          _view(<Map<String, Object?>>[_voiceComment('c1')]);
      harness.responders['getReelMediaAccessV2'] = (_) async =>
          throw FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'refused in test',
          );

      await pumpThread(tester, harness);
      await tester.tap(
        find.byKey(const ValueKey<String>('voice-reply-mini-player-c1')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('This voice reply is unavailable right now.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });
  });

  group('moderation and the text path', () {
    testWidgets('a voice comment can be deleted by its own author', (
      tester,
    ) async {
      final harness = _Harness();
      harness.responders['getReelViewV2'] = (_) async =>
          _view(<Map<String, Object?>>[
            _voiceComment('c1', authorId: _viewer, authorName: 'You'),
          ]);
      harness.responders['deleteReelComment'] = (_) async => <Object?, Object?>{
        'reelId': 'reel_1',
        'commentId': 'c1',
        'deleted': true,
        'commentCount': 0,
      };

      await pumpThread(tester, harness);
      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-delete-c1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-delete-confirm')),
      );
      await tester.pumpAndSettle();

      expect(harness.callsTo('deleteReelComment'), hasLength(1));
      expect(find.byType(VoiceReplyMiniPlayer), findsNothing);
    });

    testWidgets('posting a text comment is unchanged by the voice path', (
      tester,
    ) async {
      final harness = _Harness();
      harness.responders['getReelViewV2'] = (_) async =>
          _view(<Map<String, Object?>>[]);
      harness.responders['createReelComment'] = (_) async => <Object?, Object?>{
        'reelId': 'reel_1',
        'commentId': 'c9',
        'created': true,
        'commentCount': 1,
      };

      await pumpThread(tester, harness);
      await tester.enterText(
        find.byKey(const ValueKey<String>('reel-comment-field')),
        'Still works',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('reel-comment-post')));
      await tester.pumpAndSettle();

      expect(harness.callsTo('createReelComment'), hasLength(1));
      expect(
        harness.callsTo('createReelComment').single.payload['text'],
        'Still works',
      );
    });
  });

  group('the microphone', () {
    testWidgets('never opens on mount, and never on a thread reload', (
      tester,
    ) async {
      var composerOpened = 0;
      final harness = _Harness();
      harness.responders['getReelViewV2'] = (_) async =>
          _view(<Map<String, Object?>>[_voiceComment('c1')]);
      harness.responders['getReelMediaAccessV2'] = (_) async => _grant();

      await pumpThread(
        tester,
        harness,
        composer: (context, {required authorName, required publish}) async {
          composerOpened++;
          return false;
        },
      );

      // Opening a thread, rendering a voice row, and even playing one must
      // not reach a recorder — let alone a microphone.
      expect(composerOpened, 0);
      await tester.tap(
        find.byKey(const ValueKey<String>('voice-reply-mini-player-c1')),
      );
      await tester.pumpAndSettle();
      expect(composerOpened, 0);
      expect(
        harness.callsTo('reserveReelVoiceCommentDraft'),
        isEmpty,
        reason: 'nothing is reserved without a deliberate recording',
      );
    });
  });
}
