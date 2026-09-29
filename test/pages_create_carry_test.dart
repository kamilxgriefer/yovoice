// Create a Page, step 3's carry-over caption (ADR-234, variant C, owner
// decision 2026-09-29). Under the profile preview, which already shows the
// account's followers ("Firma · 1,2 tys. obserwujących"), a small caption
// with an up-arrow says they move to the Page and see its posts in Treści,
// then either that the public follower list closes (it is public today) or
// that everyone will see the count. With no followers and no public list,
// step 3 is exactly what it was. Same on phone, tablet and desktop: the
// caption is as wide as the preview.
import 'dart:io';
import 'dart:math' as math;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/page_profile_copy.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';
import 'package:yovoice/features/pages/presentation/screens/create_page_screen.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'support/material_icons_font.dart';

final DateTime _now = DateTime.utc(2026, 9, 29, 12);

const _carryMany =
    'Obecni obserwujący przejdą na stronę i zobaczą jej posty w Treściach.';
const _carryOne =
    'Obecny obserwujący przejdzie na stronę i zobaczy jej posty w Treściach.';
const _listHidden = 'Publiczna lista obserwujących zostanie ukryta.';
const _countPublicMany = 'Ich liczbę zobaczy każdy.';
const _countPublicOne = 'Liczbę obserwujących zobaczy każdy.';

Future<void> _loadFonts() async {
  Future<ByteData> read(String path) async =>
      ByteData.sublistView(File(path).readAsBytesSync());
  final inter = FontLoader('Inter')
    ..addFont(read('assets/fonts/InterVariable.ttf'))
    ..addFont(read('assets/fonts/InterVariable-Italic.ttf'));
  await inter.load();
  await loadMaterialIconsFont();
}

