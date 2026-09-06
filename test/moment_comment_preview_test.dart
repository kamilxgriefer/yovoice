// Inline comment previews and @-mentions on Voice Moments.
//
// The preview is built from comments the Moment view callable ALREADY
// returned — these tests seed a fake Firestore behind the same strict v2
// transport production parses, so nothing here can pass through an
// invented second read.
//
// Mentions are plain text inside the comment body: there is no mention
// field on the wire and no notification, so what is tested is exactly
// what ships — suggestion, insertion, and per-viewer resolution.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/offline_voice_moment_service.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_comments_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_detail_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_card.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_comment_preview.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_mention_composer.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_mentions.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'voice_moment_test_doubles.dart';

const _viewer = 'me';

VoiceMoment _moment({int comments = 0}) {
  final createdAt = DateTime.now().subtract(const Duration(hours: 2));
  return VoiceMoment(
    id: 'm1',
    authorId: 'nadia',
    authorName: 'Nadia Rutkowska',
    authorPhotoUrl: null,
    caption: 'The one thing nobody tells you.',
    audioUrl: 'https://cdn.example/m1.m4a',
    durationSeconds: 27,
    likeCount: 0,
    commentCount: comments,
    isPublished: true,
    createdAt: createdAt,
    expiresAt: createdAt.add(const Duration(hours: 24)),
    schemaVersion: 2,
    status: 'published',
    isDeleted: false,
  );
}

Map<String, dynamic> _momentDoc(VoiceMoment moment) => <String, dynamic>{
  'authorId': moment.authorId,
  'authorName': moment.authorName,
  'authorPhotoUrl': null,
  'caption': moment.caption,
  'audioUrl': moment.audioUrl,
  'durationSeconds': moment.durationSeconds,
  'likeCount': moment.likeCount,
  'commentCount': moment.commentCount,
  'isPublished': moment.isPublished,
  'createdAt': Timestamp.fromDate(moment.createdAt!),
  'expiresAt': Timestamp.fromDate(moment.expiresAt!),
  'schemaVersion': 2,
  'status': 'published',
  'isDeleted': false,
};

MomentComment _comment({
  required String id,
  String authorId = 'tomas',
  String authorName = 'Tomás Oliveira',
  String text = 'Real words from a real document.',
  String type = 'text',
  int durationSeconds = 0,
  int minutesAgo = 5,
}) => MomentComment(
  id: id,
  type: type,
  authorId: authorId,
  authorName: authorName,
  authorPhotoUrl: null,
  text: text,
  durationSeconds: durationSeconds,
  createdAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
  reportReceipt: fakeVoiceMomentReportReceipt,
);

class _SilentPlayer implements audio.AudioPlayer {
  @override
  Stream<Duration> get onPositionChanged => const Stream<Duration>.empty();

  @override
  Stream<Duration> get onDurationChanged => const Stream<Duration>.empty();

