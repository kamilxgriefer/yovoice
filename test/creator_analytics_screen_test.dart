import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/creator/presentation/screens/creator_analytics_screen.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';

UserProfile _profile({int followers = 41}) => UserProfile(
  uid: 'creator-1',
  email: 'creator@example.com',
  displayName: 'Creator',
  username: 'creator',
  bio: '',
  country: '',
  nativeLanguage: '',
  spokenLanguages: const [],
  learningLanguages: const [],
  photoUrl: null,
  bannerUrl: null,
  website: '',
  accountType: AccountType.creator,
  friendCount: 999,
  followerCount: followers,
  followingCount: 999,
  roomCount: 999,
  communityCount: 999,
  voiceMinutes: 999,
  messageCount: 999,
  activeDays: 999,
  momentCount: 999,
  reactionCount: 999,
  hostMinutes: 999,
  selectedTitleId: null,
  unlockedTitleIds: const [],
  unlockedTitleTimestamps: const {},
  createdAt: DateTime(2026, 1, 1),
);

VoiceRoom _room({
  required String id,
  required bool isLive,
  RoomStatus status = RoomStatus.active,
  int participants = 0,
  int members = 0,
}) => VoiceRoom(
  id: id,
  hostId: 'creator-1',
  hostName: 'Creator',
  hostPhotoUrl: null,
  name: 'Room $id',
  description: '',
  category: 'talk',
  visibility: 'public',
  language: 'English',
  maxParticipants: 100,
  participantCount: participants,
  memberCount: members,
  isLive: isLive,
  roomType: RoomType.community,
  status: status,
  imageUrl: null,
  approvalRequired: false,
  slowModeSeconds: 0,
  autoMuteNewUsers: true,
  membersCanStartVoice: false,
  createdAt: DateTime(2026, 8, 1),
  updatedAt: DateTime(2026, 8, 2),
);

Club _club({
  required String id,
  required String ownerId,
  required int members,
}) => Club(
  id: id,
  name: 'Club $id',
  description: '',
  ownerId: ownerId,
  ownerName: 'Owner',
  avatarUrl: null,
  bannerUrl: null,
  privacy: ClubPrivacy.public,
  defaultLanguage: 'English',
  memberCount: members,
  onlineCount: 0,
  defaultChatChannelId: 'chat',
  defaultVoiceChannelId: 'voice',
  announcementChannelId: 'announcements',
  createdAt: DateTime(2026, 8, 1),
  updatedAt: DateTime(2026, 8, 2),
);

VoiceMoment _moment({
  required String id,
  required bool published,
  required int likes,
  required int comments,
  required int seconds,
  required DateTime createdAt,
}) => VoiceMoment(
  id: id,
  authorId: 'creator-1',
  authorName: 'Creator',
  authorPhotoUrl: null,
  caption: 'Moment $id',
  audioUrl: published ? 'https://example.com/$id.m4a' : null,
  durationSeconds: seconds,
  likeCount: likes,
  commentCount: comments,
  isPublished: published,
  createdAt: createdAt,
);

final _rooms = [
  _room(id: 'live', isLive: true, participants: 3, members: 7),
  _room(
    id: 'closed',
    isLive: true,
    status: RoomStatus.closed,
    participants: 99,
    members: 11,
  ),
  _room(id: 'offline', isLive: false, participants: 8, members: 13),
];

final _clubs = [
  _club(id: 'owned-a', ownerId: 'creator-1', members: 5),
  _club(id: 'owned-b', ownerId: 'creator-1', members: 9),
  _club(id: 'joined', ownerId: 'someone-else', members: 100),
];

final _moments = [
  _moment(
    id: 'first',
    published: true,
    likes: 4,
    comments: 2,
    seconds: 65,
    createdAt: DateTime(2026, 8, 1),
  ),
  _moment(
    id: 'second',
    published: true,
    likes: 1,
    comments: 7,
    seconds: 30,
    createdAt: DateTime(2026, 8, 2),
  ),
  _moment(
    id: 'draft',
    published: false,
    likes: 900,
    comments: 800,
    seconds: 59,
    createdAt: DateTime(2026, 8, 3),
  ),
];

