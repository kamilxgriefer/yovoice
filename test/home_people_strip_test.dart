import 'dart:async';

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
import 'package:yovoice/features/home/presentation/widgets/shared/home_people_strip.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_status.dart';
import 'package:yovoice/features/profile/data/models/profile_visibility.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';

FriendUser _friend(
  String id,
  String name, {
  bool online = false,
  String? availability,
}) => FriendUser(
  id: id,
  displayName: name,
  email: '',
  photoUrl: null,
  isOnline: online,
  availability: availability,
  lastSeen: DateTime(2026, 9, 6),
);

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

Widget _host(
  Stream<List<FriendUser>>? friends, {
  VoidCallback? onSeeAll,
  Stream<UserProfile>? profile,
  PresenceService? presenceService,
  VoidCallback? onRetry,
}) => MaterialApp(
  theme: AppTheme.darkTheme,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(
    body: HomePeopleStrip(
      friends: friends,
      profile: profile,
      presenceService: presenceService,
      onRetry: onRetry,
      onSeeAll: onSeeAll ?? () {},
    ),
  ),
);

void main() {
  testWidgets('renders every friend, online first', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        Stream<List<FriendUser>>.value([
          _friend('a', 'Zofia'),
          _friend('b', 'Ada', online: true),
          _friend('c', 'Marek', online: true, availability: 'busy'),
          _friend('d', 'Ola'),
          _friend('e', 'Jan'),
        ]),
      ),
    );
    await tester.pump();

    // The bug this covers: Home rendered followed creators capped at two, so
    // an account with five friends saw one person.
    final strip = find.byKey(const ValueKey('home-people-strip'));
    expect(strip, findsOneWidget);
    expect(find.text('Twoi znajomi'), findsNothing);
    expect(find.text('Your people'), findsOneWidget);

    // No profile stream here, so the count is friends only.
    expect(find.byType(PeopleStatusAvatar), findsNWidgets(5));
    // Online friends come first, then alphabetical: Ada and Marek (online)
    // precede Jan, Ola and Zofia, and each group is alphabetical.
    double x(String id) =>
        tester.getTopLeft(find.byKey(ValueKey('home-person-$id'))).dx;
    expect(x('b'), lessThan(x('c'))); // Ada before Marek
    expect(x('c'), lessThan(x('e'))); // both online before the first offline
    expect(x('e'), lessThan(x('d'))); // Jan before Ola
    expect(x('d'), lessThan(x('a'))); // Ola before Zofia
    expect(tester.takeException(), isNull);
  });

  testWidgets('the signed-in account is the first tile, ahead of an online '
      'friend', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        Stream<List<FriendUser>>.value([_friend('a', 'Ada', online: true)]),
        profile: Stream<UserProfile>.value(_profile()),
      ),
    );
    await tester.pump();

    final me = find.byKey(const ValueKey('home-people-me'));
    expect(me, findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(
      tester.getTopLeft(me).dx,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('home-person-a'))).dx,
      ),
    );
    // The own tile is a real 44 x 44 target, not a decoration.
    expect(tester.getSize(me).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(me).height, greaterThanOrEqualTo(44));
  });

  testWidgets('availability drives the ring, not just online/offline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        Stream<List<FriendUser>>.value([
          _friend('busy', 'Marek', online: true, availability: 'busy'),
          _friend('brb', 'Ada', online: true, availability: 'away'),
          _friend('off', 'Jan'),
        ]),
      ),
    );
    await tester.pump();
    PeopleStatus statusOf(String id) => tester
        .widget<PeopleStatusAvatar>(find.byKey(ValueKey('home-person-$id')))
        .status;
    expect(statusOf('busy'), PeopleStatus.busy);
    expect(statusOf('brb'), PeopleStatus.brb);
    expect(statusOf('off'), PeopleStatus.away);
  });

  testWidgets('own tile ring and label follow the chosen availability, '
      'including Invisible as grey', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const expected = <UserAvailability, (PeopleStatus, String)>{
      UserAvailability.available: (PeopleStatus.online, 'Available'),
      UserAvailability.away: (PeopleStatus.brb, 'Be right back'),
      UserAvailability.busy: (PeopleStatus.busy, 'Do not disturb'),
      // The projected status is `away`, whose own label is "Away" — the
      // owner must read the state they actually chose.
      UserAvailability.invisible: (PeopleStatus.away, 'Invisible'),
    };
    for (final entry in expected.entries) {
      await tester.pumpWidget(
        _host(
          Stream<List<FriendUser>>.value(const []),
          profile: Stream<UserProfile>.value(_profile(availability: entry.key)),
        ),
      );
      await tester.pump();
      final tile = tester.widget<PeopleStatusAvatar>(
        find.byKey(const ValueKey('home-people-me')),
      );
      expect(tile.status, entry.value.$1, reason: entry.key.wire);
      expect(tile.statusLabel, entry.value.$2, reason: entry.key.wire);
      expect(find.text(entry.value.$2), findsOneWidget);
      expect(tile.showChangeBadge, isTrue);
      // The visible "You" leads — WCAG 2.5.3 Label in Name, and the cue that
      // this tile is the account's own — then the header chip's exact phrase.
      expect(
        tile.semanticLabel,
        'You. Availability: ${entry.value.$2}. Change',
      );
      final palette = AppTheme.darkTheme.extension<AppPalette>()!;
      expect(
        entry.value.$1.foreground(palette),
        entry.key == UserAvailability.invisible
            ? palette.textTertiary
            : isNot(palette.textTertiary),
      );
    }
  });

  testWidgets('the own tile opens the picker and writes the choice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = FakeFirebaseFirestore();
    final service = PresenceService(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
      firestore: db,
    );
    await db.collection('users').doc('me').set({'displayName': 'Kamil'});

    await tester.pumpWidget(
      _host(
        Stream<List<FriendUser>>.value(const []),
        profile: Stream<UserProfile>.value(_profile()),
        presenceService: service,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('home-people-me')));
    await tester.pumpAndSettle();
    expect(find.text('Your availability'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('availability-option-busy')));
    await tester.pumpAndSettle();
    final stored = (await db.collection('users').doc('me').get()).data()!;
    expect(stored['availability'], 'busy');
    // The write never clobbers the rest of the profile document.
    expect(stored['displayName'], 'Kamil');
  });

  testWidgets('an empty friend list keeps the account and offers Add friends', (
    tester,
  ) async {
    var seeAll = 0;
    await tester.pumpWidget(
      _host(
        Stream<List<FriendUser>>.value(const []),
        profile: Stream<UserProfile>.value(_profile()),
        onSeeAll: () => seeAll++,
      ),
    );
    await tester.pump();
    expect(find.text('Your people'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-people-me')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-people-add')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-people-loading')), findsNothing);
    expect(find.byType(HomeSectionError), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key as ValueKey<String>).value.startsWith('home-person-'),
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('home-people-add')));
    expect(seeAll, 1);
  });

  testWidgets('renders nothing without a session at all', (tester) async {
    await tester.pumpWidget(_host(null));
    await tester.pump();
    expect(find.byKey(const ValueKey('home-people-strip')), findsNothing);
    expect(find.text('Your people'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading and error are distinct, and neither reads as '
      '"no friends"', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Loading: a stream that has not emitted yet.
    final pending = StreamController<List<FriendUser>>();
    addTearDown(pending.close);
    await tester.pumpWidget(
      _host(pending.stream, profile: Stream<UserProfile>.value(_profile())),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('home-people-loading')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-people-me')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-people-add')), findsNothing);
    expect(find.byType(HomeSectionError), findsNothing);

    // Error: the friends read failed. The heading and the account stay; the
    // rail must never claim the account has no friends.
    var retries = 0;
    await tester.pumpWidget(
      _host(
        Stream<List<FriendUser>>.error(StateError('permission denied')),
        profile: Stream<UserProfile>.value(_profile()),
        onRetry: () => retries++,
      ),
    );
    await tester.pump();
    expect(find.text('Your people'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-people-me')), findsOneWidget);
    expect(find.byType(HomeSectionError), findsOneWidget);
    expect(find.text('Friends could not be loaded.'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-people-add')), findsNothing);
    expect(find.byKey(const ValueKey('home-people-loading')), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(retries, 1);
  });

  testWidgets('See all opens the Friends destination', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      _host(
        Stream<List<FriendUser>>.value([_friend('a', 'Ada', online: true)]),
        onSeeAll: () => opened++,
      ),
    );
    await tester.pump();
    final seeAll = find.byKey(const ValueKey('home-people-see-all'));
    expect(tester.getSize(seeAll).height, greaterThanOrEqualTo(44));
    await tester.tap(seeAll);
    expect(opened, 1);
  });

  testWidgets('survives 320 px at 200% text without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: HomePeopleStrip(
              profile: Stream<UserProfile>.value(_profile()),
              friends: Stream<List<FriendUser>>.value([
                _friend('a', 'Aleksandra Nowakowska', online: true),
                _friend('b', 'Jan', online: true),
              ]),
              onSeeAll: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('home-people-me')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