  @override
  Stream<void> get onPlayerComplete => const Stream<void>.empty();

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? ThemeData.dark(useMaterial3: true),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

FriendUser _friend(String id, String displayName) => FriendUser(
  id: id,
  displayName: displayName,
  email: '',
  photoUrl: null,
  isOnline: false,
  lastSeen: null,
);

void main() {
  late PublicIdentityRepository originalIdentity;

  setUp(() {
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _viewer)),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentity;
  });

  group('comment preview', () {
    testWidgets('renders the newest of the loaded comments, capped at the '
        'preview limit', (tester) async {
      await tester.pumpWidget(
        _host(
          MomentCommentPreview(
            comments: <MomentComment>[
              for (var index = 0; index < 5; index += 1)
                _comment(
                  id: 'c$index',
                  authorName: 'Author $index',
                  text: 'Comment $index',
                  minutesAgo: 50 - index,
                ),
            ],
            totalCommentCount: 5,
            onSeeAll: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Exactly three rows, and they are the newest three: the server
      // pages oldest-first, so the tail of the loaded page is newest.
      expect(
        find.byKey(const ValueKey('moment-comment-preview')),
        findsOneWidget,
      );
      expect(find.textContaining('Comment 0'), findsNothing);
      expect(find.textContaining('Comment 1'), findsNothing);
      expect(find.textContaining('Comment 2'), findsOneWidget);
      expect(find.textContaining('Comment 3'), findsOneWidget);
      expect(find.textContaining('Comment 4'), findsOneWidget);
      // The author's name shares the comment's single line.
      expect(find.text('Author 4'), findsOneWidget);
      expect(find.text('See all 5 comments'), findsOneWidget);
    });

    testWidgets('a preview row is one ellipsised line however long the '
        'comment is', (tester) async {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 320,
            child: MomentCommentPreview(
              comments: <MomentComment>[
                _comment(id: 'c1', text: 'word ' * 120),
              ],
              totalCommentCount: 1,
              onSeeAll: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rendered = tester.widget<Text>(
        find.descendant(
          of: find.byType(MentionText),
          matching: find.byType(Text),
        ),
      );
      expect(rendered.maxLines, 1);
      expect(rendered.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a voice comment shows a duration chip instead of text', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          MomentCommentPreview(
            comments: <MomentComment>[
              _comment(
                id: 'voice-1',
                type: 'voice',
                durationSeconds: 7,
                text: '',
              ),
            ],
            totalCommentCount: 1,
            onSeeAll: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('moment-comment-preview-voice-voice-1')),
        findsOneWidget,
      );
      expect(find.text('0:07'), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      // One comment: the row names it rather than pluralising wrongly.
      expect(find.text('See the comment'), findsOneWidget);
    });

    testWidgets('the empty state is a single affordance that opens the '
        'composer', (tester) async {
      var composed = 0;
      await tester.pumpWidget(
        _host(
          MomentCommentPreview(
            comments: const <MomentComment>[],
            totalCommentCount: 0,
            onSeeAll: () {},
            onCompose: () => composed += 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final affordance = find.byKey(
        const ValueKey('moment-comment-preview-empty'),
      );
      expect(affordance, findsOneWidget);
      expect(find.text('Be the first to comment'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('moment-comment-preview-see-all')),
        findsNothing,
      );

      await tester.tap(affordance);
      await tester.pumpAndSettle();
      expect(composed, 1);
    });

    testWidgets('with no composer to open the empty state states the fact '
        'and offers nothing', (tester) async {
      await tester.pumpWidget(
        _host(
          MomentCommentPreview(
            comments: const <MomentComment>[],
            totalCommentCount: 0,
            onSeeAll: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No comments yet'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('the card renders a preview only when a host hands it '
        'comments it already loaded', (tester) async {
      final moment = _moment(comments: 2);
      await tester.pumpWidget(
        _host(
          MomentCard(
            moment: moment,
            onComments: () {},
            offlineService: _StubOfflineService(),
            mediaUriResolver: (_) async => Uri.parse('https://cdn/x.m4a'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('moment-comment-preview')),
        findsNothing,
      );

      await tester.pumpWidget(
        _host(
          MomentCard(
            moment: moment,
            onComments: () {},
            offlineService: _StubOfflineService(),
            mediaUriResolver: (_) async => Uri.parse('https://cdn/x.m4a'),
            commentPreview: <MomentComment>[
              _comment(id: 'c1', text: 'Loaded by the host, not refetched.'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('moment-comment-preview')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Loaded by the host, not refetched.'),
        findsOneWidget,
      );
    });
  });

  group('moment detail', () {
    ({FakeFirebaseFirestore db, MomentService moments, HomeFeedService feed})
    services() {
      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: _viewer),
      );
      return (
        db: db,
        moments: MomentService(
          firestore: db,
          auth: auth,
          storage: MockFirebaseStorage(),
          readService: VoiceMomentReadService(
            viewInvoker: fakeVoiceMomentViewInvoker(firestore: db),
          ),
        ),
        feed: HomeFeedService(firestore: db, auth: auth),
      );
    }

    Future<void> seedComments(
      FakeFirebaseFirestore db,
      int count, {
      String authorName = 'Tomás Oliveira',
    }) async {
      final momentRef = db.collection('voiceMoments').doc('m1');
      for (var index = 0; index < count; index += 1) {
        await momentRef.collection('comments').doc('comment_$index').set({
          'schemaVersion': 2,
          'type': 'text',
          'authorId': 'author_$index',
          'authorName': '$authorName $index',
          'authorPhotoUrl': null,
          'text': 'Comment $index',
          'durationSeconds': null,
          'createdAt': Timestamp.fromMillisecondsSinceEpoch(
            1800000000000 + index,
          ),
        });
      }
    }

    Future<void> pumpDetail(
      WidgetTester tester, {
      required VoiceMoment moment,
      required MomentService moments,
      required HomeFeedService feed,
      Stream<List<FriendUser>>? friends,
      Size size = const Size(390, 844),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: MomentDetailScreen(
            moment: moment,
            momentService: moments,
            feedService: feed,
            auth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: _viewer),
            ),
            mentionFriendsStream: friends ?? const Stream<List<FriendUser>>.empty(),
            playerFactory: _SilentPlayer.new,
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    testWidgets('shows a capped preview and "see all" opens the full '
        'thread', (tester) async {
      final s = services();
      final moment = _moment(comments: 9);
      await s.db.collection('voiceMoments').doc('m1').set(_momentDoc(moment));
      await seedComments(s.db, 9);

      await pumpDetail(
        tester,
        moment: moment,
        moments: s.moments,
        feed: s.feed,
      );

      // The view returns the first page (7); the preview shows the last
      // three of it and never the whole page.
      expect(find.text('Comments (9)'), findsOneWidget);
      expect(find.textContaining('Comment 6'), findsOneWidget);
      expect(find.textContaining('Comment 0'), findsNothing);

      final seeAll = find.byKey(
        const ValueKey('moment-comment-preview-see-all'),
      );
      await tester.scrollUntilVisible(
        seeAll,
        180,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('moment-detail-scroll')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('See all 9 comments'), findsOneWidget);

      await tester.tap(seeAll.hitTestable());
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(
        find.byKey(const ValueKey('moment-comments-screen')),
        findsOneWidget,
      );
      // Every comment lives there, with its pagination intact.
      expect(find.text('Comment 0'), findsOneWidget);
      final loadMore = find.byKey(
        const ValueKey('moment-comments-page-load-more'),
      );
      await tester.scrollUntilVisible(
        loadMore,
        180,
        // The thread's own list, not the composer's internal scroller.
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(loadMore, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no comments yet: the preview offers the composer', (
      tester,
    ) async {
      final s = services();
      final moment = _moment();
      await s.db.collection('voiceMoments').doc('m1').set(_momentDoc(moment));

      await pumpDetail(
        tester,
        moment: moment,
        moments: s.moments,
        feed: s.feed,
      );

      expect(find.text('Be the first to comment'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('moment-comment-preview-empty')),
      );
      await tester.pump();
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('moment-detail-comment-field')),
      );
      expect(field.focusNode?.hasFocus, isTrue);
    });

    testWidgets('typing @ad filters the composer to a matching friend and '
        'picking one inserts plain text', (tester) async {
      final s = services();
      final moment = _moment();
      await s.db.collection('voiceMoments').doc('m1').set(_momentDoc(moment));

      await pumpDetail(
        tester,
        moment: moment,
        moments: s.moments,
        feed: s.feed,
        friends: Stream<List<FriendUser>>.value(<FriendUser>[
          _friend('u-ada', 'Ada Lovelace'),
          _friend('u-marek', 'Marek Nowak'),
        ]),
      );

      await tester.enterText(
        find.byKey(const ValueKey('moment-detail-comment-field')),
        'thanks @ad',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('moment-mention-suggestions')),
        findsOneWidget,
      );
      expect(find.text('Ada Lovelace'), findsOneWidget);
      // Filtered, not a directory listing.
      expect(find.text('Marek Nowak'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('moment-mention-option-u-ada')),
      );
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('moment-detail-comment-field')),
      );
      expect(field.controller!.text, 'thanks @Ada Lovelace ');
      expect(
        find.byKey(const ValueKey('moment-mention-suggestions')),
        findsNothing,
      );

      // The caret is still inside the completed run. A later rebuild —
      // the friends stream, a refresh, anything — must not re-offer the
      // name that was just inserted.
      await tester.tap(find.byKey(const ValueKey('moment-detail-like')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('moment-mention-suggestions')),
        findsNothing,
      );

      // Editing the run brings the picker back.
      await tester.enterText(
        find.byKey(const ValueKey('moment-detail-comment-field')),
        'thanks @ada',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('moment-mention-suggestions')),
        findsOneWidget,
      );
    });

    testWidgets('with no friends the composer never opens a picker', (
      tester,
    ) async {
      final s = services();
      final moment = _moment();
      await s.db.collection('voiceMoments').doc('m1').set(_momentDoc(moment));

      await pumpDetail(
        tester,
        moment: moment,
        moments: s.moments,
        feed: s.feed,
        friends: Stream<List<FriendUser>>.value(const <FriendUser>[]),
      );

      await tester.enterText(
        find.byKey(const ValueKey('moment-detail-comment-field')),
        'hello @a',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('moment-mention-suggestions')),
        findsNothing,
      );
    });
  });

  group('mention rendering', () {
    testWidgets('a resolvable mention is tinted and tappable; an '
        'unresolvable one stays plain text', (tester) async {
      final opened = <String>[];
      final directory = MentionDirectory(<MentionCandidate>[
        MentionCandidate(userId: 'u-ada', displayName: 'Ada Lovelace'),
      ]);

      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => MentionText(
              text: '@Ada Lovelace and @Nobody Here too',
              directory: directory,
              style: TextStyle(color: context.appPalette.textSecondary),
              onMentionTap: (candidate) => opened.add(candidate.userId),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final richText = tester.widget<RichText>(find.byType(RichText).first);
      final spans = <TextSpan>[];
      richText.text.visitChildren((span) {
        if (span is TextSpan) spans.add(span);
        return true;
      });
      final interactive = tester
          .element(find.byType(MentionText))
          .findAncestorWidgetOfExactType<MaterialApp>();
      expect(interactive, isNotNull);

      final mentionSpan = spans.singleWhere(
        (span) => span.text == '@Ada Lovelace',
      );
      expect(mentionSpan.recognizer, isNotNull);
      expect(mentionSpan.style?.fontWeight, FontWeight.w700);

      // Nothing resolves "@Nobody Here": it is carried inside an ordinary
      // run with no recognizer of its own.
      expect(
        spans.where((span) => span.text?.contains('@Nobody Here') ?? false),
        hasLength(1),
      );
      expect(
        spans
            .firstWhere((span) => span.text?.contains('@Nobody Here') ?? false)
            .recognizer,
        isNull,
      );

      // Tapped as a reader would: on the mention's own glyphs, which
      // start at the very left of the paragraph.
      final paragraph = tester.getRect(find.byType(RichText).first);
      await tester.tapAt(Offset(paragraph.left + 10, paragraph.top + 8));
      await tester.pumpAndSettle();
      expect(opened, <String>['u-ada']);
    });

    testWidgets('the comments screen resolves mentions against the '
        "thread's own participants", (tester) async {
      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: _viewer),
      );
      final moment = _moment(comments: 2);
      await db.collection('voiceMoments').doc('m1').set(_momentDoc(moment));
      final comments = db
          .collection('voiceMoments')
          .doc('m1')
          .collection('comments');
      await comments.doc('c1').set({
        'schemaVersion': 2,
        'type': 'text',
        'authorId': 'u-ada',
        'authorName': 'Ada Lovelace',
        'authorPhotoUrl': null,
        'text': 'I was here first.',
        'durationSeconds': null,
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(1800000000000),
      });
      await comments.doc('c2').set({
        'schemaVersion': 2,
        'type': 'text',
        'authorId': 'u-marek',
        'authorName': 'Marek Nowak',
        'authorPhotoUrl': null,
        'text': 'agreed @Ada Lovelace, and @Ghost Writer disagrees',
        'durationSeconds': null,
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(1800000000001),
      });

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: MomentCommentsScreen(
            moment: moment,
            auth: auth,
            momentService: MomentService(
              firestore: db,
              auth: auth,
              storage: MockFirebaseStorage(),
              readService: VoiceMomentReadService(
                viewInvoker: fakeVoiceMomentViewInvoker(firestore: db),
              ),
            ),
            mentionFriendsStream: const Stream<List<FriendUser>>.empty(),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      final card = find.byKey(const ValueKey('moment-comment-card-c2'));
      expect(card, findsOneWidget);
      final richText = tester.widget<RichText>(
        find
            .descendant(
              of: card,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is RichText &&
                    (widget.text.toPlainText()).contains('@Ada Lovelace'),
              ),
            )
            .first,
      );
      final spans = <TextSpan>[];
      richText.text.visitChildren((span) {
        if (span is TextSpan) spans.add(span);
        return true;
      });
      expect(
        spans.singleWhere((span) => span.text == '@Ada Lovelace').recognizer,
        isNotNull,
      );
      expect(
        spans.any(
          (span) => span.text == '@Ghost Writer' && span.recognizer != null,
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('mention text mechanics', () {
    final directory = MentionDirectory(<MentionCandidate>[
      MentionCandidate(userId: 'u-ada', displayName: 'Ada'),
      MentionCandidate(userId: 'u-ada-l', displayName: 'Ada Lovelace'),
    ]);

    test('the longest known name wins', () {
      final segments = splitMentions('hi @Ada Lovelace', directory);
      expect(segments.last.text, '@Ada Lovelace');
      expect(segments.last.candidate?.userId, 'u-ada-l');
    });

    test('a name inside a longer word is not a mention', () {
      final segments = splitMentions('hi @Adamska', directory);
      expect(segments.single.isMention, isFalse);
    });

    test('an email address is never a mention', () {
      final segments = splitMentions('write to me@Ada', directory);
      expect(segments.every((segment) => !segment.isMention), isTrue);
    });

    test('the active query is the run after the last @', () {
      final query = mentionQueryAt('thanks @ad', 10);
      expect(query?.prefix, 'ad');
      expect(query?.start, 7);
      expect(mentionQueryAt('no mention here', 8), isNull);
      expect(mentionQueryAt('mail me@x', 9), isNull);
    });

    test('applying a mention inserts plain text and a trailing space', () {
      final query = mentionQueryAt('thanks @ad', 10)!;
      final result = applyMention(
        'thanks @ad',
        query,
        MentionCandidate(userId: 'u-ada-l', displayName: 'Ada Lovelace'),
      );
      expect(result.text, 'thanks @Ada Lovelace ');
      expect(result.selection, result.text.length);
    });

    test('suggestions match any word of a friend\'s name', () {
      expect(
        directory.suggest('lovel').map((candidate) => candidate.userId),
        <String>['u-ada-l'],
      );
      expect(directory.suggest('zz'), isEmpty);
    });
  });
}

class _StubOfflineService implements OfflineVoiceMomentService {
  @override
  Future<bool> isDownloaded(String momentId) async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
