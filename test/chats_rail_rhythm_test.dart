// The Chats friend rail, build 42 "Równy rytm 48" (owner decision
// 2026-10-03, chatsRail option A).
//
// Kamil: the circles at the top of Chats were too big and too far apart.
// The rail is now one rhythm: every mark 48 px, every tile 64 px, so the
// marks stand 16 px apart and the first one starts on the page's 16 px
// gutter; the rail is 76 px tall and a 390 px phone shows six whole marks
// instead of four. The two actions carry one short word ("Dodaj" /
// "Napisz") and keep the full phrase as their spoken name and tooltip.
//
// These tests pin that geometry at 320, 390, 768 and 1440 px and in RTL
// with the real product font, and that every one of the 43 selectable
// languages has its own short word that fits the 64 px tile on one line.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_chats_rail.dart';
import 'package:yovoice/core/theme/app_icons.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/messages_screen.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/inputs/yo_search_field.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

const _me = 'me-uid';

/// The rail's numbers (docs/UI.md, "Chats friend rail").
const double _mark = 48;
const double _tile = 64;
const double _gutter = 16;
const double _railHeight = 76;

/// The label box of a 64 px tile: 3 px of air on each side.
const double _labelBox = 58;

const _addKey = ValueKey<String>('messages-add-friend');
const _writeKey = ValueKey<String>('messages-new-message');

/// Fourteen friends: more than the rail's cap of twelve.
const _friendNames = <String>[
  'Ola Nowak',
  'Kuba Wiśniewski',
  'Marta Zielińska',
  'Tomek Kowalczyk',
  'Iga Malinowska',
  'Paweł Dąbrowski',
  'Ania Lewandowska',
  'Piotr Wójcik',
  'Zosia Kamińska',
  'Bartek Lis',
  'Magda Sikora',
  'Filip Mazur',
  'Natalia Krawczyk',
  'Wojtek Pawlak',
];

class _Service extends MessageService {
  _Service()
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      );

  @override
  Stream<List<Conversation>> watchConversations({
    bool includeArchived = false,
  }) => Stream<List<Conversation>>.value(const <Conversation>[]);
}

class _Friends extends FriendService {
  _Friends({this.count = 14})
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      );

  final int count;

  @override
  Stream<List<FriendUser>> watchFriends() => Stream<List<FriendUser>>.value([
    for (final (index, name) in _friendNames.take(count).indexed)
      FriendUser(
        id: 'friend-$index',
        displayName: name,
        email: '',
        photoUrl: null,
        isOnline: index.isEven,
        lastSeen: null,
      ),
  ]);
}

Widget _host({
  Locale locale = const Locale('pl'),
  double textScale = 1,
  int friends = 14,
  bool boldText = false,
  VoidCallback? onFindFriends,
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
  builder: (context, navigator) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
      // The platform's Bold Text setting: `Text` draws every label bold.
      boldText: boldText,
    ),
    child: navigator!,
  ),
  home: MessagesScreen(
    // Keyed by locale, so a new language is a fresh screen with fresh
    // streams rather than a rebuild of the previous one.
    key: ValueKey('${locale.toLanguageTag()}-$textScale-$friends-$boldText'),
    messageService: _Service(),
    friendService: _Friends(count: friends),
    auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
    onFindFriends: onFindFriends ?? () {},
  ),
);

void _surface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The friend rail's horizontal list.
Finder _rail() =>
    find.ancestor(of: find.byKey(_addKey), matching: find.byType(ListView));

/// The mark a glyph or an avatar sits in: its nearest `Container`, which is
/// the action's ghost disc or the friend's hairline band.
Rect _markAround(WidgetTester tester, Element inner) => tester.getRect(
  find
      .ancestor(
        of: find.byElementPredicate((element) => element == inner),
        matching: find.byType(Container),
      )
      .first,
);

