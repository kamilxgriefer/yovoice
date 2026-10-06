// Page deletion on the client (ADR-236; owner's choice pageDeleteWhat B +
// pageDeleteHow B): the wire parser, the service and its refusals, the
// shared deletion state, the danger zone of Page settings, "Usuń wszystkie
// posty", the "Usuń stronę" screen, the pending and purging states in
// settings and on the owner's Page, the clearing wall and the create entry
// during the 7-day pause.
import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/pages/data/models/page_deletion_state.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/services/page_access_service.dart';
import 'package:yovoice/features/pages/data/services/page_deletion_center.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/page_account_actions.dart';
import 'package:yovoice/features/pages/presentation/page_delete_copy.dart';
import 'package:yovoice/features/pages/presentation/page_profile_copy.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';
import 'package:yovoice/features/pages/presentation/pages_flows.dart';
import 'package:yovoice/features/pages/presentation/screens/create_page_screen.dart';
import 'package:yovoice/features/pages/presentation/screens/page_composer.dart';
import 'package:yovoice/features/pages/presentation/screens/page_delete_screen.dart';
import 'package:yovoice/features/pages/presentation/screens/page_profile_screen.dart';
import 'package:yovoice/features/pages/presentation/screens/page_settings_screen.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_profile_parts.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/profile/data/models/profile_visibility.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

final DateTime _now = DateTime(2026, 10, 2, 12);
final DateTime _deleteAt = _now.add(const Duration(days: 30));
const _name = 'Pracownia Glina';

Map<String, Object?> _state({
  String? deletion,
  bool clearing = false,
  bool pageExists = true,
  DateTime? recreateAt,
}) => {
  'schemaVersion': 1,
  'pageId': 'me',
  'pageExists': pageExists,
  'deletion': deletion == null
      ? null
      : {
          'state': deletion,
          'requestedAtMs': _now.millisecondsSinceEpoch,
          'deleteAtMs': _deleteAt.millisecondsSinceEpoch,
        },
  'postsClearing': clearing
      ? {'requestedAtMs': _now.millisecondsSinceEpoch}
      : null,
  'recreateAllowedAtMs': recreateAt?.millisecondsSinceEpoch,
};

FirebaseFunctionsException _refusal(
  String code, [
  String? reason,
  Map<String, Object?> extra = const {},
]) => FirebaseFunctionsException(
  code: code,
  message: code,
  details: reason == null ? null : {'reason': reason, ...extra},
);

/// A scripted `managePageDeletionV1`: the state each op leaves behind.
class _Backend {
  _Backend({this.current, this.page});

  /// What `status` answers now (and what each op replaces).
  Map<String, Object?>? current;

  /// What `getPageV1` answers.
  Object? page;
  final List<String> ops = [];
  Object? Function(String op)? onOp;

  Future<Object?> call(String name, Map<String, Object?> payload) async {
    if (name == PagesService.pageCallable) {
      final answer = page;
      if (answer is Exception) throw answer;
      return answer;
    }
    if (name != PagesService.deletionCallable) return {'ok': true};
    expect(payload.keys, ['op'], reason: 'the input is exactly {op}');
    final op = payload['op']! as String;
    ops.add(op);
    final scripted = onOp?.call(op);
    if (scripted is Exception) throw scripted;
    if (scripted is Map<String, Object?>) current = scripted;
    return current ?? _state();
  }
}

PagesService _service(_Backend backend) =>
    PagesService(invoker: backend.call, clock: () => _now);

PageDeletionCenter _center(_Backend backend, {PageDeletionStore? store}) =>
    PageDeletionCenter(
      service: _service(backend),
      store: store ?? MemoryPageDeletionStore(),
      userId: () => 'me',
    );

OwnPage _own({bool paused = false, int posts = 14}) => OwnPage(
  kind: PageKind.business,
  status: 'active',
  ownerPaused: paused,
  suspended: false,
  category: 'music_arts',
  description: 'Ceramika.',
  business: PageBusinessInfo.empty,
  displayName: _name,
  postCount: posts,
);

