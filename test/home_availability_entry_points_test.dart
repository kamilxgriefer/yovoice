import 'dart:math' as math;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/core/presence/user_availability.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_people_strip.dart';
import 'package:yovoice/features/profile/data/models/profile_visibility.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/shared/widgets/profile/availability_picker.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';

import 'semantics_probe.dart';

/// Home now offers TWO ways to change availability — the readable chip in
/// the header and the ringed "You" tile that leads the friends rail — and
/// the app already offered two more (the More sheet, the desktop sidebar
/// profile card).
///
/// The risk a second affordance creates is drift: two pickers, two wordings,
/// two write paths, or a chip that is visually 27 px and therefore
/// untappable on a phone. This file pins the shared contract instead of
/// re-testing each screen: one picker, one phrase, one write, and a real
/// 44 px target that never inflates the pill.
UserProfile _profile({
  UserAvailability availability = UserAvailability.available,
}) => UserProfile(
  uid: 'me',
  email: 'me@yovoice.app',
  displayName: 'Kamil',
  username: 'kamil',
  bio: '',
  country: '',
  nativeLanguage: '',
  spokenLanguages: const [],
  learningLanguages: const [],
  photoUrl: null,
  bannerUrl: null,
  availability: availability,
  website: '',
  accountType: AccountType.personal,
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
  createdAt: DateTime(2026, 1, 1),
  profileVisibility: ProfileVisibility.public,
);

Widget _app(Widget child, {Size size = const Size(390, 844), Locale? locale}) =>
    MaterialApp(
      theme: AppTheme.darkTheme,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(body: Center(child: child)),
      ),
    );

