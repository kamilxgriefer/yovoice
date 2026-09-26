// Developer-only visual capture for "confirm before upload" (ADR-212): the
// picked-media review opened from the real ChatScreen (Photo library, Video
// library) and from the real Company files board, at 390 and 1440 px, Dark
// and Pearl, Polish, text 1.0.
//
// Technique of `test/slim_chats_capture.dart`: real widgets, fixtures through
// the screens' own constructor seams, an exact viewport and the real product
// fonts (Inter + Material Icons). The capture boundary wraps the Navigator,
// so the modal review is in the frame together with the screen under it.
//
// It is NOT a test and deliberately does not end in `_test.dart`, so the
// regular suite never writes artifacts. Run it explicitly:
//
//   flutter test test/nb_confirm_upload_capture.dart
//
// PNGs land OUTSIDE git, in the evidence folder named below, or in the
// directory given by the NB_FRAMES_DIR environment variable.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
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
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_company_file_service.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_company_files_board.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'server_test_support.dart';

const String _me = 'me-uid';
const String _defaultOut =
    '/Users/kamil/Documents/GitHub/yovoice-evidence/2026-09-19/next-build/confirm-upload';

final _captureKey = GlobalKey();

String _outDir() {
  final configured = Platform.environment['NB_FRAMES_DIR'];
  return configured == null || configured.trim().isEmpty
      ? _defaultOut
      : configured.trim();
}

String _resolveMaterialFontRoot() {
  final configuredRoot = Platform.environment['FLUTTER_ROOT'];
  if (configuredRoot != null) {
    final configured = '$configuredRoot/bin/cache/artifacts/material_fonts';
    if (File('$configured/MaterialIcons-Regular.otf').existsSync()) {
      return configured;
    }
  }
  var directory = File(Platform.resolvedExecutable).parent;
  while (directory.parent.path != directory.path) {
    final candidate = '${directory.path}/bin/cache/artifacts/material_fonts';
    if (File('$candidate/MaterialIcons-Regular.otf').existsSync()) {
      return candidate;
    }
    directory = directory.parent;
  }
  throw StateError('Could not locate Flutter material fonts.');
}

Future<ByteData> _read(String path) async {
  final bytes = Uint8List.fromList(File(path).readAsBytesSync());
  return ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
}

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(_read('assets/fonts/InterVariable.ttf'))
    ..addFont(_read('assets/fonts/InterVariable-Italic.ttf'));
  await inter.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(_read('${_resolveMaterialFontRoot()}/MaterialIcons-Regular.otf'));
  await icons.load();
}

