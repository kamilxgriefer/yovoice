import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_language_sync.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/notifications/presentation/notification_router.dart';
import 'package:yovoice/features/notifications/presentation/screens/notification_preferences_screen.dart';
import 'package:yovoice/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_face.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';

/// ADR-237 on the client: the followed-Page post row, the Following group of
/// notification settings, taps that always lead somewhere, and the language
/// the app tells the server it is shown in.
const _me = 'me-uid';
const _page = 'page-owner-uid';
final _postId = 'pp_${'a' * 40}';

const _delegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizationsDelegate(),
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

MockFirebaseAuth _authFor(String uid) => MockFirebaseAuth(
  signedIn: true,
  mockUser: MockUser(uid: uid, email: '$uid@yovoice.app', displayName: uid),
);

class _MemoryStore implements AppPreferencesStore {
  final Map<String, String> values = <String, String>{};
  bool failWrites = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('store unavailable');
    values[key] = value;
  }
}

Future<void> _seedRows(FakeFirebaseFirestore db) async {
  final rows = db.collection('users').doc(_me).collection('notifications');
  final now = DateTime.now();
  await rows.doc('pagePost_$_postId').set(<String, dynamic>{
    'type': 'pagePostPublished',
    'actorId': _page,
    'actorName': 'Pracownia Glina',
    'actorPhotoUrl': null,
    'targetId': _postId,
    'targetLabel': 'New post from a Page you follow: Pracownia Glina',
    'postPreview': 'Nowe kubki już w pracowni',
    'pageKind': 'business',
    'sourcePath': 'pagePosts/$_postId',
    'sourceGeneration': '1:2',
    'isRead': false,
    'createdAt': Timestamp.fromDate(now.subtract(const Duration(hours: 2))),
    'dedupeKey': 'pagePost_$_postId',
    'bellSuppressed': false,
  });
  await rows.doc('achievementUnlocked_messages_1').set(<String, dynamic>{
    'type': 'achievementUnlocked',
    'actorId': 'yovoice-system',
    'actorName': 'YO Voice',
    'actorPhotoUrl': null,
    'targetId': 'messages_1',
    'targetLabel': 'First Word',
    'isRead': true,
    'createdAt': Timestamp.fromDate(now.subtract(const Duration(hours: 4))),
    'dedupeKey': 'achievementUnlocked_messages_1',
    'bellSuppressed': false,
  });
  await rows.doc('follow_someone').set(<String, dynamic>{
    'type': 'follow',
    'actorId': 'someone',
    'actorName': 'Ola Nowak',
    'actorPhotoUrl': null,
    'targetId': null,
    'targetLabel': null,
    'isRead': true,
    'createdAt': Timestamp.fromDate(now.subtract(const Duration(hours: 6))),
    'dedupeKey': 'follow_someone',
    'bellSuppressed': false,
  });
}

Future<List<AppNotification>> _pumpInbox(
  WidgetTester tester,
  FakeFirebaseFirestore db, {
  Locale locale = const Locale('pl'),
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final opened = <AppNotification>[];
  final service = NotificationService(firestore: db, auth: _authFor(_me));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: _delegates,
      home: NotificationsScreen(
        friendService: FriendService(firestore: db, auth: _authFor(_me)),
        messageService: MessageService(
          firestore: db,
          auth: _authFor(_me),
          notificationService: service,
        ),
        notificationService: service,
        currentUserId: _me,
        firestore: db,
        auth: _authFor(_me),
        acknowledgeOnVisible: false,
        openNotification: (notification) async => opened.add(notification),
      ),
    ),
  );
  for (var pump = 0; pump < 8; pump++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
  return opened;
}

