// Refine-look B6 (Capture + Yeels, signature moment W4) frame harness.
//
// The filename deliberately has no `_test` suffix, so the ordinary suite
// skips it. Run explicitly:
//
//   flutter test test/refine_b6_capture.dart --concurrency=1 \
//     --dart-define=YO_CAPTURE_DIR=<evidence>/b6/after
//
// Frames are named `<screen>_<width>_<dark|pearl>_pl_<text>_<state>[-hc|-rm]`:
//
// * `recorder` — the real RecordVoiceMomentScreen over a fake recorder, in
//   the states W4 names: idle, requesting (a microphone prompt held open),
//   recording with a loud simulated input, recording in silence, and
//   review. The level is fed through the recorder's real amplitude stream,
//   so the meter and the halo read the very same samples.
// * `moments-yeels` — the real YO Moments screen with Yeels selected, over a
//   flat light "footage" panel (the worst case for white chrome).
// * `moments-yeels` `_scrubbing` / `_played` — the Yeels stage composed the
//   way YO Moments hosts it (immersive below 1100, the wide header and the
//   card stage from 1100) mid-drag and after a drag to 40 %, so the played
//   sweep of the timeline is on the frame, at 390 / 768 / 1440.
// * `moments-voice` / `moments-create-sheet` — the Głos canvas with its `+`
//   disc, and the create sheet's R2 choices.
// * `…-focus` / `…-hover` — keyboard focus (traditional highlight mode) and
//   a mouse pointer on the record bead, the `+` disc on the canvas and over
//   media, a 48 px media glyph plate and the create-sheet tiles.
// * `y3-yeels` — the one-row Yeels chrome (board Y3): Discover with the
//   viewer's avatar, and "Twoje Yeels" after the avatar is tapped, at 320 /
//   390 / 768 / 1440, 100 % and 200 %, high contrast, and keyboard focus on
//   the avatar and on the Back chevron. Run only these with
//   `--plain-name y3`.
//
// 390 / 768 / 1440, Dark and Pearl, 100 % and 200 % text, plus high-contrast
// and Reduce Motion frames. Every fixture is controlled, reference-like
// data: no real account, no recording, no network, no callable.
//
// The file runs unchanged on the pre-refine base (e9af91d8), which is how the
// matching before-frames are made: it only reaches the new code through
// keys and types that exist on both sides.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart' show Amplitude;

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/yo_moments_chrome.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/screens/reels_feed_screen.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_overlay_atoms.dart';

import 'reel_stage_test_support.dart';
import 'support/material_icons_font.dart';
import 'voice_moment_test_doubles.dart';

const _outDir = String.fromEnvironment(
  'YO_CAPTURE_DIR',
  defaultValue: 'test/.screenshots/refine-b6',
);

/// Colour emoji for any glyph Inter lacks: the macOS system face, or the
/// Noto one a Linux host ships.
const _emojiFonts = <String>[
  '/System/Library/Fonts/Apple Color Emoji.ttc',
  '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf',
];

final _capture = GlobalKey();

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))
    ..addFont(rootBundle.load('assets/fonts/InterVariable-Italic.ttf'));
  await inter.load();
  await loadMaterialIconsFont();
  for (final path in _emojiFonts) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = ByteData.sublistView(file.readAsBytesSync());
    for (final family in const ['Apple Color Emoji', 'sans-serif']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    break;
  }
}

Widget _host(
  Widget child, {
  required bool pearl,
  required double textScale,
  required Size size,
  bool highContrast = false,
  bool reduceMotion = false,
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
        highContrast: highContrast,
        disableAnimations: reduceMotion,
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
      final file = File('$_outDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path}');
    } finally {
      image.dispose();
    }
  });
}

/// Overflow and assertion failures are findings: printed, and the frame that
/// shows them is still written.
void _report(WidgetTester tester, String name) {
  final error = tester.takeException();
  if (error != null) {
    // ignore: avoid_print
    print('EXCEPTION $name :: $error');
  }
}

