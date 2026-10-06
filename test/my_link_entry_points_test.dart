import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/auth_entry_link.dart';
import 'package:yovoice/features/auth/presentation/screens/login_screen.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/friends/presentation/screens/friends_screen.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/profile_screen.dart';
import 'package:yovoice/services/firestore_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';

/// "Mój link" (ADR-238): where it is reachable from (Friends, Profile), what
/// a profile link shows when it cannot be opened, and what a signed-out
/// visitor of a link reads.

const _me = 'Zx8qT1mVbN4kLp0sWe7uYh2RcA93';

Stream<T> _replay<T>(T value) => Stream<T>.multi((controller) {
  controller.add(value);
  unawaited(controller.close());
});

class _FriendsSvc extends FriendService {
  _FriendsSvc(
    this.list, {
    required FirebaseFirestore db,
    required FirebaseAuth auth,
  }) : super(firestore: db, auth: auth);
  final List<FriendUser> list;

  @override
  Stream<List<FriendUser>> watchFriends() => _replay<List<FriendUser>>(list);
}

class _Graph implements SocialGraphService {
  @override
  Future<List<SuggestedFriend>> getFriendSuggestions({int limit = 10}) async =>
      const <SuggestedFriend>[];
  @override
  Future<MutualFriendsSummary> getMutualFriends(String targetUserId) async =>
      MutualFriendsSummary.empty;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AuthSvc extends AuthService {
  _AuthSvc()
    : super(
        firebaseAuth: MockFirebaseAuth(),
        firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      );

  @override
  Future<AppleSignInAvailability> getAppleSignInAvailability() async =>
      AppleSignInAvailability.available;
}

class _Fx {
  _Fx({this.friends = const <FriendUser>[]});

  final List<FriendUser> friends;
  final db = FakeFirebaseFirestore();
  late final auth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(
      uid: _me,
      isEmailVerified: true,
      displayName: 'Kamil',
      email: 'account@example.com',
    ),
  );
  late final media = ProfileMediaService(
    auth: auth,
    invoker: (callable, request) async => <Object?, Object?>{
      'schemaVersion': 1,
      'available': false,
      'expiresAtMillis': DateTime.now()
          .add(const Duration(seconds: 60))
          .millisecondsSinceEpoch,
    },
  );
  late final friendService = _FriendsSvc(friends, db: db, auth: auth);
  late final messageService = MessageService(firestore: db, auth: auth);

  Future<void> seed() => db.doc('users/$_me').set(<String, dynamic>{
    'uid': _me,
    'displayName': 'Kamil',
    'username': 'kamil',
  });

  Widget friendsScreen() => FriendsScreen(
    isRootTab: true,
    friendService: friendService,
    messageService: messageService,
    socialGraphService: _Graph(),
    profileMediaService: media,
    firestore: db,
    auth: auth,
  );
}

const _ola = FriendUser(
  id: 'ola',
  displayName: 'Ola Nowak',
  email: '',
  photoUrl: null,
  isOnline: false,
  lastSeen: null,
);

Widget _app(Widget home, {Locale locale = const Locale('pl')}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.darkTheme,
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child!,
  ),
  home: home,
);

