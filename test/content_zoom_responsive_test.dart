import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/clubs/data/models/club_invite.dart';
import 'package:yovoice/features/clubs/presentation/screens/clubs_screen.dart';
import 'package:yovoice/features/creator/presentation/screens/creator_studio_screen.dart';
import 'package:yovoice/features/discover/presentation/screens/discover_screen.dart';
import 'package:yovoice/features/friends/data/models/friend_request.dart';
import 'package:yovoice/features/friends/presentation/screens/friends_screen.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';

const _longRoomName =
    'A deliberately long multilingual room name for two hundred percent text';
const _longDescription =
    'A deliberately long description that must wrap safely instead of '
    'overflowing the featured room card at narrow phone widths.';

VoiceRoom _room(String id) => VoiceRoom(
  id: id,
  hostId: 'host-$id',
  hostName: 'A creator with a deliberately long display name',
  hostPhotoUrl: null,
  name: '$_longRoomName $id',
  description: _longDescription,
  category: 'talk',
  visibility: 'public',
  language: 'English',
  maxParticipants: 100,
  participantCount: 42,
  memberCount: 64,
  isLive: true,
  roomType: RoomType.community,
  status: RoomStatus.active,
  imageUrl: null,
  approvalRequired: false,
  slowModeSeconds: 0,
  autoMuteNewUsers: true,
  membersCanStartVoice: false,
  createdAt: DateTime(2026, 8, 16),
  updatedAt: DateTime(2026, 8, 16),
);

Widget _host(Widget child) {
  return MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    builder: (context, appChild) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(2)),
      child: appChild!,
    ),
    home: Scaffold(
      backgroundColor: const Color(0xFF080711),
      body: SafeArea(child: child),
    ),
  );
}

void _useNarrowPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets(
    'Creator Studio horizontal modules grow safely at 320px and 200% text',
    (tester) async {
      _useNarrowPhone(tester);

      await tester.pumpWidget(
        _host(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                CreatorStudioStatStrip(
                  items: const [
                    CreatorStudioStatItem(value: '123456', label: 'Followers'),
                    CreatorStudioStatItem(
                      value: '987654',
                      label: 'Speaking time',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const CreatorStudioUpcomingToolsRow(),
                const SizedBox(height: 12),
                CreatorStudioRoomsList(rooms: [_room('creator-room')]),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSize(find.byType(CreatorStudioStatStrip)).height,
        greaterThan(62),
      );
      expect(
        tester.getSize(find.byType(CreatorStudioUpcomingToolsRow)).height,
        greaterThan(108),
      );
      expect(
        tester.getSize(find.byType(CreatorStudioRoomsList)).height,
        greaterThan(96),
      );
      expect(find.textContaining(_longRoomName), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Discover Featured becomes an intrinsic vertical list for long zoomed copy',
    (tester) async {
      _useNarrowPhone(tester);

      await tester.pumpWidget(
        _host(
          SingleChildScrollView(
            child: DiscoverFeaturedRooms(
              rooms: [_room('first'), _room('second')],
              onRoomPressed: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final first = tester.getRect(
        find.byKey(const ValueKey('discover-featured-first')),
      );
      final second = tester.getRect(
        find.byKey(const ValueKey('discover-featured-second')),
      );
      expect(second.top, greaterThan(first.bottom));
      expect(second.left, closeTo(first.left, 0.1));
      expect(find.textContaining(_longDescription), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('friend request actions stack at 320px and 200% text', (
    tester,
  ) async {
    _useNarrowPhone(tester);

    await tester.pumpWidget(
      _host(
        Padding(
          padding: const EdgeInsets.all(8),
          child: FriendRequestCard(
            request: const FriendRequest(
              senderId: 'friend',
              senderName: 'A friend with a deliberately long display name',
              senderEmail: 'a.deliberately.long.address@yovoice.app',
              senderPhotoUrl: null,
              createdAt: null,
            ),
            processing: false,
            onAccept: () {},
            onDecline: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    final accept = find.byKey(const ValueKey('friend-request-accept'));
    final decline = find.byKey(const ValueKey('friend-request-decline'));
    expect(
      tester.getTopLeft(accept).dy,
      lessThan(tester.getTopLeft(decline).dy),
    );
    expect(tester.getSize(accept).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(decline).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('club invitation actions stack at 320px and 200% text', (
    tester,
  ) async {
    _useNarrowPhone(tester);

    await tester.pumpWidget(
      _host(
        Padding(
          padding: const EdgeInsets.all(8),
          child: ClubInviteCard(
            invite: const ClubInvite(
              clubId: 'club',
              clubName: 'A club with a deliberately long multilingual name',
              clubAvatarUrl: null,
              inviteeId: 'me',
              inviterId: 'owner',
              inviterName: 'A creator with a deliberately long display name',
              createdAt: null,
            ),
            busy: false,
            onAccept: () {},
            onDecline: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    final accept = find.byKey(const ValueKey('club-invite-accept'));
    final decline = find.byKey(const ValueKey('club-invite-decline'));
    expect(
      tester.getTopLeft(accept).dy,
      lessThan(tester.getTopLeft(decline).dy),
    );
    expect(tester.getSize(accept).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(decline).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });
}
