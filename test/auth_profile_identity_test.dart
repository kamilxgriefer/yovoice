import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/auth/data/auth_profile_identity.dart';

void main() {
  group('federated auth profile identity', () {
    test('prefers a valid provider display name', () {
      expect(
        resolveAuthProfileName(
          displayName: '  Ada Lovelace  ',
          email: 'ada@example.com',
        ),
        'Ada Lovelace',
      );
    });

    test('rejects a one-grapheme provider name and uses the email', () {
      expect(
        resolveAuthProfileName(displayName: 'A', email: 'alice@example.com'),
        'alice',
      );
    });

    test('truncates to the rules UTF-16 budget on grapheme boundaries', () {
      final value = resolveAuthProfileName(
        displayName: List.filled(121, '👨‍👩‍👧‍👦').join(),
        email: 'family@example.com',
      );

      expect(value.length, lessThanOrEqualTo(120));
      expect(value.characters.length, 10);
      expect(value.endsWith('👨‍👩‍👧‍👦'), isTrue);
    });

    test('accepts an emoji only when it fits the rules minimum', () {
      final value = resolveAuthProfileName(
        displayName: '🙂',
        email: 'emoji@example.com',
      );

      expect(value, '🙂');
      expect(value.length, 2);
    });

    test('uses a safe fallback when provider identity is unusable', () {
      expect(
        resolveAuthProfileName(displayName: 'X', email: 'x@example.com'),
        'YO Voice User',
      );
    });
  });
}
