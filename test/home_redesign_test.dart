// Home-only author regressions and optional real-render capture.
// Fixtures are injected here; no illustrative activity enters production.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_moments_strip.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_overview_sections.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_status.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';

const _capture = bool.fromEnvironment('YO_CAPTURE_HOME_REDESIGN');
const _me = 'home-redesign-me';

/// Tracks individual subscription ownership, including concurrent listeners.
class _Source<T> {
  _Source() {
    stream = Stream<T>.multi((sink) {
      listens++;
      if (_hasValue) sink.add(_value as T);
      if (_error != null) sink.addError(_error!);
      final subscription = _events.stream.listen(
        sink.add,
        onError: sink.addError,
      );
      sink.onCancel = () {
        cancels++;
        return subscription.cancel();
      };
    }, isBroadcast: true);
  }
  final _events = StreamController<T>.broadcast();
  late final Stream<T> stream;
  T? _value;
  Object? _error;
  bool _hasValue = false;
  int listens = 0;
  int cancels = 0;
  void add(T value) {
    _value = value;
    _error = null;
    _hasValue = true;
    _events.add(value);
  }

  void deny() {
    _value = null;
    _hasValue = false;
    _error = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
    _events.addError(_error!);
  }

  Future<void> close() => _events.close();
}

class _Rooms extends RoomService {
  _Rooms(this.fixture) : super(firestore: fixture.db, auth: fixture.auth);
  final _Fixture fixture;
  @override
  Stream<List<VoiceRoom>> watchLivePublicRooms() => fixture.rooms.stream;
  @override
  Stream<List<VoiceRoom>> watchOwnedRooms() => fixture.owned.stream;
}

class _Friends extends FriendService {
  _Friends(this.fixture) : super(firestore: fixture.db, auth: fixture.auth);
  final _Fixture fixture;
  @override
  Stream<List<FriendUser>> watchFriends() => fixture.friends.stream;
}

class _Following extends FollowService {
  _Following(this.fixture) : super(firestore: fixture.db, auth: fixture.auth);
  final _Fixture fixture;
  @override
  Stream<List<FollowUser>> watchFollowing(String userId) =>
      fixture.following.stream;
}

class _Feed extends HomeFeedService {
  _Feed(this.fixture) : super(firestore: fixture.db, auth: fixture.auth);
  final _Fixture fixture;
  int reads = 0;
  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) {
    reads++;
    // New stream identity models a new one-shot provider request on retry.
    return fixture.moments.stream.map((value) => value);
  }
}

class _Messages extends MessageService {
  _Messages(this.fixture) : super(firestore: fixture.db, auth: fixture.auth);
  final _Fixture fixture;
  int reads = 0;
  @override
  Stream<List<Conversation>> watchConversations({
    bool includeArchived = false,
  }) {
    reads++;
    return fixture.chats.stream.map((value) => value);
  }
}

class _Capabilities extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      StaffCapabilities.none;
}

