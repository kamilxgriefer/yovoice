import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timezone/data/latest.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as time_zone;

import 'server_channel.dart';
import 'server_type.dart';

enum ServerEventStatus { scheduled, cancelled }

enum ServerEventResponse { going, maybe, declined }

enum ServerEventKind {
  friendsEvent,
  communityEvent,
  familyCalendarEvent,
  podcastProgramEvent;

  static ServerEventKind? tryParse(Object? value) {
    for (final kind in values) {
      if (kind.name == value) return kind;
    }
    return null;
  }
}

class ServerEventAttendance {
  const ServerEventAttendance({
    required this.response,
    required this.reminderRequested,
  });

  final ServerEventResponse response;
  final bool reminderRequested;

  @override
  bool operator ==(Object other) =>
      other is ServerEventAttendance &&
      other.response == response &&
      other.reminderRequested == reminderRequested;

  @override
  int get hashCode => Object.hash(response, reminderRequested);
}

class ServerEvent {
  const ServerEvent({
    required this.id,
    required this.serverId,
    required this.channelId,
    required this.title,
    required this.description,
    required this.startsAt,
    required this.endsAt,
    required this.timeZone,
    required this.status,
    required this.authorId,
    required this.revision,
    this.eventKind = ServerEventKind.friendsEvent,
    this.serverType = ServerType.friends,
    this.channelKind = ServerChannelKind.events,
    this.rsvpEnabled = true,
    this.reminderOptInEnabled = false,
    this.reminderCount = 0,
    this.goingCount = 0,
    this.maybeCount = 0,
    this.declinedCount = 0,
  });

  final String id;
  final String serverId;
  final String channelId;
  final String title;
  final String description;
  final DateTime startsAt;
  final DateTime endsAt;
  final String timeZone;
  final ServerEventStatus status;
  final String authorId;
  final int revision;
  final ServerEventKind eventKind;
  final ServerType serverType;
  final ServerChannelKind channelKind;
  final bool rsvpEnabled;
  final bool reminderOptInEnabled;
  final int reminderCount;
  final int goingCount;
  final int maybeCount;
  final int declinedCount;

  factory ServerEvent.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required String serverId,
    required String channelId,
  }) {
    final data = document.data();
    if (data == null ||
        data['schemaVersion'] != 1 ||
        data['serverId'] != serverId ||
        data['channelId'] != channelId ||
        data['eventId'] != document.id) {
      throw const FormatException('Unsupported server event.');
    }
    final startsAt = _date(data['startsAt']);
    final endsAt = _date(data['endsAt']);
    final title = _text(data['title']);
    final description = data['description'];
    final timeZone = _text(data['timeZone']);
    final authorId = _text(data['authorId']);
    final eventKind = ServerEventKind.tryParse(data['eventKind']);
    final serverType = _serverType(data['serverType']);
    final channelKind = _channelKind(data['channelKind']);
    final revision = data['revision'];
    final status = switch (data['status']) {
      'scheduled' => ServerEventStatus.scheduled,
      'cancelled' => ServerEventStatus.cancelled,
      _ => null,
    };
    final counts = data['responseCounts'];
    if (startsAt == null ||
        endsAt == null ||
        !endsAt.isAfter(startsAt) ||
        title == null ||
        description is! String ||
        timeZone == null ||
        !ServerEventTime.isValidZone(timeZone) ||
        authorId == null ||
        revision is! int ||
        revision < 1 ||
        status == null ||
        counts is! Map ||
        !_validResponseCounts(counts) ||
        eventKind == null ||
        serverType == null ||
        channelKind == null ||
        !_matchesProfile(eventKind, serverType, channelKind) ||
        data['rsvpEnabled'] != true ||
        data['reminderOptInEnabled'] != _supportsReminder(eventKind) ||
        !_isCount(data['reminderCount'])) {
      throw const FormatException('Unsupported server event.');
    }
    return ServerEvent(
      id: document.id,
      serverId: serverId,
      channelId: channelId,
      title: title,
      description: description,
      startsAt: startsAt.toUtc(),
      endsAt: endsAt.toUtc(),
      timeZone: timeZone,
      status: status,
      authorId: authorId,
      revision: revision,
      eventKind: eventKind,
      serverType: serverType,
      channelKind: channelKind,
      rsvpEnabled: true,
      reminderOptInEnabled: data['reminderOptInEnabled'] as bool,
      reminderCount: data['reminderCount'] as int,
      goingCount: _count(counts['going']),
      maybeCount: _count(counts['maybe']),
      declinedCount: _count(counts['declined']),
    );
  }

  bool acceptsResponsesAt(DateTime now) =>
      status == ServerEventStatus.scheduled && startsAt.isAfter(now.toUtc());
}

