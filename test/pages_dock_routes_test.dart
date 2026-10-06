// Every Pages route opened from Treści on a 390x844 phone, measured against
// the real floating dock (owner report 2026-09-29, "czat nie chowa się", and
// the Pages route audit of the same day).
//
// MainShell itself cannot be pumped (desktop_shell_test.dart: it reads
// Firebase singletons directly), so MoreDestinationHost stands in for it: it
// is the production wrapper that mounts the same RoomMiniBar +
// YoFloatingNavigationDock column in `Scaffold.bottomNavigationBar` as the
// shell's phone layout, and the real ContentScreen puts Treści's own
// Navigator in the body above it, exactly as in the app.
//
// Two rules, one per kind of route:
//   * Treści's own screens (Find Pages, a Page profile, Page settings) keep
//     the dock by design (spec premium-pages §4.3) and end at its top edge,
//     so nothing of theirs is under it.
//   * Everything modal or full screen opened from them sits on the ROOT
//     navigator: a sheet reaches the bottom of the window and its barrier
//     covers the dock; a screen (a chat, a call) puts the dock offstage.
//     Before the fix the report, likers, invite and profile sheets stopped
//     at the dock's top edge with the dock still tappable under the modal,
//     and the chat and the call opened inside Treści, under the dock.
// Back always lands on Treści with the dock visible and Treści selected.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/core/audio/call_tone_service.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/calls/data/models/direct_call.dart';
import 'package:yovoice/features/calls/data/models/voice_connection_info.dart';
import 'package:yovoice/features/calls/data/services/direct_call_service.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/calls/presentation/direct_call_launcher.dart';
import 'package:yovoice/features/calls/presentation/screens/direct_call_screen.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';
import 'package:yovoice/features/likers/data/models/likers_target.dart';
import 'package:yovoice/features/messages/data/services/message_outbox.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/services/page_access_service.dart';
import 'package:yovoice/features/pages/data/services/pages_local_store.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/page_account_actions.dart';
import 'package:yovoice/features/pages/presentation/page_navigation.dart';
import 'package:yovoice/features/pages/presentation/pages_flows.dart';
import 'package:yovoice/features/pages/presentation/screens/content_screen.dart';
import 'package:yovoice/features/pages/presentation/screens/find_pages_screen.dart';
import 'package:yovoice/features/pages/presentation/screens/page_composer.dart';
import 'package:yovoice/features/pages/presentation/screens/page_edit_screen.dart';
import 'package:yovoice/features/pages/presentation/screens/page_profile_screen.dart';
import 'package:yovoice/features/pages/presentation/screens/page_settings_screen.dart';
import 'package:yovoice/features/permissions/data/permission_readiness_service.dart';
import 'package:yovoice/features/profile/data/models/profile_visibility.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/servers/presentation/widgets/invite_person_to_server_sheet.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';

import 'support/likers_fixtures.dart';

// ---------------------------------------------------------------- fixtures

final DateTime _now = DateTime.utc(2026, 9, 29, 12);
const Size _phone = Size(390, 844);

String _postId(int n) => 'pp_${n.toRadixString(16).padLeft(40, '0')}';

Map<String, Object?> _post(int n) => {
  'postId': _postId(n),
  'pageId': 'cafe',
  'pageName': 'Kawiarnia Ziarno',
  'pageKind': 'business',
  'kind': 'text',
  'text': 'Od 1 października otwieramy o 7:00.',
  'media': const <Object?>[],
  'createdAtMs': _now.subtract(Duration(hours: n)).millisecondsSinceEpoch,
  'likeCount': 48,
  'commentCount': 12,
  'callerLiked': false,
  'commentsEnabled': true,
  'state': 'published',
  'pinned': false,
};

Map<String, Object?> _card(String id, String name) => {
  'pageId': id,
  'displayName': name,
  'kind': 'community',
  'category': 'music',
  'followerCount': 210,
  'onYoVoiceSinceMs': _now.millisecondsSinceEpoch,
  'viewerFollows': false,
  'lastPostAtMs': null,
};

