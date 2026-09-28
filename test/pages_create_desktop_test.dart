// Create a Page on a wide window (variant C, approved 2026-09-28): from
// 1000 px every step's header (back link, step tabs, title) spans one centred
// 1040 frame, and step 2 splits into the form, with Wróć / Dalej at its foot,
// and a sticky column of two previews ("Na ścianie Treści", "Profil strony")
// with the change-name link. 720-999 keeps the single 720 column, the phone
// keeps its own layout. One-line fields wrap instead of scrolling sideways.
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/screens/create_page_screen.dart';
import 'package:yovoice/features/profile/data/models/profile_visibility.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'support/material_icons_font.dart';

final DateTime _now = DateTime.utc(2026, 9, 28, 12);

const _hours = 'Pn–Pt 7:00–19:00 · Sb–Nd 9:00–18:00';

/// Every step-2 field whose value is one line, with a realistic value.
const _oneLineValues = <String, String>{
  'create-website': 'https://kawiarniaziarno.pl',
  'create-email': 'kontakt@kawiarniaziarno.pl',
  'create-phone': '+48 58 555 01 27',
  'create-address': 'ul. Grunwaldzka 57, Gdańsk',
  'create-hours': _hours,
};

Future<void> _loadFonts() async {
  Future<ByteData> read(String path) async =>
      ByteData.sublistView(File(path).readAsBytesSync());
  final inter = FontLoader('Inter')
    ..addFont(read('assets/fonts/InterVariable.ttf'))
    ..addFont(read('assets/fonts/InterVariable-Italic.ttf'));
  await inter.load();
  await loadMaterialIconsFont();
}

UserProfile _profile({bool ageVerified = false}) => UserProfile(
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
  unlockedTitleIds: const [],
  unlockedTitleTimestamps: const {},
  createdAt: null,
  profileVisibility: ProfileVisibility.public,
);

CreatePageScreen _create({
  bool ageVerified = false,
  Stream<UserProfile> Function()? profile,
}) => CreatePageScreen(
  service: PagesService(
    invoker: (name, payload) async => {'ok': true},
    requestIdFactory: () => 'pg_test_request_0001',
    clock: () => _now,
  ),
  profileStream:
      profile ?? () => Stream.value(_profile(ageVerified: ageVerified)),
  serverStream: () => Stream.value(const []),
  birthDatePicker: (_) async => DateTime(1990, 3, 14),
  userId: 'me',
  clock: () => _now,
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  double textScale = 1,
  bool ageVerified = false,
  Stream<UserProfile> Function()? profile,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: _create(ageVerified: ageVerified, profile: profile),
        ),
      ),
    ),
  );
  await _settle(tester);
}

Finder _key(String key) => find.byKey(ValueKey(key));

Rect _rect(WidgetTester tester, String key) => tester.getRect(_key(key));

/// The page's scroll view: the nearest one around Kategoria.
ScrollPosition _page(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .ancestor(
            of: _key('create-category'),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

Future<void> _toStep2(WidgetTester tester) async {
  await tester.ensureVisible(_key('create-primary'));
  await tester.pump();
  await tester.tap(_key('create-primary'));
  await _settle(tester);
}

void _expectWithin(Rect inner, Rect outer, String reason) {
  expect(inner.left, greaterThanOrEqualTo(outer.left - .5), reason: reason);
  expect(inner.right, lessThanOrEqualTo(outer.right + .5), reason: reason);
  expect(inner.top, greaterThanOrEqualTo(outer.top - .5), reason: reason);
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom + .5), reason: reason);
}

/// Which of [keys] holds the primary focus, if any.
String? _focusedRegion(List<String> keys) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return null;
  for (final key in keys) {
    final matches = _key(key).evaluate();
    if (matches.isEmpty) continue;
    final region = matches.first;
    var inside = identical(focused, region);
    if (!inside) {
      focused.visitAncestorElements((ancestor) {
        inside = identical(ancestor, region);
        return !inside;
      });
    }
    if (inside) return key;
  }
  return null;
}

