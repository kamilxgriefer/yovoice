// Developer-only VISUAL capture for request to speak in the podcast studio.
//
// Not a golden test (see server_podcast_capture.dart for why): it renders the
// real widgets with the real Inter face, drives them through the fake session
// seams, and writes PNGs so a human can look at what the code draws. It is
// not a device or simulator frame. Run explicitly:
//
//   flutter test test/server_podcast_requests_capture.dart
//
// PNGs land in yovoice-evidence/2026-09-25/podcast-host/.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_session_hand.dart';
import 'package:yovoice/features/servers/data/services/server_media_connector.dart';
import 'package:yovoice/features/servers/data/services/server_voice_device.dart';

import 'server_podcast_test.dart' as board;
import 'server_test_support.dart';

const _outputDirectory =
    '/Users/kamil/Documents/GitHub/yovoice-evidence/2026-09-25/podcast-host';

String get _fontRoot {
  const candidates = [
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts',
    '/usr/local/share/flutter/bin/cache/artifacts/material_fonts',
  ];
  return candidates.firstWhere(
    (path) => File('$path/Roboto-Regular.ttf').existsSync(),
  );
}

ByteData _read(String path) =>
    ByteData.view(Uint8List.fromList(File(path).readAsBytesSync()).buffer);

Future<void> _loadRealFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(Future.value(_read('assets/fonts/InterVariable.ttf')));
  await inter.load();
  final roboto = FontLoader('Roboto');
  for (final face in const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    roboto.addFont(Future.value(_read('$_fontRoot/$face')));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(_read('$_fontRoot/MaterialIcons-Regular.otf')));
  await icons.load();
}

Future<FakeServerMediaConnector> _renderJoined(
  WidgetTester tester, {
  required GlobalKey captureKey,
  required Size size,
  required TestServerRepository repository,
  required List<ServerMediaParticipant> roster,
  ThemeData? theme,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  debugServerVoiceDeviceOverride = FakeServerVoiceDevice();
  addTearDown(() => debugServerVoiceDeviceOverride = null);
  final connector = FakeServerMediaConnector();
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('pl'),
        theme: theme ?? AppTheme.darkTheme,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: size,
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: inner!,
        ),
        home: board.podcastWorkspace(repository, connector: connector),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final join = find.byKey(const ValueKey('server-join')).first;
  await tester.ensureVisible(join);
  await tester.tap(join);
  await tester.pumpAndSettle();
  connector.links.single.setRoster(roster);
  await tester.pumpAndSettle();
  return connector;
}

Future<void> _shoot(
  WidgetTester tester, {
  required GlobalKey captureKey,
  required String name,
}) async {
  await tester.runAsync(() async {
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outputDirectory/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path}');
    } finally {
      image.dispose();
    }
  });
}

const _host = ServerMediaParticipant(
  identity: 'owner',
  name: 'Kasia',
  isLocal: true,
  isSpeaking: true,
  isMicrophoneEnabled: true,
);
const _audience = [
  _host,
  ServerMediaParticipant(
    identity: 'kamil',
    name: 'Kamil',
    isLocal: false,
    sessionRole: 'listener',
  ),
  ServerMediaParticipant(
    identity: 'ola',
    name: 'Ola',
    isLocal: false,
    sessionRole: 'listener',
  ),
  ServerMediaParticipant(
    identity: 'bartek',
    name: 'Bartek',
    isLocal: false,
    sessionRole: 'listener',
  ),
];

List<ServerSessionHand> _queue() => [
  ServerSessionHand(
    userId: 'ola',
    displayName: 'Ola Wiśniewska',
    role: 'listener',
    raisedAt: DateTime.now().subtract(const Duration(minutes: 4)),
  ),
  ServerSessionHand(
    userId: 'kamil',
    displayName: 'Kamil',
    role: 'listener',
    raisedAt: DateTime.now().subtract(const Duration(seconds: 20)),
  ),
];

TestServerRepository _hostRepository(
  StreamController<List<ServerSessionHand>> hands,
) => TestServerRepository()
  ..servers = [board.podcastServer()]
  ..channels = board.podcastChannels(studio: board.live, activeSessionId: 'g')
  ..myRole = ServerMemberRole.member
  ..sessionRole = 'host'
  ..sessionHandsStream = hands.stream;

ServerSessionParticipantState _own({
  bool hand = false,
  ServerHandDecision? decision,
  String role = 'listener',
}) => ServerSessionParticipantState(
  sessionId: 'g',
  role: role,
  authorizationRevision: 1,
  hostMuted: false,
  serverMuted: false,
  isHandRaised: hand,
  handDecision: decision,
  tokenFingerprint: 'token-a',
);