Map<String, Object?> _pageResponse({required bool owner}) => {
  'schemaVersion': 1,
  'page': {
    'pageId': 'cafe',
    'displayName': 'Kawiarnia Ziarno',
    'kind': 'business',
    'category': 'cafe_restaurant',
    'description': 'Kawa speciality i domowe wypieki. Grunwaldzka 57.',
    'followerCount': 1200,
    'postCount': 2,
    'onYoVoiceSinceMs': DateTime.utc(2025, 3, 10).millisecondsSinceEpoch,
    'about': {
      'business': {
        'website': 'https://kawiarniaziarno.pl',
        'email': 'czesc@kawiarniaziarno.pl',
        'phone': '+48585550127',
        'address': 'ul. Grunwaldzka 57, Gdańsk',
        'hours': 'Pn–Pt 7:00–19:00',
        'legalNotice': null,
      },
      'community': null,
    },
    'state': 'active',
  },
  'viewer': {
    'isOwner': owner,
    'following': false,
    'canFollow': !owner,
    'canMessage': !owner,
  },
  'pinned': null,
  'posts': [_post(2), _post(3)],
  'nextCursor': null,
  'hasMore': false,
};

FirebaseFunctionsException _refusal(String code, String reason) =>
    FirebaseFunctionsException(
      code: code,
      message: 'refused',
      details: {'reason': reason},
    );

/// Answers every Pages callable the routes below touch, and records them.
class _Backend {
  _Backend({this.pageAvailable = true, this.owner = false});

  final bool pageAvailable;
  final bool owner;
  final List<(String, Map<String, Object?>)> calls = [];

  Future<Object?> call(String name, Map<String, Object?> payload) async {
    calls.add((name, payload));
    switch (name) {
      case PagesService.feedCallable:
        return {
          'schemaVersion': 1,
          'posts': [_post(1)],
          'nextCursor': null,
          'hasMore': false,
          'suggestions': [_card('chor', 'Chór Gaudium')],
        };
      case PagesService.findCallable:
        return {
          'schemaVersion': 1,
          'pages': [_card('chor', 'Chór Gaudium')],
          'nextCursor': null,
          'hasMore': false,
        };
      case PagesService.pageCallable:
        if (!pageAvailable) {
          throw _refusal('permission-denied', 'pageUnavailable');
        }
        return _pageResponse(owner: owner);
      case PagesService.reportCallable:
        return {'ok': true};
      case PagesService.mediaAccessCallable:
        return {'grants': const <Object>[]};
    }
    throw FirebaseFunctionsException(code: 'not-found', message: name);
  }

  List<Map<String, Object?>> payloadsOf(String name) => [
    for (final call in calls)
      if (call.$1 == name) call.$2,
  ];
}

PagesService _service(_Backend backend) => PagesService(
  invoker: backend.call,
  requestIdFactory: () => 'pg_test_request_0001',
  clock: () => _now,
);

OwnPage _ownPage() => const OwnPage(
  kind: PageKind.business,
  status: 'active',
  ownerPaused: false,
  suspended: false,
  category: 'cafe_restaurant',
  description: 'Kawa speciality.',
  business: PageBusinessInfo(
    website: 'https://kawiarniaziarno.pl',
    phone: '+48585550127',
  ),
  rules: null,
  displayName: 'Kawiarnia Ziarno',
  lapsedAt: null,
  suspensionReason: null,
);

UserProfile _profile() => UserProfile(
  uid: 'cafe',
  email: 'me@example.com',
  displayName: 'Kawiarnia Ziarno',
  username: 'ziarno',
  bio: '',
  country: 'PL',
  nativeLanguage: 'pl',
  spokenLanguages: const [],
  learningLanguages: const [],
  photoUrl: null,
  bannerUrl: null,
  creatorAgeVerified: true,
  website: '',
  accountType: AccountType.personal,
  friendCount: 0,
  followerCount: 1200,
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
  createdAt: null,
  profileVisibility: ProfileVisibility.public,
);

/// The account behind the Page, for "Edytuj stronę".
class _EditAccount implements PageEditAccount {
  @override
  Stream<UserProfile> watchProfile() => Stream.value(_profile());

