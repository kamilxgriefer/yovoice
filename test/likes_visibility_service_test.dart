import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/likes_visibility_service.dart';

void main() {
  group('LikesVisibilityService.setHidden', () {
    test(
      'sends exactly {hidden} and parses exactly {hidden, changed}',
      () async {
        final sent = <Map<String, dynamic>>[];
        final service = LikesVisibilityService(
          mutationInvoker: (data) async {
            sent.add(data);
            return {'hidden': data['hidden'], 'changed': true};
          },
        );
        final on = await service.setHidden(true);
        expect(on.hidden, isTrue);
        expect(on.changed, isTrue);
        final off = await service.setHidden(false);
        expect(off.hidden, isFalse);
        expect(sent, [
          {'hidden': true},
          {'hidden': false},
        ]);
      },
    );

    for (final (label, response) in <(String, Map<String, dynamic>)>[
      ('extra key', {'hidden': true, 'changed': true, 'likesHidden': true}),
      ('missing key', {'hidden': true}),
      ('wrong type', {'hidden': 'true', 'changed': true}),
      ('changed not bool', {'hidden': true, 'changed': 1}),
      ('a different value than asked', {'hidden': false, 'changed': false}),
    ]) {
      test('rejects a response with $label', () {
        final service = LikesVisibilityService(
          mutationInvoker: (_) async => response,
        );
        expect(
          service.setHidden(true),
          throwsA(isA<LikesVisibilityException>()),
        );
      });
    }

    test('callable and transport errors become LikesVisibilityException', () {
      expect(
        LikesVisibilityService(
          mutationInvoker: (_) async => throw FirebaseFunctionsException(
            code: 'resource-exhausted',
            message: 'slow down',
          ),
        ).setHidden(true),
        throwsA(isA<LikesVisibilityException>()),
      );
      expect(
        LikesVisibilityService(
          mutationInvoker: (_) async => throw StateError('offline'),
        ).setHidden(true),
        throwsA(isA<LikesVisibilityException>()),
      );
    });
  });

  group('UserProfile.likesHidden (fail closed like likesHiddenOf)', () {
    Future<UserProfile> parse(Object? value, {bool present = true}) async {
      final db = FakeFirebaseFirestore();
      final ref = db.collection('users').doc('me');
      await ref.set({'displayName': 'Me', if (present) 'likesHidden': value});
      return UserProfile.fromFirestore(await ref.get());
    }

    test('missing, null or false = visible', () async {
      expect((await parse(null, present: false)).likesHidden, isFalse);
      expect((await parse(null)).likesHidden, isFalse);
      expect((await parse(false)).likesHidden, isFalse);
    });

    test('true or any malformed value = hidden', () async {
      expect((await parse(true)).likesHidden, isTrue);
      expect((await parse('false')).likesHidden, isTrue);
      expect((await parse(0)).likesHidden, isTrue);
    });
  });
}
