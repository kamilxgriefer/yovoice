import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_overview_sections.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';

String _code(String path) => File(path)
    .readAsLinesSync()
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

UserProfile _profile({
  AccountType accountType = AccountType.creator,
  bool premium = true,
  bool ageVerified = true,
  bool audienceEnabled = true,
  bool audienceVisible = true,
}) => UserProfile(
  uid: 'creator',
  email: 'creator@yovoice.app',
  displayName: 'Creator',
  username: 'creator',
  bio: '',
  country: '',
  nativeLanguage: '',
  spokenLanguages: const [],
  learningLanguages: const [],
  photoUrl: null,
  bannerUrl: null,
  premiumIdentity: premium,
  creatorAudienceVisible: audienceVisible,
  creatorAgeVerified: ageVerified,
  creatorAudienceEnabled: audienceEnabled,
  website: '',
  accountType: accountType,
  friendCount: 0,
  followerCount: 0,
  followingCount: 0,
  roomCount: 0,
  communityCount: 0,
  voiceMinutes: 0,
  messageCount: 0,
  activeDays: 0,
  momentCount: 0,
  reactionCount: 0,
  hostMinutes: 0,
  selectedTitleId: null,
  unlockedTitleIds: const [],
  unlockedTitleTimestamps: const {},
  createdAt: null,
);

