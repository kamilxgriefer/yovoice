// Premium Pages C4: the composer A "arkusz" (image metadata stripping,
// 60 s voice), the post detail A "karta + wątek", full-download voice
// playback, the likers target, the notification arms and the Pages upsell
// (spec premium-pages §2.4-§2.6, §4.5, §6.3; renders R3, R11).
import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart' show Amplitude;

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/likers/data/models/likers_target.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_media_fullscreen_viewer.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_voice_playback_source.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/presentation/notification_router.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/services/image_sanitizer.dart';
import 'package:yovoice/features/pages/data/services/page_post_events.dart';
import 'package:yovoice/features/pages/data/services/page_post_publisher.dart';
import 'package:yovoice/features/pages/data/services/page_voice_player.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/page_notice_copy.dart';
import 'package:yovoice/features/pages/presentation/screens/page_composer.dart';
import 'package:yovoice/features/pages/presentation/screens/page_post_detail_screen.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_post_card.dart';
import 'package:yovoice/features/pages/presentation/widgets/pages_upsell_sheet.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

// ---------------------------------------------------------------- fixtures

final DateTime _now = DateTime.utc(2026, 9, 28, 12);

String _postId(int n) => 'pp_${n.toRadixString(16).padLeft(40, '0')}';
String _mediaId(int n) => 'pm_${n.toRadixString(16).padLeft(40, '0')}';
String _commentId(int n) => 'pc_${n.toRadixString(16).padLeft(40, '0')}';

Map<String, Object?> _post(
  int n, {
  String pageId = 'cafe',
  String kind = 'text',
  List<Map<String, Object?>> media = const [],
  int likes = 48,
  int comments = 12,
  bool commentsEnabled = true,
  bool liked = false,
  String text = 'Jesień weszła do karty. Długa 14, otwarte do 20:00.',
}) => {
  'postId': _postId(n),
  'pageId': pageId,
  'pageName': 'Kawiarnia Pod Lipą',
  'pageKind': 'business',
  'kind': kind,
  'text': text,
  'media': media,
  'createdAtMs': _now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
  'likeCount': likes,
  'commentCount': comments,
  'callerLiked': liked,
  'commentsEnabled': commentsEnabled,
  'state': 'published',
  'pinned': false,
};

Map<String, Object?> _voice(int n, {int ms = 42000}) => {
  'mediaId': _mediaId(n),
  'type': 'audio',
  'contentType': 'audio/mp4',
  'width': null,
  'height': null,
  'durationMs': ms,
};

Map<String, Object?> _comment(
  int n, {
  String author = 'ola',
  String name = 'Ola Wiśniewska',
  bool own = false,
  String text = 'Byłam wczoraj, szarlotka jest obłędna.',
  Duration age = const Duration(hours: 1),
}) => {
  'commentId': _commentId(n),
  'authorId': author,
  'authorName': name,
  'text': text,
  'createdAtMs': _now.subtract(age).millisecondsSinceEpoch,
  'isOwnPage': own,
};

Map<String, Object?> _detail(
  Map<String, Object?> post, {
  List<Map<String, Object?>> comments = const [],
  String? next,
}) => {
  'schemaVersion': 1,
  'post': post,
  'comments': comments,
  'nextCommentCursor': next,
  'hasMoreComments': next != null,
};

FirebaseFunctionsException _refusal(String code, [String? reason]) =>
    FirebaseFunctionsException(
      code: code,
      message: 'refused',
      details: reason == null ? null : {'reason': reason},
    );

class _Backend {
  _Backend(this.handlers);

  final Map<String, FutureOr<Object?> Function(Map<String, Object?>)> handlers;
  final List<(String, Map<String, Object?>)> calls = [];

  Future<Object?> call(String name, Map<String, Object?> payload) async {
    calls.add((name, payload));
    final handler = handlers[name];
    if (handler == null) throw _refusal('not-found');
    return handler(payload);
  }

  List<Map<String, Object?>> payloadsOf(String name) => [
    for (final call in calls)
      if (call.$1 == name) call.$2,
  ];
}

int _requestSeq = 0;

PagesService _service(_Backend backend) => PagesService(
  invoker: backend.call,
  requestIdFactory: () =>
      'pg_test_request_${(++_requestSeq).toString().padLeft(4, '0')}',
  clock: () => _now,
);

Uint8List _jpeg({int width = 8, int height = 6}) => Uint8List.fromList(
  img.encodeJpg(
    img.Image(width: width, height: height)..clear(img.ColorRgb8(120, 80, 40)),
  ),
);

Widget _app(Widget child, {Locale locale = const Locale('pl')}) => MaterialApp(
  theme: AppTheme.darkTheme,
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: child,
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
  double textScale = 1,
  Locale locale = const Locale('pl'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _app(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child,
      ),
      locale: locale,
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _FakeAudio extends RecordedAudio {
  _FakeAudio(this.size);

  final int size;
  bool discarded = false;

  @override
  String get contentType => 'audio/mp4';

  @override
  int get byteLength => size;

  @override
  Future<String> uploadTo(
    Reference reference,
    SettableMetadata metadata,
  ) async => '1';

  @override
  Future<void> discard() async => discarded = true;
}

class _FakeVoiceAudio implements PageVoiceAudio {
  final StreamController<Duration> positionsController =
      StreamController<Duration>.broadcast();
  final StreamController<void> completionsController =
      StreamController<void>.broadcast();
  final List<String> log = [];

  @override
  Stream<Duration> get positions => positionsController.stream;

  @override
  Stream<void> get completions => completionsController.stream;

  @override
  Future<void> play(Source source) async => log.add('play');

  @override
  Future<void> pause() async => log.add('pause');

  @override
  Future<void> resume() async => log.add('resume');

  @override
  Future<void> stop() async => log.add('stop');

  @override
  Future<void> dispose() async {}
}

Map<String, Object?> _grants(Map<String, Object?> payload) => {
  'grants': [
    for (final id in payload['mediaIds']! as List)
      {
        'mediaId': id,
        'url':
            'https://storage.example/$id?sig=${DateTime.now().microsecondsSinceEpoch}',
        'expiresAtMs': _now
            .add(const Duration(seconds: 90))
            .millisecondsSinceEpoch,
      },
  ],
};

/// Opens the composer from a button and keeps what it returned.
class _ComposerHost extends StatefulWidget {
  const _ComposerHost({required this.open});

  final Future<PagePostView?> Function(BuildContext context) open;

  @override
  State<_ComposerHost> createState() => _ComposerHostState();
}

class _ComposerHostState extends State<_ComposerHost> {
  PagePostView? result;
  bool closed = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        key: const ValueKey('open-composer'),
        onPressed: () async {
          final post = await widget.open(context);
          setState(() {
            result = post;
            closed = true;
          });
        },
        child: const Text('open'),
      ),
    ),
  );
}

