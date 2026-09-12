import 'package:flutter/foundation.dart';

import 'server_channel.dart';
import 'server_type.dart';

/// The seeded channel set a template creates, mirrored from the reviewed
/// server-owned table in `functions/servers/templates.js`.
///
/// This exists so the configuration step can show a person exactly what the
/// backend will create for them before they commit. It is a PREVIEW of a
/// server-owned decision, never the source of it: the client never submits a
/// channel list, and `createServerV1` seeds from its own copy of this table.
/// When the backend table changes, this one must change with it — the preview
/// is a promise, and an out-of-date promise is worse than none.
///
/// Seed keys, not translated names, are the stable retry and migration
/// identity, exactly as on the server.
@immutable
class ServerTemplateChannel {
  const ServerTemplateChannel({
    required this.seedKey,
    required this.kind,
    required this.englishName,
    required this.polishName,
    this.mediaMode,
    this.restricted = false,
  });

  final String seedKey;
  final ServerChannelKind kind;
  final String englishName;
  final String polishName;
  final ServerMediaMode? mediaMode;

  /// `accessMode: "restricted"` on the server. Only the company template's
  /// `HR` and `Zarząd` rows carry it.
  final bool restricted;

  /// The name this channel is seeded with for [defaultLanguage].
  ///
  /// Matches `templateChannels()`, which picks Polish for a `defaultLanguage`
  /// the server recognises as Polish and English for everything else.
  String nameFor(String defaultLanguage) =>
      serverSeedsInPolish(defaultLanguage) ? polishName : englishName;
}

/// The server's own Polish test, character for character:
/// `/^(pl(?:[-_].*)?|polish|polski)$/iu` in `functions/servers/templates.js`.
///
/// A client preview that disagreed with this would promise `Salon` and seed
/// `Lounge`, so the predicate is copied rather than approximated.
bool serverSeedsInPolish(String defaultLanguage) => RegExp(
  r'^(pl([-_].*)?|polish|polski)$',
  caseSensitive: false,
  unicode: true,
).hasMatch(defaultLanguage);

