// Create a Page on a phone, opened from Treści inside the real shell chrome
// (MoreDestinationHost mounts the production YoFloatingNavigationDock; the
// MainShell itself is not pumpable, see desktop_shell_test.dart).
//
// Owner report 2026-09-29: after every field was filled, something stayed
// over the form and "Dalej" could not be reached. Pinned here:
//   * the create flow is a full-screen route over the shell, so the dock is
//     never drawn over it (it is offstage, not merely behind);
//   * with the software keyboard up (336 px on 390x844, UI.md's reference
//     surface) Dalej and the Done bar ride on top of the keyboard instead of
//     staying pinned behind it (ADR-169 placement 1);
//   * Back from step 1 lands on Treści with the dock and Treści selected.
// Also decision 2 of 2026-09-29: an account with paid Premium and no VIP
// grant is offered the form, not the upsell.
import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';
import 'package:yovoice/features/pages/data/services/page_access_service.dart';
import 'package:yovoice/features/pages/data/services/pages_local_store.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/pages_flows.dart';
import 'package:yovoice/features/pages/presentation/screens/content_screen.dart';
import 'package:yovoice/features/pages/presentation/screens/create_page_screen.dart';
import 'package:yovoice/features/profile/data/models/profile_visibility.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

final DateTime _now = DateTime.utc(2026, 9, 29, 12);
const Size _phone = Size(390, 844);
const double _keyboard = 336;