/// Asset art (the scenery, the logo) decodes on real I/O, which only runs
/// inside `runAsync`: without this the first capture of a run can race the
/// decode and show a bare canvas where the lounge belongs.
Future<void> _decodeAssetImages(WidgetTester tester) async {
  final images = find.byType(Image);
  final providers = <ImageProvider<Object>>[];
  for (final image in tester.widgetList<Image>(images)) {
    final provider = image.image;
    final base = provider is ResizeImage ? provider.imageProvider : provider;
    if (base is AssetBundleImageProvider) providers.add(provider);
  }
  if (providers.isEmpty) return;
  final context = tester.element(images.first);
  await tester.runAsync(() async {
    for (final provider in providers) {
      await precacheImage(provider, context);
    }
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Keyboard focus as a keyboard user sees it: the traditional highlight
/// mode, then focus on the control that owns [inside] (the nearest focus
/// node above it — the control's own InkWell).
Future<void> _focusOwnerOf(WidgetTester tester, Finder inside) async {
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  addTearDown(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic,
  );
  await tester.ensureVisible(inside.first);
  await tester.pump();
  Focus.of(tester.element(inside.first)).requestFocus();
  await _settleRing(tester);
}

/// A focus or hover change starts the ring's implicit animation during the
/// frame that rebuilds it, so its ticker only begins on the next frame:
/// pump a few more so the frame shows the finished ring.
Future<void> _settleRing(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// A mouse resting on [target]'s centre. The caller removes the pointer.
Future<TestGesture> _hover(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target.first);
  await tester.pump();
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getCenter(target.first));
  await _settleRing(tester);
  return mouse;
}

/// What a focus/hover frame shows.
enum _Pointer { none, focus, hover }

String _name(
  String screen,
  double width,
  bool pearl,
  double textScale,
  String state, {
  bool highContrast = false,
  bool reduceMotion = false,
}) {
  final theme = pearl ? 'pearl' : 'dark';
  final text = (textScale * 100).round().toString();
  final suffix = highContrast
      ? '-hc'
      : reduceMotion
      ? '-rm'
      : '';
  return '${screen}_${width.toInt()}_${theme}_pl_${text}_$state$suffix';
}

const _sizes = <Size>[Size(390, 844), Size(768, 1024), Size(1440, 900)];

void _sizeView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// ---------------------------------------------------------------------------
// Recorder
// ---------------------------------------------------------------------------

enum _RecorderState { idle, requesting, recording, silent, review, unavailable }

/// A speech-like run of input levels in dBFS, oldest first, ending on a
/// loud phrase: 27 samples fill the meter, and the halo ends near L .8.
const _speech = <double>[
  -38, -30, -22, -15, -11, -9, -13, -19, -26, -16, -10, -7, -8, -12, //
  -21, -29, -17, -11, -8, -6, -7, -10, -14, -9, -6, -5, -4,
];

Future<void> _shootRecorder(
  WidgetTester tester, {
  required Size size,
  required bool pearl,
  required double textScale,
  required _RecorderState state,
  bool highContrast = false,
  bool reduceMotion = false,
  _Pointer pointer = _Pointer.none,
}) async {
  _sizeView(tester, size);
  final backend = FakeRecorderBackend();
  final capture = FakeAudioCapture()..result = FakeRecordedAudio();
  final clock = FakeStopwatch();
  if (state == _RecorderState.requesting) {
    capture.microphoneGate = Completer<MicrophoneAccess>();
  }
  if (state == _RecorderState.unavailable) {
    capture.support = const CaptureSupport.unsupported(
      reason:
          'This browser cannot record MP4/AAC audio, which is the only '
          'format YO Voice can publish a Voice Moment in.',
      action: 'Open YO Voice in Chrome, Edge or Safari to record.',
    );
  }
  await tester.pumpWidget(
    _host(
      RecordVoiceMomentScreen(
        recorder: VoiceMomentRecorder(
          backend: backend,
          capture: capture,
          clock: clock,
        ),
        momentService: StubMomentService(),
        previewPlayerFactory: FakePreviewAudioPlayer.new,
      ),
      pearl: pearl,
      textScale: textScale,
      size: size,
      highContrast: highContrast,
      reduceMotion: reduceMotion,
    ),
  );
  await tester.pumpAndSettle();

  Future<void> tapRecord() async {
    final mic = find.byIcon(Icons.mic_rounded);
    await tester.ensureVisible(mic);
    await tester.pump();
    await tester.tap(mic, warnIfMissed: false);
    await tester.pump();
    await tester.pump();
  }

  switch (state) {
    case _RecorderState.idle || _RecorderState.unavailable:
      break;
    case _RecorderState.requesting:
      await tapRecord();
      await tester.pump(const Duration(milliseconds: 300));
    case _RecorderState.recording || _RecorderState.silent:
      await tapRecord();
      clock.value = const Duration(seconds: 12);
      for (final db
          in state == _RecorderState.silent
              ? List<double>.filled(_speech.length, -60)
              : _speech) {
        // The recording clock moves with the samples (100 ms apart, 2.7 s
        // in all, short of the 3 s silence warning), so the once-a-second
        // level label follows the input the way it does on a device.
        clock.value += const Duration(milliseconds: 100);
        backend.amplitudes.add(Amplitude(current: db, max: 0));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 300));
    case _RecorderState.review:
      await tapRecord();
      clock.value = const Duration(seconds: 12);
      for (final db in _speech) {
        backend.amplitudes.add(Amplitude(current: db, max: 0));
      }
      await tester.pump(const Duration(milliseconds: 250));
      final stop = find.byIcon(Icons.stop_rounded);
      await tester.ensureVisible(stop);
      await tester.pump();
      await tester.tap(stop, warnIfMissed: false);
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
  }
  // Frame the stage, not wherever the scroll happened to land.
  final scroll = find.byKey(const ValueKey('voice-moment-body-scroll'));
  if (scroll.evaluate().isNotEmpty && state != _RecorderState.review) {
    final scrollable = find.descendant(
      of: scroll,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable.first).position;
    final bead = find.byKey(const ValueKey('voice-record-bead'));
    if (bead.evaluate().isNotEmpty) {
      await tester.ensureVisible(bead);
      await tester.pump(const Duration(milliseconds: 250));
    } else {
      position.jumpTo(0);
      await tester.pump();
    }
  }

  TestGesture? mouse;
  switch (pointer) {
    case _Pointer.none:
      break;
    case _Pointer.focus:
      await _focusOwnerOf(tester, find.byIcon(Icons.mic_rounded));
    case _Pointer.hover:
      mouse = await _hover(tester, find.byIcon(Icons.mic_rounded));
  }

  final stateName = switch (state) {
    _RecorderState.idle => 'idle',
    _RecorderState.requesting => 'requesting',
    _RecorderState.recording => 'recording',
    _RecorderState.silent => 'recording-silent',
    _RecorderState.review => 'review',
    _RecorderState.unavailable => 'unavailable',
  };
  final name = _name(
    'recorder',
    size.width,
    pearl,
    textScale,
    switch (pointer) {
      _Pointer.none => stateName,
      _Pointer.focus => '$stateName-focus',
      _Pointer.hover => '$stateName-hover',
    },
    highContrast: highContrast,
    reduceMotion: reduceMotion,
  );
  await _shoot(tester, name);
  _report(tester, name);
  await mouse?.removePointer();

  if (state == _RecorderState.requesting) {
    final cancel = find.text('Anuluj');
    if (cancel.evaluate().isNotEmpty) {
      await tester.tap(cancel, warnIfMissed: false);
      await tester.pump();
    }
    capture.microphoneGate!.complete(const MicrophoneAccess.granted());
    await tester.pumpAndSettle();
  }
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 50));
  tester.takeException();
}