void main() {
  setUp(() {
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
      fetchOverride: (uids) async => {
        for (final uid in uids)
          uid: {'staffRole': 'user', 'isVip': true, 'page': 'business'},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  // ------------------------------------------------------------ sanitiser

  group('image sanitiser (§4.5, S-M4)', () {
    test('a GPS-tagged photo leaves with no APP1-APP15 or COM segment', () {
      final fixture = File(
        'test/fixtures/pages_photo_gps.jpg',
      ).readAsBytesSync();
      expect(
        jpegMetadataMarkers(fixture),
        contains(0xE1),
        reason: 'the fixture carries Exif (GPS)',
      );
      final clean = ImageSanitizer.sanitize(fixture);
      expect(jpegMetadataMarkers(clean.bytes), isEmpty);
      expect(clean.bytes[0], 0xFF);
      expect(clean.bytes[1], 0xD8);
      expect(clean.width, greaterThan(0));
      expect(clean.height, greaterThan(0));
    });

    test('the EXIF orientation is baked into the pixels', () {
      final source = img.Image(width: 40, height: 20)
        ..clear(img.ColorRgb8(10, 200, 30));
      source.exif.imageIfd.orientation = 6; // rotate 90° clockwise
      final bytes = Uint8List.fromList(img.encodeJpg(source));
      expect(jpegMetadataMarkers(bytes), contains(0xE1));
      final clean = ImageSanitizer.sanitize(bytes);
      expect(clean.width, 20);
      expect(clean.height, 40);
      expect(jpegMetadataMarkers(clean.bytes), isEmpty);
    });

    test('long edge at most 2048, PNG with alpha becomes a JPEG', () {
      final big = img.Image(width: 3000, height: 1000)
        ..clear(img.ColorRgb8(1, 2, 3));
      final clean = ImageSanitizer.sanitize(
        Uint8List.fromList(img.encodePng(big)),
      );
      expect(clean.width, ImageSanitizer.maxEdge);
      expect(clean.height, 683);
      expect(clean.bytes.sublist(0, 2), [0xFF, 0xD8]);

      final alpha = img.Image(width: 10, height: 10, numChannels: 4)
        ..clear(img.ColorRgba8(0, 0, 0, 0));
      final flat = ImageSanitizer.sanitize(
        Uint8List.fromList(img.encodePng(alpha)),
      );
      expect(jpegMetadataMarkers(flat.bytes), isEmpty);
    });

    test('bytes that are no image are refused', () {
      expect(
        () => ImageSanitizer.sanitize(Uint8List.fromList(List.filled(64, 7))),
        throwsA(isA<ImageSanitizerException>()),
      );
      expect(jpegMetadataMarkers(Uint8List.fromList([1, 2, 3])), [-1]);
    });
  });

  // ------------------------------------------------------------ wire

  group('wire contracts (§2.4-§2.6, §2.10)', () {
    test(
      'post detail: known keys required, unknown ignored, bad ids skipped',
      () {
        final page = PagePostDetailPage.fromWire({
          ..._detail(
            _post(1),
            comments: [
              {..._comment(1), 'v11': true},
              {..._comment(2), 'commentId': 'nope'},
            ],
            next: 'c1',
          ),
          'futureKey': 1,
        });
        expect(page.post.postId, _postId(1));
        expect(page.comments.single.commentId, _commentId(1));
        expect(page.hasMoreComments, isTrue);
        final missing = Map<String, Object?>.of(_comment(1))
          ..remove('isOwnPage');
        expect(
          () => PageCommentView.fromWire(missing),
          throwsA(isA<PagesContractException>()),
        );
      },
    );

    test(
      'reserve, publish, comment, delete, switch and report payloads',
      () async {
        final backend = _Backend({
          PagesService.reserveCallable: (_) => {
            'postId': _postId(7),
            'items': [
              {
                'mediaId': _mediaId(1),
                'storagePath': 'page_posts/me/${_postId(7)}/${_mediaId(1)}.jpg',
                'metadata': {
                  'yovoicePageId': 'me',
                  'yovoicePostId': _postId(7),
                  'yovoiceMediaId': _mediaId(1),
                  'yovoiceMediaType': 'image',
                },
                'expiresAt': 1,
              },
            ],
          },
          PagesService.publishCallable: (p) => {..._post(7, pageId: 'me')},
          PagesService.engagementCallable: (p) => p['op'] == 'comment'
              ? {
                  'schemaVersion': 1,
                  'op': 'comment',
                  'postId': p['postId'],
                  'comment': _comment(9, author: 'me'),
                  'commentCount': 13,
                }
              : {'schemaVersion': 1, 'op': p['op'], 'deleted': true},
          PagesService.managePostCallable: (p) => {
            'schemaVersion': 1,
            'op': p['op'],
            'postId': p['postId'],
            'deleted': false,
            'pinned': false,
            'commentsEnabled': p['commentsEnabled'],
          },
          PagesService.reportCallable: (_) => {
            'schemaVersion': 1,
            'reportId': 'r' * 40,
            'created': true,
          },
        });
        final service = _service(backend);
        final reservation = await service.reserveMedia(
          requestId: 'pg_reserve_000001',
          kind: PagePostKind.photo,
          items: const [
            PageMediaReserveItem.photo(size: 900, width: 8, height: 6),
          ],
        );
        expect(backend.payloadsOf(PagesService.reserveCallable).single, {
          'requestId': 'pg_reserve_000001',
          'kind': 'photo',
          'items': [
            {
              'index': 0,
              'contentType': 'image/jpeg',
              'size': 900,
              'width': 8,
              'height': 6,
              'durationMs': null,
            },
          ],
        });
        expect(reservation.slots.single.metadata['yovoicePostId'], _postId(7));

        await service.publishPost(
          requestId: 'pg_publish_00001',
          kind: PagePostKind.text,
          text: 'Hej',
          commentsEnabled: false,
          postId: _postId(7),
        );
        expect(backend.payloadsOf(PagesService.publishCallable).single, {
          'requestId': 'pg_publish_00001',
          'postId': null,
          'kind': 'text',
          'text': 'Hej',
          'mediaIds': <String>[],
          'commentsEnabled': false,
        });

        final result = await service.comment(
          _postId(7),
          'Super',
          requestId: 'pg_comment_0001',
        );
        expect(result.commentCount, 13);
        await service.deleteComment(_commentId(9));
        final engagement = backend.payloadsOf(PagesService.engagementCallable);
        expect(engagement[0], {
          'requestId': 'pg_comment_0001',
          'op': 'comment',
          'postId': _postId(7),
          'text': 'Super',
        });
        expect(engagement[1].keys.toSet(), {'requestId', 'op', 'commentId'});
        expect(engagement[1]['op'], 'deleteComment');

        final manage = await service.setCommentsEnabled(
          _postId(7),
          enabled: false,
        );
        expect(manage.commentsEnabled, isFalse);
        expect(
          backend
              .payloadsOf(PagesService.managePostCallable)
              .single
              .keys
              .toSet(),
          {'requestId', 'postId', 'op', 'commentsEnabled'},
        );

        await service.report(
          target: PageReportTarget.comment,
          pageId: 'cafe',
          postId: _postId(7),
          commentId: _commentId(9),
          reason: 'spam',
        );
        final report = backend.payloadsOf(PagesService.reportCallable).single;
        expect(report.keys.toSet(), {
          'requestId',
          'targetType',
          'pageId',
          'postId',
          'commentId',
          'reason',
          'note',
        });
        expect(report['targetType'], 'pagePostComment');
        expect(report['note'], isNull);
      },
    );

    test('refusal reasons map to failures', () {
      PagesFailure of(String reason, [String code = 'failed-precondition']) =>
          PagesService.failureFor(_refusal(code, reason));
      expect(of('pageCommentsOff'), PagesFailure.commentsOff);
      expect(of('commentLinks', 'invalid-argument'), PagesFailure.commentLinks);
      expect(of('pagePostBudget', 'resource-exhausted'), PagesFailure.budget);
      expect(of('pageMediaMetadata'), PagesFailure.mediaMetadata);
      expect(
        of('pageUploadInProgress', 'resource-exhausted'),
        PagesFailure.uploadInProgress,
      );
      expect(
        of('pageUploadExpired', 'deadline-exceeded'),
        PagesFailure.uploadExpired,
      );
      expect(of('pagePaused'), PagesFailure.paused);
      expect(of('pageReadOnly'), PagesFailure.readOnly);
    });

    test('likers target: listPagePostLikersV1 {postId, cursor?}', () {
      final target = PagePostLikersTarget(_postId(3));
      expect(target.callableName, 'listPagePostLikersV1');
      expect(target.payload(), {'postId': _postId(3)});
      expect(target.payload(cursor: 'c'), {
        'postId': _postId(3),
        'cursor': 'c',
      });
      expect(target.isReactions, isFalse);
      expect(target, PagePostLikersTarget(_postId(3)));
    });
  });

  // ------------------------------------------------------------ publisher

  group('publisher: sanitise → reserve → upload → publish (§4.5)', () {
    Map<String, Object?> reservation(int count) => {
      'postId': _postId(9),
      'items': [
        for (var i = 0; i < count; i++)
          {
            'mediaId': _mediaId(i + 1),
            'storagePath': 'page_posts/me/${_postId(9)}/${_mediaId(i + 1)}.jpg',
            'metadata': {
              'yovoicePageId': 'me',
              'yovoicePostId': _postId(9),
              'yovoiceMediaId': _mediaId(i + 1),
              'yovoiceMediaType': 'image',
            },
            'expiresAt': 1,
          },
      ],
    };

    test(
      'a failed upload retries only that object, on the same reservation',
      () async {
        final backend = _Backend({
          PagesService.reserveCallable: (_) => reservation(3),
          PagesService.publishCallable: (p) => {
            ..._post(
              9,
              pageId: 'me',
              kind: 'photo',
              media: [
                for (final id in p['mediaIds']! as List)
                  {
                    'mediaId': id,
                    'type': 'image',
                    'contentType': 'image/jpeg',
                    'width': 8,
                    'height': 6,
                    'durationMs': null,
                  },
              ],
            ),
          },
        });
        final uploads = <String>[];
        var failNext = {_mediaId(3)};
        final publisher = PagePostPublisher(
          service: _service(backend),
          uploader: (slot, payload, {required onProgress}) async {
            if (failNext.remove(slot.mediaId)) throw StateError('network');
            uploads.add(slot.mediaId);
            expect(payload.contentType, 'image/jpeg');
            onProgress(.5);
          },
        );
        addTearDown(publisher.dispose);
        final photos = [
          for (var i = 0; i < 3; i++)
            SanitizedJpeg(bytes: _jpeg(), width: 8, height: 6),
        ];
        await expectLater(
          publisher.publishPhotos(
            keys: [1, 2, 3],
            photos: photos,
            text: 'Nowa szarlotka',
            commentsEnabled: true,
          ),
          throwsA(isA<PageUploadException>()),
        );
        expect(publisher.states.last, PageUploadState.failed);
        expect(publisher.hasReservation, isTrue);

        // The owner removes photo 2 and retries: no new reservation, photo 3
        // is uploaded, and the publish names 1 and 3 only.
        final post = await publisher.publishPhotos(
          keys: [1, 3],
          photos: [photos[0], photos[2]],
          text: 'Nowa szarlotka',
          commentsEnabled: true,
        );
        expect(backend.payloadsOf(PagesService.reserveCallable), hasLength(1));
        expect(uploads, [_mediaId(1), _mediaId(2), _mediaId(3)]);
        final publish = backend.payloadsOf(PagesService.publishCallable).single;
        expect(publish['postId'], _postId(9));
        expect(publish['mediaIds'], [_mediaId(1), _mediaId(3)]);
        expect(publish['kind'], 'photo');
        expect(post.images, hasLength(2));
        expect(publisher.hasReservation, isFalse);
      },
    );

    test('a voice clip is declared 1-60 s and sent as audio/mp4', () async {
      final backend = _Backend({
        PagesService.reserveCallable: (_) => {
          'postId': _postId(4),
          'items': [
            {
              'mediaId': _mediaId(4),
              'storagePath': 'page_posts/me/${_postId(4)}/${_mediaId(4)}.m4a',
              'metadata': {
                'yovoicePageId': 'me',
                'yovoicePostId': _postId(4),
                'yovoiceMediaId': _mediaId(4),
                'yovoiceMediaType': 'audio',
              },
              'expiresAt': 1,
            },
          ],
        },
        PagesService.publishCallable: (_) => _post(
          4,
          pageId: 'me',
          kind: 'voice',
          media: [_voice(4, ms: 60000)],
        ),
      });
      final publisher = PagePostPublisher(
        service: _service(backend),
        uploader: (slot, payload, {required onProgress}) async {
          expect(payload, isA<PageVoicePayload>());
          expect(payload.contentType, 'audio/mp4');
        },
      );
      addTearDown(publisher.dispose);
      await publisher.publishVoice(
        key: 0,
        audio: _FakeAudio(960000),
        durationMs: 61500,
        text: '',
        commentsEnabled: true,
      );
      final item =
          (backend.payloadsOf(PagesService.reserveCallable).single['items']!
                      as List)
                  .single
              as Map;
      expect(item['contentType'], 'audio/mp4');
      expect(item['durationMs'], 60000);
      expect(item['width'], isNull);
    });
  });

  // ------------------------------------------------------------ voice player

  group('voice playback: full download (§4.5, P-M6)', () {
    test(
      'a 403 on an expired grant asks for one new grant and plays',
      () async {
        final backend = _Backend({PagesService.mediaAccessCallable: _grants});
        final audio = _FakeVoiceAudio();
        var downloads = 0;
        final player = PageVoicePlayer(
          service: _service(backend),
          audioFactory: () => audio,
          prepareSource: (bytes, id) async => PreparedDirectVoiceSource(
            source: BytesSource(bytes),
            dispose: () async {},
          ),
          downloader: (url) async {
            downloads++;
            if (downloads == 1) throw const PageVoiceDownloadException(403);
            return Uint8List.fromList(List.filled(2048, 1));
          },
        );
        addTearDown(player.dispose);
        final post = PagePostView.fromWire(
          _post(5, kind: 'voice', media: [_voice(5)]),
        )!;
        await player.toggle(post);
        expect(downloads, 2);
        expect(
          backend.payloadsOf(PagesService.mediaAccessCallable),
          hasLength(2),
        );
        expect(player.phaseOf(post.postId), PageVoicePhase.playing);
        expect(audio.log, contains('play'));

        await player.toggle(post);
        expect(player.phaseOf(post.postId), PageVoicePhase.paused);
        await player.toggle(post);
        expect(player.phaseOf(post.postId), PageVoicePhase.playing);
      },
    );

    test('one clip at a time: starting another stops the first', () async {
      final backend = _Backend({PagesService.mediaAccessCallable: _grants});
      final audio = _FakeVoiceAudio();
      final player = PageVoicePlayer(
        service: _service(backend),
        audioFactory: () => audio,
        prepareSource: (bytes, id) async => PreparedDirectVoiceSource(
          source: BytesSource(bytes),
          dispose: () async {},
        ),
        downloader: (url) async => Uint8List.fromList(List.filled(1024, 2)),
      );
      addTearDown(player.dispose);
      final a = PagePostView.fromWire(
        _post(6, kind: 'voice', media: [_voice(6)]),
      )!;
      final b = PagePostView.fromWire(
        _post(7, kind: 'voice', media: [_voice(7)]),
      )!;
      await player.toggle(a);
      await player.toggle(b);
      expect(player.activePostId, b.postId);
      expect(player.phaseOf(a.postId), PageVoicePhase.idle);
      expect(audio.log.where((e) => e == 'stop'), isNotEmpty);
    });
  });

  // ------------------------------------------------------------ composer

  group('composer A "arkusz" (R3)', () {
    Future<_ComposerHostState> openComposer(
      WidgetTester tester, {
      required _Backend backend,
      PagePostKind kind = PagePostKind.text,
      int publishedToday = 0,
      Size size = const Size(390, 844),
      double textScale = 1,
      PagePhotoPicker? pick,
      PageMediaUploader? uploader,
    }) async {
      // The sheet opens on the root navigator, above _pump's MediaQuery, so
      // the text size is set app-wide.
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final service = _service(backend);
      await _pump(
        tester,
        _ComposerHost(
          open: (context) => showPageComposer(
            context,
            owner: PageComposerOwner(
              pageId: 'me',
              name: 'Kawiarnia Pod Lipą',
              kind: PageKind.business,
              publishedToday: publishedToday,
            ),
            initialKind: kind,
            service: service,
            publisher: PagePostPublisher(
              service: service,
              uploader:
                  uploader ?? (slot, payload, {required onProgress}) async {},
            ),
            pickPhotos: pick,
            sanitize: (bytes) async =>
                SanitizedJpeg(bytes: _jpeg(), width: 8, height: 6),
            clock: () => _now,
          ),
        ),
        size: size,
        textScale: textScale,
      );
      await tester.tap(find.byKey(const ValueKey('open-composer')));
      await _settle(tester);
      return tester.state<_ComposerHostState>(find.byType(_ComposerHost));
    }

    testWidgets('text: publish sends the exact request and returns the post', (
      tester,
    ) async {
      final backend = _Backend({
        PagesService.publishCallable: (_) => _post(11, pageId: 'me'),
      });
      final host = await openComposer(tester, backend: backend);
      expect(find.text('Nowy post'), findsWidgets);
      // The segments keep their names (the test font's 1 em glyphs are too
      // wide for a label here, so the pill shows icons; real fonts fit).
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Tekst'), findsOneWidget);
      expect(find.bySemanticsLabel('Zdjęcia'), findsOneWidget);
      expect(find.bySemanticsLabel('Głos'), findsOneWidget);
      handle.dispose();
      expect(find.text('Komentarze włączone'), findsOneWidget);
      final publish = find.byKey(const ValueKey('page-composer-publish'));
      expect(tester.getSize(publish).height, greaterThanOrEqualTo(48));
      // At the default text size the text field is ready to type in.
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      await tester.enterText(
        find.byKey(const ValueKey('page-composer-text')),
        '  Od poniedziałku otwieramy o 7:00  ',
      );
      await tester.tap(find.byKey(const ValueKey('page-composer-comments')));
      await tester.pump();
      expect(find.text('Komentarze wyłączone'), findsOneWidget);
      await tester.tap(publish);
      await _settle(tester);
      expect(backend.payloadsOf(PagesService.publishCallable).single, {
        'requestId': isA<String>(),
        'postId': null,
        'kind': 'text',
        'text': 'Od poniedziałku otwieramy o 7:00',
        'mediaIds': <String>[],
        'commentsEnabled': false,
      });
      expect(host.result?.postId, _postId(11));
      expect(find.byKey(const ValueKey('page-composer')), findsNothing);
    });

    testWidgets('budget: refusal copy, and the line near the daily limit', (
      tester,
    ) async {
      final backend = _Backend({
        PagesService.publishCallable: (_) =>
            throw _refusal('resource-exhausted', 'pagePostBudget'),
      });
      await openComposer(tester, backend: backend, publishedToday: 8);
      expect(
        find.text('Dziś możesz opublikować jeszcze 2 posty.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('page-composer-text')),
        'Hej',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('page-composer-publish')));
      await _settle(tester);
      expect(
        find.text('Strona osiągnęła dzisiejszy limit postów. Spróbuj jutro.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('page-composer-retry')), findsNothing);
    });

    testWidgets('photos: review stage, no location, upload, publish', (
      tester,
    ) async {
      final backend = _Backend({
        PagesService.reserveCallable: (p) => {
          'postId': _postId(12),
          'items': [
            for (var i = 0; i < (p['items']! as List).length; i++)
              {
                'mediaId': _mediaId(i + 1),
                'storagePath':
                    'page_posts/me/${_postId(12)}/${_mediaId(i + 1)}.jpg',
                'metadata': {
                  'yovoicePageId': 'me',
                  'yovoicePostId': _postId(12),
                  'yovoiceMediaId': _mediaId(i + 1),
                  'yovoiceMediaType': 'image',
                },
                'expiresAt': 1,
              },
          ],
        },
        PagesService.publishCallable: (_) => _post(12, pageId: 'me'),
      });
      final uploaded = <String>[];
      await openComposer(
        tester,
        backend: backend,
        kind: PagePostKind.photo,
        pick: (remaining) async {
          expect(remaining, 10);
          return [
            XFile.fromData(_jpeg(), name: 'a.jpg'),
            XFile.fromData(_jpeg(), name: 'b.jpg'),
          ];
        },
        uploader: (slot, payload, {required onProgress}) async {
          uploaded.add(slot.mediaId);
          expect(slot.metadata['yovoiceMediaType'], 'image');
        },
      );
      await _settle(tester);
      expect(find.byKey(const ValueKey('page-composer-stage')), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('Bez lokalizacji'), findsOneWidget);
      expect(
        find.text(
          'Przed wysłaniem usuwamy ze zdjęć lokalizację i dane aparatu.',
        ),
        findsOneWidget,
      );
      expect(find.text('2/10'), findsOneWidget);
      // The remove target is 44 px although the visible dot is 24.
      expect(
        tester.getSize(find.byKey(const ValueKey('page-composer-remove-0'))),
        const Size(44, 44),
      );
      await tester.tap(find.byKey(const ValueKey('page-composer-publish')));
      await _settle(tester);
      final items =
          backend.payloadsOf(PagesService.reserveCallable).single['items']!
              as List;
      expect(items, hasLength(2));
      expect((items.first as Map)['contentType'], 'image/jpeg');
      expect(uploaded, [_mediaId(1), _mediaId(2)]);
      expect(
        backend.payloadsOf(PagesService.publishCallable).single['mediaIds'],
        [_mediaId(1), _mediaId(2)],
      );
    });

    testWidgets('pageMediaMetadata: the §5 copy with Ponów', (tester) async {
      final backend = _Backend({
        PagesService.reserveCallable: (_) => {
          'postId': _postId(13),
          'items': [
            {
              'mediaId': _mediaId(1),
              'storagePath': 'page_posts/me/${_postId(13)}/${_mediaId(1)}.jpg',
              'metadata': {
                'yovoicePageId': 'me',
                'yovoicePostId': _postId(13),
                'yovoiceMediaId': _mediaId(1),
                'yovoiceMediaType': 'image',
              },
              'expiresAt': 1,
            },
          ],
        },
        PagesService.publishCallable: (_) =>
            throw _refusal('failed-precondition', 'pageMediaMetadata'),
      });
      await openComposer(
        tester,
        backend: backend,
        kind: PagePostKind.photo,
        pick: (_) async => [XFile.fromData(_jpeg(), name: 'a.jpg')],
      );
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('page-composer-publish')));
      await _settle(tester);
      expect(
        find.text('Nie udało się przygotować zdjęcia. Spróbuj ponownie.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('page-composer-retry')), findsOneWidget);
    });

    testWidgets('close with a draft asks before discarding', (tester) async {
      final backend = _Backend({});
      final host = await openComposer(tester, backend: backend);
      await tester.enterText(
        find.byKey(const ValueKey('page-composer-text')),
        'Szkic',
      );
      await tester.tap(find.byTooltip('Zamknij: Nowy post'));
      await _settle(tester);
      expect(find.text('Odrzucić ten post?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('page-composer-discard')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('page-composer')), findsNothing);
      expect(host.result, isNull);
    });

    testWidgets('desktop: a 640 modal with the switch beside Opublikuj', (
      tester,
    ) async {
      await openComposer(
        tester,
        backend: _Backend({}),
        size: const Size(1440, 900),
      );
      final sheet = find.byKey(const ValueKey('page-composer'));
      expect(tester.getSize(sheet).width, 640);
      final publish = tester.getRect(
        find.byKey(const ValueKey('page-composer-publish')),
      );
      final toggle = tester.getRect(
        find.byKey(const ValueKey('page-composer-comments')),
      );
      expect((publish.center.dy - toggle.center.dy).abs(), lessThan(8));
      expect(
        find.byKey(const ValueKey('modal-sheet-drag-handle')),
        findsNothing,
      );
    });

    testWidgets('320 px at 200 %: lays out without overflow', (tester) async {
      await openComposer(
        tester,
        backend: _Backend({}),
        size: const Size(320, 640),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      // Large text opens at the top: no autofocus scrolls the title away.
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const ValueKey('page-composer-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scroll.position.pixels, 0);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('page-composer-kind-voice')));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Nagraj post głosowy'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------ detail

  group('post detail A "karta + wątek" (R3)', () {
    Widget detail(
      _Backend backend, {
      bool readOnly = false,
      String viewer = 'me',
      bool focus = false,
    }) => PagePostDetailScreen(
      postId: _postId(1),
      pageId: 'cafe',
      pageReadOnly: readOnly,
      focusComposer: focus,
      service: _service(backend),
      viewerId: viewer,
      viewerName: 'Aleksandra Nowak',
      player: PageVoicePlayer(service: _service(backend)),
      clock: () => _now,
    );

    testWidgets('card, "Komentarze" with count, Autor chip, send a comment', (
      tester,
    ) async {
      final events = <PagePostChange>[];
      final sub = PagePostEvents.instance.changes.listen(events.add);
      addTearDown(sub.cancel);
      final backend = _Backend({
        PagesService.postCallable: (_) => _detail(
          _post(1),
          comments: [
            _comment(
              2,
              author: 'cafe',
              name: 'Kawiarnia Pod Lipą',
              own: true,
              age: const Duration(minutes: 45),
            ),
            _comment(1),
          ],
        ),
        PagesService.engagementCallable: (p) => {
          'schemaVersion': 1,
          'op': 'comment',
          'postId': p['postId'],
          'comment': _comment(
            3,
            author: 'me',
            name: 'Aleksandra Nowak',
            text: p['text']! as String,
            age: Duration.zero,
          ),
          'commentCount': 13,
        },
      });
      await _pump(tester, detail(backend));
      expect(find.text('Post'), findsOneWidget);
      expect(find.text('Komentarze'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Autor'), findsOneWidget);
      expect(find.text('Ola Wiśniewska'), findsOneWidget);
      expect(find.byKey(const ValueKey('page-comment-field')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('page-comment-field')),
        'Macie wersję z mlekiem owsianym?',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('page-comment-send')));
      await _settle(tester);
      expect(find.text('Macie wersję z mlekiem owsianym?'), findsOneWidget);
      expect(find.text('13'), findsOneWidget);
      // The server pages newest first; the thread reads oldest first, and
      // the comment just sent lands at the bottom (deviation sheet §13).
      double top(int n) => tester
          .getTopLeft(find.byKey(ValueKey('page-comment-${_commentId(n)}')))
          .dy;
      expect(top(1), lessThan(top(2)));
      expect(top(2), lessThan(top(3)));
      expect(events.whereType<PagePostUpdated>().last.post.commentCount, 13);
      final send = backend.payloadsOf(PagesService.engagementCallable).single;
      expect(send['op'], 'comment');
      expect(send['text'], 'Macie wersję z mlekiem owsianym?');
      // ⋯ targets are 44 px.
      expect(
        tester.getSize(
          find.byKey(ValueKey('page-comment-more-${_commentId(1)}')),
        ),
        const Size(44, 44),
      );
    });

    testWidgets('a link in a comment: the commentLinks copy', (tester) async {
      final backend = _Backend({
        PagesService.postCallable: (_) => _detail(_post(1)),
        PagesService.engagementCallable: (_) =>
            throw _refusal('invalid-argument', 'commentLinks'),
      });
      await _pump(tester, detail(backend));
      expect(find.text('Nie ma jeszcze komentarzy'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('page-comment-field')),
        'zajrzyj na example . com',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('page-comment-send')));
      await _settle(tester);
      expect(
        find.text('W komentarzach nie można umieszczać linków.'),
        findsOneWidget,
      );
    });

    testWidgets('read-only Page: the closed line replaces the composer', (
      tester,
    ) async {
      final backend = _Backend({
        PagesService.postCallable: (_) => _detail(_post(1)),
      });
      await _pump(tester, detail(backend, readOnly: true, viewer: 'ola'));
      expect(find.byKey(const ValueKey('page-comment-field')), findsNothing);
      expect(
        find.text('Komentarze są wyłączone, dopóki strona jest wstrzymana.'),
        findsWidgets,
      );
    });

    testWidgets('comments turned off by the Page', (tester) async {
      final backend = _Backend({
        PagesService.postCallable: (_) =>
            _detail(_post(1, commentsEnabled: false)),
      });
      await _pump(tester, detail(backend, viewer: 'ola'));
      expect(
        find.byKey(const ValueKey('page-comments-closed')),
        findsOneWidget,
      );
      expect(
        find.text('Strona wyłączyła komentarze pod tym postem.'),
        findsOneWidget,
      );
    });

    testWidgets('the owner deletes any comment', (tester) async {
      final backend = _Backend({
        PagesService.postCallable: (_) =>
            _detail(_post(1, pageId: 'me'), comments: [_comment(1)]),
        PagesService.engagementCallable: (p) => {
          'schemaVersion': 1,
          'op': 'deleteComment',
          'postId': _postId(1),
          'commentId': p['commentId'],
          'deleted': true,
        },
      });
      await _pump(tester, detail(backend));
      await tester.tap(
        find.byKey(ValueKey('page-comment-more-${_commentId(1)}')),
      );
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('page-comment-delete')));
      await _settle(tester);
      await tester.tap(find.text('Usuń').last);
      await _settle(tester);
      expect(
        backend.payloadsOf(PagesService.engagementCallable).single['commentId'],
        _commentId(1),
      );
      expect(find.text('Ola Wiśniewska'), findsNothing);
      expect(find.text('11'), findsOneWidget);
    });

    testWidgets('earlier comments load above the thread', (tester) async {
      final backend = _Backend({
        PagesService.postCallable: (p) => p['commentCursor'] == null
            ? _detail(_post(1), comments: [_comment(1)], next: 'cursor-2')
            : _detail(
                _post(1),
                comments: [_comment(2, name: 'Tomek Zieliński')],
              ),
      });
      await _pump(tester, detail(backend));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('page-post-load-more')),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('page-post-detail-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Wcześniejsze komentarze'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('page-post-load-more')));
      await _settle(tester);
      expect(find.text('Tomek Zieliński'), findsOneWidget);
      // The earlier page sits between the button and the first page.
      expect(
        tester.getTopLeft(find.text('Tomek Zieliński')).dy,
        lessThan(tester.getTopLeft(find.text('Ola Wiśniewska')).dy),
      );
      expect(
        backend.payloadsOf(PagesService.postCallable).last['commentCursor'],
        'cursor-2',
      );
    });

    testWidgets('unavailable post', (tester) async {
      final backend = _Backend({
        PagesService.postCallable: (_) =>
            throw _refusal('permission-denied', 'pageUnavailable'),
      });
      await _pump(tester, detail(backend));
      expect(
        find.byKey(const ValueKey('page-post-unavailable')),
        findsOneWidget,
      );
      expect(find.text('Ten post jest niedostępny'), findsOneWidget);
    });

    testWidgets('desktop: the thread sits in its own column', (tester) async {
      final backend = _Backend({
        PagesService.postCallable: (_) =>
            _detail(_post(1), comments: [_comment(1)]),
      });
      await _pump(tester, detail(backend), size: const Size(1200, 800));
      final thread = tester.getRect(
        find.byKey(const ValueKey('page-post-thread-column')),
      );
      final card = tester.getRect(
        find.byKey(ValueKey('page-post-detail-${_postId(1)}')),
      );
      expect(thread.width, closeTo(344, 1));
      expect(thread.left, greaterThan(card.right));
    });

    testWidgets('320 px at 200 %: no overflow', (tester) async {
      final backend = _Backend({
        PagesService.postCallable: (_) => _detail(
          _post(1),
          comments: [
            _comment(1),
            _comment(2, own: true, author: 'cafe'),
          ],
        ),
      });
      await _pump(
        tester,
        detail(backend),
        size: const Size(320, 640),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ------------------------------------------------------------ semantics

  group('semantics (§4.5 table)', () {
    testWidgets('voice: "Wiadomość głosowa, 0:42, odtwórz"', (tester) async {
      final handle = tester.ensureSemantics();
      final post = PagePostView.fromWire(
        _post(5, kind: 'voice', media: [_voice(5)]),
      )!;
      await _pump(
        tester,
        Scaffold(
          body: PageVoiceTransport(
            voice: post.voice!,
            postId: post.postId,
            player: PageVoicePlayer(service: _service(_Backend({}))),
            onPlay: () {},
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('Wiadomość głosowa, 0:42, odtwórz'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('likers entry: "48 polubień, pokaż kto polubił", ≥ 44 px', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final post = PagePostView.fromWire(_post(1))!;
      await _pump(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: PagePostCard(
              post: post,
              now: _now,
              service: _service(_Backend({})),
              onOpenPage: () {},
              onToggleLike: () {},
              onShare: () {},
              onMore: () {},
              onOpenLikers: () {},
              onComment: () {},
            ),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('48 polubień, pokaż kto polubił'),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('page-post-likers'))).height,
        greaterThanOrEqualTo(44),
      );
      expect(
        tester.getSemantics(find.byKey(const ValueKey('page-post-like'))),
        isSemantics(
          label: 'Lubię to, 48 polubień',
          hasToggledState: true,
          isToggled: false,
          isButton: true,
        ),
      );
      handle.dispose();
    });
  });

  // ------------------------------------------------------------ notifications

  group('notification arms (§4.7)', () {
    test('destinations', () {
      expect(
        NotificationRouter.destinationFor(NotificationType.pagePostComment),
        NotificationDestination.pagePost,
      );
      expect(
        NotificationRouter.destinationFor(NotificationType.pageModeration),
        NotificationDestination.ownPage,
      );
      expect(
        NotificationRouter.destinationFor(NotificationType.pageLapse),
        NotificationDestination.ownPage,
      );
      expect(
        NotificationType.fromName('pagePostComment'),
        NotificationType.pagePostComment,
      );
    });

    test('localised notice lines from the row, English label as fallback', () {
      AppNotification row(
        NotificationType type, {
        String? action,
        String? reason,
        String? phase,
        String? label,
      }) => AppNotification(
        id: 'n',
        type: type,
        actorId: AppNotification.systemActorId,
        actorName: 'YO Voice',
        actorPhotoUrl: null,
        targetId: 'me',
        targetLabel: label,
        isRead: false,
        createdAt: null,
        moderationAction: action,
        moderationReason: reason,
        lapsePhase: phase,
      );
      const pl = PageNoticeCopy(AppLocalizations(Locale('pl')));
      expect(
        pl.moderation(
          row(
            NotificationType.pageModeration,
            action: 'postRemoved',
            reason: 'restrictedCategory',
          ),
        ),
        'Twój post na stronie został usunięty: niedozwolona kategoria',
      );
      expect(
        pl.moderation(
          row(
            NotificationType.pageModeration,
            action: 'postRestored',
            reason: 'spam',
          ),
        ),
        'Twój post na stronie jest znów widoczny',
      );
      expect(
        pl.moderation(
          row(
            NotificationType.pageModeration,
            action: 'future',
            label: 'Server label',
          ),
        ),
        'Server label',
      );
      expect(
        pl.lapse(row(NotificationType.pageLapse, phase: 'hidingSoon')),
        startsWith('Twoja strona zostanie ukryta za 7 dni.'),
      );
      expect(row(NotificationType.pageLapse).isSystemNotice, isTrue);
    });
  });

  // ------------------------------------------------------------ upsell

  group('Pages upsell (R11)', () {
    testWidgets('honest: VIP for testers, not for sale, reading is free', (
      tester,
    ) async {
      var premium = 0;
      await _pump(
        tester,
        Scaffold(body: PagesUpsellSheet(onSeePremium: () => premium++)),
      );
      expect(find.text('Własna strona to funkcja VIP'), findsOneWidget);
      expect(
        find.text('Premium nie jest jeszcze dostępne do kupienia.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Obserwowanie stron i czytanie postów jest bezpłatne dla wszystkich.',
        ),
        findsOneWidget,
      );
      expect(find.text('Rozumiem'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pages-upsell-premium')));
      expect(premium, 1);
    });
  });

  // ------------------------------------------------ review fixes

  group('review fixes: composer, detail, publisher', () {
    Map<String, Object?> image(int n) => {
      'mediaId': _mediaId(n),
      'type': 'image',
      'contentType': 'image/jpeg',
      'width': 1600,
      'height': 1200,
      'durationMs': null,
    };

    List<String> captureAnnouncements(WidgetTester tester) {
      final messages = <String>[];
      tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, (
            message,
          ) async {
            if (message is Map && message['type'] == 'announce') {
              final data = message['data'] as Map<Object?, Object?>;
              messages.add('${data['message']}');
            }
            return null;
          });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler(SystemChannels.accessibility, null),
      );
      return messages;
    }

    Future<void> open(
      WidgetTester tester, {
      required _Backend backend,
      PagePostKind kind = PagePostKind.photo,
      int photos = 0,
      _FakeRecorder? recorder,
      PagePostPublisher? publisher,
    }) async {
      final service = _service(backend);
      await _pump(
        tester,
        _ComposerHost(
          open: (context) => showPageComposer(
            context,
            owner: const PageComposerOwner(
              pageId: 'me',
              name: 'Kawiarnia Pod Lipą',
              kind: PageKind.business,
            ),
            initialKind: kind,
            service: service,
            publisher:
                publisher ??
                PagePostPublisher(
                  service: service,
                  uploader: (slot, payload, {required onProgress}) async {},
                ),
            pickPhotos: (_) async => [
              for (var i = 0; i < photos; i++)
                XFile.fromData(_jpeg(), name: '$i.jpg'),
            ],
            sanitize: (bytes) async =>
                SanitizedJpeg(bytes: _jpeg(), width: 8, height: 6),
            recorderFactory: recorder == null ? null : () => recorder,
            clock: () => _now,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-composer')));
      await _settle(tester);
    }

    int thumbs() => find
        .byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'page-composer-photo-',
              ),
        )
        .evaluate()
        .length;

    testWidgets('the whole 44 px remove target removes a photo', (
      tester,
    ) async {
      await open(tester, backend: _Backend({}), photos: 4);
      expect(thumbs(), 4);
      final corners = <Offset Function(Rect)>[
        (r) => r.topLeft + const Offset(2, 2),
        (r) => r.topRight + const Offset(-2, 2),
        (r) => r.bottomLeft + const Offset(2, -2),
        (r) => r.bottomRight + const Offset(-2, -2),
      ];
      var left = 4;
      for (final corner in corners) {
        final rect = tester.getRect(
          find.byKey(const ValueKey('page-composer-remove-0')),
        );
        expect(rect.size, const Size(44, 44));
        await tester.tapAt(corner(rect));
        await tester.pump();
        left--;
        expect(thumbs(), left, reason: 'corner of $rect');
      }
    });

    testWidgets('a thumbnail is a keyboard control that picks the stage', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester, backend: _Backend({}), photos: 3);
      final thumb = find.byKey(const ValueKey('page-composer-thumb-0'));
      final node = Focus.of(
        tester.element(
          find.descendant(of: thumb, matching: find.byType(Container)).first,
        ),
      );
      expect(node.canRequestFocus, isTrue);
      node.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        tester.getSemantics(thumb),
        isSemantics(isSelected: true, isButton: true),
      );
      handle.dispose();
    });

    testWidgets('voice: the meter follows amplitudes, Stop takes focus, '
        '10 s left is announced, the transcript is invited', (tester) async {
      final announcements = captureAnnouncements(tester);
      final recorder = _FakeRecorder();
      await open(
        tester,
        backend: _Backend({}),
        kind: PagePostKind.voice,
        recorder: recorder,
      );
      expect(find.text('Opis lub transkrypcja (zalecane)'), findsOneWidget);
      expect(
        find.text(
          'Wersja tekstowa pozwala śledzić post osobom, które nie mogą słuchać.',
        ),
        findsOneWidget,
      );
      expect(find.text('Do 1:00'), findsOneWidget);
      final record = find.byKey(const ValueKey('page-composer-record'));
      Focus.of(
        tester.element(
          find.descendant(of: record, matching: find.byType(Icon)).first,
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      final stop = find.byKey(const ValueKey('page-composer-stop'));
      expect(stop, findsOneWidget);
      expect(
        Focus.of(
          tester.element(
            find.descendant(of: stop, matching: find.byType(Icon)).first,
          ),
        ).hasPrimaryFocus,
        isTrue,
        reason: 'the record control became Stop; focus went with it',
      );
      for (final db in [-30.0, -12.0, -3.0, -40.0]) {
        recorder.levels.add(Amplitude(current: db, max: 0));
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(tester.takeException(), isNull);
      recorder.fakeElapsed = const Duration(seconds: 50);
      await tester.pump(const Duration(milliseconds: 300));
      expect(announcements, contains('Zostało 10 sekund.'));
      await tester.tap(stop);
      await _settle(tester);
      expect(find.byKey(const ValueKey('page-composer-rerecord')), findsOne);
    });

    testWidgets('publishing keeps the comments switch drawn ON', (
      tester,
    ) async {
      final pending = Completer<Object?>();
      final backend = _Backend({
        PagesService.publishCallable: (_) => pending.future,
      });
      await open(tester, backend: backend, kind: PagePostKind.text);
      await tester.enterText(
        find.byKey(const ValueKey('page-composer-text')),
        'Dzień dobry',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('page-composer-publish')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(backend.payloadsOf(PagesService.publishCallable), hasLength(1));
      final toggle = tester.widget<Switch>(
        find.byKey(const ValueKey('page-composer-comments')),
      );
      expect(toggle.value, isTrue);
      expect(toggle.onChanged, isNotNull, reason: 'locked, not disabled');
      await tester.tap(find.byKey(const ValueKey('page-composer-comments')));
      await tester.pump();
      expect(
        tester
            .widget<Switch>(
              find.byKey(const ValueKey('page-composer-comments')),
            )
            .value,
        isTrue,
      );
      pending.complete(_post(11, pageId: 'me'));
      await _settle(tester);
    });

    test(
      'an unresolved publish keeps its request id; a refusal drops it',
      () async {
        var answer = 0;
        final backend = _Backend({
          PagesService.publishCallable: (_) {
            answer++;
            if (answer == 1) throw _refusal('unavailable');
            if (answer == 2) throw _refusal('invalid-argument');
            return _post(11, pageId: 'me');
          },
        });
        final publisher = PagePostPublisher(service: _service(backend));
        addTearDown(publisher.dispose);
        await expectLater(
          publisher.publishText(text: 'A', commentsEnabled: true),
          throwsA(isA<PagesException>()),
        );
        expect(publisher.publishUnresolved, isTrue);
        await expectLater(
          publisher.publishText(text: 'A', commentsEnabled: true),
          throwsA(isA<PagesException>()),
        );
        expect(publisher.publishUnresolved, isFalse);
        await publisher.publishText(text: 'B', commentsEnabled: true);
        final ids = [
          for (final p in backend.payloadsOf(PagesService.publishCallable))
            p['requestId'],
        ];
        expect(ids[0], ids[1], reason: 'the unknown outcome is retried as is');
        expect(ids[2], isNot(ids[1]), reason: 'an answered refusal is new');
      },
    );

    Widget detail(_Backend backend) => PagePostDetailScreen(
      postId: _postId(1),
      pageId: 'cafe',
      service: _service(backend),
      viewerId: 'me',
      viewerName: 'Aleksandra Nowak',
      player: PageVoicePlayer(service: _service(backend)),
      clock: () => _now,
    );

    testWidgets('detail: Back and the title are two nodes; photos take '
        'keyboard focus and open', (tester) async {
      final handle = tester.ensureSemantics();
      final backend = _Backend({
        PagesService.postCallable: (_) =>
            _detail(_post(1, kind: 'photo', media: [image(1)])),
        PagesService.mediaAccessCallable: _grants,
      });
      await _pump(tester, detail(backend), size: const Size(1440, 900));
      await _settle(tester);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Wstecz')),
        isSemantics(isButton: true, isHeader: false),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Post')),
        isSemantics(isHeader: true, isButton: false),
      );
      final photo = find.byKey(const ValueKey('page-photo-0'));
      final node = Focus.of(
        tester.element(
          find.descendant(of: photo, matching: find.byType(Stack)).last,
        ),
      );
      expect(node.canRequestFocus, isTrue);
      node.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(tester);
      expect(
        find.byType(DirectImageFullscreenViewer),
        findsOneWidget,
        reason: 'Enter opens the full-screen viewer',
      );
      handle.dispose();
    });

    testWidgets('detail on a phone crops a single photo to a wide band', (
      tester,
    ) async {
      final backend = _Backend({
        PagesService.postCallable: (_) =>
            _detail(_post(1, kind: 'photo', media: [image(1)])),
        PagesService.mediaAccessCallable: _grants,
      });
      await _pump(tester, detail(backend));
      await _settle(tester);
      final size = tester.getSize(find.byKey(const ValueKey('page-photo-0')));
      expect(size.height, lessThanOrEqualTo((390 - 32) / 2.5 + .5));
    });
  });
}

class _FakeRecorder implements VoiceMomentRecorder {
  final StreamController<Amplitude> levels =
      StreamController<Amplitude>.broadcast();
  Duration fakeElapsed = Duration.zero;
  bool _recording = false;

  @override
  Duration get elapsed => fakeElapsed;

  @override
  bool get isRecording => _recording;

  @override
  int get durationSeconds => fakeElapsed.inSeconds.clamp(1, 60);

  @override
  Stream<Amplitude> amplitudes({
    Duration interval = const Duration(milliseconds: 120),
  }) => levels.stream;

  @override
  Future<void> start() async => _recording = true;

  @override
  Future<RecordedAudio> stop() async {
    _recording = false;
    return _FakeAudio(1200);
  }

  @override
  Future<void> cancel() async => _recording = false;

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