UserProfile _profile({bool ageVerified = true}) => UserProfile(
  uid: 'me',
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
  creatorAgeVerified: ageVerified,
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

class _Backend {
  final List<(String, Map<String, Object?>)> calls = [];

  Future<Object?> call(String name, Map<String, Object?> payload) async {
    calls.add((name, payload));
    if (name == PagesService.feedCallable) {
      return {
        'schemaVersion': 1,
        'posts': const <Object?>[],
        'nextCursor': null,
        'hasMore': false,
        'suggestions': [
          {
            'pageId': 'chor',
            'displayName': 'Chór Gaudium',
            'kind': 'community',
            'category': 'music',
            'followerCount': 210,
            'onYoVoiceSinceMs': _now.millisecondsSinceEpoch,
            'viewerFollows': false,
            'lastPostAtMs': null,
          },
        ],
      };
    }
    if (name == PagesService.findCallable) {
      return {
        'schemaVersion': 1,
        'pages': const <Object?>[],
        'nextCursor': null,
        'hasMore': false,
      };
    }
    if (name == 'managePageV1') return {'ok': true, 'pageId': 'me'};
    throw FirebaseFunctionsException(code: 'not-found', message: 'none');
  }
}

PagesService _service(_Backend backend) => PagesService(
  invoker: backend.call,
  requestIdFactory: () => 'pg_test_request_0001',
  clock: () => _now,
);

/// Paid Premium, no VIP grant, no Page (decision 2, 2026-09-29).
Stream<PageAccessState> _paidOnly() => Stream<PageAccessState>.value(
  const PageAccessState(
    resolved: true,
    hasVipGrant: false,
    hasPaidPremium: true,
    ownPage: null,
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _key(String key) => find.byKey(ValueKey(key));

/// Treści again: the dock on screen at the bottom of the window, its Czaty
/// cell reachable, Treści selected.
void _expectTresciWithDock(WidgetTester tester) {
  final dock = find.byType(YoFloatingNavigationDock);
  expect(dock, findsOneWidget);
  expect(tester.getRect(dock).bottom, _phone.height);
  expect(_key('yo-destination-2').hitTestable(), findsOneWidget);
  final content = tester.widget<Semantics>(
    find
        .ancestor(
          of: _key('yo-destination-3'),
          matching: find.byType(Semantics),
        )
        .first,
  );
  expect(content.properties.selected, isTrue);
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    160,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

Future<void> _pumpTresci(
  WidgetTester tester,
  _Backend backend, {
  bool ageVerified = true,
}) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final service = _service(backend);
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
          accessStream: _paidOnly,
          localStore: MemoryPagesLocalStore(),
          userId: 'me',
          userDisplayName: 'Ola',
          clock: () => _now,
          flows: PagesFlows(
            openPage: (context, {required pageId, displayName}) async {},
            openCreatePage: (context) => openCreatePageFlow(
              context,
              accessStream: _paidOnly,
              screenBuilder: (_) => CreatePageScreen(
                service: service,
                profileStream: () =>
                    Stream.value(_profile(ageVerified: ageVerified)),
                serverStream: () => Stream.value(const []),
                userId: 'me',
                clock: () => _now,
              ),
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
}

void main() {
  setUp(() {
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
      fetchOverride: (uids) async => {
        for (final uid in uids)
          uid: {'staffRole': 'user', 'isVip': true, 'page': null},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  testWidgets('390x844: the dock never overlaps Create, and Dalej stays above '
      'the keyboard once every field is filled', (tester) async {
    addTearDown(tester.view.resetViewInsets);
    final backend = _Backend();
    await _pumpTresci(tester, backend);

    // Treści with the real six-tab dock, Treści selected, E2 for a paid
    // Premium account without a grant.
    final dock = find.byType(YoFloatingNavigationDock);
    expect(dock, findsOneWidget);
    expect(tester.getRect(dock).bottom, _phone.height);
    expect(_key('pages-e2'), findsOneWidget);

    await tester.tap(find.text('Utwórz swoją stronę'));
    await _settle(tester);

    // Step 1: a full-screen route over the shell. The dock is offstage,
    // Dalej is on screen and nothing covers it.
    expect(find.text('Krok 1 z 3'), findsOneWidget);
    expect(dock, findsNothing);
    expect(_key('pages-upsell'), findsNothing);
    var next = tester.getRect(_key('create-primary'));
    expect(next.bottom, lessThanOrEqualTo(_phone.height));
    expect(_key('create-primary').hitTestable(), findsOneWidget);

    await tester.tap(_key('create-primary'));
    await _settle(tester);
    expect(find.text('Krok 2 z 3'), findsOneWidget);

    // Step 2, every field, with the keyboard up from the first keystroke.
    await tester.tap(_key('create-category'));
    await _settle(tester);
    await tester.tap(_key('page-category-cafe_restaurant'));
    await _settle(tester);
    const values = <String, String>{
      'create-description': 'Kawa speciality.\nPalimy na miejscu.',
      'create-website': 'https://kawiarniaziarno.pl',
      'create-email': 'kontakt@kawiarniaziarno.pl',
      'create-phone': '+48 58 555 01 27',
      'create-address': 'ul. Grunwaldzka 57, Gdańsk',
      'create-hours': 'Pn–Pt 7:00–19:00',
      'create-legal': 'Kawiarnia Ziarno sp. z o.o.\nKRS 0000123456',
    };
    for (final entry in values.entries) {
      await _reveal(tester, _key(entry.key));
      await tester.tap(_key(entry.key));
      tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
      await tester.pump();
      await tester.enterText(_key(entry.key), entry.value);
      await tester.pump();
    }
    await _reveal(tester, _key('create-consent'));
    await tester.tap(_key('create-consent'));
    await tester.pump();

    // The owner's moment: all filled, the last long-form field still has
    // the keyboard. Dalej and Done sit on the keyboard, not behind it.
    await _reveal(tester, _key('create-legal'));
    await tester.tap(_key('create-legal'));
    await _settle(tester);
    expect(dock, findsNothing);
    final keyboardTop = _phone.height - _keyboard;
    next = tester.getRect(_key('create-primary'));
    expect(next.bottom, lessThanOrEqualTo(keyboardTop));
    expect(_key('create-primary').hitTestable(), findsOneWidget);
    final done = tester.getRect(_key('yo-keyboard-done-bar'));
    expect(done.bottom, lessThanOrEqualTo(next.top + .5));
    expect(done.top, greaterThan(0));

    // Dalej works straight from the keyboard.
    await tester.tap(_key('create-primary'));
    await _settle(tester);
    expect(find.text('Krok 3 z 3'), findsOneWidget);
    tester.view.viewInsets = FakeViewPadding.zero;
    await _settle(tester);
    expect(
      find.descendant(
        of: _key('create-primary'),
        matching: find.text('Opublikuj stronę'),
      ),
      findsOneWidget,
    );
    next = tester.getRect(_key('create-primary'));
    expect(next.bottom, lessThanOrEqualTo(_phone.height));
    expect(_key('create-primary').hitTestable(), findsOneWidget);
    expect(dock, findsNothing);

    // Back walks the steps, then returns to Treści with its dock.
    for (var i = 0; i < 3; i++) {
      await tester.tap(_key('create-back'));
      await _settle(tester);
    }
    expect(find.text('Krok 1 z 3'), findsNothing);
    _expectTresciWithDock(tester);
    expect(_key('pages-e2'), findsOneWidget);
    expect(backend.calls.where((c) => c.$1 == 'managePageV1'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('390x844, a Community Page (every text field is multi-line): '
      'Gotowe closes the keyboard, the pickers open over everything and '
      'Opublikuj stronę is reachable', (tester) async {
    addTearDown(tester.view.resetViewInsets);
    final backend = _Backend();
    await _pumpTresci(tester, backend, ageVerified: false);
    final dock = find.byType(YoFloatingNavigationDock);
    final keyboardTop = _phone.height - _keyboard;

    await tester.tap(find.text('Utwórz swoją stronę'));
    await _settle(tester);
    await tester.tap(_key('create-kind-community'));
    await tester.pump();
    await tester.tap(_key('create-primary'));
    await _settle(tester);
    expect(find.text('Krok 2 z 3'), findsOneWidget);
    expect(dock, findsNothing);

    // The topic picker is a sheet over the whole window.
    await tester.tap(_key('create-category'));
    await _settle(tester);
    expect(
      tester.getRect(find.byType(BottomSheet)).bottom,
      moreOrLessEquals(_phone.height),
    );
    await tester.tap(_key('page-category-sport'));
    await _settle(tester);

    const values = <String, String>{
      'create-description': 'Biegamy razem w soboty.\nStart spod molo.',
      'create-rules': 'Bez reklam w komentarzach.\nSzanujemy tempo innych.',
    };
    for (final entry in values.entries) {
      await _reveal(tester, _key(entry.key));
      await tester.tap(_key(entry.key));
      tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
      await tester.pump();
      await tester.enterText(_key(entry.key), entry.value);
      await tester.pump();
    }

    // Return is a line break in both fields, so the keyboard has no way out
    // of its own: Gotowe and Dalej ride on top of it.
    await _settle(tester);
    var next = tester.getRect(_key('create-primary'));
    expect(next.bottom, lessThanOrEqualTo(keyboardTop));
    expect(_key('create-primary').hitTestable(), findsOneWidget);
    final done = _key('yo-keyboard-done');
    expect(done.hitTestable(), findsOneWidget);
    expect(
      tester.getRect(_key('yo-keyboard-done-bar')).bottom,
      lessThanOrEqualTo(next.top + .5),
    );
    await tester.tap(done);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.context?.widget,
      isNot(isA<EditableText>()),
      reason: 'Gotowe takes the focus out of the field',
    );
    // The system keyboard follows the focus down.
    tester.view.viewInsets = FakeViewPadding.zero;
    await _settle(tester);
    expect(_key('yo-keyboard-done-bar'), findsNothing);
    next = tester.getRect(_key('create-primary'));
    expect(next.bottom, lessThanOrEqualTo(_phone.height));
    expect(_key('create-primary').hitTestable(), findsOneWidget);

    // The linked-server picker: a sheet down to the bottom of the window.
    await _reveal(tester, _key('create-linked-server'));
    await tester.tap(_key('create-linked-server'));
    await _settle(tester);
    expect(
      tester.getRect(find.byType(BottomSheet)).bottom,
      moreOrLessEquals(_phone.height),
    );
    expect(dock, findsNothing);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byType(BottomSheet), findsNothing);

    // The birth date (no verified age on this account): the date picker
    // dialog, its OK in reach.
    await _reveal(tester, _key('create-birth-date'));
    await tester.tap(_key('create-birth-date'));
    await _settle(tester);
    expect(find.byType(DatePickerDialog), findsOneWidget);
    final ok = find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.widgetWithText(TextButton, 'OK'),
    );
    expect(ok.hitTestable(), findsOneWidget);
    await tester.tap(ok);
    await _settle(tester);
    expect(find.byType(DatePickerDialog), findsNothing);

    await _reveal(tester, _key('create-consent'));
    await tester.tap(_key('create-consent'));
    await tester.pump();
    await tester.tap(_key('create-primary'));
    await _settle(tester);
    expect(find.text('Krok 3 z 3'), findsOneWidget);
    final publish = find.descendant(
      of: _key('create-primary'),
      matching: find.text('Opublikuj stronę'),
    );
    expect(publish, findsOneWidget);
    next = tester.getRect(_key('create-primary'));
    expect(next.top, greaterThanOrEqualTo(0));
    expect(next.bottom, lessThanOrEqualTo(_phone.height));
    expect(_key('create-primary').hitTestable(), findsOneWidget);
    expect(dock, findsNothing);

    for (var i = 0; i < 3; i++) {
      await tester.tap(_key('create-back'));
      await _settle(tester);
    }
    _expectTresciWithDock(tester);
    expect(backend.calls.where((c) => c.$1 == 'managePageV1'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('820x1180 touch tablet: at rest the form keeps the home '
      'indicator inset; with the keyboard up Gotowe rides on it, and Dalej '
      'is reachable after Gotowe', (tester) async {
    const tablet = Size(820, 1180);
    const homeIndicator = 20.0;
    const keyboard = 300.0;
    tester.view.physicalSize = tablet;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: homeIndicator);
    addTearDown(tester.view.reset);
    final backend = _Backend();
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
        home: CreatePageScreen(
          service: _service(backend),
          profileStream: () => Stream.value(_profile()),
          serverStream: () => Stream.value(const []),
          userId: 'me',
          clock: () => _now,
        ),
      ),
    );
    await _settle(tester);
    await tester.ensureVisible(_key('create-primary'));
    await tester.pump();
    await tester.tap(_key('create-primary'));
    await _settle(tester);
    expect(_key('create-category'), findsOneWidget, reason: 'step 2');

    // At rest nothing is attached under the form, so the body's SafeArea
    // keeps the home-indicator inset (Scaffold hands it to any
    // bottomNavigationBar, even an empty one).
    final form = _key('create-step-2');
    expect(_key('yo-keyboard-done-bar'), findsNothing);
    expect(
      tester.getRect(form).bottom,
      lessThanOrEqualTo(tablet.height - homeIndicator),
    );

    // The keyboard comes up for a long-form field (Return is a line break).
    await _reveal(tester, _key('create-description'));
    await tester.tap(_key('create-description'));
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    await _settle(tester);
    await tester.enterText(_key('create-description'), 'Kawa.\nPalimy.');
    await _settle(tester);
    final keyboardTop = tablet.height - keyboard;
    final bar = _key('yo-keyboard-done-bar');
    expect(bar, findsOneWidget);
    expect(tester.getRect(bar).bottom, lessThanOrEqualTo(keyboardTop));
    final done = _key('yo-keyboard-done');
    expect(done.hitTestable(), findsOneWidget);
    expect(tester.getRect(form).bottom, lessThanOrEqualTo(keyboardTop));

    await tester.tap(done);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.context?.widget,
      isNot(isA<EditableText>()),
      reason: 'Gotowe takes the focus out of the field',
    );
    tester.view.viewInsets = FakeViewPadding.zero;
    tester.view.padding = const FakeViewPadding(bottom: homeIndicator);
    await _settle(tester);
    expect(bar, findsNothing);
    await _reveal(tester, _key('create-primary'));
    final next = tester.getRect(_key('create-primary'));
    expect(next.bottom, lessThanOrEqualTo(tablet.height - homeIndicator));
    expect(_key('create-primary').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