  @override
  Future<DisplayNameChangeResult> rename(String displayName) async =>
      throw StateError('not expected');

  @override
  Future<void> uploadImage(PickedProfileImage image) async {}

  @override
  Future<PickedProfileImage?> pickImage(
    BuildContext context,
    ProfileImageKind kind,
  ) async => null;
}

/// The chat's message service without the conversation callable: the
/// conversation id is known up front (profile_preview_sheet_test pattern).
class _Messages extends MessageService {
  _Messages({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    required MessageOutbox outbox,
  }) : super(firestore: firestore, auth: auth, outbox: outbox);

  int opened = 0;

  @override
  Future<String> openOrCreateConversation({
    required String otherUserId,
    required String otherDisplayName,
    required String otherEmail,
    required String otherPhotoUrl,
  }) async {
    opened++;
    return 'cafe_me';
  }
}

/// One of the viewer's servers where they may invite (the owner).
class _Servers implements ServerRepository {
  @override
  Stream<List<Server>> watchMyServers() => Stream.value(const [
    Server(
      id: 'srv1',
      name: 'Biegacze Mokotowa',
      description: '',
      ownerId: 'me',
      type: ServerType.friends,
      privacy: ServerPrivacy.private,
      schemaVersion: 1,
      activationState: 'active',
    ),
  ]);

  @override
  Stream<ServerMemberRole?> watchMyRole(String serverId) =>
      Stream.value(ServerMemberRole.owner);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DirectCall _call(DirectCallStatus status) => DirectCall(
  id: 'call-1',
  callerId: 'me',
  calleeId: 'cafe',
  caller: const DirectCallIdentity(
    userId: 'me',
    displayName: 'Ola',
    photoUrl: null,
  ),
  callee: const DirectCallIdentity(
    userId: 'cafe',
    displayName: 'Kawiarnia Ziarno',
    photoUrl: null,
  ),
  status: status,
  createdAt: _now,
  expiresAt: _now.add(const Duration(minutes: 1)),
  answeredAt: null,
  conversationId: 'cafe_me',
);

/// A ringing outgoing call that ends when the caller cancels it.
class _Calls implements DirectCallGateway {
  final StreamController<DirectCall> _changes =
      StreamController<DirectCall>.broadcast();
  DirectCall _current = _call(DirectCallStatus.ringing);
  int started = 0;
  int cancelled = 0;

  @override
  Stream<DirectCall> watchCall(String callId) async* {
    yield _current;
    yield* _changes.stream;
  }

  @override
  Future<DirectCall?> getCall(String callId) async => _current;

  @override
  Stream<List<IncomingDirectCallSignal>> watchIncomingCalls() =>
      const Stream.empty();

  @override
  Future<String> startCall({
    required String calleeId,
    required String conversationId,
    DirectCallMediaType mediaType = DirectCallMediaType.audio,
  }) async {
    started++;
    return 'call-1';
  }

  @override
  Future<DirectCallStatus> accept(
    String callId, {
    DirectCallMediaType mediaType = DirectCallMediaType.audio,
    void Function(DirectCallStatus status)? onLateValidatedResult,
  }) async => DirectCallStatus.active;

  @override
  Future<void> decline(String callId) async {}

  @override
  Future<void> cancel(String callId) async {
    cancelled++;
    _current = _call(DirectCallStatus.cancelled);
    _changes.add(_current);
  }

  @override
  Future<void> end(String callId) async {}

  @override
  Future<VoiceConnectionInfo> createJoinToken(String callId) =>
      throw StateError('a ringing call never joins');
}

/// The launcher's voice gate: no live session, microphone granted.
class _Voice extends VoiceCallService {
  _Voice() : super.forTesting();

