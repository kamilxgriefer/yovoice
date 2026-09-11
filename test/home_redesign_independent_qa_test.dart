// Independent Home QA. These are local fixtures, never production content.
// The author's source and test file are deliberately not imported or edited.
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
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';
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
import 'support/material_icons_font.dart';

const _capture = bool.fromEnvironment('QA_CAPTURE_HOME');
const _uid = 'independent-home-viewer';
const _friendId = 'independent-home-friend';
const _name = 'Alexandra Nowakowska-Kowalska';
const _roomTitle = 'Porozmawiajmy o nadchodzącym weekendzie';

/// A cold subscription with a cached initial response and observable ownership.
/// Each call to listenFresh returns a distinct stream, like a retry request.
class _Probe<T> {
  final _events = StreamController<T>.broadcast();
  T? _value;
  bool _hasValue = false;
  Object? _error;
  int listens = 0;
  int cancels = 0;

  Stream<T> listenFresh() => Stream<T>.multi((sink) {
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

  void emit(T value) {
    _hasValue = true;
    _value = value;
    _error = null;
    _events.add(value);
  }

  void fail([String code = 'permission-denied']) {
    _hasValue = false;
    _value = null;
    _error = FirebaseException(
      plugin: 'cloud_firestore',
      code: code,
      message: 'INTERNAL_SECRET_DO_NOT_RENDER',
    );
    _events.addError(_error!);
  }

  Future<void> dispose() => _events.close();
}

class _QaRooms extends RoomService {
  _QaRooms(this.f) : super(firestore: f.db, auth: f.auth);
  final _HomeFixture f;
  int reads = 0;
  @override
  Stream<List<VoiceRoom>> watchLivePublicRooms() {
    reads++;
    return f.rooms.listenFresh();
  }

  @override
  Stream<List<VoiceRoom>> watchOwnedRooms() => f.owned.listenFresh();
}

class _QaFriends extends FriendService {
  _QaFriends(this.f) : super(firestore: f.db, auth: f.auth);
  final _HomeFixture f;
  @override
  Stream<List<FriendUser>> watchFriends() => f.friends.listenFresh();
}

class _QaFollowing extends FollowService {
  _QaFollowing(this.f) : super(firestore: f.db, auth: f.auth);
  final _HomeFixture f;
  @override
  Stream<List<FollowUser>> watchFollowing(String userId) =>
      f.following.listenFresh();
}

class _QaFeed extends HomeFeedService {
  _QaFeed(this.f) : super(firestore: f.db, auth: f.auth);
  final _HomeFixture f;
  int reads = 0;
  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) {
    reads++;
    return f.feedGeneration.listenFresh();
  }
}

class _QaChats extends MessageService {
  _QaChats(this.f) : super(firestore: f.db, auth: f.auth);
  final _HomeFixture f;
  int reads = 0;
  @override
  Stream<List<Conversation>> watchConversations({
    bool includeArchived = false,
  }) {
    reads++;
    return f.chats.listenFresh();
  }
}

class _QaCapabilities extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      StaffCapabilities.none;
}