Future<void> _pumpPreferences(
  WidgetTester tester,
  FakeFirebaseFirestore db, {
  Locale locale = const Locale('en'),
  Map<String, bool> stored = const <String, bool>{},
}) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await db.collection('users').doc(_me).set({
    'uid': _me,
    'notificationPreferences': stored,
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: _delegates,
      home: NotificationPreferencesScreen(
        isRootTab: true,
        notificationService: NotificationService(
          firestore: db,
          auth: _authFor(_me),
        ),
        creatorAudienceVisibleStream: Stream.value(false),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Switch _switchOf(WidgetTester tester, NotificationType type) => tester.widget(
  find.descendant(
    of: find.byKey(ValueKey('notification-preference-${type.name}')),
    matching: find.byType(Switch),
  ),
);

void main() {
  group('the row model', () {
    test('a followed Page post parses its additive fields', () async {
      final db = FakeFirebaseFirestore();
      await _seedRows(db);
      final row = AppNotification.fromFirestore(
        await db
            .collection('users')
            .doc(_me)
            .collection('notifications')
            .doc('pagePost_$_postId')
            .get(),
      );
      expect(row.type, NotificationType.pagePostPublished);
      expect(row.actorIsPage, isTrue);
      expect(row.actorId, _page);
      expect(row.targetId, _postId);
      expect(row.postPreview, 'Nowe kubki już w pracowni');
      expect(row.pageKind, 'business');
      expect(row.title, 'Pracownia Glina published a post');
      expect(row.isSystemNotice, isFalse);
    });

    test('a build that does not know a type shows a system row', () {
      // What builds 40/41 do with `pagePostPublished`, and what this build
      // does with whatever comes next: no crash, the server's own sentence.
      expect(
        NotificationType.fromName('typeFromTheFuture'),
        NotificationType.system,
      );
      expect(NotificationType.fromName(null), NotificationType.system);
      const row = AppNotification(
        id: 'row',
        type: NotificationType.system,
        actorId: _page,
        actorName: 'Pracownia Glina',
        actorPhotoUrl: null,
        targetId: 'whatever',
        targetLabel: 'New post from a Page you follow: Pracownia Glina',
        isRead: false,
        createdAt: null,
      );
      expect(row.title, 'New post from a Page you follow: Pracownia Glina');
      expect(row.actorIsPage, isFalse);
      expect(
        NotificationRouter.destinationFor(row.type),
        NotificationDestination.inbox,
      );
    });
  });

  group('every tap leads somewhere', () {
    test('destinations', () {
      expect(
        NotificationRouter.destinationFor(NotificationType.pagePostPublished),
        NotificationDestination.pagePost,
      );
      // Was `none`: tapping "Achievement unlocked" did nothing.
      expect(
        NotificationRouter.destinationFor(NotificationType.achievementUnlocked),
        NotificationDestination.awards,
      );
      // A notice is its own message: the list that shows it.
      expect(
        NotificationRouter.destinationFor(NotificationType.moderation),
        NotificationDestination.inbox,
      );
      expect(
        NotificationRouter.destinationFor(NotificationType.system),
        NotificationDestination.inbox,
      );
      // The retired go-live type keeps its room destination, which opens the
      // room's Server or says the content is gone.
      expect(
        NotificationRouter.destinationFor(NotificationType.liveStarted),
        NotificationDestination.room,
      );
      // No destination means "nothing happens" any more.
      expect(
        NotificationDestination.values.map((destination) => destination.name),
        isNot(contains('none')),
      );
      for (final type in NotificationType.values) {
        expect(NotificationRouter.destinationFor(type), isNotNull);
      }
    });

    testWidgets('a destination that is gone says so, in the app language', (
      tester,
    ) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          locale: const Locale('pl'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: _delegates,
          home: const Scaffold(body: SizedBox.expand()),
        ),
      );
      NotificationRouter.announceUnavailable(navigatorKey.currentState!);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('notification-destination-unavailable')),
        findsOneWidget,
      );
      expect(find.text('Ta treść nie jest już dostępna.'), findsOneWidget);
      // A second failed tap replaces the line instead of queueing another.
      NotificationRouter.announceUnavailable(navigatorKey.currentState!);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Ta treść nie jest już dostępna.'), findsOneWidget);
    });
  });

  group('the bell', () {
    testWidgets('a followed Page post: Page face, title, first line, no '
        'personal badges', (tester) async {
      final db = FakeFirebaseFirestore();
      await _seedRows(db);
      final opened = await _pumpInbox(tester, db);

      expect(find.text('Pracownia Glina dodaje post'), findsOneWidget);
      expect(find.text('Nowe kubki już w pracowni'), findsOneWidget);
      final face = find.byKey(
        ValueKey('notification-page-face-pagePost_$_postId'),
      );
      expect(face, findsOneWidget);
      expect(tester.widget<PageFace>(face).pageId, _page);
      expect(tester.widget<PageFace>(face).size, 44);
      // The sentence written for older builds is never shown by this one.
      expect(
        find.textContaining('New post from a Page you follow'),
        findsNothing,
      );
      // Role and VIP badges belong to people: the two person rows have them,
      // the Page row does not.
      final badges = tester
          .widgetList<UserIdentityBadges>(find.byType(UserIdentityBadges))
          .map((badge) => badge.uid)
          .toList();
      expect(badges, isNot(contains(_page)));
      expect(badges, contains('someone'));

      await tester.tap(find.text('Pracownia Glina dodaje post'));
      await tester.pump();
      expect(opened.single.type, NotificationType.pagePostPublished);
      expect(opened.single.targetId, _postId);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unlocked achievement shows where it leads and opens', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await _seedRows(db);
      final opened = await _pumpInbox(tester, db);

      // Named in Polish from the catalogue id, not the stored English label.
      expect(
        find.text('Odblokowano osiągnięcie: Pierwsze słowo'),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('notification-chevron-achievementUnlocked_messages_1'),
        ),
        findsOneWidget,
      );
      // Only the row that needs the hint carries it.
      expect(
        find.byKey(ValueKey('notification-chevron-pagePost_$_postId')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('notification-chevron-follow_someone')),
        findsNothing,
      );
      await tester.tap(find.text('Odblokowano osiągnięcie: Pierwsze słowo'));
      await tester.pump();
      expect(opened.single.type, NotificationType.achievementUnlocked);
    });

    testWidgets('a long first line stays inside the row at 320 px and 200 % '
        'text', (tester) async {
      final db = FakeFirebaseFirestore();
      await _seedRows(db);
      await db
          .collection('users')
          .doc(_me)
          .collection('notifications')
          .doc('pagePost_$_postId')
          .update({
            'actorName': 'Pracownia Ceramiki Artystycznej i Użytkowej Glina',
            'postPreview': 'Nowe kubki, miski i talerze już w pracowni. ' * 3,
          });
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = NotificationService(firestore: db, auth: _authFor(_me));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          locale: const Locale('pl'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: _delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: NotificationsScreen(
            friendService: FriendService(firestore: db, auth: _authFor(_me)),
            messageService: MessageService(
              firestore: db,
              auth: _authFor(_me),
              notificationService: service,
            ),
            notificationService: service,
            currentUserId: _me,
            firestore: db,
            auth: _authFor(_me),
            acknowledgeOnVisible: false,
            openNotification: (_) async {},
          ),
        ),
      );
      for (var pump = 0; pump < 8; pump++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(
        find.byKey(ValueKey('notification-body-pagePost_$_postId')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('notification settings', () {
    testWidgets('Following leads the list with two independent switches', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await _pumpPreferences(tester, db);

      final following = tester.getTopLeft(find.text('Following')).dy;
      final friends = tester.getTopLeft(find.text('Friends')).dy;
      final servers = tester.getTopLeft(find.text('Servers')).dy;
      expect(following, lessThan(friends));
      expect(friends, lessThan(servers));

      final live = tester.getTopLeft(find.text('LIVE from people you follow'));
      final posts = tester.getTopLeft(
        find.text('New posts from Pages you follow'),
      );
      // Both rows sit in the Following card, above Friends.
      expect(live.dy, greaterThan(following));
      expect(posts.dy, greaterThan(live.dy));
      expect(posts.dy, lessThan(friends));
      expect(
        find.text('At most one notification a day from each Page'),
        findsOneWidget,
      );
      // The switch moved, it was not duplicated: the old Servers wording is
      // gone and every other Servers switch is still there.
      expect(find.text('People you follow go live'), findsNothing);
      for (final label in const [
        'Server invitations',
        'Server invitation accepted',
        'Voice channel invitations',
        'Podcast invitations',
        'Server events',
        'Your server role',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }

      // Opt-out model: nothing stored means both are on.
      expect(_switchOf(tester, NotificationType.liveStarted).value, isTrue);
      expect(
        _switchOf(tester, NotificationType.pagePostPublished).value,
        isTrue,
      );

      await tester.tap(
        find.descendant(
          of: find.byKey(
            const ValueKey('notification-preference-pagePostPublished'),
          ),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      final stored =
          (await db.collection('users').doc(_me).get())
                  .data()!['notificationPreferences']
              as Map<String, dynamic>;
      // One switch, one key: LIVE is untouched.
      expect(stored, <String, dynamic>{'pagePostPublished': false});
      expect(
        _switchOf(tester, NotificationType.pagePostPublished).value,
        isFalse,
      );
      expect(_switchOf(tester, NotificationType.liveStarted).value, isTrue);
    });

    testWidgets('stored choices are shown, each on its own key', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await _pumpPreferences(
        tester,
        db,
        stored: const {'liveStarted': false, 'pagePostPublished': true},
      );
      expect(_switchOf(tester, NotificationType.liveStarted).value, isFalse);
      expect(
        _switchOf(tester, NotificationType.pagePostPublished).value,
        isTrue,
      );
    });

    testWidgets('Polish reads as on the approved sheet', (tester) async {
      final db = FakeFirebaseFirestore();
      await _pumpPreferences(tester, db, locale: const Locale('pl'));
      expect(find.text('Obserwowane'), findsOneWidget);
      expect(find.text('LIVE obserwowanych'), findsOneWidget);
      expect(find.text('Nowe posty obserwowanych stron'), findsOneWidget);
      expect(
        find.text('Najwyżej jedno powiadomienie dziennie od jednej strony'),
        findsOneWidget,
      );
      expect(find.text('Znajomi'), findsOneWidget);
      expect(find.text('Serwery'), findsOneWidget);
      expect(
        find.text('Obserwowane osoby rozpoczynają transmisję'),
        findsNothing,
      );
    });
  });

  group('the app language the server reads', () {
    late FakeFirebaseFirestore db;
    late _MemoryStore store;
    final logs = <String>[];

    setUp(() {
      db = FakeFirebaseFirestore();
      store = _MemoryStore();
      logs.clear();
    });

    Future<Map<String, dynamic>?> userDoc(String uid) async =>
        (await db.collection('users').doc(uid).get()).data();

    test(
      'stores the locale key once, and again only when it changes',
      () async {
        await db.collection('users').doc(_me).set({
          'uid': _me,
          'displayName': 'Kasia',
        });
        final sync = AppLanguageSync(
          firestore: db,
          auth: _authFor(_me),
          store: store,
          log: logs.add,
        );
        addTearDown(sync.dispose);

        await sync.synchronize(const Locale('pl'));
        expect((await userDoc(_me))!['appLanguage'], 'pl');
        // A merge: the rest of the document is untouched.
        expect((await userDoc(_me))!['displayName'], 'Kasia');
        expect(store.values[AppLanguageSync.storeKey], '$_me|pl');

        // Same language on the next build: no write at all.
        await db.collection('users').doc(_me).update({
          'appLanguage': 'sentinel',
        });
        await sync.synchronize(const Locale('pl'));
        expect((await userDoc(_me))!['appLanguage'], 'sentinel');

        // Region and script resolve to the catalog's own keys.
        await sync.synchronize(const Locale('pt', 'BR'));
        expect((await userDoc(_me))!['appLanguage'], 'pt_BR');
        await sync.synchronize(const Locale('zh', 'HK'));
        expect((await userDoc(_me))!['appLanguage'], 'zh_TW');
        await sync.synchronize(
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        );
        expect((await userDoc(_me))!['appLanguage'], 'zh_CN');
        await sync.synchronize(const Locale('nb'));
        expect((await userDoc(_me))!['appLanguage'], 'nb');
        expect(logs, isEmpty);
      },
    );

    test('a restart does not write again; another account does', () async {
      store.values[AppLanguageSync.storeKey] = '$_me|de';
      final same = AppLanguageSync(
        firestore: db,
        auth: _authFor(_me),
        store: store,
        log: logs.add,
      );
      addTearDown(same.dispose);
      await same.synchronize(const Locale('de'));
      expect(await userDoc(_me), isNull);

      final other = AppLanguageSync(
        firestore: db,
        auth: _authFor('second-account'),
        store: store,
        log: logs.add,
      );
      addTearDown(other.dispose);
      await other.synchronize(const Locale('de'));
      expect((await userDoc('second-account'))!['appLanguage'], 'de');
      expect(store.values[AppLanguageSync.storeKey], 'second-account|de');
    });

    test('nothing is written while signed out; signing in stores it', () async {
      final auth = MockFirebaseAuth(mockUser: MockUser(uid: _me));
      final sync = AppLanguageSync(
        firestore: db,
        auth: auth,
        store: store,
        log: logs.add,
      );
      addTearDown(sync.dispose);
      await sync.synchronize(const Locale('fr'));
      expect(await userDoc(_me), isNull);
      expect(store.values, isEmpty);

      await auth.signInWithCredential(null);
      for (var turn = 0; turn < 10; turn++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect((await userDoc(_me))!['appLanguage'], 'fr');
      expect(store.values[AppLanguageSync.storeKey], '$_me|fr');
    });

    test('an unwritable store costs a write, never the language', () async {
      store.failWrites = true;
      final sync = AppLanguageSync(
        firestore: db,
        auth: _authFor(_me),
        store: store,
        log: logs.add,
      );
      addTearDown(sync.dispose);
      await sync.synchronize(const Locale('it'));
      expect((await userDoc(_me))!['appLanguage'], 'it');
    });
  });
}
