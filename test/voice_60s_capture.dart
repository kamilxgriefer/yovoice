// Developer-only visual capture for the voice recorders' 60 s / 30 s limit:
// the direct-message voice recorder sheet (from the real ChatScreen) in its
// final seconds with the countdown, and after the automatic stop with the
// take kept ready to send; the Family Memory composer in the same two states.
// 390 and 1440 px, Dark and Pearl, Polish, text 1.0.
//
// Technique of `test/nb_confirm_upload_capture.dart`: real widgets, fixtures
// through the screens' own constructor seams (the recorder factory drives a
// fake backend and clock), an exact viewport and the real product fonts.
//
// It is NOT a test and deliberately does not end in `_test.dart`, so the
// regular suite never writes artifacts. Run it explicitly:
//
//   flutter test test/voice_60s_capture.dart
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

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/theme/server_identity.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_family_memory_album.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'server_family_memory_album_test.dart' as album;
import 'voice_moment_test_doubles.dart';

const String _me = 'me-uid';
const String _defaultOut =
    '/Users/kamil/Documents/GitHub/yovoice-evidence/2026-09-25/voice-60s';

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
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
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

VoiceMomentRecorder Function() _recorder(FakeStopwatch clock) =>
    () => VoiceMomentRecorder(
      backend: FakeRecorderBackend(),
      capture: FakeAudioCapture(),
      clock: clock,
    );

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

      testWidgets('dm voice countdown and auto-stop $suffix', (tester) async {
        viewport(tester);
        final clock = FakeStopwatch();
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: _me),
        );
        await tester.pumpWidget(
          _host(
            theme: theme,
            child: ChatScreen(
              conversationId: '${_me}_ola',
              otherUserId: 'ola',
              otherDisplayName: 'Ola Nowak',
              otherEmail: '',
              otherPhotoUrl: '',
              messageService: _CaptureMessageService(
                FakeFirebaseFirestore(),
                auth,
              ),
              auth: auth,
              voiceRecorderFactory: _recorder(clock),
            ),
          ),
        );
        await _settle(tester);
        await tester.tap(find.byTooltip('Nagraj wiadomość głosową'));
        await _settle(tester);
        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Rozpocznij nagrywanie',
          ),
        );
        await tester.pump();

        clock.value = const Duration(milliseconds: 42_300);
        await _settle(tester);
        await _capturePng(
          tester,
          'dm_recording_0_42_$suffix',
          pixelRatio: pixelRatio,
        );

        clock.value = const Duration(milliseconds: 54_600);
        await _settle(tester);
        expect(
          find.byKey(const ValueKey('yo-recording-countdown')),
          findsOneWidget,
        );
        await _capturePng(
          tester,
          'dm_countdown_6s_$suffix',
          pixelRatio: pixelRatio,
        );

        clock.value = const Duration(milliseconds: 60_200);
        await _settle(tester);
        expect(
          find.byKey(const ValueKey('voice-message-stopped-at-limit')),
          findsOneWidget,
        );
        await _capturePng(
          tester,
          'dm_auto_stopped_ready_$suffix',
          pixelRatio: pixelRatio,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('family memory countdown and auto-stop $suffix', (
        tester,
      ) async {
        viewport(tester);
        final clock = FakeStopwatch();
        await tester.pumpWidget(
          _host(
            theme: theme,
            child: Scaffold(
              body: ServerFamilyMemoryAlbum(
                serverId: 'family_server',
                channelId: 'memories',
                repository: album.MemoryRepository(Stream.value(const [])),
                currentUserId: 'parent_1',
                role: ServerMemberRole.member,
                colors: ServerIdentity.of(
                  ServerType.family,
                ).resolve(theme.brightness),
                imagePicker: album.PickerStub(
                  XFile.fromData(
                    album.validPng(),
                    mimeType: 'image/png',
                    name: 'family.png',
                  ),
                ),
                recorderFactory: _recorder(clock),
                playerFactory: FakePreviewAudioPlayer.new,
                photoBuilder: (_, _) => const ColoredBox(color: Colors.orange),
              ),
            ),
          ),
        );
        await _settle(tester);
        await tester.tap(
          find.byKey(const ValueKey('server-family-memory-add')).first,
        );
        await _settle(tester);
        await tester.tap(
          find.byKey(const ValueKey('server-family-memory-record')),
        );
        await tester.pump();

        clock.value = const Duration(milliseconds: 24_400);
        await _settle(tester);
        await _capturePng(
          tester,
          'family_countdown_6s_$suffix',
          pixelRatio: pixelRatio,
        );

        clock.value = const Duration(milliseconds: 30_200);
        await _settle(tester);
        await _capturePng(
          tester,
          'family_auto_stopped_ready_$suffix',
          pixelRatio: pixelRatio,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
