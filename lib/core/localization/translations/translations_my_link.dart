/// Copy for "Mój link" (ADR-238): the sheet with the account's own profile
/// link and its QR code, its entry points on Friends and Profile, the share
/// texts built around a public link (the own profile, a Voice Moment), and
/// what a profile or Voice Moment link says when it cannot be opened — the
/// profile preview's unavailable line, the Voice Moment detail's gone card
/// and the line a signed-out visitor reads on the sign-in form and on the
/// create-account form. It also carries the Voice Moment detail header's
/// Share tooltip, which moved into the shared header with this feature.
///
/// English and Polish are authored at the call sites (`MyLinkCopy`,
/// `moment_detail_chrome.dart`); this module gives every other selectable
/// locale an explicit translation, so none of these strings falls back to
/// English.
///
/// "YO Voice", "Voice Moment", "Moment" and "QR" stay as written. Every value
/// keeps exactly the placeholders of its key
/// (`test/my_link_localization_test.dart`).
const myLinkTranslationKeys = <String>[
  'My link',
  'Anyone who opens it or scans the code will see your profile and can add you as a friend.',
  'Anyone who opens it or scans the code will see your Page and can follow you.',
  'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.',
  'Copy link',
  'Share my link',
  'QR code with your link',
  'Link copied.',
  'Your link is not available right now.',
  'Find me on YO Voice: {link}',
  'Listen to {name} on YO Voice: {link}',
  'This profile is not available.',
  'This Moment is no longer available',
  'It reached the end of its availability or was deleted by its author.',
  'Back to Moments',
  'Sign in to see this profile and add this person as a friend.',
  'Sign in to listen to this Voice Moment.',
  'Create an account to see this profile and add this person as a friend.',
  'Create an account to listen to this Voice Moment.',
  'Share this Moment',
];

