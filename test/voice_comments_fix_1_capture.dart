// Developer-only visual QA harness for the Reels voice-comment surfaces and
// the Moderation Center's voice-report evidence (voice-comments-fix-1).
//
// The filename deliberately has no `_test` suffix, so the ordinary suite
// skips it. Run explicitly:
//
//   flutter test test/voice_comments_fix_1_capture.dart
//
// PNGs land in test/.screenshots/ (git-ignored) as
// `vc-fix1-{surface}-{width}[-x2|-pearl]-{state}.png`.
//
// Why this exists: the widget tests prove keys, semantics and that nothing
// overflows; they never prove any of it renders. These frames are what a
// reviewer looks at. Every fixture is controlled, illustrative data — no real
// account, no real upload, no real recording.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moderation/data/models/moderation_audit_event.dart';
import 'package:yovoice/features/moderation/data/services/moderation_service.dart';
import 'package:yovoice/features/moderation/presentation/screens/moderation_center_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_comment_report_sheet.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_comments_view.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

final _capture = GlobalKey();

String get _fontRoot {
  const candidates = [
    '/opt/homebrew/Caskroom/flutter/3.44.6/flutter/bin/cache/artifacts/material_fonts',
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts',
    '/usr/local/share/flutter/bin/cache/artifacts/material_fonts',
  ];
  return candidates.firstWhere(
    (path) => File('$path/Roboto-Regular.ttf').existsSync(),
  );
}

Future<void> _loadFonts() async {
  Future<ByteData> read(String name) async {
    final bytes = File('$_fontRoot/$name').readAsBytesSync();
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }

  final roboto = FontLoader('Roboto');
  for (final face in const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]) {
    roboto.addFont(read(face));
  }
  await roboto.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(read('MaterialIcons-Regular.otf'))).load();
  final inter = FontLoader('Inter');
  inter.addFont(
    Future.value(
      ByteData.view(
        Uint8List.fromList(
          File('assets/fonts/InterVariable.ttf').readAsBytesSync(),
        ).buffer,
      ),
    ),
  );
  await inter.load();
}

Map<String, Object?> _reelWire({int commentCount = 4}) {
  const millis = 1725000000000;
  return <String, Object?>{
    'id': 'reel_1',
    'authorId': 'creator_1',
    'authorName': 'Maja Nowak',
    'media': <String, Object?>{
      'kind': 'video',
      'contentType': 'video/mp4',
      'size': 4096,
      'generation': '7',
      'durationMs': 18000,
    },
    'backingAudio': null,
    'composition': const ReelComposition(
      trimStartMs: 0,
      trimEndMs: 18000,
      originalAudioVolume: 100,
      caption: 'Poranek w porcie, zanim ruszą pierwsze łodzie',
    ).toWire(),
    'publishedAtMillis': millis,
    'sortKey': '${millis}_reel_1',
    'availability': <String, Object?>{
      'schemaVersion': 1,
      'availabilityHours': 'permanent',
      'expiresAtMillis': null,
    },
    'likeCount': 42,
    'commentCount': commentCount,
    'callerLiked': false,
  };
}

Map<String, Object?> _comment(
  String id,
  String author, {
  String text = '',
  int? voiceSeconds,
}) => <String, Object?>{
  'schemaVersion': 1,
  'commentId': id,
  'type': voiceSeconds == null ? 'text' : 'voice',
  'authorId': 'author_$id',
  'authorName': author,
  'authorPhotoUrl': null,
  'text': text,
  'durationSeconds': voiceSeconds,
  'createdAtMillis': 1725000000000,
};

enum _Thread { populated, longContent, empty }

List<Map<String, Object?>> _comments(_Thread state) => switch (state) {
  _Thread.empty => const <Map<String, Object?>>[],
  _Thread.populated => <Map<String, Object?>>[
    _comment('c1', 'Ola', text: 'To ujęcie o świcie jest cudowne.'),
    _comment('c2', 'Kuba', voiceSeconds: 12),
    _comment('c3', 'Tomek', voiceSeconds: 42, text: 'Posłuchaj końcówki'),
    _comment('c4', 'Ania', text: 'Gdzie to było?'),
  ],
  _Thread.longContent => <Map<String, Object?>>[
    _comment(
      'c1',
      'Aleksandra Wiśniewska-Kowalczyk',
      voiceSeconds: 60,
      text:
          'Nagrałam to na spacerze, słychać mewy i silnik łodzi w tle, więc '
          'podgłośnij, bo końcówka jest najlepsza, naprawdę warto posłuchać',
    ),
    _comment('c2', 'Kuba', voiceSeconds: 1),
    _comment(
      'c3',
      'Ola',
      text:
          'Bardzo długi komentarz tekstowy, który musi się ładnie zawinąć na '
          'kilka linii i nie może rozepchnąć ani przycisku mikrofonu, ani pola '
          'wpisywania, ani przycisku wysyłania na najwęższej szerokości.',
    ),
  ],
};

