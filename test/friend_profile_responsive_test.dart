import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/friends/presentation/screens/friend_profile_screen.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/follow_list_screen.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';

class _EmptySocialGraphService implements SocialGraphService {
  @override
  Future<MutualFriendsSummary> getMutualFriends(String targetUserId) async =>
      MutualFriendsSummary.empty;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MutualSocialGraphService implements SocialGraphService {
  const _MutualSocialGraphService(this.summary);

  final MutualFriendsSummary summary;

  @override
  Future<MutualFriendsSummary> getMutualFriends(String targetUserId) async =>
      summary;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const currentUserId = 'current-user';
  const friendId = 'friend-user';
  const longDisplayName =
      'Alexandra With A Deliberately Long Display Name For Responsive Layout';
  const longBio =
      'This is a deliberately long biography that exercises wrapping on a '
      'compact phone and remains readable on a very wide desktop without '
      'turning the profile into a stretched mobile layout. It contains enough '
      'copy to span several lines at every supported breakpoint.';

  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;

  setUp(() async {
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: currentUserId, email: 'me@yovoice.app'),
    );
    await db.collection('users').doc(currentUserId).set({
      'uid': currentUserId,
      'displayName': 'Current User',
      'email': 'me@yovoice.app',
    });
    final publicProfile = <String, dynamic>{
      'uid': friendId,
      'displayName': longDisplayName,
      'username': 'alexandra_responsive_profile_name',
      'statusMessage':
          'Linkin Park - In the End https://youtu.be/eVTXPUF4Oz4 playing on repeat tonight!',
      'bio': longBio,
      'nativeLanguage': 'Polish',
      'spokenLanguages': [
        'English',
        'Spanish with a deliberately long regional description',
      ],
      'learningLanguages': ['Japanese', 'Norwegian'],
      'friendCount': 42,
      'followerCount': 128,
      'followingCount': 73,
      'accountType': 'personal',
    };
    await db.collection('publicProfiles').doc(friendId).set(publicProfile);
    await db.collection('socialPresence').doc(friendId).set({
      'uid': friendId,
      'isOnline': true,
    });
  });

  FriendProfileScreen buildScreen({
    Key? key,
    SocialGraphService? socialGraphService,
    ProfileMediaService? profileMediaService,
  }) {
    final notifications = NotificationService(firestore: db, auth: auth);
    return FriendProfileScreen(
      key: key,
      friend: const FriendUser(
        id: friendId,
        displayName: longDisplayName,
        email: 'alexandra@yovoice.app',
        photoUrl: null,
        isOnline: true,
        lastSeen: null,
      ),
      firestore: db,
      auth: auth,
      friendService: FriendService(
        firestore: db,
        auth: auth,
        notificationService: notifications,
      ),
      messageService: MessageService(
        firestore: db,
        auth: auth,
        notificationService: notifications,
      ),
      profileService: ProfileService(firestore: db, auth: auth),
      followService: FollowService(firestore: db, auth: auth),
      socialGraphService: socialGraphService ?? _EmptySocialGraphService(),
      profileMediaService: profileMediaService,
    );
  }

  testWidgets('rapid stat taps push one follow-list route', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.darkTheme, home: buildScreen()),
    );
    for (var pump = 0; pump < 8; pump++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    final followers = find.byKey(
      const ValueKey('friend-profile-stat-followers'),
    );
    final scrollable = find
        .descendant(
          of: find.byKey(const ValueKey('friend-profile-content-frame')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(followers, 180, scrollable: scrollable);
    final tapRegion = tester.widget<AccessibleTapRegion>(followers);
    tapRegion.onTap!();
    tapRegion.onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(FollowListScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mutual avatar ignores legacy URL and uses viewer grant', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final requestedTargets = <String>[];
    final media = ProfileMediaService(
      auth: auth,
      invoker: (_, request) async {
        requestedTargets.add(request['userId']! as String);
        return {
          'schemaVersion': 1,
          'available': false,
          'expiresAtMillis': DateTime.now()
              .toUtc()
              .add(const Duration(seconds: 80))
              .millisecondsSinceEpoch,
        };
      },
    );
    const maliciousUrl = 'https://tracker.invalid/private-avatar.jpg';
    final graph = _MutualSocialGraphService(
      MutualFriendsSummary(
        count: 1,
        sample: [
          SuggestedFriend(
            uid: 'mutual-user',
            displayName: 'Mutual User',
            photoUrl: maliciousUrl,
            mutualCount: 1,
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: buildScreen(
          socialGraphService: graph,
          profileMediaService: media,
        ),
      ),
    );
    for (var pump = 0; pump < 8; pump++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    final mutualLabel = find.text('1 mutual friend');
    final scrollable = find
        .descendant(
          of: find.byKey(const ValueKey('friend-profile-content-frame')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(mutualLabel, 180, scrollable: scrollable);
    await tester.pumpAndSettle();

    expect(requestedTargets, contains('mutual-user'));
    expect(
      find.byWidgetPredicate((widget) {
        if (widget is! Image) return false;
        final provider = widget.image;
        return provider is NetworkImage && provider.url == maliciousUrl;
      }),
      findsNothing,
      reason: 'denormalized photoUrl must never bypass profile-media grants',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps phones full-width and centres an 880px profile feed '
      'across desktop widths with long content', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final size in const [
      Size(320, 640),
      Size(390, 844),
      Size(430, 932),
      Size(768, 1024),
      Size(1100, 800),
      Size(1440, 900),
      Size(2560, 1440),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: buildScreen(key: ValueKey(size.width)),
        ),
      );
      for (var pump = 0; pump < 8; pump++) {
        await tester.pump(const Duration(milliseconds: 80));
      }

      final frame = tester.getRect(
        find.byKey(const ValueKey('friend-profile-content-frame')),
      );
      final background = tester.getRect(
        find.byKey(const ValueKey('friend-profile-background')),
      );
      final expectedWidth = size.width > 880 ? 880.0 : size.width;
      final expectedLeft = (size.width - expectedWidth) / 2;

      expect(frame.width, expectedWidth, reason: '$size frame width');
      expect(frame.left, expectedLeft, reason: '$size top-centred frame');
      expect(background.width, size.width, reason: '$size full-bleed bg');
      expect(find.text(longDisplayName), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(longBio),
        120,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('friend-profile-content-frame')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text(longBio), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('friend-profile-vibe')),
        120,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('friend-profile-content-frame')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        find.text('Linkin Park - In the End playing on repeat tonight!'),
        findsOneWidget,
      );
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('youtu.be'), findsOneWidget);
      if (size.width > 880) {
        expect(
          tester
              .getSize(find.byKey(const ValueKey('friend-profile-bio-frame')))
              .width,
          lessThanOrEqualTo(680),
        );
      }
      expect(tester.takeException(), isNull, reason: '$size overflow');
    }
  });

  testWidgets('320px at 200% text stacks stats and actions with accessible '
      '44px targets', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();

    for (final size in const [Size(320, 568), Size(320, 844)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: buildScreen(key: ValueKey(size.height)),
          ),
        ),
      );
      for (var pump = 0; pump < 8; pump++) {
        await tester.pump(const Duration(milliseconds: 80));
      }

      expect(
        find.bySemanticsLabel('Profile photo of $longDisplayName'),
        findsOneWidget,
      );
      final scrollable = find
          .descendant(
            of: find.byKey(const ValueKey('friend-profile-content-frame')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('friend-profile-stats')),
        180,
        scrollable: scrollable,
      );

      expect(
        tester.getCenter(find.text('Followers')).dy,
        greaterThan(tester.getCenter(find.text('Friends')).dy),
        reason: '$size stats should stack at 200% text',
      );
      expect(
        tester.getCenter(find.text('Following')).dy,
        greaterThan(tester.getCenter(find.text('Followers')).dy),
      );
      final followers = find.byKey(
        const ValueKey('friend-profile-stat-followers'),
      );
      expect(tester.getSize(followers).height, greaterThanOrEqualTo(44));
      expect(
        tester
            .getSemantics(followers)
            .getSemanticsData()
            .hasAction(ui.SemanticsAction.tap),
        isTrue,
      );

      final followButton = find.byKey(
        const ValueKey('friend-profile-follow-button'),
      );
      final messageButton = find.byKey(
        const ValueKey('friend-profile-message-button'),
      );
      await tester.scrollUntilVisible(
        messageButton,
        180,
        scrollable: scrollable,
      );

      expect(
        tester.getCenter(messageButton).dy,
        greaterThan(tester.getCenter(followButton).dy),
        reason: '$size actions should stack at 200% text',
      );
      expect(tester.getSize(followButton).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(messageButton).height, greaterThanOrEqualTo(44));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('friend-profile-vibe')),
        180,
        scrollable: scrollable,
      );
      expect(
        find.text('Linkin Park - In the End playing on repeat tonight!'),
        findsOneWidget,
      );
      final vibeLink = find.bySemanticsLabel('Open in YouTube, youtu.be');
      expect(vibeLink, findsOneWidget);
      expect(tester.getSize(vibeLink).height, greaterThanOrEqualTo(48));
      expect(
        tester
            .getSemantics(vibeLink)
            .getSemanticsData()
            .hasAction(ui.SemanticsAction.tap),
        isTrue,
      );
      expect(
        tester
            .getSemantics(followButton)
            .getSemanticsData()
            .hasAction(ui.SemanticsAction.tap),
        isTrue,
      );
      expect(
        tester
            .getSemantics(messageButton)
            .getSemanticsData()
            .hasAction(ui.SemanticsAction.tap),
        isTrue,
      );
      expect(tester.takeException(), isNull, reason: '$size at 200% text');
    }
    semantics.dispose();
  });

  testWidgets('profile canvas, copy and cards follow Pearl and dark palettes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(768, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final themeCase in <({ThemeData theme, AppPalette palette})>[
      (theme: AppTheme.lightTheme, palette: AppPalette.light),
      (theme: AppTheme.darkTheme, palette: AppPalette.dark),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: themeCase.theme,
          home: buildScreen(key: ValueKey(themeCase.theme.brightness)),
        ),
      );
      for (var pump = 0; pump < 8; pump++) {
        await tester.pump(const Duration(milliseconds: 80));
      }

      final background = tester.widget<YoPageBackground>(
        find.byKey(const ValueKey('friend-profile-background')),
      );
      final gradient =
          (background.decoration! as BoxDecoration).gradient! as RadialGradient;
      expect(gradient.colors.last, themeCase.palette.background);

      final stats = tester.widget<Container>(
        find.byKey(const ValueKey('friend-profile-stats')),
      );
      final statsDecoration = stats.decoration! as BoxDecoration;
      expect(statsDecoration.color, themeCase.palette.surface);
      expect(
        (statsDecoration.border! as Border).top.color,
        themeCase.palette.border,
      );

      final displayName = tester.widget<Text>(find.text(longDisplayName));
      expect(displayName.style!.color, themeCase.palette.textPrimary);
      final username = tester.widget<Text>(
        find.text('@alexandra_responsive_profile_name'),
      );
      expect(username.style!.color, themeCase.palette.textSecondary);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Pearl destructive confirmation keeps readable semantic pairs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(768, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: buildScreen()),
    );
    for (var pump = 0; pump < 8; pump++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    final scrollable = find
        .descendant(
          of: find.byKey(const ValueKey('friend-profile-content-frame')),
          matching: find.byType(Scrollable),
        )
        .first;
    final removeFriend = find.text('Remove friend');
    await tester.scrollUntilVisible(removeFriend, 180, scrollable: scrollable);
    await tester.tap(removeFriend);
    await tester.pumpAndSettle();

    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.backgroundColor, AppPalette.light.surfaceRaised);
    final title = tester.widget<Text>(find.text('Remove friend?'));
    expect(title.style!.color, AppPalette.light.textPrimary);
    final remove = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Remove'),
    );
    expect(
      remove.style!.backgroundColor!.resolve(<WidgetState>{}),
      AppTheme.lightTheme.colorScheme.error,
    );
    expect(
      remove.style!.foregroundColor!.resolve(<WidgetState>{}),
      AppTheme.lightTheme.colorScheme.onError,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
