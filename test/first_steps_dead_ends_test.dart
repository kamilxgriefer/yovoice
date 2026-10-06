// firstSteps A (2026-10-03): the three dead ends each gain one clear action.
//
//  * the server invite sheet with nobody to invite;
//  * the empty Notifications screen;
//  * the empty friends list.
//
// Each action leads to a real place, and none is drawn where it would not be
// true (no link on an invite-only server, no "find Pages" while Treści is
// off).

import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/friends/presentation/screens/add_friend_screen.dart';
import 'package:yovoice/features/friends/presentation/screens/friends_screen.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/page_navigation.dart';
import 'package:yovoice/features/pages/presentation/screens/find_pages_host.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_session.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/server_links.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_invite_sheet.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';

import 'server_test_support.dart';

const _me = 'me-uid';

Server _server({required ServerType type, required ServerPrivacy privacy}) =>
    Server(
      id: 'srv1',
      name: 'Nocne Granie',
      description: '',
      ownerId: 'owner',
      type: type,
      privacy: privacy,
      memberCount: 128,
      schemaVersion: 1,
      activationState: 'active',
    );

class _NoSuggestions implements SocialGraphService {
  @override
  Future<List<SuggestedFriend>> getFriendSuggestions({int limit = 10}) async =>
      const <SuggestedFriend>[];