/// The own `users/{uid}` document exactly as ProfileService reads it: the
/// public (gated) count, the raw account count and the audience flags.
Future<UserProfile> _stored(
  WidgetTester tester, {
  required int followers,
  bool listVisible = false,
  bool audienceEnabled = false,
}) async {
  final profile = await tester.runAsync(() async {
    final firestore = FakeFirebaseFirestore();
    await firestore.doc('users/me').set({
      'displayName': 'Kawiarnia Ziarno',
      'username': 'ziarno',
      'creatorAgeVerified': true,
      'followerCount': followers,
      'creatorAudienceEnabled': audienceEnabled,
      'creatorAudienceVisible': listVisible,
    });
    return UserProfile.fromFirestore(await firestore.doc('users/me').get());
  });
  expect(profile!.accountFollowerCount, followers);
  expect(profile.creatorAudienceVisible, listVisible);
  return profile;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(
  WidgetTester tester,
  UserProfile profile, {
  Size size = const Size(390, 844),
  double textScale = 1,
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
          child: CreatePageScreen(
            service: PagesService(
              invoker: (name, payload) async => {'ok': true},
              requestIdFactory: () => 'pg_test_request_0001',
              clock: () => _now,
            ),
            profileStream: () => Stream.value(profile),
            serverStream: () => Stream.value(const []),
            birthDatePicker: (_) async => DateTime(1990, 3, 14),
            userId: 'me',
            clock: () => _now,
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}

Finder _key(String key) => find.byKey(ValueKey(key));

final Finder _carry = _key('create-carry');
final Finder _preview = _key('create-preview-header');
final Finder _arrow = find.descendant(
  of: _carry,
  matching: find.byIcon(Icons.arrow_upward_rounded),
);

/// Scrolls the page (its outermost scroll view, every layout's first) down
/// until [finder] is built, then brings it into view.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final position = tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position;
  for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
    position.jumpTo(math.min(position.pixels + 200, position.maxScrollExtent));
    await tester.pump();
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await _reveal(tester, _key(key));
  await tester.tap(_key(key));
  await _settle(tester);
}

/// A business Page for an attested account: Dalej, a category, the
/// consent, Dalej.
Future<void> _toStep3(WidgetTester tester) async {
  await _tap(tester, 'create-primary');
  await _tap(tester, 'create-category');
  await tester.ensureVisible(_key('page-category-cafe_restaurant'));
  await tester.tap(_key('page-category-cafe_restaurant'));
  await _settle(tester);
  await _tap(tester, 'create-consent');
  await _tap(tester, 'create-primary');
  expect(find.text('Opublikuj stronę'), findsWidgets, reason: 'on step 3');
  expect(_preview, findsOneWidget);
}

/// A line of text, whatever spaces the compact count uses ("1,2 tys." has a
/// no-break space).
Finder _meta(String text) => find.textContaining(
  RegExp('^${RegExp.escape(text).replaceAll(' ', r'\s')}\$'),
);

/// The caption's words (the arrow is a RichText too).
final Finder _words = find.descendant(of: _carry, matching: find.byType(Text));

/// The caption as printed.
String _captionText(WidgetTester tester) => tester.widget<Text>(_words).data!;

PagesCopy _copyFor(String localeKey) {
  final parts = localeKey.split('_');
  return PagesCopy(
    AppLocalizations(
      parts.length == 2 ? Locale(parts[0], parts[1]) : Locale(parts[0]),
    ),
  );
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

  group('create step 3 carry-over caption (ADR-234, variant C)', () {
    testWidgets('1 200 followers and a public list: both sentences, under '
        'the preview that shows the count', (tester) async {
      final profile = await _stored(
        tester,
        followers: 1200,
        listVisible: true,
        audienceEnabled: true,
      );
      await _pump(tester, profile);
      await _toStep3(tester);
      await _reveal(tester, _carry);

      expect(
        find.descendant(
          of: _preview,
          matching: _meta('Firma · 1,2 tys. obserwujących'),
        ),
        findsOneWidget,
      );
      expect(_captionText(tester), '$_carryMany $_listHidden');
      expect(_arrow, findsOneWidget);
      expect(tester.getSize(_arrow), const Size.square(18));

      final preview = tester.getRect(_preview);
      final caption = tester.getRect(_carry);
      expect(caption.top, closeTo(preview.bottom, .5), reason: 'right under');
      final whatHappens = tester.getRect(find.text('CO SIĘ STANIE'));
      expect(whatHappens.top, closeTo(caption.bottom + 24, .5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('3 followers, no public list: the count turns public', (
      tester,
    ) async {
      await _pump(tester, await _stored(tester, followers: 3));
      await _toStep3(tester);
      await _reveal(tester, _carry);
      expect(_captionText(tester), '$_carryMany $_countPublicMany');
      expect(find.textContaining(_listHidden), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('exactly 1 follower reads in the singular', (tester) async {
      await _pump(tester, await _stored(tester, followers: 1));
      await _toStep3(tester);
      await _reveal(tester, _carry);
      expect(_captionText(tester), '$_carryOne $_countPublicOne');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Creator audience preference without a public list '
        'gets the count sentence, not the list one', (tester) async {
      // creatorAudienceEnabled is only the stored preference; nothing is
      // public until creatorAudienceVisible, so no list is hidden.
      await _pump(
        tester,
        await _stored(tester, followers: 1200, audienceEnabled: true),
      );
      await _toStep3(tester);
      await _reveal(tester, _carry);
      expect(_captionText(tester), '$_carryMany $_countPublicMany');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a public list with no followers: only the list sentence', (
      tester,
    ) async {
      await _pump(
        tester,
        await _stored(
          tester,
          followers: 0,
          listVisible: true,
          audienceEnabled: true,
        ),
      );
      await _toStep3(tester);
      await _reveal(tester, _carry);
      expect(_captionText(tester), _listHidden);
      expect(tester.takeException(), isNull);
    });

    for (final audienceEnabled in const [false, true]) {
      testWidgets('0 followers, no public list (preference '
          '${audienceEnabled ? 'on' : 'off'}): step 3 as before', (
        tester,
      ) async {
        await _pump(
          tester,
          await _stored(tester, followers: 0, audienceEnabled: audienceEnabled),
        );
        await _toStep3(tester);
        await _reveal(tester, find.text('CO SIĘ STANIE'));
        expect(_carry, findsNothing);
        expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
        expect(
          find.descendant(
            of: _preview,
            matching: _meta('Firma · 0 obserwujących'),
          ),
          findsOneWidget,
        );
        // The 24 px between the preview and "Co się stanie", as before.
        final whatHappens = tester.getRect(find.text('CO SIĘ STANIE'));
        expect(
          whatHappens.top,
          closeTo(tester.getRect(_preview).bottom + 24, .5),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('320 px at 200 %: the caption wraps whole and its arrow '
        'grows with the words', (tester) async {
      final profile = await _stored(
        tester,
        followers: 1200,
        listVisible: true,
        audienceEnabled: true,
      );
      await _pump(tester, profile, size: const Size(320, 640), textScale: 2);
      await _toStep3(tester);
      // Measured while it is on screen: at this size the list drops it once
      // the caption is scrolled to.
      final previewWidth = tester.getRect(_preview).width;
      expect(previewWidth, 320 - 2 * 16);
      await _reveal(tester, _carry);

      expect(_captionText(tester), '$_carryMany $_listHidden');
      expect(tester.getSize(_arrow), const Size.square(36));
      final caption = tester.getRect(_carry);
      expect(caption.left, greaterThanOrEqualTo(0));
      expect(caption.right, lessThanOrEqualTo(320));
      expect(caption.width, closeTo(previewWidth, .5));
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: _words, matching: find.byType(RichText)),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(
        paragraph.size.height,
        greaterThan(26 * 1.4 * 3),
        reason: 'wraps over several lines instead of clipping',
      );
      // The arrow stays one text line tall, on the first line.
      expect(tester.getTopLeft(_arrow).dy, closeTo(caption.top + 12, .5));
      expect(tester.takeException(), isNull);
    });

    for (final (label, size) in const [
      ('phone 390', Size(390, 844)),
      ('tablet 820', Size(820, 1180)),
      ('desktop 1440', Size(1440, 900)),
    ]) {
      testWidgets('$label: the caption is exactly as wide as the preview', (
        tester,
      ) async {
        final profile = await _stored(
          tester,
          followers: 1200,
          listVisible: true,
          audienceEnabled: true,
        );
        await _pump(tester, profile, size: size);
        await _toStep3(tester);
        await _reveal(tester, _carry);
        final preview = tester.getRect(_preview);
        final caption = tester.getRect(_carry);
        expect(caption.left, closeTo(preview.left, .5));
        expect(caption.width, closeTo(preview.width, .5));
        if (size.width >= 720) {
          expect(caption.width, 390, reason: 'the preview is never scaled up');
        }
        expect(caption.top, closeTo(preview.bottom, .5));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('screen readers hear the count the hidden preview shows', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final profile = await _stored(
        tester,
        followers: 1200,
        listVisible: true,
        audienceEnabled: true,
      );
      await _pump(tester, profile);
      await _toStep3(tester);
      await _reveal(tester, _carry);

      final count = _copyFor('pl').followers(1200);
      expect(count, contains('1,2'));
      final node = tester.getSemantics(_carry);
      expect(node.label, '$count. $_carryMany $_listHidden');
      // The preview stays out of semantics; the caption is the one place a
      // screen reader hears the count.
      expect(find.bySemanticsLabel(RegExp('1,2')), findsOneWidget);
      semantics.dispose();
    });
  });

  group('carry caption copy', () {
    test('English and Polish, one follower and more', () {
      final en = _copyFor('en');
      expect(
        en.carryCaption(1200, listClosing: true),
        'Your current followers will move to the Page and see its posts in '
        'Content. Your public follower list will be hidden.',
      );
      expect(
        en.carryCaption(1, listClosing: false),
        'Your current follower will move to the Page and see its posts in '
        'Content. Everyone will see the follower count.',
      );
      expect(
        en.carryCaptionLabel(1200, listClosing: false),
        '1.2K followers. Your current followers will move to the Page and '
        'see its posts in Content. Everyone will see how many there are.',
      );
      final pl = _copyFor('pl');
      expect(
        pl.carryCaption(2, listClosing: false),
        '$_carryMany $_countPublicMany',
      );
      expect(
        pl.carryCaption(5, listClosing: false),
        '$_carryMany $_countPublicMany',
      );
      expect(pl.carryCaption(1, listClosing: true), '$_carryOne $_listHidden');
      expect(pl.carryCaption(0, listClosing: true), _listHidden);
    });

    test('no printed number: 21 reads plural where CLDR "one" covers it', () {
      for (final locale in const ['ru', 'uk', 'hr', 'sr', 'lt']) {
        final copy = _copyFor(locale);
        for (final closing in const [false, true]) {
          expect(
            copy.carryCaption(21, listClosing: closing),
            copy.carryCaption(3, listClosing: closing),
            reason: locale,
          );
          expect(
            copy.carryCaption(1, listClosing: closing),
            isNot(copy.carryCaption(21, listClosing: closing)),
            reason: locale,
          );
        }
      }
    });

    test('every translated locale has its own words and leads the spoken '
        'caption with its own count', () {
      final english = _copyFor('en');
      final locales = selectableAppLanguages
          .where(
            (language) =>
                language != AppLanguagePreference.english &&
                language != AppLanguagePreference.polish,
          )
          .map((language) => language.localeKey)
          .toList();
      expect(locales, hasLength(41));
      for (final locale in locales) {
        final copy = _copyFor(locale);
        for (final (count, closing) in const [
          (0, true),
          (1, true),
          (1, false),
          (1200, true),
          (1200, false),
        ]) {
          final caption = copy.carryCaption(count, listClosing: closing);
          expect(
            caption,
            isNot(english.carryCaption(count, listClosing: closing)),
            reason: '$locale ($count, $closing) fell back to English',
          );
          final label = copy.carryCaptionLabel(count, listClosing: closing);
          expect(label, startsWith(copy.followers(count)), reason: locale);
          expect(label, endsWith(caption), reason: locale);
          expect(label, isNot(contains('{')), reason: locale);
        }
      }
    });
  });
}
