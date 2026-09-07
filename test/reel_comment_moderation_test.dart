// Reel comment moderation from the client: reporting somebody else's comment,
// and a Reel's author clearing one off their own thread.
//
// The server owns both decisions. Everything asserted here is about what the
// client OFFERS, what it SENDS, and what it SAYS when the server refuses —
// never about predicting an authorization outcome, which is why there is no
// test that expects the client to hide a control a `permission-denied` would
// have covered.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moderation/data/services/report_service.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_comment_report_sheet.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_comments_view.dart';

typedef _Call = ({String name, Map<String, Object?> payload});

const _viewer = 'viewer';
const _reelAuthor = 'creator_1';
const _otherAuthor = 'u_other';

FirebaseFunctionsException _refusal(String code) =>
    FirebaseFunctionsException(code: code, message: 'refused in test');

Map<String, Object?> _reelWire({
  int commentCount = 0,
  String authorId = _reelAuthor,
}) {
  const millis = 1725000000000;
  return <String, Object?>{
    'id': 'reel_1',
    'authorId': authorId,
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

Reel _reel({int commentCount = 0, String authorId = _reelAuthor}) =>
    Reel.fromV2Wire(_reelWire(commentCount: commentCount, authorId: authorId));

Map<String, Object?> _commentWire(
  String id, {
  String authorId = _otherAuthor,
  String authorName = 'Other Person',
  String text = 'Their words.',
  int createdAtMillis = 1725000000000,
}) => <String, Object?>{
  'schemaVersion': 1,
  'commentId': id,
  'type': 'text',
  'authorId': authorId,
  'authorName': authorName,
  'authorPhotoUrl': null,
  'text': text,
  'durationSeconds': null,
  'createdAtMillis': createdAtMillis,
};

Map<Object?, Object?> _view(
  List<Map<String, Object?>> comments, {
  int? commentCount,
  String reelAuthorId = _reelAuthor,
}) => <Object?, Object?>{
  'schemaVersion': 2,
  'reel': _reelWire(
    commentCount: commentCount ?? comments.length,
    authorId: reelAuthorId,
  ),
  'comments': comments,
  'commentsTruncated': false,
  'nextCommentCursor': null,
};

class _Harness {
  _Harness() {
    service = ReelService(
      auth: MockFirebaseAuth(
        signedIn: true,
        // Reporting and author removal are NOT gated on a verified email —
        // a safety action never is — so the fixture stays unverified to
        // prove the client does not add a gate the backend does not have.
        mockUser: MockUser(uid: _viewer, isEmailVerified: false),
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
  late final ReelService service;

  List<_Call> callsTo(String name) =>
      calls.where((call) => call.name == name).toList(growable: false);
}

Future<void> _pumpThread(
  WidgetTester tester,
  _Harness harness, {
  Reel? reel,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<Object?>>[
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // ABOVE the Navigator, not inside `home`. The report sheet is a modal
      // route, so a MediaQuery wrapped around the thread alone never reaches
      // it and a "200% text scale" test would silently measure 100%. A real
      // device's scale arrives through the root MediaQuery and does reach
      // every route; this is what reproduces that.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: SafeArea(
          child: ReelCommentsView(
            reel: reel ?? _reel(commentCount: 1),
            service: harness.service,
            onReelUpdated: harness.updates.add,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the report sheet from a comment row and picks [reason].
Future<void> _openReport(
  WidgetTester tester,
  String commentId, {
  ReportReason reason = ReportReason.harassment,
  String? note,
  bool send = true,
}) async {
  await tester.tap(
    find.byKey(ValueKey<String>('reel-comment-report-$commentId')),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(ValueKey<String>('reel-comment-report-reason-${reason.name}')),
  );
  await tester.pumpAndSettle();
  if (note != null) {
    await tester.enterText(
      find.byKey(const ValueKey<String>('reel-comment-report-note')),
      note,
    );
    await tester.pumpAndSettle();
  }
  if (send) {
    await tester.tap(
      find.byKey(const ValueKey<String>('reel-comment-report-submit')),
    );
    await tester.pumpAndSettle();
  }
}

Map<Object?, Object?> _reportOk({bool created = true}) => <Object?, Object?>{
  'reportId': 'report_abc',
  'created': created,
};

void main() {
  group('reporting somebody else\'s comment', () {
    _Harness reportHarness({
      Future<Map<Object?, Object?>> Function(Map<String, Object?>)? onReport,
    }) {
      final harness = _Harness();
      harness.responders['getReelViewV2'] = (_) async =>
          _view(<Map<String, Object?>>[_commentWire('c1')]);
      harness.responders['createReelCommentReport'] =
          onReport ?? (_) async => _reportOk();
      return harness;
    }

    testWidgets('sends the chosen reason and note, and keeps the comment', (
      tester,
    ) async {
      final harness = reportHarness();
      await _pumpThread(tester, harness);

      await _openReport(
        tester,
        'c1',
        reason: ReportReason.impersonation,
        note: '  Pretending to be my sister.  ',
      );

      final report = harness.callsTo('createReelCommentReport').single;
      expect(report.payload['reelId'], 'reel_1');
      expect(report.payload['commentId'], 'c1');
      expect(report.payload['reason'], 'impersonation');
      // Trimmed, so a retry of this attempt hashes identically server-side.
      expect(report.payload['note'], 'Pretending to be my sister.');
      expect(report.payload['requestId'], isA<String>());

      expect(find.text('Thanks. This comment was sent for review.'), findsOne);
      // The reporter is not the person who decides: the comment stays.
      expect(find.text('Their words.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('reel-comment-reported-c1')),
        findsOneWidget,
      );
      expect(find.text('Reported — with our team'), findsOneWidget);
      // Nothing about the thread's size changed, so no count was adopted.
      expect(harness.updates.every((reel) => reel.commentCount == 1), isTrue);
    });

    testWidgets('a note is optional and the call still carries an empty one', (
      tester,
    ) async {
      final harness = reportHarness();
      await _pumpThread(tester, harness);

      await _openReport(tester, 'c1', reason: ReportReason.spam);

      expect(
        harness.callsTo('createReelCommentReport').single.payload['note'],
        '',
      );
      expect(find.text('Thanks. This comment was sent for review.'), findsOne);
    });

    testWidgets('Send stays disabled until a reason is chosen', (tester) async {
      final harness = reportHarness();
      await _pumpThread(tester, harness);

      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-report-c1')),
      );
      await tester.pumpAndSettle();

      // There is no honest default reason, so there is nothing to send yet.
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey<String>('reel-comment-report-submit')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-report-reason-hate')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey<String>('reel-comment-report-submit')),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('backing out of the sheet files nothing', (tester) async {
      final harness = reportHarness();
      await _pumpThread(tester, harness);

      await _openReport(tester, 'c1', send: false);
      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-report-cancel')),
      );
      await tester.pumpAndSettle();

      expect(harness.callsTo('createReelCommentReport'), isEmpty);
      expect(
        find.byKey(const ValueKey<String>('reel-comment-reported-c1')),
        findsNothing,
      );
    });

    testWidgets('the note cannot exceed the 300 the backend accepts', (
      tester,
    ) async {
      final harness = reportHarness();
      await _pumpThread(tester, harness);

      await _openReport(tester, 'c1', note: 'x' * 400);

      final sent =
          harness.callsTo('createReelCommentReport').single.payload['note']!
              as String;
      expect(sent.length, maxReelReportNoteLength);
      expect(sent, 'x' * maxReelReportNoteLength);
    });

    testWidgets(
      'an already-deduplicated report is not announced as a new one',
      (tester) async {
        final harness = reportHarness(
          onReport: (_) async => _reportOk(created: false),
        );
        await _pumpThread(tester, harness);

        await _openReport(tester, 'c1');

        expect(
          find.text(
            'You already reported this comment. It is still with our team.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Thanks. This comment was sent for review.'),
          findsNothing,
        );
        // Still a successful report, so the row still says so.
        expect(
          find.byKey(const ValueKey<String>('reel-comment-reported-c1')),
          findsOneWidget,
        );
      },
    );

    testWidgets('retrying the identical attempt reuses the request id', (
      tester,
    ) async {
      var attempts = 0;
      final harness = reportHarness(
        onReport: (_) async {
          if (attempts++ == 0) throw _refusal('unavailable');
          return _reportOk();
        },
      );
      await _pumpThread(tester, harness);

      await _openReport(tester, 'c1', note: 'Same words.');
      expect(find.text('Check your connection and try again.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('reel-comment-reported-c1')),
        findsNothing,
      );

      // Re-opening restores the reporter's own choice, so the retry is one
      // tap and stays byte-identical.
      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-report-c1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Same words.'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-report-submit')),
      );
      await tester.pumpAndSettle();

      final reports = harness.callsTo('createReelCommentReport');
      expect(reports, hasLength(2));
      expect(reports[1].payload['requestId'], reports[0].payload['requestId']);
      expect(reports[1].payload['reason'], reports[0].payload['reason']);
      expect(reports[1].payload['note'], 'Same words.');
      expect(find.text('Thanks. This comment was sent for review.'), findsOne);
    });

    testWidgets('changing the reason after a refusal mints a fresh id', (
      tester,
    ) async {
      var attempts = 0;
      final harness = reportHarness(
        onReport: (_) async {
          if (attempts++ == 0) throw _refusal('unavailable');
          return _reportOk();
        },
      );
      await _pumpThread(tester, harness);

      await _openReport(tester, 'c1', reason: ReportReason.spam);
      await _openReport(tester, 'c1', reason: ReportReason.hate);

      final reports = harness.callsTo('createReelCommentReport');
      expect(reports, hasLength(2));
      // The server binds one request id to one exact input. A different
      // reason is a different operation, so replaying the id would answer
      // `already-exists` on a safety path.
      expect(
        reports[1].payload['requestId'],
        isNot(reports[0].payload['requestId']),
      );
      expect(reports[0].payload['reason'], 'spam');
      expect(reports[1].payload['reason'], 'hate');
    });

    for (final (code, message) in <(String, String)>[
      ('unauthenticated', 'Sign in again to report this comment.'),
      ('failed-precondition', 'You cannot report your own comment.'),
      (
        'resource-exhausted',
        'You have sent several reports recently. '
            'Try this one again in a few minutes.',
      ),
      ('permission-denied', 'That comment is no longer available.'),
      ('not-found', 'That comment is no longer available.'),
      (
        'already-exists',
        'You have already reported this comment. It is with our team.',
      ),
      ('invalid-argument', 'The report could not be sent. Try again.'),
      ('unavailable', 'Check your connection and try again.'),
      ('deadline-exceeded', 'Check your connection and try again.'),
      ('internal', 'The report could not be sent. Try again.'),
    ]) {
      testWidgets('$code is explained as "$message"', (tester) async {
        final harness = reportHarness(
          onReport: (_) async => throw _refusal(code),
        );
        await _pumpThread(tester, harness);

        await _openReport(tester, 'c1');

        expect(find.text(message), findsOneWidget);
        // A refused report is not a filed one.
        expect(
          find.byKey(const ValueKey<String>('reel-comment-reported-c1')),
          findsNothing,
        );
        expect(find.text('Their words.'), findsOneWidget);
        // No status code and no exception string ever reaches the viewer.
        expect(find.textContaining(code), findsNothing);
        expect(find.textContaining('ReelEngagement'), findsNothing);
      });
    }

    testWidgets('an unverified account can still report', (tester) async {
      final harness = reportHarness();
      await _pumpThread(tester, harness);

      // The composer is gated on verification; the safety control is not.
      expect(
        find.byKey(const ValueKey<String>('reel-comment-verify-notice')),
        findsOneWidget,
      );
      await _openReport(tester, 'c1');

      expect(harness.callsTo('createReelCommentReport'), hasLength(1));
      expect(find.text('Thanks. This comment was sent for review.'), findsOne);
    });

    testWidgets('the reason list stays reachable at 200% text scale', (
      tester,
    ) async {
      final harness = reportHarness();
      await _pumpThread(
        tester,
        harness,
        size: const Size(320, 568),
        textScale: 2,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-report-c1')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Self-harm is the reason a distressed reporter needs most and the one
      // furthest down the list. At this scale it starts below the fold, so
      // the sheet has to be able to bring it into view rather than clip it.
      final selfHarm = find.byKey(
        const ValueKey<String>('reel-comment-report-reason-selfHarm'),
      );
      expect(selfHarm, findsOneWidget);
      expect(
        tester.getRect(selfHarm).bottom,
        greaterThan(tester.view.physicalSize.height),
        reason: 'fixture no longer places selfHarm below the fold',
      );
      await tester.ensureVisible(selfHarm);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(selfHarm).bottom,
        lessThanOrEqualTo(tester.view.physicalSize.height),
      );

      await tester.tap(selfHarm);
      await tester.pumpAndSettle();
      final submit = find.byKey(
        const ValueKey<String>('reel-comment-report-submit'),
      );
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(
        harness.callsTo('createReelCommentReport').single.payload['reason'],
        'selfHarm',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group("a Reel author removing somebody else's comment", () {
    _Harness removeHarness({
      Future<Map<Object?, Object?>> Function(Map<String, Object?>)? onRemove,
    }) {
      final harness = _Harness();
      var removed = false;
      harness.responders['getReelViewV2'] = (_) async => _view(
        <Map<String, Object?>>[
          _commentWire('c1', text: 'Kept.'),
          if (!removed) _commentWire('c2', text: 'Cleared.'),
        ],
        commentCount: removed ? 1 : 2,
        reelAuthorId: _viewer,
      );
      harness.responders['removeReelComment'] =
          onRemove ??
          (_) async {
            removed = true;
            return <Object?, Object?>{
              'reelId': 'reel_1',
              'commentId': 'c2',
              'removed': true,
              'commentCount': 1,
              'removedAuthorId': _otherAuthor,
            };
          };
      harness.responders['createReelCommentReport'] = (_) async => _reportOk();
      return harness;
    }

    Future<void> pumpOwnReel(WidgetTester tester, _Harness harness) =>
        _pumpThread(
          tester,
          harness,
          reel: _reel(commentCount: 2, authorId: _viewer),
        );

    testWidgets('a viewer who does not own the Reel is offered no Remove', (
      tester,
    ) async {
      final harness = _Harness();
      harness.responders['getReelViewV2'] = (_) async =>
          _view(<Map<String, Object?>>[_commentWire('c1')]);
      await _pumpThread(tester, harness);

      // Report, yes. Remove, no — and no menu to hide it in either.
      expect(
        find.byKey(const ValueKey<String>('reel-comment-report-c1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('reel-comment-actions-c1')),
        findsNothing,
      );
      expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    });

    testWidgets('the Reel author gets both Report and Remove in one menu', (
      tester,
    ) async {
      await pumpOwnReel(tester, removeHarness());

      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-actions-c2')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Report comment'), findsOneWidget);
      expect(find.text('Remove from my Reel'), findsOneWidget);
    });

    testWidgets('cancelling the confirmation keeps the comment', (
      tester,
    ) async {
      final harness = removeHarness();
      await pumpOwnReel(tester, harness);

      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-actions-c2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-remove-c2')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Remove this comment?'), findsOneWidget);
      // The dialog says whose words these are and that nothing undoes it.
      expect(
        find.textContaining("Other Person's comment will be removed"),
        findsOneWidget,
      );
      expect(find.textContaining('cannot be undone'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-remove-cancel')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cleared.'), findsOneWidget);
      expect(harness.callsTo('removeReelComment'), isEmpty);
    });

    testWidgets('confirming removes it and adopts the returned count', (
      tester,
    ) async {
      final harness = removeHarness();
      await pumpOwnReel(tester, harness);

      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-actions-c2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-remove-c2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-remove-confirm')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cleared.'), findsNothing);
      expect(find.text('Kept.'), findsOneWidget);
      expect(find.text('Comment removed.'), findsOneWidget);

      final call = harness.callsTo('removeReelComment').single;
      expect(call.payload['reelId'], 'reel_1');
      expect(call.payload['commentId'], 'c2');
      expect(call.payload['requestId'], isA<String>());
      // The server's count is adopted verbatim, not decremented locally.
      expect(harness.updates.last.commentCount, 1);
    });

    testWidgets('a refused removal leaves the comment and says why', (
      tester,
    ) async {
      final harness = removeHarness(
        onRemove: (_) async => throw _refusal('resource-exhausted'),
      );
      await pumpOwnReel(tester, harness);

      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-actions-c2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-remove-c2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-remove-confirm')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cleared.'), findsOneWidget);
      expect(
        find.text(
          'You have removed several comments recently. '
          'Try again in a few minutes.',
        ),
        findsOneWidget,
      );
      expect(harness.updates.last.commentCount, 2);
    });

    testWidgets('a permission-denied is the server\'s to say, not predicted', (
      tester,
    ) async {
      final harness = removeHarness(
        onRemove: (_) async => throw _refusal('permission-denied'),
      );
      await pumpOwnReel(tester, harness);

      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-actions-c2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-remove-c2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-remove-confirm')),
      );
      await tester.pumpAndSettle();

      // One refusal envelope, never branched into a reason the client made up.
      expect(find.text('That comment is no longer available.'), findsOneWidget);
      expect(find.text('Cleared.'), findsOneWidget);
    });

    testWidgets('the author\'s own comment is a Delete, not a Remove', (
      tester,
    ) async {
      final harness = _Harness();
      harness.responders['getReelViewV2'] = (_) async =>
          _view(<Map<String, Object?>>[
            _commentWire(
              'c1',
              authorId: _viewer,
              authorName: 'You',
              text: 'Mine.',
            ),
          ], reelAuthorId: _viewer);
      await _pumpThread(
        tester,
        harness,
        reel: _reel(commentCount: 1, authorId: _viewer),
      );

      expect(
        find.byKey(const ValueKey<String>('reel-comment-delete-c1')),
        findsOneWidget,
      );
      // Two destructive controls for one intent would split the trace an
      // accountability review depends on.
      expect(
        find.byKey(const ValueKey<String>('reel-comment-actions-c1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('reel-comment-report-c1')),
        findsNothing,
      );
    });
  });

  group('the report sheet on its own', () {
    testWidgets('returns the reason and the trimmed note', (tester) async {
      ReelCommentReportRequest? captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<Object?>>[
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (context) => Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      captured = await showReelCommentReportSheet(
                        context,
                        authorName: 'Other Person',
                        commentText: 'Their words.',
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The reporter sees exactly which words they are about to name.
      expect(
        find.byKey(const ValueKey<String>('reel-comment-report-target')),
        findsOneWidget,
      );
      expect(find.text('Their words.'), findsOneWidget);
      // A short, fixed heading with the author attached to the quote, not a
      // heading that grows with the name: at 200% on a 320 px window the
      // long form pushed every reason below the fold.
      expect(find.text('Report this comment'), findsOneWidget);
      expect(find.text('Other Person'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey<String>('reel-comment-report-reason-violence'),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('reel-comment-report-note')),
        '   context   ',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-report-submit')),
      );
      await tester.pumpAndSettle();

      expect(captured?.reason, ReportReason.violence);
      expect(captured?.note, 'context');
      expect(captured?.wireReason, 'violence');
    });

    testWidgets('offers exactly the eight reasons the backend accepts', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<Object?>>[
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(
            body: ReelCommentReportSheet(
              authorName: 'Other Person',
              commentText: 'Their words.',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(reelReportReasons, hasLength(8));
      for (final reason in ReportReason.values) {
        expect(
          find.byKey(
            ValueKey<String>('reel-comment-report-reason-${reason.name}'),
          ),
          findsOneWidget,
          reason: 'missing reason tile for ${reason.name}',
        );
        // Every enum name is a value `validateReelReportReason` accepts, so
        // no tile can send something the callable rejects.
        expect(reelReportReasons, contains(reason.name));
      }
    });
  });
}
