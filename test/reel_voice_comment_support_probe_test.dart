import 'dart:ui' show Tristate;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_comments_view.dart';

import 'voice_moment_test_doubles.dart';

/// The mic beside the text composer, and the honesty rule it obeys.
///
/// Slice 4's backend is built but NOT deployed. Production therefore refuses
/// the voice contract, and the client must say so rather than offer a control
/// that can only fail — and must start offering it the moment the deployment
/// proves otherwise, with no new build.
typedef _Call = ({String name, Map<String, Object?> payload});

const _viewer = 'viewer';
const _micKey = ValueKey<String>('reel-comment-voice');

Map<String, Object?> _reelWire() {
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
    'commentCount': 0,
    'callerLiked': false,
  };
}

Map<Object?, Object?> _view() => <Object?, Object?>{
  'schemaVersion': 2,
  'reel': _reelWire(),
  'comments': const <Object?>[],
  'commentsTruncated': false,
  'nextCommentCursor': null,
};

class _Harness {
  _Harness({bool emailVerified = true, bool backendAcceptsVoice = true}) {
    service = ReelService(
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: _viewer, isEmailVerified: emailVerified),
      ),
      callableInvoker: (name, payload) async {
        calls.add((name: name, payload: payload));
        if (name == 'getReelViewV2') {
          if (!backendAcceptsVoice && payload.containsKey('commentTypes')) {
            // Exactly what `requireExactInput` answers to an unknown key on
            // a deployment that predates voice comments.
            throw FirebaseFunctionsException(
              code: 'invalid-argument',
              message: 'commentTypes is invalid.',
            );
          }
          return _view();
        }
        final responder = responders[name];
        if (responder == null) throw StateError('Unexpected callable $name');
        return responder(payload);
      },
      voiceCommentUploadInvoker:
          ({
            required String storagePath,
            required RecordedAudio audio,
            required Map<String, String> metadata,
          }) async => '1700000000000001',
    );
  }

  final List<_Call> calls = <_Call>[];
  final Map<
    String,
    Future<Map<Object?, Object?>> Function(Map<String, Object?>)
  >
  responders = {};
  final List<Reel> updates = <Reel>[];
  late final ReelService service;

  List<_Call> callsTo(String name) =>
      calls.where((call) => call.name == name).toList(growable: false);
}