ReelService _reelService({
  required bool acceptsVoice,
  required _Thread state,
}) => ReelService(
  auth: MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'me', isEmailVerified: true),
  ),
  callableInvoker: (name, payload) async {
    switch (name) {
      case 'listReelsV2':
        return <Object?, Object?>{
          'schemaVersion': 2,
          'items': <Object?>[_reelWire()],
          'nextCursor': null,
        };
      case 'getReelMediaAccessV2':
        return <Object?, Object?>{
          'schemaVersion': 2,
          'url': 'https://storage.googleapis.com/yovoice/reel.mp4',
          'expiresAtMillis': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
          'generation': '7',
          'availabilityHours': 'permanent',
          'contentExpiresAtMillis': null,
        };
      case 'getReelViewV2':
        if (!acceptsVoice && payload.containsKey('commentTypes')) {
          // What a deployment that predates voice comments answers.
          throw FirebaseFunctionsException(
            code: 'invalid-argument',
            message: 'commentTypes is invalid.',
          );
        }
        final comments = _comments(state)
            .where(
              (comment) =>
                  payload.containsKey('commentTypes') ||
                  comment['type'] == 'text',
            )
            .toList();
        return <Object?, Object?>{
          'schemaVersion': 2,
          'reel': _reelWire(commentCount: _comments(state).length),
          'comments': comments,
          'commentsTruncated': false,
          'nextCommentCursor': null,
        };
      case 'listReelCommentsV2':
        return <Object?, Object?>{
          'schemaVersion': 2,
          'items': <Object?>[],
          'nextCursor': null,
        };
    }
    throw StateError('Unexpected callable $name with $payload');
  },
);

Widget _footage(BuildContext context, Uri uri, Object reel) =>
    const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFEFE6DA), Color(0xFF9FB3C8)],
        ),
      ),
    );

