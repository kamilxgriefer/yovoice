import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/rooms/data/room_links.dart';

void main() {
  group('roomShareLink', () {
    test('builds the canonical ?room= form the deep-link handler reads', () {
      expect(roomShareLink('room-1'), 'https://yovoice.app/?room=room-1');
    });

    test('refuses an id the deep-link guard would refuse', () {
      expect(() => roomShareLink('../x'), throwsArgumentError);
      expect(() => roomShareLink(''), throwsArgumentError);
      expect(() => roomShareLink('a' * 129), throwsArgumentError);
    });
  });

  group('tryParseRoomLink', () {
    test('accepts the canonical form and its host variants', () {
      expect(tryParseRoomLink('https://yovoice.app/?room=abc_9-Z'), 'abc_9-Z');
      expect(tryParseRoomLink('https://www.yovoice.app/?room=r1'), 'r1');
      expect(tryParseRoomLink('https://app.yovoice.app/?room=r1'), 'r1');
      expect(tryParseRoomLink('  https://yovoice.app/?room=r1  '), 'r1');
    });

    test('accepts the legacy /rooms/{id} path for already-sent links', () {
      expect(tryParseRoomLink('https://yovoice.app/rooms/r1'), 'r1');
      expect(tryParseRoomLink('https://yovoice.app/rooms/r1/'), 'r1');
    });

    test('refuses foreign hosts, other schemes and malformed ids', () {
      expect(tryParseRoomLink('https://example.com/?room=r1'), isNull);
      expect(tryParseRoomLink('https://yovoice.app.evil.com/?room=r1'), isNull);
      expect(tryParseRoomLink('http://yovoice.app/?room=r1'), isNull);
      expect(tryParseRoomLink('https://yovoice.app/?room=../x'), isNull);
      expect(tryParseRoomLink('https://yovoice.app/?room='), isNull);
      expect(tryParseRoomLink('https://yovoice.app/?club=r1'), isNull);
      expect(tryParseRoomLink('https://yovoice.app/rooms/'), isNull);
      expect(tryParseRoomLink('https://yovoice.app/rooms/a/b'), isNull);
      expect(tryParseRoomLink('https://yovoice.app/download'), isNull);
      expect(tryParseRoomLink('room-1'), isNull);
      expect(tryParseRoomLink(''), isNull);
    });
  });

  group('findRoomLinkId', () {
    test('finds the link inside invitation text', () {
      expect(
        findRoomLinkId(
          'Join me in The Lounge on YO Voice: https://yovoice.app/?room=r1',
        ),
        'r1',
      );
    });

    test('ignores trailing sentence punctuation', () {
      expect(
        findRoomLinkId('Come to https://yovoice.app/?room=r1. It is live!'),
        'r1',
      );
      expect(findRoomLinkId('(https://yovoice.app/?room=r1)'), 'r1');
    });

    test('returns null for plain text and foreign links', () {
      expect(findRoomLinkId('See you in the room'), isNull);
      expect(findRoomLinkId('https://example.com/?room=r1'), isNull);
      expect(findRoomLinkId('https://yovoice.app/?moment=m1'), isNull);
      expect(findRoomLinkId('yovoice.app/?room=r1'), isNull);
    });

    test('takes the first valid link when several are present', () {
      expect(
        findRoomLinkId(
          'https://example.com/?room=x then https://yovoice.app/?room=a '
          'and https://yovoice.app/?room=b',
        ),
        'a',
      );
    });
  });
}