class _HomeFixture {
  final db = FakeFirebaseFirestore();
  final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _uid));
  final rooms = _Probe<List<VoiceRoom>>();
  final owned = _Probe<List<VoiceRoom>>();
  final friends = _Probe<List<FriendUser>>();
  final following = _Probe<List<FollowUser>>();
  final chats = _Probe<List<Conversation>>();
  final feedPages = <_Probe<List<VoiceMoment>>>[_Probe<List<VoiceMoment>>()];
  _Probe<List<VoiceMoment>> get feedGeneration => feedPages.last;
  final visible = ValueNotifier(true);
  late final roomService = _QaRooms(this);
  late final friendService = _QaFriends(this);
  late final followService = _QaFollowing(this);
  late final feedService = _QaFeed(this);
  late final messageService = _QaChats(this);
  late final profileService = ProfileService(firestore: db, auth: auth);
  final actions = <String>[];
  late VoiceRoom liveRoom;
  late VoiceRoom ownedRoom;
  late Conversation conversation;
  late VoiceMoment moment;

  Future<void> initialize({bool longContent = false}) async {
    await db.doc('users/$_uid').set({
      'uid': _uid,
      'displayName': longContent ? _name : 'Alexandra',
      'username': 'qa-alexandra',
      'availability': 'available',
    });
    for (final (id, hostId) in [('qa-live', _friendId), ('qa-owned', _uid)]) {
      await db.doc('rooms/$id').set({
        'name': hostId == _uid
            ? 'My retained room'
            : longContent
            ? _roomTitle
            : 'Weekend conversation',
        'hostId': hostId,
        'hostName': hostId == _uid ? 'Alexandra' : 'Michał',
        'description': 'A real fixture description, without invented activity.',
        'category': 'community',
        'visibility': 'public',
        'language': 'English',
        'participantCount': hostId == _uid ? 0 : 2,
        'memberCount': 0,
        'isLive': hostId != _uid,
        'roomType': 'community',
        'status': 'active',
        'experience': 'community',
        'createdAt': Timestamp.now(),
      });
    }
    liveRoom = VoiceRoom.fromFirestore(await db.doc('rooms/qa-live').get());
    ownedRoom = VoiceRoom.fromFirestore(await db.doc('rooms/qa-owned').get());
    await db.doc('conversations/qa-conversation').set({
      'participantIds': [_uid, _friendId],
      'participantNames': {_uid: 'Alexandra', _friendId: 'Michał'},
      'unreadCounts': {_uid: 3},
      'lastMessage': 'Independent callback sentinel',
      'lastMessageType': 'text',
      'lastMessageSenderId': _friendId,
      'updatedAt': Timestamp.now(),
      'createdAt': Timestamp.now(),
    });
    conversation = Conversation.fromFirestore(
      await db.doc('conversations/qa-conversation').get(),
    );
    moment = VoiceMoment(
      id: 'qa-followed-moment',
      authorId: _friendId,
      authorName: 'Michał',
      authorPhotoUrl: null,
      caption: 'A followed recording',
      audioUrl: null,
      durationSeconds: 17,
      likeCount: 0,
      commentCount: 0,
      isPublished: true,
      createdAt: DateTime.now(),
      schemaVersion: 2,
      status: 'published',
      hasAuthorizedMedia: true,
    );
    populate();
  }

  void populate() {
    rooms.emit([liveRoom]);
    owned.emit([ownedRoom]);
    friends.emit([
      const FriendUser(
        id: _friendId,
        displayName: 'Michał',
        email: '',
        photoUrl: null,
        isOnline: true,
        lastSeen: null,
        availability: 'available',
      ),
    ]);
    following.emit([
      const FollowUser(
        uid: _friendId,
        displayName: 'Michał',
        username: 'qa-michal',
        photoUrl: null,
        followedAt: null,
      ),
    ]);
    chats.emit([conversation]);
    feedGeneration.emit([moment]);
  }

  List<int> get subscriptions => [
    rooms.listens,
    owned.listens,
    friends.listens,
    following.listens,
    chats.listens,
    for (final page in feedPages) page.listens,
  ];

  Widget home(bool desktop) => desktop
      ? DesktopHome(
          key: const ValueKey('independent-home'),
          currentUserId: _uid,
          onOpenRoom: (room) => actions.add('room:${room.id}'),
          onSeeAllRooms: () => actions.add('discover'),
          onViewAllFriends: () => actions.add('friends'),
          onStartRoom: () => actions.add('create'),
          onOpenMoment: (item) => actions.add('moment:${item.id}'),
          onOpenChain: (items) => actions.add('chain:${items.single.id}'),
          onCreateMoment: () => actions.add('record'),
          onSeeAllMoments: () => actions.add('moments'),
          onOpenConversation: (item) => actions.add('chat:${item.id}'),
          onSeeAllChats: () => actions.add('chats'),
          onOpenClub: (_) => actions.add('club'),
          onOpenClubs: () => actions.add('clubs'),
          roomService: roomService,
          friendService: friendService,
          followService: followService,
          profileService: profileService,
          feedService: feedService,
          messageService: messageService,
          capabilityService: _QaCapabilities(),
          isVisible: visible,
        )
      : MobileHome(
          key: const ValueKey('independent-home'),
          currentUserId: _uid,
          onOpenRoom: (room) => actions.add('room:${room.id}'),
          onOpenDiscover: () => actions.add('discover'),
          onOpenFriends: () => actions.add('friends'),
          onCreateRoom: () => actions.add('create'),
          onOpenNotifications: () => actions.add('notifications'),
          onOpenProfile: () => actions.add('profile'),
          unreadNotificationCount: 103,
          onOpenMoment: (item) => actions.add('moment:${item.id}'),
          onOpenChain: (items) => actions.add('chain:${items.single.id}'),
          onCreateMoment: () => actions.add('record'),
          onSeeAllMoments: () => actions.add('moments'),
          onOpenComments: (_) => actions.add('comments'),
          onOpenConversation: (item) => actions.add('chat:${item.id}'),
          onSeeAllChats: () => actions.add('chats'),
          roomService: roomService,
          friendService: friendService,
          followService: followService,
          profileService: profileService,
          feedService: feedService,
          messageService: messageService,
          capabilityService: _QaCapabilities(),
          isVisible: visible,
        );

  Future<void> dispose() async {
    visible.dispose();
    await Future.wait([
      rooms.dispose(),
      owned.dispose(),
      friends.dispose(),
      following.dispose(),
      chats.dispose(),
      for (final page in feedPages) page.dispose(),
    ]);
  }
}

