import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/space_identity.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/presentation/voice_room_identity.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_control_dock.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_header.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_hero_banner.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_stage.dart';

VoiceRoom _room({String experience = 'community', String? clubId}) => VoiceRoom(
  id: 'room',
  hostId: 'host',
  hostName: 'Host',
  hostPhotoUrl: null,
  name: 'A room with a genuinely long title',
  description: 'A welcoming conversation with enough copy to wrap safely.',
  category: 'talk',
  visibility: 'public',
  language: 'English',
  maxParticipants: 25,
  participantCount: 3,
  memberCount: 3,
  isLive: true,
  roomType: RoomType.temporary,
  status: RoomStatus.active,
  imageUrl: null,
  approvalRequired: false,
  slowModeSeconds: 0,
  autoMuteNewUsers: false,
  membersCanStartVoice: false,
  createdAt: null,
  updatedAt: null,
  experience: experience,
  clubId: clubId,
);

Club _club(ClubType type) => Club(
  id: 'club',
  name: 'Club',
  description: 'Description',
  ownerId: 'host',
  ownerName: 'Host',
  avatarUrl: null,
  bannerUrl: null,
  privacy: ClubPrivacy.private,
  defaultLanguage: 'English',
  memberCount: 3,
  onlineCount: 1,
  defaultChatChannelId: 'chat',
  defaultVoiceChannelId: 'voice',
  announcementChannelId: 'announcements',
  createdAt: null,
  updatedAt: null,
  type: type,
);

Widget _scene(SpaceIdentity identity) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: const TextScaler.linear(2)),
    child: child!,
  ),
  home: Scaffold(
    backgroundColor: const Color(0xFF05030A),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              RoomHeroBanner(
                identity: identity,
                title: 'Late night voices that bring people together',
                topic:
                    'A welcoming conversation with enough copy to wrap safely.',
              ),
              const SizedBox(height: 14),
              RoomStagePanel(
                identity: identity,
                speakers: const [
                  StageSpeaker(
                    userId: 'host',
                    displayName: 'Alexandra Longname',
                    photoUrl: null,
                    isHost: true,
                    isSpeaking: true,
                    audioLevel: .72,
                  ),
                  StageSpeaker(
                    userId: 'speaker',
                    displayName: 'Maya',
                    photoUrl: null,
                    isMuted: true,
                  ),
                  StageSpeaker(
                    userId: 'speaker-2',
                    displayName: 'Noah',
                    photoUrl: null,
                  ),
                ],
                onOverflowTap: () {},
                onSpeakerTap: (_) {},
              ),
              const SizedBox(height: 12),
              AudienceStrip(count: 842, identity: identity, onTap: () {}),
            ],
          ),
        ),
      ),
    ),
  ),
);

