// "Zacznij tutaj" (firstSteps A, 2026-10-03): the step model, the host's
// visibility rules and the card's rows.
//
// The rule under test everywhere: nothing is counted or shown unless it is
// real. A source that has not answered (or failed) keeps the card hidden; a
// step is ticked only from the state it is defined by; the card closes for
// good with its X or once every step is done.

import 'dart:async';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/home/data/first_steps.dart';
import 'package:yovoice/features/home/data/first_steps_store.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_first_steps_card.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';

const _uid = 'me';

class _MemoryStore implements FirstStepsStore {
  _MemoryStore([FirstStepsOutcome? initial]) {
    if (initial != null) values[_uid] = initial;
  }

  final Map<String, FirstStepsOutcome> values = <String, FirstStepsOutcome>{};
  final List<FirstStepsOutcome> writes = <FirstStepsOutcome>[];
  Object? readError;

  @override
  Future<FirstStepsOutcome?> read(String userId) async {
    final error = readError;
    if (error != null) throw error;
    return values[userId];
  }

  @override
  Future<void> write(String userId, FirstStepsOutcome outcome) async {
    values[userId] = outcome;
    writes.add(outcome);
  }
}

UserProfile _profile({
  int moments = 0,
  int following = 0,
  int friends = 0,
  DateTime? updatedAt,
}) => UserProfile(
  uid: _uid,
  email: '',
  displayName: 'Kamil',
  username: 'kamil',
  bio: '',
  country: '',
  nativeLanguage: '',
  spokenLanguages: const <String>[],
  learningLanguages: const <String>[],
  photoUrl: null,
  bannerUrl: null,
  website: '',
  accountType: AccountType.personal,
  friendCount: friends,
  followerCount: 0,
  followingCount: 0,
  accountFollowingCount: following,
  roomCount: 0,
  communityCount: 0,
  voiceMinutes: 0,
  messageCount: 0,
  activeDays: 0,
  momentCount: moments,
  reactionCount: 0,
  hostMinutes: 0,
  selectedTitleId: null,
  unlockedTitleIds: const <String>[],
  unlockedTitleTimestamps: const <String, DateTime>{},
  createdAt: null,
  profileUpdatedAt: updatedAt,
);

FriendUser _friend(String id) => FriendUser(
  id: id,
  displayName: 'Ola Nowak',
  email: '',
  photoUrl: null,
  isOnline: false,
  lastSeen: null,
);

Server _server() => const Server(
  id: 's',
  name: 'Nocne Granie',
  description: '',
  ownerId: _uid,
  type: ServerType.community,
  privacy: ServerPrivacy.public,
);

AsyncSnapshot<List<T>> _data<T>(List<T> value) =>
    AsyncSnapshot<List<T>>.withData(ConnectionState.active, value);

/// A media service whose avatar grant answers [available], or throws while
/// [fail] is set. Counts the calls it received.
class _Media {
  _Media({this.available = true, this.fail = false});

  bool available;
  bool fail;
  int calls = 0;

  late final ProfileMediaService service = ProfileMediaService(
    auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _uid)),
    invoker: (callable, request) async {
      calls += 1;
      if (fail) throw StateError('offline');
      final expiry = DateTime.now()
          .add(const Duration(seconds: 60))
          .millisecondsSinceEpoch;
      return <Object?, Object?>{
        'schemaVersion': 1,
        'available': available,
        'expiresAtMillis': expiry,
        if (available) ...<Object?, Object?>{
          'url': 'https://storage.googleapis.com/b/users/me/profile/avatar.jpg',
          'generation': '1700000000000001',
          'contentType': 'image/jpeg',
          'size': 4096,
        },
      };
    },
  );
}

class _Taps {
  final List<String> log = <String>[];
}

