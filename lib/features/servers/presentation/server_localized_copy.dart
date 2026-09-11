import 'package:yovoice/core/localization/app_localizations.dart';

import '../data/models/server_channel.dart';
import '../data/models/server_type.dart';

extension ServerLocalizedCopy on AppLocalizations {
  String get serversTitle => text('Servers', 'Serwery');
  String get createServerTitle =>
      text('Create your server.', 'Stwórz swój serwer.');
  String get serverSelectorEyebrow =>
      text('YOUR SPACE STARTS HERE', 'TWOJA PRZESTRZEŃ ZACZYNA SIĘ TUTAJ');
  String get serverSelectorQuestion =>
      text('Who are you creating a place for?', 'Dla kogo tworzysz miejsce?');
  String get serverSelectorLead => text(
    'Choose a starting point. Then make it your own.',
    'Wybierz początek. Potem nadaj mu własny charakter.',
  );
  String serverTypeTitle(ServerType type) => switch (type) {
    ServerType.friends => text('For friends', 'Dla znajomych'),
    ServerType.community => text('For a community', 'Dla społeczności'),
    ServerType.podcast => text('For a podcast', 'Dla podcastu'),
    ServerType.family => text('For family', 'Dla rodziny'),
    ServerType.company => text('For a company', 'Dla firmy'),
  };
  String serverTypeDescription(ServerType type) => switch (type) {
    ServerType.friends => text(
      'Your conversations, shared plans and endless evenings.',
      'Wasze rozmowy, wspólne plany i wieczory bez końca.',
    ),
    ServerType.community => text(
      'One place for people who share a passion.',
      'Jedno miejsce dla ludzi, których łączy wspólna pasja.',
    ),
    ServerType.podcast => text(
      'Your show, invited guests and attentive listeners.',
      'Twoja audycja, zaproszeni goście i uważni słuchacze.',
    ),
    ServerType.family => text(
      'Everyday closeness. Even when miles separate you.',
      'Bliskość na co dzień. Nawet kiedy dzielą was kilometry.',
    ),
    ServerType.company => text(
      'Talk, plan and create together as a team.',
      'Rozmawiajcie, planujcie i twórzcie razem jako zespół.',
    ),
  };
  String serverTypeFeatures(ServerType type) => switch (type) {
    ServerType.friends => text(
      'Voice and text channels\nEvents for your group',
      'Kanały głosowe i tekstowe\nWydarzenia dla ekipy',
    ),
    ServerType.community => text(
      'Video broadcasts and a LIVE stage\nChat, events and moderation',
      'Transmisje video i scena LIVE\nCzat, wydarzenia i moderacja',
    ),
    ServerType.podcast => text(
      'Host, guests and audience\nEpisode schedule and questions',
      'Prowadzący, goście i publiczność\nProgram odcinków i pytania',
    ),
    ServerType.family => text(
      'Shared calendar and conversations\nVoice memory album',
      'Wspólny kalendarz i rozmowy\nAlbum wspomnień głosowych',
    ),
    ServerType.company => text(
      'Meetings and screen sharing\nShared whiteboard and team channels',
      'Spotkania i udostępnianie ekranu\nWspólna tablica i kanały zespołów',
    ),
  };
  String serverPrivacyTitle(ServerPrivacy privacy) => switch (privacy) {
    ServerPrivacy.public => text('Public', 'Publiczny'),
    ServerPrivacy.private => text('Private', 'Prywatny'),
    ServerPrivacy.inviteOnly => text('Invite only', 'Tylko na zaproszenie'),
  };
  String serverPrivacyDescription(ServerPrivacy privacy) => switch (privacy) {
    ServerPrivacy.public => text(
      'People can discover this server and join.',
      'Inne osoby mogą znaleźć ten serwer i dołączyć.',
    ),
    ServerPrivacy.private => text(
      'Content is available only to members.',
      'Treści są dostępne tylko dla członków.',
    ),
    ServerPrivacy.inviteOnly => text(
      'Only people you invite can join.',
      'Dołączą tylko zaproszone osoby.',
    ),
  };
  String get serverChannels => text('Channels', 'Kanały');
  String get serverInvite => text('Invite', 'Zaproś');
  String get serverComingSoon => text('Coming soon', 'Wkrótce');
  String get serverNoChannels =>
      text('No channels yet', 'Nie ma jeszcze kanałów');
  String get serverNoChannelsBody => text(
    'Channels you have access to will appear here.',
    'Tutaj pojawią się kanały, do których masz dostęp.',
  );
  String get serverHeldBody => text(
    'Your server and channels have been saved. Conversations and shared tools are being prepared.',
    'Serwer i kanały zostały zapisane. Rozmowy i wspólne narzędzia są przygotowywane.',
  );
  String serverMembers(int count) => template(
    'Members: {count}',
    'Osoby na serwerze: {count}',
    values: {'count': count},
  );
  String channelEmptyTitle(ServerChannelKind kind) => switch (kind) {
    ServerChannelKind.voice || ServerChannelKind.meeting => text(
      'A place for your conversation',
      'Miejsce na Waszą rozmowę',
    ),
    ServerChannelKind.stage => text(
      'The stage is quiet',
      'Na scenie jest teraz cicho',
    ),
    ServerChannelKind.events ||
    ServerChannelKind.calendar => text('No plans yet', 'Nie ma jeszcze planów'),
    ServerChannelKind.memories => text(
      'Your shared memories',
      'Wasze wspólne wspomnienia',
    ),
    ServerChannelKind.episodes => text(
      'Your episodes will appear here',
      'Tutaj pojawią się Twoje odcinki',
    ),
    ServerChannelKind.questions => text(
      'A place for questions',
      'Miejsce na pytania',
    ),
    ServerChannelKind.list => text('Your shared list', 'Wasza wspólna lista'),
    ServerChannelKind.whiteboard => text(
      'Room for your ideas',
      'Miejsce na Wasze pomysły',
    ),
    ServerChannelKind.files => text('Your shared files', 'Wasze wspólne pliki'),
    _ => text('The conversation starts with you', 'Rozmowa zaczyna się od Was'),
  };
}