/// Converts between the wall clock a person picks and the absolute UTC instant
/// stored by Firestore. Keeping this independent from the device time zone is
/// what lets an event created in Warsaw display correctly in every country.
abstract final class ServerEventTime {
  static bool _initialized = false;

  static void _ensureInitialized() {
    if (_initialized) return;
    time_zone_data.initializeTimeZones();
    _initialized = true;
  }

  static time_zone.Location? _location(String zone) {
    _ensureInitialized();
    if (zone.trim().toUpperCase() == 'UTC') return time_zone.UTC;
    try {
      return time_zone.getLocation(zone.trim());
    } on time_zone.LocationNotFoundException {
      return null;
    }
  }

  static bool isValidZone(String zone) => _location(zone) != null;

  /// The fields shown to a person in [zone] for an already stored [instant].
  static DateTime inZone(DateTime instant, String zone) {
    final location = _location(zone);
    if (location == null) throw ArgumentError.value(zone, 'zone');
    return time_zone.TZDateTime.from(instant.toUtc(), location);
  }

  /// A zone-neutral holder for year/month/day/hour/minute form fields.
  static DateTime wallClock(DateTime value) => DateTime.utc(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute,
  );

  /// Interprets [wallClock] in [zone] and returns the Firestore UTC instant.
  static DateTime wallClockToUtc(DateTime wallClock, String zone) {
    final location = _location(zone);
    if (location == null) throw ArgumentError.value(zone, 'zone');
    return time_zone.TZDateTime(
      location,
      wallClock.year,
      wallClock.month,
      wallClock.day,
      wallClock.hour,
      wallClock.minute,
    ).toUtc();
  }
}

DateTime? _date(Object? value) => switch (value) {
  Timestamp timestamp => timestamp.toDate(),
  DateTime date => date,
  _ => null,
};

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _count(Object? value) => value is int && value >= 0 ? value : 0;

bool _isCount(Object? value) => value is int && value >= 0;

bool _validResponseCounts(Map<Object?, Object?> counts) =>
    counts.length == 3 &&
    counts.keys.toSet().containsAll(const {'going', 'maybe', 'declined'}) &&
    _isCount(counts['going']) &&
    _isCount(counts['maybe']) &&
    _isCount(counts['declined']);

bool _supportsReminder(ServerEventKind kind) =>
    kind == ServerEventKind.familyCalendarEvent ||
    kind == ServerEventKind.podcastProgramEvent;

ServerType? _serverType(Object? value) {
  for (final type in ServerType.values) {
    if (type.name == value) return type;
  }
  return null;
}

ServerChannelKind? _channelKind(Object? value) {
  for (final kind in ServerChannelKind.values) {
    if (kind.name == value) return kind;
  }
  return null;
}

bool _matchesProfile(
  ServerEventKind eventKind,
  ServerType serverType,
  ServerChannelKind channelKind,
) => switch (eventKind) {
  ServerEventKind.friendsEvent =>
    serverType == ServerType.friends && channelKind == ServerChannelKind.events,
  ServerEventKind.communityEvent =>
    serverType == ServerType.community &&
        channelKind == ServerChannelKind.events,
  ServerEventKind.familyCalendarEvent =>
    serverType == ServerType.family &&
        channelKind == ServerChannelKind.calendar,
  ServerEventKind.podcastProgramEvent =>
    serverType == ServerType.podcast && channelKind == ServerChannelKind.events,
};
