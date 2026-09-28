import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/likers/data/models/likers_page.dart';

import 'support/likers_fixtures.dart';

void main() {
  group('LikersPage.parse (spec §3.0 exact contract)', () {
    test('parses a valid page with likes and reactions', () {
      final page = LikersPage.parse(
        pageWire([
          likerWire('julia', 'Julia Nowak'),
          likerWire('marta', 'Marta Wiśniewska', reaction: '👍'),
        ], cursor: kTestCursor),
      );
      expect(page.likers, hasLength(2));
      expect(page.likers.first.userId, 'julia');
      expect(page.likers.first.reaction, isNull);
      expect(page.likers.last.reaction, '👍');
      expect(page.nextCursor, kTestCursor);
      expect(page.hasMore, isTrue);
    });

    test('an empty final page is valid', () {
      final page = LikersPage.parse(pageWire(const []));
      expect(page.likers, isEmpty);
      expect(page.hasMore, isFalse);
      expect(page.nextCursor, isNull);
    });

    test('an extra or a missing page key throws', () {
      final extra = pageWire(const [])..['hiddenCount'] = 3;
      expect(() => LikersPage.parse(extra), throwsFormatException);
      final missing = pageWire(const [])..remove('hasMore');
      expect(() => LikersPage.parse(missing), throwsFormatException);
      expect(() => LikersPage.parse(null), throwsFormatException);
      expect(() => LikersPage.parse(const ['x']), throwsFormatException);
    });

    test('a schemaVersion other than 1 throws', () {
      final page = pageWire(const [])..['schemaVersion'] = 2;
      expect(() => LikersPage.parse(page), throwsFormatException);
    });

    test('more than 20 likers throws', () {
      final page = pageWire([
        for (var i = 0; i < 21; i++) likerWire('u$i', 'User $i'),
      ]);
      expect(() => LikersPage.parse(page), throwsFormatException);
      final twenty = pageWire([
        for (var i = 0; i < 20; i++) likerWire('u$i', 'User $i'),
      ]);
      expect(LikersPage.parse(twenty).likers, hasLength(kLikersPageSize));
    });

    test('hasMore must agree with nextCursor', () {
      final moreWithoutCursor = pageWire(const [])..['hasMore'] = true;
      expect(() => LikersPage.parse(moreWithoutCursor), throwsFormatException);
      final cursorWithoutMore = pageWire(const [], cursor: kTestCursor)
        ..['hasMore'] = false;
      expect(() => LikersPage.parse(cursorWithoutMore), throwsFormatException);
    });

    test('a cursor that is not the 43-character opaque token throws', () {
      for (final bad in const ['short', 'a/b', '']) {
        final page = pageWire(const [], cursor: kTestCursor)
          ..['nextCursor'] = bad;
        expect(() => LikersPage.parse(page), throwsFormatException);
      }
      final tooLong = pageWire(const [], cursor: kTestCursor)
        ..['nextCursor'] = '${kTestCursor}A';
      expect(() => LikersPage.parse(tooLong), throwsFormatException);
    });
  });

  group('Liker.parse', () {
    test('a non-null photoUrl throws (avatars resolve by uid only)', () {
      final liker = likerWire('julia', 'Julia')
        ..['photoUrl'] = 'https://x.test/a.jpg';
      expect(() => LikersPage.parse(pageWire([liker])), throwsFormatException);
    });

    test('an extra key (for example username) or a missing key throws', () {
      final extra = likerWire('julia', 'Julia')..['username'] = 'julka';
      expect(() => LikersPage.parse(pageWire([extra])), throwsFormatException);
      final missing = likerWire('julia', 'Julia')..remove('reaction');
      expect(
        () => LikersPage.parse(pageWire([missing])),
        throwsFormatException,
      );
    });

    test('a reaction outside the six message reactions throws', () {
      final liker = likerWire('julia', 'Julia', reaction: '🍕');
      expect(() => LikersPage.parse(pageWire([liker])), throwsFormatException);
    });

    test('malformed ids and names throw', () {
      for (final bad in <Map<String, Object?>>[
        likerWire('', 'Julia'),
        likerWire('a/b', 'Julia'),
        likerWire('julia', ''),
        likerWire('julia', ' Julia'),
        likerWire('julia', 'J' * 81),
      ]) {
        expect(() => LikersPage.parse(pageWire([bad])), throwsFormatException);
      }
    });
  });
}