void main() {
  group('standalone space surfaces are retired from active routing', () {
    const activeRoutingSources = [
      'lib/features/home/presentation/screens/main_shell.dart',
      'lib/features/home/presentation/widgets/more_sheet.dart',
      'lib/features/creator/presentation/screens/creator_studio_screen.dart',
      'lib/features/profile/presentation/screens/profile_screen.dart',
      'lib/features/notifications/presentation/notification_router.dart',
      'lib/features/messages/presentation/widgets/room_link_message_card.dart',
      'lib/features/rooms/presentation/widgets/mini_player/active_room_mini_player.dart',
    ];

    test('active routers import and construct no old Room or Club screen', () {
      const retiredImports = [
        'clubs/presentation/screens/clubs_screen.dart',
        'clubs/presentation/screens/club_overview_screen.dart',
        'clubs/presentation/screens/create_club_screen.dart',
        'discover/presentation/screens/discover_screen.dart',
        'rooms/presentation/screens/room_entry_screen.dart',
        'rooms/presentation/screens/create_room_screen.dart',
      ];
      const retiredConstructors = [
        'ClubsScreen(',
        'ClubOverviewScreen(',
        'CreateClubScreen(',
        'DiscoverScreen(',
        'RoomEntryScreen(',
        'CreateRoomScreen(',
      ];

      for (final path in activeRoutingSources) {
        final source = _code(path);
        for (final retired in [...retiredImports, ...retiredConstructors]) {
          expect(source, isNot(contains(retired)), reason: '$path: $retired');
        }
      }
    });

    test('legacy destination identities resolve to the Servers facade', () {
      for (final destination in [
        MoreDestination.discover,
        MoreDestination.clubs,
      ]) {
        expect(
          moreDestinationScreen(destination).runtimeType.toString(),
          'ServersScreen',
          reason: destination.name,
        );
        expect(
          premiumFeatureForMoreDestination(destination),
          isNull,
          reason: 'retired identities cannot resurrect the Clubs paywall',
        );
      }
    });

    test('the compatibility room creator is only a Server adapter', () {
      final source = _code(
        'lib/features/rooms/presentation/screens/room_type_selector_screen.dart',
      );
      expect(source, contains('CreateServerScreen'));
      expect(source, isNot(contains('CreateRoomScreen(')));
      expect(source, isNot(contains('CreateClubScreen(')));
    });

    test('Home subscriptions use Servers and never old space/follow feeds', () {
      for (final path in [
        'lib/features/home/presentation/widgets/mobile/mobile_home.dart',
        'lib/features/home/presentation/widgets/desktop/desktop_home.dart',
      ]) {
        final source = _code(path);
        expect(source, contains('watchMyServers()'), reason: path);
        for (final retiredWatch in [
          'watchLiveRooms(',
          'watchOwnedRooms(',
          'watchMyCommunities(',
          'watchMyClubs(',
          'watchFollowing(',
          'watchFollowers(',
        ]) {
          expect(
            source,
            isNot(contains(retiredWatch)),
            reason: '$path: $retiredWatch',
          );
        }
      }
    });

    test('the active onboarding tour is Server-first in every locale', () {
      final source = _code(
        'lib/features/onboarding/presentation/guided_onboarding_tour.dart',
      );
      const currentKeys = <String>{
        'Open your servers, listen to Voice Moments, and catch up with your people.',
        'Create a Voice Moment or start a server here.',
        'Create a server here. Open Moments to record a Voice Moment.',
        'Open Creator Studio, Awards, alerts, and Settings. You can replay this tour in Settings anytime.',
        'Find friends, your profile, and Settings here. Replay this tour from Settings anytime.',
      };
      expect(source, isNot(contains('Join live rooms')));
      expect(source, isNot(contains('Voice Room here')));
      expect(source, isNot(contains('Open Clubs')));
      expect(source, isNot(contains('Friends, Clubs')));
      expect(appTranslationKeys, containsAll(currentKeys));
      const retiredKeys = <String>{
        'Join live rooms, listen to Voice Moments, and catch up with your people.',
        'Create a Voice Moment or start a Voice Room here.',
        'YO is your shortcut to a Voice Moment or a new Voice Room.',
        'Open Clubs, Creator Studio, Awards, alerts, and Settings. You can replay this tour in Settings anytime.',
        'Find Friends, Clubs, your profile, and Settings here. Replay this tour from Settings anytime.',
        'Create Room',
      };
      expect(appTranslationKeys.intersection(retiredKeys), isEmpty);
      for (final translations in appTranslations.values) {
        expect(translations.keys.toSet().intersection(retiredKeys), isEmpty);
        for (final key in currentKeys) {
          expect(translations[key], isNotNull);
          expect(translations[key], isNot(key));
        }
      }
    });
  });

  group('navigation remains frozen through the copy/destination cutover', () {
    test('mobile dock geometry and destination order are unchanged', () {
      expect(YoFloatingNavigationDock.horizontalMargin, 0);
      expect(YoFloatingNavigationDock.topClearance, 0);
      expect(YoFloatingNavigationDock.visualHeight, 64);
      expect(YoFloatingNavigationDock.activeIndicatorWidth, 64);
      expect(YoFloatingNavigationDock.activeIndicatorHeight, 56);
      expect([0, 13, 1, 5].map(MainShell.mobileNavigationOrder).toList(), [
        0,
        1,
        2,
        3,
      ]);
      expect([0, 13, 1, 5].map(MainShell.mobileIndexFor).toList(), [
        0,
        13,
        1,
        5,
      ]);
    });

    test('desktop rail dimensions and stable slots are unchanged', () {
      expect(DesktopSidebar.width, 264);
      expect(DesktopSidebar.enlargedTextWidth, 528);
      expect(DesktopSidebar.minimumSupportedHeight, 620);
      expect(DesktopSidebar.compactCreateActionsBelow, 700);
      expect(MainShell.desktopSlots, const {
        3: MoreDestination.discover,
        4: MoreDestination.notifications,
        5: MoreDestination.moments,
        6: MoreDestination.clubs,
        7: MoreDestination.creatorStudio,
        8: MoreDestination.achievements,
        9: MoreDestination.settings,
        10: MoreDestination.moderation,
        11: MoreDestination.staffCenter,
        12: MoreDestination.findCreators,
        13: MoreDestination.servers,
      });
    });

    testWidgets('Home create keeps its control and opens the Server callback', (
      tester,
    ) async {
      var serverCreates = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeQuickActions(
              onCreateRoom: () => serverCreates++,
              onFriends: () {},
            ),
          ),
        ),
      );

      final create = find.byKey(const ValueKey('home-quick-create-server'));
      expect(create, findsOneWidget);
      expect(find.text('Create server'), findsOneWidget);
      expect(find.text('Create room'), findsNothing);
      await tester.tap(create);
      expect(serverCreates, 1);
    });
  });

  group('creator audience is fail-closed', () {
    test('public UI trusts only the server-written visibility decision', () {
      expect(_profile().canExposeCreatorAudience, isTrue);
      expect(
        _profile(audienceVisible: false).canExposeCreatorAudience,
        isFalse,
      );
      expect(
        _profile(
          audienceVisible: false,
          premium: true,
          ageVerified: true,
          audienceEnabled: true,
        ).canExposeCreatorAudience,
        isFalse,
      );
      expect(
        _profile(
          audienceVisible: true,
          premium: false,
          ageVerified: false,
          audienceEnabled: false,
        ).canExposeCreatorAudience,
        isTrue,
      );
    });
  });
}
