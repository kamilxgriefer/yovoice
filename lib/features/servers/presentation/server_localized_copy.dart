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
  String get serverAvailableAfterJoining =>
      text('Available after joining', 'Dostępne po dołączeniu');
  String get serverManage => text('Manage server', 'Zarządzaj serwerem');
  String get serverSettings => text('Server settings', 'Ustawienia serwera');
  String get serverOverview => text('Overview', 'Serwer');
  String get serverMembersTitle => text('Members', 'Członkowie');
  String get serverSaveChanges => text('Save changes', 'Zapisz zmiany');
  String get serverNameLabel => text('Server name', 'Nazwa serwera');
  String get serverDescriptionLabel => text('Description', 'Opis');
  String get serverPrivacyLabel => text('Privacy', 'Prywatność');
  String get serverSaved => text('Changes saved.', 'Zmiany zostały zapisane.');
  String get serverRenameChannel =>
      text('Rename channel', 'Zmień nazwę kanału');
  String get serverChannelAccess => text('Channel access', 'Dostęp do kanału');
  String get serverEveryoneInServer =>
      text('Everyone in the server', 'Wszyscy na serwerze');
  String get serverRestrictedChannel =>
      text('Restricted — owner access', 'Ograniczony — dostęp właściciela');
  String get serverMoveUp => text('Move up', 'Przenieś wyżej');
  String get serverMoveDown => text('Move down', 'Przenieś niżej');
  String get serverArchiveChannel =>
      text('Archive channel', 'Archiwizuj kanał');
  String get serverDeleteChannel => text('Delete channel', 'Usuń kanał');
  String get serverArchiveChannelQuestion => text(
    'Archive this channel? An active conversation will end.',
    'Zarchiwizować ten kanał? Aktywna rozmowa zostanie zakończona.',
  );
  String get serverDeleteChannelQuestion => text(
    'Delete this channel and its content?',
    'Usunąć ten kanał wraz z jego zawartością?',
  );
  String get serverChangeRole => text('Change role', 'Zmień rolę');
  String get serverTransferOwnership =>
      text('Transfer ownership', 'Przekaż własność');
  String get serverRemoveMember => text('Remove member', 'Usuń członka');
  String get serverBanMember => text('Ban member', 'Zablokuj członka');
  String get serverUnbanMember => text('Lift ban', 'Zdejmij blokadę');
  String get serverBanReason => text('Reason for the ban', 'Powód blokady');
  String get serverLeave => text('Leave server', 'Opuść serwer');
  String get serverDelete => text('Delete server', 'Usuń serwer');
  String get serverLeaveQuestion => text(
    'Leave this server? You will lose access to its channels.',
    'Opuścić ten serwer? Stracisz dostęp do jego kanałów.',
  );
  String get serverDeleteQuestion => text(
    'Delete this server permanently? This cannot be undone.',
    'Usunąć ten serwer na stałe? Tej operacji nie można cofnąć.',
  );
  String get serverConfirm => text('Confirm', 'Potwierdź');
  String get serverCancel => text('Cancel', 'Anuluj');
  String get serverOwnerRole => text('Owner', 'Właściciel');
  String get serverCoOwnerRole => text('Co-owner', 'Współwłaściciel');
  String get serverAdminRole => text('Administrator', 'Administrator');
  String get serverMemberRoleLabel => text('Member', 'Członek');
  String get serverGuestRole => text('Guest', 'Gość');
  String get serverBannedLabel => text('Banned', 'Zablokowany');
  String get serverNoMembers => text(
    'No members are available to manage.',
    'Brak członków dostępnych do zarządzania.',
  );
  String get serverFriendsEvents =>
      text('Plans with your friends', 'Plany z ekipą');
  String get serverFriendsEventsBody => text(
    'Choose a date, let everyone respond and keep the plan in one place.',
    'Wybierz termin, zbierz odpowiedzi i trzymaj wspólny plan w jednym miejscu.',
  );
  String serverEventsTitle(ServerType type) => switch (type) {
    ServerType.friends => serverFriendsEvents,
    ServerType.community => text('Community events', 'Wydarzenia społeczności'),
    ServerType.family => text('Family calendar', 'Rodzinny kalendarz'),
    ServerType.podcast => text('Show program', 'Program audycji'),
    ServerType.company => text('Team calendar', 'Kalendarz zespołu'),
  };
  String serverEventsBody(ServerType type) => switch (type) {
    ServerType.friends => serverFriendsEventsBody,
    ServerType.community => text(
      'Schedule community meetups and let every member respond.',
      'Planuj spotkania społeczności i zbieraj odpowiedzi członków.',
    ),
    ServerType.family => text(
      'Keep family dates, responses and reminders together.',
      'Trzymaj rodzinne terminy, odpowiedzi i przypomnienia w jednym miejscu.',
    ),
    ServerType.podcast => text(
      'Publish the upcoming show program and let listeners set reminders.',
      'Publikuj program audycji i pozwól słuchaczom ustawić przypomnienia.',
    ),
    ServerType.company => text(
      'Keep team dates and responses together.',
      'Trzymaj terminy zespołu i odpowiedzi w jednym miejscu.',
    ),
  };
  String serverCreateEventFor(ServerType type) => switch (type) {
    ServerType.family => text('Add a family plan', 'Dodaj rodzinny termin'),
    ServerType.podcast => text('Schedule a show', 'Zaplanuj audycję'),
    _ => serverCreateEvent,
  };
  String get serverCreateEvent => text('Plan an event', 'Zaplanuj wydarzenie');
  String get serverEditEvent => text('Edit event', 'Edytuj wydarzenie');
  String get serverCancelEvent => text('Cancel event', 'Odwołaj wydarzenie');
  String get serverCancelEventQuestion => text(
    'Cancel this event for everyone?',
    'Odwołać to wydarzenie dla wszystkich?',
  );
  String get serverEventTitle => text('Event name', 'Nazwa wydarzenia');
  String get serverEventDescription => text('Details', 'Szczegóły');
  String get serverEventStarts => text('Starts', 'Początek');
  String get serverEventEnds => text('Ends', 'Koniec');
  String get serverEventTimeZone => text('Time zone', 'Strefa czasowa');
  String get serverEventTimeZoneHint =>
      text('For example Europe/Warsaw', 'Na przykład Europe/Warsaw');
  String get serverNoUpcomingEvents => text(
    'There are no upcoming plans yet.',
    'Nie ma jeszcze żadnych nadchodzących planów.',
  );
  String get serverEventGoing => text('Going', 'Będę');
  String get serverEventMaybe => text('Maybe', 'Może');
  String get serverEventDeclined => text("Can't go", 'Nie mogę');
  String get serverEventReminder => text('Remind me', 'Przypomnij mi');
  String get serverEventStarted => text(
    'Responses closed when this event started.',
    'Odpowiedzi zostały zamknięte wraz z rozpoczęciem wydarzenia.',
  );
  String get serverEventCreated =>
      text('The event was added.', 'Wydarzenie zostało dodane.');
  String get serverEventUpdated =>
      text('The event was updated.', 'Wydarzenie zostało zaktualizowane.');
  String get serverEventCancelled =>
      text('The event was cancelled.', 'Wydarzenie zostało odwołane.');
  String get serverEventResponseSaved =>
      text('Your response was saved.', 'Twoja odpowiedź została zapisana.');
  String get serverEventReminderSaved => text(
    'Your reminder preference was saved.',
    'Ustawienie przypomnienia zostało zapisane.',
  );
  String get serverOpenEvents => text('Open events', 'Otwórz wydarzenia');
  String get serverOpenCalendar => text('Open calendar', 'Otwórz kalendarz');
  String get serverOpenProgram => text('Open program', 'Otwórz program');
  String get serverOpenSharedList =>
      text('Open shared list', 'Otwórz wspólną listę');
  String get serverFollowing => text('Following', 'Obserwujesz');
  String get serverEventResponses => text('responses', 'odpowiedzi');
  String get serverEventCreateAction =>
      text('Create event', 'Utwórz wydarzenie');
  String get serverEventUpdateAction => text('Save event', 'Zapisz wydarzenie');
  String get serverPodcastQuestionsTitle =>
      text('Listener questions', 'Pytania słuchaczy');
  String get serverPodcastQuestionsBody => text(
    'Ask during the show, vote for what matters and follow the question currently on air.',
    'Pytaj podczas audycji, głosuj na ważne tematy i śledź pytanie aktualnie na antenie.',
  );
  String get serverPodcastAskQuestion =>
      text('Ask a question', 'Zadaj pytanie');
  String get serverPodcastQuestionHint => text(
    'What would you like the hosts to answer?',
    'O co chcesz zapytać prowadzących?',
  );
  String get serverPodcastSendQuestion =>
      text('Send question', 'Wyślij pytanie');
  String get serverPodcastNoQuestions => text(
    'There are no listener questions yet.',
    'Nie ma jeszcze pytań od słuchaczy.',
  );
  String get serverPodcastVote => text('Vote', 'Głosuj');
  String get serverPodcastRemoveVote => text('Remove vote', 'Cofnij głos');
  String get serverPodcastOnAir => text('On air', 'Na antenie');
  String get serverPodcastPutOnAir => text('Put on air', 'Dodaj na antenę');
  String get serverPodcastRemoveFromAir =>
      text('Remove from on air', 'Zdejmij z anteny');
  String serverPodcastVotes(int count) {
    if (isPolish) {
      if (count == 1) return '1 głos';
      final lastTwo = count % 100;
      final last = count % 10;
      if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) {
        return '$count głosy';
      }
      return '$count głosów';
    }
    return count == 1 ? '1 vote' : '$count votes';
  }

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
    'You have reached your owned Server limit: 5 on Free or 30 on Premium.',
    'Osiągnąłeś limit własnych serwerów: 5 na koncie bezpłatnym lub 30 w Premium.',
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

  /// Every created/owned Server consumes the same 5-Free / 30-Premium
  /// allowance. Memberships never consume it. A family retains its additional
  /// one-per-owner type constraint inside that shared owned-Server boundary.
  String get serverCreationAllowanceBody => text(
    'Own up to 5 Servers on Free or 30 on Premium. Joining is unlimited.',
    'Możesz mieć 5 własnych serwerów bezpłatnie lub 30 w Premium. Dołączasz bez limitu.',
  );
  String get serverCreationFamilyAllowanceBody => text(
    'You can have one Family Server. It counts towards the same 5-Free or 30-Premium owned limit; joining is unlimited.',
    'Możesz mieć jeden serwer rodzinny. Wlicza się do limitu 5 własnych serwerów bezpłatnie lub 30 w Premium; dołączasz bez limitu.',
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
      'Space for your ideas',
      'Miejsce na Wasze pomysły',
    ),
    ServerChannelKind.files => text('Your shared files', 'Wasze wspólne pliki'),
    _ => text('The conversation starts with you', 'Rozmowa zaczyna się od Was'),
  };

  // ------------------------------------------------------------------ shell

  /// The subtitle under the server name, as each board writes it:
  /// "Prywatny serwer · 12 osób", "Społeczność · 248 osób",
  /// "Tylko na zaproszenie · 8 osób", "Przestrzeń firmowa · 24 osoby".
  String serverKindSubtitle(ServerType type, ServerPrivacy privacy) =>
      switch (type) {
        ServerType.friends => text('Private server', 'Prywatny serwer'),
        ServerType.community =>
          privacy == ServerPrivacy.public
              ? text('Community', 'Społeczność')
              : text('Private community', 'Prywatna społeczność'),
        ServerType.podcast => text('Podcast server', 'Serwer podcastu'),
        ServerType.family => serverPrivacyTitle(privacy),
        ServerType.company => text('Company space', 'Przestrzeń firmowa'),
      };

  /// "12 osób w serwerze" — the phone header line.
  String serverMembersInServer(int count) => text(
    '${serverMembers(count)} in the server',
    '${serverMembers(count)} w serwerze',
  );

  /// Group headings by template and kind (contract decision B): derived
  /// from the kind because categories have no callable and no Rules.
  String serverShellChannelGroup(ServerType type, ServerChannelKind kind) {
    switch (type) {
      case ServerType.friends:
        return switch (kind) {
          ServerChannelKind.text ||
          ServerChannelKind.announcements => text('TEXT', 'TEKSTOWE'),
          ServerChannelKind.voice ||
          ServerChannelKind.stage ||
          ServerChannelKind.meeting => text('VOICE', 'GŁOSOWE'),
          _ => text('ORGANISATION', 'ORGANIZACJA'),
        };
      case ServerType.community:
        return switch (kind) {
          ServerChannelKind.announcements ||
          ServerChannelKind.rules => text('START', 'START'),
          ServerChannelKind.stage ||
          ServerChannelKind.events => text('LIVE', 'NA ŻYWO'),
          _ => text('CONVERSATIONS', 'ROZMOWY'),
        };
      case ServerType.podcast:
        return switch (kind) {
          ServerChannelKind.stage ||
          ServerChannelKind.episodes ||
          ServerChannelKind.events => text('PODCAST', 'PODCAST'),
          _ => text('COMMUNITY', 'SPOŁECZNOŚĆ'),
        };
      case ServerType.family:
        return switch (kind) {
          ServerChannelKind.text ||
          ServerChannelKind.announcements ||
          ServerChannelKind.voice ||
          ServerChannelKind.stage ||
          ServerChannelKind.meeting => text('HOME', 'DOM'),
          _ => text('TOGETHER', 'RAZEM'),
        };
      case ServerType.company:
        return switch (kind) {
          ServerChannelKind.text ||
          ServerChannelKind.announcements ||
          ServerChannelKind.rules => text('COMPANY', 'FIRMA'),
          _ => text('TEAM', 'ZESPÓŁ'),
        };
    }
  }

  String get serverAddChannel => text('Add channel', 'Dodaj kanał');
  String get serverBackToServers => text('Back to servers', 'Wróć do serwerów');
  String get serverOpenChannels => text('Open channels', 'Otwórz kanały');
  String get serverInviteBody => text(
    'Invitations go to your friends. They accept it themselves.',
    'Zaproszenia trafiają do Twoich znajomych. Sami je przyjmują.',
  );
  String get serverInviteHeldBody => text(
    'Invitations open once the server is ready.',
    'Zaproszenia będą możliwe, gdy serwer będzie gotowy.',
  );
  String get serverInviteNoFriendsTitle =>
      text('No friends to invite yet', 'Nie masz jeszcze kogo zaprosić');
  String get serverInviteNoFriendsBody => text(
    'Add friends first — a server invitation can only go to a friend.',
    'Najpierw dodaj znajomych — zaproszenie do serwera trafia tylko do znajomego.',
  );
  String serverInviteSent(String name) => template(
    'Invitation sent to {name}',
    'Wysłano zaproszenie do {name}',
    values: {'name': name},
  );
  String serverInvitePending(String name) => template(
    'An invitation for {name} is already waiting',
    'Zaproszenie dla {name} już czeka',
    values: {'name': name},
  );
  String get serverInviteSending => text('Sending…', 'Wysyłanie…');

  /// The Servers backend is missing or its runtime rollout is not available
  /// to this account yet.
  String get serverActionUnavailable => text(
    'This part of YO Voice is still being prepared.',
    'Ta część YO Voice jest jeszcze przygotowywana.',
  );
  String get serverActionDenied => text(
    'You cannot do that in this server.',
    'Nie możesz tego zrobić w tym serwerze.',
  );
  String get serverInviteRefused => text(
    'This person cannot be invited right now.',
    'Tej osoby nie można teraz zaprosić.',
  );

  String get serverNewChannelTitle => text('New channel', 'Nowy kanał');
  String get serverChannelNameLabel => text('Channel name', 'Nazwa kanału');
  String get serverChannelKindLabel => text('Kind', 'Rodzaj');
  String serverChannelKindTitle(ServerChannelKind kind) => switch (kind) {
    ServerChannelKind.text => text('Text', 'Tekstowy'),
    ServerChannelKind.voice => text('Voice', 'Głosowy'),
    ServerChannelKind.announcements => text('Announcements', 'Ogłoszenia'),
    ServerChannelKind.stage => text('Stage', 'Scena'),
    ServerChannelKind.meeting => text('Meeting', 'Spotkanie'),
    ServerChannelKind.events => text('Events', 'Wydarzenia'),
    ServerChannelKind.questions => text('Questions', 'Pytania'),
    ServerChannelKind.rules => text('Rules', 'Zasady'),
    ServerChannelKind.episodes => text('Episodes', 'Odcinki'),
    ServerChannelKind.calendar => text('Calendar', 'Kalendarz'),
    ServerChannelKind.memories => text('Memories', 'Wspomnienia'),
    ServerChannelKind.list => text('List', 'Lista'),
    ServerChannelKind.whiteboard => text('Whiteboard', 'Tablica'),
    ServerChannelKind.files => text('Files', 'Pliki'),
  };
  String get serverChannelRestrictedToggle => text(
    'Limited access — only people you choose see it',
    'Ograniczony dostęp — widzą go tylko wybrane osoby',
  );
  String get serverChannelCreateAction =>
      text('Create channel', 'Utwórz kanał');
  String get serverChannelCreated => text('Channel created', 'Kanał utworzony');
  String get serverChannelNameRequired =>
      text('Give the channel a name.', 'Nadaj kanałowi nazwę.');

  // -------------------------------------------------------------- liveness

  String get serverLivePill => text('LIVE', 'NA ŻYWO');
  String serverLiveSince(String time) => template(
    'Live since {time}',
    'Na żywo od {time}',
    values: {'time': time},
  );
  String serverQuiet(ServerChannelKind kind) => switch (kind) {
    ServerChannelKind.stage => text(
      'The stage is not live',
      'Scena jeszcze nie nadaje',
    ),
    ServerChannelKind.meeting => text(
      'The meeting has not started',
      'Spotkanie się nie rozpoczęło',
    ),
    _ => text('Nobody is talking yet', 'Nikt jeszcze nie rozmawia'),
  };
  String get serverJoinConversation =>
      text('Join the conversation', 'Dołącz do rozmowy');
  String get serverListen => text('Listen', 'Słuchaj');

  /// A stage whose media mode is `video` (board 02's `Scena LIVE`) is watched,
  /// not only heard: `deriveSessionGrant` gives that channel a camera source,
  /// so promising sound alone would understate what the join opens.
  String get serverWatch => text('Watch', 'Oglądaj');
  String get serverGoLive => text('Go live', 'Rozpocznij nadawanie');
  String get serverStartMeeting =>
      text('Start the meeting', 'Rozpocznij spotkanie');
  String get serverJoinMeeting =>
      text('Join the meeting', 'Dołącz do spotkania');
  String get serverStageWaiting => text(
    'You can listen as soon as the stage goes live.',
    'Będzie można słuchać, gdy scena zacznie nadawać.',
  );

  // ---------------------------------------------------------------- session

  String get serverConnecting => text('Connecting…', 'Łączenie…');
  String get serverCheckingAccess =>
      text('Checking access…', 'Sprawdzanie dostępu…');
  String get serverReconnecting => text('Reconnecting…', 'Ponowne łączenie…');
  String get serverLeaving => text('Leaving…', 'Opuszczanie…');
  String get serverConnected => text('connected', 'połączono');

  /// What the dock says when the provider refuses a microphone or headphones
  /// press. It names the outcome rather than the cause: nothing changed, and
  /// the control beside it already shows the state that really holds.
  String get serverAudioControlFailed => text(
    'That audio setting could not be changed.',
    'Nie udało się zmienić ustawienia dźwięku.',
  );
  String get serverListening => text('Listening', 'Słuchasz');
  String get serverInConversation => text('In the conversation', 'W rozmowie');
  String get serverMicrophone => text('Microphone', 'Mikrofon');
  String get serverMicrophoneOn => text('Microphone on', 'Mikrofon włączony');
  String get serverMicrophoneOff =>
      text('Microphone off', 'Mikrofon wyłączony');
  String get serverListenOnly => text('Listening only', 'Tylko słuchasz');

  /// Said of a tile only while the provider reports that person speaking.
  String get serverSpeaking => text('speaking', 'mówi');
  String get serverLeaveConversation =>
      text('Leave the conversation', 'Opuść rozmowę');
  String get serverLeaveShort => text('Leave', 'Opuść');
  String get serverEndConversation => text(
    'End the conversation for everyone',
    'Zakończ rozmowę dla wszystkich',
  );
  String get serverEndShort => text('End', 'Zakończ');
  String get serverEndQuestion => text(
    'End this live conversation for everyone?',
    'Zakończyć tę rozmowę dla wszystkich?',
  );
  String get serverEndingConversation =>
      text('Ending the conversation…', 'Kończenie rozmowy…');
  String get serverEndFailed => text(
    'Could not end the conversation. Try again.',
    'Nie udało się zakończyć rozmowy. Spróbuj ponownie.',
  );
  String get serverPublicJoinTitle =>
      text('Join this server', 'Dołącz do tego serwera');
  String get serverPublicJoinBody => text(
    'Join to open its channels, conversations and events.',
    'Dołącz, aby otworzyć kanały, rozmowy i wydarzenia.',
  );
  String get serverPublicJoinAction => text('Join server', 'Dołącz do serwera');
  String get serverPublicJoining => text('Joining…', 'Dołączanie…');
  String get serverOtherVoiceActive => text(
    'Finish your current call or voice conversation first.',
    'Najpierw zakończ trwającą rozmowę.',
  );
  String get serverJoinFailed =>
      text('Could not join.', 'Nie udało się dołączyć.');
  String get serverConnectionLost =>
      text('The connection was lost.', 'Połączenie zostało przerwane.');
  String get serverDismiss => text('Dismiss', 'Zamknij');
  String get serverHeadphones => text('Headphones', 'Słuchawki');

  /// The `Słuchawki` control is local output only — it never mutes anyone
  /// for anybody else, so its copy talks about what this device hears.
  String get serverHeadphonesOn => text('Sound on', 'Dźwięk włączony');
  String get serverHeadphonesOff => text('Sound off', 'Dźwięk wyłączony');
  String get serverCamera => text('Camera', 'Kamera');
  String get serverCameraOn => text('Camera on', 'Kamera włączona');
  String get serverCameraOff => text('Camera off', 'Kamera wyłączona');
  String get serverCameraControlFailed => text(
    'The camera setting could not be changed.',
    'Nie udało się zmienić ustawienia kamery.',
  );
  String get serverCameraNotAllowed => text(
    'Your role cannot publish camera video in this meeting.',
    'Twoja rola nie może udostępniać obrazu z kamery w tym spotkaniu.',
  );
  String get serverShareScreen => text('Share screen', 'Udostępnij ekran');
  String get serverVideoPreview => text('Video preview', 'Podgląd wideo');
  String get serverYou => text('you', 'Ty');

  // ------------------------------------------------------------------- text

  String serverMessageHint(String channel) => template(
    'Message #{channel}',
    'Wiadomość na #{channel}',
    values: {'channel': channel},
  );
  String get serverNoMessagesTitle =>
      text('No messages yet', 'Nie ma jeszcze wiadomości');
  String serverNoMessagesBody(String channel) => template(
    'Write the first message on #{channel}.',
    'Napisz pierwszą wiadomość na #{channel}.',
    values: {'channel': channel},
  );
  String get serverMessagesFailed =>
      text('Could not load messages', 'Nie udało się wczytać wiadomości');
  String get serverSendFailed => text(
    'Could not send the message. Try again.',
    'Nie udało się wysłać wiadomości. Spróbuj ponownie.',
  );
  String get serverSend => text('Send', 'Wyślij');
  String get serverReadOnlyBody => text(
    'This channel is read-only for your role.',
    'Dla Twojej roli ten kanał jest tylko do odczytu.',
  );
  String get serverAnnouncementsOnlyBody => text(
    'Announcements are posted by moderators.',
    'Ogłoszenia publikują moderatorzy.',
  );
  String get serverMessageDeleted =>
      text('Message deleted', 'Wiadomość usunięta');
  String get serverChat => text('Chat', 'Czat');

  /// The conversation beside a lounge scene, as boards 01 and 03 title it.
  /// The real channel is always named next to it, so the heading describes
  /// the place and never renames the channel it is reading.
  String get serverLoungeChat => text('Lounge chat', 'Czat salonu');

  // ------------------------------------------------------- friends (board 01)

  /// The board's event CTA, backed by the server-scoped events service.
  String get serverEventRsvp => text("I'll join", 'Dołączę');

  /// The card under the salon. It names the shared events module.
  String get serverNextEvent => text('Next event', 'Najbliższe wydarzenie');
  String get serverEventsModuleBody => text(
    'Plan a date and time, then see who is coming.',
    'Zaplanuj datę i godzinę, a potem sprawdź, kto się wybiera.',
  );

  // -------------------------------------------------------- family (board 03)

  /// The family board is a view of the server, not a channel: nothing is
  /// seeded under this name and nothing pretends to be.
  String get serverFamilyHome => text('Family desk', 'Rodzinny pulpit');
  String get serverFamilyHomeTab => text('Home', 'Dom');
  String get serverFamilyHeroTitle =>
      text('Good to be together.', 'Dobrze być razem.');
  String get serverFamilyHeroBody => text(
    'Familiar voices. The same stories. Always our home.',
    'Znajome głosy. Te same historie. Zawsze nasz dom.',
  );
  String get serverFamilyPlans => text('Upcoming plans', 'Najbliższe plany');
  String get serverFamilyPlansBody => text(
    'Family dates and everyone’s response, kept together.',
    'Rodzinne terminy i odpowiedzi wszystkich w jednym miejscu.',
  );
  String get serverFamilyPlansRsvp => text("I'll be there", 'Będę');
  String get serverFamilyMemories =>
      text('Family memories', 'Rodzinne wspomnienia');
  String get serverFamilyMemoriesBody => text(
    'A private album where every photo keeps the voice behind it.',
    'Prywatny album, w którym każde zdjęcie zachowuje głos tej chwili.',
  );
  String get serverFamilyMemoriesPlay => text('Open album', 'Otwórz album');
  String get serverFamilyShopping => text('To buy', 'Do kupienia');
  String get serverFamilyShoppingBody => text(
    'One shared list everyone can add to and tick off.',
    'Jedna wspólna lista, do której każdy może dopisywać i odhaczać rzeczy.',
  );
  String get serverFamilyShoppingAdd => text('Add product', 'Dodaj produkt');

  // ----------------------------------------------------- community (board 02)

  /// Board 02 titles the context panel "Czat na żywo". The real channel is
  /// still named beside it, exactly as the lounge chat is.
  String get serverLiveChat => text('Live chat', 'Czat na żywo');

  /// Drawn only for an id the server roster actually returned with moderator
  /// power or above — never from a display name, a message or a guess.
  String get serverModerator => text('Moderator', 'Moderator');

  /// The 16:9 scene before a join. Video arrives with the token, so there is
  /// nothing to show until the person has joined; that is stated instead of
  /// drawing an empty player.
  String get serverStageJoinToWatch =>
      text('Join to watch and listen.', 'Dołącz, aby oglądać i słuchać.');

  /// Connected, but nobody on stage is sending a picture. The conversation
  /// carries on in sound; the scene says which of the two is happening.
  String get serverStageNoVideo => text(
    'Nobody is sending a picture right now.',
    'Nikt nie przesyła teraz obrazu.',
  );

  /// The people the provider reports in the generation — the only readable
  /// in-session presence there is (contract G3).
  String get serverStageOnAir => text('On air', 'Na antenie');

  /// Board 02's persisted follow action and canonical Server share action.
  String get serverFollow => text('Follow', 'Obserwuj');
  String get serverShare => text('Share', 'Udostępnij');

  /// `setServerSessionHandV1`, offered only inside a joined session.
  String get serverRaiseHand => text('Ask to speak', 'Poproś o głos');
  String get serverLowerHand =>
      text('Cancel the request', 'Anuluj prośbę o głos');
  String get serverHandRaised =>
      text('Your request is with the hosts.', 'Prowadzący widzą Twoją prośbę.');
  String get serverHandSending => text('Sending…', 'Wysyłanie…');
  String get serverHandFailed => text(
    'Could not send your request. Try again.',
    'Nie udało się wysłać prośby. Spróbuj ponownie.',
  );

  /// Participant actions backed by the two generation-bound moderation
  /// callables. The mute wording is deliberately scoped to moderation: it does
  /// not claim to turn on somebody else's local microphone.
  String serverStageManageParticipant(String name) =>
      text('Manage $name', 'Zarządzaj: $name');
  String get serverStageMoveToStage => text('Move to stage', 'Dodaj na scenę');
  String get serverStageMoveToAudience =>
      text('Move to audience', 'Przenieś do publiczności');
  String get serverStageMuteParticipant =>
      text('Apply moderator mute', 'Wycisz jako moderator');
  String get serverStageReleaseMute =>
      text('Release your mute', 'Cofnij swoje wyciszenie');
  String serverStageRoleChanged(String name) => text(
    'Updated $name\'s stage role. They will reconnect with the new access.',
    'Zmieniono rolę osoby $name. Połączy się ponownie z nowym dostępem.',
  );
  String serverStageMuteApplied(String name) => text(
    'Moderator mute applied to $name.',
    'Wyciszenie moderatora zastosowane dla: $name.',
  );
  String serverStageMuteReleased(String name) => text(
    'Your mute was released for $name.',
    'Cofnięto Twoje wyciszenie dla: $name.',
  );
  String serverStageMuteStillActive(String name) => text(
    '$name is still muted by another stage authority.',
    '$name nadal ma wyciszenie nadane przez inną osobę uprawnioną.',
  );
  String get serverStageModerationFailed => text(
    'The participant could not be updated. Try again.',
    'Nie udało się zaktualizować uczestnika. Spróbuj ponownie.',
  );

  /// The stage's own description line when the server has none of its own.
  String get serverCommunityStageBody => text(
    'Live conversations for this community happen here.',
    'Tutaj odbywają się rozmowy na żywo tej społeczności.',
  );

  // ------------------------------------------------------- podcast (board 05)

  /// The two stage roles board 05 prints under the avatars. Both are read
  /// from the role the server signed into that person's own access token —
  /// never from who happens to be talking.
  String get serverPodcastHost => text('Host', 'Prowadzący');
  String get serverPodcastGuest => text('Guest', 'Gość');

  /// The listener strip. It is a strip of the people the provider actually
  /// reports to this device after joining — never a headline count, because
  /// nothing counts listeners (contract G6).
  String get serverPodcastAudience => text('Audience', 'Publiczność');

  /// The audio stage before a join: sound arrives with the token, so there is
  /// nothing to play until the person has joined.
  String get serverPodcastJoinToListen =>
      text('Join to listen live.', 'Dołącz, aby słuchać na żywo.');

  /// Connected, and the provider reports nobody holding a stage role.
  String get serverPodcastNobodyOnAir => text(
    'Nobody is on the air right now.',
    'Nikt nie jest teraz na antenie.',
  );

  /// The studio's own description line when the server has none of its own.
  String get serverPodcastStageBody => text(
    'Live episodes of this show are made here.',
    'Tutaj powstają odcinki tej audycji na żywo.',
  );

  /// Board 05's second action. It opens the server's real questions channel,
  /// where the message goes through the same reviewed path as every other
  /// message; it is not drawn when that channel does not exist.
  String get serverAskQuestion => text('Ask a question', 'Zadaj pytanie');

  /// The panel beside the studio, as board 05 titles it. The real channel is
  /// named beside it, exactly as the lounge and live chats are.
  String get serverListenerQuestions =>
      text('Listener questions', 'Pytania słuchaczy');

  String get serverRecording => text('Recording', 'Nagrywanie audycji');
  String get serverPodcastRecordingIdle => text(
    'This live session is not being recorded.',
    'Ta transmisja nie jest teraz nagrywana.',
  );
  String get serverPodcastRecordingActive =>
      text('Recording', 'Nagrywanie trwa');
  String get serverPodcastRecordingProcessing =>
      text('Processing', 'Przetwarzanie');
  String get serverPodcastRecordingError =>
      text('Recording error', 'Błąd nagrywania');
  String get serverPodcastEpisodeReady => text('Ready', 'Gotowy');
  String get serverPodcastEpisodePublished => text('Published', 'Opublikowany');
  String get serverPodcastStartRecording =>
      text('Start recording', 'Rozpocznij nagrywanie');
  String get serverPodcastStopRecording =>
      text('Stop recording', 'Zatrzymaj nagrywanie');
  String get serverPodcastRecordingTitle =>
      text('Episode title', 'Tytuł odcinka');
  String get serverPodcastRecordingTitleHint => text(
    'Give this recording a clear title',
    'Nadaj nagraniu czytelny tytuł',
  );
  String get serverPodcastFinalize =>
      text('Check processing', 'Sprawdź przetwarzanie');
  String get serverPodcastRetryRecording =>
      text('Retry recording', 'Ponów nagrywanie');
  String get serverPodcastPublishEpisode =>
      text('Publish episode', 'Opublikuj odcinek');
  String get serverEpisodePause => text('Pause', 'Pauza');
  String get serverPodcastEpisodesTitle =>
      text('Episode archive', 'Archiwum odcinków');
  String get serverPodcastEpisodesBody => text(
    'Listen to published episodes. Hosts can finish processing and publish new recordings here.',
    'Słuchaj opublikowanych odcinków. Prowadzący mogą tu kończyć przetwarzanie i publikować nowe nagrania.',
  );
  String get serverPodcastEpisodesEmpty => text(
    'Published recordings will appear here.',
    'Tutaj pojawią się opublikowane nagrania.',
  );

  String get serverNextEpisode => text('Next episode', 'Następny odcinek');
  String get serverNextEpisodeBody => text(
    'Open the show schedule to see upcoming live episodes and reminders.',
    'Otwórz program audycji, aby zobaczyć transmisje i przypomnienia.',
  );
  String get serverEpisodeRemind => text('Remind me', 'Przypomnij');
  String get serverRecentEpisodes =>
      text('Recent episodes', 'Ostatnie odcinki');
  String get serverRecentEpisodesBody => text(
    'Open the archive to play published episodes and manage new recordings.',
    'Otwórz archiwum, aby odtwarzać odcinki i zarządzać nowymi nagraniami.',
  );
  String get serverEpisodePlay => text('Play', 'Odtwórz');

  // ------------------------------------------------------- company (board 04)

  /// Board 04's panel search. It filters the channels this person may
  /// actually see — the list is already in hand — so it is named for what it
  /// searches. Nothing here searches messages, files or people: none of those
  /// has a search index.
  String get serverSearchChannels => text('Search channels', 'Szukaj kanału');
  String get serverSearchNoChannels => text(
    'No channel matches that name.',
    'Żaden kanał nie pasuje do tej nazwy.',
  );
  String get serverSearchClear => text('Clear the search', 'Wyczyść szukanie');

  /// The meeting's own tabs. `Czat` is the shell's ordinary conversation and
  /// keeps its own name.
  String get serverMeetingPresentation => text('Presentation', 'Prezentacja');

  /// The presenter row, from the provider's own roster: it names the person
  /// whose screen track this device is actually receiving.
  String serverMeetingSharing(String name) => template(
    '{name} is sharing their screen',
    '{name} udostępnia ekran',
    values: {'name': name},
  );
  String get serverMeetingYouSharing =>
      text('You are sharing your screen', 'Udostępniasz ekran');
  String get serverMeetingNoPresentation => text(
    'Nobody is sharing a screen right now.',
    'Nikt nie udostępnia teraz ekranu.',
  );
  String get serverMeetingJoinToSee => text(
    'Join the meeting to see what is being shared.',
    'Dołącz do spotkania, aby zobaczyć, co jest udostępniane.',
  );
  String get serverStopSharing => text('Stop sharing', 'Zakończ udostępnianie');
  String get serverShareFailed => text(
    'The screen share did not start.',
    'Nie udało się rozpocząć udostępniania.',
  );

  /// Contract decision D, said plainly on the device that cannot do it. The
  /// receiving half is never in doubt, so the sentence says which half is
  /// missing rather than "unavailable".
  String get serverShareScreenUnavailable => text(
    'This device cannot start a screen share yet.',
    'Z tego urządzenia nie można jeszcze rozpocząć udostępniania ekranu.',
  );

  /// `deriveSessionGrant` gives `screen_share` to the meeting's host only.
  String get serverShareScreenHostOnly => text(
    'The person who started the meeting shares the screen.',
    'Ekran udostępnia osoba, która rozpoczęła spotkanie.',
  );

  /// Board 04's right-hand tiles. They are the provider's in-session roster
  /// and nothing else, so the heading names the room, never a number.
  String get serverMeetingPeople => text('In the meeting', 'W spotkaniu');

  /// Board 04's durable Company whiteboard. The canvas persists each completed
  /// line in the server's whiteboard channel and updates every connected view.
  String get serverMeetingBoard => text('Team whiteboard', 'Tablica zespołu');
  String get serverMeetingBoardBody => text(
    'Open the shared canvas. Completed lines are saved for everyone on this server.',
    'Otwórz wspólny obszar. Ukończone linie zapisują się dla wszystkich na tym serwerze.',
  );

  String get serverCompanyFilesTitle => text('Team files', 'Pliki zespołu');
  String get serverCompanyFilesBody => text(
    'Share private PDFs, images and notes with everyone who can access this channel.',
    'Udostępniaj prywatne PDF-y, obrazy i notatki osobom z dostępem do tego kanału.',
  );
  String get serverCompanyFilesEmptyTitle =>
      text('No shared files yet', 'Nie ma jeszcze wspólnych plików');
  String get serverCompanyFilesEmptyBody => text(
    'Upload the first PDF, image or text file for your team.',
    'Dodaj pierwszy PDF, obraz lub plik tekstowy dla zespołu.',
  );
  String get serverCompanyFileUpload => text('Upload file', 'Dodaj plik');
  String get serverCompanyFileOpen => text('Open file', 'Otwórz plik');
  String get serverCompanyFileDelete => text('Delete', 'Usuń');
  String get serverCompanyFileDeleteTitle =>
      text('Delete this file?', 'Usunąć ten plik?');
  String serverCompanyFileDeleteBody(String name) => template(
    '{name} will be removed for everyone with access to this channel.',
    '{name} zostanie usunięty dla wszystkich osób z dostępem do tego kanału.',
    values: {'name': name},
  );
  String serverCompanyFileUploading(String name) => template(
    'Uploading {name}',
    'Przesyłanie {name}',
    values: {'name': name},
  );
  String get serverCompanyFileRetry => text('Retry', 'Spróbuj ponownie');
  String get serverCompanyFileActionFailed => text(
    'The file operation could not be completed. Try again.',
    'Nie udało się wykonać operacji na pliku. Spróbuj ponownie.',
  );
  String get serverCompanyFilesOfflineTitle =>
      text('Files are offline', 'Pliki są teraz offline');
  String get serverCompanyFilesOfflineBody => text(
    'Reconnect to load, upload or open team files.',
    'Połącz się z internetem, aby wczytać, dodać lub otworzyć pliki zespołu.',
  );
  String get serverCompanyFilesOfflineCached => text(
    'You are offline. Saved file names remain visible, but opening and changes need a connection.',
    'Jesteś offline. Zapisane nazwy plików nadal są widoczne, ale otwieranie i zmiany wymagają połączenia.',
  );
  String get serverCompanyFileTextType => text('Text file', 'Plik tekstowy');
  String get serverCompanyFileGenericType => text('File', 'Plik');

  /// The dock's elapsed time. It counts from the instant the server wrote
  /// into the channel's liveness projection when this generation started —
  /// never from when this device happened to join.
  String serverMeetingElapsed(String time) => template(
    'Meeting time {time}',
    'Czas spotkania {time}',
    values: {'time': time},
  );
}
