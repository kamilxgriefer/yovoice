// Developer-only VISUAL capture for refine-look batch 3 ("shared controls")
// on REAL screens — the surfaces where the batch changes pixels:
//
// * device-sessions  — the default YoIconButton (AppBar Back) and Material
//                      Cards (the theme card hairline);
// * server-events    — the Community events board: theme FilterChips
//                      (response and reminder chips, selected / enabled /
//                      disabled);
// * server-new-channel — the workspace's "Nowy kanał" sheet: theme
//                      ChoiceChips (the channel kinds);
// * company-files    — the Company files board's YoEmptyState with its
//                      YoButton primary CTA (the lift);
// * media-review     — the chat's confirm-before-send review WHILE SENDING
//                      (YoButton primary busy + ghost "Anuluj" disabled),
//                      plus pointer-hover shots of the caller-coloured
//                      YoIconButtons (the video play plate, the sheet close).
//
// Every surface is the real widget, reached through its own constructor
// seams with the fakes the widget tests use; nothing is drawn by hand. The
// theme reaches the app exactly as in `lib/app/app.dart`: theme, darkTheme
// and the two high-contrast twins on MaterialApp, with the platform's text
// scale and high-contrast flag set on the test platform dispatcher.
//
// Widths 390 / 768 / 1440, Dark and Pearl, 100 % and 200 % text, plus high
// contrast at 100 % (every width) and 200 % (390). Names follow the spec's
// §11 pattern: <screen>_<width>_<dark|pearl>_pl_<text>_<state>[-hc].png.
//
// flutter_test paints every elevation and BoxShadow as a hard, solid debug
// band (`debugDisableShadows`); the capture switches that off for each
// render, so the primary's lift and the Pearl contact shadows are the real
// soft shadows, and restores it before the binding checks its invariants.
//
// Not a *_test.dart file, so the regular suite ignores it. Run explicitly:
//
//   flutter test test/refine_controls_capture.dart --concurrency=1 \
//     --dart-define=REFINE_CONTROLS_OUT=<dir>
//
// Options (all `--dart-define`):
//   REFINE_CONTROLS_WIDTHS=390,1440   any of 390, 768, 1440 (default: all)
//   REFINE_CONTROLS_SCREENS=company-files,media-review
//                                     a subset of: device-sessions,
//                                     server-events, server-new-channel,
//                                     company-files, media-review
//                                     (default: all; the hover shots run
//                                     with media-review)
//
// The same file runs unchanged against the pre-refine base commit (the
// "before" frames), except that the base has no high-contrast theme twins;
// the capture script strips the two `highContrast*Theme` lines there.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/servers/data/models/server_event.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_voice_device.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/settings/data/services/session_management_service.dart';
import 'package:yovoice/features/settings/presentation/screens/device_sessions_screen.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'server_templates_test.dart' as boards;
import 'server_test_support.dart';
import 'support/material_icons_font.dart';

const _out = String.fromEnvironment(
  'REFINE_CONTROLS_OUT',
  defaultValue: 'test/.screenshots/refine-controls',
);
const _widthsDefine = String.fromEnvironment(
  'REFINE_CONTROLS_WIDTHS',
  defaultValue: '390,768,1440',
);
const _screensDefine = String.fromEnvironment('REFINE_CONTROLS_SCREENS');
const _emojiFont = '/System/Library/Fonts/Apple Color Emoji.ttc';

List<String> _list(String define) => [
  for (final part in define.split(','))
    if (part.trim().isNotEmpty) part.trim(),
];

final Set<int> _widths = _list(_widthsDefine).map(int.parse).toSet();
final Set<String> _screens = _list(_screensDefine).toSet();

bool _wants(String screen, _Variant v) =>
    _widths.contains(v.width.toInt()) &&
    (_screens.isEmpty || _screens.contains(screen));
const String _me = 'me-uid';

final _captureKey = GlobalKey();

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))
    ..addFont(rootBundle.load('assets/fonts/InterVariable-Italic.ttf'));
  await inter.load();
  await loadMaterialIconsFont();
  final emoji = File(_emojiFont);
  if (emoji.existsSync()) {
    final loader = FontLoader('Apple Color Emoji')
      ..addFont(Future.value(ByteData.sublistView(emoji.readAsBytesSync())));
    await loader.load();
  }
}

/// One capture configuration.
class _Variant {
  const _Variant(this.width, this.height, this.dark, this.text, this.hc);

  final double width;
  final double height;
  final bool dark;
  final int text;
  final bool hc;

  String name(String screen, String state) =>
      '${screen}_${width.toInt()}_${dark ? 'dark' : 'pearl'}_pl_${text}_'
      '$state${hc ? '-hc' : ''}';

  double get pixelRatio => width <= 768 ? 2 : 1;
}