// ---------------------------------------------------------------------------
// Yeels
// ---------------------------------------------------------------------------

const _reelCaptions = <String>[
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
      caption: _reelCaptions[index - 1],
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

/// The viewer's own Yeel for the "Twoje Yeels" pool: same fixture, the
/// signed-in account as its author.
Map<String, Object?> _ownReelWire(int index) => <String, Object?>{
  ..._reelWire(index),
  'id': 'own_$index',
  'authorId': 'me',
  'authorName': 'Kamil',
  'sortKey': '${1725000000000 + index}_own_$index',
  'likeCount': 5,
  'commentCount': 1,
};

ReelService _reelService({String? viewerName, bool ownEmpty = false}) =>
    ReelService(
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
          uid: 'me',
          displayName: viewerName,
          isEmailVerified: true,
        ),
      ),
      callableInvoker: (name, payload) async {
        switch (name) {
          case 'listReelsV2':
            return <Object?, Object?>{
              'schemaVersion': 2,
              'items': payload['scope'] == 'own'
                  ? <Object?>[if (!ownEmpty) _ownReelWire(2)]
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
              'comments': <Object?>[],
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

MockFirebaseAuth _authMe() => MockFirebaseAuth(
  signedIn: true,
  mockUser: MockUser(uid: 'me', isEmailVerified: true),
);

FollowService _follows() => FollowService(
  firestore: FakeFirebaseFirestore(),
  auth: _authMe(),
  mutationInvoker: (_) async => <String, dynamic>{},
);

/// Flat, light footage with a darker foot: the worst case for white chrome
/// at the top, and the dark end the timeline has to read against below.
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

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shootYeels(
  WidgetTester tester, {
  required Size size,
  required bool pearl,
  required double textScale,
  bool highContrast = false,
  _Pointer pointer = _Pointer.none,
}) async {
  _sizeView(tester, size);
  await tester.pumpWidget(
    _host(
      MomentsScreen(
        key: UniqueKey(),
        isRootTab: true,
        initialFormat: YoMomentsFormat.reels,
        reelService: _reelService(),
        reelVideoBuilder: _footage,
        followService: _follows(),
        onCreateReel: () async {},
      ),
      pearl: pearl,
      textScale: textScale,
      size: size,
      highContrast: highContrast,
    ),
  );
  await _settle(tester);
  await _decodeAssetImages(tester);
  TestGesture? mouse;
  switch (pointer) {
    case _Pointer.none:
      break;
    case _Pointer.focus:
      // The `+` over media: the glyph sits inside the control's own tap
      // region, so its nearest focus node is the control's.
      await _focusOwnerOf(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('moments-create-cta')),
          matching: find.byIcon(Icons.add_rounded),
        ),
      );
    case _Pointer.hover:
      final plate = find.byType(OverlayPlate);
      final icon = tester.widget<OverlayPlate>(plate.first).icon;
      // ignore: avoid_print
      print('hovering the media plate with ${icon.codePoint}');
      mouse = await _hover(tester, plate);
  }
  final name = _name(
    'moments-yeels',
    size.width,
    pearl,
    textScale,
    switch (pointer) {
      _Pointer.none => 'populated',
      _Pointer.focus => 'create-focus',
      _Pointer.hover => 'plate-hover',
    },
    highContrast: highContrast,
  );
  await _shoot(tester, name);
  _report(tester, name);
  await mouse?.removePointer();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 20));
}