void main() {
  setUpAll(_loadFonts);

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

  group('create, desktop frame (variant C)', () {
    for (final (width, height, formWidth) in const [
      (1440.0, 900.0, 616.0),
      (1024.0, 768.0, 552.0),
    ]) {
      final label = width.toInt();

      testWidgets('$label: step 2 is the form and a sticky preview column', (
        tester,
      ) async {
        await _pump(tester, Size(width, height));
        await _toStep2(tester);
        expect(_key('create-live-preview'), findsNothing);

        final gutter = math.max(24.0, (width - 1040) / 2);
        final form = _rect(tester, 'create-form-column');
        final side = _rect(tester, 'create-preview-column');
        expect(form.left, gutter);
        expect(form.width, formWidth);
        expect(side.width, 360);
        expect(side.left, form.right + 64);
        expect(side.right, width - gutter);
        expect(side.top, form.top);

        // Na ścianie Treści above Profil strony, then the change-name link,
        // all in the right column.
        final wall = _rect(tester, 'create-preview-wall');
        final header = _rect(tester, 'create-preview-header');
        final link = _rect(tester, 'create-change-profile');
        _expectWithin(wall, side, 'wall row');
        _expectWithin(header, side, 'profile header');
        _expectWithin(link, side, 'change-name link');
        expect(wall.bottom, lessThan(header.top));
        expect(header.bottom, lessThanOrEqualTo(link.top));
        expect(find.text('NA ŚCIANIE TREŚCI'), findsOneWidget);
        expect(find.text('PROFIL STRONY'), findsOneWidget);

        // Wróć / Dalej at the foot of the form, Dalej at its end.
        final consent = _rect(tester, 'create-consent');
        final back = _rect(tester, 'create-secondary');
        final next = _rect(tester, 'create-primary');
        _expectWithin(next, form, 'Dalej');
        _expectWithin(back, form, 'Wróć');
        expect(next.right, closeTo(form.right, .5));
        expect(next.top, greaterThan(consent.bottom));
        expect(back.right, lessThan(next.left));
        expect(back.top, next.top);

        // Past the header the preview column pins to the window's top and
        // stays put while the form keeps scrolling under the drags.
        final page = _page(tester);
        final grab = Offset(form.right + 32, height / 2);
        await tester.dragFrom(grab, const Offset(0, -350));
        await tester.pumpAndSettle();
        final firstOffset = page.pixels;
        final wallPinned = _rect(tester, 'create-preview-wall');
        final headerPinned = _rect(tester, 'create-preview-header');
        final categoryBefore = _rect(tester, 'create-category');
        expect(_rect(tester, 'create-preview-column').top, 0);
        expect(wallPinned.top, lessThan(wall.top));

        await tester.dragFrom(grab, const Offset(0, -150));
        await tester.pumpAndSettle();
        final moved = page.pixels - firstOffset;
        expect(moved, greaterThan(100), reason: 'the second drag scrolls');
        expect(_rect(tester, 'create-preview-wall'), wallPinned);
        expect(_rect(tester, 'create-preview-header'), headerPinned);
        expect(
          _rect(tester, 'create-category').top,
          closeTo(categoryBefore.top - moved, .5),
        );

        // The wheel over the preview column scrolls the one page.
        page.jumpTo(0);
        await tester.pump();
        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(
          pointer.hover(_rect(tester, 'create-preview-header').center),
        );
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
        await tester.pump();
        expect(page.pixels, 120);
        await tester.sendEventToBinding(
          pointer.hover(_rect(tester, 'create-preview-wall').center),
        );
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 80)));
        await tester.pump();
        expect(page.pixels, 200);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$label at 200 %: every field wraps, nothing overflows', (
        tester,
      ) async {
        await _pump(tester, Size(width, height), textScale: 2);
        await _toStep2(tester);
        expect(tester.takeException(), isNull);
        for (final entry in _oneLineValues.entries) {
          await tester.ensureVisible(_key(entry.key));
          await tester.enterText(_key(entry.key), entry.value);
          await tester.pump();
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await _settle(tester);

        final form = _rect(tester, 'create-form-column');
        for (final key in _oneLineValues.keys) {
          await tester.ensureVisible(_key(key));
          await tester.pump();
          final inner = tester
              .state<ScrollableState>(
                find.descendant(
                  of: _key(key),
                  matching: find.byType(Scrollable),
                ),
              )
              .position;
          expect(inner.axis, Axis.vertical, reason: '$key wraps');
          expect(inner.maxScrollExtent, 0, reason: '$key is cut');
          expect(inner.pixels, 0, reason: '$key is scrolled');
          final field = _rect(tester, key);
          expect(field.left, greaterThanOrEqualTo(form.left - .5));
          expect(field.right, lessThanOrEqualTo(form.right + .5));
        }
        // Godziny runs onto a second line instead of losing "Pn–".
        expect(
          tester.getSize(_key('create-hours')).height,
          greaterThan(tester.getSize(_key('create-phone')).height),
        );
        expect(
          tester.widget<TextField>(_key('create-hours')).controller!.text,
          _hours,
        );

        final page = _page(tester);
        for (final offset in [0.0, page.maxScrollExtent / 2]) {
          page.jumpTo(offset);
          await tester.pump();
          expect(tester.takeException(), isNull, reason: 'at $offset');
        }
        page.jumpTo(page.maxScrollExtent);
        await tester.pump();
        expect(_key('create-change-profile'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('1024 at 200 %: a Godziny at its limit still shows whole', (
      tester,
    ) async {
      await _pump(tester, const Size(1024, 768), textScale: 2);
      await _toStep2(tester);
      final longest =
          'Poniedziałek–piątek 7:00–19:00, sobota 9:00–18:00, niedziela '
                  '9:00–16:00, w święta zamknięte, w wakacje do 20:00'
              .padRight(120, '.')
              .substring(0, 120);
      await tester.ensureVisible(_key('create-hours'));
      await tester.enterText(_key('create-hours'), longest);
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(tester);
      await tester.ensureVisible(_key('create-hours'));
      await tester.pump();
      final inner = tester
          .state<ScrollableState>(
            find.descendant(
              of: _key('create-hours'),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      expect(inner.maxScrollExtent, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('one-line values stay one line: no line breaks, own keys', (
      tester,
    ) async {
      await _pump(tester, const Size(1440, 900));
      await _toStep2(tester);
      await tester.ensureVisible(_key('create-address'));
      await tester.enterText(
        _key('create-address'),
        'ul. Grunwaldzka 57\nGdańsk',
      );
      await tester.pump();
      expect(
        tester.widget<TextField>(_key('create-address')).controller!.text,
        'ul. Grunwaldzka 57Gdańsk',
        reason: 'as a one-line field drops a pasted line break',
      );
      EditableText editable(String key) => tester.widget<EditableText>(
        find.descendant(of: _key(key), matching: find.byType(EditableText)),
      );
      expect(editable('create-website').keyboardType, TextInputType.url);
      expect(editable('create-email').keyboardType, TextInputType.emailAddress);
      expect(editable('create-phone').keyboardType, TextInputType.phone);
      expect(editable('create-address').keyboardType, TextInputType.text);
      expect(editable('create-hours').keyboardType, TextInputType.text);
      expect(
        editable('create-legal').keyboardType,
        TextInputType.multiline,
        reason: 'the legal notice keeps its line breaks',
      );
    });

    testWidgets('1440: the header stands still through steps 1, 2 and 3', (
      tester,
    ) async {
      await _pump(tester, const Size(1440, 900), ageVerified: true);
      (Rect, Rect, Offset) header(String title) => (
        _rect(tester, 'create-back'),
        _rect(tester, 'create-step-tabs'),
        tester.getTopLeft(find.text(title)),
      );

      final step1 = header('Jaką stronę chcesz prowadzić?');
      expect(step1.$1.left, 200);
      expect(step1.$2.left, 200);
      expect(step1.$2.width, 1040);
      expect(step1.$3.dx, 200);
      // Step 1 keeps its approved 720 column at the frame's start.
      expect(_rect(tester, 'create-kind-business').left, 200);
      expect(_rect(tester, 'create-kind-community').right, 920);
      expect(_rect(tester, 'create-primary').right, 920);

      await _toStep2(tester);
      expect(header('Szczegóły strony'), step1);

      await tester.tap(_key('create-category'));
      await _settle(tester);
      await tester.tap(_key('page-category-cafe_restaurant'));
      await _settle(tester);
      await tester.ensureVisible(_key('create-consent'));
      await tester.pump();
      await tester.tap(_key('create-consent'));
      await tester.pump();
      await tester.ensureVisible(_key('create-primary'));
      await tester.pump();
      await tester.tap(_key('create-primary'));
      await _settle(tester);
      expect(find.text('Opublikuj stronę'), findsOneWidget);
      expect(header('Tak zobaczą ją inni'), step1);
      // Step 3 keeps its approved 720 column with the header centred in it.
      final preview = _rect(tester, 'create-preview-header');
      expect(preview.width, lessThanOrEqualTo(480));
      expect(preview.center.dx, 560);
      expect(tester.takeException(), isNull);
    });

    testWidgets('1440 step 2: Tab walks the form, Wróć / Dalej, then the '
        'change-name link, never the previews', (tester) async {
      await _pump(tester, const Size(1440, 900));
      await _toStep2(tester);
      const order = [
        'create-back',
        'create-category',
        'create-description',
        'create-website',
        'create-email',
        'create-phone',
        'create-address',
        'create-hours',
        'create-legal',
        'create-birth-date',
        'create-consent',
        'create-secondary',
        'create-primary',
        'create-change-profile',
      ];
      const regions = [
        ...order,
        'create-preview-wall',
        'create-preview-header',
      ];
      final visited = <String>[];
      for (var i = 0; i < 40; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final region = _focusedRegion(regions) ?? '?';
        if (visited.isEmpty || visited.last != region) visited.add(region);
        if (region == 'create-change-profile') break;
      }
      expect(visited, order);
      // The link sits pinned in the preview column when reached.
      expect(_rect(tester, 'create-change-profile').top, greaterThan(0));
      expect(_rect(tester, 'create-change-profile').bottom, lessThan(900));
    });

    testWidgets('1440 community: the shorter form keeps both previews', (
      tester,
    ) async {
      await _pump(tester, const Size(1440, 900));
      await tester.tap(_key('create-kind-community'));
      await _toStep2(tester);
      expect(_key('create-rules'), findsOneWidget);
      expect(_key('create-linked-server'), findsOneWidget);
      expect(_key('create-website'), findsNothing);
      _expectWithin(
        _rect(tester, 'create-preview-wall'),
        _rect(tester, 'create-preview-column'),
        'wall row',
      );
      expect(find.text('Społeczność'), findsWidgets);
      final page = _page(tester);
      page.jumpTo(page.maxScrollExtent);
      await tester.pump();
      _expectWithin(
        _rect(tester, 'create-primary'),
        _rect(tester, 'create-form-column'),
        'Dalej',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('1440 before the profile arrives: the fallback name, and the '
        'change-name link waits', (tester) async {
      await _pump(
        tester,
        const Size(1440, 900),
        profile: () => const Stream<UserProfile>.empty(),
      );
      await _toStep2(tester);
      expect(
        find.descendant(
          of: _key('create-preview-column'),
          matching: find.text('Twoja strona'),
        ),
        findsWidgets,
      );
      final link = tester.widget<ButtonStyleButton>(
        _key('create-change-profile'),
      );
      expect(link.onPressed, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('1440: an invalid Dalej brings Kategoria back into view', (
      tester,
    ) async {
      await _pump(tester, const Size(1440, 900));
      await _toStep2(tester);
      final page = _page(tester);
      page.jumpTo(page.maxScrollExtent);
      await tester.pump();
      await tester.tap(_key('create-primary'));
      await _settle(tester);
      expect(find.text('Wybierz kategorię'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'create-category');
      final category = _rect(tester, 'create-category');
      expect(category.top, greaterThanOrEqualTo(0));
      expect(category.bottom, lessThanOrEqualTo(900));
    });
  });

  group('create below the frame', () {
    testWidgets('800: every step keeps the one 720 column', (tester) async {
      await _pump(tester, const Size(800, 1024));
      expect(_rect(tester, 'create-back').left, 40);
      expect(_rect(tester, 'create-step-tabs').width, 720);
      await _toStep2(tester);
      expect(_key('create-form-column'), findsNothing);
      expect(_key('create-preview-wall'), findsNothing);
      final preview = _rect(tester, 'create-live-preview');
      expect(preview.left, 40);
      expect(preview.width, 720);
      final category = _rect(tester, 'create-category');
      expect(category.width, 720);
      expect(category.top, greaterThan(preview.bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('390: the phone layout with its app bar', (tester) async {
      await _pump(tester, const Size(390, 844));
      await _toStep2(tester);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Krok 2 z 3'), findsOneWidget);
      expect(_key('create-step-tabs'), findsNothing);
      expect(_key('create-preview-wall'), findsNothing);
      final preview = _rect(tester, 'create-live-preview');
      expect(preview.left, 16);
      expect(preview.width, 358);
      expect(tester.takeException(), isNull);
    });
  });
}
