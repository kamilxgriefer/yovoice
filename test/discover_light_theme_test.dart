import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/discover/presentation/screens/discover_screen.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

class _StaticRoomService extends RoomService {
  _StaticRoomService(this.rooms)
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: true),
      );

  final List<VoiceRoom> rooms;

  @override
  Stream<List<VoiceRoom>> watchLivePublicRooms() => Stream.value(rooms);
}

VoiceRoom _room() => VoiceRoom(
  id: 'pearl-room',
  hostId: 'host',
  hostName: 'A creator with a long display name',
  hostPhotoUrl: null,
  name: 'A premium conversation for curious people',
  description: 'Long live-room copy remains readable at accessibility zoom.',
  category: 'Talk',
  visibility: 'public',
  language: 'English',
  maxParticipants: 100,
  participantCount: 42,
  memberCount: 42,
  isLive: true,
  roomType: RoomType.community,
  status: RoomStatus.active,
  imageUrl: null,
  approvalRequired: false,
  slowModeSeconds: 0,
  autoMuteNewUsers: true,
  membersCanStartVoice: false,
  createdAt: DateTime(2026, 8, 29),
  updatedAt: DateTime(2026, 8, 29),
);

void main() {
  testWidgets('Discover Pearl is semantic and overflow-free at 320px / 200%', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: DiscoverScreen(
            isRootTab: true,
            roomService: _StaticRoomService([_room()]),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final scaffold = tester.widget<Scaffold>(
      find.byKey(const ValueKey('discover-screen')),
    );
    expect(scaffold.backgroundColor, AppPalette.light.background);

    final search = tester.widget<TextField>(
      find.byKey(const ValueKey('discover-search-field')),
    );
    expect(search.decoration?.fillColor, AppPalette.light.surface);

    final selected = tester.widget<Material>(
      find.byKey(const ValueKey('discover-category-All')),
    );
    expect(selected.color, AppTheme.lightTheme.colorScheme.primary);
    expect(find.byKey(const ValueKey('discover-hero-pearl-room')), findsOne);
    expect(tester.takeException(), isNull);
  });
}
