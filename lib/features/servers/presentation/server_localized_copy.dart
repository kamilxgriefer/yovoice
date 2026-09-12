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

  // ---------------------------------------------------------------- creation

  /// Group headings for the seeded channel preview. Derived from the channel
  /// kind, because owner-defined categories have no callable and no Rules yet.
  String serverChannelGroup(ServerChannelKind kind) => switch (kind) {
    ServerChannelKind.voice ||
    ServerChannelKind.stage ||
    ServerChannelKind.meeting => text('VOICE', 'GŁOSOWE'),
    ServerChannelKind.text ||
    ServerChannelKind.announcements => text('TEXT', 'TEKSTOWE'),
    // Rules sit with events and the shared tools in every reference panel,
    // not with the conversation channels.
    _ => text('ORGANISATION', 'ORGANIZACJA'),
  };
  String get serverSeededChannelsTitle =>
      text('Channels we will create', 'Kanały, które utworzymy');
  String get serverSeededChannelsBody => text(
    'You can rename them, add your own and change their order once the server exists.',
    'Gdy serwer powstanie, zmienisz ich nazwy, dodasz własne i ustawisz kolejność.',
  );
  String get serverChannelRestricted =>
      text('Limited access', 'Ograniczony dostęp');
  String get serverIconTitle => text('Server icon', 'Ikona serwera');
  String get serverIconBody => text(
    'To begin with, your server carries the first letter of its name — in the template colour.',
    'Na początek serwer nosi pierwszą literę swojej nazwy — w kolorze szablonu.',
  );
  String get serverIconUpload => text('Add a picture', 'Dodaj obrazek');
  String get serverCreating => text('Creating…', 'Tworzenie…');
  String get serverCreateAction => text('Create server', 'Stwórz serwer');
  String get serverTryAgain => text('Try again', 'Spróbuj ponownie');
  String get serverResend => text('Send again', 'Wyślij ponownie');
  String get serverCheckAgain => text('Check again', 'Sprawdź ponownie');
  String get serverCreationUnavailableTitle => text(
    'Creating servers is not available yet',
    'Tworzenie serwerów nie jest jeszcze dostępne',
  );
  String get serverCreationUnavailableBody => text(
    'Nothing was created. This part of YO Voice is still being prepared, so your server could not be saved. Everything you entered is kept here.',
    'Nic nie zostało utworzone. Ta część YO Voice jest jeszcze przygotowywana, więc serwer nie mógł zostać zapisany. Wszystko, co wpisujesz, zostaje tutaj.',
  );
  String get serverCreationOfflineBody => text(
    'We could not finish creating your server. Check your connection — sending it again is safe and will not create a second server.',
    'Nie udało się dokończyć tworzenia serwera. Sprawdź połączenie — ponowne wysłanie jest bezpieczne i nie utworzy drugiego serwera.',
  );
  String get serverCreationCapacityBody => text(
    'You have reached the limit of 20 active servers.',
    'Masz już 20 aktywnych serwerów.',
  );

  /// `invalid-argument`: the payload was refused before any write, so the
  /// form unlocks and a corrected submission is a new request.
  String get serverCreationRejectedBody => text(
    'The server was not created — something in the name or description was not accepted. Correct it and send again.',
    'Serwer nie powstał — coś w nazwie lub opisie nie zostało przyjęte. Popraw i wyślij ponownie.',
  );

  /// `failed-precondition` on the family template: `FAMILY_SERVER_LIMIT` is
  /// one per owner, so the true next step is the server that already exists.
  String get serverCreationFamilyExistsBody => text(
    'You already have a family server — there can be only one. Open it from Servers instead of creating a new one. Nothing was created.',
    'Masz już serwer rodzinny — może być tylko jeden. Otwórz go z listy serwerów zamiast tworzyć nowy. Nic nie zostało utworzone.',
  );

  /// `failed-precondition` on any other template.
  String get serverCreationPreconditionBody => text(
    'This server cannot be created right now. Nothing was created — go back to Servers and check the ones you already have.',
    'Ten serwer nie może teraz powstać. Nic nie zostało utworzone — wróć do serwerów i sprawdź te, które już masz.',
  );

  /// `permission-denied`: the account, not the payload, is what the backend
  /// refused, so resending changes nothing.
  String get serverCreationDeniedBody => text(
    'This account cannot create servers right now. Nothing was created — check that you are signed in to the right account.',
    'To konto nie może teraz tworzyć serwerów. Nic nie zostało utworzone — sprawdź, czy jesteś na właściwym koncie.',
  );

  /// `data-loss`: the backend found saved server data it cannot build on.
  String get serverCreationLostBody => text(
    'Nothing new was created. Go back to Servers — this needs fixing on our side, not another attempt from here.',
    'Nic nowego nie powstało. Wróć do serwerów — to wymaga naprawy po naszej stronie, nie kolejnej próby stąd.',
  );

  /// Shown when the configuration step is re-entered while an earlier
  /// submission for this owner and template is still unresolved.
  String get serverCreationResumedBody => text(
    'Your last attempt to create this server was not confirmed. Send it again — that is safe and will not create a second server.',
    'Ostatnia próba utworzenia tego serwera nie została potwierdzona. Wyślij ponownie — to bezpieczne i nie utworzy drugiego serwera.',
  );
  String get serverCreationRetrySafe => text(
    'Everything you type stays right here.',
    'Wszystko, co wpisujesz, zostaje na miejscu.',
  );

  /// The free allowance, stated per template: `FREE_SERVER_LIMIT` is 20 for
  /// four templates, while a family server is charged to `familyFreeV1` with
  /// a limit of one per owner and never to the 20-server allowance.
  String get serverCreationAllowanceBody => text(
    'You can create up to 20 servers for free.',
    'Możesz bezpłatnie utworzyć do 20 serwerów.',
  );
  String get serverCreationFamilyAllowanceBody => text(
    'You can have one family server. It does not count towards your 20 free servers.',
    'Serwer rodzinny może być tylko jeden. Nie wlicza się do 20 bezpłatnych serwerów.',
  );
  String get serverInviteIntroTitle =>
      text('Your server is waiting for people', 'Serwer czeka na ludzi');
  String get serverInviteIntroBody => text(
    'A server starts with you. Invite the people who belong here.',
    'Serwer zaczyna się od Ciebie. Zaproś osoby, które mają tu być.',
  );
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

  /// "12 osób" — a count, not a label, as every mockup writes it.
  ///
  /// Polish needs three forms (1 osoba / 2–4 osoby / 5+ osób, with 12–14
  /// and every x2–x4 above 20 following the usual exception), so the Polish
  /// branch selects its own form the way `unreadConversations` does.
  String serverMembers(int count) {
    if (isPolish) {
      if (count == 1) return '1 osoba';
      final lastTwo = count % 100;
      final last = count % 10;
      if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) {
        return '$count osoby';
      }
      return '$count osób';
    }
    return count == 1
        ? template('{count} person', '{count} osoba', values: {'count': count})
        : template('{count} people', '{count} osób', values: {'count': count});
  }

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
