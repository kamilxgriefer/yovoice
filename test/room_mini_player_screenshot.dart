// Developer-only visual QA harness for the live-room MINI PLAYER.
//
// The filename deliberately has no `_test` suffix, so the ordinary suite
// skips it. Run explicitly:
//
//   flutter test test/room_mini_player_screenshot.dart
//
// PNGs land in test/.screenshots/ (git-ignored).
//
// Covers the desktop dock at 1280/1440/1920, the mobile card at
// 320/360/390/430 above a bottom navigation, the expanded chat on both
// platforms, muted, reconnecting, long title + long message, the "N new"
// pill, host vs participant, and 200% text at the narrowest width.
//
// The bottom navigation here is a Material 3 stand-in with the shell's
// five destinations: MainShell itself reads FirebaseAuth.instance in its
// state and cannot be pumped in a widget test (same reason
// desktop_shell_test.dart mirrors the composition instead of mounting it).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/rooms/data/services/room_mute_coordinator.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_mini_bar.dart';

import 'room_mini_player_test.dart' show FakeVoiceService, FakeRoomService;

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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

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

VoiceParticipantViewData _person(String name, {bool speaking = false}) =>
    VoiceParticipantViewData(
      identity: name.toLowerCase(),
      displayName: name,
      isLocal: false,
      isSpeaking: speaking,
      audioLevel: speaking ? .4 : 0,
      isMuted: false,
    );

/// The shell's five mobile destinations, as a Material 3 stand-in.
class _StandInBottomNav extends StatelessWidget {
  const _StandInBottomNav();

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: 0,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
        NavigationDestination(
          icon: Icon(Icons.chat_bubble_rounded),
          label: 'Chats',
        ),
        NavigationDestination(icon: Icon(Icons.mic_rounded), label: 'Voice'),
        NavigationDestination(
          icon: Icon(Icons.auto_awesome_rounded),
          label: 'Moments',
        ),
        NavigationDestination(
          icon: Icon(Icons.grid_view_rounded),
          label: 'More',
        ),
      ],
    );
  }
}

