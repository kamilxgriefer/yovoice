import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/rooms/data/models/room_metadata.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';

void main() {
  test(
    'podcast production metadata survives the Firestore model boundary',
    () async {
      final firestore = FakeFirebaseFirestore();
      final reference = firestore.collection('rooms').doc('podcast');
      await reference.set({
        'hostId': 'host',
        'hostName': 'Ada',
        'name': 'Signal & Story',
        'description': 'A show about thoughtful technology.',
        'category': 'technology',
        'visibility': 'public',
        'language': 'English',
        'participantCount': 11,
        'memberCount': 0,
        'isLive': true,
        'roomType': 'temporary',
        'status': 'active',
        'experience': 'broadcast',
        'topic': 'Can independent podcasts stay independent?',
        'showFormat': 'panel',
        'roomGuidelines': 'Stay concise and challenge ideas, not people.',
        'audienceCanSpeak': false,
        'handRaisingEnabled': false,
        'stageLimit': 6,
      });

      final room = VoiceRoom.fromFirestore(await reference.get());

      expect(room.topic, 'Can independent podcasts stay independent?');
      expect(room.showFormat, ShowFormat.panel);
      expect(room.roomGuidelines, contains('challenge ideas'));
      expect(room.audienceCanSpeak, isFalse);
      expect(room.handRaisingEnabled, isFalse);
      expect(room.stageLimit, 6);
      expect(room.toMap()['topic'], room.topic);
      expect(room.toMap()['showFormat'], 'panel');
    },
  );

  test('legacy podcasts get safe producer defaults', () async {
    final firestore = FakeFirebaseFirestore();
    final reference = firestore.collection('rooms').doc('legacy-podcast');
    await reference.set({
      'hostId': 'host',
      'hostName': 'Host',
      'name': 'Legacy show',
      'description': '',
      'category': 'talk',
      'visibility': 'public',
      'language': 'English',
      'participantCount': 0,
      'memberCount': 0,
      'isLive': false,
      'roomType': 'temporary',
      'status': 'active',
      'experience': 'broadcast',
    });

    final room = VoiceRoom.fromFirestore(await reference.get());

    expect(room.topic, isEmpty);
    expect(room.handRaisingEnabled, isTrue);
    expect(room.stageLimit, 8);
  });
}