/// Every semantics node in the rendered tree, in traversal order.
List<SemanticsNode> _allSemanticsNodes(WidgetTester tester) {
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

/// The one node that announces itself as the mic button named [label], found
/// the way a screen reader finds it rather than through a widget key.
SemanticsNode _micNode(WidgetTester tester, String label) {
  final matches = _allSemanticsNodes(tester).where((node) {
    final data = node.getSemanticsData();
    return data.label == label && data.flagsCollection.isButton;
  }).toList();
  expect(matches, hasLength(1), reason: 'exactly one "$label" button node');
  return matches.single;
}

void main() {
  setUp(ReelService.clearAllMediaAccessCaches);

  Future<void> pumpThread(
    WidgetTester tester,
    _Harness harness, {
    Size size = const Size(390, 844),
    double textScale = 1,
    ReelVoiceCommentComposer? composer,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: ReelCommentsView(
            reel: Reel.fromV2Wire(_reelWire()),
            service: harness.service,
            onReelUpdated: harness.updates.add,
            voiceComposer: composer,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool micEnabled(WidgetTester tester) =>
      tester.widget<IconButton>(find.byKey(_micKey)).onPressed != null;

  group('a backend that does not know voice comments', () {
    testWidgets('offers a disabled mic that says Coming soon', (tester) async {
      final semantics = tester.ensureSemantics();
      final harness = _Harness(backendAcceptsVoice: false);

      await pumpThread(tester, harness);

      expect(find.byKey(_micKey), findsOneWidget);
      expect(micEnabled(tester), isFalse);
      expect(
        find.bySemanticsLabel('Reply with voice — coming soon'),
        findsAtLeastNWidgets(1),
      );
      // Nothing is faked and nothing is invented.
      expect(
        harness.callsTo('reserveReelVoiceCommentDraft'),
        isEmpty,
        reason: 'a control that cannot work must not call anything',
      );
      semantics.dispose();
    });

    testWidgets('leaves the text composer exactly as it was', (tester) async {
      final harness = _Harness(backendAcceptsVoice: false);
      harness.responders['createReelComment'] = (_) async => <Object?, Object?>{
        'reelId': 'reel_1',
        'commentId': 'c1',
        'created': true,
        'commentCount': 1,
      };

      await pumpThread(tester, harness);
      await tester.enterText(
        find.byKey(const ValueKey<String>('reel-comment-field')),
        'Text still works',
      );
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey<String>('reel-comment-post')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey<String>('reel-comment-post')));
      await tester.pumpAndSettle();

      expect(harness.callsTo('createReelComment'), hasLength(1));
    });

    testWidgets('tapping the disabled mic opens nothing', (tester) async {
      var opened = 0;
      final harness = _Harness(backendAcceptsVoice: false);

      await pumpThread(
        tester,
        harness,
        composer: (context, {required authorName, required publish}) async {
          opened++;
          return false;
        },
      );
      await tester.tap(find.byKey(_micKey), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(opened, 0);
    });
  });

  group('a backend that accepts voice comments', () {
    testWidgets('offers a live mic named for its action', (tester) async {
      final semantics = tester.ensureSemantics();
      final harness = _Harness();

      await pumpThread(tester, harness);

      expect(micEnabled(tester), isTrue);
      expect(
        find.bySemanticsLabel('Reply with voice'),
        findsAtLeastNWidgets(1),
      );
      expect(
        find.bySemanticsLabel('Reply with voice — coming soon'),
        findsNothing,
      );
      semantics.dispose();
    });

    testWidgets(
      'the mic opens the recorder ONCE, and never opens a microphone itself',
      (tester) async {
        final opened = <String>[];
        final harness = _Harness();

        await pumpThread(
          tester,
          harness,
          composer: (context, {required authorName, required publish}) async {
            opened.add(authorName);
            return false;
          },
        );
        expect(opened, isEmpty, reason: 'mounting must open nothing');

        await tester.tap(find.byKey(_micKey));
        await tester.pumpAndSettle();

        expect(opened, <String>['Creator One']);
        // Opening the recorder reserves nothing: the reservation belongs to
        // the moment a person presses Publish.
        expect(harness.callsTo('reserveReelVoiceCommentDraft'), isEmpty);
      },
    );

    testWidgets('cancelling changes nothing and reloads nothing', (
      tester,
    ) async {
      final harness = _Harness();

      await pumpThread(
        tester,
        harness,
        composer: (context, {required authorName, required publish}) async =>
            null,
      );
      final viewsBefore = harness.callsTo('getReelViewV2').length;
      await tester.tap(find.byKey(_micKey));
      await tester.pumpAndSettle();

      expect(harness.callsTo('getReelViewV2'), hasLength(viewsBefore));
      expect(harness.callsTo('reserveReelVoiceCommentDraft'), isEmpty);
      expect(find.textContaining('Voice comment posted.'), findsNothing);
    });

    testWidgets('a published recording is re-read from the server', (
      tester,
    ) async {
      final harness = _Harness();
      harness.responders['reserveReelVoiceCommentDraft'] = (_) async =>
          <Object?, Object?>{
            'reelId': 'reel_1',
            'commentId': 'c1',
            'storagePath': 'reel_voice_comments/$_viewer/reel_1/c1.m4a',
            'created': true,
          };
      harness.responders['finalizeReelVoiceCommentDraft'] = (_) async =>
          <Object?, Object?>{
            'reelId': 'reel_1',
            'commentId': 'c1',
            'created': true,
            'commentCount': 1,
          };

      await pumpThread(
        tester,
        harness,
        composer: (context, {required authorName, required publish}) async {
          await publish(
            audio: FakeRecordedAudio(),
            durationSeconds: 8,
            caption: 'Here you go',
          );
          return true;
        },
      );
      final viewsBefore = harness.callsTo('getReelViewV2').length;
      await tester.tap(find.byKey(_micKey));
      await tester.pumpAndSettle();

      expect(harness.callsTo('reserveReelVoiceCommentDraft'), hasLength(1));
      expect(harness.callsTo('finalizeReelVoiceCommentDraft'), hasLength(1));
      expect(
        harness.callsTo('getReelViewV2').length,
        greaterThan(viewsBefore),
        reason: 'the thread re-reads rather than inventing the new comment',
      );
      // Once in the composer's own live-region note, and once in the
      // snackbar that announces it.
      expect(find.text('Voice comment posted.'), findsAtLeastNWidgets(1));
    });

    testWidgets('a refused publish is reported with copy the recorder shows', (
      tester,
    ) async {
      Object? reported;
      final harness = _Harness();
      harness.responders['reserveReelVoiceCommentDraft'] = (_) async =>
          throw FirebaseFunctionsException(
            code: 'resource-exhausted',
            message: 'refused in test',
          );

      await pumpThread(
        tester,
        harness,
        composer: (context, {required authorName, required publish}) async {
          try {
            await publish(
              audio: FakeRecordedAudio(),
              durationSeconds: 8,
              caption: '',
            );
            return true;
          } catch (error) {
            reported = error;
            return false;
          }
        },
      );
      await tester.tap(find.byKey(_micKey));
      await tester.pumpAndSettle();

      // Already-localized copy naming THIS operation, not a raw exception and
      // not Voice Moment wording.
      expect(reported, isA<VoiceMomentPresentationNotice>());
      final notice = reported! as VoiceMomentPresentationNotice;
      expect(notice.problem, VoiceRecordingProblem.uploadFailed);
      expect(notice.message.trim(), isNotEmpty);
      expect(notice.message, isNot(contains('Voice Moment')));
      expect(notice.action, contains('recording'));
      // Nothing is claimed to have been posted.
      expect(find.text('Voice comment posted.'), findsNothing);
    });

    testWidgets('a retry of the same take replays one request id', (
      tester,
    ) async {
      var attempts = 0;
      final harness = _Harness();
      harness.responders['reserveReelVoiceCommentDraft'] = (_) async =>
          <Object?, Object?>{
            'reelId': 'reel_1',
            'commentId': 'c1',
            'storagePath': 'reel_voice_comments/$_viewer/reel_1/c1.m4a',
            'created': true,
          };
      harness.responders['finalizeReelVoiceCommentDraft'] = (_) async {
        attempts++;
        if (attempts == 1) {
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'refused in test',
          );
        }
        return <Object?, Object?>{
          'reelId': 'reel_1',
          'commentId': 'c1',
          'created': true,
          'commentCount': 1,
        };
      };
      final audio = FakeRecordedAudio();

      await pumpThread(
        tester,
        harness,
        composer: (context, {required authorName, required publish}) async {
          try {
            await publish(audio: audio, durationSeconds: 8, caption: 'Take');
          } catch (_) {
            // The recorder keeps the recording and offers Publish again.
            await publish(audio: audio, durationSeconds: 8, caption: 'Take');
          }
          return true;
        },
      );
      await tester.tap(find.byKey(_micKey));
      await tester.pumpAndSettle();

      expect(harness.callsTo('reserveReelVoiceCommentDraft'), hasLength(1));
      expect(harness.callsTo('finalizeReelVoiceCommentDraft'), hasLength(2));
      final ids = harness.calls
          .where((call) => call.name.contains('VoiceCommentDraft'))
          .map((call) => call.payload['requestId'])
          .toSet();
      expect(ids, hasLength(1));
    });
  });

  group('targets, names and enlarged text', () {
    for (final (label, size) in <(String, Size)>[
      ('narrow', Size(320, 720)),
      ('medium', Size(768, 1024)),
      ('wide', Size(1440, 900)),
    ]) {
      testWidgets('$label: the mic and Send are both 48 px targets', (
        tester,
      ) async {
        final harness = _Harness();
        await pumpThread(tester, harness, size: size);

        final mic = tester.getSize(find.byKey(_micKey));
        expect(mic.width, greaterThanOrEqualTo(48));
        expect(mic.height, greaterThanOrEqualTo(48));
        final send = tester.getSize(
          find.byKey(const ValueKey<String>('reel-comment-post')),
        );
        expect(send.width, greaterThanOrEqualTo(48));
        expect(send.height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('200% text keeps the composer usable and unoverflowed', (
      tester,
    ) async {
      final harness = _Harness();
      await pumpThread(
        tester,
        harness,
        size: const Size(320, 720),
        textScale: 2,
      );

      expect(find.byKey(_micKey), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('reel-comment-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('reel-comment-post')),
        findsOneWidget,
      );
      final mic = tester.getSize(find.byKey(_micKey));
      expect(mic.height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    });

    // A pointer tap in flutter_test never crosses the accessibility bridge,
    // so the cases above could not see a mic whose Semantics wrapper had
    // excluded the IconButton's own tap action. These operate it the way
    // TalkBack, Switch Access and VoiceOver do.
    testWidgets('a live mic opens the recorder through the semantics tap', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var opened = 0;
      final harness = _Harness();
      await pumpThread(
        tester,
        harness,
        composer: (context, {required authorName, required publish}) async {
          opened++;
          return false;
        },
      );

      final node = _micNode(tester, 'Reply with voice');
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason: 'an enabled button with no tap action cannot be operated',
      );
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pumpAndSettle();

      expect(opened, 1);
      expect(harness.callsTo('reserveReelVoiceCommentDraft'), isEmpty);
      semantics.dispose();
    });

    testWidgets('a coming-soon mic offers assistive tech no action at all', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var opened = 0;
      final harness = _Harness(backendAcceptsVoice: false);
      await pumpThread(
        tester,
        harness,
        composer: (context, {required authorName, required publish}) async {
          opened++;
          return false;
        },
      );

      final data = _micNode(
        tester,
        'Reply with voice — coming soon',
      ).getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(opened, 0);
      semantics.dispose();
    });

    testWidgets('an unverified account is told why, and gets no mic', (
      tester,
    ) async {
      final harness = _Harness(emailVerified: false);
      await pumpThread(tester, harness);

      expect(
        find.byKey(const ValueKey<String>('reel-comment-verify-notice')),
        findsOneWidget,
      );
      expect(find.byKey(_micKey), findsNothing);
    });
  });
}