UserProfile _me() => UserProfile(
  uid: 'me',
  email: 'me@example.com',
  displayName: _name,
  username: 'glina',
  bio: '',
  country: 'PL',
  nativeLanguage: 'pl',
  spokenLanguages: const [],
  learningLanguages: const [],
  photoUrl: null,
  bannerUrl: null,
  creatorAgeVerified: false,
  website: '',
  accountType: AccountType.personal,
  friendCount: 0,
  followerCount: 0,
  accountFollowerCount: 128,
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

Map<String, Object?> _post(int n, {required Duration age}) => {
  'postId': 'pp_${n.toRadixString(16).padLeft(40, '0')}',
  'pageId': 'me',
  'pageName': _name,
  'pageKind': 'business',
  'kind': 'text',
  'text': 'Post $n',
  'media': <Object>[],
  'createdAtMs': _now.subtract(age).millisecondsSinceEpoch,
  'likeCount': 0,
  'commentCount': 0,
  'callerLiked': false,
  'commentsEnabled': true,
  'state': 'published',
  'pinned': false,
};

Map<String, Object?> _ownerPage({
  String state = 'active',
  List<Map<String, Object?>> posts = const [],
}) => {
  'schemaVersion': 1,
  'page': {
    'pageId': 'me',
    'displayName': _name,
    'kind': 'business',
    'category': 'music_arts',
    'description': 'Ceramika.',
    'followerCount': 128,
    'postCount': posts.length,
    'onYoVoiceSinceMs': DateTime.utc(2026, 3, 10).millisecondsSinceEpoch,
    'about': {
      'business': {
        'website': null,
        'email': null,
        'phone': null,
        'address': null,
        'hours': null,
        'legalNotice': null,
      },
      'community': null,
    },
    'state': state,
  },
  'viewer': {
    'isOwner': true,
    'following': false,
    'canFollow': false,
    'canMessage': false,
  },
  'pinned': null,
  'posts': posts,
  'nextCursor': null,
  'hasMore': false,
};

class _Actions implements PageAccountActions {
  const _Actions();
  @override
  Future<FriendRelationshipStatus?> relationship(String uid) async => null;
  @override
  Future<void> openChat(
    BuildContext context, {
    required String uid,
    required String name,
    bool recordVoice = false,
  }) async {}
  @override
  Future<void> call(
    BuildContext context, {
    required String uid,
    required String name,
  }) async {}
  @override
  Future<void> inviteToServer(
    BuildContext context, {
    required String uid,
    required String name,
  }) async {}
  @override
  Future<void> removeFriend(String uid) async {}
  @override
  Future<void> block(String uid) async {}
  @override
  Future<void> openPersonalProfile(
    BuildContext context, {
    required String uid,
    String? name,
  }) async {}
}

Future<PagePostView?> _noCompose(
  BuildContext context, {
  required PageComposerOwner owner,
  PagePostKind initialKind = PagePostKind.text,
}) async => null;

Widget _app(Widget home) => MaterialApp(
  theme: AppTheme.darkTheme,
  locale: const Locale('pl'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: home,
);

/// Settings pushed over a blank route, as the Page profile pushes them.
Widget _pushed(Widget child) => Navigator(
  onGenerateInitialRoutes: (navigator, _) => [
    MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink()),
    MaterialPageRoute<void>(builder: (_) => child),
  ],
);

/// [child] pushed over a route that has a Scaffold, so what the closing
/// screens say (a snack) is still on screen after they are gone.
Widget _overBase(Widget child) => Navigator(
  onGenerateInitialRoutes: (navigator, _) => [
    MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Center(child: Text('base'))),
    ),
    MaterialPageRoute<void>(builder: (_) => child),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(child));
  await tester.pumpAndSettle();
}

Widget _settings(_Backend backend, PageDeletionCenter center, {OwnPage? own}) =>
    _pushed(
      PageSettingsScreen(
        service: _service(backend),
        deletion: center,
        accessStream: () => Stream.value(
          PageAccessState(
            resolved: true,
            hasVipGrant: true,
            ownPage: own ?? _own(),
          ),
        ),
        profileStream: () => Stream.value(_me()),
        serverStream: () => Stream.value(const []),
        userId: 'me',
        clock: () => _now,
      ),
    );

Widget _profile(_Backend backend, PageDeletionCenter center, {OwnPage? own}) =>
    _pushed(
      PageProfileScreen(
        pageId: 'me',
        displayName: _name,
        service: _service(backend),
        deletion: center,
        actions: const _Actions(),
        flows: const PagesFlows(openComposer: _noCompose),
        userId: 'me',
        clock: () => _now,
        accessStream: () => Stream.value(
          PageAccessState(
            resolved: true,
            hasVipGrant: true,
            ownPage: own ?? _own(),
          ),
        ),
      ),
    );

