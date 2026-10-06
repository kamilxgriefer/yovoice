// "Edytuj stronę" (pageEdit A, owner decision 2026-10-03): the one form with
// the live preview, its single save, the read-only state with "Wyczyść dane
// kontaktowe" (ADR-241), and the three layouts.
import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/page_links.dart';
import 'package:yovoice/features/pages/data/services/page_access_service.dart';
import 'package:yovoice/features/pages/data/services/pages_local_store.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/page_navigation.dart';
import 'package:yovoice/features/pages/presentation/pages_flows.dart';
import 'package:yovoice/features/pages/presentation/screens/content_screen.dart';
import 'package:yovoice/features/pages/presentation/screens/page_edit_screen.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_form_parts.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';

final DateTime _now = DateTime.utc(2026, 10, 3, 12);

/// A decodable 1x1 PNG: what a picked picture holds.
final Uint8List _pixel = Uint8List.fromList(const <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

FirebaseFunctionsException _refusal(String code, [String? reason]) =>
    FirebaseFunctionsException(
      code: code,
      message: code,
      details: reason == null ? null : <String, Object?>{'reason': reason},
    );

class _Backend {
  _Backend([Map<String, FutureOr<Object?> Function(Map<String, Object?>)>? h])
    : handlers = h ?? {};

  final Map<String, FutureOr<Object?> Function(Map<String, Object?>)> handlers;
  final List<(String, Map<String, Object?>)> calls = [];

  Future<Object?> call(String name, Map<String, Object?> payload) async {
    calls.add((name, payload));
    final handler = handlers[name];
    if (handler == null) {
      return {
        'pageId': 'me',
        'kind': 'business',
        'status': 'active',
        'ownerPaused': false,
      };
    }
    return handler(payload);
  }

  List<Map<String, Object?>> get manage => [
    for (final call in calls)
      if (call.$1 == 'managePageV1') call.$2,
  ];
}

PagesService _service(_Backend backend) => PagesService(
  invoker: backend.call,
  requestIdFactory: () => 'pg_test_request_0001',
  clock: () => _now,
);

class _Account implements PageEditAccount {
  _Account({
    UserProfile? profile,
    this.renameError,
    this.uploadError,
    this.pick,
  }) : profile = profile ?? _profile();

  final UserProfile profile;
  Object? renameError;
  Object? uploadError;
  final PickedProfileImage? Function(ProfileImageKind kind)? pick;
  final List<String> log = [];

  @override
  Stream<UserProfile> watchProfile() => Stream.value(profile);

  @override
  Future<DisplayNameChangeResult> rename(String displayName) async {
    log.add('rename:$displayName');
    final error = renameError;
    if (error != null) throw error;
    return DisplayNameChangeResult(
      displayName: displayName,
      changed: true,
      canChange: false,
      displayNameChangedAt: _now,
      nextDisplayNameChangeAt: _now.add(const Duration(days: 30)),
    );
  }

  @override
  Future<void> uploadImage(PickedProfileImage image) async {
    log.add('upload:${image.kind.name}');
    final error = uploadError;
    if (error != null) throw error;
  }

  @override
  Future<PickedProfileImage?> pickImage(
    BuildContext context,
    ProfileImageKind kind,
  ) async {
    log.add('pick:${kind.name}');
    return pick?.call(kind);
  }
}

UserProfile _profile({
  String name = 'Kawiarnia Ziarno',
  DateTime? nameChangedAt,
  int followers = 128,
}) => UserProfile(
  uid: 'me',
  email: 'me@example.com',
  displayName: name,
  username: 'ziarno',
  bio: '',
  country: 'PL',
  nativeLanguage: 'pl',
  spokenLanguages: const [],
  learningLanguages: const [],
  photoUrl: null,
  bannerUrl: null,
  website: '',
  accountType: AccountType.personal,
  friendCount: 0,
  followerCount: 0,
  accountFollowerCount: followers,
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
  displayNameChangedAt: nameChangedAt,
);

const _contact = PageBusinessInfo(
  website: 'https://kawiarniaziarno.pl',
  phone: '+48585550127',
);

OwnPage _own({
  PageKind kind = PageKind.business,
  String status = 'active',
  bool suspended = false,
  PageBusinessInfo? business = _contact,
  String description = 'Kawa speciality.',
  String? linkedServerId,
}) => OwnPage(
  kind: kind,
  status: status,
  ownerPaused: false,
  suspended: suspended,
  suspensionReason: suspended ? 'spam' : null,
  category: kind == PageKind.business ? 'cafe_restaurant' : 'sport',
  description: description,
  business: kind == PageKind.business ? business : null,
  rules: kind == PageKind.community ? 'Biegamy razem.' : null,
  linkedServerId: linkedServerId,
  displayName: 'Kawiarnia Ziarno',
);

PageAccessState _state(OwnPage? page, {bool vip = true}) =>
    PageAccessState(resolved: true, hasVipGrant: vip, ownPage: page);

const _server = Server(
  id: 'srv_run',
  name: 'Biegamy w Oliwie',
  description: '',
  ownerId: 'me',
  type: ServerType.community,
  privacy: ServerPrivacy.public,
);

PageEditScreen _edit(
  _Backend backend, {
  _Account? account,
  OwnPage? page,
  bool vip = true,
  Stream<PageAccessState> Function()? access,
}) => PageEditScreen(
  service: _service(backend),
  account: account ?? _Account(),
  accessStream: access ?? () => Stream.value(_state(page ?? _own(), vip: vip)),
  serverStream: () => Stream.value(const [_server]),
  userId: 'me',
  clock: () => _now,
);

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps [screen] as a pushed route over a blank one (so it can pop), at
/// [size]: on the app's own navigator, as on a phone, or ([desktop]) on a
/// nested one that says it is Treści's desktop column.
Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(390, 844),
  double textScale = 1,
  Locale locale = const Locale('pl'),
  bool desktop = false,
  bool pearl = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final route = MaterialPageRoute<void>(
    settings: const RouteSettings(name: pageEditRouteName),
    builder: (_) => screen,
  );
  final rootNavigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      // A fresh app per pump: no state survives from an earlier screen.
      key: UniqueKey(),
      navigatorKey: rootNavigator,
      theme: pearl ? AppTheme.lightTheme : AppTheme.darkTheme,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: desktop
          ? Scaffold(
              body: PagesNavigatorScope(
                desktop: true,
                child: Navigator(
                  onGenerateInitialRoutes: (navigator, _) => [
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(body: Text('under')),
                    ),
                    route,
                  ],
                ),
              ),
            )
          : const Scaffold(body: Text('under')),
    ),
  );
  if (!desktop) unawaited(rootNavigator.currentState!.push(route));
  await _settle(tester);
}