/// Every mark the rail has built, from the leading edge on.
List<Rect> _marks(WidgetTester tester, {bool rtl = false}) {
  final inner = <Finder>[
    find.descendant(of: _rail(), matching: find.byIcon(AppIcons.addFriend)),
    find.descendant(of: _rail(), matching: find.byIcon(AppIcons.compose)),
    find.descendant(of: _rail(), matching: find.byType(UserAvatar)),
  ];
  final marks = [
    for (final finder in inner)
      for (final element in finder.evaluate()) _markAround(tester, element),
  ];
  marks.sort(
    (a, b) => rtl ? b.right.compareTo(a.right) : a.left.compareTo(b.left),
  );
  return marks;
}

/// The tile's label paragraph (its glyph is a paragraph too, so the label is
/// found through its `Text`).
RenderParagraph _label(WidgetTester tester, Key tile) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.descendant(of: find.byKey(tile), matching: find.byType(Text)),
        matching: find.byType(RichText),
      ),
    );

/// True when Inter itself draws [text]: Latin (with the Vietnamese block),
/// Greek and Cyrillic. Other scripts come from a device fallback font the
/// test host does not have, so they cannot be measured here.
bool _interDraws(String text) => text.runes.every(
  (rune) =>
      rune < 0x0530 ||
      (rune >= 0x1E00 && rune <= 0x1FFF) ||
      (rune >= 0x2000 && rune <= 0x206F),
);

/// The label's own width on one unbroken line, measured with the style and
/// text scale it is really drawn with (the theme adds letter spacing, so a
/// bare 11 px measurement would come out narrower than the screen).
double _unbrokenWidth(RenderParagraph label) {
  final painter = TextPainter(
    text: label.text,
    textDirection: label.textDirection,
    textScaler: label.textScaler,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// The width of the label's longest word, as it is really drawn: the least
/// width that still breaks the label only between words.
double _longestWordWidth(RenderParagraph label) {
  final painter = TextPainter(
    text: label.text,
    textDirection: label.textDirection,
    textScaler: label.textScaler,
  )..layout();
  final width = painter.minIntrinsicWidth;
  painter.dispose();
  return width;
}

/// Where the label's glyphs really are on screen. The paragraph's own box is
/// as wide as its tile allows and the text is centred in it, so the box says
/// nothing about how far two neighbouring labels stand apart.
Rect _inkRect(RenderParagraph label) {
  final boxes = label.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: label.text.toPlainText().length),
  );
  final local = boxes
      .map((box) => box.toRect())
      .reduce((a, b) => a.expandToInclude(b));
  return label.localToGlobal(local.topLeft) & local.size;
}

/// A friend's name label in the rail.
RenderParagraph _nameLabel(WidgetTester tester, String name) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.descendant(of: _rail(), matching: find.text(name)),
        matching: find.byType(RichText),
      ),
    );

/// The tile of the friend called [name].
Rect _friendTile(WidgetTester tester, String name) => tester.getRect(
  find
      .ancestor(
        of: find.descendant(of: _rail(), matching: find.text(name)),
        matching: find.byType(AccessibleTapRegion),
      )
      .first,
);

typedef _RailCopy = ({
  String add,
  String write,
  String addName,
  String writeName,
});

/// What the rail shows and says in [language].
_RailCopy _copyFor(AppLanguagePreference language) {
  if (language == AppLanguagePreference.english) {
    return (
      add: 'Add',
      write: 'Write',
      addName: 'Add friend',
      writeName: 'New message',
    );
  }
  if (language == AppLanguagePreference.polish) {
    return (
      add: 'Dodaj',
      write: 'Napisz',
      addName: 'Dodaj znajomego',
      writeName: 'Nowa wiadomość',
    );
  }
  final entries = chatsRailTranslations[language.localeKey]!;
  return (
    add: entries['chatsRail.add']!,
    write: entries['chatsRail.write']!,
    addName: entries['chatsRail.addFriend']!,
    writeName: entries['chatsRail.newMessage']!,
  );
}

