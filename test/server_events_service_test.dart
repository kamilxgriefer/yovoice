import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server_event.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';

Map<String, Object?> eventData({
  required String eventId,
  required DateTime startsAt,
  required DateTime endsAt,
  String status = 'scheduled',
}) => <String, Object?>{
  'schemaVersion': 1,
  'serverId': 'family',
  'channelId': 'calendar',
  'eventId': eventId,
  'eventKind': 'familyCalendarEvent',
  'serverType': 'family',
  'channelKind': 'calendar',
  'rsvpEnabled': true,
  'reminderOptInEnabled': true,
  'title': 'Termin $eventId',
  'description': '',
  'startsAt': Timestamp.fromDate(startsAt),
  'endsAt': Timestamp.fromDate(endsAt),
  'timeZone': 'Europe/Warsaw',
  'status': status,
  'responseCounts': const {'going': 1, 'maybe': 2, 'declined': 0},
  'reminderCount': 1,
  'authorId': 'owner',
  'revision': 2,
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 1)),
  'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 9, 1)),
};

void main() {
  test(
    'events query drops ended rows and sorts the remainder by start',
    () async {
      final now = DateTime.utc(2026, 9, 13, 12);
      final firestore = FakeFirebaseFirestore();
      final events = firestore
          .collection('clubs')
          .doc('family')
          .collection('channels')
          .doc('calendar')
          .collection('events');
      await events
          .doc('ended')
          .set(
            eventData(
              eventId: 'ended',
              startsAt: now.subtract(const Duration(hours: 2)),
              endsAt: now.subtract(const Duration(minutes: 1)),
            ),
          );
      await events
          .doc('later')
          .set(
            eventData(
              eventId: 'later',
              startsAt: now.add(const Duration(hours: 4)),
              endsAt: now.add(const Duration(hours: 5)),
            ),
          );
      await events
          .doc('sooner')
          .set(
            eventData(
              eventId: 'sooner',
              startsAt: now.add(const Duration(hours: 1)),
              endsAt: now.add(const Duration(hours: 6)),
            ),
          );
      await events
          .doc('cancelled')
          .set(
            eventData(
              eventId: 'cancelled',
              startsAt: now.add(const Duration(minutes: 30)),
              endsAt: now.add(const Duration(hours: 1)),
              status: 'cancelled',
            ),
          );
      final service = ServerService(firestore: firestore, now: () => now);

      final result = await service.watchEvents('family', 'calendar').first;

      expect(result.map((event) => event.id), ['sooner', 'later']);
      expect(result.every((event) => event.endsAt.isAfter(now)), isTrue);
    },
  );

  test('my response decodes RSVP and reminder from the exact V1 row', () async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'listener'),
    );
    final response = firestore
        .collection('clubs')
        .doc('family')
        .collection('channels')
        .doc('calendar')
        .collection('events')
        .doc('event')
        .collection('responses')
        .doc('listener');
    await response.set({
      'schemaVersion': 1,
      'serverId': 'family',
      'channelId': 'calendar',
      'eventId': 'event',
      'userId': 'listener',
      'response': 'going',
      'reminderRequested': true,
      'eventRevision': 4,
      'operationId': 'request-1',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 13)),
      'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 9, 13)),
    });
    final service = ServerService(firestore: firestore, auth: auth);

    expect(
      await service
          .watchMyEventResponse('family', 'calendar', 'event')
          .firstWhere((value) => value != null),
      const ServerEventAttendance(
        response: ServerEventResponse.going,
        reminderRequested: true,
      ),
    );
  });
}