Future<void> _settle(WidgetTester tester) async {
  for (var round = 0; round < 3; round++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

void _view(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

UserProfile _profile() => UserProfile(
  uid: _me,
  email: 'account@example.com',
  displayName: 'Kamil',
  username: 'kamil',
  bio: '',
  statusMessage: '',
  country: '',
  nativeLanguage: '',
  spokenLanguages: const <String>[],
  learningLanguages: const <String>[],
  photoUrl: null,
  bannerUrl: null,
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
  unlockedTitleIds: const <String>[],
  unlockedTitleTimestamps: const {},
  createdAt: DateTime(2026),
);

final _panel = find.byKey(const ValueKey('my-link-panel'));
final _headerAction = find.byKey(const ValueKey('friends-my-link'));
final _emptyAction = find.byKey(const ValueKey('friends-empty-share-my-link'));

void main() {
  late PublicIdentityRepository originalIdentity;

  setUp(() {
    ProfileService.resetCurrentProfileCache();
    FriendService.clearSharedReadCaches();
    ProfileMediaService.clearAllMediaAccessCaches();
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      fetchOverride: (uids) async => {
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });
  tearDown(() => PublicIdentityRepository.instance = originalIdentity);

  group('Friends', () {
    testWidgets('the header carries "Mój link" beside the one filled CTA, and '
        'it opens the sheet with the real account', (tester) async {
      _view(tester, const Size(390, 844));
      final fx = _Fx(friends: const [_ola]);
      await tester.runAsync(fx.seed);
      await tester.pumpWidget(_app(fx.friendsScreen()));
      await _settle(tester);

      expect(_headerAction, findsOneWidget);
      expect(find.byTooltip('Mój link'), findsOneWidget);
      final action = tester.getRect(_headerAction);
      final add = tester.getRect(
        find.byKey(const ValueKey('friends-find-new-person')),
      );
      expect(action.width, greaterThanOrEqualTo(44));
      expect(action.height, greaterThanOrEqualTo(44));
      expect(action.center.dy, closeTo(add.center.dy, 1));
      expect(add.right, lessThan(action.left));
      // A list with people in it has no empty-state pill.
      expect(_emptyAction, findsNothing);
      // Everything that was reachable before still is.
      expect(find.text('Dodaj znajomego'), findsOneWidget);
      expect(find.text('Zablokowani'), findsOneWidget);

      await tester.tap(_headerAction);
      await _settle(tester);
      expect(_panel, findsOneWidget);
      expect(find.text('Kamil'), findsOneWidget);
      expect(find.text('@kamil'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('my-link-text')))
            .semanticsLabel,
        'app.yovoice.app/?user=$_me',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty list offers "Udostępnij mój link"', (tester) async {
      _view(tester, const Size(390, 844));
      final fx = _Fx();
      await tester.runAsync(fx.seed);
      await tester.pumpWidget(_app(fx.friendsScreen()));
      await _settle(tester);

      expect(find.text('Nie masz jeszcze znajomych'), findsOneWidget);
      expect(_emptyAction, findsOneWidget);
      expect(find.text('Udostępnij mój link'), findsOneWidget);
      expect(
        tester.getSize(_emptyAction).height,
        greaterThanOrEqualTo(44),
      );

      await tester.tap(_emptyAction);
      await _settle(tester);
      expect(_panel, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the pill belongs to "no friends yet" only', (tester) async {
      _view(tester, const Size(390, 844));
      final fx = _Fx(friends: const [_ola]);
      await tester.runAsync(fx.seed);
      await tester.pumpWidget(_app(fx.friendsScreen()));
      await _settle(tester);

      // Nobody online: a different empty state, without the pill.
      await tester.tap(find.text('Online'));
      await _settle(tester);
      expect(find.text('Nikt nie jest teraz online'), findsOneWidget);
      expect(_emptyAction, findsNothing);

      // A search with no match: the same.
      await tester.tap(find.text('Wszyscy'));
      await _settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('current-friend-search')),
        'zzz',
      );
      await _settle(tester);
      expect(find.text('Brak pasujących znajomych'), findsOneWidget);
      expect(_emptyAction, findsNothing);
    });

    testWidgets('desktop: the header action opens the 420 px dialog', (
      tester,
    ) async {
      _view(tester, const Size(1440, 900));
      final fx = _Fx(friends: const [_ola]);
      await tester.runAsync(fx.seed);
      await tester.pumpWidget(_app(fx.friendsScreen()));
      await _settle(tester);

      final action = tester.getRect(_headerAction);
      final add = tester.getRect(
        find.byKey(const ValueKey('friends-find-new-person')),
      );
      expect(action.right, lessThan(add.left));

      await tester.tap(_headerAction);
      await _settle(tester);
      expect(find.byType(Dialog), findsOneWidget);
      expect(tester.getSize(_panel).width, 420);
      expect(tester.takeException(), isNull);
    });

    testWidgets('320 px at 200 % text: the header and the pill do not '
        'overflow', (tester) async {
      _view(tester, const Size(320, 690));
      final fx = _Fx();
      await tester.runAsync(fx.seed);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          locale: const Locale('el'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: fx.friendsScreen(),
        ),
      );
      await _settle(tester);
      expect(_headerAction, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        _emptyAction,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await _settle(tester);
      expect(find.text('Κοινοποίηση του συνδέσμου μου'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Profile', () {
    Future<List<String>> pumpProfile(
      WidgetTester tester, {
      required bool withMyLink,
      Size size = const Size(390, 844),
    }) async {
      _view(tester, size);
      final fx = _Fx();
      final calls = <String>[];
      await tester.runAsync(fx.seed);
      await tester.pumpWidget(
        _app(
          ProfileScreenView(
            profile: _profile(),
            servers: const [],
            serversLoading: false,
            onEdit: () => calls.add('edit'),
            onAchievements: () {},
            onOpenServer: (_) {},
            showSuperAdminActivation: false,
            isActivatingSuperAdmin: false,
            currentRole: 'user',
            onActivateSuperAdmin: () async {},
            onLogout: () async {},
            onMyLink: withMyLink ? () => calls.add('myLink') : null,
            identityRepository: PublicIdentityRepository.instance,
            mediaService: fx.media,
          ),
        ),
      );
      await _settle(tester);
      return calls;
    }

    testWidgets('the toolbar, the ⋯ sheet and the account section all open '
        '"Mój link"', (tester) async {
      final calls = await pumpProfile(tester, withMyLink: true);

      // 1. The raised 44 px control over the photo.
      final toolbar = find.byKey(const ValueKey('profile-my-link'));
      expect(toolbar, findsOneWidget);
      expect(find.byTooltip('Mój link'), findsOneWidget);
      expect(tester.getSize(toolbar).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(toolbar).height, greaterThanOrEqualTo(44));
      await tester.tap(toolbar);
      await tester.pump();
      expect(calls, ['myLink']);

      // 2. First row of the ⋯ sheet; Edit and Log out stay.
      await tester.tap(find.byKey(const ValueKey('profile-more-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('profile-more-edit')), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-more-logout')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('profile-more-my-link')));
      await tester.pumpAndSettle();
      expect(calls, ['myLink', 'myLink']);

      // 3. The account section at the foot of the page.
      final row = find.byKey(const ValueKey('profile-account-my-link'));
      await tester.scrollUntilVisible(
        row,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pump();
      expect(calls, ['myLink', 'myLink', 'myLink']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the existing actions are untouched', (tester) async {
      final calls = await pumpProfile(tester, withMyLink: true);
      expect(find.byKey(const ValueKey('profile-edit-button')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('profile-awards-button')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('profile-more-button')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('profile-edit-button')));
      await tester.pump();
      expect(calls, ['edit']);
    });

    testWidgets('a preview without a session draws none of the entries', (
      tester,
    ) async {
      await pumpProfile(tester, withMyLink: false);
      expect(find.byKey(const ValueKey('profile-my-link')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('profile-more-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('profile-more-my-link')), findsNothing);
      expect(find.byKey(const ValueKey('profile-more-edit')), findsOneWidget);
    });

    testWidgets('desktop keeps the toolbar control inside the page', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        withMyLink: true,
        size: const Size(1440, 900),
      );
      final toolbar = tester.getRect(
        find.byKey(const ValueKey('profile-my-link')),
      );
      expect(toolbar.right, lessThanOrEqualTo(1440));
      expect(toolbar.top, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
    });
  });

  group('a profile link that cannot be opened', () {
    test('missing, refused and not-found are "not available"; a transport '
        'failure is not', () {
      expect(
        profilePreviewIsUnavailable(const ProfileUnavailableException()),
        isTrue,
      );
      expect(
        profilePreviewIsUnavailable(
          FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
        ),
        isTrue,
      );
      expect(
        profilePreviewIsUnavailable(
          FirebaseException(plugin: 'cloud_firestore', code: 'not-found'),
        ),
        isTrue,
      );
      expect(
        profilePreviewIsUnavailable(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        ),
        isFalse,
      );
      expect(profilePreviewIsUnavailable(StateError('boom')), isFalse);
    });

    testWidgets('an unknown id shows the honest sentence, never a profile', (
      tester,
    ) async {
      _view(tester, const Size(390, 844));
      final fx = _Fx();
      await tester.runAsync(fx.seed);
      await tester.pumpWidget(
        _app(const Scaffold(body: SizedBox.expand())),
      );
      unawaited(
        showProfilePreview(
          tester.element(find.byType(Scaffold)),
          userId: 'nobodyWithThisIdExists0000',
          firestore: fx.db,
          auth: fx.auth,
          friendService: fx.friendService,
          messageService: fx.messageService,
          profileMediaService: fx.media,
          resolvePages: false,
        ),
      );
      await _settle(tester);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('profile-preview-error')))
            .data,
        'Ten profil jest niedostępny.',
      );
      expect(find.text('Dodaj znajomego'), findsNothing);
      expect(find.text('Wiadomość'), findsNothing);
      expect(find.textContaining('uprawnień'), findsNothing);
    });

    testWidgets('a known id opens the existing preview with Add friend', (
      tester,
    ) async {
      _view(tester, const Size(390, 844));
      final fx = _Fx();
      await tester.runAsync(() async {
        await fx.seed();
        await fx.db.doc('publicProfiles/ola').set(<String, dynamic>{
          'uid': 'ola',
          'displayName': 'Ola Nowak',
          'username': 'ola',
        });
      });
      await tester.pumpWidget(
        _app(const Scaffold(body: SizedBox.expand())),
      );
      unawaited(
        showProfilePreview(
          tester.element(find.byType(Scaffold)),
          userId: 'ola',
          firestore: fx.db,
          auth: fx.auth,
          friendService: fx.friendService,
          messageService: fx.messageService,
          profileMediaService: fx.media,
          resolvePages: false,
        ),
      );
      await _settle(tester);
      expect(find.text('Ola Nowak'), findsOneWidget);
      expect(find.text('Dodaj znajomego'), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-preview-error')), findsNothing);
    });
  });

  group('a signed-out visitor of a link', () {
    Future<void> pumpLogin(WidgetTester tester, AuthEntryLink? link) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(LoginScreen(authService: _AuthSvc(), entryLink: link)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('reads what signing in opens', (tester) async {
      await pumpLogin(tester, AuthEntryLink.profile);
      expect(find.text('Witaj ponownie'), findsOneWidget);
      expect(
        find.text(
          'Zaloguj się, aby zobaczyć ten profil i dodać tę osobę do '
          'znajomych.',
        ),
        findsOneWidget,
      );
      expect(find.text('Znajomi i rozmowy już na Ciebie czekają.'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a Voice link has its own line', (tester) async {
      await pumpLogin(tester, AuthEntryLink.voiceMoment);
      expect(
        find.text('Zaloguj się, aby posłuchać tego Voice Momentu.'),
        findsOneWidget,
      );
    });

    testWidgets('without a link the sign-in screen is unchanged', (
      tester,
    ) async {
      await pumpLogin(tester, null);
      expect(
        find.text('Znajomi i rozmowy już na Ciebie czekają.'),
        findsOneWidget,
      );
      expect(find.textContaining('Zaloguj się, aby'), findsNothing);
    });
  });
}