Widget _host({
  required Stream<UserProfile>? profile,
  required FirstStepsStore store,
  required ProfileMediaService media,
  AsyncSnapshot<List<FriendUser>>? friends,
  AsyncSnapshot<List<Server>>? servers,
  bool? contentEnabled = true,
  _Taps? taps,
  Locale locale = const Locale('pl'),
  double textScale = 1,
  String userId = _uid,
}) => MaterialApp(
  theme: AppTheme.darkTheme,
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: HomeFirstSteps(
          userId: userId,
          profile: profile,
          friendsSnapshot: friends ?? _data(const <FriendUser>[]),
          serversSnapshot: servers ?? _data(const <Server>[]),
          contentEnabled: contentEnabled,
          profileMediaService: media,
          store: store,
          onAddPhoto: (_) => taps?.log.add('photo'),
          onAddFriend: () => taps?.log.add('friend'),
          onOpenServers: () => taps?.log.add('server'),
          onRecordVoice: () => taps?.log.add('voice'),
          onFollow: () => taps?.log.add('follow'),
        ),
      ),
    ),
  ),
);

Finder _step(FirstStep step) =>
    find.byKey(ValueKey('home-first-step-${step.name}'));

void main() {
  setUp(ProfileMediaService.clearAllMediaAccessCaches);

  group('FirstStepsProgress.evaluate', () {
    test('is unknown while any source has not answered', () {
      FirstStepsProgress? evaluate({
        bool? photo = true,
        int? friends = 0,
        int? servers = 0,
        int? moments = 0,
        int? following = 0,
        bool content = true,
      }) => FirstStepsProgress.evaluate(
        hasPhoto: photo,
        friendCount: friends,
        serverCount: servers,
        momentCount: moments,
        followingCount: following,
        contentEnabled: content,
      );

      expect(evaluate(), isNotNull);
      expect(evaluate(photo: null), isNull);
      expect(evaluate(friends: null), isNull);
      expect(evaluate(servers: null), isNull);
      expect(evaluate(moments: null), isNull);
      expect(evaluate(following: null), isNull);
      // The follow counter is not consulted while Treści is off.
      expect(evaluate(following: null, content: false), isNotNull);
    });

    test('lists five steps with Treści and four without it', () {
      final withContent = FirstStepsProgress.evaluate(
        hasPhoto: true,
        friendCount: 0,
        serverCount: 0,
        momentCount: 0,
        followingCount: 0,
        contentEnabled: true,
      )!;
      expect(withContent.steps, FirstStep.values);
      expect(withContent.total, 5);
      expect(withContent.doneCount, 1);
      expect(withContent.next, FirstStep.friend);

      final without = FirstStepsProgress.evaluate(
        hasPhoto: false,
        friendCount: 2,
        serverCount: 1,
        momentCount: 3,
        followingCount: 9,
        contentEnabled: false,
      )!;
      expect(without.steps, isNot(contains(FirstStep.follow)));
      expect(without.total, 4);
      expect(without.doneCount, 3);
      expect(without.next, FirstStep.photo);
      expect(without.isComplete, isFalse);
    });

    test('each step is ticked only by its own state', () {
      final progress = FirstStepsProgress.evaluate(
        hasPhoto: false,
        friendCount: 1,
        serverCount: 0,
        momentCount: 1,
        followingCount: 0,
        contentEnabled: true,
      )!;
      expect(progress.done, {FirstStep.friend, FirstStep.voice});
      expect(progress.next, FirstStep.photo);

      final complete = FirstStepsProgress.evaluate(
        hasPhoto: true,
        friendCount: 1,
        serverCount: 1,
        momentCount: 1,
        followingCount: 1,
        contentEnabled: true,
      )!;
      expect(complete.isComplete, isTrue);
      expect(complete.next, isNull);
    });
  });

  testWidgets('a newcomer with a photo sees 1 z 5 and the next step lit', (
    tester,
  ) async {
    final store = _MemoryStore();
    final media = _Media();
    final taps = _Taps();
    await tester.pumpWidget(
      _host(
        profile: Stream.value(_profile()),
        store: store,
        media: media.service,
        taps: taps,
      ),
    );
    // Nothing on the first frame: no source has answered yet.
    expect(find.byKey(const ValueKey('home-first-steps')), findsNothing);
    await tester.pumpAndSettle();

    expect(find.text('Zacznij tutaj'), findsOneWidget);
    expect(find.text('1 z 5'), findsOneWidget);
    expect(find.text('Dodaj zdjęcie profilowe'), findsOneWidget);
    expect(find.text('Dodaj pierwszego znajomego'), findsOneWidget);
    expect(find.text('Dołącz do serwera albo stwórz własny'), findsOneWidget);
    expect(find.text('Nagraj pierwszy Głos'), findsOneWidget);
    expect(find.text('Zaobserwuj stronę lub twórcę'), findsOneWidget);
    // Only the next step carries its hint.
    expect(
      find.text('Wyszukaj po nazwie albo wyślij swój link'),
      findsOneWidget,
    );
    expect(find.text('Ich nowości zobaczysz w Treściach'), findsNothing);
    expect(find.text('Znajomi szybciej Cię rozpoznają'), findsNothing);
    expect(store.writes, [FirstStepsOutcome.started]);

    // The ticked step is not a control; every open step is one and leads to
    // its own place.
    expect(
      find.descendant(
        of: _step(FirstStep.photo),
        matching: find.byType(AccessibleTapRegion),
      ),
      findsNothing,
    );
    for (final step in const [
      FirstStep.friend,
      FirstStep.server,
      FirstStep.voice,
      FirstStep.follow,
    ]) {
      await tester.tap(_step(step));
      await tester.pump();
    }
    expect(taps.log, ['friend', 'server', 'voice', 'follow']);

    // Every open row is at least 48 px tall, and so is the close target.
    for (final step in FirstStep.values) {
      expect(tester.getSize(_step(step)).height, greaterThanOrEqualTo(48));
    }
    final close = tester.getSize(
      find.byKey(const ValueKey('home-first-steps-close')),
    );
    expect(close, const Size(48, 48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a photo the photo step is next and opens the editor', (
    tester,
  ) async {
    final taps = _Taps();
    await tester.pumpWidget(
      _host(
        profile: Stream.value(_profile()),
        store: _MemoryStore(),
        media: _Media(available: false).service,
        friends: _data([_friend('ola')]),
        taps: taps,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 z 5'), findsOneWidget);
    expect(find.text('Znajomi szybciej Cię rozpoznają'), findsOneWidget);
    await tester.tap(_step(FirstStep.photo));
    expect(taps.log, ['photo']);
  });

  testWidgets('with Treści off the card counts four steps', (tester) async {
    await tester.pumpWidget(
      _host(
        profile: Stream.value(_profile(following: 3)),
        store: _MemoryStore(),
        media: _Media().service,
        contentEnabled: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 z 4'), findsOneWidget);
    expect(find.text('Zaobserwuj stronę lub twórcę'), findsNothing);
  });

  testWidgets('real state ticks steps: 4 z 5 leaves the follow step lit', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        profile: Stream.value(_profile(moments: 1)),
        store: _MemoryStore(),
        media: _Media().service,
        friends: _data([_friend('ola')]),
        servers: _data([_server()]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('4 z 5'), findsOneWidget);
    expect(find.text('Ich nowości zobaczysz w Treściach'), findsOneWidget);
  });

  testWidgets('the card waits for every source and never guesses', (
    tester,
  ) async {
    // Treści availability unknown.
    await tester.pumpWidget(
      _host(
        profile: Stream.value(_profile()),
        store: _MemoryStore(),
        media: _Media().service,
        contentEnabled: null,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-first-steps')), findsNothing);

    // Each case below starts from a new host, as a new session would.
    Future<void> fresh() async {
      await tester.pumpWidget(const SizedBox.shrink());
      ProfileMediaService.clearAllMediaAccessCaches();
    }

    // Friends still loading.
    await fresh();
    await tester.pumpWidget(
      _host(
        profile: Stream.value(_profile()),
        store: _MemoryStore(),
        media: _Media().service,
        friends: const AsyncSnapshot<List<FriendUser>>.waiting(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-first-steps')), findsNothing);

    // Servers failed.
    await fresh();
    await tester.pumpWidget(
      _host(
        profile: Stream.value(_profile()),
        store: _MemoryStore(),
        media: _Media().service,
        servers: AsyncSnapshot<List<Server>>.withError(
          ConnectionState.active,
          StateError('denied'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-first-steps')), findsNothing);

    // No profile yet.
    await fresh();
    final never = StreamController<UserProfile>();
    addTearDown(never.close);
    await tester.pumpWidget(
      _host(
        profile: never.stream,
        store: _MemoryStore(),
        media: _Media().service,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-first-steps')), findsNothing);

    // An unreadable local store.
    await fresh();
    final broken = _MemoryStore()..readError = StateError('no prefs');
    await tester.pumpWidget(
      _host(
        profile: Stream.value(_profile()),
        store: broken,
        media: _Media().service,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-first-steps')), findsNothing);
    expect(broken.writes, isEmpty);

    // No signed-in account.
    await fresh();
    await tester.pumpWidget(
      _host(
        profile: Stream.value(_profile()),
        store: _MemoryStore(),
        media: _Media().service,
        userId: '',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-first-steps')), findsNothing);
  });

  testWidgets('a failed avatar grant hides the card and is asked again', (
    tester,
  ) async {
    final media = _Media(fail: true);
    await tester.pumpWidget(
      _host(
        profile: Stream.value(_profile()),
        store: _MemoryStore(),
        media: media.service,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-first-steps')), findsNothing);
    expect(media.calls, 1);

    media.fail = false;
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(media.calls, 2);
    expect(find.text('1 z 5'), findsOneWidget);
  });

  testWidgets('X closes the card for good on this device', (tester) async {
    final store = _MemoryStore();
    await tester.pumpWidget(
      _host(
        profile: Stream.value(_profile()),
        store: store,
        media: _Media().service,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Zamknij'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-first-steps-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-first-steps')), findsNothing);
    expect(store.values[_uid], FirstStepsOutcome.dismissed);

    // A new session (a fresh host) reads the stored outcome.
    await tester.pumpWidget(const SizedBox.shrink());
    ProfileMediaService.clearAllMediaAccessCaches();
    await tester.pumpWidget(
      _host(
        profile: Stream.value(_profile()),
        store: store,
        media: _Media().service,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-first-steps')), findsNothing);
  });

  testWidgets('the last step done earns the Gotowe line, then it is gone', (
    tester,
  ) async {
    final store = _MemoryStore();
    final profiles = StreamController<UserProfile>();
    addTearDown(profiles.close);
    await tester.pumpWidget(
      _host(
        profile: profiles.stream,
        store: store,
        media: _Media().service,
        friends: _data([_friend('ola')]),
        servers: _data([_server()]),
      ),
    );
    profiles.add(_profile(moments: 1));
    await tester.pumpAndSettle();
    expect(find.text('4 z 5'), findsOneWidget);
    expect(store.values[_uid], FirstStepsOutcome.started);

    // The account follows its first Page: the server keeps the counter.
    profiles.add(_profile(moments: 1, following: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-first-steps')), findsNothing);
    expect(find.text('Gotowe. Znasz już YO Voice.'), findsOneWidget);
    expect(store.values[_uid], FirstStepsOutcome.completed);

    // An unfollow later does not bring the checklist back.
    profiles.add(_profile(moments: 1));
    await tester.pumpAndSettle();
    expect(find.text('Gotowe. Znasz już YO Voice.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-first-steps-close')));
    await tester.pumpAndSettle();
    expect(find.text('Gotowe. Znasz już YO Voice.'), findsNothing);
    expect(store.values[_uid], FirstStepsOutcome.completed);

    // Next session: nothing.
    await tester.pumpWidget(const SizedBox.shrink());
    ProfileMediaService.clearAllMediaAccessCaches();
    await tester.pumpWidget(
      _host(
        profile: Stream.value(_profile(moments: 1)),
        store: store,
        media: _Media().service,
        friends: _data([_friend('ola')]),
        servers: _data([_server()]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-first-steps')), findsNothing);
    expect(find.byKey(const ValueKey('home-first-steps-done')), findsNothing);
  });

  testWidgets('an account that already did everything never sees the card', (
    tester,
  ) async {
    final store = _MemoryStore();
    await tester.pumpWidget(
      _host(
        profile: Stream.value(_profile(moments: 4, following: 2)),
        store: store,
        media: _Media().service,
        friends: _data([_friend('ola')]),
        servers: _data([_server()]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-first-steps')), findsNothing);
    expect(find.byKey(const ValueKey('home-first-steps-done')), findsNothing);
    expect(store.writes, [FirstStepsOutcome.completed]);
  });

  testWidgets('friends not answered yet: the card waits, and an account that '
      'did everything long ago gets no Gotowe', (tester) async {
    // `FriendService.watchFriends()` stays silent while relationship rows are
    // listed but no profile has joined, so what the card sees meanwhile is a
    // waiting snapshot, not an empty list. That silence is pinned in
    // test/friend_service_first_answer_test.dart.
    final store = _MemoryStore();
    final media = _Media().service;
    final profiles = StreamController<UserProfile>();
    addTearDown(profiles.close);
    final stream = profiles.stream;
    Widget host(AsyncSnapshot<List<FriendUser>> friends) => _host(
      profile: stream,
      store: store,
      media: media,
      friends: friends,
      servers: _data([_server()]),
    );

    await tester.pumpWidget(
      host(const AsyncSnapshot<List<FriendUser>>.waiting()),
    );
    profiles.add(_profile(moments: 3, following: 1, friends: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-first-steps')), findsNothing);
    expect(find.text('Dodaj pierwszego znajomego'), findsNothing);
    expect(store.writes, isEmpty, reason: 'nothing was shown, nothing stored');

    // The profiles arrive: every step is done, and was before this device
    // ever showed a checklist. No card, no "Gotowe".
    await tester.pumpWidget(host(_data([_friend('ola'), _friend('jan')])));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-first-steps')), findsNothing);
    expect(find.byKey(const ValueKey('home-first-steps-done')), findsNothing);
    expect(store.writes, [FirstStepsOutcome.completed]);
  });

  testWidgets('the friends list is the truth: a friendCount that drifted above '
      'an empty list does not hide the card', (tester) async {
    final store = _MemoryStore();
    final media = _Media().service;
    final profiles = StreamController<UserProfile>();
    addTearDown(profiles.close);
    final stream = profiles.stream;
    Widget host(List<FriendUser> friends) => _host(
      profile: stream,
      store: store,
      media: media,
      friends: _data(friends),
    );

    // The counter says two friends; the relationship rows say nobody. The
    // rows are canonical, so the step is open and the card is shown.
    await tester.pumpWidget(host(const <FriendUser>[]));
    profiles.add(_profile(friends: 2));
    await tester.pumpAndSettle();
    expect(find.text('1 z 5'), findsOneWidget);
    expect(
      find.text('Wyszukaj po nazwie albo wyślij swój link'),
      findsOneWidget,
    );
    expect(store.writes, [FirstStepsOutcome.started]);

    // A friend in the list ticks the step whatever the counter says.
    profiles.add(_profile());
    await tester.pumpWidget(host([_friend('ola')]));
    await tester.pumpAndSettle();
    expect(find.text('2 z 5'), findsOneWidget);
    expect(
      find.descendant(
        of: _step(FirstStep.friend),
        matching: find.byType(AccessibleTapRegion),
      ),
      findsNothing,
      reason: 'the friend step is ticked, not a control',
    );

    // The last friend is removed: the list empties and the step reopens at
    // once, before the counter has followed.
    profiles.add(_profile(friends: 1));
    await tester.pumpWidget(host(const <FriendUser>[]));
    await tester.pumpAndSettle();
    expect(find.text('1 z 5'), findsOneWidget);
    expect(
      find.text('Wyszukaj po nazwie albo wyślij swój link'),
      findsOneWidget,
    );
  });

  testWidgets('a new avatar ticks the photo step without a restart', (
    tester,
  ) async {
    final media = _Media(available: false);
    final profiles = StreamController<UserProfile>();
    addTearDown(profiles.close);
    await tester.pumpWidget(
      _host(
        profile: profiles.stream,
        store: _MemoryStore(),
        media: media.service,
      ),
    );
    profiles.add(_profile());
    await tester.pumpAndSettle();
    expect(find.text('0 z 5'), findsOneWidget);

    // The upload finalised: the grant is evicted and the profile revision
    // moves, exactly as `finalizeUpload` and the profile document do.
    media.available = true;
    ProfileMediaService.evictUser(_uid);
    profiles.add(_profile(updatedAt: DateTime.utc(2026, 10, 3, 12)));
    await tester.pumpAndSettle();
    expect(find.text('1 z 5'), findsOneWidget);
  });

  testWidgets('rows form two columns on a wide card and one on a phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    tester.view.physicalSize = const Size(768, 1024);
    await tester.pumpWidget(
      _host(
        profile: Stream.value(_profile()),
        store: _MemoryStore(),
        media: _Media().service,
      ),
    );
    await tester.pumpAndSettle();
    final photo = tester.getTopLeft(_step(FirstStep.photo));
    final voice = tester.getTopLeft(_step(FirstStep.voice));
    final server = tester.getTopLeft(_step(FirstStep.server));
    expect(voice.dy, photo.dy, reason: 'the fourth step heads column two');
    expect(voice.dx, greaterThan(photo.dx + 200));
    expect(server.dx, photo.dx);
    expect(server.dy, greaterThan(photo.dy));

    // 200 % text on the same slate: one column again, nothing overflows.
    await tester.pumpWidget(const SizedBox.shrink());
    ProfileMediaService.clearAllMediaAccessCaches();
    await tester.pumpWidget(
      _host(
        profile: Stream.value(_profile()),
        store: _MemoryStore(),
        media: _Media().service,
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(_step(FirstStep.voice)).dx,
      tester.getTopLeft(_step(FirstStep.photo)).dx,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    ProfileMediaService.clearAllMediaAccessCaches();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(
      _host(
        profile: Stream.value(_profile()),
        store: _MemoryStore(),
        media: _Media().service,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(_step(FirstStep.voice)).dx,
      tester.getTopLeft(_step(FirstStep.photo)).dx,
    );
  });

  testWidgets('no overflow at 320 px, at 100 % and 200 % text, in every '
      'selectable locale', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 690);
    addTearDown(tester.view.reset);
    expect(AppLocalizations.supportedLocales, hasLength(43));
    for (final locale in AppLocalizations.supportedLocales) {
      for (final textScale in const [1.0, 2.0]) {
        await tester.pumpWidget(const SizedBox.shrink());
        ProfileMediaService.clearAllMediaAccessCaches();
        await tester.pumpWidget(
          _host(
            profile: Stream.value(_profile()),
            store: _MemoryStore(),
            media: _Media().service,
            locale: locale,
            textScale: textScale,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('home-first-steps')),
          findsOneWidget,
          reason: '$locale x$textScale',
        );
        expect(tester.takeException(), isNull, reason: '$locale x$textScale');
      }
    }
  });

  testWidgets('the done line fits 320 px at 200 % text in every locale', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 690);
    addTearDown(tester.view.reset);
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(const SizedBox.shrink());
      ProfileMediaService.clearAllMediaAccessCaches();
      await tester.pumpWidget(
        _host(
          profile: Stream.value(_profile(moments: 1, following: 1)),
          store: _MemoryStore(FirstStepsOutcome.started),
          media: _Media().service,
          friends: _data([_friend('ola')]),
          servers: _data([_server()]),
          locale: locale,
          textScale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('home-first-steps-done')),
        findsOneWidget,
        reason: '$locale',
      );
      expect(tester.takeException(), isNull, reason: '$locale');
    }
  });

  testWidgets('semantics: a heading, named open steps and ticked ones', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        profile: Stream.value(_profile()),
        store: _MemoryStore(),
        media: _Media().service,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text('Zacznij tutaj')),
      matchesSemantics(label: 'Zacznij tutaj', isHeader: true),
    );
    expect(
      find.bySemanticsLabel(
        'Dodaj pierwszego znajomego. Wyszukaj po nazwie albo wyślij swój link',
      ),
      findsOneWidget,
    );
    final ticked = tester.getSemantics(_step(FirstStep.photo));
    expect(ticked.label, 'Dodaj zdjęcie profilowe');
    expect(ticked.value, 'Zrobione');
    handle.dispose();
  });

  test('the owner profile carries its own following count ungated', () {
    // `followingCount` is the public, audience-gated projection; the card
    // reads the account's own counter.
    final profile = _profile(following: 2);
    expect(profile.followingCount, 0);
    expect(profile.accountFollowingCount, 2);
  });
}