Widget _host(
  Widget child, {
  required bool pearl,
  required double textScale,
  required Size size,
  Locale locale = const Locale('pl'),
}) => RepaintBoundary(
  key: _capture,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: pearl ? AppTheme.lightTheme : AppTheme.darkTheme,
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
        disableAnimations: true,
      ),
      child: child!,
    ),
    home: child,
  ),
);

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('test/.screenshots/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path}');
    } finally {
      image.dispose();
    }
  });
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _QuietAudit extends ModerationService {
  _QuietAudit({
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

void main() {
  late PublicIdentityRepository originalIdentity;

  setUpAll(_loadFonts);

  setUp(() {
    ReelService.clearAllMediaAccessCaches();
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentity;
  });

  // ---- The thread on its own: the phone sheet and the medium sheet. ----
  Future<void> thread(
    WidgetTester tester, {
    required double width,
    required double height,
    bool acceptsVoice = true,
    _Thread state = _Thread.populated,
    bool pearl = false,
    double textScale = 1,
  }) async {
    final size = Size(width, height);
    _size(tester, size);
    await tester.pumpWidget(
      _host(
        Scaffold(
          body: SafeArea(
            child: ReelCommentsView(
              reel: Reel.fromV2Wire(_reelWire()),
              service: _reelService(acceptsVoice: acceptsVoice, state: state),
              onReelUpdated: (_) {},
            ),
          ),
        ),
        pearl: pearl,
        textScale: textScale,
        size: size,
      ),
    );
    await _settle(tester);
  }

  // ---- The wide feed with the docked thread. ----
  Future<void> wide(
    WidgetTester tester, {
    required double width,
    required double height,
    bool acceptsVoice = true,
    bool pearl = false,
  }) async {
    final size = Size(width, height);
    _size(tester, size);
    await tester.pumpWidget(
      _host(
        MomentsScreen(
          key: UniqueKey(),
          isRootTab: true,
          initialFormat: YoMomentsFormat.reels,
          reelService: _reelService(
            acceptsVoice: acceptsVoice,
            state: _Thread.populated,
          ),
          reelVideoBuilder: _footage,
          followService: FollowService(
            firestore: FakeFirebaseFirestore(),
            auth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: 'me', isEmailVerified: true),
            ),
            mutationInvoker: (_) async => <String, dynamic>{},
          ),
          onCreateReel: () async {},
        ),
        pearl: pearl,
        textScale: 1,
        size: size,
      ),
    );
    await _settle(tester);
    final toggle = find.byKey(
      const ValueKey<String>('reel-panel-thread-toggle'),
    );
    if (toggle.evaluate().isNotEmpty) {
      await tester.tap(toggle);
      await _settle(tester);
    }
  }

  // ---- The reporter's sheet. ----
  Future<void> reportSheet(
    WidgetTester tester, {
    required double width,
    required double height,
    String caption = '',
    bool pearl = false,
    double textScale = 1,
  }) async {
    final size = Size(width, height);
    _size(tester, size);
    await tester.pumpWidget(
      _host(
        Scaffold(
          body: ReelCommentReportSheet(
            authorName: 'Kuba',
            commentText: caption,
            voiceDurationSeconds: 42,
          ),
        ),
        pearl: pearl,
        textScale: textScale,
        size: size,
      ),
    );
    await _settle(tester);
  }

  // ---- Staff: the Moderation Center with a voice report open. ----
  Future<void> moderation(
    WidgetTester tester, {
    required double width,
    required double height,
    String? commentType = 'voice',
    String caption = '',
    bool pearl = false,
    double textScale = 1,
    bool open = true,
  }) async {
    final size = Size(width, height);
    _size(tester, size);
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('mod').set({
      'uid': 'mod',
      'displayName': 'mod',
      'role': 'moderator',
    });
    await db.collection('reports').doc('r-voice').set({
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
      'targetCommentType': commentType,
      'targetDurationSeconds': commentType == 'voice' ? 42 : null,
      'targetStoragePath': commentType == 'voice'
          ? 'reel_voice_comments/commenter-uid/reel-1/comment-1.m4a'
          : null,
      'targetMediaGeneration': commentType == 'voice' ? '900001' : null,
      'note': 'Nagranie z obelgami pod moją rolką',
      'reason': 'harassment',
      'status': 'open',
      'createdAt': Timestamp.now(),
    });
    await tester.pumpWidget(
      _host(
        ModerationCenterScreen(
          moderationService: _QuietAudit(
            firestore: db,
            auth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(
                uid: 'mod',
                email: 'mod@yovoice.app',
                customClaim: const {'role': 'moderator'},
              ),
            ),
          ),
        ),
        pearl: pearl,
        textScale: textScale,
        size: size,
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    if (open) {
      final row = find.bySemanticsLabel(
        RegExp(r'Harassment or bullying, Open'),
      );
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
    }
  }

  final frames = <String, Future<void> Function(WidgetTester)>{
    // Thread: supported mic, populated, three widths and both themes.
    'vc-fix1-thread-320-populated': (t) => thread(t, width: 320, height: 640),
    'vc-fix1-thread-390-populated': (t) => thread(t, width: 390, height: 844),
    'vc-fix1-thread-390-pearl-populated': (t) =>
        thread(t, width: 390, height: 844, pearl: true),
    'vc-fix1-thread-320-x2-populated': (t) =>
        thread(t, width: 320, height: 900, textScale: 2),
    'vc-fix1-thread-390-long': (t) =>
        thread(t, width: 390, height: 844, state: _Thread.longContent),
    'vc-fix1-thread-390-empty': (t) =>
        thread(t, width: 390, height: 844, state: _Thread.empty),
    'vc-fix1-thread-768-populated': (t) => thread(t, width: 768, height: 1024),
    // Thread: a backend that predates voice comments.
    'vc-fix1-thread-390-unsupported': (t) =>
        thread(t, width: 390, height: 844, acceptsVoice: false),
    'vc-fix1-thread-390-pearl-unsupported': (t) =>
        thread(t, width: 390, height: 844, acceptsVoice: false, pearl: true),
    // Wide feed with the docked thread.
    'vc-fix1-wide-1440-thread': (t) => wide(t, width: 1440, height: 900),
    'vc-fix1-wide-1440-pearl-thread': (t) =>
        wide(t, width: 1440, height: 900, pearl: true),
    'vc-fix1-wide-1440-unsupported-thread': (t) =>
        wide(t, width: 1440, height: 900, acceptsVoice: false),
    // The reporter's sheet.
    'vc-fix1-report-390-voice': (t) => reportSheet(t, width: 390, height: 844),
    'vc-fix1-report-320-x2-voice-caption': (t) => reportSheet(
      t,
      width: 320,
      height: 900,
      caption: 'Posłuchaj końcówki',
      textScale: 2,
    ),
    // Staff evidence.
    'vc-fix1-moderation-360-queue': (t) =>
        moderation(t, width: 360, height: 800, open: false),
    'vc-fix1-moderation-360-voice': (t) =>
        moderation(t, width: 360, height: 800),
    'vc-fix1-moderation-360-x2-voice': (t) =>
        moderation(t, width: 360, height: 1000, textScale: 2),
    'vc-fix1-moderation-768-voice': (t) =>
        moderation(t, width: 768, height: 1024),
    'vc-fix1-moderation-1440-voice': (t) =>
        moderation(t, width: 1440, height: 1000),
    'vc-fix1-moderation-1440-pearl-voice': (t) =>
        moderation(t, width: 1440, height: 1000, pearl: true),
    'vc-fix1-moderation-1440-voice-caption': (t) => moderation(
      t,
      width: 1440,
      height: 1000,
      caption: 'you know exactly why I said it',
    ),
    'vc-fix1-moderation-1440-text-control': (t) => moderation(
      t,
      width: 1440,
      height: 1000,
      commentType: 'text',
      caption: 'the reported words, unchanged',
    ),
  };

  for (final entry in frames.entries) {
    testWidgets(entry.key, (tester) async {
      await entry.value(tester);
      await _shoot(tester, entry.key);
    });
  }
}