/// The Yeels stage composed the way YO Moments hosts it — the page scenery,
/// the immersive stage with the YO Moments header below 1100, the wide
/// header over the card stage from 1100 — with a real (fake-engine) video
/// playback so the timeline can be scrubbed: once while the finger is down,
/// once after it lets go at 40 %.
Future<void> _shootScrub(
  WidgetTester tester, {
  required Size size,
  required bool pearl,
  required double textScale,
  bool highContrast = false,
}) async {
  _sizeView(tester, size);
  final players = FakeReelPlayers();
  await tester.pumpWidget(
    _host(
      Builder(
        builder: (context) => Scaffold(
          backgroundColor: context.appPalette.background,
          body: YoPageBackground(
            section: YoPageSection.moments,
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final layout = YoMomentsLayout.of(
                    constraints.maxWidth,
                    textScale: MediaQuery.textScalerOf(context).scale(1),
                  );
                  final immersive = !layout.showsLocalPanel;
                  final feed = ReelsFeedScreen(
                    embedded: true,
                    immersive: immersive,
                    immersiveHeader: buildImmersiveMomentsHeader(
                      context,
                      showBack: false,
                      selectedFormat: YoMomentsFormat.reels,
                      onFormatSelected: (_) {},
                      onCreate: () {},
                    ),
                    service: _reelService(),
                    friendService: stageFriendService(viewerUid: 'me'),
                    onCreate: () async {},
                    audioPlaybackFactory: FakeReelAudioPlayback.new,
                    videoPlaybackFactory: (uri, reel) => players.of(reel.id),
                    videoBuilder: _footage,
                  );
                  if (immersive) return feed;
                  return Column(
                    children: <Widget>[
                      ResponsiveContentFrame(
                        width: ResponsiveContentWidth.feed,
                        fillHeight: false,
                        child: YoMomentsHeader(
                          selectedFormat: YoMomentsFormat.reels,
                          onFormatSelected: (_) {},
                          gutter: layout.gutter,
                          onCreate: () {},
                        ),
                      ),
                      Expanded(child: feed),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
      pearl: pearl,
      textScale: textScale,
      size: size,
      highContrast: highContrast,
    ),
  );
  await _settle(tester);
  await _decodeAssetImages(tester);

  Finder inCard(Finder finder) =>
      find.descendant(of: find.byType(ReelCard), matching: finder).first;
  final bandFinder = inCard(
    find.byKey(const ValueKey<String>('reel-progress-scrub')),
  );
  final barFinder = inCard(find.byKey(reelProgressBarKey));
  if (bandFinder.evaluate().isEmpty || barFinder.evaluate().isEmpty) {
    // ignore: avoid_print
    print('SKIP scrub ${size.width.toInt()}: no band on this stage');
    return;
  }
  final band = tester.getRect(bandFinder);
  final bar = tester.getRect(barFinder);
  final gesture = await tester.startGesture(
    Offset(bar.left + bar.width * .1, band.bottom - 4),
  );
  await gesture.moveTo(Offset(bar.left + bar.width * .4, band.bottom - 4));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  final dragging = _name(
    'moments-yeels',
    size.width,
    pearl,
    textScale,
    'scrubbing',
    highContrast: highContrast,
  );
  await _shoot(tester, dragging);
  _report(tester, dragging);
  await gesture.up();
  await _settle(tester);
  final played = _name(
    'moments-yeels',
    size.width,
    pearl,
    textScale,
    'played',
    highContrast: highContrast,
  );
  await _shoot(tester, played);
  _report(tester, played);
  // The played box's key is a plain string key, so the same file also runs
  // on the pre-refine base, where the fill had no key.
  final playedBox = find.descendant(
    of: find.byType(ReelCard),
    matching: find.byKey(const ValueKey<String>('reel-progress-played')),
  );
  if (playedBox.evaluate().isNotEmpty) {
    // ignore: avoid_print
    print(
      'played fraction ≈ '
      '${(tester.getSize(playedBox.first).width / bar.width).toStringAsFixed(2)}',
    );
  }
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 20));
}

// ---------------------------------------------------------------------------
// Y3 — the one-row Yeels chrome
// ---------------------------------------------------------------------------

enum _Y3Focus { none, avatar, back, sound, tabHover }

/// The real YO Moments screen on Yeels, over the light footage panel, in
/// Discover or — after a real tap on the viewer's avatar — in "Twoje
/// Yeels". [pushed] opens it as a route above a start page (the host's Back
/// plate leads the row); [ownEmpty] gives the viewer no Yeels of their own.
/// The 1440 frames prove the wide header and panel are unchanged.
Future<void> _shootY3(
  WidgetTester tester, {
  required Size size,
  required bool pearl,
  required double textScale,
  bool own = false,
  bool ownEmpty = false,
  bool pushed = false,
  bool highContrast = false,
  _Y3Focus focus = _Y3Focus.none,
}) async {
  _sizeView(tester, size);
  final navigator = GlobalKey<NavigatorState>();
  Widget moments() => MomentsScreen(
    key: UniqueKey(),
    isRootTab: !pushed,
    initialFormat: YoMomentsFormat.reels,
    reelService: _reelService(viewerName: 'Kamil', ownEmpty: ownEmpty),
    reelVideoBuilder: _footage,
    followService: _follows(),
    onCreateReel: () async {},
  );
  await tester.pumpWidget(
    _host(
      pushed
          ? Navigator(
              key: navigator,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: SizedBox.expand()),
              ),
            )
          : moments(),
      pearl: pearl,
      textScale: textScale,
      size: size,
      highContrast: highContrast,
    ),
  );
  if (pushed) {
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => moments()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }
  await _settle(tester);
  await _decodeAssetImages(tester);
  final avatar = find.byKey(const ValueKey<String>('reels-own-scope'));
  if (own) {
    if (avatar.evaluate().isNotEmpty) {
      await tester.tap(avatar);
    } else {
      // From the local-panel width the pool is a panel row, as today.
      await tester.tap(find.byKey(const ValueKey<String>('reels-own-filter')));
    }
    await _settle(tester);
    // A finger tap parks focus on the feed, not on a control; the frame
    // shows the page as a reader sees it.
  }
  TestGesture? mouse;
  switch (focus) {
    case _Y3Focus.none:
      break;
    case _Y3Focus.avatar:
      await _focusOwnerOf(
        tester,
        find.byKey(const ValueKey<String>('reels-own-scope-ring')),
      );
    case _Y3Focus.back:
      await _focusOwnerOf(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey<String>('reels-own-back')),
          matching: find.byType(OverlayPlate),
        ),
      );
    case _Y3Focus.sound:
      await _focusOwnerOf(
        tester,
        find
            .descendant(
              of: find.byKey(const ValueKey<String>('reel-sound-toggle')),
              matching: find.byType(Icon),
            )
            .first,
      );
    case _Y3Focus.tabHover:
      mouse = await _hover(
        tester,
        find.byKey(const ValueKey<String>('yo-moments-format-reels')),
      );
      // The tooltip waits for the pointer to rest.
      await tester.pump(const Duration(seconds: 2));
      await _settleRing(tester);
  }
  final name = _name(
    'y3-yeels',
    size.width,
    pearl,
    textScale,
    <String>[
      if (pushed) 'pushed',
      if (size.width == 800) '800x${size.height.toInt()}',
      own ? (ownEmpty ? 'own-empty' : 'own') : 'discover',
      if (focus != _Y3Focus.none)
        focus == _Y3Focus.tabHover ? 'tab-hover' : '${focus.name}-focus',
    ].join('-'),
    highContrast: highContrast,
  );
  await _shoot(tester, name);
  _report(tester, name);
  await mouse?.removePointer();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 20));
}