const _sizes = <(double, double)>[(390, 844), (768, 1024), (1440, 900)];

/// 390 / 768 / 1440 × Dark / Pearl × {100, 200, 100 high contrast}, plus
/// 200 % high contrast at 390.
final List<_Variant> _matrix = [
  for (final (w, h) in _sizes)
    for (final dark in const [true, false]) ...[
      _Variant(w, h, dark, 100, false),
      _Variant(w, h, dark, 200, false),
      _Variant(w, h, dark, 100, true),
      if (w == 390) _Variant(w, h, dark, 200, true),
    ],
];

/// The pointer-hover shots: 390 and 1440, both themes, 100 % text.
final List<_Variant> _hoverMatrix = [
  for (final (w, h) in const <(double, double)>[(390, 844), (1440, 900)])
    for (final dark in const [true, false]) _Variant(w, h, dark, 100, false),
];

void _configure(WidgetTester tester, _Variant v) {
  tester.view.physicalSize = Size(v.width, v.height);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = v.text / 100;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(highContrast: v.hc);
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
}

Widget _app({required bool dark, required Widget home}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('pl'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  // As lib/app/app.dart hands them over.
  theme: AppTheme.lightTheme,
  darkTheme: AppTheme.darkTheme,
  highContrastTheme: AppTheme.lightHighContrastTheme,
  highContrastDarkTheme: AppTheme.darkHighContrastTheme,
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  // The boundary wraps the Navigator, so sheets and dialogs are in frame.
  builder: (context, navigator) =>
      RepaintBoundary(key: _captureKey, child: navigator),
  home: home,
);

/// A capture test whose render shows the real soft shadows.
///
/// flutter_test swaps every elevation and BoxShadow blur for a hard debug
/// band; evidence must show the real lift, so the flag is off for the whole
/// render and back on before the binding checks its invariants (which it
/// does before any `addTearDown` callback runs).
void _capture(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    debugDisableShadows = false;
    try {
      await body(tester);
    } finally {
      debugDisableShadows = true;
    }
  });
}

/// Frames for layout, streams and the real image decodes. Never
/// `pumpAndSettle`: a busy spinner never settles.
Future<void> _settle(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _shoot(WidgetTester tester, _Variant v, String name) async {
  final exception = tester.takeException();
  if (exception != null) {
    // ignore: avoid_print
    print('$name EXCEPTION: $exception');
  }
  await tester.runAsync(() async {
    final boundary =
        _captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    // Prime the font and icon atlases: without a first raster pass a
    // headless engine can intermittently omit a glyph from the evidence.
    final warmup = await boundary.toImage(pixelRatio: v.pixelRatio);
    warmup.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final image = await boundary.toImage(pixelRatio: v.pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_out/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path} (${image.width}x${image.height})');
    } finally {
      image.dispose();
    }
  });
  expect(exception, isNull, reason: name);
}

// ---------------------------------------------------------------------------
// Surfaces
// ---------------------------------------------------------------------------

Widget _deviceSessions() => DeviceSessionsScreen(
  deviceLabel: 'iPhone',
  service: SessionManagementService(
    currentSessionLoader: () async => CurrentSessionInfo(
      signedInAt: DateTime(2026, 9, 25, 21, 14),
      providerLabels: const ['Google'],
    ),
  ),
);

/// A Community server (id `s`) with its template channels.
TestServerRepository _communityRepository() {
  final repository = TestServerRepository()
    ..servers = [boards.boardServer(ServerType.community, members: 184)]
    ..channels = boards.boardChannels(ServerType.community);
  final friday = DateTime(2026, 10, 2, 19);
  final sunday = DateTime(2026, 10, 4, 11);
  ServerEvent event(
    String id,
    String title,
    DateTime startsAt, {
    required int going,
    required int maybe,
    required int reminders,
  }) => ServerEvent(
    id: id,
    serverId: 's',
    channelId: 'events',
    title: title,
    description: '',
    startsAt: startsAt,
    endsAt: startsAt.add(const Duration(hours: 2)),
    timeZone: 'Europe/Warsaw',
    status: ServerEventStatus.scheduled,
    authorId: 'owner',
    revision: 1,
    eventKind: ServerEventKind.communityEvent,
    serverType: ServerType.community,
    reminderOptInEnabled: true,
    goingCount: going,
    maybeCount: maybe,
    reminderCount: reminders,
  );
  repository.events = [
    event('e1', 'Wieczór z książką', friday, going: 12, maybe: 4, reminders: 9),
    event(
      'e2',
      'Niedzielne śniadanie',
      sunday,
      going: 5,
      maybe: 2,
      reminders: 3,
    ),
  ];
  repository.eventResponses['e1'] = const ServerEventAttendance(
    response: ServerEventResponse.going,
    reminderRequested: true,
  );
  return repository;
}