  @override
  Future<PermissionReadinessSnapshot> prepareMediaPermissionsFromUserGesture({
    bool includeCamera = false,
  }) async =>
      PermissionReadinessSnapshot(<AppPermissionKind, AppPermissionAccess>{
        AppPermissionKind.microphone: AppPermissionAccess.granted,
      });
}

/// The Page profile's account actions, each through the production path
/// the fix lives in: `AppPageAccountActions.openChat`, the shared direct
/// call launcher, the invite sheet and the profile preview, with fakes
/// behind them instead of Firebase.
class _ShellActions implements PageAccountActions {
  _ShellActions({
    required this.firestore,
    required this.auth,
    required this.messages,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final _Messages messages;
  final _Calls calls = _Calls();
  final _Voice voice = _Voice();

  @override
  Future<FriendRelationshipStatus?> relationship(String uid) async =>
      FriendRelationshipStatus.friends;

  @override
  Future<void> openChat(
    BuildContext context, {
    required String uid,
    required String name,
    bool recordVoice = false,
  }) => AppPageAccountActions(
    messageService: messages,
    firestore: firestore,
    auth: auth,
  ).openChat(context, uid: uid, name: name, recordVoice: recordVoice);

  @override
  Future<void> call(
    BuildContext context, {
    required String uid,
    required String name,
  }) => launchDirectCall(
    context,
    calls: calls,
    voice: voice,
    calleeId: uid,
    resolveConversationId: () => 'cafe_me',
    currentUserId: 'me',
    participantName: () => 'Ola',
    showMessage: (_) {},
    onBusyChanged: (_) {},
    onStartAudioInstead: () {},
  );

  @override
  Future<void> inviteToServer(
    BuildContext context, {
    required String uid,
    required String name,
  }) => showInvitePersonToServerSheet(
    context,
    inviteeId: uid,
    inviteeName: name,
    repository: _Servers(),
  );

  @override
  Future<void> removeFriend(String uid) async {}

  @override
  Future<void> block(String uid) async {}

  @override
  Future<void> openPersonalProfile(
    BuildContext context, {
    required String uid,
    String? name,
  }) => showProfilePreview(
    context,
    userId: uid,
    displayName: name,
    firestore: firestore,
    auth: auth,
    messageService: messages,
    resolvePages: false,
  );
}

// ------------------------------------------------------------------ harness

class _Tresci {
  _Tresci(this.backend, this.actions);

  final _Backend backend;
  final _ShellActions actions;
  final List<String> openedPages = [];
}

Finder _key(String key) => find.byKey(ValueKey(key));

Finder get _dock => find.byType(YoFloatingNavigationDock);

/// The dock's Czaty cell: a real button, so a hit test at its centre tells
/// whether the dock can still be reached.
Finder get _chatsCell => _key('yo-destination-2');

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<_Tresci> _pumpTresci(
  WidgetTester tester, {
  _Backend? backend,
  bool owner = false,
  bool? likersAllowed,
}) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final firestore = FakeFirebaseFirestore();
  final auth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'me', email: 'me@yovoice.app', displayName: 'Ola'),
  );
  await firestore.collection('users').doc('me').set({
    'uid': 'me',
    'displayName': 'Ola',
  });
  await firestore.collection('publicProfiles').doc('cafe').set({
    'uid': 'cafe',
    'displayName': 'Kawiarnia Ziarno',
    'username': 'ziarno',
    'email': 'cafe@yovoice.app',
    'accountType': 'user',
  });
  await firestore.collection('conversations').doc('cafe_me').set({
    'participantIds': ['cafe', 'me'],
    'unreadCounts': {'me': 0, 'cafe': 0},
    'typing': <String, Object?>{},
  });
  final messages = _Messages(
    firestore: firestore,
    auth: auth,
    outbox: MessageOutbox(preferences: preferences, storageKey: null),
  );
  addTearDown(messages.dispose);

  final pages = backend ?? _Backend(owner: owner);
  final service = _service(pages);
  final actions = _ShellActions(
    firestore: firestore,
    auth: auth,
    messages: messages,
  );
  final tresci = _Tresci(pages, actions);
  final access = owner
      ? PageAccessState(resolved: true, hasVipGrant: true, ownPage: _ownPage())
      : const PageAccessState(
          resolved: true,
          hasVipGrant: false,
          hasPaidPremium: true,
          ownPage: null,
        );
  Stream<PageAccessState> accessStream() => Stream.value(access);
  final likers = likersAllowed == null
      ? null
      : testLikersLauncher(
          allowed: likersAllowed,
          script: ScriptedLikers([
            pageWire([likerWire('ola', 'Ola Nowak'), likerWire('jan', 'Jan')]),
          ]),
        );