// ---------------------------------------------------------------------------
// Głos canvas "+" and the create sheet
// ---------------------------------------------------------------------------

VoiceMoment _moment(String id, String author, String caption, int hours) {
  final createdAt = DateTime.now().subtract(Duration(hours: hours));
  return VoiceMoment(
    id: id,
    authorId: author.toLowerCase(),
    authorName: author,
    authorPhotoUrl: null,
    caption: caption,
    audioUrl: 'https://cdn.example/$id.m4a',
    durationSeconds: 42,
    likeCount: 12,
    commentCount: 3,
    isPublished: true,
    createdAt: createdAt,
    expiresAt: createdAt.add(const Duration(hours: 24)),
    schemaVersion: 2,
    status: 'published',
    isDeleted: false,
  );
}

final _voiceFeed = <VoiceMoment>[
  _moment('v1', 'Maja', 'Zanim obudzi się miasto.', 2),
  _moment('v2', 'Kamil', 'Mała rzecz, dobry dzień.', 5),
];

class _StaticDiscovery implements MomentDiscoveryService {
  _StaticDiscovery(this.moments);

  final List<VoiceMoment> moments;

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) async => MomentDiscoveryFeed(
    moments: moments,
    fetchedCount: moments.length,
    drops: const <String, MomentDropReason>{},
    seed: seed ?? 0,
    poolExhausted: false,
  );

  @override
  Stream<Map<String, MomentEngagement>> watchEngagement({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
  }) => const Stream<Map<String, MomentEngagement>>.empty();

  @override
  Future<List<VoiceMoment>> topLikedMoments({int limit = 3}) async =>
      moments.take(limit).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuietFeed extends HomeFeedService {
  _QuietFeed({super.firestore, super.auth});

  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) =>
      Stream<List<VoiceMoment>>.value(const <VoiceMoment>[]);

  @override
  Stream<bool> watchLiked(String momentId) => Stream<bool>.value(false);

  @override
  Future<void> toggleLike(String momentId) async {}
}