void main() {
  test('authoritative models resolve all four room identities', () {
    expect(voiceRoomIdentity(_room()), same(SpaceIdentity.community));
    expect(
      voiceRoomIdentity(_room(experience: 'broadcast')),
      same(SpaceIdentity.podcast),
    );
    expect(
      voiceRoomIdentity(_room(clubId: 'club'), club: _club(ClubType.community)),
      same(SpaceIdentity.club),
    );
    expect(
      voiceRoomIdentity(_room(clubId: 'family'), club: _club(ClubType.family)),
      same(SpaceIdentity.family),
    );
  });

  for (final identity in SpaceIdentity.all) {
    for (final viewport in const [
      (320.0, 844.0),
      (390.0, 844.0),
      (768.0, 1024.0),
      (1100.0, 800.0),
      (1440.0, 900.0),
    ]) {
      testWidgets(
        '${identity.label} stage fits ${viewport.$1.toInt()}px at 200% text',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(viewport.$1, viewport.$2);
          addTearDown(tester.view.reset);

          await tester.pumpWidget(_scene(identity));
          await tester.pump();

          expect(find.text(identity.label.toUpperCase()), findsOneWidget);
          if (find.text('On stage').evaluate().isEmpty) {
            await tester.drag(find.byType(ListView), const Offset(0, -1000));
            await tester.pump();
          }
          expect(find.text('On stage'), findsOneWidget);
          expect(
            find.text('The room is quiet — your voice can start it'),
            findsNothing,
          );
          expect(
            tester
                .getSize(
                  find.byKey(ValueKey('room-stage-${identity.kind.name}')),
                )
                .width,
            lessThanOrEqualTo(1040),
          );
          await tester.drag(find.byType(ListView), const Offset(0, -1200));
          await tester.pump();
          expect(find.text('842 listening'), findsOneWidget);
          expect(
            tester
                .getSize(
                  find.byKey(ValueKey('room-listeners-${identity.kind.name}')),
                )
                .height,
            greaterThanOrEqualTo(44),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('desktop speaker tiles are centered inside the bounded stage', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_scene(SpaceIdentity.community));
    await tester.pump();

    final panelRect = tester.getRect(
      find.byKey(const ValueKey('room-stage-community')),
    );
    final tiles = find.byType(SpeakerTile);
    expect(tiles, findsNWidgets(3));
    final tileRects = [
      for (var index = 0; index < 3; index++) tester.getRect(tiles.at(index)),
    ];
    final groupLeft = tileRects
        .map((rect) => rect.left)
        .reduce((a, b) => a < b ? a : b);
    final groupRight = tileRects
        .map((rect) => rect.right)
        .reduce((a, b) => a > b ? a : b);
    final groupCenter = (groupLeft + groupRight) / 2;

    expect((groupCenter - panelRect.center.dx).abs(), lessThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a lone host renders as a hero tile, not a lost thumbnail', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: RoomStagePanel(
                identity: SpaceIdentity.podcast,
                speakers: const [
                  StageSpeaker(
                    userId: 'host',
                    displayName: 'Host',
                    photoUrl: null,
                    isHost: true,
                  ),
                ],
                onOverflowTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final tile = tester.getSize(find.byType(SpeakerTile));
    expect(tile.width, greaterThanOrEqualTo(158));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop workspace gives stage and chat purposeful widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RoomWorkspace(
            showCompactChat: false,
            stage: ColoredBox(
              key: ValueKey('test-stage'),
              color: Colors.purple,
            ),
            chat: ColoredBox(key: ValueKey('test-chat'), color: Colors.blue),
          ),
        ),
      ),
    );

    final stageRect = tester.getRect(find.byKey(const ValueKey('test-stage')));
    final chatRect = tester.getRect(find.byKey(const ValueKey('test-chat')));
    expect(chatRect.width, 350);
    expect(stageRect.width, lessThan(740));
    expect(stageRect.right, lessThan(chatRect.left));
    expect(chatRect.right - stageRect.left, lessThanOrEqualTo(1120));
    expect(tester.takeException(), isNull);
  });

  // A tablet is never a squeezed desktop: below the 1100 breakpoint the
  // stage keeps its full canvas and chat docks over its bottom edge.
  for (final width in const [320.0, 390.0, 768.0, 1024.0]) {
    testWidgets(
      'compact workspace keeps stage and docks chat at ${width.toInt()}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        addTearDown(tester.view.reset);

        Widget app(bool chat) => MaterialApp(
          home: Scaffold(
            body: RoomWorkspace(
              showCompactChat: chat,
              stage: const ColoredBox(
                key: ValueKey('compact-stage'),
                color: Colors.purple,
              ),
              chat: const ColoredBox(
                key: ValueKey('compact-chat'),
                color: Colors.blue,
              ),
            ),
          ),
        );

        await tester.pumpWidget(app(false));
        expect(find.byKey(const ValueKey('compact-stage')), findsOneWidget);
        expect(find.byKey(const ValueKey('compact-chat')), findsNothing);
        expect(
          tester.getSize(find.byKey(const ValueKey('compact-stage'))).width,
          width - 24,
        );

        await tester.pumpWidget(app(true));
        expect(find.byKey(const ValueKey('compact-stage')), findsOneWidget);
        expect(find.byKey(const ValueKey('compact-chat')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('room-compact-chat-dock')),
          findsOneWidget,
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('compact-chat'))).width,
          width <= 584 ? width - 24 : 560,
        );
        final stageRect = tester.getRect(
          find.byKey(const ValueKey('compact-stage')),
        );
        final chatRect = tester.getRect(
          find.byKey(const ValueKey('compact-chat')),
        );
        expect(chatRect.bottom, stageRect.bottom);
        expect(chatRect.height, lessThan(stageRect.height));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('200% text keeps the compact chat below 40% of the room', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: RoomWorkspace(
            showCompactChat: true,
            stage: ColoredBox(
              key: ValueKey('scaled-stage'),
              color: Colors.purple,
            ),
            chat: ColoredBox(key: ValueKey('scaled-chat'), color: Colors.blue),
          ),
        ),
      ),
    );

    final stage = tester.getRect(find.byKey(const ValueKey('scaled-stage')));
    final chat = tester.getRect(find.byKey(const ValueKey('scaled-chat')));
    expect(chat.height, greaterThanOrEqualTo(230));
    expect(chat.height / stage.height, lessThan(.40));
    expect(chat.bottom, stage.bottom);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px at 200% keeps the full long room identity readable', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 844);
    addTearDown(tester.view.reset);
    const title =
        'The Extended Jaguszewski Family Sunday Evening Lounge and Storytime';
    const topic =
        'A very long description that has to wrap gracefully at the '
        'narrowest supported width, at double text scale, without losing '
        'the meaning of the room.';

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFF05030A),
          body: SafeArea(
            child: Column(
              children: [
                RoomHeader(
                  identity: SpaceIdentity.family,
                  title: title,
                  subtitle: 'FAMILY ROOM · NOT LIVE YET',
                  speaking: 0,
                  listeners: 0,
                  people: 0,
                  onBack: () {},
                  onSpeakingTap: () {},
                  onListenersTap: () {},
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: const [
                      RoomHeroBanner(
                        identity: SpaceIdentity.family,
                        title: title,
                        topic: topic,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final heroTitle = tester.renderObject<RenderParagraph>(
      find.byKey(const ValueKey('room-hero-title')),
    );
    final heroTopic = tester.renderObject<RenderParagraph>(
      find.byKey(const ValueKey('room-hero-topic')),
    );
    final headerSubtitle = tester.renderObject<RenderParagraph>(
      find.byKey(const ValueKey('room-header-subtitle')),
    );
    expect(heroTitle.didExceedMaxLines, isFalse);
    expect(heroTopic.didExceedMaxLines, isFalse);
    expect(
      headerSubtitle.didExceedMaxLines,
      isFalse,
      reason: 'The room type and liveness must not collapse into fragments.',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('room-header-title')))
          .maxLines,
      3,
    );
    expect(tester.takeException(), isNull);
  });

  for (final viewport in const [
    (320.0, 844.0),
    (390.0, 844.0),
    (768.0, 1024.0),
    (1100.0, 800.0),
    (1440.0, 900.0),
  ]) {
    testWidgets(
      'podcast header and control dock fit ${viewport.$1.toInt()}px at 200%',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(viewport.$1, viewport.$2);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              backgroundColor: const Color(0xFF05030A),
              body: Column(
                children: [
                  RoomHeader(
                    identity: SpaceIdentity.podcast,
                    title: 'A podcast with a long room title',
                    subtitle: 'PODCAST ROOM',
                    speaking: 3,
                    listeners: 842,
                    onBack: () {},
                    onSpeakingTap: () {},
                    onListenersTap: () {},
                    actions: [
                      IconButton(
                        tooltip: 'Share room',
                        onPressed: () {},
                        color: Colors.white,
                        icon: const Icon(Icons.ios_share_rounded, size: 21),
                      ),
                      IconButton(
                        tooltip: 'Manage podcast',
                        onPressed: () {},
                        color: Colors.white,
                        icon: const Icon(Icons.more_vert_rounded),
                      ),
                    ],
                  ),
                  const Spacer(),
                  RoomControlDock(
                    children: [
                      RoomDockButton(
                        icon: Icons.mic_rounded,
                        label: 'Mute',
                        style: RoomDockStyle.accent,
                        accentColor: SpaceIdentity.podcast.primary,
                        onTap: () {},
                      ),
                      RoomDockButton(
                        icon: Icons.forum_rounded,
                        label: 'Chat',
                        style: RoomDockStyle.neutral,
                        accentColor: SpaceIdentity.podcast.primary,
                        onTap: () {},
                      ),
                      RoomDockButton(
                        icon: Icons.groups_rounded,
                        label: 'People',
                        style: RoomDockStyle.neutral,
                        accentColor: SpaceIdentity.podcast.primary,
                        onTap: () {},
                      ),
                      RoomDockButton(
                        icon: Icons.ios_share_rounded,
                        label: 'Share',
                        style: RoomDockStyle.neutral,
                        accentColor: SpaceIdentity.podcast.primary,
                        onTap: () {},
                      ),
                      const RoomDockDivider(),
                      RoomDockButton(
                        icon: Icons.stop_circle_rounded,
                        label: 'End',
                        style: RoomDockStyle.danger,
                        accentColor: SpaceIdentity.podcast.primary,
                        onTap: () {},
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('PODCAST ROOM'), findsOneWidget);
        expect(find.text('End'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