  PageProfileScreen profile(String pageId, String? name) => PageProfileScreen(
    pageId: pageId,
    displayName: name,
    service: service,
    actions: actions,
    userId: owner ? 'cafe' : 'me',
    clock: () => _now,
    accessStream: accessStream,
    shareLink: (_) async {},
    flows: PagesFlows(
      openPage: (context, {required pageId, displayName}) async {},
      openComposer:
          (context, {required owner, initialKind = PagePostKind.text}) =>
              showPageComposer(
                context,
                owner: owner,
                initialKind: initialKind,
                service: service,
                clock: () => _now,
              ),
    ),
    settingsBuilder: (_) => PageSettingsScreen(
      service: service,
      accessStream: accessStream,
      profileStream: () => Stream.value(_profile()),
      userId: 'cafe',
      clock: () => _now,
    ),
    editBuilder: (_) => PageEditScreen(
      service: service,
      account: _EditAccount(),
      accessStream: accessStream,
      serverStream: () => Stream.value(const []),
      userId: 'cafe',
      clock: () => _now,
    ),
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      locale: const Locale('pl'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MoreDestinationHost(
        body: ContentScreen(
          isRootTab: true,
          service: service,
          accessStream: accessStream,
          localStore: MemoryPagesLocalStore(),
          userId: owner ? 'cafe' : 'me',
          userDisplayName: 'Ola',
          clock: () => _now,
          shareLink: (_) async {},
          flows: PagesFlows(
            // What `openPageProfile` does under Treści's navigator, with the
            // screen's test seams instead of the shared services.
            openPage: (context, {required pageId, displayName}) {
              expect(PagesNavigatorScope.maybeOf(context), isNotNull);
              tresci.openedPages.add(pageId);
              return Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  settings: RouteSettings(name: 'pages/page/$pageId'),
                  builder: (_) => profile(pageId, displayName),
                ),
              );
            },
            openLikers: likers == null
                ? null
                : (context, post) => likers.open(
                    context,
                    PagePostLikersTarget(post.postId),
                    totalCount: post.likeCount,
                  ),
          ),
        ),
        selectedIndex: MainShell.contentSlot,
        unreadConversationCount: 0,
        onDestinationSelected: (_) {},
        onVoicePressed: () {},
        onMorePressed: () {},
        contentEnabled: true,
      ),
    ),
  );
  await _settle(tester);
  return tresci;
}

// --------------------------------------------------------------- assertions

/// Treści with the dock on screen, reachable, at the bottom of the window,
/// and Treści selected.
void _expectTresciWithDock(WidgetTester tester) {
  expect(_dock, findsOneWidget);
  expect(tester.getRect(_dock).bottom, moreOrLessEquals(_phone.height));
  expect(_chatsCell.hitTestable(), findsOneWidget);
  final content = tester.widget<Semantics>(
    find
        .ancestor(
          of: _key('yo-destination-3'),
          matching: find.byType(Semantics),
        )
        .first,
  );
  expect(content.properties.selected, isTrue, reason: 'Treści is selected');
}

/// [target] is fully on screen, above the dock's top edge, and takes taps.
void _expectAboveDock(WidgetTester tester, Finder target) {
  expect(target, findsOneWidget);
  final rect = tester.getRect(target);
  final dockTop = tester.getRect(_dock).top;
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(
    rect.bottom,
    lessThanOrEqualTo(dockTop + .5),
    reason: 'nothing of a Treści screen is under the dock',
  );
  expect(target.hitTestable(), findsOneWidget);
}

/// A sheet opened from Treści: on the root navigator, down to the bottom of
/// the window, over the dock (which no longer takes taps), and its
/// [action] is fully visible and takes taps.
void _expectRootSheet(WidgetTester tester, Finder surface, Finder action) {
  expect(surface, findsOneWidget);
  expect(
    tester.getRect(surface).bottom,
    moreOrLessEquals(_phone.height, epsilon: .5),
    reason: 'the sheet reaches the bottom of the window, over the dock',
  );
  expect(
    _chatsCell.hitTestable(),
    findsNothing,
    reason: 'the dock cannot be reached under the sheet',
  );
  expect(
    find.ancestor(of: surface, matching: find.byType(Navigator)),
    findsOneWidget,
    reason: 'only the root navigator is above the sheet, not Treści\'s',
  );
  final rect = tester.getRect(action);
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(_phone.height));
  expect(action.hitTestable(), findsOneWidget);
}

