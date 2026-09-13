import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/moderation/data/models/moderation_audit_event.dart';
import 'package:yovoice/features/moderation/data/models/moderation_report.dart';
import 'package:yovoice/features/moderation/data/services/moderation_service.dart';
import 'package:yovoice/features/moderation/presentation/screens/moderation_center_screen.dart';

/// A report on a Reel VOICE comment, as staff see it.
///
/// `createReelCommentReport` stamps `targetCommentType`,
/// `targetDurationSeconds`, `targetStoragePath` and `targetMediaGeneration`
/// onto a voice report, and its `targetTextSnapshot` is only the recording's
/// optional caption. Before this suite the Moderation Center read none of
/// those fields, so a voice comment posted without a caption reached staff as
/// "the reported text was not retained" — a false statement about evidence
/// that was never words. Pinned here: the queue and the detail panel name the
/// target as a recording with its length, an empty caption reads as an empty
/// caption, a missing one as missing, and a text report is unchanged.
void main() {
  const mod = 'mod-uid';
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  MockFirebaseAuth moderatorAuth() => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(
      uid: mod,
      email: '$mod@yovoice.app',
      displayName: 'Tester',
      customClaim: const {'role': 'moderator'},
    ),
  );

  Future<void> seedModerator() => db.collection('users').doc(mod).set({
    'uid': mod,
    'displayName': mod,
    'role': 'moderator',
  });

  /// The exact document `createReelCommentReport` writes, with the voice
  /// fields switchable so the same seed covers text, voice and legacy.
  Future<void> seedReelCommentReport({
    String id = 'reel-comment-report',
    Object? commentType = 'voice',
    Object? durationSeconds = 42,
    Object? caption = '',
    bool includeVoiceFields = true,
    String reason = 'harassment',
  }) async {
    await db.collection('reports').doc(id).set({
      'schemaVersion': 2,
      'reporterId': 'reporter-uid',
      'targetType': 'reelComment',
      'targetId': 'comment-1',
      'reportedUserId': 'commenter-uid',
      'contextPath': 'reels/reel-1/comments/comment-1',
      'reelId': 'reel-1',
      'commentId': 'comment-1',
      'reelAuthorId': 'reel-author-uid',
      'targetTextSnapshot': caption,
      if (includeVoiceFields) ...{
        'targetCommentType': commentType,
        'targetDurationSeconds': durationSeconds,
        'targetStoragePath': commentType == 'voice'
            ? 'reel_voice_comments/commenter-uid/reel-1/comment-1.m4a'
            : null,
        'targetMediaGeneration': commentType == 'voice' ? '900001' : null,
      },
      'note': '',
      'reason': reason,
      'status': 'open',
      'createdAt': Timestamp.now(),
    });
  }

  Future<ModerationReport> readReport([
    String id = 'reel-comment-report',
  ]) async => ModerationReport.fromFirestore(
    await db.collection('reports').doc(id).get(),
  );

  void useSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Widget host(
    Widget child, {
    Locale locale = const Locale('en'),
    double textScale = 1,
  }) => MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: app!,
    ),
    home: child,
  );

  Future<void> openCenter(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      host(
        ModerationCenterScreen(
          moderationService: _QuietAuditModerationService(
            firestore: db,
            auth: moderatorAuth(),
          ),
        ),
        locale: locale,
        textScale: textScale,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the report model reads the voice evidence', () {
    test('a voice report carries its type and its length', () async {
      await seedReelCommentReport(caption: 'listen to this');
      final report = await readReport();

      expect(report.targetCommentType, 'voice');
      expect(report.targetDurationSeconds, 42);
      expect(report.isReelVoiceComment, isTrue);
      expect(report.targetText, 'listen to this');
    });

    test(
      'a report filed before voice comments existed is a text report',
      () async {
        await seedReelCommentReport(
          includeVoiceFields: false,
          caption: 'the words',
        );
        final report = await readReport();

        expect(report.targetCommentType, isNull);
        expect(report.targetDurationSeconds, isNull);
        expect(report.isReelVoiceComment, isFalse);
        expect(report.targetText, 'the words');
      },
    );

    test('a length outside the 1-60 second contract is not evidence', () async {
      for (final (index, raw) in <Object?>[0, 61, 7.5, '42', null].indexed) {
        await seedReelCommentReport(id: 'bad-$index', durationSeconds: raw);
        final report = await readReport('bad-$index');
        expect(report.isReelVoiceComment, isTrue, reason: '$raw');
        expect(report.targetDurationSeconds, isNull, reason: '$raw');
      }
      await seedReelCommentReport(id: 'edge-1', durationSeconds: 1);
      await seedReelCommentReport(id: 'edge-60', durationSeconds: 60);
      expect((await readReport('edge-1')).targetDurationSeconds, 1);
      expect((await readReport('edge-60')).targetDurationSeconds, 60);
    });

    test(
      'only a Yeel comment report can be a Yeel voice comment report',
      () async {
        await db.collection('reports').doc('moment-reply').set({
          'targetType': 'voiceMomentComment',
          'targetCommentType': 'voice',
          'targetDurationSeconds': 12,
          'reportedUserId': 'someone',
          'status': 'open',
        });
        expect((await readReport('moment-reply')).isReelVoiceComment, isFalse);
      },
    );
  });

  group('the Moderation Center names a recording as a recording', () {
    testWidgets('an uncaptioned voice comment is named, timed and never '
        'called a missing snapshot', (tester) async {
      useSize(tester, const Size(1440, 1200));
      await seedModerator();
      await seedReelCommentReport();

      await openCenter(tester);

      // The queue row already says it is a recording.
      expect(find.text('Yeel comment · Voice comment · 0:42'), findsOneWidget);

      await tester.tap(
        find.bySemanticsLabel(RegExp(r'Harassment or bullying, Open')),
      );
      await tester.pumpAndSettle();

      final target = find.byKey(
        const ValueKey<String>('moderation-voice-comment-target'),
      );
      expect(target, findsOneWidget);
      expect(
        find.descendant(
          of: target,
          matching: find.text('Reported voice comment'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: target,
          matching: find.text('Voice comment · 0:42'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: target,
          matching: find.textContaining('cannot be played here yet'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('moderation-voice-comment-caption'),
          ),
          matching: find.text('No caption was posted with this recording.'),
        ),
        findsOneWidget,
      );
      expect(
        find.text('The reported text was not retained in this report.'),
        findsNothing,
      );
      expect(find.text('Reported comment'), findsNothing);
      // The target identity and the removal action are unchanged.
      expect(find.text('Reported Yeel comment'), findsOneWidget);
      expect(find.text('Remove Yeel comment and resolve'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a caption is quoted verbatim under the recording', (
      tester,
    ) async {
      useSize(tester, const Size(1440, 1200));
      await seedModerator();
      await seedReelCommentReport(durationSeconds: 60, caption: 'you know why');

      await openCenter(tester);
      await tester.tap(
        find.bySemanticsLabel(RegExp(r'Harassment or bullying, Open')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Voice comment · 1:00'), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('moderation-voice-comment-caption'),
          ),
          matching: find.text('you know why'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'a length the report did not retain prints a dash, not a clock',
      (tester) async {
        useSize(tester, const Size(1440, 1200));
        await seedModerator();
        await seedReelCommentReport(durationSeconds: 600, caption: null);

        await openCenter(tester);
        await tester.tap(
          find.bySemanticsLabel(RegExp(r'Harassment or bullying, Open')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Voice comment · —'), findsWidgets);
        expect(find.textContaining('10:00'), findsNothing);
        expect(
          find.text('The caption was not retained in this report.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a text Yeel comment report renders exactly as before', (
      tester,
    ) async {
      useSize(tester, const Size(1440, 1200));
      await seedModerator();
      await seedReelCommentReport(
        commentType: 'text',
        durationSeconds: null,
        caption: 'the reported words',
      );

      await openCenter(tester);
      expect(find.text('Yeel comment'), findsWidgets);
      expect(find.textContaining('Voice comment'), findsNothing);

      await tester.tap(
        find.bySemanticsLabel(RegExp(r'Harassment or bullying, Open')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reported comment'), findsOneWidget);
      expect(find.text('the reported words'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('moderation-voice-comment-target')),
        findsNothing,
      );
      expect(find.text('Remove Yeel comment and resolve'), findsOneWidget);
    });

    testWidgets('a pre-voice report with no type field stays a text report', (
      tester,
    ) async {
      useSize(tester, const Size(1440, 1200));
      await seedModerator();
      await seedReelCommentReport(
        includeVoiceFields: false,
        caption: 'legacy words',
      );

      await openCenter(tester);
      await tester.tap(
        find.bySemanticsLabel(RegExp(r'Harassment or bullying, Open')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reported comment'), findsOneWidget);
      expect(find.text('legacy words'), findsOneWidget);
      expect(find.textContaining('Voice comment'), findsNothing);
    });

    for (final (label, size) in const <(String, Size)>[
      ('narrow 320', Size(320, 900)),
      ('medium 768', Size(768, 1024)),
      ('wide 1440', Size(1440, 1200)),
    ]) {
      testWidgets('$label at 200% text keeps the voice evidence whole', (
        tester,
      ) async {
        useSize(tester, size);
        await seedModerator();
        await seedReelCommentReport(
          caption:
              'a caption long enough to wrap onto a second line at the '
              'narrowest width this panel is ever given',
        );

        await openCenter(tester, textScale: 2);
        final row = find.bySemanticsLabel(
          RegExp(r'Harassment or bullying, Open'),
        );
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pumpAndSettle();

        final target = find.byKey(
          const ValueKey<String>('moderation-voice-comment-target'),
        );
        final detailScroll = find
            .descendant(
              of: find.byKey(
                const ValueKey<String>('moderation-detail-scroll'),
              ),
              matching: find.byType(Scrollable),
            )
            .first;
        expect(detailScroll, findsOneWidget);
        await tester.scrollUntilVisible(target, 240, scrollable: detailScroll);
        await tester.pumpAndSettle();
        expect(target, findsOneWidget);
        expect(
          find.descendant(
            of: target,
            matching: find.text('Voice comment · 0:42'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Polish names the recording in Polish', (tester) async {
      useSize(tester, const Size(1440, 1200));
      await seedModerator();
      await seedReelCommentReport(durationSeconds: 7);

      await openCenter(tester, locale: const Locale('pl'));
      expect(
        find.text('Komentarz rolki · Komentarz głosowy · 0:07'),
        findsOneWidget,
      );
      await tester.tap(
        find.bySemanticsLabel(RegExp(r'Nękanie lub zastraszanie, Otwarte')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Zgłoszony komentarz głosowy'), findsOneWidget);
      expect(find.text('Do tego nagrania nie dodano podpisu.'), findsOneWidget);
      expect(find.textContaining('Nagrania nie można jeszcze'), findsOneWidget);
    });
  });
}

/// The audit trail is a callable; nothing here is about it.
class _QuietAuditModerationService extends ModerationService {
  _QuietAuditModerationService({
    required FakeFirebaseFirestore firestore,
    required MockFirebaseAuth auth,
  }) : super(firestore: firestore, auth: auth);

  @override
  Future<ModerationAuditPage> reportAuditTrail(
    String reportId, {
    int limit = ModerationService.auditPageSize,
    String? cursor,
  }) async => ModerationAuditPage.empty;
}