Widget _workspace(TestServerRepository repository, String channelId) =>
    ServerWorkspaceScreen(
      key: UniqueKey(),
      serverId: 's',
      repository: repository,
      isRootTab: true,
      initialChannelId: channelId,
      chatService: boards.boardChat(),
      connector: FakeServerMediaConnector(),
    );

TestServerRepository _companyRepository() => TestServerRepository()
  ..servers = [boards.boardServer(ServerType.company, members: 23)]
  ..channels = boards.boardChannels(ServerType.company);

// --- the chat host for the media review (as test/nb_confirm_upload_capture)

class _CaptureMessageService extends MessageService {
  _CaptureMessageService(FakeFirebaseFirestore firestore, MockFirebaseAuth auth)
    : super(firestore: firestore, auth: auth);

  /// The outbox hand-off never finishes, so the review stays in "sending".
  final pending = Completer<String>();

  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      Stream.value(const <Message>[]);

  @override
  Stream<bool> watchTyping({
    required String conversationId,
    required String otherUserId,
  }) => Stream.value(false);

  @override
  Stream<ChatPresence> watchUserPresence(String userId) =>
      Stream.value(const ChatPresence(isOnline: true, lastSeen: null));

  @override
  Future<void> markConversationRead(String conversationId) async {}

  @override
  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) async {}

  @override
  Future<String> enqueueImageMessage({
    required String conversationId,
    required XFile image,
  }) => pending.future;
}

class _StillVideoController implements VideoPlayerController {
  _StillVideoController(Duration duration)
    : _state = ValueNotifier(VideoPlayerValue(duration: duration));

  final ValueNotifier<VideoPlayerValue> _state;

  @override
  VideoPlayerValue get value => _state.value;

  @override
  set value(VideoPlayerValue value) => _state.value = value;

  @override
  int get playerId => VideoPlayerController.kUninitializedPlayerId;

  @override
  Future<void> initialize() async {
    value = value.copyWith(
      isInitialized: true,
      size: const Size(1080, 1920),
      position: const Duration(seconds: 7),
    );
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> setVolume(double volume) async {
    value = value.copyWith(volume: volume);
  }

  @override
  void addListener(VoidCallback listener) => _state.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _state.removeListener(listener);

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A real 1600×1200 PNG: a warm evening gradient with a horizon.
Future<Uint8List> _photoBytes(WidgetTester tester) async {
  final bytes = await tester.runAsync(() async {
    const size = Size(1600, 1200);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          const [AppColors.contrastInk, AppColors.voice, AppColors.warning],
          const [0, .62, 1],
        ),
    );
    canvas.drawCircle(
      const Offset(1100, 760),
      150,
      Paint()..color = AppColors.vipGold,
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, 900, 1600, 300),
      Paint()..color = AppColors.contrastInk,
    );
    final image = await recorder.endRecording().toImage(1600, 1200);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  return bytes!;
}

Widget _chat({
  DirectMessagePhotoPicker? photoPicker,
  DirectMessageVideoPicker? videoPicker,
}) {
  final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me));
  return ChatScreen(
    conversationId: '${_me}_ola',
    otherUserId: 'ola',
    otherDisplayName: 'Ola Nowak',
    otherEmail: '',
    otherPhotoUrl: '',
    messageService: _CaptureMessageService(FakeFirebaseFirestore(), auth),
    auth: auth,
    photoPicker: photoPicker,
    videoPicker: videoPicker,
    videoInspector: (_) async => const Duration(seconds: 42),
    videoPreviewControllerFactory: (_) =>
        _StillVideoController(const Duration(seconds: 42)),
  );
}

Future<void> _openMedia(WidgetTester tester, String action) async {
  await tester.tap(find.byTooltip('Dodaj zdjęcie lub film'));
  await _settle(tester, frames: 10);
  await tester.tap(find.text(action));
  await _settle(tester, frames: 10);
}

Future<Widget> _photoChat(WidgetTester tester) async {
  final png = await _photoBytes(tester);
  return _chat(
    photoPicker: (_) async => XFile.fromData(
      png,
      name: 'IMG_2043.png',
      mimeType: 'image/png',
      length: png.length,
    ),
  );
}

// ---------------------------------------------------------------------------