/// A screen opened from Treści: full screen over the shell, the dock
/// offstage.
void _expectOverShell(WidgetTester tester, Finder screen) {
  expect(screen, findsOneWidget);
  expect(_dock, findsNothing, reason: 'the dock is offstage under it');
  expect(tester.getRect(screen), Offset.zero & _phone);
  expect(
    find.ancestor(of: screen, matching: find.byType(Navigator)),
    findsOneWidget,
    reason: 'pushed on the root navigator, not inside Treści',
  );
}

Future<void> _openCafe(WidgetTester tester) async {
  await tester.tap(
    find.textContaining('Kawiarnia Ziarno', findRichText: true).first,
  );
  await _settle(tester);
  expect(find.byType(PageProfileScreen), findsOneWidget);
}

Future<void> _openPageMenu(WidgetTester tester) async {
  await tester.tap(_key('page-more').first);
  await _settle(tester);
}

/// Taps [back] once it is scrolled back on screen.
Future<void> _tapBack(WidgetTester tester, Finder back) async {
  await tester.ensureVisible(back);
  await tester.pump();
  await tester.tap(back);
}

Future<void> _backToWall(WidgetTester tester) async {
  await _tapBack(tester, _key('page-back'));
  await _settle(tester);
  expect(find.byType(PageProfileScreen), findsNothing);
  expect(_key('content-feed'), findsOneWidget);
  _expectTresciWithDock(tester);
}

