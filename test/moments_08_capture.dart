// Developer-only visual QA harness for board 08 — the Reels stage, its
// footer bar and the docked "Rozmowa" column.
//
// The filename deliberately has no `_test` suffix, so the ordinary suite
// skips it. Run explicitly:
//
//   flutter test test/moments_08_capture.dart
//
// PNGs land in test/.screenshots/ (git-ignored) as
// `moments-08-{width}[-x2|-rtl|-pearl]-{state}.png`, the naming the build
// brief asks for.
//
// WIDTH IS THE SLOT the destination receives, not the window: inside the
// Home shell a 1440 window gives Moments ~1176 (wide-2: card + thread) and a
// 1464 window gives 1200 (wide-3: local panel + card + thread). Both are
// captured, under their slot widths.
//
// Why this exists: the widget tests prove keys, geometry and behaviour; they
// never prove any of it renders. These frames are what a reviewer looks at.
// Every fixture is controlled, reference-like data — no real account, no real
// upload — and the media is a flat panel standing in for footage, so the
// legibility of white-on-media chrome can be judged against a light frame.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
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

const _captions = <String>[
  'Poranek w porcie, zanim ruszą pierwsze łodzie',
  'Mała rzecz, dobry dzień',
];

Map<String, Object?> _reelWire(int index) {
  final millis = 1725000000000 + index;
  return <String, Object?>{
    'id': 'reel_$index',
    'authorId': 'creator_$index',
    'authorName': index == 1 ? 'Maja Nowak' : 'Kuba',
    'media': <String, Object?>{
      'kind': 'video',
      'contentType': 'video/mp4',
      'size': 4096,
      'generation': '7',
      'durationMs': 18000,
    },
    'backingAudio': null,
    'composition': ReelComposition(
      trimStartMs: 0,
      trimEndMs: 18000,
      originalAudioVolume: 100,
      caption: _captions[index - 1],
    ).toWire(),
    'publishedAtMillis': millis,
    'sortKey': '${millis}_reel_$index',
    'availability': <String, Object?>{
      'schemaVersion': 1,
      'availabilityHours': 'permanent',
      'expiresAtMillis': null,
    },
    'likeCount': index == 1 ? 42 : 8,
    'commentCount': index == 1 ? 8 : 1,
    'callerLiked': false,
  };
}

enum _Cell { populated, thread, empty, error }

ReelService _service(_Cell state) => ReelService(
  auth: MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'me', isEmailVerified: true),
  ),
  callableInvoker: (name, payload) async {
    switch (name) {
      case 'listReelsV2':
        if (state == _Cell.error) throw StateError('offline');
        return <Object?, Object?>{
          'schemaVersion': 2,
          'items': state == _Cell.empty
              ? <Object?>[]
              : <Object?>[_reelWire(1), _reelWire(2)],
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
        return <Object?, Object?>{
          'schemaVersion': 2,
          'reel': _reelWire(1),
          'comments': <Object?>[
            for (final entry in const <List<String>>[
              ['c1', 'Ola', 'To ujęcie o świcie jest cudowne.'],
              ['c2', 'Kuba', 'Gdzie to było?'],
            ])
              <String, Object?>{
                'schemaVersion': 1,
                'commentId': entry[0],
                'type': 'text',
                'authorId': entry[0],
                'authorName': entry[1],
                'authorPhotoUrl': null,
                'text': entry[2],
                'durationSeconds': null,
                'createdAtMillis': 1725000000000,
              },
          ],
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

FollowService _follows() => FollowService(
  firestore: FakeFirebaseFirestore(),
  auth: MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'me', isEmailVerified: true),
  ),
  mutationInvoker: (_) async => <String, dynamic>{},
);

/// A flat, light panel standing in for footage: white-on-media chrome has to
/// stay legible on the worst case, not on a convenient dark frame.
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
  required bool rtl,
  required double textScale,
  required Size size,
}) => RepaintBoundary(
  key: _capture,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: pearl ? AppTheme.lightTheme : AppTheme.darkTheme,
    locale: const Locale('pl'),
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
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
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

void main() {
  late PublicIdentityRepository originalIdentity;

  setUpAll(_loadFonts);

  setUp(() {
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

  Future<void> cell(
    WidgetTester tester, {
    required double width,
    required double height,
    _Cell state = _Cell.populated,
    bool pearl = false,
    bool rtl = false,
    double textScale = 1,
  }) async {
    final size = Size(width, height);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _host(
        MomentsScreen(
          key: UniqueKey(),
          isRootTab: true,
          initialFormat: YoMomentsFormat.reels,
          reelService: _service(state),
          reelVideoBuilder: _footage,
          followService: _follows(),
          onCreateReel: () async {},
        ),
        pearl: pearl,
        rtl: rtl,
        textScale: textScale,
        size: size,
      ),
    );
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    if (state == _Cell.thread) {
      final toggle = find.byKey(
        const ValueKey<String>('reel-panel-thread-toggle'),
      );
      if (toggle.evaluate().isNotEmpty) {
        await tester.tap(toggle);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 120));
        }
      }
    }
  }

  final frames = <String, Future<void> Function(WidgetTester)>{
    'moments-08-320-populated': (t) => cell(t, width: 320, height: 568),
    'moments-08-390-populated': (t) => cell(t, width: 390, height: 844),
    'moments-08-390-x2-populated': (t) =>
        cell(t, width: 390, height: 844, textScale: 2),
    'moments-08-390-rtl-populated': (t) =>
        cell(t, width: 390, height: 844, rtl: true),
    'moments-08-390-pearl-populated': (t) =>
        cell(t, width: 390, height: 844, pearl: true),
    'moments-08-390-empty': (t) =>
        cell(t, width: 390, height: 844, state: _Cell.empty),
    'moments-08-390-error': (t) =>
        cell(t, width: 390, height: 844, state: _Cell.error),
    'moments-08-768-populated': (t) => cell(t, width: 768, height: 1024),
    'moments-08-1100-populated': (t) => cell(t, width: 1100, height: 900),
    'moments-08-1176-populated': (t) => cell(t, width: 1176, height: 900),
    'moments-08-1200-populated': (t) => cell(t, width: 1200, height: 900),
    'moments-08-1440-populated': (t) => cell(t, width: 1440, height: 900),
    'moments-08-1440-thread': (t) =>
        cell(t, width: 1440, height: 900, state: _Cell.thread),
    'moments-08-1440-pearl-populated': (t) =>
        cell(t, width: 1440, height: 900, pearl: true),
    'moments-08-1440-x2-populated': (t) =>
        cell(t, width: 1440, height: 900, textScale: 2),
    'moments-08-1656-thread': (t) =>
        cell(t, width: 1656, height: 1000, state: _Cell.thread),
  };

  for (final entry in frames.entries) {
    testWidgets(entry.key, (tester) async {
      await entry.value(tester);
      await _shoot(tester, entry.key);
    });
  }
}