String _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(_key(key)).controller!.text;

/// Brings a lazily built field on screen.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final scrollable = find
      .descendant(
        of: _key('page-edit-scroll'),
        matching: find.byType(Scrollable),
      )
      .first;
  for (var step = 0; step < 40 && finder.evaluate().isEmpty; step++) {
    tester.state<ScrollableState>(scrollable).position.jumpTo(step * 300.0);
    await tester.pump();
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _type(WidgetTester tester, String key, String value) async {
  await _reveal(tester, _key(key));
  await tester.enterText(_key(key), value);
  await tester.pump();
}

bool _saveEnabled(WidgetTester tester) =>
    tester.widget<YoGradientFilledButton>(_key('page-edit-save')).onPressed !=
    null;

void main() {
  setUp(() {
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
      fetchOverride: (uids) async => {
        for (final uid in uids)
          uid: {'staffRole': 'user', 'isVip': true, 'page': 'business'},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  group('the form', () {
    testWidgets('shows the whole stored profile and nothing to save', (
      tester,
    ) async {
      final backend = _Backend();
      await _pump(tester, _edit(backend));
      expect(find.text('Edytuj stronę'), findsOneWidget);
      expect(_text(tester, 'page-edit-name'), 'Kawiarnia Ziarno');
      expect(
        find.text(
          'Okładka, zdjęcie i nazwa strony to także okładka, zdjęcie i nazwa '
          'Twojego konta w czatach i serwerach.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Nazwę zmienisz raz na 30 dni. Po zmianie strona przez 7 dni nie '
          'pojawia się w wyszukiwarce.',
        ),
        findsOneWidget,
      );
      // The type is shown and locked (D16).
      expect(find.text('Firma'), findsOneWidget);
      expect(find.text('Typu nie da się jeszcze zmienić'), findsOneWidget);
      expect(find.text('Kawiarnia i restauracja'), findsOneWidget);
      await _reveal(tester, _key('page-edit-phone'));
      expect(_text(tester, 'page-edit-description'), 'Kawa speciality.');
      expect(_text(tester, 'page-edit-website'), 'https://kawiarniaziarno.pl');
      expect(_text(tester, 'page-edit-phone'), '+48585550127');

      // Clean: "Zapisz" is off, there is no save bar, Back just leaves.
      expect(
        tester.widget<TextButton>(_key('page-edit-save-action')).onPressed,
        isNull,
      );
      expect(_key('page-edit-save-bar'), findsNothing);
      expect(_key('page-edit-unsaved'), findsNothing);
      await tester.tap(_key('page-edit-back'));
      await _settle(tester);
      expect(find.byType(PageEditScreen), findsNothing);
      expect(backend.calls, isEmpty);
    });

    testWidgets('one change brings "Zapisz zmiany"; saving sends ONE update '
        'with the whole profile and leaves', (tester) async {
      final backend = _Backend();
      final account = _Account();
      await _pump(tester, _edit(backend, account: account));
      await _type(tester, 'page-edit-description', 'Kawa i ciasto.');
      await _type(tester, 'page-edit-phone', '+48 58 555 01 42');
      expect(find.text('Masz niezapisane zmiany'), findsOneWidget);
      expect(_saveEnabled(tester), isTrue);
      expect(
        tester.widget<TextButton>(_key('page-edit-save-action')).onPressed,
        isNotNull,
      );

      await tester.tap(_key('page-edit-save'));
      await _settle(tester);
      expect(backend.manage, [
        {
          'requestId': 'pg_test_request_0001',
          'op': 'update',
          'category': 'cafe_restaurant',
          'description': 'Kawa i ciasto.',
          'business': {
            'website': 'https://kawiarniaziarno.pl',
            'email': null,
            'phone': '+48 58 555 01 42',
            'address': null,
            'hours': null,
            'legalNotice': null,
          },
          'community': null,
        },
      ]);
      // Neither the name nor a picture changed: nothing else was called.
      expect(account.log, isEmpty);
      expect(find.byType(PageEditScreen), findsNothing);
      expect(find.text('Zapisano'), findsOneWidget);
    });

    testWidgets('the name, both pictures and the fields save in that order, '
        'each once', (tester) async {
      final backend = _Backend();
      final bytes = _pixel;
      final account = _Account(
        pick: (kind) => PickedProfileImage(
          kind: kind,
          bytes: bytes,
          format: ProfileImageFormat.jpeg,
        ),
      );
      final order = <String>[];
      backend.handlers['managePageV1'] = (payload) {
        order.addAll([...account.log, 'update']);
        return {
          'pageId': 'me',
          'kind': 'business',
          'status': 'active',
          'ownerPaused': false,
        };
      };
      await _pump(tester, _edit(backend, account: account));
      await tester.tap(_key('page-edit-cover'));
      await _settle(tester);
      await tester.tap(_key('page-edit-photo'));
      await _settle(tester);
      // A chosen picture is a pending change: nothing is uploaded yet.
      expect(account.log, ['pick:banner', 'pick:avatar']);
      expect(_key('page-cover-local'), findsOneWidget);
      expect(_key('page-face-local'), findsOneWidget);
      expect(find.text('Masz niezapisane zmiany'), findsOneWidget);
      account.log.clear();

      await _type(tester, 'page-edit-name', '  Ziarno Oliwa ');
      await _type(tester, 'page-edit-description', 'Nowy opis.');
      await tester.tap(_key('page-edit-save'));
      await _settle(tester);
      expect(order, [
        'rename:Ziarno Oliwa',
        'upload:avatar',
        'upload:banner',
        'update',
      ]);
      expect(backend.manage.single['description'], 'Nowy opis.');
      expect(find.byType(PageEditScreen), findsNothing);
    });

    testWidgets('a save in flight makes the form inert until it answers', (
      tester,
    ) async {
      final answer = Completer<Object?>();
      final backend = _Backend({'managePageV1': (_) => answer.future});
      await _pump(tester, _edit(backend));
      bool inert() => tester
          .widget<AbsorbPointer>(
            find
                .ancestor(
                  of: _key('page-edit-scroll'),
                  matching: find.byType(AbsorbPointer),
                )
                .first,
          )
          .absorbing;
      await _type(tester, 'page-edit-description', 'Nowy opis.');
      expect(inert(), isFalse);

      await tester.tap(_key('page-edit-save'));
      await tester.pump();
      expect(inert(), isTrue);
      // Neither the form nor Back can change anything meanwhile.
      await tester.tap(_key('page-edit-category'), warnIfMissed: false);
      await tester.tap(_key('page-edit-back'));
      await _settle(tester);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Odrzucić zmiany?'), findsNothing);
      expect(find.byType(PageEditScreen), findsOneWidget);

      answer.complete({
        'pageId': 'me',
        'kind': 'business',
        'status': 'active',
        'ownerPaused': false,
      });
      await _settle(tester);
      expect(backend.manage.single['description'], 'Nowy opis.');
      expect(find.byType(PageEditScreen), findsNothing);
    });

    testWidgets('only a picture changed: no update call is spent', (
      tester,
    ) async {
      final backend = _Backend();
      final account = _Account(
        pick: (kind) => PickedProfileImage(
          kind: kind,
          bytes: _pixel,
          format: ProfileImageFormat.jpeg,
        ),
      );
      await _pump(tester, _edit(backend, account: account));
      await tester.tap(_key('page-edit-cover'));
      await _settle(tester);
      await tester.tap(_key('page-edit-save'));
      await _settle(tester);
      expect(account.log, ['pick:banner', 'upload:banner']);
      expect(backend.manage, isEmpty);
      expect(find.byType(PageEditScreen), findsNothing);
    });

    testWidgets('a community Page edits its rules and linked server', (
      tester,
    ) async {
      final backend = _Backend();
      await _pump(tester, _edit(backend, page: _own(kind: PageKind.community)));
      expect(find.text('Społeczność'), findsWidgets);
      expect(find.text('Temat'), findsOneWidget);
      await _reveal(tester, _key('page-edit-linked-server'));
      expect(_key('page-edit-website'), findsNothing);
      expect(_text(tester, 'page-edit-rules'), 'Biegamy razem.');
      expect(find.text('Bez serwera'), findsOneWidget);

      await tester.tap(_key('page-edit-linked-server'));
      await _settle(tester);
      await tester.tap(_key('page-server-srv_run'));
      await _settle(tester);
      expect(find.text('Biegamy w Oliwie'), findsOneWidget);
      await _type(tester, 'page-edit-rules', '');
      await tester.tap(_key('page-edit-save'));
      await _settle(tester);
      final update = backend.manage.single;
      expect(update['business'], isNull);
      expect(update['community'], {'rules': null, 'linkedServerId': 'srv_run'});
      expect(update['category'], 'sport');
    });

    testWidgets('the category picker changes the category and the preview '
        'follows', (tester) async {
      final backend = _Backend();
      await _pump(tester, _edit(backend), size: const Size(1280, 900));
      await tester.tap(_key('page-edit-category'));
      await _settle(tester);
      await tester.tap(_key('page-category-shop'));
      await _settle(tester);
      expect(find.text('Sklep'), findsOneWidget);
      expect(find.text('Masz niezapisane zmiany'), findsOneWidget);
    });
  });

  group('validation and refusals', () {
    testWidgets('an invalid field stops the save, is focused and said', (
      tester,
    ) async {
      final backend = _Backend();
      final account = _Account();
      await _pump(tester, _edit(backend, account: account));
      await _type(tester, 'page-edit-phone', '12345');
      await tester.tap(_key('page-edit-save'));
      await _settle(tester);
      expect(backend.manage, isEmpty);
      expect(account.log, isEmpty);
      expect(find.textContaining('+48 58 555 01 27'), findsOneWidget);
      expect(find.byType(PageEditScreen), findsOneWidget);

      await _type(tester, 'page-edit-phone', '');
      await _type(tester, 'page-edit-name', 'K');
      await tester.tap(_key('page-edit-save'));
      await _settle(tester);
      expect(find.text('Nazwa musi mieć od 2 do 120 znaków.'), findsOneWidget);
      expect(account.log, isEmpty);
    });

    testWidgets('a refused name stops everything after it and says why', (
      tester,
    ) async {
      final backend = _Backend();
      final account = _Account(
        renameError: const DisplayNameChangeException(
          DisplayNameChangeFailure.nameNotAllowed,
          "This name can't be used for a Page.",
        ),
      );
      await _pump(tester, _edit(backend, account: account));
      await _type(tester, 'page-edit-name', 'YO Voice Official');
      await _type(tester, 'page-edit-description', 'Nowy opis.');
      await tester.tap(_key('page-edit-save'));
      await _settle(tester);
      expect(account.log, ['rename:YO Voice Official']);
      expect(backend.manage, isEmpty);
      expect(find.text('Nie udało się zapisać zmian'), findsOneWidget);
      expect(find.text('Tej nazwy nie można użyć dla strony.'), findsOneWidget);
      // Still here, still unsaved.
      expect(find.byType(PageEditScreen), findsOneWidget);
      expect(_saveEnabled(tester), isTrue);
    });

    testWidgets('the 30-day cooldown locks the name and says until when', (
      tester,
    ) async {
      final backend = _Backend();
      await _pump(
        tester,
        _edit(
          backend,
          account: _Account(
            profile: _profile(
              nameChangedAt: _now.subtract(const Duration(days: 9)),
            ),
          ),
        ),
      );
      final field = tester.widget<TextField>(_key('page-edit-name'));
      expect(field.readOnly, isTrue);
      // 24 September + 30 days, with its year.
      expect(
        find.textContaining(RegExp(r'^Nazwę zmienisz ponownie 24.*2026\.$')),
        findsOneWidget,
      );
    });

    testWidgets('a cooldown answered by the server restores the stored name', (
      tester,
    ) async {
      final backend = _Backend();
      final next = _now.add(const Duration(days: 12));
      final account = _Account(
        renameError: DisplayNameChangeException(
          DisplayNameChangeFailure.cooldown,
          'cooldown',
          nextDisplayNameChangeAt: next,
        ),
      );
      await _pump(tester, _edit(backend, account: account));
      await _type(tester, 'page-edit-name', 'Ziarno Oliwa');
      await tester.tap(_key('page-edit-save'));
      await _settle(tester);
      expect(_text(tester, 'page-edit-name'), 'Kawiarnia Ziarno');
      expect(tester.widget<TextField>(_key('page-edit-name')).readOnly, isTrue);
      expect(find.text('Nie udało się zapisać zmian'), findsOneWidget);
      expect(backend.manage, isEmpty);
    });

    testWidgets('a later step failing says what was already saved', (
      tester,
    ) async {
      final backend = _Backend({
        'managePageV1': (_) => throw _refusal('unavailable'),
      });
      final account = _Account();
      await _pump(tester, _edit(backend, account: account));
      await _type(tester, 'page-edit-name', 'Ziarno Oliwa');
      await _type(tester, 'page-edit-description', 'Nowy opis.');
      await tester.tap(_key('page-edit-save'));
      await _settle(tester);
      expect(
        find.text('Część zmian została zapisana, ale nie wszystkie'),
        findsOneWidget,
      );
      expect(
        find.text('Brak połączenia. Sprawdź internet i spróbuj ponownie.'),
        findsOneWidget,
      );
      // The name is stored: a retry sends only what is still unsaved.
      expect(_text(tester, 'page-edit-name'), 'Ziarno Oliwa');
      backend.handlers.remove('managePageV1');
      account.log.clear();
      await _reveal(tester, _key('page-edit-save'));
      await tester.tap(_key('page-edit-save'));
      await _settle(tester);
      expect(account.log, isEmpty);
      expect(backend.manage.last['description'], 'Nowy opis.');
      expect(find.byType(PageEditScreen), findsNothing);
    });

    testWidgets('a picture that cannot be uploaded keeps the form open', (
      tester,
    ) async {
      final backend = _Backend();
      final account = _Account(
        uploadError: StateError('network'),
        pick: (kind) => PickedProfileImage(
          kind: kind,
          bytes: _pixel,
          format: ProfileImageFormat.jpeg,
        ),
      );
      await _pump(tester, _edit(backend, account: account));
      await tester.tap(_key('page-edit-photo'));
      await _settle(tester);
      await tester.tap(_key('page-edit-save'));
      await _settle(tester);
      expect(
        find.text(
          'Nie udało się przesłać obrazu. Sprawdź połączenie i spróbuj '
          'ponownie.',
        ),
        findsOneWidget,
      );
      expect(_key('page-face-local'), findsOneWidget);
      expect(_saveEnabled(tester), isTrue);
    });
  });

  group('leaving', () {
    testWidgets('Back with unsaved edits asks; "Wróć do edycji" stays, '
        '"Odrzuć" leaves without saving', (tester) async {
      final backend = _Backend();
      await _pump(tester, _edit(backend));
      await _type(tester, 'page-edit-description', 'Nowy opis.');
      await tester.tap(_key('page-edit-back'));
      await _settle(tester);
      expect(find.text('Odrzucić zmiany?'), findsOneWidget);
      await tester.tap(find.text('Wróć do edycji'));
      await _settle(tester);
      expect(find.byType(PageEditScreen), findsOneWidget);
      expect(_text(tester, 'page-edit-description'), 'Nowy opis.');

      // System Back takes the same path.
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(find.text('Odrzucić zmiany?'), findsOneWidget);
      await tester.tap(_key('page-confirm-action'));
      await _settle(tester);
      expect(find.byType(PageEditScreen), findsNothing);
      expect(backend.calls, isEmpty);
    });
  });

  group('following the server', () {
    testWidgets('a clean form takes the stored values; unsaved edits are '
        'kept', (tester) async {
      final backend = _Backend();
      final access = StreamController<PageAccessState>();
      addTearDown(access.close);
      await _pump(tester, _edit(backend, access: () => access.stream));
      // Nothing resolved yet: the loading state, with Back.
      expect(_key('page-edit-name'), findsNothing);
      expect(_key('page-edit-back'), findsOneWidget);

      access.add(_state(_own()));
      await _settle(tester);
      expect(_text(tester, 'page-edit-description'), 'Kawa speciality.');

      // The server normalized something (as after a save): a clean form
      // follows it.
      access.add(_state(_own(description: 'Kawa speciality i ciasto.')));
      await _settle(tester);
      expect(
        _text(tester, 'page-edit-description'),
        'Kawa speciality i ciasto.',
      );

      await _type(tester, 'page-edit-description', 'Piszę właśnie…');
      access.add(_state(_own(description: 'Zmienione gdzie indziej.')));
      await _settle(tester);
      expect(_text(tester, 'page-edit-description'), 'Piszę właśnie…');
    });

    testWidgets('an account without a Page gets the plain message', (
      tester,
    ) async {
      await _pump(
        tester,
        _edit(_Backend(), access: () => Stream.value(_state(null))),
      );
      expect(find.text('To konto nie ma strony.'), findsOneWidget);
      expect(_key('page-edit-name'), findsNothing);
    });
  });

  group('read-only and "Wyczyść dane kontaktowe" (ADR-241)', () {
    testWidgets('a lapsed owner reads the form and can clear the contact '
        'details', (tester) async {
      final backend = _Backend();
      await _pump(
        tester,
        _edit(backend, page: _own(status: 'readOnly'), vip: false),
      );
      expect(_key('page-edit-locked'), findsOneWidget);
      expect(find.text('Edycja jest teraz wyłączona'), findsOneWidget);
      expect(
        find.text('Edycja wróci, gdy Premium lub VIP znów będzie aktywne.'),
        findsOneWidget,
      );
      // Nothing can be changed or saved, and no camera is offered.
      expect(_key('page-edit-save-action'), findsNothing);
      expect(_key('page-edit-cover'), findsNothing);
      expect(_key('page-edit-photo'), findsNothing);
      expect(tester.widget<TextField>(_key('page-edit-name')).enabled, isFalse);
      await _reveal(tester, _key('page-edit-clear-contact'));
      expect(
        tester.widget<TextField>(_key('page-edit-website')).enabled,
        isFalse,
      );
      expect(_text(tester, 'page-edit-website'), 'https://kawiarniaziarno.pl');
      expect(
        find.text(
          'Dane kontaktowe zostają zapisane, gdy strona jest wstrzymana. '
          'Możesz je usunąć w każdej chwili.',
        ),
        findsOneWidget,
      );

      await tester.tap(_key('page-edit-clear-contact'));
      await _settle(tester);
      expect(find.text('Wyczyścić dane kontaktowe?'), findsOneWidget);
      await tester.tap(_key('page-confirm-action'));
      await _settle(tester);
      expect(backend.manage, [
        {'requestId': 'pg_test_request_0001', 'op': 'clearContact'},
      ]);
      expect(_text(tester, 'page-edit-website'), '');
      expect(_text(tester, 'page-edit-phone'), '');
      expect(find.text('Dane kontaktowe wyczyszczone'), findsOneWidget);
      expect(_key('page-edit-save-bar'), findsNothing);
    });

    testWidgets('a suspended Page says so; cancelling the question sends '
        'nothing', (tester) async {
      final backend = _Backend();
      await _pump(tester, _edit(backend, page: _own(suspended: true)));
      expect(
        find.text(
          'Strona jest zawieszona przez moderację, więc nie można jej '
          'edytować.',
        ),
        findsOneWidget,
      );
      await _reveal(tester, _key('page-edit-clear-contact'));
      await tester.tap(_key('page-edit-clear-contact'));
      await _settle(tester);
      await tester.tap(find.text('Anuluj'));
      await _settle(tester);
      expect(backend.manage, isEmpty);
      expect(_text(tester, 'page-edit-website'), 'https://kawiarniaziarno.pl');
    });

    testWidgets('a refused clear keeps the fields and says it failed', (
      tester,
    ) async {
      final backend = _Backend({
        'managePageV1': (_) => throw _refusal('invalid-argument'),
      });
      await _pump(
        tester,
        _edit(backend, page: _own(status: 'hidden'), vip: false),
      );
      await _reveal(tester, _key('page-edit-clear-contact'));
      await tester.tap(_key('page-edit-clear-contact'));
      await _settle(tester);
      await tester.tap(_key('page-confirm-action'));
      await _settle(tester);
      expect(find.text('Nie udało się. Spróbuj ponownie.'), findsOneWidget);
      expect(_text(tester, 'page-edit-website'), 'https://kawiarniaziarno.pl');
    });

    testWidgets('nothing stored: no clear action', (tester) async {
      await _pump(
        tester,
        _edit(_Backend(), page: _own(business: PageBusinessInfo.empty)),
      );
      await _reveal(tester, _key('page-edit-legal'));
      expect(_key('page-edit-clear-contact'), findsNothing);
    });

    testWidgets('a lapsed community Page is read-only with no clear action', (
      tester,
    ) async {
      await _pump(
        tester,
        _edit(
          _Backend(),
          page: _own(kind: PageKind.community, status: 'readOnly'),
          vip: false,
        ),
      );
      await _reveal(tester, _key('page-edit-linked-server'));
      expect(_key('page-edit-clear-contact'), findsNothing);
      expect(_key('page-edit-locked'), findsOneWidget);
    });

    testWidgets('an editable Page with stored contact details offers it too', (
      tester,
    ) async {
      final backend = _Backend();
      await _pump(tester, _edit(backend));
      await _reveal(tester, _key('page-edit-clear-contact'));
      await tester.tap(_key('page-edit-clear-contact'));
      await _settle(tester);
      await tester.tap(_key('page-confirm-action'));
      await _settle(tester);
      expect(backend.manage.single['op'], 'clearContact');
      // What was cleared is not an unsaved change.
      expect(_key('page-edit-save-bar'), findsNothing);
    });
  });

  group('layouts', () {
    testWidgets('phone: one column, the cover edge to edge, no preview', (
      tester,
    ) async {
      await _pump(tester, _edit(_Backend()));
      expect(find.byType(AppBar), findsOneWidget);
      expect(_key('page-edit-preview-card'), findsNothing);
      expect(_key('page-edit-preview-column'), findsNothing);
      final photos = tester.getRect(_key('page-edit-photos'));
      expect(photos.left, 0);
      expect(photos.width, 390);
      expect(
        photos.height,
        PageEditScreen.phoneCover +
            PageEditScreen.face -
            PageEditScreen.faceOverlap +
            PageEditScreen.faceRing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('tablet: one 640 column under a collapsible preview card', (
      tester,
    ) async {
      await _pump(tester, _edit(_Backend()), size: const Size(768, 1024));
      expect(_key('page-edit-preview-card'), findsOneWidget);
      expect(tester.getSize(_key('page-edit-preview-card')).width, 640);
      expect(_key('page-edit-preview-header'), findsOneWidget);
      expect(_key('page-edit-preview-column'), findsNothing);
      await tester.tap(_key('page-edit-preview-toggle'));
      await _settle(tester);
      expect(_key('page-edit-preview-header'), findsNothing);
      expect(find.byTooltip('Rozwiń podgląd'), findsOneWidget);
      await tester.tap(_key('page-edit-preview-toggle'));
      await _settle(tester);
      expect(_key('page-edit-preview-header'), findsOneWidget);
      expect(find.byTooltip('Zwiń podgląd'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide: the form (560) beside a preview that stands still '
        'and follows what is typed', (tester) async {
      await _pump(tester, _edit(_Backend()), size: const Size(1280, 900));
      final form = tester.getRect(_key('page-edit-form-column'));
      final side = tester.getRect(_key('page-edit-preview-column'));
      expect(form.width, PageEditScreen.formWidth);
      expect(side.width, PageEditScreen.previewWidth);
      expect(side.left, greaterThan(form.right));
      expect(side.right - form.left, PageEditScreen.splitFrame);
      expect(_key('page-edit-preview-wall'), findsOneWidget);
      expect(_key('page-edit-preview-header'), findsOneWidget);
      expect(
        find.text('Tak zobaczą stronę inni. Podgląd zmienia się, gdy piszesz.'),
        findsOneWidget,
      );

      // Live: the typed name and description show in the preview.
      await tester.enterText(_key('page-edit-name'), 'Ziarno Oliwa');
      await _type(tester, 'page-edit-description', 'Kawa prosto z pieca.');
      expect(
        find.descendant(
          of: _key('page-edit-preview-header'),
          matching: find.textContaining('Ziarno Oliwa', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _key('page-edit-preview-header'),
          matching: find.text('Kawa prosto z pieca.'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _key('page-edit-preview-header'),
          matching: find.textContaining('128 obserwujących'),
        ),
        findsOneWidget,
      );

      // The preview stays where it is while the form scrolls.
      final before = tester.getRect(_key('page-edit-preview-wall'));
      tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: _key('page-edit-scroll'),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .jumpTo(400);
      await tester.pump();
      expect(tester.getRect(_key('page-edit-preview-wall')), before);
      expect(tester.getRect(_key('page-edit-form-column')).top, form.top - 400);
      // A picture of the result, never a control.
      expect(
        find.descendant(
          of: _key('page-edit-preview-column'),
          matching: find.byType(PageProfilePreviewHeader),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('in the desktop shell slot: no app bar, a pinned header with '
        'Back, Anuluj and Zapisz zmiany', (tester) async {
      final backend = _Backend();
      await _pump(
        tester,
        _edit(backend),
        size: const Size(1176, 900),
        desktop: true,
      );
      expect(find.byType(AppBar), findsNothing);
      expect(_key('page-edit-back'), findsOneWidget);
      expect(_key('page-edit-cancel'), findsOneWidget);
      // "Zapisz zmiany" is always there, off until something changed.
      expect(_saveEnabled(tester), isFalse);
      expect(_key('page-edit-unsaved'), findsNothing);
      final save = tester.getRect(_key('page-edit-save'));

      await _type(tester, 'page-edit-description', 'Nowy opis.');
      expect(_saveEnabled(tester), isTrue);
      expect(find.text('Masz niezapisane zmiany'), findsOneWidget);
      // The header does not scroll with the form.
      expect(tester.getRect(_key('page-edit-save')).top, save.top);

      // Anuluj asks before dropping the edits.
      await tester.tap(_key('page-edit-cancel'));
      await _settle(tester);
      expect(find.text('Odrzucić zmiany?'), findsOneWidget);
      await tester.tap(find.text('Wróć do edycji'));
      await _settle(tester);

      await tester.tap(_key('page-edit-save'));
      await _settle(tester);
      expect(backend.manage.single['description'], 'Nowy opis.');
      expect(find.byType(PageEditScreen), findsNothing);
    });

    testWidgets('200 % text never overflows, at any width', (tester) async {
      for (final (size, desktop) in const [
        (Size(320, 640), false),
        (Size(390, 844), false),
        (Size(768, 1024), false),
        (Size(1176, 900), true),
      ]) {
        await _pump(
          tester,
          _edit(_Backend()),
          size: size,
          textScale: 2,
          desktop: desktop,
        );
        await _type(tester, 'page-edit-description', 'Nowy opis.');
        await _reveal(tester, _key('page-edit-legal'));
        expect(tester.takeException(), isNull, reason: '$size');
        await _settle(tester);
        expect(tester.takeException(), isNull, reason: '$size');
      }
    });

    testWidgets('right to left and Pearl lay out without errors', (
      tester,
    ) async {
      await _pump(
        tester,
        _edit(_Backend()),
        locale: const Locale('ar'),
        pearl: true,
      );
      expect(
        Directionality.of(tester.element(_key('page-edit-photos'))),
        TextDirection.rtl,
      );
      // The photo sits at the start edge (the right, here).
      final face = tester.getRect(_key('page-edit-photo'));
      expect(face.right, greaterThan(390 - 20));
      await _type(tester, 'page-edit-description', 'Nowy opis.');
      expect(tester.takeException(), isNull);
    });

    testWidgets('right to left, wide: the form starts the row (the right) '
        'and the preview ends it', (tester) async {
      await _pump(
        tester,
        _edit(_Backend()),
        size: const Size(1176, 900),
        locale: const Locale('ar'),
        desktop: true,
      );
      final form = tester.getRect(_key('page-edit-form-column'));
      final side = tester.getRect(_key('page-edit-preview-column'));
      expect(form.width, PageEditScreen.formWidth);
      expect(side.width, PageEditScreen.previewWidth);
      expect(form.left, greaterThan(side.right));
      expect(form.right - side.left, PageEditScreen.splitFrame);
      // The header mirrors with it: Back above the form, Save above the
      // preview.
      expect(
        tester.getCenter(_key('page-edit-back')).dx,
        greaterThan(form.left),
      );
      expect(tester.getCenter(_key('page-edit-save')).dx, lessThan(side.right));
      expect(tester.takeException(), isNull);
    });
  });

  group('inside Treści on desktop (the real ContentScreen)', () {
    _Backend contentBackend() => _Backend({
      PagesService.feedCallable: (_) => {
        'schemaVersion': 1,
        'posts': <Object>[],
        'nextCursor': null,
        'hasMore': false,
        'suggestions': <Object>[],
      },
      PagesService.findCallable: (_) => {
        'schemaVersion': 1,
        'pages': <Object>[],
        'nextCursor': null,
        'hasMore': false,
      },
      PagesService.mediaAccessCallable: (_) => {'grants': <Object>[]},
    });

    /// Pumps Treści at 1440 and opens "Edytuj stronę" on its own navigator,
    /// the way the Page profile does.
    Future<_Backend> pumpContent(
      WidgetTester tester, {
      Listenable? reselect,
      ValueNotifier<PageLinkTarget?>? link,
    }) async {
      final backend = contentBackend();
      await _pump(
        tester,
        Scaffold(
          body: ContentScreen(
            isRootTab: true,
            service: _service(backend),
            accessStream: () => Stream.value(_state(_own())),
            localStore: MemoryPagesLocalStore(),
            userId: 'me',
            userDisplayName: 'Kawiarnia Ziarno',
            reselect: reselect,
            pendingPageLink: link,
            clock: () => _now,
            // A Page opened from a link is one more route of Treści.
            flows: PagesFlows(
              openPage: (context, {required pageId, displayName}) =>
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      settings: RouteSettings(name: 'pages/page/$pageId'),
                      builder: (_) => Scaffold(body: Text('page $pageId')),
                    ),
                  ),
            ),
          ),
        ),
        size: const Size(1440, 900),
      );
      return backend;
    }

    Future<void> openEdit(WidgetTester tester, _Backend backend) async {
      final navigator = tester.state<NavigatorState>(
        find.descendant(
          of: find.byType(ContentScreen),
          matching: find.byType(Navigator),
        ),
      );
      unawaited(
        openPageEdit(navigator.context, builder: (_) => _edit(backend)),
      );
      await _settle(tester);
    }

    testWidgets('the 240 panel steps aside for the form and comes back', (
      tester,
    ) async {
      final backend = await pumpContent(tester);
      expect(_key('content-panel-all-posts'), findsOneWidget);

      await openEdit(tester, backend);
      expect(find.byType(PageEditScreen), findsOneWidget);
      // Inside the shell's slot: no app bar, the form beside its preview.
      expect(find.byType(AppBar), findsNothing);
      expect(_key('content-panel-all-posts'), findsNothing);
      expect(
        tester.getSize(_key('page-edit-form-column')).width,
        PageEditScreen.formWidth,
      );
      expect(_key('page-edit-preview-column'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(_key('page-edit-back'));
      await _settle(tester);
      expect(find.byType(PageEditScreen), findsNothing);
      expect(_key('content-panel-all-posts'), findsOneWidget);
    });

    testWidgets('re-selecting Treści asks before dropping unsaved edits; a '
        'clean form just closes', (tester) async {
      final reselect = ValueNotifier<int>(0);
      addTearDown(reselect.dispose);
      final backend = await pumpContent(tester, reselect: reselect);
      await openEdit(tester, backend);
      await _type(tester, 'page-edit-description', 'Nowy opis.');

      reselect.value++;
      await _settle(tester);
      expect(find.text('Odrzucić zmiany?'), findsOneWidget);
      await tester.tap(find.text('Wróć do edycji'));
      await _settle(tester);
      expect(find.byType(PageEditScreen), findsOneWidget);
      expect(_text(tester, 'page-edit-description'), 'Nowy opis.');

      reselect.value++;
      await _settle(tester);
      await tester.tap(_key('page-confirm-action'));
      await _settle(tester);
      expect(find.byType(PageEditScreen), findsNothing);
      expect(_key('content-panel-all-posts'), findsOneWidget);
      expect(backend.manage, isEmpty);

      // Nothing to lose: no question.
      await openEdit(tester, backend);
      reselect.value++;
      await _settle(tester);
      expect(find.text('Odrzucić zmiany?'), findsNothing);
      expect(find.byType(PageEditScreen), findsNothing);
    });

    testWidgets('a Page link that arrives while editing opens over the form '
        'and keeps the unsaved edits', (tester) async {
      final link = ValueNotifier<PageLinkTarget?>(null);
      addTearDown(link.dispose);
      final backend = await pumpContent(tester, link: link);
      await openEdit(tester, backend);
      await _type(tester, 'page-edit-description', 'Nowy opis.');

      link.value = const PageLinkTarget(pageId: 'glina');
      await _settle(tester);
      expect(find.text('page glina'), findsOneWidget);
      // A second link replaces the first Page, never the form under it.
      link.value = const PageLinkTarget(pageId: 'chor');
      await _settle(tester);
      expect(find.text('page chor'), findsOneWidget);
      expect(find.text('page glina', skipOffstage: false), findsNothing);
      expect(
        find.byType(PageEditScreen, skipOffstage: false),
        findsOneWidget,
      );

      // Back from the Page: the form, as it was left.
      tester
          .state<NavigatorState>(
            find.descendant(
              of: find.byType(ContentScreen),
              matching: find.byType(Navigator),
            ),
          )
          .pop();
      await _settle(tester);
      expect(find.byType(PageEditScreen), findsOneWidget);
      expect(_text(tester, 'page-edit-description'), 'Nowy opis.');
    });
  });

  group('service', () {
    test('clearPageContact sends the exact safety op', () async {
      final backend = _Backend();
      final result = await _service(backend).clearPageContact();
      expect(backend.manage, [
        {'requestId': 'pg_test_request_0001', 'op': 'clearContact'},
      ]);
      expect(result.pageId, 'me');
    });

    test('a reserved Page name is its own rename failure', () {
      final failure = ProfileService.displayNameExceptionForTesting(
        _refusal('failed-precondition', 'pageNameReserved'),
      );
      expect(failure.failure, DisplayNameChangeFailure.nameNotAllowed);
      // Every other failed-precondition keeps its old reading.
      expect(
        ProfileService.displayNameExceptionForTesting(
          _refusal('failed-precondition', 'display-name-state-invalid'),
        ).failure,
        DisplayNameChangeFailure.unavailable,
      );
    });
  });

  // Keep this group LAST: it loads the app's real font (Inter), which stays
  // loaded for the rest of the file, so the label widths it measures are the
  // ones a reader gets. Scripts Inter has no glyphs for (Arabic, Hebrew,
  // CJK, Thai, Devanagari, Bengali) fall back to the test font's 1 em boxes,
  // which are wider than the real glyphs: passing with them is the safe side.
  group('every language', () {
    setUpAll(() async {
      final inter = FontLoader('Inter')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('assets/fonts/InterVariable.ttf').readAsBytesSync(),
            ),
          ),
        );
      await inter.load();
    });

    testWidgets('the desktop header and the phone save bar hold their '
        'labels in all 43 locales, also at a larger text size', (tester) async {
      expect(AppLocalizations.supportedLocales, hasLength(43));
      for (final locale in AppLocalizations.supportedLocales) {
        for (final (size, desktop, scale) in const [
          // The narrowest slot that still gets the one-line header.
          (Size(1000, 800), true, 1.0),
          (Size(1000, 800), true, 1.3),
          (Size(760, 800), true, 1.3),
          (Size(390, 844), false, 1.0),
          (Size(390, 844), false, 2.0),
        ]) {
          await _pump(
            tester,
            _edit(_Backend()),
            size: size,
            textScale: scale,
            locale: locale,
            desktop: desktop,
          );
          await _type(tester, 'page-edit-name', 'Ziarno Oliwa');
          await _settle(tester);
          final reason = '$locale $size x$scale';
          expect(tester.takeException(), isNull, reason: reason);
          // The whole save button is on screen: nothing pushed it out.
          final save = tester.getRect(_key('page-edit-save'));
          expect(save.left, greaterThanOrEqualTo(0), reason: reason);
          expect(save.right, lessThanOrEqualTo(size.width), reason: reason);
          // Its label is never cut short.
          final label = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: _key('page-edit-save'),
              matching: find.byType(RichText),
            ),
          );
          expect(label.didExceedMaxLines, isFalse, reason: reason);
          expect(
            label.size.width,
            lessThanOrEqualTo(save.width),
            reason: reason,
          );
        }
      }
    });
  });
}