Widget _host({
  UserProfile? profile,
  List<VoiceRoom>? rooms,
  List<Club>? clubs,
  List<VoiceMoment>? moments,
  double textScale = 1,
}) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: CreatorAnalyticsScreen(
    isRootTab: true,
    profile: profile ?? _profile(),
    rooms: rooms ?? _rooms,
    clubs: clubs ?? _clubs,
    moments: moments ?? _moments,
  ),
);

void _expectMetric(WidgetTester tester, String key, String value) {
  final metric = find.byKey(ValueKey(key));
  expect(metric, findsOneWidget);
  expect(
    find.descendant(of: metric, matching: find.text(value)),
    findsOneWidget,
  );
}

void main() {
  test(
    'summary uses only current stored values and excludes drafts/non-owners',
    () {
      final summary = CreatorAnalyticsSummary.fromData(
        profile: _profile(),
        rooms: _rooms,
        clubs: _clubs,
        moments: _moments,
      );

      expect(summary.currentFollowers, 41);
      expect(summary.hostedRooms, 3);
      expect(summary.liveRooms, 1);
      expect(summary.peopleInLiveRooms, 3);
      expect(summary.roomMemberships, 31);
      expect(summary.ownedClubs, 2);
      expect(summary.clubMemberships, 14);
      expect(summary.publishedMoments, 2);
      expect(summary.momentLikes, 5);
      expect(summary.momentComments, 9);
      expect(summary.publishedAudioSeconds, 95);
      expect(summary.topPublishedMoments.map((moment) => moment.id), [
        'second',
        'first',
      ]);
    },
  );

  testWidgets('screen labels truthful current metrics and published totals', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.pump();

    _expectMetric(tester, 'analytics-followers', '41');
    _expectMetric(tester, 'analytics-hosted-rooms', '3');
    _expectMetric(tester, 'analytics-owned-clubs', '2');
    expect(find.text('Room status when opened'), findsOneWidget);
    expect(
      find.textContaining('reopen Analytics to capture a newer room snapshot'),
      findsOneWidget,
    );
    expect(find.text('Growth'), findsNothing);
    expect(find.text('Views'), findsNothing);
    expect(find.text('Listens'), findsNothing);
    expect(find.text('Attendance'), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('analytics-live-people')),
      250,
    );
    _expectMetric(tester, 'analytics-live-rooms', '1');
    _expectMetric(tester, 'analytics-live-people', '3');

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('analytics-published-audio')),
      250,
    );
    _expectMetric(tester, 'analytics-published-moments', '2');
    _expectMetric(tester, 'analytics-moment-likes', '5');
    _expectMetric(tester, 'analytics-moment-comments', '9');
    _expectMetric(tester, 'analytics-published-audio', '1m 35s');
    expect(
      find.textContaining('never invents growth percentages'),
      findsOneWidget,
    );
    expect(find.text('Moment draft'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0, 768.0, 1100.0, 1440.0]) {
    testWidgets('responsive at ${width.toInt()} px with 200% text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(textScale: 2));
      await tester.pump();

      expect(find.text('Analytics'), findsOneWidget);
      expect(find.text('Real data, clearly labeled'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.text('Owned spaces'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(find.text('Owned spaces'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty content stays honest instead of showing invented data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        profile: _profile(followers: 0),
        rooms: const [],
        clubs: const [],
        moments: const [],
      ),
    );
    await tester.pump();

    _expectMetric(tester, 'analytics-followers', '0');
    _expectMetric(tester, 'analytics-hosted-rooms', '0');
    _expectMetric(tester, 'analytics-owned-clubs', '0');
    await tester.scrollUntilVisible(find.text('Most interacted with'), 350);
    expect(
      find.textContaining('Publish a Voice Moment to see its stored likes'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