Future<void> _shootVoice(
  WidgetTester tester, {
  required Size size,
  required bool pearl,
  required bool openSheet,
  double textScale = 1,
  bool highContrast = false,
  _Pointer pointer = _Pointer.none,
}) async {
  _sizeView(tester, size);
  final firestore = FakeFirebaseFirestore();
  final auth = _authMe();
  await tester.pumpWidget(
    _host(
      MomentsScreen(
        key: UniqueKey(),
        isRootTab: true,
        auth: auth,
        discoveryService: _StaticDiscovery(_voiceFeed),
        feedService: _QuietFeed(firestore: firestore, auth: auth),
        followService: FollowService(firestore: firestore, auth: auth),
        reelService: _reelService(),
      ),
      pearl: pearl,
      textScale: textScale,
      size: size,
      highContrast: highContrast,
    ),
  );
  await _settle(tester);
  await _decodeAssetImages(tester);
  if (openSheet) {
    final create = find.byKey(const ValueKey('moments-create-cta')).first;
    await tester.ensureVisible(create);
    await tester.pump();
    await tester.tap(create, warnIfMissed: false);
    await _settle(tester);
  }
  TestGesture? mouse;
  switch (pointer) {
    case _Pointer.none:
      break;
    case _Pointer.focus:
      await _focusOwnerOf(
        tester,
        openSheet
            // The first choice: its label sits inside the tile's own InkWell.
            ? find.descendant(
                of: find.byKey(const ValueKey('create-voice-moment-choice')),
                matching: find.byType(Text),
              )
            // The canvas `+`: its glyph sits inside the control's tap region.
            : find.descendant(
                of: find.byKey(const ValueKey('moments-create-cta')),
                matching: find.byIcon(Icons.add_rounded),
              ),
      );
    case _Pointer.hover:
      mouse = await _hover(
        tester,
        openSheet
            ? find.byKey(const ValueKey('create-reel-choice'))
            : find.byKey(const ValueKey('moments-create-cta')),
      );
  }
  final name = _name(
    openSheet ? 'moments-create-sheet' : 'moments-voice',
    size.width,
    pearl,
    textScale,
    switch ((openSheet, pointer)) {
      (true, _Pointer.none) => 'open',
      (true, _Pointer.focus) => 'tile-focus',
      (true, _Pointer.hover) => 'tile-hover',
      (false, _Pointer.none) => 'populated',
      (false, _Pointer.focus) => 'create-focus',
      (false, _Pointer.hover) => 'create-hover',
    },
    highContrast: highContrast,
  );
  await _shoot(tester, name);
  _report(tester, name);
  await mouse?.removePointer();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 20));
}

/// `flutter_test` turns every `BoxShadow` blur off for golden stability
/// (`debugDisableShadows`), which would draw the record halo and the CTA
/// lift as hard rings. The capture switches it off for each frame, so the
/// light is drawn as a device draws it, and restores it before the
/// binding's end-of-test invariant check.
Future<void> _withShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

