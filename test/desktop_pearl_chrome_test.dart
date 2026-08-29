import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/followed_creators_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/premium_desktop_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/sponsored_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/timezone_world_map_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/voice_trending_card.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

void main() {
  testWidgets(
    'TimezoneWorldMapCard uses Pearl semantic pairs with AA text contrast',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          themeMode: ThemeMode.light,
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(alwaysUse24HourFormat: true),
              child: SizedBox(
                width: 240,
                child: TimezoneWorldMapCard(
                  source: ClockSource(
                    now: () => DateTime.utc(2026, 8, 29, 18, 42),
                    zoneLabel: () => 'UTC',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final surface = _containerColor(
        tester,
        const ValueKey('desktop-timezone-card'),
      );
      expect(surface, AppPalette.light.surfaceRaised);
      _expectTextContrast(tester, '18:42', surface, 4.5);
      _expectTextContrast(tester, 'UTC', surface, 4.5);

      final scheme = AppTheme.lightTheme.colorScheme;
      _expectTextContrast(tester, 'UTC+00:00', scheme.primaryContainer, 4.5);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('TimezoneWorldMapCard preserves its dark AA semantic pairs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(alwaysUse24HourFormat: true),
            child: SizedBox(
              width: 240,
              child: TimezoneWorldMapCard(
                source: ClockSource(
                  now: () => DateTime.utc(2026, 8, 29, 18, 42),
                  zoneLabel: () => 'UTC',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final surface = _containerColor(
      tester,
      const ValueKey('desktop-timezone-card'),
    );
    expect(surface, AppPalette.dark.surfaceRaised);
    _expectTextContrast(tester, '18:42', surface, 4.5);
    _expectTextContrast(tester, 'UTC', surface, 4.5);
    _expectTextContrast(
      tester,
      'UTC+00:00',
      AppTheme.darkTheme.colorScheme.primaryContainer,
      4.5,
    );
  });

  testWidgets(
    'real DesktopSidebar and complete Home right column stay Pearl-native',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'pearl-user', email: 'pearl@yovoice.app'),
      );
      final rooms = RoomService(firestore: firestore, auth: auth);
      final feed = HomeFeedService(firestore: firestore, auth: auth);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          themeMode: ThemeMode.light,
          home: Scaffold(
            body: Row(
              children: [
                DesktopSidebar(
                  active: DesktopNavItem.home,
                  unreadConversationCount: 3,
                  unreadNotificationCount: 2,
                  onSelect: (_) {},
                  onCreateRoom: () {},
                  onCreateMoment: () {},
                  onOpenProfile: () {},
                  onOpenProfileSettings: () {},
                ),
                Expanded(
                  child: ColoredBox(
                    color: AppPalette.light.background,
                    child: Align(
                      alignment: Alignment.topRight,
                      child: SizedBox(
                        width: 344,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(6, 20, 20, 20),
                          children: [
                            FollowedCreatorsCard(
                              currentUserId: 'pearl-user',
                              onOpenCreator: (_) {},
                              onViewAll: () {},
                              followService: FollowService(
                                firestore: firestore,
                                auth: auth,
                              ),
                              feedService: feed,
                              roomService: rooms,
                            ),
                            const SizedBox(height: 16),
                            VoiceTrendingCard(
                              onOpenRoom: (_) {},
                              onSeeAll: () {},
                              onSeeAllRooms: () {},
                              roomService: rooms,
                              discoveryService: MomentDiscoveryService(
                                firestore: firestore,
                                auth: auth,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const SponsoredCard(),
                            const SizedBox(height: 16),
                            PremiumDesktopCard(onCheckPlans: () {}),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.byType(DesktopSidebar), findsOneWidget);
      expect(find.byType(TimezoneWorldMapCard), findsOneWidget);
      expect(tester.takeException(), isNull);

      expect(
        _containerColor(tester, const ValueKey('desktop-sidebar-surface')),
        AppPalette.light.navigationSurface,
      );
      _expectTextContrast(
        tester,
        'YO Voice',
        AppPalette.light.navigationSurface,
        4.5,
      );
      _expectTextContrast(
        tester,
        'Create Voice Moment',
        AppPalette.light.surfaceRaised,
        4.5,
      );

      expect(
        _containerColor(
          tester,
          const ValueKey('desktop-followed-creators-card'),
        ),
        AppPalette.light.surface,
      );
      expect(
        _containerColor(tester, const ValueKey('desktop-voice-trending-card')),
        AppPalette.light.surface,
      );
      expect(
        _containerColor(tester, const ValueKey('desktop-sponsored-card')),
        AppPalette.light.surfaceMuted,
      );
      expect(
        _containerColor(tester, const ValueKey('desktop-premium-card')),
        AppPalette.light.surface,
      );

      _expectTextContrast(
        tester,
        'Top creators you follow',
        AppPalette.light.surface,
        4.5,
      );
      _expectTextContrast(
        tester,
        'Voice Trending',
        AppPalette.light.surface,
        4.5,
      );
      _expectTextContrast(
        tester,
        'Your campaign could sit here',
        AppPalette.light.surfaceMuted,
        4.5,
      );
      _expectTextContrast(
        tester,
        'Become a Creator',
        AppPalette.light.surfaceMuted,
        4.5,
      );
      _expectTextContrast(
        tester,
        'Check plans',
        AppTheme.lightTheme.colorScheme.primary,
        4.5,
      );
      _expectTextContrast(
        tester,
        'Check plans',
        AppTheme.lightTheme.colorScheme.secondary,
        4.5,
      );
    },
  );
}

Color _containerColor(WidgetTester tester, Key key) {
  final container = tester.widget<Container>(find.byKey(key));
  final decoration = container.decoration! as BoxDecoration;
  return decoration.color!;
}

void _expectTextContrast(
  WidgetTester tester,
  String label,
  Color background,
  double minimum,
) {
  final text = tester.widget<Text>(find.text(label));
  final foreground = text.style?.color;
  expect(foreground, isNotNull, reason: '$label must own its foreground');
  expect(
    _contrastRatio(foreground!, background),
    greaterThanOrEqualTo(minimum),
    reason: '$label must meet $minimum:1 against its rendered surface',
  );
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + .05) / (darker + .05);
}