void main() {
  setUp(() {
    debugCallToneServiceOverride = CallToneService(enabled: () => false);
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
      fetchOverride: (uids) async => {
        for (final uid in uids)
          uid: {'staffRole': 'user', 'isVip': true, 'page': null},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() => debugCallToneServiceOverride = null);

  group('Treści screens keep the dock and end above it (§4.3)', () {
    testWidgets('Find Pages', (tester) async {
      await _pumpTresci(tester);
      _expectTresciWithDock(tester);

      await tester.tap(_key('content-search'));
      await _settle(tester);
      _expectAboveDock(tester, find.byType(FindPagesScreen));
      _expectAboveDock(tester, _key('find-pages-field'));
      _expectTresciWithDock(tester);

      await tester.tap(find.byTooltip('Wstecz'));
      await _settle(tester);
      expect(find.byType(FindPagesScreen), findsNothing);
      _expectTresciWithDock(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a Page profile: header actions reachable, Back to the wall', (
      tester,
    ) async {
      final tresci = await _pumpTresci(tester);
      await _openCafe(tester);
      expect(tresci.openedPages, ['cafe']);
      _expectAboveDock(tester, find.byType(PageProfileScreen));
      _expectAboveDock(tester, _key('page-follow'));
      _expectAboveDock(tester, _key('page-message'));
      _expectTresciWithDock(tester);
      await _backToWall(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Page settings: its last action scrolls above the dock; the '
        'edit form and the composer cover the dock', (tester) async {
      await _pumpTresci(tester, owner: true);
      await _openCafe(tester);

      // The owner's composer (root sheet): Opublikuj on screen.
      await tester.tap(_key('page-new-post'));
      await _settle(tester);
      _expectRootSheet(
        tester,
        _key('page-composer'),
        _key('page-composer-publish'),
      );
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(_key('page-composer'), findsNothing);
      _expectTresciWithDock(tester);

      // "Edytuj stronę" (pageEdit A): the one form, pushed over the shell
      // like create A, so its pinned "Zapisz zmiany" owns the bottom edge.
      await tester.tap(_key('page-edit'));
      await _settle(tester);
      _expectOverShell(tester, find.byType(PageEditScreen));
      await tester.enterText(_key('page-edit-description'), 'Nowy opis.');
      await _settle(tester);
      expect(_key('page-edit-save').hitTestable(), findsOneWidget);
      expect(
        tester.getRect(_key('page-edit-save-bar')).bottom,
        moreOrLessEquals(_phone.height, epsilon: .5),
      );
      // Back with unsaved edits asks first; discarding returns to the Page.
      await tester.tap(_key('page-edit-back'));
      await _settle(tester);
      expect(find.text('Odrzucić zmiany?'), findsOneWidget);
      await tester.tap(_key('page-confirm-action'));
      await _settle(tester);
      expect(find.byType(PageEditScreen), findsNothing);
      _expectTresciWithDock(tester);

      // Page settings stay one tap away in the ⋯ menu, on Treści's own
      // navigator (the dock stays).
      await _openPageMenu(tester);
      await tester.tap(find.text('Ustawienia strony'));
      await _settle(tester);
      expect(find.byType(PageSettingsScreen), findsOneWidget);
      _expectAboveDock(tester, find.byType(PageSettingsScreen));
      _expectTresciWithDock(tester);
      expect(_key('settings-edit'), findsOneWidget);

      // The list's last action, scrolled to: above the dock, tappable.
      await tester.scrollUntilVisible(
        _key('settings-pause'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(PageSettingsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump();
      _expectAboveDock(tester, _key('settings-pause'));

      await _tapBack(tester, _key('page-settings-back'));
      await _settle(tester);
      expect(find.byType(PageSettingsScreen), findsNothing);
      await _backToWall(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('sheets opened from Treści cover the dock', () {
    testWidgets('wall post ⋯ → Zgłoś: the report sheet', (tester) async {
      final tresci = await _pumpTresci(tester);
      await tester.tap(find.byTooltip('Więcej opcji').first);
      await _settle(tester);
      await tester.tap(_key('page-post-report'));
      await _settle(tester);
      _expectRootSheet(
        tester,
        _key('report-reason-sheet'),
        _key('report-reason-spam'),
      );

      await tester.tap(_key('report-reason-spam'));
      await _settle(tester);
      expect(_key('report-reason-sheet'), findsNothing);
      expect(
        tresci.backend.payloadsOf(PagesService.reportCallable).single,
        containsPair('reason', 'spam'),
      );
      _expectTresciWithDock(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Page ⋯ → Zgłoś stronę, and a wall post ⋯ → Zgłoś on the '
        'profile: the report sheet', (tester) async {
      final tresci = await _pumpTresci(tester);
      await _openCafe(tester);

      await _openPageMenu(tester);
      // The Page menu itself was already on the root navigator.
      _expectRootSheet(
        tester,
        find.byType(BottomSheet),
        _key('page-menu-report'),
      );
      await tester.tap(_key('page-menu-report'));
      await _settle(tester);
      _expectRootSheet(
        tester,
        _key('report-reason-sheet'),
        _key('report-reason-spam'),
      );
      await tester.tap(_key('report-reason-spam'));
      await _settle(tester);
      expect(
        tresci.backend.payloadsOf(PagesService.reportCallable).single,
        containsPair('targetType', 'page'),
      );

      final postMenu = find.descendant(
        of: _key('page-wall-post-${_postId(2)}'),
        matching: find.byTooltip('Więcej opcji'),
      );
      await tester.scrollUntilVisible(
        postMenu,
        200,
        scrollable: find
            .descendant(
              of: _key('page-profile-scroll'),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump();
      _expectAboveDock(tester, postMenu);
      await tester.tap(postMenu);
      await _settle(tester);
      await tester.tap(_key('page-post-report'));
      await _settle(tester);
      _expectRootSheet(
        tester,
        _key('report-reason-sheet'),
        _key('report-reason-spam'),
      );
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(_key('report-reason-sheet'), findsNothing);
      _expectTresciWithDock(tester);
      await _backToWall(tester);
      expect(tester.takeException(), isNull);
    });

    for (final allowed in [true, false]) {
      testWidgets('"N polubień": the likers ${allowed ? 'list' : 'upsell'}', (
        tester,
      ) async {
        await _pumpTresci(tester, likersAllowed: allowed);
        await tester.tap(_key('page-post-likers').first);
        await _settle(tester);
        final surface = allowed ? kLikersListSurface : kLikersUpsellSurface;
        expect(_key(surface.value), findsOneWidget);
        // The sheet's own close control is its always-visible action.
        final close = find.descendant(
          of: find.byType(BottomSheet),
          matching: _key('modal-sheet-close'),
        );
        _expectRootSheet(tester, find.byType(BottomSheet), close);
        await tester.tap(close);
        await _settle(tester);
        expect(_key(surface.value), findsNothing);
        _expectTresciWithDock(tester);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Page ⋯ → Zaproś na serwer: the invite sheet', (tester) async {
      await _pumpTresci(tester);
      await _openCafe(tester);
      await _openPageMenu(tester);
      await tester.tap(find.text('Zaproś na serwer'));
      await _settle(tester);
      _expectRootSheet(
        tester,
        find.byType(InvitePersonToServerSheet),
        find.text('Biegacze Mokotowa'),
      );
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(find.byType(InvitePersonToServerSheet), findsNothing);
      _expectTresciWithDock(tester);
      await _backToWall(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unavailable Page → Profil osobisty: the profile preview, '
        'and its Wiadomość opens the chat over the shell', (tester) async {
      final tresci = await _pumpTresci(
        tester,
        backend: _Backend(pageAvailable: false),
      );
      await tester.tap(
        find.textContaining('Kawiarnia Ziarno', findRichText: true).first,
      );
      await _settle(tester);
      // The profile removed itself and fell back to the personal preview.
      expect(find.byType(PageProfileScreen), findsNothing);
      final message = find.widgetWithText(FilledButton, 'Wiadomość');
      _expectRootSheet(tester, find.byType(ProfilePreviewSheet), message);

      await tester.tap(message);
      await _settle(tester);
      expect(find.byType(ProfilePreviewSheet), findsNothing);
      _expectOverShell(tester, find.byType(ChatScreen));
      expect(
        tresci.actions.messages.opened,
        1,
        reason: 'the preview opened the conversation',
      );

      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(find.byType(ChatScreen), findsNothing);
      expect(_key('content-feed'), findsOneWidget);
      _expectTresciWithDock(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('screens opened from a Page cover the shell', () {
    testWidgets('Wiadomość: the chat, not inside Treści', (tester) async {
      final tresci = await _pumpTresci(tester);
      await _openCafe(tester);
      await tester.tap(_key('page-message'));
      await _settle(tester);
      expect(tresci.actions.messages.opened, 1);
      _expectOverShell(tester, find.byType(ChatScreen));
      final chat = tester.widget<ChatScreen>(find.byType(ChatScreen));
      expect(chat.conversationId, 'cafe_me');
      // The composer, the chat's bottom action, is on screen and live.
      final composer = find.descendant(
        of: find.byType(ChatScreen),
        matching: find.byType(TextField),
      );
      expect(composer.hitTestable(), findsOneWidget);
      expect(tester.getRect(composer).bottom, lessThanOrEqualTo(_phone.height));

      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(find.byType(ChatScreen), findsNothing);
      expect(find.byType(PageProfileScreen), findsOneWidget);
      _expectTresciWithDock(tester);
      await _backToWall(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Page ⋯ → Zadzwoń: the call, not inside Treści', (
      tester,
    ) async {
      final tresci = await _pumpTresci(tester);
      await _openCafe(tester);
      await _openPageMenu(tester);
      await tester.tap(find.text('Zadzwoń'));
      await _settle(tester);
      expect(tresci.actions.calls.started, 1);
      _expectOverShell(tester, find.byType(DirectCallScreen));
      final cancel = find.byTooltip('Anuluj');
      expect(cancel.hitTestable(), findsOneWidget);

      await tester.tap(cancel);
      await _settle(tester);
      expect(tresci.actions.calls.cancelled, 1);
      expect(find.byType(DirectCallScreen), findsNothing);
      expect(find.byType(PageProfileScreen), findsOneWidget);
      _expectTresciWithDock(tester);
      await _backToWall(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
