import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_people_strip.dart';
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

Widget _host(Stream<List<FriendUser>>? friends, {VoidCallback? onSeeAll}) =>
    MaterialApp(
      theme: AppTheme.darkTheme,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: HomePeopleStrip(friends: friends, onSeeAll: onSeeAll ?? () {}),
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

    expect(find.byType(PeopleStatusAvatar), findsNWidgets(5));
    // Online friends come first, then alphabetical.
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('home-person-b'))).dx,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('home-person-a'))).dx,
      ),
    );
    expect(tester.takeException(), isNull);
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

  testWidgets('renders nothing without friends or without a session', (
    tester,
  ) async {
    await tester.pumpWidget(_host(Stream<List<FriendUser>>.value(const [])));
    await tester.pump();
    expect(find.byKey(const ValueKey('home-people-strip')), findsNothing);
    expect(find.text('Your people'), findsNothing);

    await tester.pumpWidget(_host(null));
    await tester.pump();
    expect(find.byKey(const ValueKey('home-people-strip')), findsNothing);
    expect(tester.takeException(), isNull);
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
    await tester.tap(find.byKey(const ValueKey('home-people-see-all')));
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
    expect(tester.takeException(), isNull);
  });
}