void main() {
  setUpAll(_loadFonts);

  late FakeVoiceService voice;
  late FakeRoomService rooms;
  late RoomMuteCoordinator coordinator;

  Future<void> seedRoom({String hostId = 'host'}) async {
    await rooms.db.collection('rooms').doc('room-1').set({
      'hostId': hostId,
      'hostName': 'Host',
      'name': 'Sunday Morning Talk',
      'description': 'A calm place to talk about anything.',
      'category': 'talk',
      'visibility': 'public',
      'language': 'English',
      'participantCount': 3,
      'memberCount': 0,
      'isLive': true,
      'status': 'active',
      'experience': 'community',
    });
  }

  Future<void> message(String id, String text, {String sender = 'Zosia',
      required DateTime at}) {
    return rooms.db
        .collection('rooms')
        .doc('room-1')
        .collection('messages')
        .doc(id)
        .set({
      'senderId': sender.toLowerCase(),
      'senderName': sender,
      'senderPhotoUrl': null,
      'text': text,
      'createdAt': Timestamp.fromDate(at),
      'reactions': <String, List<String>>{},
    });
  }

  setUp(() {
    voice = FakeVoiceService()
      ..roomIdValue = 'room-1'
      ..roomNameValue = 'Sunday Morning Talk'
      ..participantsValue = [
        _person('Kamil', speaking: true),
        _person('Zosia Wieczorek'),
        _person('Bartek K.'),
      ];
    rooms = FakeRoomService.fresh(uid: 'me');
    coordinator = RoomMuteCoordinator(
      persistRosterState: (roomId, muted) async {},
      applyMicrophoneState: (muted) => voice.setMuted(muted),
      readCurrentMuted: () => voice.isMuted,
      disconnectStaleSession: () => voice.disconnect(),
    );
  });

  Future<void> pumpPlayer(
    WidgetTester tester, {
    required Size viewport,
    required bool desktop,
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = viewport;
    addTearDown(tester.view.reset);

    final player = RoomMiniBar(
      voiceService: voice,
      muteCoordinator: coordinator,
      roomService: rooms,
      openRoom: (context, roomId) async {},
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: RepaintBoundary(key: _capture, child: child!),
        ),
        home: desktop
            // The desktop shell mount: the dock is the bottom-most element
            // of the window's root column.
            ? Scaffold(
                backgroundColor: AppColors.background,
                body: Column(
                  children: [
                    const Expanded(child: SizedBox.expand()),
                    SafeArea(top: false, child: player),
                  ],
                ),
              )
            // The mobile shell mount: player directly above the bottom nav.
            : Scaffold(
                backgroundColor: AppColors.background,
                body: const SizedBox.expand(),
                bottomNavigationBar: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [player, const _StandInBottomNav()],
                ),
              ),
      ),
    );
    await _settle(tester);
    // No-overflow gate: a frame that throws (RenderFlex overflow included)
    // is a failed frame, not just an ugly one.
    expect(tester.takeException(), isNull);
  }

  // ------------------------------------------------------------- desktop

  testWidgets('dock 1280 populated (participant)', (tester) async {
    await seedRoom();
    await message('m1', 'Witajcie! Super, ze jestescie — dzisiaj gadamy o '
        'planach na niedzielny wieczor.', at: DateTime(2026, 8, 22, 10, 0));
    await pumpPlayer(tester, viewport: const Size(1280, 800), desktop: true);
    await _shoot(tester, 'mini-player-dock-1280');
  });

  testWidgets('dock 1440 host sees End room', (tester) async {
    await seedRoom(hostId: 'me');
    await message('m1', 'Zaczynamy za chwile!', at: DateTime(2026, 8, 22, 10));
    await pumpPlayer(tester, viewport: const Size(1440, 900), desktop: true);
    await _shoot(tester, 'mini-player-dock-1440-host');
  });

  testWidgets('dock 1920 long title and long message', (tester) async {
    voice.roomNameValue =
        'The Extended Jaguszewski Family Sunday Evening Lounge and Storytime';
    await seedRoom();
    await message(
      'm1',
      'This is a deliberately very long chat message that has to clamp to '
      'exactly two lines with an ellipsis and must never be allowed to grow '
      'the dock taller, no matter how much someone types into the room chat.',
      at: DateTime(2026, 8, 22, 10, 0),
    );
    await pumpPlayer(tester, viewport: const Size(1920, 1000), desktop: true);
    await _shoot(tester, 'mini-player-dock-1920-long');
  });

  testWidgets('dock 1440 with N new pill', (tester) async {
    await seedRoom();
    await message('m1', 'Pierwsza wiadomosc', at: DateTime(2026, 8, 22, 10));
    await pumpPlayer(tester, viewport: const Size(1440, 900), desktop: true);
    await message('m2', 'Druga — swieza', at: DateTime(2026, 8, 22, 10, 1));
    await _settle(tester);
    await message('m3', 'Trzecia — najswiezsza 🔥',
        at: DateTime(2026, 8, 22, 10, 2));
    await _settle(tester);
    await _shoot(tester, 'mini-player-dock-1440-newpill');
  });

  testWidgets('dock 1440 expanded chat popover', (tester) async {
    await seedRoom();
    await message('m1', 'Witajcie! Super, ze jestescie.',
        at: DateTime(2026, 8, 22, 10, 0));
    await message('m2', 'Czesc wszystkim! Dobrze was slyszec.',
        sender: 'Kamil', at: DateTime(2026, 8, 22, 10, 1));
    await pumpPlayer(tester, viewport: const Size(1440, 900), desktop: true);
    await tester.tap(find.byKey(const ValueKey('mini-player-expand-chat')));
    await _settle(tester);
    await _shoot(tester, 'mini-player-dock-1440-expanded');
  });

  testWidgets('dock 1440 muted', (tester) async {
    voice.mutedValue = true;
    await seedRoom();
    await message('m1', 'Czekamy na Ciebie!', at: DateTime(2026, 8, 22, 10));
    await pumpPlayer(tester, viewport: const Size(1440, 900), desktop: true);
    await _shoot(tester, 'mini-player-dock-1440-muted');
  });

  testWidgets('dock 1280 reconnecting', (tester) async {
    voice.statusValue = VoiceCallStatus.reconnecting;
    await seedRoom();
    await message('m1', 'Halo, slychac nas?', at: DateTime(2026, 8, 22, 10));
    await pumpPlayer(tester, viewport: const Size(1280, 800), desktop: true);
    await _shoot(tester, 'mini-player-dock-1280-reconnecting');
  });

  // -------------------------------------------------------------- mobile

  testWidgets('card 320 populated with emoji message', (tester) async {
    await seedRoom();
    await message('m1', '🔥🔥🔥', at: DateTime(2026, 8, 22, 10, 0));
    await pumpPlayer(tester, viewport: const Size(320, 844), desktop: false);
    await _shoot(tester, 'mini-player-card-320');
  });

  testWidgets('card 360 reconnecting', (tester) async {
    voice.statusValue = VoiceCallStatus.reconnecting;
    await seedRoom();
    await message('m1', 'Halo, slychac nas?', at: DateTime(2026, 8, 22, 10));
    await pumpPlayer(tester, viewport: const Size(360, 844), desktop: false);
    await _shoot(tester, 'mini-player-card-360-reconnecting');
  });

  testWidgets('card 390 populated (participant)', (tester) async {
    await seedRoom();
    await message('m1', 'Witajcie! Super, ze jestescie — dzisiaj gadamy o '
        'planach na niedzielny wieczor.', at: DateTime(2026, 8, 22, 10, 0));
    await pumpPlayer(tester, viewport: const Size(390, 844), desktop: false);
    await _shoot(tester, 'mini-player-card-390');
  });

  testWidgets('card 390 muted host', (tester) async {
    voice.mutedValue = true;
    await seedRoom(hostId: 'me');
    await message('m1', 'Zaraz wracam!', at: DateTime(2026, 8, 22, 10, 0));
    await pumpPlayer(tester, viewport: const Size(390, 844), desktop: false);
    await _shoot(tester, 'mini-player-card-390-muted-host');
  });

  testWidgets('card 390 with N new pill', (tester) async {
    await seedRoom();
    await message('m1', 'Pierwsza wiadomosc', at: DateTime(2026, 8, 22, 10));
    await pumpPlayer(tester, viewport: const Size(390, 844), desktop: false);
    await message('m2', 'Druga — swieza', at: DateTime(2026, 8, 22, 10, 1));
    await _settle(tester);
    await message('m3', 'Trzecia — najswiezsza 🔥',
        at: DateTime(2026, 8, 22, 10, 2));
    await _settle(tester);
    await _shoot(tester, 'mini-player-card-390-newpill');
  });

  testWidgets('card 390 expanded chat sheet', (tester) async {
    await seedRoom();
    await message('m1', 'Witajcie! Super, ze jestescie.',
        at: DateTime(2026, 8, 22, 10, 0));
    await message('m2', 'Czesc wszystkim! Dobrze was slyszec.',
        sender: 'Kamil', at: DateTime(2026, 8, 22, 10, 1));
    await pumpPlayer(tester, viewport: const Size(390, 844), desktop: false);
    await tester.tap(find.byKey(const ValueKey('mini-player-expand-chat')));
    await _settle(tester);
    await _shoot(tester, 'mini-player-card-390-expanded');
  });

  testWidgets('card 430 long title and long message', (tester) async {
    voice.roomNameValue =
        'The Extended Jaguszewski Family Sunday Evening Lounge and Storytime';
    await seedRoom();
    await message(
      'm1',
      'This is a deliberately very long chat message that has to clamp to '
      'exactly two lines with an ellipsis and must never be allowed to grow '
      'the card taller, no matter how much someone types into the room chat.',
      at: DateTime(2026, 8, 22, 10, 0),
    );
    await pumpPlayer(tester, viewport: const Size(430, 932), desktop: false);
    await _shoot(tester, 'mini-player-card-430-long');
  });

  testWidgets('card 320 at 200% text', (tester) async {
    await seedRoom();
    await message('m1', 'Dwukrotna skala tekstu na najwezszym ekranie.',
        at: DateTime(2026, 8, 22, 10, 0));
    await pumpPlayer(
      tester,
      viewport: const Size(320, 844),
      desktop: false,
      textScale: 2,
    );
    await _shoot(tester, 'mini-player-card-320-x2');
  });
}