Future<void> _toBottom(WidgetTester tester) async {
  await tester.drag(
    find.byKey(const ValueKey('page-settings-list')),
    const Offset(0, -3000),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    EntitlementService.resetCache();
    ProfileService.resetCurrentProfileCache();
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
      fetchOverride: (uids) async => {
        for (final uid in uids) uid: {'staffRole': 'user', 'isVip': true},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  group('wire and service', () {
    test('the state parser requires its keys and ignores unknown ones', () {
      final parsed = PageDeletionState.fromWire({
        ..._state(deletion: 'pending', clearing: true),
        'futureKey': 1,
      });
      expect(parsed.pageId, 'me');
      expect(parsed.pending, isTrue);
      expect(
        parsed.deletion!.deleteAt.millisecondsSinceEpoch,
        _deleteAt.millisecondsSinceEpoch,
      );
      expect(parsed.postsClearingSince, isNotNull);
      expect(parsed.recreateAllowedAt, isNull);
      expect(parsed.isIdle, isFalse);
      // A state this build does not know is the most restrictive one.
      expect(
        PageDeletionState.fromWire(_state(deletion: 'archiving')).purging,
        isTrue,
      );
      expect(PageDeletionState.fromWire(_state()).isIdle, isTrue);
      final missing = _state()..remove('postsClearing');
      expect(() => PageDeletionState.fromWire(missing), throwsFormatException);
      expect(() => PageDeletionState.fromWire('x'), throwsFormatException);
      // The stored form round-trips.
      expect(PageDeletionState.fromWire(parsed.toStored()), parsed);
    });

    test('every op sends exactly {op}; refusals carry their meaning', () async {
      final backend = _Backend(current: _state(deletion: 'pending'));
      final service = _service(backend);
      for (final op in PageDeletionOp.values) {
        await service.managePageDeletion(op);
      }
      expect(backend.ops, [
        'status',
        'request',
        'restore',
        'purgeNow',
        'clearPosts',
      ]);
      final retryAt = _now.add(const Duration(days: 7));
      backend.onOp = (_) => _refusal(
        'failed-precondition',
        'pageRecreateCooldown',
        {'retryAtMs': retryAt.millisecondsSinceEpoch},
      );
      await expectLater(
        service.managePageDeletion(PageDeletionOp.status),
        throwsA(
          isA<PagesException>()
              .having(
                (e) => e.failure,
                'failure',
                PagesFailure.recreateCooldown,
              )
              .having(
                (e) => e.retryAt?.millisecondsSinceEpoch,
                'retryAt',
                retryAt.millisecondsSinceEpoch,
              ),
        ),
      );
      backend.onOp = (_) =>
          _refusal('failed-precondition', 'pageDeletionInProgress');
      await expectLater(
        service.managePageDeletion(PageDeletionOp.restore),
        throwsA(
          isA<PagesException>().having(
            (e) => e.failure,
            'failure',
            PagesFailure.deletionInProgress,
          ),
        ),
      );
    });

    test(
      'the centre shares, remembers and never throws on a refresh',
      () async {
        final store = MemoryPageDeletionStore();
        final backend = _Backend(current: _state(deletion: 'pending'));
        final center = _center(backend, store: store);
        var notified = 0;
        center.addListener(() => notified += 1);
        expect(center.state, isNull);
        // Concurrent refreshes are one request.
        final answers = await Future.wait([center.refresh(), center.refresh()]);
        expect(backend.ops, ['status']);
        expect(answers.first!.pending, isTrue);
        expect(center.resolved, isTrue);
        expect(notified, 1);
        expect(store.states['me']!.pending, isTrue);

        // A second device start shows the remembered state before the answer.
        final offline = _Backend()..onOp = (_) => _refusal('unavailable');
        final later = _center(offline, store: store);
        expect(await later.refresh(), isNull);
        expect(later.state!.pending, isTrue);
        expect(later.resolved, isFalse);

        // Restore clears what was remembered.
        backend.onOp = (op) => op == 'restore' ? _state() : null;
        expect((await center.restore()).deletion, isNull);
        expect(store.states.containsKey('me'), isFalse);
      },
    );

    test(
      'the create entry asks only when this device remembers a deletion',
      () async {
        final backend = _Backend(current: _state());
        final center = _center(backend);
        expect(await center.recreateBlockedUntil(clock: () => _now), isNull);
        expect(
          backend.ops,
          isEmpty,
          reason: 'no request for an ordinary account',
        );

        final until = _now.add(const Duration(days: 5));
        final store = MemoryPageDeletionStore()
          ..states['me'] = PageDeletionState.fromWire(
            _state(deletion: 'pending'),
          );
        final gone = _Backend(
          current: _state(pageExists: false, recreateAt: until),
        );
        final remembering = _center(gone, store: store);
        expect(
          (await remembering.recreateBlockedUntil(
            clock: () => _now,
          ))!.millisecondsSinceEpoch,
          until.millisecondsSinceEpoch,
        );
        expect(gone.ops, ['status']);
        expect(
          await remembering.recreateBlockedUntil(
            clock: () => until.add(const Duration(minutes: 1)),
          ),
          isNull,
          reason: 'the pause is over',
        );
      },
    );
  });

  group('Page settings', () {
    testWidgets('the danger zone replaces the footnote with two actions', (
      tester,
    ) async {
      final backend = _Backend(current: _state());
      await _pump(tester, _settings(backend, _center(backend)));
      await _toBottom(tester);
      expect(find.text('STREFA ZAGROŻENIA'), findsOneWidget);
      expect(find.text('Usuń wszystkie posty'), findsOneWidget);
      expect(find.text('Strona i obserwujący zostają'), findsOneWidget);
      expect(find.text('Usuń stronę'), findsOneWidget);
      expect(
        find.text('Posty, obserwujący i kontakt. Konto zostaje.'),
        findsOneWidget,
      );
      expect(find.textContaining('razem z kontem'), findsNothing);
      // "Wstrzymaj stronę" is still there, above the zone.
      expect(find.byKey(const ValueKey('settings-pause')), findsOneWidget);
    });

    testWidgets(
      '"Usuń wszystkie posty" confirms with the counts, then clears',
      (tester) async {
        final backend = _Backend(current: _state());
        await _pump(tester, _settings(backend, _center(backend)));
        await _toBottom(tester);
        await tester.tap(find.byKey(const ValueKey('settings-delete-posts')));
        await tester.pumpAndSettle();
        expect(find.text('Usunąć 14 postów?'), findsOneWidget);
        expect(
          find.text(
            'Znikną też komentarze i polubienia pod nimi. Strona i 128 '
            'obserwujących zostają. Tego nie da się cofnąć.',
          ),
          findsOneWidget,
        );
        // Cancel sends nothing.
        await tester.tap(find.text('Anuluj'));
        await tester.pumpAndSettle();
        expect(backend.ops, ['status']);

        await tester.tap(find.byKey(const ValueKey('settings-delete-posts')));
        await tester.pumpAndSettle();
        backend.onOp = (op) =>
            op == 'clearPosts' ? _state(clearing: true) : null;
        await tester.tap(find.text('Usuń posty'));
        await tester.pumpAndSettle();
        expect(backend.ops, ['status', 'clearPosts']);
        expect(find.text('Trwa usuwanie postów'), findsOneWidget);
      },
    );

    testWidgets('a Page with no posts has nothing to clear', (tester) async {
      final backend = _Backend(current: _state());
      await _pump(
        tester,
        _settings(backend, _center(backend), own: _own(posts: 0)),
      );
      await _toBottom(tester);
      await tester.tap(
        find.byKey(const ValueKey('settings-delete-posts')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(backend.ops, ['status']);
    });

    testWidgets('"Usuń stronę" needs the typed name, then shows the date', (
      tester,
    ) async {
      final backend = _Backend(current: _state());
      await _pump(tester, _settings(backend, _center(backend)));
      await _toBottom(tester);
      await tester.tap(find.byKey(const ValueKey('settings-delete-page')));
      await tester.pumpAndSettle();
      expect(find.byType(PageDeleteScreen), findsOneWidget);
      expect(find.text('ZNIKNIE'), findsOneWidget);
      expect(find.text('ZOSTAJE'), findsOneWidget);
      expect(find.text('14 postów ze zdjęciami i nagraniami.'), findsOneWidget);
      expect(
        find.text(
          '128 obserwujących strony i ich powiadomienia o Twoich LIVE.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Zgłoszone treści możemy przechowywać niepublicznie do 90 dni.',
        ),
        findsOneWidget,
      );
      await tester.drag(
        find.byKey(const ValueKey('page-delete-list')),
        const Offset(0, -3000),
      );
      await tester.pumpAndSettle();
      expect(find.text('Masz 30 dni na powrót'), findsOneWidget);
      expect(find.textContaining('1 listopada 2026'), findsOneWidget);

      FilledButton button() => tester.widget<FilledButton>(
        find.byKey(const ValueKey('page-delete-confirm')),
      );
      expect(button().onPressed, isNull, reason: 'nothing typed yet');
      await tester.enterText(
        find.byKey(const ValueKey('page-delete-name')),
        'Pracownia',
      );
      await tester.pump();
      expect(button().onPressed, isNull, reason: 'not the whole name');
      await tester.enterText(
        find.byKey(const ValueKey('page-delete-name')),
        ' pracownia glina ',
      );
      await tester.pump();
      expect(button().onPressed, isNotNull, reason: 'case and edges forgiven');

      backend.onOp = (op) =>
          op == 'request' ? _state(deletion: 'pending') : null;
      await tester.tap(find.byKey(const ValueKey('page-delete-confirm')));
      await tester.pumpAndSettle();
      expect(backend.ops, ['status', 'request']);
      expect(find.byType(PageDeleteScreen), findsNothing);
      // Back in settings, in the pending state.
      expect(
        find.byKey(const ValueKey('settings-notice-pending')),
        findsOneWidget,
      );
    });

    testWidgets('pending: the date, restore, locked edits, "Usuń teraz"', (
      tester,
    ) async {
      final backend = _Backend(current: _state(deletion: 'pending'));
      await _pump(
        tester,
        _settings(backend, _center(backend), own: _own(paused: true)),
      );
      expect(
        find.text('Strona zostanie usunięta 1 listopada 2026'),
        findsOneWidget,
      );
      expect(find.text('DO USUNIĘCIA'), findsOneWidget);
      // Every edit row is disabled.
      final category = tester.widget<ListTile>(
        find.descendant(
          of: find.byKey(const ValueKey('settings-category')),
          matching: find.byType(ListTile),
        ),
      );
      expect(category.enabled, isFalse);
      await _toBottom(tester);
      expect(find.byKey(const ValueKey('settings-pause')), findsNothing);
      expect(find.byKey(const ValueKey('settings-resume')), findsNothing);
      expect(find.byKey(const ValueKey('settings-delete-posts')), findsNothing);
      expect(find.text('Usuń teraz, nie czekaj'), findsOneWidget);
      expect(
        find.text('Bez czekania do 1 listopada. Tego nie da się cofnąć.'),
        findsOneWidget,
      );

      // "Usuń teraz" asks first.
      await tester.tap(find.byKey(const ValueKey('settings-delete-now')));
      await tester.pumpAndSettle();
      expect(find.text('Usunąć stronę teraz?'), findsOneWidget);
      await tester.tap(find.text('Anuluj'));
      await tester.pumpAndSettle();
      expect(backend.ops, ['status']);

      // Restore brings the ordinary settings back.
      backend.onOp = (op) => op == 'restore' ? _state() : null;
      await tester.tap(find.byKey(const ValueKey('settings-restore')));
      await tester.pumpAndSettle();
      expect(backend.ops, ['status', 'restore']);
      expect(find.text('Strona przywrócona'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-notice-pending')),
        findsNothing,
      );
    });

    testWidgets('a refused restore says why and changes nothing', (
      tester,
    ) async {
      final backend = _Backend(current: _state(deletion: 'pending'))
        ..onOp = (op) => op == 'restore'
            ? _refusal('failed-precondition', 'pageAccessRequired')
            : null;
      await _pump(
        tester,
        _settings(backend, _center(backend), own: _own(paused: true)),
      );
      await tester.tap(find.byKey(const ValueKey('settings-notice-restore')));
      await tester.pumpAndSettle();
      expect(
        find.text('Do prowadzenia strony potrzebny jest YO Voice VIP.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-notice-pending')),
        findsOneWidget,
      );
    });

    testWidgets(
      '"Usuń teraz" confirmed starts the purge; nothing is left to do',
      (tester) async {
        final backend = _Backend(current: _state(deletion: 'pending'));
        await _pump(
          tester,
          _settings(backend, _center(backend), own: _own(paused: true)),
        );
        await _toBottom(tester);
        await tester.tap(find.byKey(const ValueKey('settings-delete-now')));
        await tester.pumpAndSettle();
        backend.onOp = (op) =>
            op == 'purgeNow' ? _state(deletion: 'purging') : null;
        await tester.tap(find.byKey(const ValueKey('page-confirm-action')));
        await tester.pumpAndSettle();
        expect(backend.ops, ['status', 'purgeNow']);
        expect(
          find.byKey(const ValueKey('settings-notice-purging')),
          findsOneWidget,
        );
        await _toBottom(tester);
        expect(
          find.byKey(const ValueKey('settings-danger-zone')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('settings-restore')), findsNothing);
      },
    );

    testWidgets(
      '"Usuń teraz" on a small Page: gone at once, said so, settings close',
      (tester) async {
        final backend = _Backend(current: _state(deletion: 'pending'));
        await _pump(
          tester,
          _overBase(
            PageSettingsScreen(
              service: _service(backend),
              deletion: _center(backend),
              accessStream: () => Stream.value(
                PageAccessState(
                  resolved: true,
                  hasVipGrant: true,
                  ownPage: _own(paused: true),
                ),
              ),
              profileStream: () => Stream.value(_me()),
              serverStream: () => Stream.value(const []),
              userId: 'me',
              clock: () => _now,
            ),
          ),
        );
        await _toBottom(tester);
        await tester.tap(find.byKey(const ValueKey('settings-delete-now')));
        await tester.pumpAndSettle();
        backend.onOp = (op) => op == 'purgeNow'
            ? _state(
                pageExists: false,
                recreateAt: _now.add(const Duration(days: 7)),
              )
            : null;
        await tester.tap(find.byKey(const ValueKey('page-confirm-action')));
        await tester.pumpAndSettle();
        expect(backend.ops, ['status', 'purgeNow']);
        expect(find.byType(PageSettingsScreen), findsNothing);
        expect(find.text('base'), findsOneWidget);
        expect(find.text('Strona usunięta'), findsOneWidget);
      },
    );

    testWidgets(
      'the purge finishes while settings are open: the fact and the date, '
      'not an error',
      (tester) async {
        final backend = _Backend(current: _state(deletion: 'purging'));
        final access = StreamController<PageAccessState>();
        addTearDown(access.close);
        access.add(
          PageAccessState(
            resolved: true,
            hasVipGrant: true,
            ownPage: _own(paused: true),
          ),
        );
        await _pump(
          tester,
          _pushed(
            PageSettingsScreen(
              service: _service(backend),
              deletion: _center(backend),
              accessStream: () => access.stream,
              profileStream: () => Stream.value(_me()),
              serverStream: () => Stream.value(const []),
              userId: 'me',
              clock: () => _now,
            ),
          ),
        );
        expect(
          find.byKey(const ValueKey('settings-notice-purging')),
          findsOneWidget,
        );

        // pages/{uid} is gone; this screen's deletion state is older.
        final until = _now.add(const Duration(days: 7));
        backend.current = _state(pageExists: false, recreateAt: until);
        access.add(
          const PageAccessState(
            resolved: true,
            hasVipGrant: true,
            ownPage: null,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('settings-page-deleted')),
          findsOneWidget,
        );
        expect(find.text('Strona usunięta'), findsOneWidget);
        final copy = PagesCopy(const AppLocalizations(Locale('pl')));
        expect(find.text(copy.recreateAfter(until)), findsOneWidget);
        expect(find.text(copy.noPageYet), findsNothing);
        expect(backend.ops, ['status', 'status'], reason: 'asked once more');
      },
    );

    testWidgets('an account that simply has no Page keeps the plain message', (
      tester,
    ) async {
      final backend = _Backend(current: _state(pageExists: false));
      await _pump(
        tester,
        _pushed(
          PageSettingsScreen(
            service: _service(backend),
            deletion: _center(backend),
            accessStream: () => Stream.value(
              const PageAccessState(
                resolved: true,
                hasVipGrant: true,
                ownPage: null,
              ),
            ),
            profileStream: () => Stream.value(_me()),
            serverStream: () => Stream.value(const []),
            userId: 'me',
            clock: () => _now,
          ),
        ),
      );
      // No deletion and no pause before a new Page are known: the screen
      // says "deleted" only when it knows of one.
      final copy = PagesCopy(const AppLocalizations(Locale('pl')));
      expect(find.text(copy.noPageYet), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-page-deleted')), findsNothing);
    });

    testWidgets('one 640 column on desktop, no overflow at 200 % text', (
      tester,
    ) async {
      final backend = _Backend(current: _state(deletion: 'pending'));
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(1440, 900),
              textScaler: TextScaler.linear(2),
            ),
            child: _settings(
              backend,
              _center(backend),
              own: _own(paused: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final notice = tester.getSize(
        find.byKey(const ValueKey('settings-notice-pending')),
      );
      expect(notice.width, lessThanOrEqualTo(PageSettingsScreen.columnWidth));
      await _toBottom(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('the owner\'s Page', () {
    testWidgets('pending: banner, pill, restore; no "Wznów stronę"', (
      tester,
    ) async {
      final backend = _Backend(
        current: _state(deletion: 'pending'),
        page: _ownerPage(
          state: 'paused',
          posts: [_post(1, age: const Duration(days: 2))],
        ),
      );
      await _pump(
        tester,
        _profile(backend, _center(backend), own: _own(paused: true)),
      );
      expect(
        find.byKey(const ValueKey('page-notice-pending-deletion')),
        findsOneWidget,
      );
      expect(
        find.text('Strona zostanie usunięta 1 listopada 2026'),
        findsOneWidget,
      );
      expect(find.byType(PageStatusPill), findsOneWidget);
      expect(find.text('DO USUNIĘCIA'), findsOneWidget);
      expect(find.byKey(const ValueKey('page-resume')), findsNothing);
      expect(find.byKey(const ValueKey('page-notice-paused')), findsNothing);
      expect(
        find.byKey(const ValueKey('page-settings-button')),
        findsOneWidget,
      );

      backend.onOp = (op) => op == 'restore' ? _state() : null;
      backend.page = _ownerPage(
        posts: [_post(1, age: const Duration(days: 2))],
      );
      await tester.tap(find.byKey(const ValueKey('page-restore')));
      await tester.pumpAndSettle();
      expect(backend.ops, ['status', 'restore']);
      expect(
        find.byKey(const ValueKey('page-notice-pending-deletion')),
        findsNothing,
      );
      expect(find.text('DO USUNIĘCIA'), findsNothing);
    });

    testWidgets(
      'clearing: the honest state, old posts hidden, new ones shown',
      (tester) async {
        final backend = _Backend(
          current: _state(clearing: true),
          page: _ownerPage(posts: [_post(1, age: const Duration(days: 2))]),
        );
        await _pump(tester, _profile(backend, _center(backend)));
        expect(
          find.byKey(const ValueKey('page-wall-clearing')),
          findsOneWidget,
        );
        expect(find.text('Trwa usuwanie postów'), findsOneWidget);
        expect(
          find.text(
            'Znikają w tle, zwykle w kilkanaście minut. Strona i 128 '
            'obserwujących zostają.',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('page-wall-clearing-publish')),
          findsOneWidget,
        );
        expect(
          find.text('Post 1'),
          findsNothing,
          reason: 'about to be deleted',
        );
        expect(find.byKey(const ValueKey('page-wall-empty')), findsNothing);
        // The poll stops with the screen.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 30));
      },
    );

    testWidgets(
      'desktop: the settings-only action row lays out beside the name',
      (tester) async {
        // The desktop header puts the actions in an unbounded Row; a pending
        // (or read-only, hidden, suspended) owner's row must not expand there.
        for (final own in [
          _own(paused: true),
          const OwnPage(
            kind: PageKind.business,
            status: 'readOnly',
            ownerPaused: false,
            suspended: false,
          ),
        ]) {
          final pending = own.ownerPaused;
          final backend = _Backend(
            current: pending ? _state(deletion: 'pending') : _state(),
            page: _ownerPage(
              state: pending ? 'paused' : 'readOnly',
              posts: [_post(1, age: const Duration(days: 2))],
            ),
          );
          await _pump(
            tester,
            _profile(backend, _center(backend), own: own),
            size: const Size(1440, 900),
          );
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const ValueKey('page-settings-button')),
            findsOneWidget,
          );
          expect(
            find.text('DO USUNIĘCIA'),
            pending ? findsOneWidget : findsNothing,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );

    testWidgets(
      '"Usuń teraz" from settings: both screens close, one confirmation',
      (tester) async {
        final backend = _Backend(
          current: _state(deletion: 'pending'),
          page: _ownerPage(
            state: 'paused',
            posts: [_post(1, age: const Duration(days: 2))],
          ),
        );
        final center = _center(backend);
        final access = PageAccessState(
          resolved: true,
          hasVipGrant: true,
          ownPage: _own(paused: true),
        );
        await _pump(
          tester,
          _overBase(
            PageProfileScreen(
              pageId: 'me',
              displayName: _name,
              service: _service(backend),
              deletion: center,
              actions: const _Actions(),
              flows: const PagesFlows(openComposer: _noCompose),
              userId: 'me',
              clock: () => _now,
              accessStream: () => Stream.value(access),
              settingsBuilder: (_) => PageSettingsScreen(
                service: _service(backend),
                deletion: center,
                accessStream: () => Stream.value(access),
                profileStream: () => Stream.value(_me()),
                serverStream: () => Stream.value(const []),
                userId: 'me',
                clock: () => _now,
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('page-settings-button')));
        await tester.pumpAndSettle();
        expect(find.byType(PageSettingsScreen), findsOneWidget);
        await _toBottom(tester);
        await tester.tap(find.byKey(const ValueKey('settings-delete-now')));
        await tester.pumpAndSettle();
        backend.onOp = (op) => op == 'purgeNow'
            ? _state(
                pageExists: false,
                recreateAt: _now.add(const Duration(days: 7)),
              )
            : null;
        await tester.tap(find.byKey(const ValueKey('page-confirm-action')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Neither the settings nor the profile of a Page that no longer
        // exists is left on the stack.
        expect(find.byType(PageSettingsScreen), findsNothing);
        expect(find.byType(PageProfileScreen), findsNothing);
        expect(find.text('base'), findsOneWidget);
        expect(find.text('Strona usunięta'), findsOneWidget);
      },
    );

    testWidgets(
      'purging: the open profile keeps asking, then says so and closes',
      (tester) async {
        final backend = _Backend(
          current: _state(deletion: 'purging'),
          page: _ownerPage(state: 'paused'),
        );
        await _pump(
          tester,
          _overBase(
            PageProfileScreen(
              pageId: 'me',
              displayName: _name,
              service: _service(backend),
              deletion: _center(backend),
              actions: const _Actions(),
              flows: const PagesFlows(openComposer: _noCompose),
              userId: 'me',
              clock: () => _now,
              accessStream: () => Stream.value(
                PageAccessState(
                  resolved: true,
                  hasVipGrant: true,
                  ownPage: _own(paused: true),
                ),
              ),
            ),
          ),
        );
        expect(
          find.byKey(const ValueKey('page-notice-purging')),
          findsOneWidget,
        );
        expect(backend.ops, ['status']);
        // Still purging on the next poll: nothing changes.
        await tester.pump(const Duration(seconds: 21));
        await tester.pumpAndSettle();
        expect(backend.ops, ['status', 'status']);
        expect(find.byType(PageProfileScreen), findsOneWidget);
        // The worker finished.
        backend.current = _state(
          pageExists: false,
          recreateAt: _now.add(const Duration(days: 7)),
        );
        await tester.pump(const Duration(seconds: 21));
        await tester.pumpAndSettle();
        expect(find.byType(PageProfileScreen), findsNothing);
        expect(find.text('base'), findsOneWidget);
        expect(find.text('Strona usunięta'), findsOneWidget);
        // The poll went with the screen.
        final asked = backend.ops.length;
        await tester.pump(const Duration(seconds: 60));
        expect(backend.ops.length, asked);
      },
    );

    testWidgets('clearing: the Zdjęcia tab hides the photos that are going', (
      tester,
    ) async {
      final backend = _Backend(
        current: _state(clearing: true),
        page: _ownerPage(posts: [_post(1, age: const Duration(days: 2))]),
      );
      await _pump(tester, _profile(backend, _center(backend)));
      await tester.tap(find.text('Zdjęcia'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('page-photos-grid')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 30));
    });

    testWidgets('a visitor is never asked about deletion', (tester) async {
      final backend = _Backend(
        current: _state(deletion: 'pending'),
        page: {
          ..._ownerPage(posts: [_post(1, age: const Duration(days: 2))]),
          'viewer': {
            'isOwner': false,
            'following': false,
            'canFollow': true,
            'canMessage': false,
          },
        },
      );
      final center = _center(backend);
      await _pump(
        tester,
        _pushed(
          PageProfileScreen(
            pageId: 'me',
            displayName: _name,
            service: _service(backend),
            deletion: center,
            actions: const _Actions(),
            flows: const PagesFlows(openComposer: _noCompose),
            userId: 'visitor',
            clock: () => _now,
          ),
        ),
      );
      expect(backend.ops, isEmpty);
      expect(find.text('DO USUNIĘCIA'), findsNothing);
      expect(find.text('Post 1'), findsOneWidget);
    });
  });

  group('create entry', () {
    testWidgets('during the 7-day pause the entry names the date instead', (
      tester,
    ) async {
      // The centre compares with the wall clock: a pause that ends 5 days
      // from now, whenever this runs.
      final until = DateTime.now().add(const Duration(days: 5));
      final store = MemoryPageDeletionStore()
        ..states['me'] = PageDeletionState.fromWire(
          _state(pageExists: false, recreateAt: until),
        );
      final backend = _Backend(
        current: _state(pageExists: false, recreateAt: until),
      );
      final center = _center(backend, store: store);
      var opened = 0;
      await _pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                openCreatePageFlow(
                  context,
                  accessStream: () => Stream.value(
                    const PageAccessState(
                      resolved: true,
                      hasVipGrant: true,
                      ownPage: null,
                    ),
                  ),
                  deletion: center,
                  screenBuilder: (_) {
                    opened += 1;
                    return const SizedBox.shrink();
                  },
                ),
              ),
              child: const Text('create'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('create'));
      await tester.pumpAndSettle();
      expect(opened, 0, reason: 'the form is not opened');
      expect(backend.ops, ['status']);
      final copy = PagesCopy(const AppLocalizations(Locale('pl')));
      expect(find.text(copy.recreateAfter(until)), findsOneWidget);
    });

    testWidgets(
      'an account that never deleted a Page goes straight to create',
      (tester) async {
        final backend = _Backend(current: _state());
        final center = _center(backend);
        var opened = 0;
        await _pump(
          tester,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  openCreatePageFlow(
                    context,
                    accessStream: () => Stream.value(
                      const PageAccessState(
                        resolved: true,
                        hasVipGrant: true,
                        ownPage: null,
                      ),
                    ),
                    deletion: center,
                    screenBuilder: (_) {
                      opened += 1;
                      return const Scaffold(body: SizedBox.shrink());
                    },
                  ),
                ),
                child: const Text('create'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('create'));
        await tester.pumpAndSettle();
        expect(opened, 1);
        expect(
          backend.ops,
          isEmpty,
          reason: 'no extra request before the form',
        );
      },
    );
  });
}