void main() {
  late PublicIdentityRepository originalIdentity;

  setUpAll(_loadFonts);

  setUp(() {
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: _authMe(),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentity;
  });

  group('recorder', () {
    for (final size in _sizes) {
      for (final pearl in const <bool>[false, true]) {
        for (final textScale in const <double>[1, 2]) {
          for (final state in _RecorderState.values) {
            final label =
                'recorder ${size.width.toInt()} '
                '${pearl ? 'pearl' : 'dark'} ${textScale}x ${state.name}';
            testWidgets(label, (tester) async {
              await _withShadows(
                () => _shootRecorder(
                  tester,
                  size: size,
                  pearl: pearl,
                  textScale: textScale,
                  state: state,
                ),
              );
            });
          }
        }
      }
    }
    for (final state in const <_RecorderState>[
      _RecorderState.idle,
      _RecorderState.recording,
      _RecorderState.review,
    ]) {
      testWidgets('recorder 390 dark high contrast ${state.name}', (
        tester,
      ) async {
        await _withShadows(
          () => _shootRecorder(
            tester,
            size: _sizes.first,
            pearl: false,
            textScale: 1,
            state: state,
            highContrast: true,
          ),
        );
      });
    }
    testWidgets('recorder 390 dark reduce motion recording', (tester) async {
      await _withShadows(
        () => _shootRecorder(
          tester,
          size: _sizes.first,
          pearl: false,
          textScale: 1,
          state: _RecorderState.recording,
          reduceMotion: true,
        ),
      );
    });
  });

  group('yeels', () {
    for (final size in _sizes) {
      for (final pearl in const <bool>[false, true]) {
        for (final textScale in const <double>[1, 2]) {
          testWidgets('yeels ${size.width.toInt()} ${pearl ? 'pearl' : 'dark'} '
              '${textScale}x', (tester) async {
            await _withShadows(
              () => _shootYeels(
                tester,
                size: size,
                pearl: pearl,
                textScale: textScale,
              ),
            );
          });
        }
      }
    }
    for (final (size, pearl) in <(Size, bool)>[
      (_sizes[0], true),
      (_sizes[1], false),
      (_sizes[1], true),
      (_sizes[2], false),
      (_sizes[2], true),
    ]) {
      testWidgets('yeels ${size.width.toInt()} '
          '${pearl ? 'pearl' : 'dark'} high contrast', (tester) async {
        await _withShadows(
          () => _shootYeels(
            tester,
            size: size,
            pearl: pearl,
            textScale: 1,
            highContrast: true,
          ),
        );
      });
    }
    for (final size in _sizes) {
      for (final pearl in const <bool>[false, true]) {
        for (final textScale in const <double>[1, 2]) {
          testWidgets('yeels scrub ${size.width.toInt()} '
              '${pearl ? 'pearl' : 'dark'} ${textScale}x', (tester) async {
            await _withShadows(
              () => _shootScrub(
                tester,
                size: size,
                pearl: pearl,
                textScale: textScale,
              ),
            );
          });
        }
      }
      testWidgets('yeels scrub ${size.width.toInt()} dark high contrast', (
        tester,
      ) async {
        await _withShadows(
          () => _shootScrub(
            tester,
            size: size,
            pearl: false,
            textScale: 1,
            highContrast: true,
          ),
        );
      });
    }
  });

  group('y3', () {
    const y3Sizes = <Size>[
      Size(320, 640),
      Size(390, 844),
      Size(768, 1024),
      Size(1440, 900),
    ];
    for (final size in y3Sizes) {
      for (final pearl in const <bool>[false, true]) {
        for (final textScale in const <double>[1, 2]) {
          for (final own in const <bool>[false, true]) {
            testWidgets('y3 ${size.width.toInt()} '
                '${pearl ? 'pearl' : 'dark'} ${textScale}x '
                '${own ? 'own' : 'discover'}', (tester) async {
              await _withShadows(
                () => _shootY3(
                  tester,
                  size: size,
                  pearl: pearl,
                  textScale: textScale,
                  own: own,
                ),
              );
            });
          }
        }
      }
    }
    for (final size in <Size>[y3Sizes[1], y3Sizes[2]]) {
      for (final pearl in const <bool>[false, true]) {
        for (final own in const <bool>[false, true]) {
          testWidgets('y3 ${size.width.toInt()} '
              '${pearl ? 'pearl' : 'dark'} high contrast '
              '${own ? 'own' : 'discover'}', (tester) async {
            await _withShadows(
              () => _shootY3(
                tester,
                size: size,
                pearl: pearl,
                textScale: 1,
                own: own,
                highContrast: true,
              ),
            );
          });
        }
        testWidgets('y3 ${size.width.toInt()} '
            '${pearl ? 'pearl' : 'dark'} avatar focus', (tester) async {
          await _withShadows(
            () => _shootY3(
              tester,
              size: size,
              pearl: pearl,
              textScale: 1,
              focus: _Y3Focus.avatar,
            ),
          );
        });
        testWidgets('y3 ${size.width.toInt()} '
            '${pearl ? 'pearl' : 'dark'} own empty', (tester) async {
          await _withShadows(
            () => _shootY3(
              tester,
              size: size,
              pearl: pearl,
              textScale: 1,
              own: true,
              ownEmpty: true,
            ),
          );
        });
        testWidgets('y3 ${size.width.toInt()} '
            '${pearl ? 'pearl' : 'dark'} back focus', (tester) async {
          await _withShadows(
            () => _shootY3(
              tester,
              size: size,
              pearl: pearl,
              textScale: 1,
              own: true,
              focus: _Y3Focus.back,
            ),
          );
        });
      }
    }
  });

  group('y3 review', () {
    for (final textScale in const <double>[1, 2]) {
      for (final own in const <bool>[false, true]) {
        testWidgets('y3 review pushed 320 ${textScale}x '
            '${own ? 'own' : 'discover'}', (tester) async {
          await _withShadows(
            () => _shootY3(
              tester,
              size: const Size(320, 640),
              pearl: false,
              textScale: textScale,
              own: own,
              pushed: true,
            ),
          );
        });
      }
    }
    for (final pearl in const <bool>[false, true]) {
      for (final own in const <bool>[false, true]) {
        testWidgets('y3 review 800x600 ${pearl ? 'pearl' : 'dark'} '
            '${own ? 'own' : 'discover'}', (tester) async {
          await _withShadows(
            () => _shootY3(
              tester,
              size: const Size(800, 600),
              pearl: pearl,
              textScale: 1,
              own: own,
            ),
          );
        });
      }
      testWidgets('y3 review 390 ${pearl ? 'pearl' : 'dark'} sound focus', (
        tester,
      ) async {
        await _withShadows(
          () => _shootY3(
            tester,
            size: const Size(390, 844),
            pearl: pearl,
            textScale: 1,
            focus: _Y3Focus.sound,
          ),
        );
      });
    }
    // Where the 600–1099 stage trades the shallow overlay card for board
    // 08's stacked card: the one-row chrome gives the stage its second row
    // back, so the switch now happens at a lower window height.
    for (final height in const <double>[640, 680, 720]) {
      testWidgets('y3 review 800x${height.toInt()} dark discover', (
        tester,
      ) async {
        await _withShadows(
          () => _shootY3(
            tester,
            size: Size(800, height),
            pearl: false,
            textScale: 1,
          ),
        );
      });
    }
    // Between the ordinary and the accessibility layouts (1.3, 1.5 × text)
    // the row decides by measurement alone: one line while the switch fits,
    // stacked the moment it would be cut.
    for (final width in const <double>[320, 360]) {
      for (final textScale in const <double>[1.3, 1.5]) {
        for (final own in const <bool>[false, true]) {
          testWidgets('y3 review midscale ${width.toInt()} ${textScale}x '
              '${own ? 'own' : 'discover'}', (tester) async {
            await _withShadows(
              () => _shootY3(
                tester,
                size: Size(width, 640),
                pearl: false,
                textScale: textScale,
                own: own,
              ),
            );
          });
        }
      }
    }
    testWidgets('y3 review 768 dark tab hover', (tester) async {
      await _withShadows(
        () => _shootY3(
          tester,
          size: const Size(768, 1024),
          pearl: false,
          textScale: 1,
          focus: _Y3Focus.tabHover,
        ),
      );
    });
    testWidgets('y3 review 390 dark tab hover', (tester) async {
      await _withShadows(
        () => _shootY3(
          tester,
          size: const Size(390, 844),
          pearl: false,
          textScale: 1,
          focus: _Y3Focus.tabHover,
        ),
      );
    });
  });

  group('voice canvas', () {
    for (final size in _sizes) {
      for (final pearl in const <bool>[false, true]) {
        for (final openSheet in const <bool>[false, true]) {
          testWidgets('voice ${size.width.toInt()} ${pearl ? 'pearl' : 'dark'} '
              '${openSheet ? 'sheet' : 'feed'}', (tester) async {
            await _withShadows(
              () => _shootVoice(
                tester,
                size: size,
                pearl: pearl,
                openSheet: openSheet,
              ),
            );
          });
        }
        testWidgets('voice ${size.width.toInt()} '
            '${pearl ? 'pearl' : 'dark'} sheet 2x', (tester) async {
          await _withShadows(
            () => _shootVoice(
              tester,
              size: size,
              pearl: pearl,
              openSheet: true,
              textScale: 2,
            ),
          );
        });
      }
    }
    for (final size in <Size>[_sizes[0], _sizes[1]]) {
      for (final pearl in const <bool>[false, true]) {
        for (final openSheet in const <bool>[false, true]) {
          testWidgets('voice ${size.width.toInt()} ${pearl ? 'pearl' : 'dark'} '
              '${openSheet ? 'sheet' : 'feed'} high contrast', (tester) async {
            await _withShadows(
              () => _shootVoice(
                tester,
                size: size,
                pearl: pearl,
                openSheet: openSheet,
                highContrast: true,
              ),
            );
          });
        }
      }
    }
  });

  group('focus and hover', () {
    for (final pearl in const <bool>[false, true]) {
      final theme = pearl ? 'pearl' : 'dark';
      testWidgets('recorder 1440 $theme idle focus', (tester) async {
        await _withShadows(
          () => _shootRecorder(
            tester,
            size: _sizes[2],
            pearl: pearl,
            textScale: 1,
            state: _RecorderState.idle,
            pointer: _Pointer.focus,
          ),
        );
      });
      for (final pointer in const <_Pointer>[_Pointer.focus, _Pointer.hover]) {
        testWidgets('voice 768 $theme ${pointer.name}', (tester) async {
          await _withShadows(
            () => _shootVoice(
              tester,
              size: _sizes[1],
              pearl: pearl,
              openSheet: false,
              pointer: pointer,
            ),
          );
        });
        testWidgets('sheet 768 $theme ${pointer.name}', (tester) async {
          await _withShadows(
            () => _shootVoice(
              tester,
              size: _sizes[1],
              pearl: pearl,
              openSheet: true,
              pointer: pointer,
            ),
          );
        });
        testWidgets('yeels 768 $theme ${pointer.name}', (tester) async {
          await _withShadows(
            () => _shootYeels(
              tester,
              size: _sizes[1],
              pearl: pearl,
              textScale: 1,
              pointer: pointer,
            ),
          );
        });
      }
    }
    testWidgets('recorder 1440 dark idle hover', (tester) async {
      await _withShadows(
        () => _shootRecorder(
          tester,
          size: _sizes[2],
          pearl: false,
          textScale: 1,
          state: _RecorderState.idle,
          pointer: _Pointer.hover,
        ),
      );
    });
    testWidgets('yeels 1440 dark hover', (tester) async {
      await _withShadows(
        () => _shootYeels(
          tester,
          size: _sizes[2],
          pearl: false,
          textScale: 1,
          pointer: _Pointer.hover,
        ),
      );
    });
    testWidgets('sheet 1440 dark focus', (tester) async {
      await _withShadows(
        () => _shootVoice(
          tester,
          size: _sizes[2],
          pearl: false,
          openSheet: true,
          pointer: _Pointer.focus,
        ),
      );
    });
  });
}