/// WCAG relative-luminance contrast, so the focus ring is asserted as a
/// visible indicator rather than as a colour constant.
double _contrast(Color a, Color b) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  final first = luminance(a);
  final second = luminance(b);
  final lighter = math.max(first, second);
  final darker = math.min(first, second);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  testWidgets('the Home chip reserves a 44 px target without inflating the '
      'pill, and a hit in the band still opens the picker', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        const AvailabilityChip(
          availability: UserAvailability.busy,
          hitTargetSize: 44,
        ),
      ),
    );
    await tester.pump();

    final chip = find.byType(AvailabilityChip);
    final pill = find.byKey(const ValueKey('availability-chip'));
    final chipSize = tester.getSize(chip);
    final pillSize = tester.getSize(pill);
    expect(chipSize.height, greaterThanOrEqualTo(44));
    expect(
      pillSize.height,
      lessThan(32),
      reason: 'the visible pill must stay a pill, not become a button',
    );
    expect(chipSize.width, pillSize.width);

    // A tap in the reserved band above the pill lands on the pill, the way
    // Material's own minimum-target padding forwards it.
    final band = tester.getRect(chip);
    await tester.tapAt(Offset(band.center.dx, band.top + 3));
    await tester.pumpAndSettle();
    expect(find.text('Your availability'), findsOneWidget);
  });

  testWidgets('a chip without a hit target is exactly its pill', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const AvailabilityChip(availability: UserAvailability.busy)),
    );
    await tester.pump();
    // No reserved band: the chip is exactly its pill. Nothing in `lib/`
    // ships this configuration any more — the four entry points all pass a
    // target — but the widget must still lay out unchanged for the previews
    // and captures that do.
    expect(
      tester.getSize(find.byType(AvailabilityChip)),
      tester.getSize(find.byKey(const ValueKey('availability-chip'))),
    );
  });

  testWidgets('every shipped chip configuration is a 44 x 44 target on BOTH '
      'axes, and none of them inflates the pill', (tester) async {
    tester.view.physicalSize = const Size(600, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The four entry points that open the picker, as `lib/` builds them:
    // the More sheet and Home (default), the desktop sidebar profile card
    // (compact) and the profile name plate (dense).
    const shipped = <String, AvailabilityChip>{
      'more sheet / home': AvailabilityChip(
        availability: UserAvailability.busy,
        hitTargetSize: 44,
      ),
      'desktop sidebar': AvailabilityChip(
        availability: UserAvailability.busy,
        compact: true,
        hitTargetSize: 44,
      ),
      'profile name plate': AvailabilityChip(
        availability: UserAvailability.busy,
        dense: true,
        hitTargetSize: 44,
      ),
    };
    for (final entry in shipped.entries) {
      await tester.pumpWidget(_app(entry.value, size: const Size(600, 400)));
      await tester.pump();
      final outer = tester.getSize(find.byType(AvailabilityChip));
      final pill = tester.getSize(
        find.byKey(const ValueKey('availability-chip')),
      );
      expect(
        outer.width,
        greaterThanOrEqualTo(44),
        reason: '${entry.key}: the compact chip is 42 px wide on its own',
      );
      expect(outer.height, greaterThanOrEqualTo(44), reason: entry.key);
      expect(
        pill.height,
        lessThan(32),
        reason: '${entry.key}: the visible pill must stay a pill',
      );
    }
  });

  testWidgets('the desktop sidebar chip is a 44 x 44 target on every rail '
      'that can pay for it', (tester) async {
    addTearDown(ProfileService.resetCurrentProfileCache);
    final db = FakeFirebaseFirestore();
    const uid = 'me';
    await db.collection('users').doc(uid).set({
      'uid': uid,
      'displayName': 'Kamil',
      'email': 'me@yovoice.app',
      'availability': UserAvailability.busy.wire,
    });
    final firebaseAuth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: uid, email: 'me@yovoice.app'),
    );

    // The rail tiers its density by measured height: at and above
    // `compactCreateActionsBelow` the chip reserves its target; below it the
    // rail is already fighting to keep every destination visible, so the
    // chip stays the 42 x 26 pill rather than clipping the nav column.
    for (final (railHeight, expected) in [(900.0, 44.0), (620.0, 26.0)]) {
      ProfileService.resetCurrentProfileCache();
      tester.view.physicalSize = Size(1440, railHeight);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          SizedBox(
            height: railHeight,
            child: DesktopSidebar(
              active: DesktopNavItem.home,
              unreadConversationCount: 0,
              unreadNotificationCount: 0,
              onSelect: (_) {},
              onCreateRoom: () {},
              onCreateMoment: () {},
              onOpenProfile: () {},
              onOpenProfileSettings: () {},
              profileService: ProfileService(firestore: db, auth: firebaseAuth),
            ),
          ),
          size: Size(1440, railHeight),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      final chip = find.byType(AvailabilityChip);
      expect(chip, findsOneWidget, reason: 'rail $railHeight');
      final size = tester.getSize(chip);
      expect(size.height, expected, reason: 'rail $railHeight');
      if (expected == 44) {
        expect(
          size.width,
          greaterThanOrEqualTo(44),
          reason: 'the compact pill is only 42 px wide on its own',
        );
      }
    }
  });

  testWidgets('both Home affordances announce one phrase for one action, and '
      'the chip never swallows the text beside it', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    for (final availability in UserAvailability.values) {
      await tester.pumpWidget(
        _app(
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The Home greeting's exact arrangement: plain Text siblings
              // in the same Column as the chip. Plain Text carries no flags,
              // so a chip whose Semantics is not a container merges them all
              // into its own button node.
              const Text('Good morning,'),
              const Text('Kamil'),
              AvailabilityChip(availability: availability, hitTargetSize: 44),
              HomePeopleStrip(
                friends: Stream<List<FriendUser>>.value(const []),
                profile: Stream<UserProfile>.value(
                  _profile(availability: availability),
                ),
                onSeeAll: () {},
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      final copy = AppLocalizations.of(
        tester.element(find.byType(AvailabilityChip)),
      );
      final status = availability.localizedLabel(copy);
      final phrase = 'Availability: $status. Change';

      // The COMPILED node, not the `Semantics` widget's properties: the
      // widget always said the right thing, the announced string did not.
      final chipLabel = announcedLabelOf(tester, find.byType(AvailabilityChip));
      expect(chipLabel, phrase, reason: availability.wire);
      expect(
        chipLabel,
        isNot(anyOf(contains('Good morning'), contains('Kamil'))),
        reason: 'the greeting is static content, not part of a control name',
      );
      expect(
        status.allMatches(chipLabel).length,
        1,
        reason: 'the pill Text must not repeat the status inside the button',
      );

      // Exactly one button node carries the phrase — the chip. The rail's
      // own tile leads with the visible "You", so it is a different string
      // for the same action, not a second copy of this one.
      expect(
        compiledButtonLabels(tester).where((label) => label == phrase).length,
        1,
        reason: availability.wire,
      );
      final tileLabel = announcedLabelOf(
        tester,
        find.byKey(const ValueKey('home-people-me')),
      );
      expect(tileLabel, '${copy.homeYou}. $phrase', reason: availability.wire);
    }
    semantics.dispose();
  });

  testWidgets('the own tile keeps its visible name in its accessible name, '
      'in every locale and every state', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    for (final locale in const [Locale('en'), Locale('pl')]) {
      for (final availability in UserAvailability.values) {
        await tester.pumpWidget(
          _app(
            HomePeopleStrip(
              friends: Stream<List<FriendUser>>.value(const []),
              profile: Stream<UserProfile>.value(
                _profile(availability: availability),
              ),
              onSeeAll: () {},
            ),
            locale: locale,
          ),
        );
        await tester.pump();

        final copy = AppLocalizations.of(
          tester.element(find.byType(HomePeopleStrip)),
        );
        final tile = find.byKey(const ValueKey('home-people-me'));
        final label = announcedLabelOf(tester, tile);
        final reason = '${locale.languageCode}/${availability.wire}';
        // WCAG 2.5.3 Label in Name: "You" / "Ty" is printed under the
        // avatar, so "tap You" has to reach this tile.
        expect(label, contains(copy.homeYou), reason: reason);
        expect(label, startsWith(copy.homeYou), reason: reason);
        expect(
          label,
          contains(availability.localizedLabel(copy)),
          reason: reason,
        );
        expect(label, contains(copy.text('Change', 'Zmień')), reason: reason);
        // And the visible text really is the string being echoed.
        expect(find.text(copy.homeYou), findsOneWidget, reason: reason);
      }
    }
    semantics.dispose();
  });

  testWidgets('keyboard focus on a people tile is a real 2 px boundary, not '
      'a 14 % wash', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
      final palette = theme.extension<AppPalette>()!;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: HomePeopleStrip(
              friends: Stream<List<FriendUser>>.value(const []),
              profile: Stream<UserProfile>.value(_profile()),
              onSeeAll: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      Border borderOf(Finder tile) {
        final decorated = tester
            .widgetList<AnimatedContainer>(
              find.descendant(
                of: tile,
                matching: find.byType(AnimatedContainer),
              ),
            )
            .last;
        return (decorated.decoration! as BoxDecoration).border! as Border;
      }

      for (final key in const [
        ValueKey('home-people-me'),
        ValueKey('home-people-add'),
      ]) {
        final tile = find.byKey(key);
        expect(tile, findsOneWidget);
        expect(
          borderOf(tile).top.color,
          Colors.transparent,
          reason: 'unfocused tiles draw no boundary',
        );

        // Any node inside the tile resolves to the ink surface's own focus
        // node, which is what a Tab key press would land on.
        final inner = find.descendant(of: tile, matching: find.byType(Text));
        Focus.of(tester.element(inner.first)).requestFocus();
        await tester.pumpAndSettle();

        final focused = borderOf(tile).top;
        expect(focused.width, greaterThanOrEqualTo(2), reason: '$key');
        expect(
          focused.color,
          palette.focus,
          reason:
              '$key: the focus ring uses the palette focus token, which '
              'is contrast-checked against the background',
        );
        expect(
          _contrast(focused.color, palette.background),
          greaterThanOrEqualTo(3),
          reason: '$key on ${theme.brightness.name}',
        );
      }
    }
  });

  testWidgets('every entry point opens the same picker, with all four states '
      'and the current one marked', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = FakeFirebaseFirestore();
    final presence = PresenceService(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
      firestore: db,
    );

    Future<void> open(Finder target) async {
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.text('Your availability'), findsOneWidget);
      for (final option in UserAvailability.values) {
        expect(
          find.byKey(ValueKey('availability-option-${option.wire}')),
          findsOneWidget,
          reason: option.wire,
        );
      }
      // The state the account is already in is the checked one — the sheet
      // never presents a guess as the current choice.
      final selected = tester.widget<ListTile>(
        find.byKey(const ValueKey('availability-option-away')),
      );
      expect(selected.selected, isTrue);
      expect(selected.trailing, isA<Icon>());
      Navigator.of(tester.element(find.text('Your availability'))).pop();
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      _app(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AvailabilityChip(
              availability: UserAvailability.away,
              hitTargetSize: 44,
              presenceService: null,
            ),
            HomePeopleStrip(
              friends: Stream<List<FriendUser>>.value(const []),
              profile: Stream<UserProfile>.value(
                _profile(availability: UserAvailability.away),
              ),
              presenceService: presence,
              onSeeAll: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    await open(find.byKey(const ValueKey('availability-chip')));
    await open(find.byKey(const ValueKey('home-people-me')));

    // Choosing the state that is already current writes nothing: the picker
    // closes without touching presence.
    await tester.tap(find.byKey(const ValueKey('home-people-me')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('availability-option-away')));
    await tester.pumpAndSettle();
    expect((await db.collection('users').doc('me').get()).exists, isFalse);
  });

  testWidgets('a failed write reports it instead of pretending the choice '
      'landed', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // A signed-out PresenceService is the honest stand-in for a rejected
    // write: setAvailability throws rather than resolving.
    final presence = PresenceService(
      auth: MockFirebaseAuth(signedIn: false),
      firestore: FakeFirebaseFirestore(),
    );
    await tester.pumpWidget(
      _app(
        HomePeopleStrip(
          friends: Stream<List<FriendUser>>.value(const []),
          profile: Stream<UserProfile>.value(_profile()),
          presenceService: presence,
          onSeeAll: () {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('home-people-me')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('availability-option-busy')));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not change your availability. Try again.'),
      findsOneWidget,
    );
    // And the tile still shows the state that is actually stored.
    expect(
      tester
          .widget<PeopleStatusAvatar>(
            find.byKey(const ValueKey('home-people-me')),
          )
          .statusLabel,
      'Available',
    );
  });
}
