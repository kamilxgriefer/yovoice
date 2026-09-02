import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/achievements/data/achievement_catalog.dart';
import 'package:yovoice/features/achievements/data/services/achievement_service.dart';
import 'package:yovoice/features/achievements/presentation/achievement_localized_copy.dart';
import 'package:yovoice/features/achievements/presentation/screens/achievements_screen.dart';
import 'package:yovoice/features/achievements/presentation/widgets/title_badge.dart';
import 'package:yovoice/features/discover/presentation/screens/discover_screen.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

void main() {
  Widget polishHost(Widget child) => MaterialApp(
    locale: const Locale('pl'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: AppTheme.darkTheme,
    home: child,
  );

  test(
    'every persisted achievement has deliberate Polish presentation copy',
    () {
      const copy = AppLocalizations(Locale('pl'));

      expect(AchievementCatalog.all, hasLength(100));
      for (final achievement in AchievementCatalog.all) {
        expect(
          localizedAchievementTitle(copy, achievement),
          isNot(achievement.title),
          reason: '${achievement.id} needs a Polish title',
        );
        expect(
          localizedAchievementDescription(copy, achievement),
          isNot(achievement.description),
          reason: '${achievement.id} needs a Polish description',
        );
      }
    },
  );

  testWidgets('Awards localizes progress, metadata and selected-title status', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      polishHost(
        AchievementsScreen(
          profile: _profile(),
          achievementService: AchievementService(
            firestore: FakeFirebaseFirestore(),
            auth: MockFirebaseAuth(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Twoje postępy w YO Voice'), findsOneWidget);
    expect(find.text('Kategorie'), findsOneWidget);
    expect(find.text('Odblokowane'), findsOneWidget);
    expect(find.text('Ostatnio odblokowane'), findsOneWidget);
    expect(find.text('Pierwsze słowo'), findsWidgets);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
    await tester.pump();

    expect(find.text('Napisz 1 wiadomość.'), findsOneWidget);
    expect(find.text('AKTYWNY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TitleBadge translates persisted achievement titles', (
    tester,
  ) async {
    await tester.pumpWidget(
      polishHost(
        Scaffold(
          body: Center(
            child: TitleBadge(achievement: AchievementCatalog.all.first),
          ),
        ),
      ),
    );

    expect(find.text('Pierwsze słowo'), findsOneWidget);
    expect(find.text('First Word'), findsNothing);
  });

  testWidgets('Discover localizes its live-room journey in Polish', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      polishHost(
        DiscoverScreen(
          isRootTab: true,
          roomService: _StaticRoomService([_room()]),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Odkrywaj'), findsOneWidget);
    expect(find.text('Wszystkie'), findsOneWidget);
    expect(find.text('Rozmowy'), findsWidgets);
    expect(find.text('WYRÓŻNIONY POKÓJ SPOŁECZNOŚCIOWY'), findsOneWidget);
    expect(find.text('Prowadzi: Anna'), findsOneWidget);
    expect(find.text('2 osoby'), findsOneWidget);
    expect(find.text('Dołącz jako jedna z pierwszych osób'), findsOneWidget);
    expect(find.text('DOŁĄCZ DO POKOJU'), findsOneWidget);
    expect(find.text('TERAZ NA ŻYWO'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('discover-search-field')),
      'brak-wyniku',
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Brak pasujących pokoi'), findsOneWidget);
    expect(find.text('WYCZYŚĆ FILTRY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Discover localizes its loading failure without leaking errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      polishHost(
        DiscoverScreen(isRootTab: true, roomService: _ErrorRoomService()),
      ),
    );
    await tester.pump();

    expect(find.text('Nie udało się wczytać sekcji Odkrywaj'), findsOneWidget);
    expect(find.text('Ten pokój jest obecnie niedostępny.'), findsOneWidget);
    expect(find.textContaining('Bad state'), findsNothing);
  });
}

UserProfile _profile() => UserProfile(
  uid: 'member',
  email: 'member@yovoice.app',
  displayName: 'Member',
  username: 'member',
  bio: '',
  country: '',
  nativeLanguage: '',
  spokenLanguages: const [],
  learningLanguages: const [],
  photoUrl: null,
  bannerUrl: null,
  website: '',
  accountType: AccountType.personal,
  friendCount: 7,
  followerCount: 12,
  followingCount: 4,
  roomCount: 2,
  communityCount: 1,
  voiceMinutes: 145,
  messageCount: 42,
  activeDays: 5,
  momentCount: 3,
  reactionCount: 8,
  hostMinutes: 30,
  selectedTitleId: 'messages_1',
  unlockedTitleIds: const ['messages_1'],
  unlockedTitleTimestamps: {'messages_1': DateTime(2026, 9, 1)},
  createdAt: DateTime(2026),
);

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

class _ErrorRoomService extends RoomService {
  _ErrorRoomService()
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: true),
      );

  @override
  Stream<List<VoiceRoom>> watchLivePublicRooms() =>
      Stream.error(StateError('unavailable'));
}

VoiceRoom _room() => VoiceRoom(
  id: 'polish-room',
  hostId: 'host',
  hostName: 'Anna',
  hostPhotoUrl: null,
  name: 'Rozmowy wieczorne',
  description: '',
  category: 'Talk',
  visibility: 'public',
  language: 'Polski',
  maxParticipants: 100,
  participantCount: 2,
  memberCount: 2,
  isLive: true,
  roomType: RoomType.community,
  status: RoomStatus.active,
  imageUrl: null,
  approvalRequired: false,
  slowModeSeconds: 0,
  autoMuteNewUsers: true,
  membersCanStartVoice: false,
  createdAt: DateTime(2026, 9, 1),
  updatedAt: DateTime(2026, 9, 1),
);