  @override
  Future<MutualFriendsSummary> getMutualFriends(String targetUserId) async =>
      MutualFriendsSummary.empty;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _localized(
  Widget home, {
  double textScale = 1,
  Locale locale = const Locale('pl'),
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
  home: home,
);

void main() {
  group('server invite sheet with nobody to invite', () {
    Future<void> pumpSheet(
      WidgetTester tester, {
      required Server server,
      List<ServerInviteCandidate> friends = const [],
      Future<void> Function(Uri link)? shareServer,
      VoidCallback? onAddFriends,
      Size size = const Size(390, 844),
      double textScale = 1,
      Locale locale = const Locale('pl'),
    }) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [server]
        ..friends = friends;
      await pumpServers(
        tester,
        Scaffold(
          body: ServerInviteSheet(
            server: server,
            repository: repository,
            shareServer: shareServer,
            onAddFriends: onAddFriends,
          ),
        ),
        size: size,
        textScale: textScale,
        locale: locale,
      );
    }

    testWidgets('a public server offers its link first, then Add friends', (
      tester,
    ) async {
      final shared = <Uri>[];
      var addFriends = 0;
      await pumpSheet(
        tester,
        server: _server(
          type: ServerType.community,
          privacy: ServerPrivacy.public,
        ),
        shareServer: (link) async => shared.add(link),
        onAddFriends: () => addFriends += 1,
      );

      expect(find.text('Nie masz jeszcze kogo zaprosić'), findsOneWidget);
      final share = find.byKey(const ValueKey('server-invite-share-link'));
      final add = find.byKey(const ValueKey('server-invite-add-friends'));
      expect(share, findsOneWidget);
      expect(add, findsOneWidget);
      expect(
        find.descendant(
          of: share,
          matching: find.text('Udostępnij link do serwera'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: add, matching: find.text('Dodaj znajomych')),
        findsOneWidget,
      );
      // One violet fill: the link. "Dodaj znajomych" is the tonal second.
      expect(find.byType(YoGradientFilledButton), findsOneWidget);
      expect(
        tester.getTopLeft(add).dy,
        greaterThan(tester.getBottomLeft(share).dy),
      );
      expect(tester.getSize(share).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(add).height, greaterThanOrEqualTo(48));

      await tester.tap(share);
      await tester.pumpAndSettle();
      expect(shared, [buildServerLink('srv1')]);
      expect(shared.single.toString(), 'https://app.yovoice.app/?server=srv1');

      await tester.tap(add);
      await tester.pump();
      expect(addFriends, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an invite-only server offers Add friends alone', (
      tester,
    ) async {
      var addFriends = 0;
      await pumpSheet(
        tester,
        server: _server(
          type: ServerType.friends,
          privacy: ServerPrivacy.inviteOnly,
        ),
        shareServer: (_) async => fail('no link on an invite-only server'),
        onAddFriends: () => addFriends += 1,
      );

      expect(
        find.byKey(const ValueKey('server-invite-share-link')),
        findsNothing,
      );
      expect(find.text('Udostępnij link do serwera'), findsNothing);
      final add = find.byKey(const ValueKey('server-invite-add-friends'));
      expect(add, findsOneWidget);
      // Alone, it is the primary (the gradient).
      expect(
        find.ancestor(of: add, matching: find.byType(YoGradientFilledButton)),
        findsOneWidget,
      );
      await tester.tap(add);
      await tester.pump();
      expect(addFriends, 1);
    });

    testWidgets('a private community server does not offer a link either', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        server: _server(
          type: ServerType.community,
          privacy: ServerPrivacy.inviteOnly,
        ),
      );
      expect(
        find.byKey(const ValueKey('server-invite-share-link')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('server-invite-add-friends')),
        findsOneWidget,
      );
    });

    testWidgets('with friends to invite there are no empty-state actions', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        server: _server(
          type: ServerType.community,
          privacy: ServerPrivacy.public,
        ),
        friends: const [ServerInviteCandidate(id: 'u2', displayName: 'Ola')],
      );
      expect(find.text('Ola'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('server-invite-share-link')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('server-invite-add-friends')),
        findsNothing,
      );
    });

    testWidgets('a share that fails says so and can be tried again', (
      tester,
    ) async {
      var attempts = 0;
      await pumpSheet(
        tester,
        server: _server(
          type: ServerType.community,
          privacy: ServerPrivacy.public,
        ),
        shareServer: (_) async {
          attempts += 1;
          if (attempts == 1) throw StateError('share sheet unavailable');
        },
      );
      final share = find.byKey(const ValueKey('server-invite-share-link'));
      await tester.tap(share);
      await tester.pumpAndSettle();
      // Said inside the sheet, under the button: a snackbar would be drawn
      // on the page beneath the sheet, where nobody sees it.
      final failure = find.byKey(const ValueKey('server-invite-share-failed'));
      expect(failure, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ServerInviteSheet),
          matching: find.text(
            'Nie udało się udostępnić linku. Spróbuj ponownie.',
          ),
        ),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(
        tester.getTopLeft(failure).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(share).dy),
      );
      await tester.tap(share);
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(failure, findsNothing, reason: 'a share that opened clears it');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the system share sheet is anchored on the button, which '
        'iPadOS requires for its popover', (tester) async {
      const channel = MethodChannel('dev.fluttercommunity.plus/share');
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return 'dev.fluttercommunity.plus/share/unavailable';
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      // No seam: the production path through share_plus.
      await pumpSheet(
        tester,
        server: _server(
          type: ServerType.community,
          privacy: ServerPrivacy.public,
        ),
        size: const Size(768, 1024),
      );
      final share = find.byKey(const ValueKey('server-invite-share-link'));
      await tester.tap(share);
      await tester.pumpAndSettle();

      expect(calls, hasLength(1));
      expect(calls.single.method, 'share');
      final arguments = (calls.single.arguments as Map).cast<String, Object?>();
      expect(
        arguments['text'],
        'Nocne Granie\nhttps://app.yovoice.app/?server=srv1',
      );
      final origin = Rect.fromLTWH(
        arguments['originX']! as double,
        arguments['originY']! as double,
        arguments['originWidth']! as double,
        arguments['originHeight']! as double,
      );
      expect(origin.isEmpty, isFalse);
      expect(origin.contains(tester.getCenter(share)), isTrue);
      expect(
        (Offset.zero & const Size(768, 1024)).contains(origin.topLeft),
        isTrue,
      );
      expect(
        find.byKey(const ValueKey('server-invite-share-failed')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at 320 px and 200 % text', (tester) async {
      await pumpSheet(
        tester,
        server: _server(
          type: ServerType.community,
          privacy: ServerPrivacy.public,
        ),
        size: const Size(320, 690),
        textScale: 2,
      );
      expect(
        find.byKey(const ValueKey('server-invite-share-link')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('both actions fit 320 px in every selectable locale', (
      tester,
    ) async {
      for (final locale in AppLocalizations.supportedLocales) {
        await pumpSheet(
          tester,
          server: _server(
            type: ServerType.community,
            privacy: ServerPrivacy.public,
          ),
          size: const Size(320, 690),
          locale: locale,
        );
        expect(
          find.byKey(const ValueKey('server-invite-share-link')),
          findsOneWidget,
          reason: '$locale',
        );
        expect(tester.takeException(), isNull, reason: '$locale');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  });

  group('empty Notifications', () {
    late FakeFirebaseFirestore db;
    late MockFirebaseAuth auth;
    late MessageService messages;

    setUp(() {
      db = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: _me, email: '$_me@yovoice.app'),
      );
      messages = MessageService(firestore: db, auth: auth);
    });

    tearDown(() {
      unawaited(messages.dispose());
      FriendService.clearSharedReadCaches();
    });

    Future<void> pumpEmpty(
      WidgetTester tester, {
      required ValueNotifier<bool> pagesEnabled,
      Future<void> Function(BuildContext context)? onFindPages,
      VoidCallback? onAddFriends,
      double textScale = 1,
      Size size = const Size(390, 844),
      Locale locale = const Locale('pl'),
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _localized(
          NotificationsScreen(
            isRootTab: true,
            acknowledgeOnVisible: false,
            friendService: FriendService(firestore: db, auth: auth),
            messageService: messages,
            notificationService: NotificationService(firestore: db, auth: auth),
            currentUserId: _me,
            pagesEnabled: pagesEnabled,
            onFindPages: onFindPages,
            onAddFriends: onAddFriends,
          ),
          textScale: textScale,
          locale: locale,
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    testWidgets('with Treści on, the action opens Find Pages', (tester) async {
      final pagesEnabled = ValueNotifier<bool>(true);
      addTearDown(pagesEnabled.dispose);
      var opened = 0;
      await pumpEmpty(
        tester,
        pagesEnabled: pagesEnabled,
        onFindPages: (_) async => opened += 1,
        onAddFriends: () => fail('Pages are on: the action is Find Pages'),
      );

      expect(find.text('Wszystko jest już sprawdzone'), findsOneWidget);
      final action = find.byKey(
        const ValueKey('notifications-empty-find-pages'),
      );
      expect(action, findsOneWidget);
      expect(
        find.descendant(
          of: action,
          matching: find.text('Znajdź strony do obserwowania'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(action).dy,
        greaterThan(
          tester
              .getBottomLeft(
                find.text(
                  'Nowe zaproszenia, wiadomości i aktywność pojawią się tutaj.',
                ),
              )
              .dy,
        ),
      );
      expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
      await tester.tap(action);
      await tester.pump();
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with Treści off, the action is Add friends', (tester) async {
      final pagesEnabled = ValueNotifier<bool>(false);
      addTearDown(pagesEnabled.dispose);
      var added = 0;
      await pumpEmpty(
        tester,
        pagesEnabled: pagesEnabled,
        onFindPages: (_) async => fail('Pages are off'),
        onAddFriends: () => added += 1,
      );

      expect(
        find.byKey(const ValueKey('notifications-empty-find-pages')),
        findsNothing,
      );
      expect(find.text('Znajdź strony do obserwowania'), findsNothing);
      final action = find.byKey(
        const ValueKey('notifications-empty-add-friends'),
      );
      expect(action, findsOneWidget);
      expect(
        find.descendant(of: action, matching: find.text('Dodaj znajomych')),
        findsOneWidget,
      );
      await tester.tap(action);
      await tester.pump();
      expect(added, 1);

      // The kill switch flips live: the label follows it.
      pagesEnabled.value = true;
      await tester.pump();
      expect(
        find.byKey(const ValueKey('notifications-empty-find-pages')),
        findsOneWidget,
      );
    });

    testWidgets('without a shell to host Find Pages it is not offered', (
      tester,
    ) async {
      final pagesEnabled = ValueNotifier<bool>(true);
      addTearDown(pagesEnabled.dispose);
      expect(PagesShellBridge.findHost, isNull);
      await pumpEmpty(tester, pagesEnabled: pagesEnabled, onAddFriends: () {});
      expect(
        find.byKey(const ValueKey('notifications-empty-find-pages')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('notifications-empty-add-friends')),
        findsOneWidget,
      );
    });

    testWidgets('the default Add friends action opens the Add friend screen', (
      tester,
    ) async {
      final pagesEnabled = ValueNotifier<bool>(false);
      addTearDown(pagesEnabled.dispose);
      await pumpEmpty(tester, pagesEnabled: pagesEnabled);
      await tester.tap(
        find.byKey(const ValueKey('notifications-empty-add-friends')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AddFriendScreen), findsOneWidget);
      // Leave before the screen's own suggestion request is torn down.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('no overflow at 320 px and 200 % text', (tester) async {
      final pagesEnabled = ValueNotifier<bool>(true);
      addTearDown(pagesEnabled.dispose);
      await pumpEmpty(
        tester,
        pagesEnabled: pagesEnabled,
        onFindPages: (_) async {},
        size: const Size(320, 640),
        textScale: 2,
      );
      expect(
        find.byKey(const ValueKey('notifications-empty-find-pages')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('empty Notifications in every locale', () {
    testWidgets('either action fits 320 px in every selectable locale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.reset);
      for (final locale in AppLocalizations.supportedLocales) {
        for (final pages in const [true, false]) {
          final db = FakeFirebaseFirestore();
          final auth = MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: _me, email: '$_me@yovoice.app'),
          );
          final messages = MessageService(firestore: db, auth: auth);
          final pagesEnabled = ValueNotifier<bool>(pages);
          await tester.pumpWidget(
            _localized(
              NotificationsScreen(
                isRootTab: true,
                acknowledgeOnVisible: false,
                friendService: FriendService(firestore: db, auth: auth),
                messageService: messages,
                notificationService: NotificationService(
                  firestore: db,
                  auth: auth,
                ),
                currentUserId: _me,
                pagesEnabled: pagesEnabled,
                onFindPages: (_) async {},
                onAddFriends: () {},
              ),
              locale: locale,
            ),
          );
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 80));
          }
          expect(
            find.byKey(
              ValueKey(
                pages
                    ? 'notifications-empty-find-pages'
                    : 'notifications-empty-add-friends',
              ),
            ),
            findsOneWidget,
            reason: '$locale pages=$pages',
          );
          expect(tester.takeException(), isNull, reason: '$locale');
          await tester.pumpWidget(const SizedBox.shrink());
          await messages.dispose();
          pagesEnabled.dispose();
          FriendService.clearSharedReadCaches();
        }
      }
    });
  });

  group('empty friends list', () {
    late FakeFirebaseFirestore db;
    late MockFirebaseAuth auth;
    late MessageService messages;

    setUp(() async {
      db = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: _me, email: '$_me@yovoice.app'),
      );
      messages = MessageService(firestore: db, auth: auth);
      await db.collection('users').doc(_me).set({
        'uid': _me,
        'displayName': 'Kamil',
      });
    });

    tearDown(() {
      unawaited(messages.dispose());
      FriendService.clearSharedReadCaches();
    });

    Future<void> seedFriend(String id, String name) async {
      await db.collection('publicProfiles').doc(id).set({
        'uid': id,
        'displayName': name,
        'username': name.toLowerCase(),
      });
      await db.collection('users').doc(_me).collection('friends').doc(id).set({
        'friendId': id,
        'displayName': name,
      });
    }

    Widget screen({double textScale = 1}) => _localized(
      FriendsScreen(
        isRootTab: true,
        friendService: FriendService(
          firestore: db,
          auth: auth,
          mutationInvoker: (name, data) async => const {'outcome': 'requested'},
        ),
        messageService: messages,
        socialGraphService: _NoSuggestions(),
        firestore: db,
        auth: auth,
      ),
      textScale: textScale,
    );

    testWidgets('the message is followed by Add friend, which opens search', (
      tester,
    ) async {
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      expect(find.text('Nie masz jeszcze znajomych'), findsOneWidget);
      final action = find.byKey(const ValueKey('friends-empty-add-friend'));
      expect(action, findsOneWidget);
      expect(
        find.descendant(of: action, matching: find.text('Dodaj znajomego')),
        findsOneWidget,
      );
      // The header keeps the page's one violet fill; this one is tonal.
      expect(
        find.ancestor(
          of: action,
          matching: find.byType(YoGradientFilledButton),
        ),
        findsNothing,
      );
      expect(
        tester.getTopLeft(action).dy,
        greaterThan(
          tester
              .getBottomLeft(
                find.text('Znajdź kogoś i zacznij budować swoje grono.'),
              )
              .dy,
        ),
      );
      expect(tester.getSize(action).height, greaterThanOrEqualTo(44));

      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AddFriendScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a search or the Online filter that matched nobody has none', (
      tester,
    ) async {
      await seedFriend('ada', 'Ada');
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('friends-empty-add-friend')),
        findsNothing,
      );

      await tester.enterText(find.byType(TextField).first, 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Brak pasujących znajomych'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('friends-empty-add-friend')),
        findsNothing,
      );
    });

    testWidgets('no overflow at 320 px and 200 % text', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 690);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(screen(textScale: 2));
      await tester.pumpAndSettle();
      // On a short screen the header, filters and results share one lazy
      // scroll: the empty state is below the fold until it is scrolled to.
      final action = find.byKey(const ValueKey('friends-empty-add-friend'));
      await tester.scrollUntilVisible(
        action,
        160,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('friends-coordinated-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(action, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
  group('Find Pages hosted from outside Treści', () {
    final now = DateTime.utc(2026, 10, 3, 12);

    PagesService service() => PagesService(
      invoker: (name, payload) async => <String, Object?>{
        'schemaVersion': 1,
        'pages': [
          <String, Object?>{
            'pageId': 'glina',
            'displayName': 'Pracownia Glina',
            'kind': 'business',
            'category': 'shop',
            'followerCount': 128,
            'onYoVoiceSinceMs': now.millisecondsSinceEpoch,
            'viewerFollows': false,
            'lastPostAtMs': now
                .subtract(const Duration(hours: 2))
                .millisecondsSinceEpoch,
          },
        ],
        'nextCursor': null,
        'hasMore': false,
      },
      clock: () => now,
    );

    testWidgets('it is the real Find Pages; Back returns to the caller and a '
        'Page opens through the given flow', (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(
        _localized(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        body: FindPagesHost(
                          service: service(),
                          onOpenPage:
                              (context, {required pageId, displayName}) async =>
                                  opened.add('$pageId|$displayName'),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('caller'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('caller'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('find-pages-field')), findsOneWidget);
      expect(find.byKey(const ValueKey('pages-canvas')), findsOneWidget);
      expect(find.text('Pracownia Glina'), findsOneWidget);

      await tester.tap(find.text('Pracownia Glina'));
      await tester.pump();
      expect(opened, ['glina|Pracownia Glina']);

      await tester.tap(find.byTooltip('Wstecz'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('find-pages-field')), findsNothing);
      expect(find.text('caller'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