const myLinkTranslations = <String, Map<String, String>>{
  'de': <String, String>{
    'My link': 'Mein Link',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Wer ihn öffnet oder den Code scannt, sieht dein Profil und kann dich als Freund hinzufügen.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Wer ihn öffnet oder den Code scannt, sieht deine Seite und kann dir folgen.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Dein Profil ist nicht öffentlich, daher öffnet dieser Link es nicht für alle. Damit dich jeder hinzufügen kann, ändere die Profilsichtbarkeit in den Einstellungen.',
    'Copy link': 'Link kopieren',
    'Share my link': 'Meinen Link teilen',
    'QR code with your link': 'QR-Code mit deinem Link',
    'Link copied.': 'Link kopiert.',
    'Your link is not available right now.':
        'Dein Link ist gerade nicht verfügbar.',
    'Find me on YO Voice: {link}': 'Finde mich auf YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}':
        'Hör dir {name} auf YO Voice an: {link}',
    'This profile is not available.': 'Dieses Profil ist nicht verfügbar.',
    'This Moment is no longer available':
        'Dieser Moment ist nicht mehr verfügbar',
    'It reached the end of its availability or was deleted by its author.':
        'Seine Verfügbarkeit ist abgelaufen oder der Autor hat ihn gelöscht.',
    'Back to Moments': 'Zurück zu den Momenten',
    'Sign in to see this profile and add this person as a friend.':
        'Melde dich an, um dieses Profil zu sehen und diese Person als Freund hinzuzufügen.',
    'Sign in to listen to this Voice Moment.':
        'Melde dich an, um diesen Voice Moment anzuhören.',
    'Create an account to see this profile and add this person as a friend.':
        'Erstelle ein Konto, um dieses Profil zu sehen und diese Person als Freund hinzuzufügen.',
    'Create an account to listen to this Voice Moment.':
        'Erstelle ein Konto, um diesen Voice Moment anzuhören.',
    'Share this Moment': 'Diesen Moment teilen',
  },
  'es': <String, String>{
    'My link': 'Mi enlace',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Quien lo abra o escanee el código verá tu perfil y podrá añadirte como amigo.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Quien lo abra o escanee el código verá tu página y podrá seguirte.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Tu perfil no es público, así que este enlace no lo abrirá para todos. Para que cualquiera pueda añadirte, cambia Visibilidad del perfil en Ajustes.',
    'Copy link': 'Copiar enlace',
    'Share my link': 'Compartir mi enlace',
    'QR code with your link': 'Código QR con tu enlace',
    'Link copied.': 'Enlace copiado.',
    'Your link is not available right now.':
        'Tu enlace no está disponible en este momento.',
    'Find me on YO Voice: {link}': 'Encuéntrame en YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}':
        'Escucha a {name} en YO Voice: {link}',
    'This profile is not available.': 'Este perfil no está disponible.',
    'This Moment is no longer available': 'Este Moment ya no está disponible',
    'It reached the end of its availability or was deleted by its author.':
        'Terminó su tiempo de disponibilidad o su autor lo eliminó.',
    'Back to Moments': 'Volver a Momentos',
    'Sign in to see this profile and add this person as a friend.':
        'Inicia sesión para ver este perfil y añadir a esta persona como amigo.',
    'Sign in to listen to this Voice Moment.':
        'Inicia sesión para escuchar este Voice Moment.',
    'Create an account to see this profile and add this person as a friend.':
        'Crea una cuenta para ver este perfil y añadir a esta persona como amigo.',
    'Create an account to listen to this Voice Moment.':
        'Crea una cuenta para escuchar este Voice Moment.',
    'Share this Moment': 'Compartir este Moment',
  },
  'pt': <String, String>{
    'My link': 'A minha ligação',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Quem a abrir ou ler o código verá o teu perfil e poderá adicionar-te como amigo.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Quem a abrir ou ler o código verá a tua página e poderá seguir-te.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'O teu perfil não é público, por isso esta ligação não o abrirá para todos. Para que qualquer pessoa te possa adicionar, altera a Visibilidade do perfil nas Definições.',
    'Copy link': 'Copiar ligação',
    'Share my link': 'Partilhar a minha ligação',
    'QR code with your link': 'Código QR com a tua ligação',
    'Link copied.': 'Ligação copiada.',
    'Your link is not available right now.':
        'A tua ligação não está disponível neste momento.',
    'Find me on YO Voice: {link}': 'Encontra-me no YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}': 'Ouve {name} no YO Voice: {link}',
    'This profile is not available.': 'Este perfil não está disponível.',
    'This Moment is no longer available': 'Este Moment já não está disponível',
    'It reached the end of its availability or was deleted by its author.':
        'Chegou ao fim da sua disponibilidade ou foi eliminado pelo autor.',
    'Back to Moments': 'Voltar aos Momentos',
    'Sign in to see this profile and add this person as a friend.':
        'Inicia sessão para ver este perfil e adicionar esta pessoa como amigo.',
    'Sign in to listen to this Voice Moment.':
        'Inicia sessão para ouvir este Voice Moment.',
    'Create an account to see this profile and add this person as a friend.':
        'Cria uma conta para ver este perfil e adicionar esta pessoa como amigo.',
    'Create an account to listen to this Voice Moment.':
        'Cria uma conta para ouvir este Voice Moment.',
    'Share this Moment': 'Partilhar este Moment',
  },
  'pt_BR': <String, String>{
    'My link': 'Meu link',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Quem abrir o link ou escanear o código verá seu perfil e poderá adicionar você como amigo.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Quem abrir o link ou escanear o código verá sua página e poderá seguir você.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Seu perfil não é público, então este link não o abrirá para todos. Para que qualquer pessoa possa adicionar você, altere a Visibilidade do perfil nas Configurações.',
    'Copy link': 'Copiar link',
    'Share my link': 'Compartilhar meu link',
    'QR code with your link': 'Código QR com seu link',
    'Link copied.': 'Link copiado.',
    'Your link is not available right now.':
        'Seu link não está disponível no momento.',
    'Find me on YO Voice: {link}': 'Me encontre no YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}': 'Ouça {name} no YO Voice: {link}',
    'This profile is not available.': 'Este perfil não está disponível.',
    'This Moment is no longer available':
        'Este Moment não está mais disponível',
    'It reached the end of its availability or was deleted by its author.':
        'Ele chegou ao fim da disponibilidade ou foi excluído pelo autor.',
    'Back to Moments': 'Voltar aos Momentos',
    'Sign in to see this profile and add this person as a friend.':
        'Entre na sua conta para ver este perfil e adicionar esta pessoa como amigo.',
    'Sign in to listen to this Voice Moment.':
        'Entre na sua conta para ouvir este Voice Moment.',
    'Create an account to see this profile and add this person as a friend.':
        'Crie uma conta para ver este perfil e adicionar esta pessoa como amigo.',
    'Create an account to listen to this Voice Moment.':
        'Crie uma conta para ouvir este Voice Moment.',
    'Share this Moment': 'Compartilhar este Moment',
  },
  'fr': <String, String>{
    'My link': 'Mon lien',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Toute personne qui l’ouvre ou scanne le code verra votre profil et pourra vous ajouter en ami.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Toute personne qui l’ouvre ou scanne le code verra votre page et pourra vous suivre.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Votre profil n’est pas public, ce lien ne l’ouvrira donc pas pour tout le monde. Pour que tout le monde puisse vous ajouter, modifiez Visibilité du profil dans les Paramètres.',
    'Copy link': 'Copier le lien',
    'Share my link': 'Partager mon lien',
    'QR code with your link': 'Code QR avec votre lien',
    'Link copied.': 'Lien copié.',
    'Your link is not available right now.':
        'Votre lien n’est pas disponible pour le moment.',
    'Find me on YO Voice: {link}': 'Retrouvez-moi sur YO Voice : {link}',
    'Listen to {name} on YO Voice: {link}':
        'Écoutez {name} sur YO Voice : {link}',
    'This profile is not available.': 'Ce profil n’est pas disponible.',
    'This Moment is no longer available': 'Ce Moment n’est plus disponible',
    'It reached the end of its availability or was deleted by its author.':
        'Sa durée de disponibilité est terminée ou son auteur l’a supprimé.',
    'Back to Moments': 'Retour aux Moments',
    'Sign in to see this profile and add this person as a friend.':
        'Connectez-vous pour voir ce profil et ajouter cette personne en ami.',
    'Sign in to listen to this Voice Moment.':
        'Connectez-vous pour écouter ce Voice Moment.',
    'Create an account to see this profile and add this person as a friend.':
        'Créez un compte pour voir ce profil et ajouter cette personne en ami.',
    'Create an account to listen to this Voice Moment.':
        'Créez un compte pour écouter ce Voice Moment.',
    'Share this Moment': 'Partager ce Moment',
  },
  'it': <String, String>{
    'My link': 'Il mio link',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Chi lo apre o scansiona il codice vedrà il tuo profilo e potrà aggiungerti agli amici.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Chi lo apre o scansiona il codice vedrà la tua pagina e potrà seguirti.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Il tuo profilo non è pubblico, quindi questo link non lo aprirà a tutti. Per permettere a chiunque di aggiungerti, cambia Visibilità del profilo nelle Impostazioni.',
    'Copy link': 'Copia link',
    'Share my link': 'Condividi il mio link',
    'QR code with your link': 'Codice QR con il tuo link',
    'Link copied.': 'Link copiato.',
    'Your link is not available right now.':
        'Il tuo link non è disponibile in questo momento.',
    'Find me on YO Voice: {link}': 'Trovami su YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}':
        'Ascolta {name} su YO Voice: {link}',
    'This profile is not available.': 'Questo profilo non è disponibile.',
    'This Moment is no longer available': 'Questo Moment non è più disponibile',
    'It reached the end of its availability or was deleted by its author.':
        'È terminato il suo periodo di disponibilità oppure l’autore lo ha eliminato.',
    'Back to Moments': 'Torna ai Momenti',
    'Sign in to see this profile and add this person as a friend.':
        'Accedi per vedere questo profilo e aggiungere questa persona agli amici.',
    'Sign in to listen to this Voice Moment.':
        'Accedi per ascoltare questo Voice Moment.',
    'Create an account to see this profile and add this person as a friend.':
        'Crea un account per vedere questo profilo e aggiungere questa persona agli amici.',
    'Create an account to listen to this Voice Moment.':
        'Crea un account per ascoltare questo Voice Moment.',
    'Share this Moment': 'Condividi questo Moment',
  },
  'nl': <String, String>{
    'My link': 'Mijn link',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Wie hem opent of de code scant, ziet je profiel en kan je als vriend toevoegen.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Wie hem opent of de code scant, ziet je pagina en kan je volgen.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Je profiel is niet openbaar, dus deze link opent het niet voor iedereen. Wijzig Zichtbaarheid van profiel in Instellingen zodat iedereen je kan toevoegen.',
    'Copy link': 'Link kopiëren',
    'Share my link': 'Mijn link delen',
    'QR code with your link': 'QR-code met je link',
    'Link copied.': 'Link gekopieerd.',
    'Your link is not available right now.': 'Je link is nu niet beschikbaar.',
    'Find me on YO Voice: {link}': 'Vind me op YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}':
        'Luister naar {name} op YO Voice: {link}',
    'This profile is not available.': 'Dit profiel is niet beschikbaar.',
    'This Moment is no longer available': 'Dit Moment is niet meer beschikbaar',
    'It reached the end of its availability or was deleted by its author.':
        'De beschikbaarheid is verlopen of de maker heeft het verwijderd.',
    'Back to Moments': 'Terug naar Momenten',
    'Sign in to see this profile and add this person as a friend.':
        'Log in om dit profiel te bekijken en deze persoon als vriend toe te voegen.',
    'Sign in to listen to this Voice Moment.':
        'Log in om dit Voice Moment te beluisteren.',
    'Create an account to see this profile and add this person as a friend.':
        'Maak een account om dit profiel te bekijken en deze persoon als vriend toe te voegen.',
    'Create an account to listen to this Voice Moment.':
        'Maak een account om dit Voice Moment te beluisteren.',
    'Share this Moment': 'Dit Moment delen',
  },
  'ro': <String, String>{
    'My link': 'Linkul meu',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Cine îl deschide sau scanează codul îți va vedea profilul și te va putea adăuga ca prieten.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Cine îl deschide sau scanează codul îți va vedea pagina și te va putea urmări.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Profilul tău nu este public, așa că acest link nu îl va deschide pentru toată lumea. Pentru ca oricine să te poată adăuga, schimbă Vizibilitatea profilului în Setări.',
    'Copy link': 'Copiază linkul',
    'Share my link': 'Distribuie linkul meu',
    'QR code with your link': 'Cod QR cu linkul tău',
    'Link copied.': 'Link copiat.',
    'Your link is not available right now.':
        'Linkul tău nu este disponibil acum.',
    'Find me on YO Voice: {link}': 'Găsește-mă pe YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}':
        'Ascultă {name} pe YO Voice: {link}',
    'This profile is not available.': 'Acest profil nu este disponibil.',
    'This Moment is no longer available': 'Acest Moment nu mai este disponibil',
    'It reached the end of its availability or was deleted by its author.':
        'Perioada lui de disponibilitate s-a încheiat sau autorul l-a șters.',
    'Back to Moments': 'Înapoi la Momente',
    'Sign in to see this profile and add this person as a friend.':
        'Conectează-te pentru a vedea acest profil și a adăuga această persoană ca prieten.',
    'Sign in to listen to this Voice Moment.':
        'Conectează-te pentru a asculta acest Voice Moment.',
    'Create an account to see this profile and add this person as a friend.':
        'Creează un cont pentru a vedea acest profil și a adăuga această persoană ca prieten.',
    'Create an account to listen to this Voice Moment.':
        'Creează un cont pentru a asculta acest Voice Moment.',
    'Share this Moment': 'Distribuie acest Moment',
  },
  'tr': <String, String>{
    'My link': 'Bağlantım',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Bağlantıyı açan veya kodu tarayan herkes profilinizi görür ve sizi arkadaş olarak ekleyebilir.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Bağlantıyı açan veya kodu tarayan herkes sayfanızı görür ve sizi takip edebilir.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Profiliniz herkese açık değil, bu yüzden bu bağlantı profili herkese açmaz. Herkesin sizi ekleyebilmesi için Ayarlar’da Profil görünürlüğü seçeneğini değiştirin.',
    'Copy link': 'Bağlantıyı kopyala',
    'Share my link': 'Bağlantımı paylaş',
    'QR code with your link': 'Bağlantınızı içeren QR kodu',
    'Link copied.': 'Bağlantı kopyalandı.',
    'Your link is not available right now.':
        'Bağlantınız şu anda kullanılamıyor.',
    'Find me on YO Voice: {link}': 'Beni YO Voice’ta bulun: {link}',
    'Listen to {name} on YO Voice: {link}':
        'YO Voice’ta {name} adlı kişiyi dinleyin: {link}',
    'This profile is not available.': 'Bu profil kullanılamıyor.',
    'This Moment is no longer available': 'Bu Moment artık kullanılamıyor',
    'It reached the end of its availability or was deleted by its author.':
        'Kullanılabilirlik süresi doldu veya sahibi tarafından silindi.',
    'Back to Moments': 'Anlara dön',
    'Sign in to see this profile and add this person as a friend.':
        'Bu profili görmek ve bu kişiyi arkadaş olarak eklemek için oturum açın.',
    'Sign in to listen to this Voice Moment.':
        'Bu Voice Moment’ı dinlemek için oturum açın.',
    'Create an account to see this profile and add this person as a friend.':
        'Bu profili görmek ve bu kişiyi arkadaş olarak eklemek için hesap oluşturun.',
    'Create an account to listen to this Voice Moment.':
        'Bu Voice Moment’ı dinlemek için hesap oluşturun.',
    'Share this Moment': 'Bu Moment’ı paylaş',
  },
  'el': <String, String>{
    'My link': 'Ο σύνδεσμός μου',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Όποιος τον ανοίξει ή σαρώσει τον κωδικό θα δει το προφίλ σας και θα μπορεί να σας προσθέσει ως φίλο.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Όποιος τον ανοίξει ή σαρώσει τον κωδικό θα δει τη σελίδα σας και θα μπορεί να σας ακολουθήσει.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Το προφίλ σας δεν είναι δημόσιο, επομένως αυτός ο σύνδεσμος δεν θα το ανοίγει για όλους. Για να μπορεί οποιοσδήποτε να σας προσθέσει, αλλάξτε την Ορατότητα προφίλ στις Ρυθμίσεις.',
    'Copy link': 'Αντιγραφή συνδέσμου',
    'Share my link': 'Κοινοποίηση του συνδέσμου μου',
    'QR code with your link': 'Κωδικός QR με τον σύνδεσμό σας',
    'Link copied.': 'Ο σύνδεσμος αντιγράφηκε.',
    'Your link is not available right now.':
        'Ο σύνδεσμός σας δεν είναι διαθέσιμος αυτή τη στιγμή.',
    'Find me on YO Voice: {link}': 'Βρείτε με στο YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}':
        'Ακούστε {name} στο YO Voice: {link}',
    'This profile is not available.': 'Αυτό το προφίλ δεν είναι διαθέσιμο.',
    'This Moment is no longer available':
        'Αυτό το Moment δεν είναι πλέον διαθέσιμο',
    'It reached the end of its availability or was deleted by its author.':
        'Έληξε ο χρόνος διαθεσιμότητάς του ή διαγράφηκε από τον δημιουργό του.',
    'Back to Moments': 'Πίσω στις Στιγμές',
    'Sign in to see this profile and add this person as a friend.':
        'Συνδεθείτε για να δείτε αυτό το προφίλ και να προσθέσετε αυτό το άτομο ως φίλο.',
    'Sign in to listen to this Voice Moment.':
        'Συνδεθείτε για να ακούσετε αυτό το Voice Moment.',
    'Create an account to see this profile and add this person as a friend.':
        'Δημιουργήστε λογαριασμό για να δείτε αυτό το προφίλ και να προσθέσετε αυτό το άτομο ως φίλο.',
    'Create an account to listen to this Voice Moment.':
        'Δημιουργήστε λογαριασμό για να ακούσετε αυτό το Voice Moment.',
    'Share this Moment': 'Κοινοποίηση αυτού του Moment',
  },
  'hu': <String, String>{
    'My link': 'Saját linkem',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Aki megnyitja vagy beolvassa a kódot, látja a profilodat, és ismerősnek jelölhet.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Aki megnyitja vagy beolvassa a kódot, látja az oldaladat, és követhet téged.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'A profilod nem nyilvános, ezért ez a link nem mindenkinek nyitja meg. Ha azt szeretnéd, hogy bárki ismerősnek jelölhessen, módosítsd a Profil láthatósága beállítást a Beállításokban.',
    'Copy link': 'Link másolása',
    'Share my link': 'Linkem megosztása',
    'QR code with your link': 'QR-kód a linkeddel',
    'Link copied.': 'Link másolva.',
    'Your link is not available right now.': 'A linked most nem érhető el.',
    'Find me on YO Voice: {link}': 'Keress meg a YO Voice-on: {link}',
    'Listen to {name} on YO Voice: {link}':
        'Hallgasd meg {name} felvételét a YO Voice-on: {link}',
    'This profile is not available.': 'Ez a profil nem érhető el.',
    'This Moment is no longer available': 'Ez a Moment már nem érhető el',
    'It reached the end of its availability or was deleted by its author.':
        'Lejárt az elérhetősége, vagy a szerzője törölte.',
    'Back to Moments': 'Vissza a Pillanatokhoz',
    'Sign in to see this profile and add this person as a friend.':
        'Jelentkezz be, hogy megnézd ezt a profilt, és ismerősnek jelöld ezt a személyt.',
    'Sign in to listen to this Voice Moment.':
        'Jelentkezz be a Voice Moment meghallgatásához.',
    'Create an account to see this profile and add this person as a friend.':
        'Hozz létre fiókot, hogy megnézd ezt a profilt, és ismerősnek jelöld ezt a személyt.',
    'Create an account to listen to this Voice Moment.':
        'Hozz létre fiókot a Voice Moment meghallgatásához.',
    'Share this Moment': 'A Moment megosztása',
  },
  'uk': <String, String>{
    'My link': 'Моє посилання',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Хто відкриє його або відсканує код, побачить ваш профіль і зможе додати вас у друзі.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Хто відкриє його або відсканує код, побачить вашу сторінку і зможе стежити за вами.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Ваш профіль не є публічним, тому це посилання відкриє його не всім. Щоб будь-хто міг додати вас, змініть Видимість профілю в Налаштуваннях.',
    'Copy link': 'Копіювати посилання',
    'Share my link': 'Поділитися моїм посиланням',
    'QR code with your link': 'QR-код із вашим посиланням',
    'Link copied.': 'Посилання скопійовано.',
    'Your link is not available right now.': 'Ваше посилання зараз недоступне.',
    'Find me on YO Voice: {link}': 'Знайдіть мене в YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}':
        'Послухайте {name} в YO Voice: {link}',
    'This profile is not available.': 'Цей профіль недоступний.',
    'This Moment is no longer available': 'Цей Moment більше недоступний',
    'It reached the end of its availability or was deleted by its author.':
        'Час його доступності минув або автор його видалив.',
    'Back to Moments': 'Назад до Моментів',
    'Sign in to see this profile and add this person as a friend.':
        'Увійдіть, щоб переглянути цей профіль і додати цю людину в друзі.',
    'Sign in to listen to this Voice Moment.':
        'Увійдіть, щоб послухати цей Voice Moment.',
    'Create an account to see this profile and add this person as a friend.':
        'Створіть обліковий запис, щоб переглянути цей профіль і додати цю людину в друзі.',
    'Create an account to listen to this Voice Moment.':
        'Створіть обліковий запис, щоб послухати цей Voice Moment.',
    'Share this Moment': 'Поділитися цим Moment',
  },
  'ru': <String, String>{
    'My link': 'Моя ссылка',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Тот, кто откроет её или отсканирует код, увидит ваш профиль и сможет добавить вас в друзья.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Тот, кто откроет её или отсканирует код, увидит вашу страницу и сможет подписаться на вас.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Ваш профиль не является общедоступным, поэтому эта ссылка откроет его не всем. Чтобы любой мог добавить вас, измените Видимость профиля в Настройках.',
    'Copy link': 'Копировать ссылку',
    'Share my link': 'Поделиться моей ссылкой',
    'QR code with your link': 'QR-код с вашей ссылкой',
    'Link copied.': 'Ссылка скопирована.',
    'Your link is not available right now.': 'Ваша ссылка сейчас недоступна.',
    'Find me on YO Voice: {link}': 'Найдите меня в YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}':
        'Послушайте {name} в YO Voice: {link}',
    'This profile is not available.': 'Этот профиль недоступен.',
    'This Moment is no longer available': 'Этот Moment больше недоступен',
    'It reached the end of its availability or was deleted by its author.':
        'Срок его доступности истёк, или автор удалил его.',
    'Back to Moments': 'Назад к Моментам',
    'Sign in to see this profile and add this person as a friend.':
        'Войдите, чтобы посмотреть этот профиль и добавить этого человека в друзья.',
    'Sign in to listen to this Voice Moment.':
        'Войдите, чтобы послушать этот Voice Moment.',
    'Create an account to see this profile and add this person as a friend.':
        'Создайте аккаунт, чтобы посмотреть этот профиль и добавить этого человека в друзья.',
    'Create an account to listen to this Voice Moment.':
        'Создайте аккаунт, чтобы послушать этот Voice Moment.',
    'Share this Moment': 'Поделиться этим Moment',
  },
  'cs': <String, String>{
    'My link': 'Můj odkaz',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Kdo ho otevře nebo naskenuje kód, uvidí váš profil a může si vás přidat do přátel.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Kdo ho otevře nebo naskenuje kód, uvidí vaši stránku a může vás sledovat.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Váš profil není veřejný, takže tento odkaz ho neotevře každému. Aby si vás mohl přidat kdokoli, změňte Viditelnost profilu v Nastavení.',
    'Copy link': 'Kopírovat odkaz',
    'Share my link': 'Sdílet můj odkaz',
    'QR code with your link': 'QR kód s vaším odkazem',
    'Link copied.': 'Odkaz zkopírován.',
    'Your link is not available right now.': 'Váš odkaz teď není dostupný.',
    'Find me on YO Voice: {link}': 'Najdete mě na YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}':
        'Poslechněte si {name} na YO Voice: {link}',
    'This profile is not available.': 'Tento profil není dostupný.',
    'This Moment is no longer available': 'Tento Moment už není dostupný',
    'It reached the end of its availability or was deleted by its author.':
        'Skončila doba jeho dostupnosti nebo ho autor smazal.',
    'Back to Moments': 'Zpět na Momenty',
    'Sign in to see this profile and add this person as a friend.':
        'Přihlaste se, abyste viděli tento profil a mohli si tuto osobu přidat do přátel.',
    'Sign in to listen to this Voice Moment.':
        'Přihlaste se a poslechněte si tento Voice Moment.',
    'Create an account to see this profile and add this person as a friend.':
        'Vytvořte si účet, abyste viděli tento profil a mohli si tuto osobu přidat do přátel.',
    'Create an account to listen to this Voice Moment.':
        'Vytvořte si účet a poslechněte si tento Voice Moment.',
    'Share this Moment': 'Sdílet tento Moment',
  },
  'sk': <String, String>{
    'My link': 'Môj odkaz',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Kto ho otvorí alebo naskenuje kód, uvidí váš profil a môže si vás pridať medzi priateľov.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Kto ho otvorí alebo naskenuje kód, uvidí vašu stránku a môže vás sledovať.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Váš profil nie je verejný, takže tento odkaz ho neotvorí každému. Aby si vás mohol pridať ktokoľvek, zmeňte Viditeľnosť profilu v Nastaveniach.',
    'Copy link': 'Kopírovať odkaz',
    'Share my link': 'Zdieľať môj odkaz',
    'QR code with your link': 'QR kód s vaším odkazom',
    'Link copied.': 'Odkaz bol skopírovaný.',
    'Your link is not available right now.': 'Váš odkaz teraz nie je dostupný.',
    'Find me on YO Voice: {link}': 'Nájdete ma na YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}':
        'Vypočujte si {name} na YO Voice: {link}',
    'This profile is not available.': 'Tento profil nie je dostupný.',
    'This Moment is no longer available': 'Tento Moment už nie je dostupný',
    'It reached the end of its availability or was deleted by its author.':
        'Skončil sa čas jeho dostupnosti alebo ho autor odstránil.',
    'Back to Moments': 'Späť na Momenty',
    'Sign in to see this profile and add this person as a friend.':
        'Prihláste sa, aby ste videli tento profil a mohli si túto osobu pridať medzi priateľov.',
    'Sign in to listen to this Voice Moment.':
        'Prihláste sa a vypočujte si tento Voice Moment.',
    'Create an account to see this profile and add this person as a friend.':
        'Vytvorte si účet, aby ste videli tento profil a mohli si túto osobu pridať medzi priateľov.',
    'Create an account to listen to this Voice Moment.':
        'Vytvorte si účet a vypočujte si tento Voice Moment.',
    'Share this Moment': 'Zdieľať tento Moment',
  },
  'bg': <String, String>{
    'My link': 'Моята връзка',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Който я отвори или сканира кода, ще види профила ви и ще може да ви добави като приятел.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Който я отвори или сканира кода, ще види страницата ви и ще може да ви последва.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Профилът ви не е публичен, затова тази връзка няма да го отвори за всички. За да може всеки да ви добави, променете Видимост на профила в Настройки.',
    'Copy link': 'Копирай връзката',
    'Share my link': 'Сподели моята връзка',
    'QR code with your link': 'QR код с вашата връзка',
    'Link copied.': 'Връзката е копирана.',
    'Your link is not available right now.':
        'Връзката ви не е достъпна в момента.',
    'Find me on YO Voice: {link}': 'Намерете ме в YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}': 'Чуйте {name} в YO Voice: {link}',
    'This profile is not available.': 'Този профил не е достъпен.',
    'This Moment is no longer available': 'Този Moment вече не е достъпен',
    'It reached the end of its availability or was deleted by its author.':
        'Времето му за достъпност изтече или авторът го изтри.',
    'Back to Moments': 'Назад към Моменти',
    'Sign in to see this profile and add this person as a friend.':
        'Влезте, за да видите този профил и да добавите този човек като приятел.',
    'Sign in to listen to this Voice Moment.':
        'Влезте, за да чуете този Voice Moment.',
    'Create an account to see this profile and add this person as a friend.':
        'Създайте акаунт, за да видите този профил и да добавите този човек като приятел.',
    'Create an account to listen to this Voice Moment.':
        'Създайте акаунт, за да чуете този Voice Moment.',
    'Share this Moment': 'Споделяне на този Moment',
  },
  'hr': <String, String>{
    'My link': 'Moja poveznica',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Tko je otvori ili skenira kod, vidjet će vaš profil i moći će vas dodati za prijatelja.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Tko je otvori ili skenira kod, vidjet će vašu stranicu i moći će vas pratiti.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Vaš profil nije javan, pa ga ova poveznica neće otvoriti svima. Da bi vas svatko mogao dodati, promijenite Vidljivost profila u Postavkama.',
    'Copy link': 'Kopiraj poveznicu',
    'Share my link': 'Podijeli moju poveznicu',
    'QR code with your link': 'QR kod s vašom poveznicom',
    'Link copied.': 'Poveznica je kopirana.',
    'Your link is not available right now.':
        'Vaša poveznica trenutačno nije dostupna.',
    'Find me on YO Voice: {link}': 'Pronađite me na YO Voiceu: {link}',
    'Listen to {name} on YO Voice: {link}':
        'Poslušajte {name} na YO Voiceu: {link}',
    'This profile is not available.': 'Ovaj profil nije dostupan.',
    'This Moment is no longer available': 'Ovaj Moment više nije dostupan',
    'It reached the end of its availability or was deleted by its author.':
        'Isteklo je vrijeme njegove dostupnosti ili ga je autor izbrisao.',
    'Back to Moments': 'Natrag na Momente',
    'Sign in to see this profile and add this person as a friend.':
        'Prijavite se kako biste vidjeli ovaj profil i dodali ovu osobu za prijatelja.',
    'Sign in to listen to this Voice Moment.':
        'Prijavite se kako biste poslušali ovaj Voice Moment.',
    'Create an account to see this profile and add this person as a friend.':
        'Izradite račun kako biste vidjeli ovaj profil i dodali ovu osobu za prijatelja.',
    'Create an account to listen to this Voice Moment.':
        'Izradite račun kako biste poslušali ovaj Voice Moment.',
    'Share this Moment': 'Podijeli ovaj Moment',
  },
  'sr': <String, String>{
    'My link': 'Моја веза',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Ко је отвори или скенира код, видеће ваш профил и моћи ће да вас дода за пријатеља.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Ко је отвори или скенира код, видеће вашу страницу и моћи ће да вас прати.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Ваш профил није јаван, па га ова веза неће отворити свима. Да би свако могао да вас дода, промените Видљивост профила у Подешавањима.',
    'Copy link': 'Копирај везу',
    'Share my link': 'Подели моју везу',
    'QR code with your link': 'QR код са вашом везом',
    'Link copied.': 'Веза је копирана.',
    'Your link is not available right now.':
        'Ваша веза тренутно није доступна.',
    'Find me on YO Voice: {link}': 'Пронађите ме на YO Voice-у: {link}',
    'Listen to {name} on YO Voice: {link}':
        'Послушајте {name} на YO Voice-у: {link}',
    'This profile is not available.': 'Овај профил није доступан.',
    'This Moment is no longer available': 'Овај Moment више није доступан',
    'It reached the end of its availability or was deleted by its author.':
        'Истекло је време његове доступности или га је аутор обрисао.',
    'Back to Moments': 'Назад на Моменте',
    'Sign in to see this profile and add this person as a friend.':
        'Пријавите се да бисте видели овај профил и додали ову особу за пријатеља.',
    'Sign in to listen to this Voice Moment.':
        'Пријавите се да бисте послушали овај Voice Moment.',
    'Create an account to see this profile and add this person as a friend.':
        'Направите налог да бисте видели овај профил и додали ову особу за пријатеља.',
    'Create an account to listen to this Voice Moment.':
        'Направите налог да бисте послушали овај Voice Moment.',
    'Share this Moment': 'Подели овај Moment',
  },
  'sv': <String, String>{
    'My link': 'Min länk',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Den som öppnar den eller skannar koden ser din profil och kan lägga till dig som vän.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Den som öppnar den eller skannar koden ser din sida och kan följa dig.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Din profil är inte offentlig, så den här länken öppnar den inte för alla. Ändra Profilens synlighet i Inställningar så att vem som helst kan lägga till dig.',
    'Copy link': 'Kopiera länk',
    'Share my link': 'Dela min länk',
    'QR code with your link': 'QR-kod med din länk',
    'Link copied.': 'Länken har kopierats.',
    'Your link is not available right now.':
        'Din länk är inte tillgänglig just nu.',
    'Find me on YO Voice: {link}': 'Hitta mig på YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}':
        'Lyssna på {name} på YO Voice: {link}',
    'This profile is not available.': 'Den här profilen är inte tillgänglig.',
    'This Moment is no longer available':
        'Detta Moment är inte längre tillgängligt',
    'It reached the end of its availability or was deleted by its author.':
        'Dess tillgänglighetstid har gått ut eller så har skaparen tagit bort det.',
    'Back to Moments': 'Tillbaka till Moment',
    'Sign in to see this profile and add this person as a friend.':
        'Logga in för att se den här profilen och lägga till personen som vän.',
    'Sign in to listen to this Voice Moment.':
        'Logga in för att lyssna på detta Voice Moment.',
    'Create an account to see this profile and add this person as a friend.':
        'Skapa ett konto för att se den här profilen och lägga till personen som vän.',
    'Create an account to listen to this Voice Moment.':
        'Skapa ett konto för att lyssna på detta Voice Moment.',
    'Share this Moment': 'Dela detta Moment',
  },
  'da': <String, String>{
    'My link': 'Mit link',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Den, der åbner det eller scanner koden, ser din profil og kan tilføje dig som ven.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Den, der åbner det eller scanner koden, ser din side og kan følge dig.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Din profil er ikke offentlig, så dette link åbner den ikke for alle. Skift Profilens synlighed i Indstillinger, så alle kan tilføje dig.',
    'Copy link': 'Kopiér link',
    'Share my link': 'Del mit link',
    'QR code with your link': 'QR-kode med dit link',
    'Link copied.': 'Link kopieret.',
    'Your link is not available right now.':
        'Dit link er ikke tilgængeligt lige nu.',
    'Find me on YO Voice: {link}': 'Find mig på YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}':
        'Lyt til {name} på YO Voice: {link}',
    'This profile is not available.': 'Denne profil er ikke tilgængelig.',
    'This Moment is no longer available':
        'Dette Moment er ikke længere tilgængeligt',
    'It reached the end of its availability or was deleted by its author.':
        'Dets tilgængelighed er udløbet, eller forfatteren har slettet det.',
    'Back to Moments': 'Tilbage til Moments',
    'Sign in to see this profile and add this person as a friend.':
        'Log ind for at se denne profil og tilføje personen som ven.',
    'Sign in to listen to this Voice Moment.':
        'Log ind for at lytte til dette Voice Moment.',
    'Create an account to see this profile and add this person as a friend.':
        'Opret en konto for at se denne profil og tilføje personen som ven.',
    'Create an account to listen to this Voice Moment.':
        'Opret en konto for at lytte til dette Voice Moment.',
    'Share this Moment': 'Del dette Moment',
  },
  'nb': <String, String>{
    'My link': 'Min lenke',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Den som åpner den eller skanner koden, ser profilen din og kan legge deg til som venn.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Den som åpner den eller skanner koden, ser siden din og kan følge deg.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Profilen din er ikke offentlig, så denne lenken åpner den ikke for alle. Endre Profilsynlighet i Innstillinger slik at hvem som helst kan legge deg til.',
    'Copy link': 'Kopier lenke',
    'Share my link': 'Del lenken min',
    'QR code with your link': 'QR-kode med lenken din',
    'Link copied.': 'Lenken er kopiert.',
    'Your link is not available right now.':
        'Lenken din er ikke tilgjengelig akkurat nå.',
    'Find me on YO Voice: {link}': 'Finn meg på YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}': 'Hør på {name} på YO Voice: {link}',
    'This profile is not available.': 'Denne profilen er ikke tilgjengelig.',
    'This Moment is no longer available':
        'Dette Momentet er ikke lenger tilgjengelig',
    'It reached the end of its availability or was deleted by its author.':
        'Tilgjengeligheten er utløpt, eller så har forfatteren slettet det.',
    'Back to Moments': 'Tilbake til Moments',
    'Sign in to see this profile and add this person as a friend.':
        'Logg inn for å se denne profilen og legge til personen som venn.',
    'Sign in to listen to this Voice Moment.':
        'Logg inn for å høre på dette Voice Momentet.',
    'Create an account to see this profile and add this person as a friend.':
        'Opprett en konto for å se denne profilen og legge til personen som venn.',
    'Create an account to listen to this Voice Moment.':
        'Opprett en konto for å høre på dette Voice Momentet.',
    'Share this Moment': 'Del dette Momentet',
  },
  'fi': <String, String>{
    'My link': 'Oma linkkini',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Kun joku avaa sen tai skannaa koodin, hän näkee profiilisi ja voi lisätä sinut kaveriksi.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Kun joku avaa sen tai skannaa koodin, hän näkee sivusi ja voi seurata sinua.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Profiilisi ei ole julkinen, joten tämä linkki ei avaa sitä kaikille. Muuta Profiilin näkyvyys Asetuksissa, jotta kuka tahansa voi lisätä sinut.',
    'Copy link': 'Kopioi linkki',
    'Share my link': 'Jaa linkkini',
    'QR code with your link': 'QR-koodi, jossa on linkkisi',
    'Link copied.': 'Linkki kopioitu.',
    'Your link is not available right now.':
        'Linkkisi ei ole juuri nyt saatavilla.',
    'Find me on YO Voice: {link}': 'Löydät minut YO Voicesta: {link}',
    'Listen to {name} on YO Voice: {link}':
        'Kuuntele YO Voicessa: {name} – {link}',
    'This profile is not available.': 'Tämä profiili ei ole saatavilla.',
    'This Moment is no longer available': 'Tämä Moment ei ole enää saatavilla',
    'It reached the end of its availability or was deleted by its author.':
        'Sen saatavuusaika päättyi tai tekijä poisti sen.',
    'Back to Moments': 'Takaisin Hetkiin',
    'Sign in to see this profile and add this person as a friend.':
        'Kirjaudu sisään nähdäksesi tämän profiilin ja lisätäksesi henkilön kaveriksi.',
    'Sign in to listen to this Voice Moment.':
        'Kirjaudu sisään kuunnellaksesi tämän Voice Momentin.',
    'Create an account to see this profile and add this person as a friend.':
        'Luo tili nähdäksesi tämän profiilin ja lisätäksesi henkilön kaveriksi.',
    'Create an account to listen to this Voice Moment.':
        'Luo tili kuunnellaksesi tämän Voice Momentin.',
    'Share this Moment': 'Jaa tämä Moment',
  },
  'lt': <String, String>{
    'My link': 'Mano nuoroda',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Kas ją atidarys arba nuskaitys kodą, pamatys jūsų profilį ir galės pridėti jus prie draugų.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Kas ją atidarys arba nuskaitys kodą, pamatys jūsų puslapį ir galės jus sekti.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Jūsų profilis nėra viešas, todėl ši nuoroda jį atvers ne visiems. Kad bet kas galėtų jus pridėti, pakeiskite Profilio matomumą Nustatymuose.',
    'Copy link': 'Kopijuoti nuorodą',
    'Share my link': 'Bendrinti mano nuorodą',
    'QR code with your link': 'QR kodas su jūsų nuoroda',
    'Link copied.': 'Nuoroda nukopijuota.',
    'Your link is not available right now.':
        'Jūsų nuoroda šiuo metu nepasiekiama.',
    'Find me on YO Voice: {link}': 'Raskite mane „YO Voice“: {link}',
    'Listen to {name} on YO Voice: {link}':
        'Paklausykite {name} per „YO Voice“: {link}',
    'This profile is not available.': 'Šis profilis nepasiekiamas.',
    'This Moment is no longer available': 'Šis Moment nebepasiekiamas',
    'It reached the end of its availability or was deleted by its author.':
        'Baigėsi jo pasiekiamumo laikas arba autorius jį ištrynė.',
    'Back to Moments': 'Atgal į Akimirkas',
    'Sign in to see this profile and add this person as a friend.':
        'Prisijunkite, kad pamatytumėte šį profilį ir pridėtumėte šį žmogų prie draugų.',
    'Sign in to listen to this Voice Moment.':
        'Prisijunkite, kad paklausytumėte šio Voice Moment.',
    'Create an account to see this profile and add this person as a friend.':
        'Susikurkite paskyrą, kad pamatytumėte šį profilį ir pridėtumėte šį žmogų prie draugų.',
    'Create an account to listen to this Voice Moment.':
        'Susikurkite paskyrą, kad paklausytumėte šio Voice Moment.',
    'Share this Moment': 'Bendrinti šį Moment',
  },
  'lv': <String, String>{
    'My link': 'Mana saite',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Ikviens, kas to atvērs vai noskenēs kodu, redzēs jūsu profilu un varēs pievienot jūs draugiem.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Ikviens, kas to atvērs vai noskenēs kodu, redzēs jūsu lapu un varēs jums sekot.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Jūsu profils nav publisks, tāpēc šī saite to neatvērs visiem. Lai ikviens varētu jūs pievienot, mainiet Profila redzamību Iestatījumos.',
    'Copy link': 'Kopēt saiti',
    'Share my link': 'Kopīgot manu saiti',
    'QR code with your link': 'QR kods ar jūsu saiti',
    'Link copied.': 'Saite nokopēta.',
    'Your link is not available right now.': 'Jūsu saite pašlaik nav pieejama.',
    'Find me on YO Voice: {link}': 'Atrodiet mani YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}':
        'Noklausieties {name} lietotnē YO Voice: {link}',
    'This profile is not available.': 'Šis profils nav pieejams.',
    'This Moment is no longer available': 'Šis Moment vairs nav pieejams',
    'It reached the end of its availability or was deleted by its author.':
        'Tā pieejamības laiks ir beidzies, vai autors to izdzēsa.',
    'Back to Moments': 'Atpakaļ uz Mirkļiem',
    'Sign in to see this profile and add this person as a friend.':
        'Pierakstieties, lai skatītu šo profilu un pievienotu šo personu draugiem.',
    'Sign in to listen to this Voice Moment.':
        'Pierakstieties, lai noklausītos šo Voice Moment.',
    'Create an account to see this profile and add this person as a friend.':
        'Izveidojiet kontu, lai skatītu šo profilu un pievienotu šo personu draugiem.',
    'Create an account to listen to this Voice Moment.':
        'Izveidojiet kontu, lai noklausītos šo Voice Moment.',
    'Share this Moment': 'Kopīgot šo Moment',
  },
  'et': <String, String>{
    'My link': 'Minu link',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Kes selle avab või koodi skannib, näeb sinu profiili ja saab sind sõbraks lisada.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Kes selle avab või koodi skannib, näeb sinu lehte ja saab sind jälgida.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Sinu profiil ei ole avalik, seega ei ava see link seda kõigile. Et igaüks saaks sind lisada, muuda Seadetes Profiili nähtavust.',
    'Copy link': 'Kopeeri link',
    'Share my link': 'Jaga minu linki',
    'QR code with your link': 'QR-kood sinu lingiga',
    'Link copied.': 'Link kopeeritud.',
    'Your link is not available right now.': 'Sinu link pole praegu saadaval.',
    'Find me on YO Voice: {link}': 'Leia mind YO Voice’ist: {link}',
    'Listen to {name} on YO Voice: {link}':
        'Kuula YO Voice’is: {name} – {link}',
    'This profile is not available.': 'See profiil pole saadaval.',
    'This Moment is no longer available': 'See Moment pole enam saadaval',
    'It reached the end of its availability or was deleted by its author.':
        'Selle saadavusaeg sai läbi või autor kustutas selle.',
    'Back to Moments': 'Tagasi Hetkede juurde',
    'Sign in to see this profile and add this person as a friend.':
        'Logi sisse, et näha seda profiili ja lisada see inimene sõbraks.',
    'Sign in to listen to this Voice Moment.':
        'Logi sisse, et kuulata seda Voice Momenti.',
    'Create an account to see this profile and add this person as a friend.':
        'Loo konto, et näha seda profiili ja lisada see inimene sõbraks.',
    'Create an account to listen to this Voice Moment.':
        'Loo konto, et kuulata seda Voice Momenti.',
    'Share this Moment': 'Jaga seda Momenti',
  },
  'id': <String, String>{
    'My link': 'Tautan saya',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Siapa pun yang membukanya atau memindai kodenya akan melihat profil Anda dan dapat menambahkan Anda sebagai teman.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Siapa pun yang membukanya atau memindai kodenya akan melihat halaman Anda dan dapat mengikuti Anda.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Profil Anda tidak publik, jadi tautan ini tidak akan membukanya untuk semua orang. Agar siapa pun dapat menambahkan Anda, ubah Visibilitas profil di Pengaturan.',
    'Copy link': 'Salin tautan',
    'Share my link': 'Bagikan tautan saya',
    'QR code with your link': 'Kode QR berisi tautan Anda',
    'Link copied.': 'Tautan disalin.',
    'Your link is not available right now.':
        'Tautan Anda sedang tidak tersedia.',
    'Find me on YO Voice: {link}': 'Temukan saya di YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}':
        'Dengarkan {name} di YO Voice: {link}',
    'This profile is not available.': 'Profil ini tidak tersedia.',
    'This Moment is no longer available': 'Moment ini sudah tidak tersedia',
    'It reached the end of its availability or was deleted by its author.':
        'Masa ketersediaannya telah berakhir atau dihapus oleh pembuatnya.',
    'Back to Moments': 'Kembali ke Momen',
    'Sign in to see this profile and add this person as a friend.':
        'Masuk untuk melihat profil ini dan menambahkan orang ini sebagai teman.',
    'Sign in to listen to this Voice Moment.':
        'Masuk untuk mendengarkan Voice Moment ini.',
    'Create an account to see this profile and add this person as a friend.':
        'Buat akun untuk melihat profil ini dan menambahkan orang ini sebagai teman.',
    'Create an account to listen to this Voice Moment.':
        'Buat akun untuk mendengarkan Voice Moment ini.',
    'Share this Moment': 'Bagikan Moment ini',
  },
  'vi': <String, String>{
    'My link': 'Liên kết của tôi',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Ai mở liên kết hoặc quét mã sẽ thấy hồ sơ của bạn và có thể kết bạn với bạn.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Ai mở liên kết hoặc quét mã sẽ thấy trang của bạn và có thể theo dõi bạn.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Hồ sơ của bạn không công khai, nên liên kết này sẽ không mở hồ sơ cho mọi người. Để ai cũng có thể kết bạn với bạn, hãy đổi Chế độ hiển thị hồ sơ trong Cài đặt.',
    'Copy link': 'Sao chép liên kết',
    'Share my link': 'Chia sẻ liên kết của tôi',
    'QR code with your link': 'Mã QR chứa liên kết của bạn',
    'Link copied.': 'Đã sao chép liên kết.',
    'Your link is not available right now.':
        'Liên kết của bạn hiện không khả dụng.',
    'Find me on YO Voice: {link}': 'Tìm tôi trên YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}': 'Nghe {name} trên YO Voice: {link}',
    'This profile is not available.': 'Hồ sơ này không khả dụng.',
    'This Moment is no longer available': 'Moment này không còn khả dụng',
    'It reached the end of its availability or was deleted by its author.':
        'Đã hết thời gian hiển thị hoặc tác giả đã xóa.',
    'Back to Moments': 'Quay lại Khoảnh khắc',
    'Sign in to see this profile and add this person as a friend.':
        'Đăng nhập để xem hồ sơ này và kết bạn với người này.',
    'Sign in to listen to this Voice Moment.':
        'Đăng nhập để nghe Voice Moment này.',
    'Create an account to see this profile and add this person as a friend.':
        'Tạo tài khoản để xem hồ sơ này và kết bạn với người này.',
    'Create an account to listen to this Voice Moment.':
        'Tạo tài khoản để nghe Voice Moment này.',
    'Share this Moment': 'Chia sẻ Moment này',
  },
  'zh_CN': <String, String>{
    'My link': '我的链接',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        '打开链接或扫描二维码的人会看到你的个人资料，并可以加你为好友。',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        '打开链接或扫描二维码的人会看到你的主页，并可以关注你。',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        '你的个人资料未公开，因此并非所有人都能通过此链接打开它。如需让任何人都能添加你，请在“设置”中更改“个人资料可见性”。',
    'Copy link': '复制链接',
    'Share my link': '分享我的链接',
    'QR code with your link': '包含你的链接的二维码',
    'Link copied.': '已复制链接。',
    'Your link is not available right now.': '你的链接暂时不可用。',
    'Find me on YO Voice: {link}': '在 YO Voice 上找到我：{link}',
    'Listen to {name} on YO Voice: {link}': '在 YO Voice 上收听 {name}：{link}',
    'This profile is not available.': '此个人资料不可用。',
    'This Moment is no longer available': '此 Moment 已不可用',
    'It reached the end of its availability or was deleted by its author.':
        '它的可用时间已结束，或已被作者删除。',
    'Back to Moments': '返回动态',
    'Sign in to see this profile and add this person as a friend.':
        '登录以查看此个人资料并添加此人为好友。',
    'Sign in to listen to this Voice Moment.': '登录以收听此 Voice Moment。',
    'Create an account to see this profile and add this person as a friend.':
        '创建账号以查看此个人资料并添加此人为好友。',
    'Create an account to listen to this Voice Moment.':
        '创建账号以收听此 Voice Moment。',
    'Share this Moment': '分享此 Moment',
  },
  'zh_TW': <String, String>{
    'My link': '我的連結',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        '開啟連結或掃描 QR 碼的人會看到你的個人檔案，並可以加你為好友。',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        '開啟連結或掃描 QR 碼的人會看到你的專頁，並可以追蹤你。',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        '你的個人檔案未公開，因此並非所有人都能透過此連結開啟它。如要讓任何人都能加你，請在「設定」中變更「個人檔案可見度」。',
    'Copy link': '複製連結',
    'Share my link': '分享我的連結',
    'QR code with your link': '含有你的連結的 QR 碼',
    'Link copied.': '已複製連結。',
    'Your link is not available right now.': '你的連結目前無法使用。',
    'Find me on YO Voice: {link}': '在 YO Voice 上找到我：{link}',
    'Listen to {name} on YO Voice: {link}': '在 YO Voice 上收聽 {name}：{link}',
    'This profile is not available.': '此個人檔案無法使用。',
    'This Moment is no longer available': '此 Moment 已無法使用',
    'It reached the end of its availability or was deleted by its author.':
        '它的可用時間已結束，或已被作者刪除。',
    'Back to Moments': '返回動態',
    'Sign in to see this profile and add this person as a friend.':
        '登入以查看此個人檔案並將此人加為好友。',
    'Sign in to listen to this Voice Moment.': '登入以收聽此 Voice Moment。',
    'Create an account to see this profile and add this person as a friend.':
        '建立賬號以查看此個人檔案並將此人加為好友。',
    'Create an account to listen to this Voice Moment.':
        '建立賬號以收聽此 Voice Moment。',
    'Share this Moment': '分享此 Moment',
  },
  'ja': <String, String>{
    'My link': 'マイリンク',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'リンクを開くかコードを読み取った人は、あなたのプロフィールを見て友達に追加できます。',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'リンクを開くかコードを読み取った人は、あなたのページを見てフォローできます。',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'プロフィールが公開されていないため、このリンクを開いても全員には表示されません。誰でも友達に追加できるようにするには、設定で「プロフィールの公開範囲」を変更してください。',
    'Copy link': 'リンクをコピー',
    'Share my link': 'マイリンクを共有',
    'QR code with your link': 'あなたのリンクのQRコード',
    'Link copied.': 'リンクをコピーしました。',
    'Your link is not available right now.': '現在、あなたのリンクは利用できません。',
    'Find me on YO Voice: {link}': 'YO Voiceで私を見つけてください：{link}',
    'Listen to {name} on YO Voice: {link}': 'YO Voiceで{name}さんを聴く：{link}',
    'This profile is not available.': 'このプロフィールは利用できません。',
    'This Moment is no longer available': 'このMomentは利用できなくなりました',
    'It reached the end of its availability or was deleted by its author.':
        '公開期間が終了したか、作成者によって削除されました。',
    'Back to Moments': 'モーメントに戻る',
    'Sign in to see this profile and add this person as a friend.':
        'このプロフィールを見て友達に追加するには、ログインしてください。',
    'Sign in to listen to this Voice Moment.': 'このVoice Momentを聴くにはログインしてください。',
    'Create an account to see this profile and add this person as a friend.':
        'このプロフィールを見て友達に追加するには、アカウントを作成してください。',
    'Create an account to listen to this Voice Moment.':
        'このVoice Momentを聴くにはアカウントを作成してください。',
    'Share this Moment': 'このMomentを共有',
  },
  'ko': <String, String>{
    'My link': '내 링크',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        '링크를 열거나 코드를 스캔한 사람은 내 프로필을 보고 친구로 추가할 수 있어요.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        '링크를 열거나 코드를 스캔한 사람은 내 페이지를 보고 팔로우할 수 있어요.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        '프로필이 공개 상태가 아니어서 이 링크로 모든 사람이 프로필을 볼 수는 없어요. 누구나 나를 추가할 수 있게 하려면 설정에서 프로필 공개 범위를 변경하세요.',
    'Copy link': '링크 복사',
    'Share my link': '내 링크 공유',
    'QR code with your link': '내 링크가 담긴 QR 코드',
    'Link copied.': '링크를 복사했어요.',
    'Your link is not available right now.': '지금은 내 링크를 사용할 수 없어요.',
    'Find me on YO Voice: {link}': 'YO Voice에서 저를 찾아보세요: {link}',
    'Listen to {name} on YO Voice: {link}':
        'YO Voice에서 {name} 님의 목소리를 들어보세요: {link}',
    'This profile is not available.': '이 프로필은 볼 수 없어요.',
    'This Moment is no longer available': '이 Moment는 더 이상 볼 수 없어요',
    'It reached the end of its availability or was deleted by its author.':
        '공개 기간이 끝났거나 작성자가 삭제했어요.',
    'Back to Moments': '모먼트로 돌아가기',
    'Sign in to see this profile and add this person as a friend.':
        '이 프로필을 보고 친구로 추가하려면 로그인하세요.',
    'Sign in to listen to this Voice Moment.': '이 Voice Moment를 들으려면 로그인하세요.',
    'Create an account to see this profile and add this person as a friend.':
        '이 프로필을 보고 친구로 추가하려면 계정을 만드세요.',
    'Create an account to listen to this Voice Moment.':
        '이 Voice Moment를 들으려면 계정을 만드세요.',
    'Share this Moment': '이 Moment 공유',
  },
  'ar': <String, String>{
    'My link': 'رابطي',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'كل من يفتحه أو يمسح الرمز سيرى ملفك الشخصي ويمكنه إضافتك كصديق.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'كل من يفتحه أو يمسح الرمز سيرى صفحتك ويمكنه متابعتك.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'ملفك الشخصي ليس عامًا، لذلك لن يفتحه هذا الرابط للجميع. ليتمكن أي شخص من إضافتك، غيّر «ظهور الملف الشخصي» من الإعدادات.',
    'Copy link': 'نسخ الرابط',
    'Share my link': 'مشاركة رابطي',
    'QR code with your link': 'رمز QR يحتوي على رابطك',
    'Link copied.': 'تم نسخ الرابط.',
    'Your link is not available right now.': 'رابطك غير متاح حاليًا.',
    'Find me on YO Voice: {link}': 'اعثر عليّ في YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}':
        'استمع إلى {name} في YO Voice: {link}',
    'This profile is not available.': 'هذا الملف الشخصي غير متاح.',
    'This Moment is no longer available': 'هذا الـ Moment لم يعد متاحًا',
    'It reached the end of its availability or was deleted by its author.':
        'انتهت مدة إتاحته أو حذفه صاحبه.',
    'Back to Moments': 'العودة إلى اللحظات',
    'Sign in to see this profile and add this person as a friend.':
        'سجّل الدخول لعرض هذا الملف الشخصي وإضافة هذا الشخص كصديق.',
    'Sign in to listen to this Voice Moment.':
        'سجّل الدخول للاستماع إلى هذا الـ Voice Moment.',
    'Create an account to see this profile and add this person as a friend.':
        'أنشئ حسابًا لعرض هذا الملف الشخصي وإضافة هذا الشخص كصديق.',
    'Create an account to listen to this Voice Moment.':
        'أنشئ حسابًا للاستماع إلى هذا الـ Voice Moment.',
    'Share this Moment': 'مشاركة هذا الـ Moment',
  },
  'th': <String, String>{
    'My link': 'ลิงก์ของฉัน',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'ใครก็ตามที่เปิดลิงก์หรือสแกนโค้ดจะเห็นโปรไฟล์ของคุณและเพิ่มคุณเป็นเพื่อนได้',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'ใครก็ตามที่เปิดลิงก์หรือสแกนโค้ดจะเห็นเพจของคุณและติดตามคุณได้',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'โปรไฟล์ของคุณไม่ได้เป็นสาธารณะ ลิงก์นี้จึงไม่ได้เปิดโปรไฟล์ให้ทุกคนเห็น หากต้องการให้ใครก็เพิ่มคุณได้ ให้เปลี่ยนการมองเห็นโปรไฟล์ในการตั้งค่า',
    'Copy link': 'คัดลอกลิงก์',
    'Share my link': 'แชร์ลิงก์ของฉัน',
    'QR code with your link': 'คิวอาร์โค้ดที่มีลิงก์ของคุณ',
    'Link copied.': 'คัดลอกลิงก์แล้ว',
    'Your link is not available right now.':
        'ลิงก์ของคุณยังใช้งานไม่ได้ในขณะนี้',
    'Find me on YO Voice: {link}': 'ตามหาฉันได้ใน YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}': 'ฟัง {name} ใน YO Voice: {link}',
    'This profile is not available.': 'โปรไฟล์นี้ไม่พร้อมใช้งาน',
    'This Moment is no longer available': 'Moment นี้ไม่พร้อมใช้งานแล้ว',
    'It reached the end of its availability or was deleted by its author.':
        'หมดช่วงเวลาที่เปิดให้ฟังแล้ว หรือผู้สร้างลบไปแล้ว',
    'Back to Moments': 'กลับไปที่โมเมนต์',
    'Sign in to see this profile and add this person as a friend.':
        'เข้าสู่ระบบเพื่อดูโปรไฟล์นี้และเพิ่มบุคคลนี้เป็นเพื่อน',
    'Sign in to listen to this Voice Moment.':
        'เข้าสู่ระบบเพื่อฟัง Voice Moment นี้',
    'Create an account to see this profile and add this person as a friend.':
        'สร้างบัญชีเพื่อดูโปรไฟล์นี้และเพิ่มบุคคลนี้เป็นเพื่อน',
    'Create an account to listen to this Voice Moment.':
        'สร้างบัญชีเพื่อฟัง Voice Moment นี้',
    'Share this Moment': 'แชร์ Moment นี้',
  },
  'ms': <String, String>{
    'My link': 'Pautan saya',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Sesiapa yang membukanya atau mengimbas kod akan melihat profil anda dan boleh menambah anda sebagai rakan.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Sesiapa yang membukanya atau mengimbas kod akan melihat halaman anda dan boleh mengikuti anda.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Profil anda tidak umum, jadi pautan ini tidak akan membukanya untuk semua orang. Untuk membolehkan sesiapa sahaja menambah anda, tukar Keterlihatan profil dalam Tetapan.',
    'Copy link': 'Salin pautan',
    'Share my link': 'Kongsi pautan saya',
    'QR code with your link': 'Kod QR dengan pautan anda',
    'Link copied.': 'Pautan disalin.',
    'Your link is not available right now.':
        'Pautan anda tidak tersedia sekarang.',
    'Find me on YO Voice: {link}': 'Cari saya di YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}': 'Dengar {name} di YO Voice: {link}',
    'This profile is not available.': 'Profil ini tidak tersedia.',
    'This Moment is no longer available': 'Moment ini tidak lagi tersedia',
    'It reached the end of its availability or was deleted by its author.':
        'Tempoh ketersediaannya telah tamat atau ia dipadamkan oleh pengarangnya.',
    'Back to Moments': 'Kembali ke Momen',
    'Sign in to see this profile and add this person as a friend.':
        'Log masuk untuk melihat profil ini dan menambah orang ini sebagai rakan.',
    'Sign in to listen to this Voice Moment.':
        'Log masuk untuk mendengar Voice Moment ini.',
    'Create an account to see this profile and add this person as a friend.':
        'Buat akaun untuk melihat profil ini dan menambah orang ini sebagai rakan.',
    'Create an account to listen to this Voice Moment.':
        'Buat akaun untuk mendengar Voice Moment ini.',
    'Share this Moment': 'Kongsi Moment ini',
  },
  'fil': <String, String>{
    'My link': 'Ang link ko',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Makikita ng sinumang magbukas nito o mag-scan ng code ang profile mo at maaari ka niyang idagdag bilang kaibigan.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Makikita ng sinumang magbukas nito o mag-scan ng code ang Page mo at maaari ka niyang i-follow.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Hindi pampubliko ang profile mo, kaya hindi ito mabubuksan ng link na ito para sa lahat. Para maidagdag ka ng kahit sino, palitan ang Visibility ng profile sa Mga setting.',
    'Copy link': 'Kopyahin ang link',
    'Share my link': 'Ibahagi ang link ko',
    'QR code with your link': 'QR code na may link mo',
    'Link copied.': 'Nakopya ang link.',
    'Your link is not available right now.':
        'Hindi available ang link mo sa ngayon.',
    'Find me on YO Voice: {link}': 'Hanapin ako sa YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}':
        'Pakinggan si {name} sa YO Voice: {link}',
    'This profile is not available.': 'Hindi available ang profile na ito.',
    'This Moment is no longer available':
        'Hindi na available ang Moment na ito',
    'It reached the end of its availability or was deleted by its author.':
        'Natapos na ang panahon ng availability nito o binura ito ng may-akda.',
    'Back to Moments': 'Bumalik sa Mga Moment',
    'Sign in to see this profile and add this person as a friend.':
        'Mag-sign in para makita ang profile na ito at idagdag ang taong ito bilang kaibigan.',
    'Sign in to listen to this Voice Moment.':
        'Mag-sign in para pakinggan ang Voice Moment na ito.',
    'Create an account to see this profile and add this person as a friend.':
        'Gumawa ng account para makita ang profile na ito at idagdag ang taong ito bilang kaibigan.',
    'Create an account to listen to this Voice Moment.':
        'Gumawa ng account para pakinggan ang Voice Moment na ito.',
    'Share this Moment': 'Ibahagi ang Moment na ito',
  },
  'he': <String, String>{
    'My link': 'הקישור שלי',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'מי שיפתח אותו או יסרוק את הקוד יראה את הפרופיל שלך ויוכל להוסיף אותך כחבר.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'מי שיפתח אותו או יסרוק את הקוד יראה את הדף שלך ויוכל לעקוב אחריך.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'הפרופיל שלך אינו ציבורי, ולכן הקישור הזה לא יפתח אותו לכולם. כדי שכל אחד יוכל להוסיף אותך, יש לשנות את נראות הפרופיל בהגדרות.',
    'Copy link': 'העתקת קישור',
    'Share my link': 'שיתוף הקישור שלי',
    'QR code with your link': 'קוד QR עם הקישור שלך',
    'Link copied.': 'הקישור הועתק.',
    'Your link is not available right now.': 'הקישור שלך אינו זמין כרגע.',
    'Find me on YO Voice: {link}': 'אפשר למצוא אותי ב-YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}':
        'להאזנה ל-{name} ב-YO Voice: {link}',
    'This profile is not available.': 'הפרופיל הזה אינו זמין.',
    'This Moment is no longer available': 'ה-Moment הזה כבר לא זמין',
    'It reached the end of its availability or was deleted by its author.':
        'זמן הזמינות שלו הסתיים או שהיוצר מחק אותו.',
    'Back to Moments': 'חזרה לרגעים',
    'Sign in to see this profile and add this person as a friend.':
        'יש להתחבר כדי לראות את הפרופיל הזה ולהוסיף את האדם הזה כחבר.',
    'Sign in to listen to this Voice Moment.':
        'יש להתחבר כדי להאזין ל-Voice Moment הזה.',
    'Create an account to see this profile and add this person as a friend.':
        'יש ליצור חשבון כדי לראות את הפרופיל הזה ולהוסיף את האדם הזה כחבר.',
    'Create an account to listen to this Voice Moment.':
        'יש ליצור חשבון כדי להאזין ל-Voice Moment הזה.',
    'Share this Moment': 'שיתוף ה-Moment הזה',
  },
  'fa': <String, String>{
    'My link': 'پیوند من',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'هر کسی آن را باز کند یا کد را اسکن کند، نمایهٔ شما را می‌بیند و می‌تواند شما را به دوستانش اضافه کند.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'هر کسی آن را باز کند یا کد را اسکن کند، صفحهٔ شما را می‌بیند و می‌تواند شما را دنبال کند.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'نمایهٔ شما عمومی نیست، بنابراین این پیوند آن را برای همه باز نمی‌کند. برای اینکه هر کسی بتواند شما را اضافه کند، «نمایش نمایه» را در تنظیمات تغییر دهید.',
    'Copy link': 'کپی پیوند',
    'Share my link': 'اشتراک‌گذاری پیوند من',
    'QR code with your link': 'کد QR با پیوند شما',
    'Link copied.': 'پیوند کپی شد.',
    'Your link is not available right now.':
        'پیوند شما در حال حاضر در دسترس نیست.',
    'Find me on YO Voice: {link}': 'مرا در YO Voice پیدا کنید: {link}',
    'Listen to {name} on YO Voice: {link}':
        'به {name} در YO Voice گوش دهید: {link}',
    'This profile is not available.': 'این نمایه در دسترس نیست.',
    'This Moment is no longer available': 'این Moment دیگر در دسترس نیست',
    'It reached the end of its availability or was deleted by its author.':
        'زمان دسترسی آن به پایان رسیده یا سازنده آن را حذف کرده است.',
    'Back to Moments': 'بازگشت به لحظه‌ها',
    'Sign in to see this profile and add this person as a friend.':
        'برای دیدن این نمایه و افزودن این شخص به دوستان وارد شوید.',
    'Sign in to listen to this Voice Moment.':
        'برای گوش دادن به این Voice Moment وارد شوید.',
    'Create an account to see this profile and add this person as a friend.':
        'برای دیدن این نمایه و افزودن این شخص به دوستان، حساب کاربری بسازید.',
    'Create an account to listen to this Voice Moment.':
        'برای گوش دادن به این Voice Moment حساب کاربری بسازید.',
    'Share this Moment': 'اشتراک‌گذاری این Moment',
  },
  'sw': <String, String>{
    'My link': 'Kiungo changu',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'Yeyote atakayekifungua au kuchanganua msimbo ataona wasifu wako na anaweza kukuongeza kama rafiki.',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'Yeyote atakayekifungua au kuchanganua msimbo ataona ukurasa wako na anaweza kukufuata.',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'Wasifu wako si wa umma, kwa hivyo kiungo hiki hakitaufungua kwa kila mtu. Ili yeyote aweze kukuongeza, badilisha Mwonekano wa wasifu kwenye Mipangilio.',
    'Copy link': 'Nakili kiungo',
    'Share my link': 'Shiriki kiungo changu',
    'QR code with your link': 'Msimbo wa QR wenye kiungo chako',
    'Link copied.': 'Kiungo kimenakiliwa.',
    'Your link is not available right now.':
        'Kiungo chako hakipatikani kwa sasa.',
    'Find me on YO Voice: {link}': 'Nitafute kwenye YO Voice: {link}',
    'Listen to {name} on YO Voice: {link}':
        'Msikilize {name} kwenye YO Voice: {link}',
    'This profile is not available.': 'Wasifu huu haupatikani.',
    'This Moment is no longer available': 'Moment hii haipatikani tena',
    'It reached the end of its availability or was deleted by its author.':
        'Muda wake wa kupatikana umeisha au mwandishi ameifuta.',
    'Back to Moments': 'Rudi kwenye Matukio',
    'Sign in to see this profile and add this person as a friend.':
        'Ingia ili kuona wasifu huu na kumwongeza mtu huyu kama rafiki.',
    'Sign in to listen to this Voice Moment.':
        'Ingia ili kusikiliza Voice Moment hii.',
    'Create an account to see this profile and add this person as a friend.':
        'Fungua akaunti ili kuona wasifu huu na kumwongeza mtu huyu kama rafiki.',
    'Create an account to listen to this Voice Moment.':
        'Fungua akaunti ili kusikiliza Voice Moment hii.',
    'Share this Moment': 'Shiriki Moment hii',
  },
  'hi': <String, String>{
    'My link': 'मेरा लिंक',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'जो भी इसे खोलेगा या कोड स्कैन करेगा, वह आपकी प्रोफ़ाइल देखेगा और आपको दोस्त के रूप में जोड़ सकेगा।',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'जो भी इसे खोलेगा या कोड स्कैन करेगा, वह आपका पेज देखेगा और आपको फ़ॉलो कर सकेगा।',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'आपकी प्रोफ़ाइल सार्वजनिक नहीं है, इसलिए यह लिंक इसे सभी के लिए नहीं खोलेगा। कोई भी आपको जोड़ सके, इसके लिए सेटिंग्स में प्रोफ़ाइल की दृश्यता बदलें।',
    'Copy link': 'लिंक कॉपी करें',
    'Share my link': 'मेरा लिंक शेयर करें',
    'QR code with your link': 'आपके लिंक वाला QR कोड',
    'Link copied.': 'लिंक कॉपी हो गया।',
    'Your link is not available right now.': 'आपका लिंक अभी उपलब्ध नहीं है।',
    'Find me on YO Voice: {link}': 'मुझे YO Voice पर खोजें: {link}',
    'Listen to {name} on YO Voice: {link}':
        'YO Voice पर {name} को सुनें: {link}',
    'This profile is not available.': 'यह प्रोफ़ाइल उपलब्ध नहीं है।',
    'This Moment is no longer available': 'यह Moment अब उपलब्ध नहीं है',
    'It reached the end of its availability or was deleted by its author.':
        'इसकी उपलब्धता का समय समाप्त हो गया है या इसके लेखक ने इसे हटा दिया है।',
    'Back to Moments': 'मोमेंट्स पर वापस जाएँ',
    'Sign in to see this profile and add this person as a friend.':
        'यह प्रोफ़ाइल देखने और इस व्यक्ति को दोस्त के रूप में जोड़ने के लिए साइन इन करें।',
    'Sign in to listen to this Voice Moment.':
        'यह Voice Moment सुनने के लिए साइन इन करें।',
    'Create an account to see this profile and add this person as a friend.':
        'यह प्रोफ़ाइल देखने और इस व्यक्ति को दोस्त के रूप में जोड़ने के लिए खाता बनाएं।',
    'Create an account to listen to this Voice Moment.':
        'यह Voice Moment सुनने के लिए खाता बनाएं।',
    'Share this Moment': 'यह Moment साझा करें',
  },
  'bn': <String, String>{
    'My link': 'আমার লিংক',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'যে কেউ এটি খুললে বা কোড স্ক্যান করলে আপনার প্রোফাইল দেখতে পাবেন এবং আপনাকে বন্ধু হিসেবে যোগ করতে পারবেন।',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'যে কেউ এটি খুললে বা কোড স্ক্যান করলে আপনার পেজ দেখতে পাবেন এবং আপনাকে ফলো করতে পারবেন।',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'আপনার প্রোফাইল সর্বজনীন নয়, তাই এই লিংক সবার জন্য এটি খুলবে না। যে কেউ যাতে আপনাকে যোগ করতে পারেন, সে জন্য সেটিংসে প্রোফাইলের দৃশ্যমানতা পরিবর্তন করুন।',
    'Copy link': 'লিংক কপি করুন',
    'Share my link': 'আমার লিংক শেয়ার করুন',
    'QR code with your link': 'আপনার লিংকসহ QR কোড',
    'Link copied.': 'লিংক কপি হয়েছে।',
    'Your link is not available right now.':
        'আপনার লিংক এই মুহূর্তে পাওয়া যাচ্ছে না।',
    'Find me on YO Voice: {link}': 'YO Voice-এ আমাকে খুঁজুন: {link}',
    'Listen to {name} on YO Voice: {link}':
        'YO Voice-এ {name}-কে শুনুন: {link}',
    'This profile is not available.': 'এই প্রোফাইলটি পাওয়া যাচ্ছে না।',
    'This Moment is no longer available': 'এই Moment আর পাওয়া যাচ্ছে না',
    'It reached the end of its availability or was deleted by its author.':
        'এর উপলভ্যতার সময় শেষ হয়েছে অথবা এর লেখক এটি মুছে ফেলেছেন।',
    'Back to Moments': 'মোমেন্টসে ফিরে যান',
    'Sign in to see this profile and add this person as a friend.':
        'এই প্রোফাইল দেখতে এবং এই ব্যক্তিকে বন্ধু হিসেবে যোগ করতে সাইন ইন করুন।',
    'Sign in to listen to this Voice Moment.':
        'এই Voice Moment শুনতে সাইন ইন করুন।',
    'Create an account to see this profile and add this person as a friend.':
        'এই প্রোফাইল দেখতে এবং এই ব্যক্তিকে বন্ধু হিসেবে যোগ করতে অ্যাকাউন্ট তৈরি করুন।',
    'Create an account to listen to this Voice Moment.':
        'এই Voice Moment শুনতে অ্যাকাউন্ট তৈরি করুন।',
    'Share this Moment': 'এই Moment শেয়ার করুন',
  },
  'ur': <String, String>{
    'My link': 'میرا لنک',
    'Anyone who opens it or scans the code will see your profile and can add you as a friend.':
        'جو بھی اسے کھولے گا یا کوڈ اسکین کرے گا، وہ آپ کی پروفائل دیکھے گا اور آپ کو دوست کے طور پر شامل کر سکے گا۔',
    'Anyone who opens it or scans the code will see your Page and can follow you.':
        'جو بھی اسے کھولے گا یا کوڈ اسکین کرے گا، وہ آپ کا پیج دیکھے گا اور آپ کو فالو کر سکے گا۔',
    'Your profile is not public, so this link will not open it for everyone. To let anyone add you, change Profile visibility in Settings.':
        'آپ کی پروفائل عوامی نہیں ہے، اس لیے یہ لنک اسے سب کے لیے نہیں کھولے گا۔ تاکہ کوئی بھی آپ کو شامل کر سکے، ترتیبات میں پروفائل کی مرئیت تبدیل کریں۔',
    'Copy link': 'لنک کاپی کریں',
    'Share my link': 'میرا لنک شیئر کریں',
    'QR code with your link': 'آپ کے لنک والا QR کوڈ',
    'Link copied.': 'لنک کاپی ہو گیا۔',
    'Your link is not available right now.': 'آپ کا لنک اس وقت دستیاب نہیں ہے۔',
    'Find me on YO Voice: {link}': 'مجھے YO Voice پر تلاش کریں: {link}',
    'Listen to {name} on YO Voice: {link}':
        'YO Voice پر {name} کو سنیں: {link}',
    'This profile is not available.': 'یہ پروفائل دستیاب نہیں ہے۔',
    'This Moment is no longer available': 'یہ Moment اب دستیاب نہیں ہے',
    'It reached the end of its availability or was deleted by its author.':
        'اس کی دستیابی کا وقت ختم ہو گیا ہے یا اس کے مصنف نے اسے حذف کر دیا ہے۔',
    'Back to Moments': 'لمحات پر واپس جائیں',
    'Sign in to see this profile and add this person as a friend.':
        'یہ پروفائل دیکھنے اور اس شخص کو دوست کے طور پر شامل کرنے کے لیے سائن ان کریں۔',
    'Sign in to listen to this Voice Moment.':
        'یہ Voice Moment سننے کے لیے سائن ان کریں۔',
    'Create an account to see this profile and add this person as a friend.':
        'یہ پروفائل دیکھنے اور اس شخص کو دوست کے طور پر شامل کرنے کے لیے اکاؤنٹ بنائیں۔',
    'Create an account to listen to this Voice Moment.':
        'یہ Voice Moment سننے کے لیے اکاؤنٹ بنائیں۔',
    'Share this Moment': 'یہ Moment شیئر کریں',
  },
};