/// Every template's seeded channels, in the order the server writes them.
///
/// Position in this list is the channel's `position`, so the preview lists
/// them in the same order the workspace will.
const serverTemplateChannels = <ServerType, List<ServerTemplateChannel>>{
  ServerType.friends: [
    ServerTemplateChannel(
      seedKey: 'general',
      kind: ServerChannelKind.text,
      englishName: 'general',
      polishName: 'ogólny',
    ),
    ServerTemplateChannel(
      seedKey: 'memes',
      kind: ServerChannelKind.text,
      englishName: 'memes',
      polishName: 'memy',
    ),
    ServerTemplateChannel(
      seedKey: 'lounge',
      kind: ServerChannelKind.voice,
      englishName: 'Lounge',
      polishName: 'Salon',
      mediaMode: ServerMediaMode.audio,
    ),
    ServerTemplateChannel(
      seedKey: 'gaming',
      kind: ServerChannelKind.voice,
      englishName: 'Gaming',
      polishName: 'Gaming',
      mediaMode: ServerMediaMode.audio,
    ),
    ServerTemplateChannel(
      seedKey: 'events',
      kind: ServerChannelKind.events,
      englishName: 'Events',
      polishName: 'Wydarzenia',
    ),
    ServerTemplateChannel(
      seedKey: 'rules',
      kind: ServerChannelKind.rules,
      englishName: 'Rules',
      polishName: 'Zasady',
    ),
  ],
  ServerType.community: [
    ServerTemplateChannel(
      seedKey: 'announcements',
      kind: ServerChannelKind.announcements,
      englishName: 'Announcements',
      polishName: 'Ogłoszenia',
    ),
    ServerTemplateChannel(
      seedKey: 'rules',
      kind: ServerChannelKind.rules,
      englishName: 'Rules',
      polishName: 'Regulamin',
    ),
    ServerTemplateChannel(
      seedKey: 'general',
      kind: ServerChannelKind.text,
      englishName: 'general',
      polishName: 'ogólny',
    ),
    ServerTemplateChannel(
      seedKey: 'questions',
      kind: ServerChannelKind.questions,
      englishName: 'Questions',
      polishName: 'Pytania',
    ),
    ServerTemplateChannel(
      seedKey: 'lounge',
      kind: ServerChannelKind.voice,
      englishName: 'Lounge',
      polishName: 'Salon',
      mediaMode: ServerMediaMode.audio,
    ),
    ServerTemplateChannel(
      seedKey: 'stage',
      kind: ServerChannelKind.stage,
      englishName: 'LIVE Stage',
      polishName: 'Scena LIVE',
      mediaMode: ServerMediaMode.video,
    ),
    ServerTemplateChannel(
      seedKey: 'events',
      kind: ServerChannelKind.events,
      englishName: 'Events',
      polishName: 'Wydarzenia',
    ),
  ],
  ServerType.podcast: [
    ServerTemplateChannel(
      seedKey: 'studio',
      kind: ServerChannelKind.stage,
      englishName: 'LIVE Studio',
      polishName: 'Studio LIVE',
      mediaMode: ServerMediaMode.audio,
    ),
    ServerTemplateChannel(
      seedKey: 'episodes',
      kind: ServerChannelKind.episodes,
      englishName: 'Episodes',
      polishName: 'Odcinki',
    ),
    ServerTemplateChannel(
      seedKey: 'program',
      kind: ServerChannelKind.events,
      englishName: 'Program',
      polishName: 'Program',
    ),
    ServerTemplateChannel(
      seedKey: 'discussion',
      kind: ServerChannelKind.text,
      englishName: 'discussion',
      polishName: 'dyskusje',
    ),
    ServerTemplateChannel(
      seedKey: 'questions',
      kind: ServerChannelKind.questions,
      englishName: 'Questions',
      polishName: 'Pytania',
    ),
    ServerTemplateChannel(
      seedKey: 'announcements',
      kind: ServerChannelKind.announcements,
      englishName: 'Announcements',
      polishName: 'Ogłoszenia',
    ),
    ServerTemplateChannel(
      seedKey: 'rules',
      kind: ServerChannelKind.rules,
      englishName: 'Rules',
      polishName: 'Zasady',
    ),
  ],
  ServerType.family: [
    ServerTemplateChannel(
      seedKey: 'family',
      kind: ServerChannelKind.text,
      englishName: 'family',
      polishName: 'rodzinny',
    ),
    ServerTemplateChannel(
      seedKey: 'lounge',
      kind: ServerChannelKind.voice,
      englishName: 'Lounge',
      polishName: 'Salon',
      mediaMode: ServerMediaMode.audio,
    ),
    ServerTemplateChannel(
      seedKey: 'calendar',
      kind: ServerChannelKind.calendar,
      englishName: 'Calendar',
      polishName: 'Kalendarz',
    ),
    ServerTemplateChannel(
      seedKey: 'memories',
      kind: ServerChannelKind.memories,
      englishName: 'Memories',
      polishName: 'Wspomnienia',
    ),
    ServerTemplateChannel(
      seedKey: 'shopping',
      kind: ServerChannelKind.list,
      englishName: 'Shopping list',
      polishName: 'Lista zakupów',
    ),
  ],
  ServerType.company: [
    ServerTemplateChannel(
      seedKey: 'general',
      kind: ServerChannelKind.text,
      englishName: 'general',
      polishName: 'ogólny',
    ),
    ServerTemplateChannel(
      seedKey: 'announcements',
      kind: ServerChannelKind.announcements,
      englishName: 'Announcements',
      polishName: 'Ogłoszenia',
    ),
    ServerTemplateChannel(
      seedKey: 'team',
      kind: ServerChannelKind.text,
      englishName: 'team',
      polishName: 'zespół',
    ),
    ServerTemplateChannel(
      seedKey: 'projects',
      kind: ServerChannelKind.text,
      englishName: 'projects',
      polishName: 'projekty',
    ),
    ServerTemplateChannel(
      seedKey: 'hr',
      kind: ServerChannelKind.text,
      englishName: 'HR',
      polishName: 'HR',
      restricted: true,
    ),
    ServerTemplateChannel(
      seedKey: 'boardroom',
      kind: ServerChannelKind.text,
      englishName: 'Management',
      polishName: 'Zarząd',
      restricted: true,
    ),
    ServerTemplateChannel(
      seedKey: 'meeting',
      kind: ServerChannelKind.meeting,
      englishName: 'Meetings',
      polishName: 'Spotkania',
      mediaMode: ServerMediaMode.meeting,
    ),
    ServerTemplateChannel(
      seedKey: 'board',
      kind: ServerChannelKind.whiteboard,
      englishName: 'Whiteboard',
      polishName: 'Tablica',
    ),
    ServerTemplateChannel(
      seedKey: 'files',
      kind: ServerChannelKind.files,
      englishName: 'Files',
      polishName: 'Pliki',
    ),
  ],
};

List<ServerTemplateChannel> serverTemplateChannelsFor(ServerType type) =>
    serverTemplateChannels[type]!;