Future<void> _capturePng(
  WidgetTester tester,
  String filename, {
  required double pixelRatio,
}) async {
  await tester.runAsync(() async {
    final boundary =
        _captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final warmup = await boundary.toImage(pixelRatio: pixelRatio);
    warmup.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${_outDir()}/$filename.png');
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
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Lets real image decoding finish (it runs outside the fake clock).
Future<void> _decode(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A real 1600×1200 PNG: a warm evening gradient with a horizon, so the
/// preview shows actual decoded pixels, not a placeholder.
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

class _CaptureMessageService extends MessageService {
  _CaptureMessageService(FakeFirebaseFirestore firestore, MockFirebaseAuth auth)
    : super(firestore: firestore, auth: auth);

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

Widget _host({required ThemeData theme, required Widget child}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: theme,
  locale: const Locale('pl'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, navigator) =>
      RepaintBoundary(key: _captureKey, child: navigator),
  home: child,
);

Widget _chat({
  DirectMessagePhotoPicker? photoPicker,
  DirectMessageVideoPicker? videoPicker,
  Duration? videoDuration,
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
    videoInspector: (_) async => videoDuration ?? const Duration(seconds: 1),
    videoPreviewControllerFactory: (_) =>
        _StillVideoController(videoDuration ?? const Duration(seconds: 1)),
  );
}

Future<void> _openMedia(WidgetTester tester, String action) async {
  await tester.tap(find.byTooltip('Dodaj zdjęcie lub film'));
  await _settle(tester);
  await tester.tap(find.text(action));
  await _settle(tester);
}

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
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentityRepository;
  });

  for (final (width, height) in const <(double, double)>[
    (390, 844),
    (1440, 900),
  ]) {
    for (final (themeName, theme) in <(String, ThemeData)>[
      ('dark', AppTheme.darkTheme),
      ('pearl', AppTheme.lightTheme),
    ]) {
      final suffix = '${width.toInt()}_${themeName}_pl';
      final pixelRatio = width < 600 ? 2.0 : 1.0;

      void viewport(WidgetTester tester) {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
      }

      testWidgets('dm photo $suffix', (tester) async {
        viewport(tester);
        final png = await _photoBytes(tester);
        await tester.pumpWidget(
          _host(
            theme: theme,
            child: _chat(
              photoPicker: (_) async => XFile.fromData(
                png,
                name: 'IMG_2043.png',
                mimeType: 'image/png',
                length: png.length,
              ),
            ),
          ),
        );
        await _settle(tester);
        await _openMedia(tester, 'Biblioteka zdjęć');
        await _decode(tester);
        await _capturePng(tester, 'dm_photo_$suffix', pixelRatio: pixelRatio);
        expect(tester.takeException(), isNull);
      });

      testWidgets('dm video ok $suffix', (tester) async {
        viewport(tester);
        await tester.pumpWidget(
          _host(
            theme: theme,
            child: _chat(
              videoPicker: (_) async => XFile.fromData(
                Uint8List(12 * 1024 * 1024 + 400 * 1024),
                name: 'VID_0419.mp4',
                mimeType: 'video/mp4',
              ),
              videoDuration: const Duration(seconds: 42),
            ),
          ),
        );
        await _settle(tester);
        await _openMedia(tester, 'Biblioteka filmów');
        await _capturePng(
          tester,
          'dm_video_ok_$suffix',
          pixelRatio: pixelRatio,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('dm video too long $suffix', (tester) async {
        viewport(tester);
        await tester.pumpWidget(
          _host(
            theme: theme,
            child: _chat(
              videoPicker: (_) async => XFile.fromData(
                Uint8List(30 * 1024 * 1024),
                name: 'VID_0420.mp4',
                mimeType: 'video/mp4',
              ),
              videoDuration: const Duration(seconds: 94),
            ),
          ),
        );
        await _settle(tester);
        await _openMedia(tester, 'Biblioteka filmów');
        await _capturePng(
          tester,
          'dm_video_too_long_$suffix',
          pixelRatio: pixelRatio,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('company pdf $suffix', (tester) async {
        viewport(tester);
        await tester.pumpWidget(
          _host(
            theme: theme,
            child: Scaffold(
              body: ServerCompanyFilesBoard(
                server: const Server(
                  id: 's',
                  name: 'Studio North',
                  description: 'Zespół',
                  ownerId: 'owner',
                  type: ServerType.company,
                  privacy: ServerPrivacy.inviteOnly,
                  defaultChannelId: 'files',
                  schemaVersion: 1,
                  templateVersion: 1,
                  revision: 1,
                  activationState: 'active',
                ),
                channel: const ServerChannel(
                  id: 'files',
                  serverId: 's',
                  name: 'Pliki',
                  kind: ServerChannelKind.files,
                  position: 1,
                  access: ServerChannelAccess.members,
                  schemaVersion: 1,
                  revision: 1,
                  aclRevision: 1,
                ),
                repository: TestServerRepository()
                  ..myRole = ServerMemberRole.member,
                role: ServerMemberRole.member,
                online: Stream.value(true),
                pickFile: () async => ServerCompanyFileSelection(
                  displayName:
                      'Plan kwartalny Q4 — budżet, zatrudnienie i harmonogram wdrożenia.pdf',
                  contentType: 'application/pdf',
                  bytes: Uint8List(3 * 1024 * 1024 + 300 * 1024),
                ),
              ),
            ),
          ),
        );
        await _settle(tester);
        await tester.tap(find.text('Dodaj plik').first);
        await _settle(tester);
        await _capturePng(tester, 'company_pdf_$suffix', pixelRatio: pixelRatio);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