Widget _host(
  Widget child,
  Size size, {
  double scale = 1,
  bool pearl = false,
  String language = 'en',
  bool dock = false,
  GlobalKey? captureKey,
}) => RepaintBoundary(
  key: captureKey,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: pearl ? AppTheme.lightTheme : AppTheme.darkTheme,
    locale: Locale(language),
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
        padding: dock
            ? const EdgeInsets.only(top: 24, bottom: 34)
            : EdgeInsets.zero,
        disableAnimations: true,
      ),
      child: Scaffold(
        body: child,
        bottomNavigationBar: dock
            ? YoFloatingNavigationDock(
                selectedTabIndex: 0,
                momentsTabIndex: 5,
                unreadConversationCount: 3,
                onDestinationSelected: (_) {},
                onMorePressed: () {},
                onVoicePressed: () {},
              )
            : null,
      ),
    ),
  ),
);

Future<void> _pump(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _mount(
  WidgetTester tester,
  _HomeFixture f,
  bool desktop, {
  Size size = const Size(1440, 2800),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(f.dispose);
  await tester.pumpWidget(_host(f.home(desktop), size, scale: scale));
  await _pump(tester);
}

Finder _key(String key) => find.byKey(ValueKey(key));
Finder _retry(String key) =>
    find.descendant(of: _key(key), matching: find.byType(OutlinedButton));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await _pump(tester);
}

Future<void> _revealLazy(WidgetTester tester, Finder finder) async {
  // A large heading can put the entire next ListView child beyond the lazy
  // cache. Scroll the real page before asking ensureVisible for its element.
  final scrollable = tester.state<ScrollableState>(
    find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  for (var step = 0; finder.evaluate().isEmpty && step < 16; step++) {
    final position = scrollable.position;
    position.jumpTo(
      (position.pixels + position.viewportDimension / 2).clamp(
        0.0,
        position.maxScrollExtent,
      ),
    );
    await _pump(tester);
  }
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await _pump(tester);
}

Future<void> _screenshot(
  WidgetTester tester,
  GlobalKey captureKey,
  String name,
) async {
  if (!_capture) return;
  await tester.runAsync(() async {
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final frame = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
      final destination = File(
        'test/.screenshots/home-independent-qa-2026-09-11/$name.png',
      );
      destination.parent.createSync(recursive: true);
      destination.writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      frame.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))).load();
    await loadMaterialIconsFont();
  });
  setUp(ProfileService.resetCurrentProfileCache);
  tearDown(ProfileService.resetCurrentProfileCache);

  for (final desktop in [false, true]) {
    testWidgets(
      'independent Home $desktop actual route callbacks stay distinct',
      (tester) async {
        final f = _HomeFixture();
        await f.initialize();
        await _mount(tester, f, desktop);
        expect(
          f.actions,
          isEmpty,
          reason: 'Merely rendering must not join audio.',
        );
        await _tap(tester, _key('home-room-join').first);
        await _tap(tester, _key('home-quick-create-room'));
        await _tap(tester, _key('home-quick-friends'));
        await _tap(tester, _key('home-moment-qa-followed-moment'));
        await _tap(tester, _key('home-record-moment'));
        await _tap(tester, find.text('Independent callback sentinel'));
        expect(f.actions, [
          'room:qa-live',
          'create',
          'friends',
          'chain:qa-followed-moment',
          'record',
          'chat:qa-conversation',
        ]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'independent Home $desktop denied cache never returns on retry',
      (tester) async {
        final f = _HomeFixture();
        await f.initialize();
        await _mount(tester, f, desktop);
        final oldFeed = f.feedGeneration;
        final chatSubscriptions = f.chats.listens;
        oldFeed.fail();
        await _pump(tester);
        expect(_key('home-moment-qa-followed-moment'), findsNothing);
        final newFeed = _Probe<List<VoiceMoment>>();
        f.feedPages.add(newFeed);
        await _tap(tester, _retry('home-moments-error'));
        expect(f.feedService.reads, 2);
        expect(oldFeed.cancels, oldFeed.listens);
        oldFeed.emit([f.moment]); // A stale completed request is now unowned.
        await _pump(tester);
        expect(_key('home-moment-qa-followed-moment'), findsNothing);
        expect(f.chats.listens, chatSubscriptions);
        expect(find.text('My retained room'), findsOneWidget);
        newFeed.emit([]);
        await _pump(tester);
        expect(_key('home-moments-error'), findsNothing);
        expect(_key('home-record-moment'), findsOneWidget);
        expect(find.textContaining('INTERNAL_SECRET'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'independent Home $desktop room retry is scoped and retains owned',
      (tester) async {
        final f = _HomeFixture();
        await f.initialize();
        await _mount(tester, f, desktop);
        final ownedSubscriptions = f.owned.listens;
        final feedReads = f.feedService.reads;
        f.rooms.fail();
        await _pump(tester);
        expect(_key('home-conversation-invitation'), findsNothing);
        expect(_key('home-room-join'), findsNothing);
        expect(find.text('My retained room'), findsOneWidget);
        await _tap(tester, _retry('home-rooms-error'));
        expect(f.roomService.reads, 2);
        expect(f.owned.listens, ownedSubscriptions);
        expect(f.feedService.reads, feedReads);
        f.rooms.emit([]);
        await _pump(tester);
        expect(_key('home-rooms-error'), findsNothing);
        expect(_key('home-conversation-invitation'), findsOneWidget);
        expect(find.text('My retained room'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('independent Home $desktop relationship denial is not empty', (
      tester,
    ) async {
      final f = _HomeFixture();
      await f.initialize();
      await _mount(tester, f, desktop);
      f.following.fail();
      f.friends.fail();
      await _pump(tester);
      expect(_key('home-moment-qa-followed-moment'), findsNothing);
      expect(_key('home-person-$_friendId'), findsNothing);
      expect(_key('home-people-add'), findsNothing);
      expect(_key('home-people-error'), findsOneWidget);
      expect(_key('home-moments-error'), findsOneWidget);
      expect(_key('home-people-me'), findsOneWidget);
      expect(_key('home-room-join'), findsOneWidget);
      await _tap(tester, _key('home-quick-create-room'));
      expect(f.actions, ['create']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'independent Home $desktop simultaneous errors have one polite channel',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final announcements = <Map<Object?, Object?>>[];
          tester.binding.defaultBinaryMessenger
              .setMockDecodedMessageHandler<Object?>(
                SystemChannels.accessibility,
                (message) async {
                  if (message is Map && message['type'] == 'announce') {
                    announcements.add(message['data'] as Map<Object?, Object?>);
                  }
                  return null;
                },
              );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockDecodedMessageHandler<Object?>(
                  SystemChannels.accessibility,
                  null,
                ),
          );
          final f = _HomeFixture();
          await f.initialize();
          await _mount(tester, f, desktop);
          f.rooms.fail();
          f.feedGeneration.fail();
          f.chats.fail();
          await _pump(tester);
          expect(find.byType(HomeSectionError), findsNWidgets(3));
          final liveNodes = <SemanticsNode>[];
          void visit(SemanticsNode node) {
            if (node.getSemanticsData().flagsCollection.isLiveRegion) {
              liveNodes.add(node);
            }
            node.visitChildren((child) {
              visit(child);
              return true;
            });
          }

          SemanticsNode? root;
          void visitOwner(PipelineOwner owner) {
            root ??= owner.semanticsOwner?.rootSemanticsNode;
            owner.visitChildren(visitOwner);
          }

          visitOwner(tester.binding.rootPipelineOwner);
          expect(root, isNotNull);
          visit(root!);
          expect(
            liveNodes,
            hasLength(lessThanOrEqualTo(1)),
            reason:
                'UI.md / ADR-058: section errors must not compete in the shared '
                'polite announcement channel. Errors use the assertive path.',
          );
          expect(
            announcements.where(
              (event) =>
                  event['assertiveness'] == Assertiveness.assertive.index,
            ),
            isNotEmpty,
            reason:
                'Removing all live regions must not silently remove error '
                'announcements; the error channel is assertive.',
          );
          await tester.pumpWidget(const SizedBox());
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'independent narrow large-text header keeps profile and unread action',
    (tester) async {
      final f = _HomeFixture();
      await f.initialize(longContent: true);
      await _mount(tester, f, false, size: const Size(320, 900), scale: 2);
      expect(find.text(_name), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
      await _tap(tester, find.byTooltip('Notifications, 103 unread'));
      await _tap(tester, find.byTooltip('Profile'));
      expect(f.actions, ['notifications', 'profile']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final width in [320.0, 390.0, 430.0, 768.0, 1100.0, 1440.0, 2560.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('independent real render long English Home $width at $scale', (
        tester,
      ) async {
        final desktop = width >= 1100;
        final size = Size(width, desktop ? 1000 : 900);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final f = _HomeFixture();
        await f.initialize(longContent: true);
        addTearDown(f.dispose);
        final captureKey = GlobalKey();
        for (final pearl in [false, true]) {
          await tester.pumpWidget(
            _host(
              f.home(desktop),
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
          await _pump(tester);
          final prefix =
              '${pearl ? 'pearl' : 'dark'}-${width.toInt()}-${scale.toInt()}x-en';
          await _screenshot(tester, captureKey, '$prefix-top');
          await _revealLazy(tester, _key('home-featured-room'));
          await _screenshot(tester, captureKey, '$prefix-featured');
          await _revealLazy(tester, _key('home-room-join'));
          await _screenshot(tester, captureKey, '$prefix-join');
          final joinBounds = tester.getRect(_key('home-room-join').first);
          final bodyBounds = tester.getRect(
            find.byType(desktop ? DesktopHome : MobileHome),
          );
          expect(joinBounds.height, greaterThanOrEqualTo(44));
          expect(joinBounds.left, greaterThanOrEqualTo(bodyBounds.left));
          expect(joinBounds.right, lessThanOrEqualTo(bodyBounds.right));
          expect(joinBounds.bottom, lessThanOrEqualTo(bodyBounds.bottom));
          expect(tester.takeException(), isNull, reason: prefix);
          await _revealLazy(tester, _key('home-quick-create-room'));
          await _screenshot(tester, captureKey, '$prefix-create');
          final button = _key('home-quick-create-room');
          final focus = Focus.of(
            tester.element(
              find.descendant(of: button, matching: find.byType(Text)).first,
            ),
          );
          focus.requestFocus();
          await tester.pumpAndSettle();
          await _screenshot(tester, captureKey, '$prefix-focused');
          expect(focus.hasFocus, isTrue);
          focus.unfocus();
          final position = tester
              .state<ScrollableState>(
                find
                    .descendant(
                      of: find.byType(ListView).first,
                      matching: find.byType(Scrollable),
                    )
                    .first,
              )
              .position;
          position.jumpTo(0);
          await _pump(tester);
        }
        expect(f.actions, isEmpty);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