class _Fixture {
  final db = FakeFirebaseFirestore();
  final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me));
  final rooms = _Source<List<VoiceRoom>>();
  final owned = _Source<List<VoiceRoom>>();
  final friends = _Source<List<FriendUser>>();
  final following = _Source<List<FollowUser>>();
  final moments = _Source<List<VoiceMoment>>();
  final chats = _Source<List<Conversation>>();
  final visible = ValueNotifier<bool>(true);
  late final roomService = _Rooms(this);
  late final friendService = _Friends(this);
  late final followService = _Following(this);
  late final feedService = _Feed(this);
  late final messageService = _Messages(this);
  late final profileService = ProfileService(firestore: db, auth: auth);
  final actions = <String>[];
  late VoiceRoom liveRoom;
  late VoiceRoom ownedRoom;

  Future<void> initialize({
    bool populated = true,
    bool loading = false,
    bool longName = false,
  }) async {
    await db.doc('users/$_me').set({
      'uid': _me,
      'displayName': longName ? 'Aleksandra Nowakowska-Kowalska' : 'Aleksandra',
      'username': 'aleksandra',
      'availability': 'available',
    });
    for (final (id, owner) in [('qa-live', 'qa-friend'), ('qa-owned', _me)]) {
      await db.doc('rooms/$id').set({
        'hostId': owner,
        'hostName': owner == _me ? 'Aleksandra' : 'Ola',
        'name': owner == _me ? 'Twój pokój' : 'Wieczorne rozmowy',
        'description': 'Rozmowy, pomysły i codzienne historie.',
        'category': 'community',
        'visibility': 'public',
        'language': 'Polish',
        'participantCount': owner == _me ? 0 : 3,
        'memberCount': 0,
        'isLive': owner != _me,
        'roomType': 'community',
        'status': 'active',
        'experience': 'community',
        'createdAt': Timestamp.now(),
      });
    }
    liveRoom = VoiceRoom.fromFirestore(await db.doc('rooms/qa-live').get());
    ownedRoom = VoiceRoom.fromFirestore(await db.doc('rooms/qa-owned').get());
    await db.doc('conversations/qa-chat').set({
      'participantIds': [_me, 'qa-friend'],
      'participantNames': {_me: 'Aleksandra', 'qa-friend': 'Ola'},
      'unreadCounts': {_me: 2},
      'lastMessage': 'Masz chwilę na rozmowę?',
      'lastMessageType': 'text',
      'lastMessageSenderId': 'qa-friend',
      'updatedAt': Timestamp.now(),
      'createdAt': Timestamp.now(),
    });
    if (loading) return;
    rooms.add(populated ? [liveRoom] : []);
    owned.add(populated ? [ownedRoom] : []);
    friends.add(
      populated
          ? [
              for (final name in ['Ola', 'Marek', 'Ada', 'Szymon'])
                FriendUser(
                  id: name == 'Ola' ? 'qa-friend' : 'qa-$name',
                  displayName: name,
                  email: '',
                  photoUrl: null,
                  isOnline: name == 'Ola',
                  lastSeen: null,
                  availability: name == 'Ola' ? 'available' : 'away',
                ),
            ]
          : [],
    );
    following.add([
      const FollowUser(
        uid: 'qa-friend',
        displayName: 'Ola',
        username: 'ola',
        photoUrl: null,
        followedAt: null,
      ),
    ]);
    moments.add(
      populated
          ? [
              VoiceMoment(
                id: 'qa-moment',
                authorId: 'qa-friend',
                authorName: 'Ola',
                authorPhotoUrl: null,
                caption: 'Małe rzeczy cieszą',
                audioUrl: null,
                durationSeconds: 12,
                likeCount: 2,
                commentCount: 1,
                isPublished: true,
                createdAt: DateTime.now(),
                schemaVersion: 2,
                status: 'published',
                hasAuthorizedMedia: true,
              ),
            ]
          : [],
    );
    chats.add(
      populated
          ? [
              Conversation.fromFirestore(
                await db.doc('conversations/qa-chat').get(),
              ),
            ]
          : [],
    );
  }

  Widget home({required bool desktop}) => desktop
      ? DesktopHome(
          key: const ValueKey('redesign-home'),
          currentUserId: _me,
          onOpenRoom: (r) => actions.add('room:${r.id}'),
          onSeeAllRooms: () => actions.add('discover'),
          onViewAllFriends: () => actions.add('friends'),
          onStartRoom: () => actions.add('create'),
          onOpenMoment: (m) => actions.add('moment:${m.id}'),
          onOpenChain: (m) => actions.add('chain:${m.first.id}'),
          onCreateMoment: () => actions.add('record'),
          onSeeAllMoments: () => actions.add('moments'),
          onOpenConversation: (c) => actions.add('chat:${c.id}'),
          onSeeAllChats: () => actions.add('chats'),
          onOpenClub: (_) {},
          onOpenClubs: () {},
          roomService: roomService,
          friendService: friendService,
          followService: followService,
          profileService: profileService,
          feedService: feedService,
          messageService: messageService,
          capabilityService: _Capabilities(),
          isVisible: visible,
        )
      : MobileHome(
          key: const ValueKey('redesign-home'),
          currentUserId: _me,
          onOpenRoom: (r) => actions.add('room:${r.id}'),
          onOpenDiscover: () => actions.add('discover'),
          onOpenFriends: () => actions.add('friends'),
          onCreateRoom: () => actions.add('create'),
          onOpenNotifications: () => actions.add('notifications'),
          onOpenProfile: () => actions.add('profile'),
          unreadNotificationCount: 2,
          onOpenMoment: (m) => actions.add('moment:${m.id}'),
          onOpenChain: (m) => actions.add('chain:${m.first.id}'),
          onCreateMoment: () => actions.add('record'),
          onSeeAllMoments: () => actions.add('moments'),
          onOpenComments: (_) {},
          onOpenConversation: (c) => actions.add('chat:${c.id}'),
          onSeeAllChats: () => actions.add('chats'),
          roomService: roomService,
          friendService: friendService,
          followService: followService,
          profileService: profileService,
          feedService: feedService,
          messageService: messageService,
          capabilityService: _Capabilities(),
          isVisible: visible,
        );

  List<int> get listens => [
    rooms.listens,
    owned.listens,
    friends.listens,
    following.listens,
    moments.listens,
    chats.listens,
  ];

  Future<void> dispose() async {
    visible.dispose();
    await Future.wait([
      rooms.close(),
      owned.close(),
      friends.close(),
      following.close(),
      moments.close(),
      chats.close(),
    ]);
  }
}