void main() {
  late PublicIdentityRepository originalIdentityRepository;

  setUpAll(_loadFonts);

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    originalIdentityRepository = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
    debugServerVoiceDeviceOverride = FakeServerVoiceDevice();
    // Connectivity is a UI hint on the files and events boards; answer as
    // online instead of throwing MissingPluginException.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? <String>['wifi'] : null,
    );
    messenger.setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(
        onListen: (arguments, events) => events.success(<String>['wifi']),
      ),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentityRepository;
    debugServerVoiceDeviceOverride = null;
  });

  for (final v in _matrix) {
    if (_wants('device-sessions', v)) {
      _capture(v.name('device-sessions', 'populated'), (tester) async {
        _configure(tester, v);
        await tester.pumpWidget(_app(dark: v.dark, home: _deviceSessions()));
        await _settle(tester);
        await _shoot(tester, v, v.name('device-sessions', 'populated'));
      });
    }

    if (_wants('server-events', v)) {
      _capture(v.name('server-events', 'populated'), (tester) async {
        _configure(tester, v);
        await tester.pumpWidget(
          _app(
            dark: v.dark,
            home: _workspace(_communityRepository(), 'events'),
          ),
        );
        await _settle(tester);
        await _shoot(tester, v, v.name('server-events', 'populated'));
      });
    }

    if (_wants('server-new-channel', v)) {
      _capture(v.name('server-new-channel', 'sheet'), (tester) async {
        _configure(tester, v);
        await tester.pumpWidget(
          _app(
            dark: v.dark,
            home: _workspace(_communityRepository(), 'general'),
          ),
        );
        await _settle(tester);
        // On a phone the channel list (and its "Dodaj kanał") lives in the
        // "Kanały" sheet.
        final add = find.byKey(const ValueKey('server-add-channel'));
        final panel = find.byKey(const ValueKey('server-panel'));
        if (add.hitTestable().evaluate().isEmpty &&
            panel.hitTestable().evaluate().isEmpty) {
          await tester.tap(find.byKey(const ValueKey('server-open-channels')));
          await _settle(tester, frames: 10);
        }
        // The panel is a lazy ListView: at 200 % text "Dodaj kanał" sits
        // past its cache extent and is not built until the list scrolls.
        await tester.scrollUntilVisible(
          add,
          160,
          scrollable: find
              .descendant(of: panel.last, matching: find.byType(Scrollable))
              .first,
        );
        await _settle(tester, frames: 4);
        await tester.tap(add);
        await _settle(tester);
        expect(
          find.byKey(const ValueKey('server-create-channel-sheet')),
          findsOneWidget,
        );
        await _shoot(tester, v, v.name('server-new-channel', 'sheet'));
      });
    }

    if (_wants('company-files', v)) {
      _capture(v.name('company-files', 'empty'), (tester) async {
        _configure(tester, v);
        await tester.pumpWidget(
          _app(dark: v.dark, home: _workspace(_companyRepository(), 'files')),
        );
        await _settle(tester);
        await _shoot(tester, v, v.name('company-files', 'empty'));
      });
    }

    if (_wants('media-review', v)) {
      _capture(v.name('media-review', 'sending'), (tester) async {
        _configure(tester, v);
        final chat = await _photoChat(tester);
        await tester.pumpWidget(_app(dark: v.dark, home: chat));
        await _settle(tester);
        await _openMedia(tester, 'Biblioteka zdjęć');
        await tester.tap(find.byKey(const ValueKey('yo-media-review-send')));
        // ~0.5 s into the spinner's cycle: a long, legible arc.
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await _shoot(tester, v, v.name('media-review', 'sending'));
      });
    }
  }

  for (final v in _hoverMatrix) {
    if (_wants('media-review', v)) {
      _capture(v.name('media-review', 'hover-play'), (tester) async {
        _configure(tester, v);
        await tester.pumpWidget(
          _app(
            dark: v.dark,
            home: _chat(
              videoPicker: (_) async => XFile.fromData(
                Uint8List(12 * 1024 * 1024 + 400 * 1024),
                name: 'VID_0419.mp4',
                mimeType: 'video/mp4',
              ),
            ),
          ),
        );
        await _settle(tester);
        await _openMedia(tester, 'Biblioteka filmów');
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(
          location: tester.getCenter(
            find.byKey(const ValueKey('yo-media-review-play')),
          ),
        );
        await _settle(tester, frames: 8);
        await _shoot(tester, v, v.name('media-review', 'hover-play'));
        await mouse.removePointer();
      });
    }

    if (_wants('media-review', v)) {
      _capture(v.name('media-review', 'hover-close'), (tester) async {
        _configure(tester, v);
        final chat = await _photoChat(tester);
        await tester.pumpWidget(_app(dark: v.dark, home: chat));
        await _settle(tester);
        await _openMedia(tester, 'Biblioteka zdjęć');
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(
          location: tester.getCenter(
            find.byKey(const ValueKey('modal-sheet-close')),
          ),
        );
        await _settle(tester, frames: 8);
        await _shoot(tester, v, v.name('media-review', 'hover-close'));
        await mouse.removePointer();
      });
    }
  }
}