void main() {
  late PublicIdentityRepository originalIdentityRepository;

  setUpAll(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'));
    await inter.load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    originalIdentityRepository = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentityRepository;
  });

  group('one rhythm', () {
    // Whole marks in view: the brief's counts. At 320 and 768 the last one
    // ends exactly on the edge; at 1440 the list column is 880 px wide.
    for (final (size, whole) in const [
      (Size(320, 690), 5),
      (Size(390, 844), 6),
      (Size(768, 1024), 12),
      (Size(1440, 900), 13),
    ]) {
      testWidgets('${size.width.toInt()} px: 48 px marks 16 px apart, '
          '$whole whole', (tester) async {
        _surface(tester, size);
        await tester.pumpWidget(_host());
        await tester.pumpAndSettle();

        final rail = tester.getRect(_rail());
        expect(rail.height, _railHeight);
        expect(rail.left, 0);

        final marks = _marks(tester);
        expect(marks.length, greaterThanOrEqualTo(whole));
        for (final (index, mark) in marks.indexed) {
          expect(mark.size, const Size.square(_mark), reason: 'mark $index');
          expect(mark.left, _gutter + index * _tile, reason: 'mark $index');
          expect(mark.top, rail.top, reason: 'mark $index');
        }
        expect(
          marks.where((mark) => mark.right <= rail.right).length,
          whole,
          reason: 'whole marks in a ${rail.width.toInt()} px rail',
        );

        // The first mark stands on the page's 16 px gutter, in line with the
        // search field above it.
        expect(
          marks.first.left,
          tester.getRect(find.byType(YoSearchField)).left,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('every tile is 64 px with a one-line 11 px label', (
      tester,
    ) async {
      _surface(tester, const Size(390, 844));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      for (final key in const [_addKey, _writeKey]) {
        final tile = tester.getRect(find.byKey(key));
        expect(tile.width, _tile, reason: '$key');
        // The whole tile is the target: 64 px wide, as tall as the rail.
        expect(tile.height, greaterThanOrEqualTo(48), reason: '$key');
        final glyph = tester.widget<Icon>(
          find.descendant(of: find.byKey(key), matching: find.byType(Icon)),
        );
        expect(glyph.size, 20, reason: '$key');
        final label = _label(tester, key);
        expect(label.maxLines, 1, reason: '$key');
        expect(label.didExceedMaxLines, isFalse, reason: '$key');
        expect(label.text.style?.fontSize, 11, reason: '$key');
        expect(label.size.width, lessThanOrEqualTo(_labelBox), reason: '$key');
      }
      expect(
        tester.getRect(find.byKey(_writeKey)).left,
        tester.getRect(find.byKey(_addKey)).right,
        reason: 'no separator between tiles',
      );

      // A friend: a radius-22 avatar inside the 2 px band, the name 6 px
      // under the mark.
      final avatar = find.descendant(
        of: _rail(),
        matching: find.byType(UserAvatar),
      );
      expect(tester.getSize(avatar.first), const Size.square(44));
      final name = tester.getRect(
        find.descendant(of: _rail(), matching: find.text('Ola Nowak')),
      );
      final firstFriend = _marks(tester)[2];
      expect(name.top, firstFriend.bottom + 6);
      expect(name.left, greaterThanOrEqualTo(firstFriend.left - 8 + 3));
      expect(name.right, lessThanOrEqualTo(firstFriend.right + 8 - 3));
    });

    testWidgets('the short word is the label, the full phrase the name', (
      tester,
    ) async {
      _surface(tester, const Size(390, 844));
      var opened = 0;
      await tester.pumpWidget(_host(onFindFriends: () => opened++));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byKey(_addKey), matching: find.text('Dodaj')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(_writeKey),
          matching: find.text('Napisz'),
        ),
        findsOneWidget,
      );
      expect(find.text('Dodaj znajomego'), findsNothing);
      // The spoken name and the tooltip keep the whole phrase.
      expect(find.bySemanticsLabel('Dodaj znajomego'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_writeKey),
          matching: find.bySemanticsLabel('Nowa wiadomość'),
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Dodaj znajomego'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_writeKey),
          matching: find.byTooltip('Nowa wiadomość'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(_addKey));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('the rail shows at most twelve friends', (tester) async {
      _surface(tester, const Size(1440, 900));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      await tester.drag(_rail(), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: _rail(), matching: find.text('Filip Mazur')),
        findsOneWidget,
      );
      expect(find.text('Natalia Krawczyk'), findsNothing);
      // Scrolled to its end, the last mark keeps the same 16 px gutter.
      final rail = tester.getRect(_rail());
      expect(_marks(tester).last.right, rail.right - _gutter);
    });

    testWidgets('with no friends the two actions stand alone', (tester) async {
      _surface(tester, const Size(390, 844));
      await tester.pumpWidget(_host(friends: 0));
      await tester.pumpAndSettle();
      final marks = _marks(tester);
      expect(marks, hasLength(2));
      expect(marks.first.left, _gutter);
      expect(marks.last.left, _gutter + _tile);
      expect(tester.getSize(_rail()).height, _railHeight);
    });

    testWidgets('RTL mirrors the rhythm from the right gutter', (tester) async {
      _surface(tester, const Size(390, 844));
      await tester.pumpWidget(_host(locale: const Locale('ar')));
      await tester.pumpAndSettle();

      final marks = _marks(tester, rtl: true);
      for (final (index, mark) in marks.indexed) {
        expect(mark.size, const Size.square(_mark), reason: 'mark $index');
        expect(
          mark.right,
          390 - _gutter - index * _tile,
          reason: 'mark $index',
        );
      }
      expect(marks.where((mark) => mark.left >= 0).length, 6);
      // "Add" leads: it is the mark nearest the right edge.
      expect(tester.getRect(find.byKey(_addKey)).right, 390 - 8);
      expect(tester.takeException(), isNull);
    });
  });

  group('large text', () {
    for (final width in const [320.0, 390.0, 768.0, 1440.0]) {
      testWidgets('200 % at ${width.toInt()} px: marks stay 48 px, tiles '
          'widen, labels take two lines', (tester) async {
        _surface(tester, Size(width, 900));
        await tester.pumpWidget(_host(textScale: 2));
        await tester.pumpAndSettle();

        // 48 + 6 + two 26.4 px lines + 8.8.
        expect(tester.getSize(_rail()).height, moreOrLessEquals(115.6));
        final marks = _marks(tester);
        for (final mark in marks) {
          // Fractional tile widths: the mark is 48 px to within rounding.
          expect(mark.width, moreOrLessEquals(_mark, epsilon: .01));
          expect(mark.height, moreOrLessEquals(_mark, epsilon: .01));
        }
        // The actions widen to 1.3× (83.2 px); the first mark is centred in
        // its wider tile.
        final add = tester.getRect(find.byKey(_addKey));
        expect(add.width, moreOrLessEquals(83.2));
        expect(marks.first.center.dx, moreOrLessEquals(add.center.dx));
        for (final key in const [_addKey, _writeKey]) {
          final label = _label(tester, key);
          expect(label.maxLines, 2);
          expect(label.didExceedMaxLines, isFalse);
        }
        // The friends share one width. "Lewandowska" is 153 px at 200 %,
        // more than any tile holds, so they stand at the 144 px cap, which
        // keeps every word up to 138 px whole ("Wiśniewski").
        final ola = _friendTile(tester, 'Ola Nowak');
        final kuba = _friendTile(tester, 'Kuba Wiśniewski');
        expect(ola.width, moreOrLessEquals(144));
        expect(kuba.width, moreOrLessEquals(144));
        expect(kuba.left, moreOrLessEquals(ola.right));
        for (final name in const ['Ola Nowak', 'Kuba Wiśniewski']) {
          final label = _nameLabel(tester, name);
          expect(label.maxLines, 2, reason: name);
          expect(label.didExceedMaxLines, isFalse, reason: name);
          expect(
            label.constraints.maxWidth,
            greaterThanOrEqualTo(_longestWordWidth(label)),
            reason: '$name is broken inside a word',
          );
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('200 % with short names: a friend is 128 px', (tester) async {
      // Wide enough to show all three (a finder skips a tile that is built
      // but scrolled out of view).
      _surface(tester, const Size(768, 1024));
      // The first three friends: no word wider than the text-scaled tile.
      await tester.pumpWidget(_host(textScale: 2, friends: 3));
      await tester.pumpAndSettle();
      for (final name in _friendNames.take(3)) {
        expect(
          _friendTile(tester, name).width,
          moreOrLessEquals(128),
          reason: name,
        );
        final label = _nameLabel(tester, name);
        expect(label.didExceedMaxLines, isFalse, reason: name);
        expect(
          label.constraints.maxWidth,
          greaterThanOrEqualTo(_longestWordWidth(label)),
          reason: '$name is broken inside a word',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('200 % with Bold Text: a name is measured as it is drawn', (
      tester,
    ) async {
      _surface(tester, const Size(768, 1024));
      // "Wiśniewski" fits the 128 px tile at its medium weight and not at
      // the bold one the platform's Bold Text setting draws it with: the
      // friends' shared tile has to follow the drawn width.
      await tester.pumpWidget(_host(textScale: 2, friends: 3, boldText: true));
      await tester.pumpAndSettle();
      final shared = _friendTile(tester, _friendNames.first).width;
      expect(shared, greaterThan(128.5));
      expect(shared, lessThanOrEqualTo(_tile * 2.25));
      for (final name in _friendNames.take(3)) {
        final label = _nameLabel(tester, name);
        expect(label.text.style?.fontWeight, FontWeight.bold, reason: name);
        expect(label.didExceedMaxLines, isFalse, reason: name);
        expect(
          label.constraints.maxWidth,
          greaterThanOrEqualTo(_longestWordWidth(label)),
          reason: '$name is broken inside a word',
        );
        expect(
          _friendTile(tester, name).width,
          moreOrLessEquals(shared, epsilon: .001),
          reason: '$name: the friends share one width',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('130 %: the actions grow with the text, the friends share '
        'the width their longest word needs', (tester) async {
      // The 880 px list column: wide enough for the seventh friend's tile.
      _surface(tester, const Size(1440, 900));
      await tester.pumpWidget(_host(textScale: 1.3));
      await tester.pumpAndSettle();
      final add = tester.getRect(find.byKey(_addKey));
      final write = tester.getRect(find.byKey(_writeKey));
      expect(add.width, moreOrLessEquals(_tile * 1.3));
      expect(write.width, moreOrLessEquals(_tile * 1.3));

      // "Lewandowska" (100.5 px at 130 %) is the longest word among the
      // twelve names: every friend tile is as wide as it needs, so no name
      // is broken inside a word and the friends keep one pitch.
      const shown = ['Ola Nowak', 'Kuba Wiśniewski', 'Ania Lewandowska'];
      // The word, 3 px of air on each side, rounded up to a whole pixel.
      final shared =
          (_longestWordWidth(_nameLabel(tester, 'Ania Lewandowska')) + 6)
              .ceilToDouble();
      expect(shared, greaterThan(_tile * 1.3));
      expect(shared, lessThanOrEqualTo(_tile * 2.25));
      for (final name in shown) {
        expect(
          _friendTile(tester, name).width,
          moreOrLessEquals(shared, epsilon: .001),
          reason: '$name: the friends share one width',
        );
        final label = _nameLabel(tester, name);
        expect(label.maxLines, 2, reason: name);
        expect(label.didExceedMaxLines, isFalse, reason: name);
        expect(
          label.constraints.maxWidth,
          greaterThanOrEqualTo(_longestWordWidth(label)),
          reason: '$name is broken inside a word',
        );
      }
      final marks = _marks(tester);
      expect(
        marks[3].left - marks[2].right,
        moreOrLessEquals(marks[4].left - marks[3].right),
        reason: 'one pitch between friends',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('130 % with short names keeps one rhythm for every tile', (
      tester,
    ) async {
      _surface(tester, const Size(390, 844));
      // "Ola Nowak" only: no word needs more than the text-scaled tile.
      await tester.pumpWidget(_host(textScale: 1.3, friends: 1));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(_addKey)).width,
        moreOrLessEquals(_tile * 1.3),
      );
      expect(
        _friendTile(tester, 'Ola Nowak').width,
        moreOrLessEquals(_tile * 1.3),
      );
      final marks = _marks(tester);
      expect(marks, hasLength(3));
      expect(
        marks[1].left - marks[0].right,
        moreOrLessEquals(marks[2].left - marks[1].right),
        reason: 'actions and friends share one pitch',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('43 languages', () {
    final translated = selectableAppLanguages
        .where(
          (language) =>
              language != AppLanguagePreference.english &&
              language != AppLanguagePreference.polish,
        )
        .toList();

    test('every translated locale carries all four rail strings', () {
      expect(AppLocalizations.supportedLocales, hasLength(43));
      expect(translated, hasLength(41));
      expect(
        chatsRailTranslations.keys.toSet(),
        translated.map((language) => language.localeKey).toSet(),
      );
      expect(
        chatsRailTranslationKeys.toSet(),
        hasLength(chatsRailTranslationKeys.length),
      );
      expect(appTranslationKeys, containsAll(chatsRailTranslationKeys));
      const english = <String, String>{
        'chatsRail.add': 'Add',
        'chatsRail.write': 'Write',
        'chatsRail.addFriend': 'Add friend',
        'chatsRail.newMessage': 'New message',
      };
      for (final language in translated) {
        final key = language.localeKey;
        final entries = chatsRailTranslations[key]!;
        expect(
          entries.keys.toSet(),
          chatsRailTranslationKeys.toSet(),
          reason: key,
        );
        for (final entry in entries.entries) {
          expect(entry.value.trim(), entry.value, reason: '$key: ${entry.key}');
          expect(entry.value, isNotEmpty, reason: '$key: ${entry.key}');
          expect(
            entry.value,
            isNot(english[entry.key]),
            reason: '$key: English fallback shipped for ${entry.key}',
          );
          expect(
            translatedPhrase(key, entry.key),
            entry.value,
            reason: '$key: ${entry.key} is overridden by another module',
          );
        }
      }
    });

    testWidgets('each language shows a short word that fits the 64 px tile '
        'and says the full phrase', (tester) async {
      _surface(tester, const Size(390, 844));
      final measured = <String, double>{};
      for (final language in selectableAppLanguages) {
        final copy = _copyFor(language);
        final reason = language.localeKey;
        await tester.pumpWidget(_host(locale: language.locale!, friends: 3));
        await tester.pumpAndSettle();

        // The two actions share one width, so both labels have to be
        // measurable for the tile's width to mean anything here.
        final measurable = _interDraws(copy.add) && _interDraws(copy.write);
        for (final (key, short, name) in [
          (_addKey, copy.add, copy.addName),
          (_writeKey, copy.write, copy.writeName),
        ]) {
          expect(
            find.descendant(of: find.byKey(key), matching: find.text(short)),
            findsOneWidget,
            reason: '$reason: "$short"',
          );
          expect(
            find.descendant(
              of: find.byKey(key),
              matching: find.bySemanticsLabel(name),
            ),
            findsOneWidget,
            reason: '$reason: "$name"',
          );
          if (measurable) {
            // No language widens its tile: the rhythm is the same
            // everywhere. (A tile grows to hold a label that would otherwise
            // be cut, so 64 px also says the label fits.)
            expect(
              tester.getSize(find.byKey(key)).width,
              _tile,
              reason: '$reason: "$short"',
            );
          }
          if (_interDraws(short)) {
            final label = _label(tester, key);
            final width = _unbrokenWidth(label);
            measured['$reason "$short"'] = width;
            expect(
              width,
              lessThanOrEqualTo(_labelBox),
              reason: '$reason: "$short" is wider than the label box',
            );
            expect(
              label.didExceedMaxLines,
              isFalse,
              reason: '$reason: "$short" is cut',
            );
          } else {
            // CJK, Arabic-script, Hebrew, Indic and Thai labels are drawn by
            // a device fallback font the test host does not have. They are
            // kept to a few glyphs; with the macOS system fonts the widest
            // are Urdu "شامل کریں" (about 53 px) and Bengali "যোগ করুন"
            // (about 47 px), and test/slim_chats_capture.dart renders every
            // one of them (`rail-languages`).
            expect(
              short.runes.length,
              lessThanOrEqualTo(9),
              reason: '$reason: "$short"',
            );
          }
        }
        expect(tester.getSize(_rail()).height, _railHeight, reason: reason);
        expect(tester.takeException(), isNull, reason: reason);
      }
      // 82 labels in all, 60 of them measurable here; the widest stays
      // inside the box with room to spare.
      expect(measured, hasLength(greaterThanOrEqualTo(60)));
      final widest = measured.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      expect(widest.value, lessThanOrEqualTo(_labelBox - 1), reason: '$widest');
    });

    testWidgets('at 200 % each language keeps its short word whole on at most '
        'two lines, and the two words apart', (tester) async {
      _surface(tester, const Size(390, 844));
      final gaps = <String, double>{};
      for (final language in selectableAppLanguages) {
        final copy = _copyFor(language);
        final reason = language.localeKey;
        await tester.pumpWidget(
          _host(locale: language.locale!, friends: 3, textScale: 2),
        );
        await tester.pumpAndSettle();

        for (final (key, short) in [
          (_addKey, copy.add),
          (_writeKey, copy.write),
        ]) {
          expect(
            tester.getSize(find.byKey(key)).width,
            greaterThanOrEqualTo(_tile * 1.3 - .01),
            reason: '$reason: "$short"',
          );
          if (!_interDraws(short)) continue;
          final label = _label(tester, key);
          expect(
            label.didExceedMaxLines,
            isFalse,
            reason: '$reason: "$short" is cut at 200 %',
          );
          // One 26.4 px line per word at most: a word is never broken.
          final lines = (label.size.height / (11 * 1.2 * 2)).round();
          expect(
            lines,
            lessThanOrEqualTo(short.split(' ').length),
            reason: '$reason: "$short" is broken inside a word',
          );
        }
        // Both actions share one width, so the pair stays even.
        expect(
          tester.getSize(find.byKey(_addKey)).width,
          tester.getSize(find.byKey(_writeKey)).width,
          reason: reason,
        );
        // The two words never run together: at 22 px a 6 px gap is a word
        // space ("Добавить Написать" read as one phrase), so the pair
        // widens until the labels stand 12 px apart.
        if (_interDraws(copy.add) && _interDraws(copy.write)) {
          final add = _inkRect(_label(tester, _addKey));
          final write = _inkRect(_label(tester, _writeKey));
          final gap =
              (add.left < write.left ? write.left : add.left) -
              (add.left < write.left ? add.right : write.right);
          gaps[reason] = gap;
          expect(
            gap,
            greaterThanOrEqualTo(11.5),
            reason: '$reason: "${copy.add}" and "${copy.write}" run together',
          );
        }
        expect(tester.takeException(), isNull, reason: reason);
      }
      expect(gaps, hasLength(greaterThanOrEqualTo(30)));
    });
  });
}