Widget _app(
  Widget home,
  Size size, {
  double scale = 1,
  bool pearl = false,
  bool dock = false,
  GlobalKey? captureKey,
}) => RepaintBoundary(
  key: captureKey,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: pearl ? AppTheme.lightTheme : AppTheme.darkTheme,
    locale: const Locale('pl'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(scale),
        disableAnimations: true,
        padding: dock ? const EdgeInsets.only(top: 24) : EdgeInsets.zero,
      ),
      child: Scaffold(
        body: home,
        bottomNavigationBar: dock
            ? YoFloatingNavigationDock(
                selectedTabIndex: 0,
                momentsTabIndex: 5,
                unreadConversationCount: 2,
                onDestinationSelected: (_) {},
                onMorePressed: () {},
                onVoicePressed: () {},
              )
            : null,
      ),
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

List<Map<Object?, Object?>> _captureErrorAnnouncements(WidgetTester tester) {
  final messages = <Map<Object?, Object?>>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
    SystemChannels.accessibility,
    (message) async {
      if (message is Map && message['type'] == 'announce') {
        messages.add(message['data'] as Map<Object?, Object?>);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler(
      SystemChannels.accessibility,
      null,
    ),
  );
  return messages;
}

Future<void> _shoot(WidgetTester tester, GlobalKey key, String name) async {
  if (!_capture) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('test/.screenshots/home-redesign-2026-09-11/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    if (!_capture) return;
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))).load();
    final icons = File(
      '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
        .load();
  });
  setUp(ProfileService.resetCurrentProfileCache);
  tearDown(ProfileService.resetCurrentProfileCache);

  for (final desktop in [false, true]) {
    testWidgets('Home $desktop errors announce once per active episode', (
      tester,
    ) async {
      const size = Size(1440, 2800);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final messages = _captureErrorAnnouncements(tester);
      final f = _Fixture();
      await f.initialize();
      addTearDown(f.dispose);
      await tester.pumpWidget(_app(f.home(desktop: desktop), size));
      await _settle(tester);
      messages.clear();
      f.rooms.deny();
      f.moments.deny();
      f.chats.deny();
      await _settle(tester);
      expect(find.byType(HomeSectionError), findsNWidgets(3));
      expect(messages, hasLength(1));
      expect(messages.single['assertiveness'], Assertiveness.assertive.index);
      const safeMessage = 'Nie masz uprawnień, aby to zrobić.';
      expect(messages.single['message'], safeMessage);

      // The real Home scope, including a desktop column reparent, retains
      // its active episode through localization-independent presentation.
      const resized = Size(768, 2800);
      tester.view.physicalSize = resized;
      await tester.pumpWidget(
        _app(f.home(desktop: desktop), resized, scale: 2, pearl: true),
      );
      await _settle(tester);
      expect(messages, hasLength(1));
      f.rooms.add([]);
      f.moments.add([]);
      f.chats.add([]);
      await _settle(tester);
      expect(find.byType(HomeSectionError), findsNothing);
      f.rooms.deny();
      await _settle(tester);
      expect(messages, hasLength(2));
      expect(messages.last['message'], safeMessage);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await _settle(tester);
      expect(messages, hasLength(2));
    });

    testWidgets('Home $desktop hidden failures wait for the visible surface', (
      tester,
    ) async {
      const size = Size(1440, 2800);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final messages = _captureErrorAnnouncements(tester);
      final f = _Fixture();
      await f.initialize();
      addTearDown(f.dispose);
      await tester.pumpWidget(_app(f.home(desktop: desktop), size));
      await _settle(tester);
      messages.clear();
      f.visible.value = false;
      f.rooms.deny();
      f.chats.deny();
      await _settle(tester);
      expect(messages, isEmpty);
      f.visible.value = true;
      await _settle(tester);
      expect(messages, hasLength(1));
      f.visible.value = false;
      await _settle(tester);
      f.visible.value = true;
      await _settle(tester);
      expect(messages, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'Home $desktop following denial removes only followed content',
      (tester) async {
        const size = Size(1440, 2400);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final f = _Fixture();
        await f.initialize();
        addTearDown(f.dispose);
        await tester.pumpWidget(_app(f.home(desktop: desktop), size));
        await _settle(tester);
        final before = f.listens;
        f.following.deny();
        await _settle(tester);
        expect(
          find.byKey(const ValueKey('home-moment-qa-moment')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('home-moments-error')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('home-featured-room')),
          findsOneWidget,
        );
        expect(find.text('Twój pokój'), findsOneWidget);
        expect(f.listens, before);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('Home $desktop chat denial has an independent fresh retry', (
      tester,
    ) async {
      const size = Size(1440, 2400);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final f = _Fixture();
      await f.initialize();
      addTearDown(f.dispose);
      await tester.pumpWidget(_app(f.home(desktop: desktop), size));
      await _settle(tester);
      f.chats.deny();
      await _settle(tester);
      final error = find.byKey(const ValueKey('home-chats-error'));
      expect(error, findsOneWidget);
      expect(find.text('Masz chwilę na rozmowę?'), findsNothing);
      expect(
        find.byKey(const ValueKey('home-moment-qa-moment')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: error, matching: find.byType(OutlinedButton)),
      );
      await _settle(tester);
      expect(f.messageService.reads, 2);
      expect(f.feedService.reads, 1);
      f.chats.add([]);
      await _settle(tester);
      expect(error, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'Home $desktop permission loss removes content; retry stays local',
      (tester) async {
        const size = Size(1440, 2400);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final f = _Fixture();
        await f.initialize();
        addTearDown(f.dispose);
        await tester.pumpWidget(_app(f.home(desktop: desktop), size));
        await _settle(tester);
        expect(
          find.byKey(const ValueKey('home-moment-qa-moment')),
          findsOneWidget,
        );
        final chatReads = f.chats.listens;
        f.moments.deny();
        await _settle(tester);
        expect(
          find.byKey(const ValueKey('home-moment-qa-moment')),
          findsNothing,
        );
        final error = find.byKey(const ValueKey('home-moments-error'));
        expect(error, findsOneWidget);
        expect(
          find.byKey(const ValueKey('home-featured-room')),
          findsOneWidget,
        );
        expect(f.chats.listens, chatReads);
        await tester.tap(
          find.descendant(of: error, matching: find.byType(OutlinedButton)),
        );
        await _settle(tester);
        expect(f.feedService.reads, 2);
        expect(
          find.byKey(const ValueKey('home-moment-qa-moment')),
          findsNothing,
        );
        f.moments.add([]);
        await _settle(tester);
        expect(error, findsNothing);
        expect(
          find.byKey(const ValueKey('home-record-moment')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'Home $desktop empty-to-live preserves chat and owned subscriptions',
      (tester) async {
        const size = Size(1440, 2400);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final f = _Fixture();
        await f.initialize();
        f.rooms.add([]);
        f.moments.add([]);
        addTearDown(f.dispose);
        await tester.pumpWidget(_app(f.home(desktop: desktop), size));
        await _settle(tester);
        expect(find.byType(HomeConversationInvitation), findsOneWidget);
        final listens = f.listens;
        final action = find.byKey(const ValueKey('home-quick-create-room'));
        final focus = Focus.of(
          tester.element(
            find.descendant(of: action, matching: find.byType(Text)).first,
          ),
        );
        focus.requestFocus();
        await tester.pump();
        f.rooms.add([f.liveRoom]);
        await _settle(tester);
        expect(find.byType(HomeConversationInvitation), findsNothing);
        expect(f.listens, listens);
        expect(focus.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(f.actions, ['create']);
        expect(find.text('Twój pokój'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Home error channel composes safe messages and replaces queued copy',
    (tester) async {
      final messages = _captureErrorAnnouncements(tester);
      const size = Size(800, 1200);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Widget errors(String first) => _app(
        HomeErrorAnnouncementScope(
          child: Column(
            children: [
              HomeSectionError(
                message: first,
                error: StateError(
                  'private-provider-detail-should-never-be-spoken',
                ),
                onRetry: null,
              ),
              const HomeSectionError(
                message: 'Second safe error.',
                onRetry: null,
              ),
              const HomeSectionError(
                message: 'Second safe error.',
                onRetry: null,
              ),
            ],
          ),
        ),
        size,
      );
      await tester.pumpWidget(errors('Withdrawn safe error.'));
      expect(messages, isEmpty);
      await tester.pumpWidget(errors('Current safe error.'));
      await _settle(tester);
      expect(messages, hasLength(1));
      expect(messages.single['assertiveness'], Assertiveness.assertive.index);
      expect(
        messages.single['message'],
        'Current safe error.\nSecond safe error.',
      );
      expect(
        messages.single.toString(),
        isNot(contains('private-provider-detail')),
      );
      expect(messages.single.toString(), isNot(contains('Withdrawn')));
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final removeScope in [false, true]) {
    testWidgets(
      'Home error channel drops withdrawn/unmounted $removeScope speech',
      (tester) async {
        final messages = _captureErrorAnnouncements(tester);
        const size = Size(800, 1200);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _app(
            const HomeErrorAnnouncementScope(
              child: HomeSectionError(
                message: 'No longer current.',
                onRetry: null,
              ),
            ),
            size,
          ),
        );
        expect(messages, isEmpty);
        await tester.pumpWidget(
          removeScope
              ? const SizedBox()
              : _app(const HomeErrorAnnouncementScope(child: SizedBox()), size),
        );
        await _settle(tester);
        expect(messages, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('standalone desktop own chain survives following denial', (
    tester,
  ) async {
    const size = Size(1440, 1000);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = _Fixture();
    await f.initialize();
    addTearDown(f.dispose);
    f.moments.add([
      VoiceMoment(
        id: 'qa-own-moment',
        authorId: _me,
        authorName: 'Aleksandra',
        authorPhotoUrl: null,
        caption: 'Własna historia',
        audioUrl: null,
        durationSeconds: 12,
        likeCount: 0,
        commentCount: 0,
        isPublished: true,
        createdAt: DateTime.now(),
        schemaVersion: 2,
        status: 'published',
        hasAuthorizedMedia: true,
      ),
    ]);
    await tester.pumpWidget(
      _app(
        DesktopMomentsStrip(
          currentUserId: _me,
          feedService: f.feedService,
          friendService: f.friendService,
          followService: f.followService,
          onOpenMoment: (moment) => f.actions.add('moment:${moment.id}'),
          onOpenChain: (chain) => f.actions.add('chain:${chain.first.id}'),
          onCreateMoment: () => f.actions.add('record'),
          onSeeAll: () => f.actions.add('moments'),
        ),
        size,
      ),
    );
    await _settle(tester);
    final reads = f.feedService.reads;
    f.following.deny();
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('home-your-moment')));
    await _settle(tester);
    expect(f.actions, ['chain:qa-own-moment']);
    expect(f.feedService.reads, reads);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('desktop real available width reflows without resubscribing', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = _Fixture();
    await f.initialize();
    addTearDown(f.dispose);
    Future<void> frame(double width, double scale) async {
      final size = Size(width, 2600);
      tester.view.physicalSize = size;
      await tester.pumpWidget(_app(f.home(desktop: true), size, scale: scale));
      await _settle(tester);
      expect(tester.takeException(), isNull);
    }

    await frame(1440, 1);
    final listens = f.listens;
    expect(find.byKey(const ValueKey('home-secondary-column')), findsOneWidget);
    await frame(768, 1);
    expect(find.byKey(const ValueKey('home-secondary-column')), findsNothing);
    expect(f.listens, listens);
    await frame(1440, 2);
    expect(find.byKey(const ValueKey('home-secondary-column')), findsOneWidget);
    expect(f.listens, listens);
    expect(find.text('Twój pokój'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [320.0, 390.0, 430.0, 768.0, 1100.0, 1440.0, 2560.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final state in ['populated', 'empty', 'error', 'loading']) {
        testWidgets('render Home $width $scale $state', (tester) async {
          final desktop = width >= 1100;
          final size = Size(width, width >= 1100 ? 1000 : 900);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final f = _Fixture();
          await f.initialize(
            populated: state != 'empty',
            loading: state == 'loading',
            longName: scale == 2,
          );
          if (state == 'error') {
            f.rooms.deny();
            f.moments.deny();
            f.chats.deny();
          }
          addTearDown(f.dispose);
          final captureKey = GlobalKey();
          for (final pearl in [false, true]) {
            await tester.pumpWidget(
              _app(
                f.home(desktop: desktop),
                size,
                scale: scale,
                pearl: pearl,
                dock: !desktop,
                captureKey: captureKey,
              ),
            );
            if (_capture) {
              await tester.runAsync(
                () => precacheImage(
                  AssetImage(YoPageSection.home.asset),
                  captureKey.currentContext!,
                ),
              );
            }
            await _settle(tester);
            final prefix =
                '${pearl ? 'pearl' : 'dark'}-${width.toInt()}-${scale.toInt()}x-$state';
            await _shoot(tester, captureKey, '$prefix-top');
            expect(tester.takeException(), isNull, reason: prefix);
            // Traverse the entire lazy page, not just the first viewport.
            final scrollable = tester.state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(ListView).first,
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            for (var i = 0; i < 8; i++) {
              final p = scrollable.position;
              if (p.pixels >= p.maxScrollExtent) break;
              p.jumpTo(
                (p.pixels + size.height * .7).clamp(0.0, p.maxScrollExtent),
              );
              await _settle(tester);
              final exception = tester.takeException();
              if (exception != null) debugPrint(exception.toString());
              expect(exception, isNull, reason: '$prefix scroll $i');
            }
            await _shoot(tester, captureKey, '$prefix-bottom');
            scrollable.position.jumpTo(0);
            await _settle(tester);
          }
          expect(
            f.actions,
            isEmpty,
            reason: 'rendering never opens a route or joins audio',
          );
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