void main() {
  setUpAll(_loadRealFonts);

  for (final (label, size, scale, light) in <(String, Size, double, bool)>[
    ('390x844', Size(390, 844), 1, false),
    ('390x844-scale2', Size(390, 844), 2, false),
    ('768x1024', Size(768, 1024), 1, false),
    ('1440x900', Size(1440, 900), 1, false),
    ('1440x900-pearl', Size(1440, 900), 1, true),
  ]) {
    testWidgets('host queue in the studio $label', (tester) async {
      final hands = StreamController<List<ServerSessionHand>>.broadcast();
      addTearDown(hands.close);
      final captureKey = GlobalKey();
      await _renderJoined(
        tester,
        captureKey: captureKey,
        size: size,
        textScale: scale,
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        repository: _hostRepository(hands),
        roster: _audience,
      );
      hands.add(_queue());
      await tester.pumpAndSettle();
      final requests = find.byKey(const ValueKey('server-stage-requests'));
      if (requests.evaluate().isNotEmpty) {
        await tester.ensureVisible(requests);
        await tester.pumpAndSettle();
      }
      await _shoot(
        tester,
        captureKey: captureKey,
        name: 'host-queue-studio-$label',
      );
    });
  }

  testWidgets('host on another channel, dock and sheet 1440x900', (
    tester,
  ) async {
    final hands = StreamController<List<ServerSessionHand>>.broadcast();
    addTearDown(hands.close);
    final captureKey = GlobalKey();
    await _renderJoined(
      tester,
      captureKey: captureKey,
      size: const Size(1440, 900),
      repository: _hostRepository(hands),
      roster: _audience,
    );
    hands.add(_queue());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('server-channel-discussion')));
    await tester.pumpAndSettle();
    await _shoot(
      tester,
      captureKey: captureKey,
      name: 'host-dock-dot-other-channel-1440x900',
    );
    await tester.tap(find.byKey(const ValueKey('server-dock-requests')));
    await tester.pumpAndSettle();
    await _shoot(
      tester,
      captureKey: captureKey,
      name: 'host-dock-sheet-1440x900',
    );
  });

  testWidgets('host dock sheet on a phone 390x844', (tester) async {
    final hands = StreamController<List<ServerSessionHand>>.broadcast();
    addTearDown(hands.close);
    final captureKey = GlobalKey();
    await _renderJoined(
      tester,
      captureKey: captureKey,
      size: const Size(390, 844),
      repository: _hostRepository(hands),
      roster: _audience,
    );
    hands.add(_queue());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('server-dock-requests')));
    await tester.pumpAndSettle();
    await _shoot(
      tester,
      captureKey: captureKey,
      name: 'host-dock-sheet-390x844',
    );
  });

  for (final (label, state) in <(String, ServerSessionParticipantState)>[
    ('pending', _own(hand: true)),
    ('declined', _own(decision: ServerHandDecision.declined)),
    ('lowered', _own(decision: ServerHandDecision.lowered)),
  ]) {
    testWidgets('listener $label 390x844', (tester) async {
      final own = StreamController<ServerSessionParticipantState?>.broadcast();
      addTearDown(own.close);
      final captureKey = GlobalKey();
      await _renderJoined(
        tester,
        captureKey: captureKey,
        size: const Size(390, 844),
        repository: board.listenerRepository()
          ..channels = board.podcastChannels(
            studio: board.live,
            activeSessionId: 'g',
          )
          ..ownParticipantStream = own.stream,
        roster: board.broadcast,
      );
      own.add(state);
      await tester.pumpAndSettle();
      await _shoot(
        tester,
        captureKey: captureKey,
        name: 'listener-$label-390x844',
      );
    });
  }

  testWidgets('listener approved: joining the stage, then on it 390x844', (
    tester,
  ) async {
    final own = StreamController<ServerSessionParticipantState?>.broadcast();
    addTearDown(own.close);
    final captureKey = GlobalKey();
    final repository = board.listenerRepository()
      ..channels = board.podcastChannels(
        studio: board.live,
        activeSessionId: 'g',
      )
      ..ownParticipantStream = own.stream;
    final connector = await _renderJoined(
      tester,
      captureKey: captureKey,
      size: const Size(390, 844),
      repository: repository,
      roster: board.broadcast,
    );
    own.add(_own(hand: true));
    await tester.pumpAndSettle();
    repository
      ..sessionRole = 'guest'
      ..permittedTrackSources = const ['microphone'];
    own.add(
      ServerSessionParticipantState(
        sessionId: 'g',
        role: 'guest',
        authorizationRevision: 2,
        hostMuted: false,
        serverMuted: false,
        isHandRaised: false,
        handDecision: ServerHandDecision.approved,
        tokenFingerprint: 'token-a',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await _shoot(
      tester,
      captureKey: captureKey,
      name: 'listener-approved-joining-390x844',
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    // The new provider link reports the same people, this device now signed
    // as a guest.
    connector.links.last.setRoster([
      for (final person in board.broadcast)
        if (person.isLocal)
          const ServerMediaParticipant(
            identity: 'owner',
            name: 'Kasia',
            isLocal: true,
            sessionRole: 'guest',
          )
        else
          person,
    ]);
    await tester.pumpAndSettle();
    await _shoot(
      tester,
      captureKey: captureKey,
      name: 'listener-approved-on-stage-390x844',
    );
  });
}
