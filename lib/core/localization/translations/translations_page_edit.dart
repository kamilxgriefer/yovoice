/// Copy for "Edytuj stronę" (pageEdit A, owner decision 2026-10-03): the one
/// Page edit form with its live preview, the unsaved-changes and save states,
/// the read-only form with "Wyczyść dane kontaktowe" (ADR-241) and the entry
/// in Page settings.
///
/// English and Polish are authored at the call site (`PageEditCopy` in
/// `lib/features/pages/presentation/page_edit_copy.dart`); this module gives
/// every other selectable locale an explicit translation, so none of these
/// strings falls back to English. What the form shares with create A and the
/// Page profile (field labels, "Widoczne publicznie", "Zapisz", "Anuluj")
/// stays in `translations_pages.dart`.
///
/// Two kinds of key live here:
///
/// * The final English phrase or template (`You can change the name again on
///   {date}.`), resolved by `AppLocalizations.text` / `.template`.
/// * `pageEdit.*` context keys for short words whose meaning depends on the
///   form ("Appearance" the section, "Name" the field, "Clear" the confirm
///   button), resolved by `AppLocalizations.contextualText`.
///
/// "Premium", "VIP", "JPG", "PNG" and "WebP" stay as written. Every value
/// keeps exactly the placeholders of its key
/// (`test/page_edit_localization_test.dart`).
const pageEditTranslationKeys = <String>[
  'pageEdit.appearance',
  'pageEdit.name',
  'pageEdit.clear',
  'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.',
  'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.',
  'You can change the name again on {date}.',
  'The name must be 2 to 120 characters long.',
  "The type can't be changed yet",
  'For example: be kind, no ads, only photos of your own work.',
  'Change cover',
  'Change photo',
  'This is how others will see your Page. The preview changes as you type.',
  'Hide preview',
  'Show preview',
  'You have unsaved changes',
  'Save changes',
  'Discard changes?',
  "Your changes haven't been saved.",
  "Couldn't save the changes",
  'Some changes were saved, but not all',
  "Couldn't change the name. Try again.",
  'The name is saved. Press Save again to finish.',
  "Couldn't use this image. Choose a JPG, PNG or WebP file.",
  "Couldn't upload the image. Check your connection and try again.",
  'Editing is off right now',
  'Editing comes back when Premium or VIP is active again.',
  "This Page is suspended by moderation, so it can't be edited.",
  'Clear contact details',
  'Clear contact details?',
  "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.",
  'Contact details cleared',
  'Cover, photo, name, description and everything visitors see',
];

const pageEditTranslations = <String, Map<String, String>>{
  'de': <String, String>{
    'pageEdit.appearance': 'Aussehen',
    'pageEdit.name': 'Name',
    'pageEdit.clear': 'Löschen',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Titelbild, Foto und Name deiner Seite sind auch Titelbild, Foto und Name deines Kontos in Chats und auf Servern.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Du kannst den Namen einmal alle 30 Tage ändern. Nach einer Änderung erscheint die Seite 7 Tage lang nicht in der Suche.',
    'You can change the name again on {date}.':
        'Du kannst den Namen wieder am {date} ändern.',
    'The name must be 2 to 120 characters long.':
        'Der Name muss 2 bis 120 Zeichen lang sein.',
    "The type can't be changed yet": 'Der Typ lässt sich noch nicht ändern',
    'For example: be kind, no ads, only photos of your own work.':
        'Zum Beispiel: freundlich bleiben, keine Werbung, nur Fotos eigener Arbeiten.',
    'Change cover': 'Titelbild ändern',
    'Change photo': 'Foto ändern',
    'This is how others will see your Page. The preview changes as you type.':
        'So sehen andere deine Seite. Die Vorschau ändert sich beim Tippen.',
    'Hide preview': 'Vorschau ausblenden',
    'Show preview': 'Vorschau anzeigen',
    'You have unsaved changes': 'Du hast ungespeicherte Änderungen',
    'Save changes': 'Änderungen speichern',
    'Discard changes?': 'Änderungen verwerfen?',
    "Your changes haven't been saved.":
        'Deine Änderungen wurden nicht gespeichert.',
    "Couldn't save the changes":
        'Die Änderungen konnten nicht gespeichert werden',
    'Some changes were saved, but not all':
        'Einige Änderungen wurden gespeichert, aber nicht alle',
    "Couldn't change the name. Try again.":
        'Der Name konnte nicht geändert werden. Versuche es erneut.',
    'The name is saved. Press Save again to finish.':
        'Der Name ist gespeichert. Tippe noch einmal auf Speichern, um abzuschließen.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Dieses Bild kann nicht verwendet werden. Wähle eine JPG-, PNG- oder WebP-Datei.',
    "Couldn't upload the image. Check your connection and try again.":
        'Das Bild konnte nicht hochgeladen werden. Prüfe deine Verbindung und versuche es erneut.',
    'Editing is off right now': 'Bearbeiten ist gerade nicht möglich',
    'Editing comes back when Premium or VIP is active again.':
        'Du kannst wieder bearbeiten, sobald Premium oder VIP aktiv ist.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Diese Seite wurde von der Moderation gesperrt und kann deshalb nicht bearbeitet werden.',
    'Clear contact details': 'Kontaktdaten löschen',
    'Clear contact details?': 'Kontaktdaten löschen?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Website, E-Mail, Telefon, Adresse, Öffnungszeiten und Impressum werden von deiner Seite entfernt. Das lässt sich nicht rückgängig machen.',
    'Contact details cleared': 'Kontaktdaten gelöscht',
    'Cover, photo, name, description and everything visitors see':
        'Titelbild, Foto, Name, Beschreibung und alles, was Besucher sehen',
  },
  'es': <String, String>{
    'pageEdit.appearance': 'Apariencia',
    'pageEdit.name': 'Nombre',
    'pageEdit.clear': 'Borrar',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'La portada, la foto y el nombre de tu página son también la portada, la foto y el nombre de tu cuenta en los chats y servidores.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Puedes cambiar el nombre una vez cada 30 días. Tras un cambio, la página no aparece en la búsqueda durante 7 días.',
    'You can change the name again on {date}.':
        'Podrás volver a cambiar el nombre el {date}.',
    'The name must be 2 to 120 characters long.':
        'El nombre debe tener entre 2 y 120 caracteres.',
    "The type can't be changed yet": 'El tipo aún no se puede cambiar',
    'For example: be kind, no ads, only photos of your own work.':
        'Por ejemplo: nos respetamos, sin anuncios, solo fotos de trabajos propios.',
    'Change cover': 'Cambiar portada',
    'Change photo': 'Cambiar foto',
    'This is how others will see your Page. The preview changes as you type.':
        'Así verán los demás tu página. La vista previa cambia mientras escribes.',
    'Hide preview': 'Ocultar vista previa',
    'Show preview': 'Mostrar vista previa',
    'You have unsaved changes': 'Tienes cambios sin guardar',
    'Save changes': 'Guardar cambios',
    'Discard changes?': '¿Descartar los cambios?',
    "Your changes haven't been saved.": 'Tus cambios no se han guardado.',
    "Couldn't save the changes": 'No se pudieron guardar los cambios',
    'Some changes were saved, but not all':
        'Se guardaron algunos cambios, pero no todos',
    "Couldn't change the name. Try again.":
        'No se pudo cambiar el nombre. Inténtalo de nuevo.',
    'The name is saved. Press Save again to finish.':
        'El nombre está guardado. Pulsa Guardar otra vez para terminar.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'No se puede usar esta imagen. Elige un archivo JPG, PNG o WebP.',
    "Couldn't upload the image. Check your connection and try again.":
        'No se pudo subir la imagen. Revisa tu conexión e inténtalo de nuevo.',
    'Editing is off right now': 'La edición está desactivada por ahora',
    'Editing comes back when Premium or VIP is active again.':
        'Podrás volver a editar cuando Premium o VIP esté activo de nuevo.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Moderación ha suspendido esta página, por lo que no se puede editar.',
    'Clear contact details': 'Borrar datos de contacto',
    'Clear contact details?': '¿Borrar los datos de contacto?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'El sitio web, el correo, el teléfono, la dirección, el horario y el aviso legal se quitarán de tu página. Esto no se puede deshacer.',
    'Contact details cleared': 'Datos de contacto borrados',
    'Cover, photo, name, description and everything visitors see':
        'Portada, foto, nombre, descripción y todo lo que ven los visitantes',
  },
  'pt': <String, String>{
    'pageEdit.appearance': 'Aspeto',
    'pageEdit.name': 'Nome',
    'pageEdit.clear': 'Limpar',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'A capa, a foto e o nome da tua página são também a capa, a foto e o nome da tua conta nas conversas e nos servidores.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Podes alterar o nome uma vez a cada 30 dias. Depois de uma alteração, a página fica 7 dias fora da pesquisa.',
    'You can change the name again on {date}.':
        'Podes voltar a alterar o nome a {date}.',
    'The name must be 2 to 120 characters long.':
        'O nome tem de ter entre 2 e 120 caracteres.',
    "The type can't be changed yet": 'Ainda não é possível alterar o tipo',
    'For example: be kind, no ads, only photos of your own work.':
        'Por exemplo: respeitamo-nos, sem anúncios, só fotos de trabalhos próprios.',
    'Change cover': 'Alterar capa',
    'Change photo': 'Alterar foto',
    'This is how others will see your Page. The preview changes as you type.':
        'É assim que os outros vão ver a tua página. A pré-visualização muda enquanto escreves.',
    'Hide preview': 'Ocultar pré-visualização',
    'Show preview': 'Mostrar pré-visualização',
    'You have unsaved changes': 'Tens alterações por guardar',
    'Save changes': 'Guardar alterações',
    'Discard changes?': 'Rejeitar as alterações?',
    "Your changes haven't been saved.":
        'As tuas alterações não foram guardadas.',
    "Couldn't save the changes": 'Não foi possível guardar as alterações',
    'Some changes were saved, but not all':
        'Algumas alterações foram guardadas, mas não todas',
    "Couldn't change the name. Try again.":
        'Não foi possível alterar o nome. Tenta novamente.',
    'The name is saved. Press Save again to finish.':
        'O nome está guardado. Toca em Guardar outra vez para concluir.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Não é possível usar esta imagem. Escolhe um ficheiro JPG, PNG ou WebP.',
    "Couldn't upload the image. Check your connection and try again.":
        'Não foi possível carregar a imagem. Verifica a ligação e tenta novamente.',
    'Editing is off right now': 'A edição está desativada de momento',
    'Editing comes back when Premium or VIP is active again.':
        'A edição volta quando o Premium ou o VIP estiver novamente ativo.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Esta página foi suspensa pela moderação, por isso não pode ser editada.',
    'Clear contact details': 'Limpar dados de contacto',
    'Clear contact details?': 'Limpar os dados de contacto?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'O site, o e-mail, o telefone, a morada, o horário e o aviso legal serão removidos da tua página. Não é possível anular esta ação.',
    'Contact details cleared': 'Dados de contacto limpos',
    'Cover, photo, name, description and everything visitors see':
        'Capa, foto, nome, descrição e tudo o que os visitantes veem',
  },
  'pt_BR': <String, String>{
    'pageEdit.appearance': 'Aparência',
    'pageEdit.name': 'Nome',
    'pageEdit.clear': 'Limpar',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'A capa, a foto e o nome da sua página também são a capa, a foto e o nome da sua conta nos chats e servidores.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Você pode alterar o nome uma vez a cada 30 dias. Depois de uma alteração, a página fica 7 dias fora da busca.',
    'You can change the name again on {date}.':
        'Você poderá alterar o nome de novo em {date}.',
    'The name must be 2 to 120 characters long.':
        'O nome precisa ter de 2 a 120 caracteres.',
    "The type can't be changed yet": 'Ainda não dá para alterar o tipo',
    'For example: be kind, no ads, only photos of your own work.':
        'Por exemplo: respeito entre todos, sem anúncios, só fotos de trabalhos próprios.',
    'Change cover': 'Alterar capa',
    'Change photo': 'Alterar foto',
    'This is how others will see your Page. The preview changes as you type.':
        'É assim que as outras pessoas verão sua página. A prévia muda enquanto você digita.',
    'Hide preview': 'Ocultar prévia',
    'Show preview': 'Mostrar prévia',
    'You have unsaved changes': 'Você tem alterações não salvas',
    'Save changes': 'Salvar alterações',
    'Discard changes?': 'Descartar as alterações?',
    "Your changes haven't been saved.": 'Suas alterações não foram salvas.',
    "Couldn't save the changes": 'Não foi possível salvar as alterações',
    'Some changes were saved, but not all':
        'Algumas alterações foram salvas, mas não todas',
    "Couldn't change the name. Try again.":
        'Não foi possível alterar o nome. Tente novamente.',
    'The name is saved. Press Save again to finish.':
        'O nome foi salvo. Toque em Salvar de novo para concluir.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Não é possível usar esta imagem. Escolha um arquivo JPG, PNG ou WebP.',
    "Couldn't upload the image. Check your connection and try again.":
        'Não foi possível enviar a imagem. Verifique sua conexão e tente novamente.',
    'Editing is off right now': 'A edição está desativada no momento',
    'Editing comes back when Premium or VIP is active again.':
        'A edição volta quando o Premium ou o VIP estiver ativo de novo.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Esta página foi suspensa pela moderação, por isso não pode ser editada.',
    'Clear contact details': 'Limpar dados de contato',
    'Clear contact details?': 'Limpar os dados de contato?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'O site, o e-mail, o telefone, o endereço, o horário e o aviso legal serão removidos da sua página. Não é possível desfazer.',
    'Contact details cleared': 'Dados de contato limpos',
    'Cover, photo, name, description and everything visitors see':
        'Capa, foto, nome, descrição e tudo o que os visitantes veem',
  },
  'fr': <String, String>{
    'pageEdit.appearance': 'Apparence',
    'pageEdit.name': 'Nom',
    'pageEdit.clear': 'Effacer',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'La couverture, la photo et le nom de ta page sont aussi la couverture, la photo et le nom de ton compte dans les discussions et les serveurs.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Tu peux changer le nom une fois tous les 30 jours. Après un changement, la page n’apparaît plus dans la recherche pendant 7 jours.',
    'You can change the name again on {date}.':
        'Tu pourras de nouveau changer le nom le {date}.',
    'The name must be 2 to 120 characters long.':
        'Le nom doit comporter entre 2 et 120 caractères.',
    "The type can't be changed yet": 'Le type ne peut pas encore être modifié',
    'For example: be kind, no ads, only photos of your own work.':
        'Par exemple : respect de chacun, pas de publicité, uniquement des photos de ses propres créations.',
    'Change cover': 'Changer la couverture',
    'Change photo': 'Changer la photo',
    'This is how others will see your Page. The preview changes as you type.':
        'Voici comment les autres verront ta page. L’aperçu change pendant que tu écris.',
    'Hide preview': 'Masquer l’aperçu',
    'Show preview': 'Afficher l’aperçu',
    'You have unsaved changes': 'Tu as des modifications non enregistrées',
    'Save changes': 'Enregistrer les modifications',
    'Discard changes?': 'Abandonner les modifications ?',
    "Your changes haven't been saved.":
        'Tes modifications n’ont pas été enregistrées.',
    "Couldn't save the changes": 'Impossible d’enregistrer les modifications',
    'Some changes were saved, but not all':
        'Certaines modifications ont été enregistrées, mais pas toutes',
    "Couldn't change the name. Try again.":
        'Impossible de changer le nom. Réessaie.',
    'The name is saved. Press Save again to finish.':
        'Le nom est enregistré. Appuie de nouveau sur Enregistrer pour terminer.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Impossible d’utiliser cette image. Choisis un fichier JPG, PNG ou WebP.',
    "Couldn't upload the image. Check your connection and try again.":
        'Impossible d’envoyer l’image. Vérifie ta connexion et réessaie.',
    'Editing is off right now': 'La modification est désactivée pour le moment',
    'Editing comes back when Premium or VIP is active again.':
        'La modification reviendra quand Premium ou VIP sera de nouveau actif.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Cette page a été suspendue par la modération, elle ne peut donc pas être modifiée.',
    'Clear contact details': 'Effacer les coordonnées',
    'Clear contact details?': 'Effacer les coordonnées ?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Le site web, l’e-mail, le téléphone, l’adresse, les horaires et les mentions légales seront retirés de ta page. Cette action est irréversible.',
    'Contact details cleared': 'Coordonnées effacées',
    'Cover, photo, name, description and everything visitors see':
        'Couverture, photo, nom, description et tout ce que voient les visiteurs',
  },
  'it': <String, String>{
    'pageEdit.appearance': 'Aspetto',
    'pageEdit.name': 'Nome',
    'pageEdit.clear': 'Cancella',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'La copertina, la foto e il nome della tua pagina sono anche la copertina, la foto e il nome del tuo account nelle chat e nei server.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Puoi cambiare il nome una volta ogni 30 giorni. Dopo una modifica la pagina non compare nella ricerca per 7 giorni.',
    'You can change the name again on {date}.':
        'Potrai cambiare di nuovo il nome il {date}.',
    'The name must be 2 to 120 characters long.':
        'Il nome deve avere da 2 a 120 caratteri.',
    "The type can't be changed yet": 'Il tipo non si può ancora cambiare',
    'For example: be kind, no ads, only photos of your own work.':
        'Per esempio: rispetto reciproco, niente pubblicità, solo foto di lavori propri.',
    'Change cover': 'Cambia copertina',
    'Change photo': 'Cambia foto',
    'This is how others will see your Page. The preview changes as you type.':
        'Ecco come gli altri vedranno la tua pagina. L’anteprima cambia mentre scrivi.',
    'Hide preview': 'Nascondi anteprima',
    'Show preview': 'Mostra anteprima',
    'You have unsaved changes': 'Hai modifiche non salvate',
    'Save changes': 'Salva modifiche',
    'Discard changes?': 'Annullare le modifiche?',
    "Your changes haven't been saved.":
        'Le tue modifiche non sono state salvate.',
    "Couldn't save the changes": 'Impossibile salvare le modifiche',
    'Some changes were saved, but not all':
        'Alcune modifiche sono state salvate, ma non tutte',
    "Couldn't change the name. Try again.":
        'Impossibile cambiare il nome. Riprova.',
    'The name is saved. Press Save again to finish.':
        'Il nome è stato salvato. Tocca di nuovo Salva per completare.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Impossibile usare questa immagine. Scegli un file JPG, PNG o WebP.',
    "Couldn't upload the image. Check your connection and try again.":
        'Impossibile caricare l’immagine. Controlla la connessione e riprova.',
    'Editing is off right now': 'La modifica al momento è disattivata',
    'Editing comes back when Premium or VIP is active again.':
        'La modifica tornerà quando Premium o VIP sarà di nuovo attivo.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Questa pagina è stata sospesa dalla moderazione, quindi non può essere modificata.',
    'Clear contact details': 'Cancella i dati di contatto',
    'Clear contact details?': 'Cancellare i dati di contatto?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Sito web, e-mail, telefono, indirizzo, orari e note legali verranno rimossi dalla tua pagina. L’operazione non può essere annullata.',
    'Contact details cleared': 'Dati di contatto cancellati',
    'Cover, photo, name, description and everything visitors see':
        'Copertina, foto, nome, descrizione e tutto ciò che vedono i visitatori',
  },
  'nl': <String, String>{
    'pageEdit.appearance': 'Uiterlijk',
    'pageEdit.name': 'Naam',
    'pageEdit.clear': 'Wissen',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'De omslag, de foto en de naam van je pagina zijn ook de omslag, de foto en de naam van je account in chats en servers.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Je kunt de naam één keer per 30 dagen wijzigen. Na een wijziging staat de pagina 7 dagen niet in de zoekresultaten.',
    'You can change the name again on {date}.':
        'Je kunt de naam weer wijzigen op {date}.',
    'The name must be 2 to 120 characters long.':
        'De naam moet 2 tot 120 tekens lang zijn.',
    "The type can't be changed yet": 'Het type kan nog niet worden gewijzigd',
    'For example: be kind, no ads, only photos of your own work.':
        'Bijvoorbeeld: wees aardig, geen reclame, alleen foto’s van eigen werk.',
    'Change cover': 'Omslag wijzigen',
    'Change photo': 'Foto wijzigen',
    'This is how others will see your Page. The preview changes as you type.':
        'Zo zien anderen je pagina. Het voorbeeld verandert terwijl je typt.',
    'Hide preview': 'Voorbeeld verbergen',
    'Show preview': 'Voorbeeld tonen',
    'You have unsaved changes': 'Je hebt niet-opgeslagen wijzigingen',
    'Save changes': 'Wijzigingen opslaan',
    'Discard changes?': 'Wijzigingen weggooien?',
    "Your changes haven't been saved.": 'Je wijzigingen zijn niet opgeslagen.',
    "Couldn't save the changes": 'De wijzigingen konden niet worden opgeslagen',
    'Some changes were saved, but not all':
        'Sommige wijzigingen zijn opgeslagen, maar niet alle',
    "Couldn't change the name. Try again.":
        'De naam kon niet worden gewijzigd. Probeer het opnieuw.',
    'The name is saved. Press Save again to finish.':
        'De naam is opgeslagen. Tik nog een keer op Opslaan om af te ronden.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Deze afbeelding kan niet worden gebruikt. Kies een JPG-, PNG- of WebP-bestand.',
    "Couldn't upload the image. Check your connection and try again.":
        'De afbeelding kon niet worden geüpload. Controleer je verbinding en probeer het opnieuw.',
    'Editing is off right now': 'Bewerken staat nu uit',
    'Editing comes back when Premium or VIP is active again.':
        'Bewerken kan weer zodra Premium of VIP opnieuw actief is.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Deze pagina is door de moderatie geschorst en kan daarom niet worden bewerkt.',
    'Clear contact details': 'Contactgegevens wissen',
    'Clear contact details?': 'Contactgegevens wissen?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'De website, het e-mailadres, het telefoonnummer, het adres, de openingstijden en de juridische vermelding worden van je pagina verwijderd. Dit kan niet ongedaan worden gemaakt.',
    'Contact details cleared': 'Contactgegevens gewist',
    'Cover, photo, name, description and everything visitors see':
        'Omslag, foto, naam, beschrijving en alles wat bezoekers zien',
  },
  'ro': <String, String>{
    'pageEdit.appearance': 'Aspect',
    'pageEdit.name': 'Nume',
    'pageEdit.clear': 'Șterge',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Coperta, fotografia și numele paginii tale sunt și coperta, fotografia și numele contului tău în conversații și pe servere.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Poți schimba numele o dată la 30 de zile. După o schimbare, pagina nu apare în căutare timp de 7 zile.',
    'You can change the name again on {date}.':
        'Vei putea schimba din nou numele pe {date}.',
    'The name must be 2 to 120 characters long.':
        'Numele trebuie să aibă între 2 și 120 de caractere.',
    "The type can't be changed yet": 'Tipul nu poate fi schimbat încă',
    'For example: be kind, no ads, only photos of your own work.':
        'De exemplu: ne respectăm, fără reclame, doar fotografii cu lucrări proprii.',
    'Change cover': 'Schimbă coperta',
    'Change photo': 'Schimbă fotografia',
    'This is how others will see your Page. The preview changes as you type.':
        'Așa vor vedea ceilalți pagina ta. Previzualizarea se schimbă pe măsură ce scrii.',
    'Hide preview': 'Ascunde previzualizarea',
    'Show preview': 'Arată previzualizarea',
    'You have unsaved changes': 'Ai modificări nesalvate',
    'Save changes': 'Salvează modificările',
    'Discard changes?': 'Renunți la modificări?',
    "Your changes haven't been saved.": 'Modificările tale nu au fost salvate.',
    "Couldn't save the changes": 'Modificările nu au putut fi salvate',
    'Some changes were saved, but not all':
        'Unele modificări au fost salvate, dar nu toate',
    "Couldn't change the name. Try again.":
        'Numele nu a putut fi schimbat. Încearcă din nou.',
    'The name is saved. Press Save again to finish.':
        'Numele este salvat. Apasă din nou pe Salvează pentru a termina.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Această imagine nu poate fi folosită. Alege un fișier JPG, PNG sau WebP.',
    "Couldn't upload the image. Check your connection and try again.":
        'Imaginea nu a putut fi încărcată. Verifică conexiunea și încearcă din nou.',
    'Editing is off right now': 'Editarea este dezactivată acum',
    'Editing comes back when Premium or VIP is active again.':
        'Editarea revine când Premium sau VIP este din nou activ.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Această pagină a fost suspendată de moderare, așa că nu poate fi editată.',
    'Clear contact details': 'Șterge datele de contact',
    'Clear contact details?': 'Ștergi datele de contact?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Site-ul, e-mailul, telefonul, adresa, programul și mențiunile legale vor fi eliminate de pe pagina ta. Acțiunea nu poate fi anulată.',
    'Contact details cleared': 'Datele de contact au fost șterse',
    'Cover, photo, name, description and everything visitors see':
        'Copertă, fotografie, nume, descriere și tot ce văd vizitatorii',
  },
  'tr': <String, String>{
    'pageEdit.appearance': 'Görünüm',
    'pageEdit.name': 'Ad',
    'pageEdit.clear': 'Temizle',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Sayfanın kapağı, fotoğrafı ve adı aynı zamanda sohbetlerde ve sunucularda hesabının kapağı, fotoğrafı ve adıdır.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Adı 30 günde bir kez değiştirebilirsin. Değişiklikten sonra sayfa 7 gün boyunca aramada görünmez.',
    'You can change the name again on {date}.':
        'Adı {date} tarihinde yeniden değiştirebilirsin.',
    'The name must be 2 to 120 characters long.':
        'Ad 2 ile 120 karakter arasında olmalı.',
    "The type can't be changed yet": 'Tür henüz değiştirilemiyor',
    'For example: be kind, no ads, only photos of your own work.':
        'Örneğin: saygılı olalım, reklam yok, yalnızca kendi işlerinin fotoğrafları.',
    'Change cover': 'Kapağı değiştir',
    'Change photo': 'Fotoğrafı değiştir',
    'This is how others will see your Page. The preview changes as you type.':
        'Başkaları sayfanı böyle görecek. Önizleme sen yazdıkça değişir.',
    'Hide preview': 'Önizlemeyi gizle',
    'Show preview': 'Önizlemeyi göster',
    'You have unsaved changes': 'Kaydedilmemiş değişikliklerin var',
    'Save changes': 'Değişiklikleri kaydet',
    'Discard changes?': 'Değişiklikler silinsin mi?',
    "Your changes haven't been saved.": 'Değişikliklerin kaydedilmedi.',
    "Couldn't save the changes": 'Değişiklikler kaydedilemedi',
    'Some changes were saved, but not all':
        'Bazı değişiklikler kaydedildi, ama hepsi değil',
    "Couldn't change the name. Try again.": 'Ad değiştirilemedi. Tekrar dene.',
    'The name is saved. Press Save again to finish.':
        'Ad kaydedildi. Bitirmek için Kaydet’e tekrar dokun.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Bu görsel kullanılamıyor. JPG, PNG veya WebP dosyası seç.',
    "Couldn't upload the image. Check your connection and try again.":
        'Görsel yüklenemedi. Bağlantını kontrol edip tekrar dene.',
    'Editing is off right now': 'Düzenleme şu anda kapalı',
    'Editing comes back when Premium or VIP is active again.':
        'Premium veya VIP yeniden etkin olduğunda düzenleme geri gelir.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Bu sayfa moderasyon tarafından askıya alındı, bu yüzden düzenlenemez.',
    'Clear contact details': 'İletişim bilgilerini temizle',
    'Clear contact details?': 'İletişim bilgileri temizlensin mi?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Web sitesi, e-posta, telefon, adres, çalışma saatleri ve yasal bildirim sayfandan kaldırılacak. Bu işlem geri alınamaz.',
    'Contact details cleared': 'İletişim bilgileri temizlendi',
    'Cover, photo, name, description and everything visitors see':
        'Kapak, fotoğraf, ad, açıklama ve ziyaretçilerin gördüğü her şey',
  },
  'el': <String, String>{
    'pageEdit.appearance': 'Εμφάνιση',
    'pageEdit.name': 'Όνομα',
    'pageEdit.clear': 'Διαγραφή',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Το εξώφυλλο, η φωτογραφία και το όνομα της σελίδας σου είναι επίσης το εξώφυλλο, η φωτογραφία και το όνομα του λογαριασμού σου στις συνομιλίες και στους διακομιστές.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Μπορείς να αλλάζεις το όνομα μία φορά κάθε 30 ημέρες. Μετά από μια αλλαγή, η σελίδα δεν εμφανίζεται στην αναζήτηση για 7 ημέρες.',
    'You can change the name again on {date}.':
        'Θα μπορέσεις να αλλάξεις ξανά το όνομα στις {date}.',
    'The name must be 2 to 120 characters long.':
        'Το όνομα πρέπει να έχει από 2 έως 120 χαρακτήρες.',
    "The type can't be changed yet": 'Το είδος δεν μπορεί ακόμη να αλλάξει',
    'For example: be kind, no ads, only photos of your own work.':
        'Για παράδειγμα: σεβόμαστε ο ένας τον άλλον, χωρίς διαφημίσεις, μόνο φωτογραφίες δικών σου έργων.',
    'Change cover': 'Αλλαγή εξωφύλλου',
    'Change photo': 'Αλλαγή φωτογραφίας',
    'This is how others will see your Page. The preview changes as you type.':
        'Έτσι θα βλέπουν οι άλλοι τη σελίδα σου. Η προεπισκόπηση αλλάζει καθώς γράφεις.',
    'Hide preview': 'Απόκρυψη προεπισκόπησης',
    'Show preview': 'Εμφάνιση προεπισκόπησης',
    'You have unsaved changes': 'Έχεις μη αποθηκευμένες αλλαγές',
    'Save changes': 'Αποθήκευση αλλαγών',
    'Discard changes?': 'Απόρριψη αλλαγών;',
    "Your changes haven't been saved.": 'Οι αλλαγές σου δεν αποθηκεύτηκαν.',
    "Couldn't save the changes": 'Δεν ήταν δυνατή η αποθήκευση των αλλαγών',
    'Some changes were saved, but not all':
        'Κάποιες αλλαγές αποθηκεύτηκαν, αλλά όχι όλες',
    "Couldn't change the name. Try again.":
        'Δεν ήταν δυνατή η αλλαγή του ονόματος. Δοκίμασε ξανά.',
    'The name is saved. Press Save again to finish.':
        'Το όνομα αποθηκεύτηκε. Πάτησε ξανά Αποθήκευση για να ολοκληρώσεις.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Αυτή η εικόνα δεν μπορεί να χρησιμοποιηθεί. Επίλεξε αρχείο JPG, PNG ή WebP.',
    "Couldn't upload the image. Check your connection and try again.":
        'Δεν ήταν δυνατή η μεταφόρτωση της εικόνας. Έλεγξε τη σύνδεσή σου και δοκίμασε ξανά.',
    'Editing is off right now': 'Η επεξεργασία είναι προς το παρόν ανενεργή',
    'Editing comes back when Premium or VIP is active again.':
        'Η επεξεργασία θα επιστρέψει όταν το Premium ή το VIP είναι ξανά ενεργό.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Αυτή η σελίδα έχει ανασταλεί από τους συντονιστές, γι’ αυτό δεν μπορεί να γίνει επεξεργασία.',
    'Clear contact details': 'Διαγραφή στοιχείων επικοινωνίας',
    'Clear contact details?': 'Διαγραφή στοιχείων επικοινωνίας;',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Ο ιστότοπος, το e-mail, το τηλέφωνο, η διεύθυνση, το ωράριο και η νομική σημείωση θα αφαιρεθούν από τη σελίδα σου. Αυτό δεν αναιρείται.',
    'Contact details cleared': 'Τα στοιχεία επικοινωνίας διαγράφηκαν',
    'Cover, photo, name, description and everything visitors see':
        'Εξώφυλλο, φωτογραφία, όνομα, περιγραφή και ό,τι βλέπουν οι επισκέπτες',
  },
  'hu': <String, String>{
    'pageEdit.appearance': 'Megjelenés',
    'pageEdit.name': 'Név',
    'pageEdit.clear': 'Törlés',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Az oldalad borítója, fotója és neve egyben a fiókod borítója, fotója és neve is a csevegésekben és a szervereken.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'A nevet 30 naponta egyszer módosíthatod. Módosítás után az oldal 7 napig nem jelenik meg a keresésben.',
    'You can change the name again on {date}.':
        'A nevet legközelebb ekkor módosíthatod: {date}.',
    'The name must be 2 to 120 characters long.':
        'A névnek 2–120 karakter hosszúnak kell lennie.',
    "The type can't be changed yet": 'A típus egyelőre nem módosítható',
    'For example: be kind, no ads, only photos of your own work.':
        'Például: tiszteljük egymást, nincs reklám, csak saját munkákról készült fotók.',
    'Change cover': 'Borító módosítása',
    'Change photo': 'Fotó módosítása',
    'This is how others will see your Page. The preview changes as you type.':
        'Így látják majd mások az oldaladat. Az előnézet gépelés közben változik.',
    'Hide preview': 'Előnézet elrejtése',
    'Show preview': 'Előnézet megjelenítése',
    'You have unsaved changes': 'Nem mentett módosításaid vannak',
    'Save changes': 'Módosítások mentése',
    'Discard changes?': 'Elveted a módosításokat?',
    "Your changes haven't been saved.": 'A módosításaid nem lettek elmentve.',
    "Couldn't save the changes": 'Nem sikerült menteni a módosításokat',
    'Some changes were saved, but not all':
        'Néhány módosítás el lett mentve, de nem mind',
    "Couldn't change the name. Try again.":
        'Nem sikerült módosítani a nevet. Próbáld újra.',
    'The name is saved. Press Save again to finish.':
        'A név el van mentve. A befejezéshez koppints újra a Mentés gombra.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Ez a kép nem használható. Válassz JPG, PNG vagy WebP fájlt.',
    "Couldn't upload the image. Check your connection and try again.":
        'Nem sikerült feltölteni a képet. Ellenőrizd a kapcsolatot, és próbáld újra.',
    'Editing is off right now': 'A szerkesztés most ki van kapcsolva',
    'Editing comes back when Premium or VIP is active again.':
        'A szerkesztés visszatér, amint a Premium vagy a VIP újra aktív.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Ezt az oldalt a moderátorok felfüggesztették, ezért nem szerkeszthető.',
    'Clear contact details': 'Elérhetőségek törlése',
    'Clear contact details?': 'Törlöd az elérhetőségeket?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'A webhely, az e-mail, a telefonszám, a cím, a nyitvatartás és a jogi nyilatkozat lekerül az oldaladról. Ez nem vonható vissza.',
    'Contact details cleared': 'Elérhetőségek törölve',
    'Cover, photo, name, description and everything visitors see':
        'Borító, fotó, név, leírás és minden, amit a látogatók látnak',
  },
  'uk': <String, String>{
    'pageEdit.appearance': 'Вигляд',
    'pageEdit.name': 'Назва',
    'pageEdit.clear': 'Очистити',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Обкладинка, фото й назва вашої сторінки — це також обкладинка, фото й ім’я вашого облікового запису в чатах і на серверах.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Назву можна змінювати раз на 30 днів. Після зміни сторінка 7 днів не з’являється в пошуку.',
    'You can change the name again on {date}.':
        'Знову змінити назву можна буде {date}.',
    'The name must be 2 to 120 characters long.':
        'Назва має містити від 2 до 120 символів.',
    "The type can't be changed yet": 'Тип поки що не можна змінити',
    'For example: be kind, no ads, only photos of your own work.':
        'Наприклад: поважаємо одне одного, без реклами, лише фото власних робіт.',
    'Change cover': 'Змінити обкладинку',
    'Change photo': 'Змінити фото',
    'This is how others will see your Page. The preview changes as you type.':
        'Так вашу сторінку бачитимуть інші. Попередній перегляд змінюється, коли ви пишете.',
    'Hide preview': 'Згорнути попередній перегляд',
    'Show preview': 'Показати попередній перегляд',
    'You have unsaved changes': 'У вас є незбережені зміни',
    'Save changes': 'Зберегти зміни',
    'Discard changes?': 'Відхилити зміни?',
    "Your changes haven't been saved.": 'Ваші зміни не збережено.',
    "Couldn't save the changes": 'Не вдалося зберегти зміни',
    'Some changes were saved, but not all':
        'Частину змін збережено, але не всі',
    "Couldn't change the name. Try again.":
        'Не вдалося змінити назву. Спробуйте ще раз.',
    'The name is saved. Press Save again to finish.':
        'Назву збережено. Натисніть «Зберегти» ще раз, щоб завершити.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Не вдалося використати це зображення. Виберіть файл JPG, PNG або WebP.',
    "Couldn't upload the image. Check your connection and try again.":
        'Не вдалося завантажити зображення. Перевірте з’єднання та спробуйте ще раз.',
    'Editing is off right now': 'Редагування зараз вимкнено',
    'Editing comes back when Premium or VIP is active again.':
        'Редагування повернеться, коли Premium або VIP знову буде активним.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Цю сторінку призупинила модерація, тому її не можна редагувати.',
    'Clear contact details': 'Очистити контактні дані',
    'Clear contact details?': 'Очистити контактні дані?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Вебсайт, електронну пошту, телефон, адресу, години роботи та юридичну інформацію буде вилучено зі сторінки. Це не можна скасувати.',
    'Contact details cleared': 'Контактні дані очищено',
    'Cover, photo, name, description and everything visitors see':
        'Обкладинка, фото, назва, опис і все, що бачать відвідувачі',
  },
  'ru': <String, String>{
    'pageEdit.appearance': 'Внешний вид',
    'pageEdit.name': 'Название',
    'pageEdit.clear': 'Очистить',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Обложка, фото и название вашей страницы — это также обложка, фото и имя вашего аккаунта в чатах и на серверах.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Название можно менять раз в 30 дней. После изменения страница 7 дней не показывается в поиске.',
    'You can change the name again on {date}.':
        'Снова изменить название можно будет {date}.',
    'The name must be 2 to 120 characters long.':
        'Название должно содержать от 2 до 120 символов.',
    "The type can't be changed yet": 'Тип пока нельзя изменить',
    'For example: be kind, no ads, only photos of your own work.':
        'Например: уважаем друг друга, без рекламы, только фото своих работ.',
    'Change cover': 'Изменить обложку',
    'Change photo': 'Изменить фото',
    'This is how others will see your Page. The preview changes as you type.':
        'Так вашу страницу увидят другие. Предпросмотр меняется, когда вы пишете.',
    'Hide preview': 'Свернуть предпросмотр',
    'Show preview': 'Показать предпросмотр',
    'You have unsaved changes': 'У вас есть несохранённые изменения',
    'Save changes': 'Сохранить изменения',
    'Discard changes?': 'Отменить изменения?',
    "Your changes haven't been saved.": 'Ваши изменения не сохранены.',
    "Couldn't save the changes": 'Не удалось сохранить изменения',
    'Some changes were saved, but not all':
        'Часть изменений сохранена, но не все',
    "Couldn't change the name. Try again.":
        'Не удалось изменить название. Попробуйте ещё раз.',
    'The name is saved. Press Save again to finish.':
        'Название сохранено. Нажмите «Сохранить» ещё раз, чтобы завершить.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Не удалось использовать это изображение. Выберите файл JPG, PNG или WebP.',
    "Couldn't upload the image. Check your connection and try again.":
        'Не удалось загрузить изображение. Проверьте соединение и попробуйте ещё раз.',
    'Editing is off right now': 'Редактирование сейчас отключено',
    'Editing comes back when Premium or VIP is active again.':
        'Редактирование вернётся, когда Premium или VIP снова будет активен.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Эта страница приостановлена модерацией, поэтому её нельзя редактировать.',
    'Clear contact details': 'Очистить контактные данные',
    'Clear contact details?': 'Очистить контактные данные?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Сайт, электронная почта, телефон, адрес, часы работы и юридическая информация будут удалены со страницы. Это нельзя отменить.',
    'Contact details cleared': 'Контактные данные очищены',
    'Cover, photo, name, description and everything visitors see':
        'Обложка, фото, название, описание и всё, что видят посетители',
  },
  'cs': <String, String>{
    'pageEdit.appearance': 'Vzhled',
    'pageEdit.name': 'Název',
    'pageEdit.clear': 'Vymazat',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Úvodní obrázek, fotka a název tvé stránky jsou zároveň úvodním obrázkem, fotkou a jménem tvého účtu v chatech a na serverech.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Název můžeš změnit jednou za 30 dní. Po změně se stránka 7 dní nezobrazuje ve vyhledávání.',
    'You can change the name again on {date}.':
        'Název půjde znovu změnit {date}.',
    'The name must be 2 to 120 characters long.':
        'Název musí mít 2 až 120 znaků.',
    "The type can't be changed yet": 'Typ zatím nejde změnit',
    'For example: be kind, no ads, only photos of your own work.':
        'Například: respektujeme se, žádná reklama, jen fotky vlastních prací.',
    'Change cover': 'Změnit úvodní obrázek',
    'Change photo': 'Změnit fotku',
    'This is how others will see your Page. The preview changes as you type.':
        'Takhle uvidí tvou stránku ostatní. Náhled se mění, jak píšeš.',
    'Hide preview': 'Skrýt náhled',
    'Show preview': 'Zobrazit náhled',
    'You have unsaved changes': 'Máš neuložené změny',
    'Save changes': 'Uložit změny',
    'Discard changes?': 'Zahodit změny?',
    "Your changes haven't been saved.": 'Tvé změny nebyly uloženy.',
    "Couldn't save the changes": 'Změny se nepodařilo uložit',
    'Some changes were saved, but not all':
        'Některé změny se uložily, ale ne všechny',
    "Couldn't change the name. Try again.":
        'Název se nepodařilo změnit. Zkus to znovu.',
    'The name is saved. Press Save again to finish.':
        'Název je uložený. Dokonči to dalším klepnutím na Uložit.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Tento obrázek nejde použít. Vyber soubor JPG, PNG nebo WebP.',
    "Couldn't upload the image. Check your connection and try again.":
        'Obrázek se nepodařilo nahrát. Zkontroluj připojení a zkus to znovu.',
    'Editing is off right now': 'Úpravy jsou teď vypnuté',
    'Editing comes back when Premium or VIP is active again.':
        'Úpravy se vrátí, až bude Premium nebo VIP znovu aktivní.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Tuto stránku pozastavila moderace, proto ji nejde upravovat.',
    'Clear contact details': 'Vymazat kontaktní údaje',
    'Clear contact details?': 'Vymazat kontaktní údaje?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Web, e-mail, telefon, adresa, otevírací doba a právní informace budou ze stránky odstraněny. Tuto akci nejde vrátit.',
    'Contact details cleared': 'Kontaktní údaje vymazány',
    'Cover, photo, name, description and everything visitors see':
        'Úvodní obrázek, fotka, název, popis a vše, co vidí návštěvníci',
  },
  'sk': <String, String>{
    'pageEdit.appearance': 'Vzhľad',
    'pageEdit.name': 'Názov',
    'pageEdit.clear': 'Vymazať',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Titulný obrázok, fotka a názov tvojej stránky sú zároveň titulným obrázkom, fotkou a menom tvojho účtu v četoch a na serveroch.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Názov môžeš zmeniť raz za 30 dní. Po zmene sa stránka 7 dní nezobrazuje vo vyhľadávaní.',
    'You can change the name again on {date}.':
        'Názov bude možné znova zmeniť {date}.',
    'The name must be 2 to 120 characters long.':
        'Názov musí mať 2 až 120 znakov.',
    "The type can't be changed yet": 'Typ sa zatiaľ nedá zmeniť',
    'For example: be kind, no ads, only photos of your own work.':
        'Napríklad: rešpektujeme sa, žiadna reklama, iba fotky vlastných prác.',
    'Change cover': 'Zmeniť titulný obrázok',
    'Change photo': 'Zmeniť fotku',
    'This is how others will see your Page. The preview changes as you type.':
        'Takto uvidia tvoju stránku ostatní. Náhľad sa mení, ako píšeš.',
    'Hide preview': 'Skryť náhľad',
    'Show preview': 'Zobraziť náhľad',
    'You have unsaved changes': 'Máš neuložené zmeny',
    'Save changes': 'Uložiť zmeny',
    'Discard changes?': 'Zahodiť zmeny?',
    "Your changes haven't been saved.": 'Tvoje zmeny neboli uložené.',
    "Couldn't save the changes": 'Zmeny sa nepodarilo uložiť',
    'Some changes were saved, but not all':
        'Niektoré zmeny sa uložili, ale nie všetky',
    "Couldn't change the name. Try again.":
        'Názov sa nepodarilo zmeniť. Skús to znova.',
    'The name is saved. Press Save again to finish.':
        'Názov je uložený. Dokonči to ďalším ťuknutím na Uložiť.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Tento obrázok sa nedá použiť. Vyber súbor JPG, PNG alebo WebP.',
    "Couldn't upload the image. Check your connection and try again.":
        'Obrázok sa nepodarilo nahrať. Skontroluj pripojenie a skús to znova.',
    'Editing is off right now': 'Úpravy sú teraz vypnuté',
    'Editing comes back when Premium or VIP is active again.':
        'Úpravy sa vrátia, keď bude Premium alebo VIP znova aktívne.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Túto stránku pozastavila moderácia, preto sa nedá upravovať.',
    'Clear contact details': 'Vymazať kontaktné údaje',
    'Clear contact details?': 'Vymazať kontaktné údaje?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Web, e-mail, telefón, adresa, otváracie hodiny a právne informácie budú zo stránky odstránené. Túto akciu nie je možné vrátiť.',
    'Contact details cleared': 'Kontaktné údaje vymazané',
    'Cover, photo, name, description and everything visitors see':
        'Titulný obrázok, fotka, názov, popis a všetko, čo vidia návštevníci',
  },
  'bg': <String, String>{
    'pageEdit.appearance': 'Изглед',
    'pageEdit.name': 'Име',
    'pageEdit.clear': 'Изчисти',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Корицата, снимката и името на страницата ти са също корицата, снимката и името на профила ти в чатовете и сървърите.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Можеш да сменяш името веднъж на 30 дни. След промяна страницата не се показва в търсенето 7 дни.',
    'You can change the name again on {date}.':
        'Ще можеш да смениш името отново на {date}.',
    'The name must be 2 to 120 characters long.':
        'Името трябва да е от 2 до 120 знака.',
    "The type can't be changed yet": 'Видът още не може да се променя',
    'For example: be kind, no ads, only photos of your own work.':
        'Например: уважаваме се, без реклами, само снимки на собствени творби.',
    'Change cover': 'Смени корицата',
    'Change photo': 'Смени снимката',
    'This is how others will see your Page. The preview changes as you type.':
        'Така другите ще виждат страницата ти. Прегледът се променя, докато пишеш.',
    'Hide preview': 'Скрий прегледа',
    'Show preview': 'Покажи прегледа',
    'You have unsaved changes': 'Имаш незапазени промени',
    'Save changes': 'Запази промените',
    'Discard changes?': 'Отхвърляне на промените?',
    "Your changes haven't been saved.": 'Промените ти не са запазени.',
    "Couldn't save the changes": 'Промените не бяха запазени',
    'Some changes were saved, but not all':
        'Някои промени са запазени, но не всички',
    "Couldn't change the name. Try again.":
        'Името не беше сменено. Опитай отново.',
    'The name is saved. Press Save again to finish.':
        'Името е запазено. Натисни „Запази“ още веднъж, за да завършиш.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Това изображение не може да се използва. Избери файл JPG, PNG или WebP.',
    "Couldn't upload the image. Check your connection and try again.":
        'Изображението не беше качено. Провери връзката си и опитай отново.',
    'Editing is off right now': 'Редактирането в момента е изключено',
    'Editing comes back when Premium or VIP is active again.':
        'Редактирането ще се върне, когато Premium или VIP отново е активен.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Тази страница е спряна от модерацията, затова не може да се редактира.',
    'Clear contact details': 'Изчисти данните за контакт',
    'Clear contact details?': 'Изчистване на данните за контакт?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Уебсайтът, имейлът, телефонът, адресът, работното време и правната информация ще бъдат премахнати от страницата ти. Това не може да се отмени.',
    'Contact details cleared': 'Данните за контакт са изчистени',
    'Cover, photo, name, description and everything visitors see':
        'Корица, снимка, име, описание и всичко, което виждат посетителите',
  },
  'hr': <String, String>{
    'pageEdit.appearance': 'Izgled',
    'pageEdit.name': 'Naziv',
    'pageEdit.clear': 'Očisti',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Naslovna slika, fotografija i naziv tvoje stranice ujedno su naslovna slika, fotografija i ime tvog računa u razgovorima i na poslužiteljima.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Naziv možeš promijeniti jednom u 30 dana. Nakon promjene stranica se 7 dana ne prikazuje u pretraživanju.',
    'You can change the name again on {date}.':
        'Naziv ćeš ponovno moći promijeniti {date}.',
    'The name must be 2 to 120 characters long.':
        'Naziv mora imati od 2 do 120 znakova.',
    "The type can't be changed yet": 'Vrsta se još ne može promijeniti',
    'For example: be kind, no ads, only photos of your own work.':
        'Na primjer: poštujemo se, bez oglasa, samo fotografije vlastitih radova.',
    'Change cover': 'Promijeni naslovnu sliku',
    'Change photo': 'Promijeni fotografiju',
    'This is how others will see your Page. The preview changes as you type.':
        'Ovako će drugi vidjeti tvoju stranicu. Pregled se mijenja dok pišeš.',
    'Hide preview': 'Sakrij pregled',
    'Show preview': 'Prikaži pregled',
    'You have unsaved changes': 'Imaš nespremljene promjene',
    'Save changes': 'Spremi promjene',
    'Discard changes?': 'Odbaciti promjene?',
    "Your changes haven't been saved.": 'Tvoje promjene nisu spremljene.',
    "Couldn't save the changes": 'Promjene nisu spremljene',
    'Some changes were saved, but not all':
        'Neke su promjene spremljene, ali ne sve',
    "Couldn't change the name. Try again.":
        'Naziv nije promijenjen. Pokušaj ponovno.',
    'The name is saved. Press Save again to finish.':
        'Naziv je spremljen. Ponovno dodirni Spremi za dovršetak.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Ova se slika ne može upotrijebiti. Odaberi datoteku JPG, PNG ili WebP.',
    "Couldn't upload the image. Check your connection and try again.":
        'Slika nije prenesena. Provjeri vezu i pokušaj ponovno.',
    'Editing is off right now': 'Uređivanje je trenutačno isključeno',
    'Editing comes back when Premium or VIP is active again.':
        'Uređivanje se vraća kad Premium ili VIP ponovno bude aktivan.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Ovu je stranicu obustavila moderacija pa se ne može uređivati.',
    'Clear contact details': 'Očisti podatke za kontakt',
    'Clear contact details?': 'Očistiti podatke za kontakt?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Web-stranica, e-pošta, telefon, adresa, radno vrijeme i pravna napomena uklonit će se s tvoje stranice. To se ne može poništiti.',
    'Contact details cleared': 'Podaci za kontakt očišćeni',
    'Cover, photo, name, description and everything visitors see':
        'Naslovna slika, fotografija, naziv, opis i sve što vide posjetitelji',
  },
  'sr': <String, String>{
    'pageEdit.appearance': 'Изглед',
    'pageEdit.name': 'Назив',
    'pageEdit.clear': 'Обриши',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Насловна слика, фотографија и назив твоје странице уједно су насловна слика, фотографија и име твог налога у ћаскањима и на серверима.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Назив можеш да промениш једном у 30 дана. После промене страница се 7 дана не приказује у претрази.',
    'You can change the name again on {date}.':
        'Назив ћеш поново моћи да промениш {date}.',
    'The name must be 2 to 120 characters long.':
        'Назив мора да има од 2 до 120 знакова.',
    "The type can't be changed yet": 'Врста још не може да се промени',
    'For example: be kind, no ads, only photos of your own work.':
        'На пример: поштујемо се, без реклама, само фотографије сопствених радова.',
    'Change cover': 'Промени насловну слику',
    'Change photo': 'Промени фотографију',
    'This is how others will see your Page. The preview changes as you type.':
        'Овако ће други видети твоју страницу. Преглед се мења док пишеш.',
    'Hide preview': 'Сакриј преглед',
    'Show preview': 'Прикажи преглед',
    'You have unsaved changes': 'Имаш несачуване измене',
    'Save changes': 'Сачувај измене',
    'Discard changes?': 'Одбацити измене?',
    "Your changes haven't been saved.": 'Твоје измене нису сачуване.',
    "Couldn't save the changes": 'Измене нису сачуване',
    'Some changes were saved, but not all':
        'Неке измене су сачуване, али не све',
    "Couldn't change the name. Try again.":
        'Назив није промењен. Покушај поново.',
    'The name is saved. Press Save again to finish.':
        'Назив је сачуван. Поново додирни Сачувај да завршиш.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Ова слика не може да се користи. Изабери датотеку JPG, PNG или WebP.',
    "Couldn't upload the image. Check your connection and try again.":
        'Слика није отпремљена. Провери везу и покушај поново.',
    'Editing is off right now': 'Уређивање је тренутно искључено',
    'Editing comes back when Premium or VIP is active again.':
        'Уређивање се враћа када Premium или VIP поново буде активан.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Ову страницу је суспендовала модерација, па не може да се уређује.',
    'Clear contact details': 'Обриши податке за контакт',
    'Clear contact details?': 'Обрисати податке за контакт?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Веб-сајт, имејл, телефон, адреса, радно време и правна напомена биће уклоњени са твоје странице. Ово не може да се опозове.',
    'Contact details cleared': 'Подаци за контакт су обрисани',
    'Cover, photo, name, description and everything visitors see':
        'Насловна слика, фотографија, назив, опис и све што виде посетиоци',
  },
  'sv': <String, String>{
    'pageEdit.appearance': 'Utseende',
    'pageEdit.name': 'Namn',
    'pageEdit.clear': 'Rensa',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Omslaget, fotot och namnet på din sida är också omslaget, fotot och namnet på ditt konto i chattar och servrar.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Du kan ändra namnet en gång var 30:e dag. Efter en ändring syns sidan inte i sökningen på 7 dagar.',
    'You can change the name again on {date}.':
        'Du kan ändra namnet igen den {date}.',
    'The name must be 2 to 120 characters long.':
        'Namnet måste vara 2 till 120 tecken långt.',
    "The type can't be changed yet": 'Typen går inte att ändra än',
    'For example: be kind, no ads, only photos of your own work.':
        'Till exempel: var schyst, ingen reklam, bara foton på egna arbeten.',
    'Change cover': 'Byt omslag',
    'Change photo': 'Byt foto',
    'This is how others will see your Page. The preview changes as you type.':
        'Så här ser andra din sida. Förhandsvisningen ändras medan du skriver.',
    'Hide preview': 'Dölj förhandsvisning',
    'Show preview': 'Visa förhandsvisning',
    'You have unsaved changes': 'Du har ändringar som inte har sparats',
    'Save changes': 'Spara ändringar',
    'Discard changes?': 'Ignorera ändringarna?',
    "Your changes haven't been saved.": 'Dina ändringar har inte sparats.',
    "Couldn't save the changes": 'Det gick inte att spara ändringarna',
    'Some changes were saved, but not all':
        'Vissa ändringar sparades, men inte alla',
    "Couldn't change the name. Try again.":
        'Det gick inte att ändra namnet. Försök igen.',
    'The name is saved. Press Save again to finish.':
        'Namnet är sparat. Tryck på Spara igen för att slutföra.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Det går inte att använda den här bilden. Välj en JPG-, PNG- eller WebP-fil.',
    "Couldn't upload the image. Check your connection and try again.":
        'Det gick inte att ladda upp bilden. Kontrollera anslutningen och försök igen.',
    'Editing is off right now': 'Redigering är avstängd just nu',
    'Editing comes back when Premium or VIP is active again.':
        'Redigeringen kommer tillbaka när Premium eller VIP är aktivt igen.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Den här sidan har stängts av av moderatorerna och kan därför inte redigeras.',
    'Clear contact details': 'Rensa kontaktuppgifter',
    'Clear contact details?': 'Rensa kontaktuppgifterna?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Webbplats, e-post, telefon, adress, öppettider och juridisk information tas bort från din sida. Det går inte att ångra.',
    'Contact details cleared': 'Kontaktuppgifterna har rensats',
    'Cover, photo, name, description and everything visitors see':
        'Omslag, foto, namn, beskrivning och allt som besökare ser',
  },
  'da': <String, String>{
    'pageEdit.appearance': 'Udseende',
    'pageEdit.name': 'Navn',
    'pageEdit.clear': 'Ryd',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Coverbilledet, billedet og navnet på din side er også coverbilledet, billedet og navnet på din konto i chats og på servere.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Du kan ændre navnet én gang hver 30. dag. Efter en ændring vises siden ikke i søgningen i 7 dage.',
    'You can change the name again on {date}.':
        'Du kan ændre navnet igen den {date}.',
    'The name must be 2 to 120 characters long.':
        'Navnet skal være mellem 2 og 120 tegn.',
    "The type can't be changed yet": 'Typen kan ikke ændres endnu',
    'For example: be kind, no ads, only photos of your own work.':
        'For eksempel: tal pænt, ingen reklamer, kun billeder af egne værker.',
    'Change cover': 'Skift coverbillede',
    'Change photo': 'Skift billede',
    'This is how others will see your Page. The preview changes as you type.':
        'Sådan ser andre din side. Forhåndsvisningen ændrer sig, mens du skriver.',
    'Hide preview': 'Skjul forhåndsvisning',
    'Show preview': 'Vis forhåndsvisning',
    'You have unsaved changes': 'Du har ændringer, der ikke er gemt',
    'Save changes': 'Gem ændringer',
    'Discard changes?': 'Vil du kassere ændringerne?',
    "Your changes haven't been saved.": 'Dine ændringer er ikke gemt.',
    "Couldn't save the changes": 'Ændringerne kunne ikke gemmes',
    'Some changes were saved, but not all':
        'Nogle ændringer blev gemt, men ikke alle',
    "Couldn't change the name. Try again.":
        'Navnet kunne ikke ændres. Prøv igen.',
    'The name is saved. Press Save again to finish.':
        'Navnet er gemt. Tryk på Gem igen for at afslutte.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Dette billede kan ikke bruges. Vælg en JPG-, PNG- eller WebP-fil.',
    "Couldn't upload the image. Check your connection and try again.":
        'Billedet kunne ikke uploades. Tjek din forbindelse, og prøv igen.',
    'Editing is off right now': 'Redigering er slået fra lige nu',
    'Editing comes back when Premium or VIP is active again.':
        'Redigering vender tilbage, når Premium eller VIP er aktivt igen.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Denne side er suspenderet af moderatorerne og kan derfor ikke redigeres.',
    'Clear contact details': 'Ryd kontaktoplysninger',
    'Clear contact details?': 'Vil du rydde kontaktoplysningerne?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Websted, e-mail, telefon, adresse, åbningstider og juridiske oplysninger fjernes fra din side. Det kan ikke fortrydes.',
    'Contact details cleared': 'Kontaktoplysningerne er ryddet',
    'Cover, photo, name, description and everything visitors see':
        'Coverbillede, billede, navn, beskrivelse og alt det, besøgende ser',
  },
  'nb': <String, String>{
    'pageEdit.appearance': 'Utseende',
    'pageEdit.name': 'Navn',
    'pageEdit.clear': 'Tøm',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Forsidebildet, bildet og navnet på siden din er også forsidebildet, bildet og navnet på kontoen din i chatter og på servere.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Du kan endre navnet én gang hver 30. dag. Etter en endring vises ikke siden i søk på 7 dager.',
    'You can change the name again on {date}.':
        'Du kan endre navnet igjen {date}.',
    'The name must be 2 to 120 characters long.':
        'Navnet må være mellom 2 og 120 tegn.',
    "The type can't be changed yet": 'Typen kan ikke endres ennå',
    'For example: be kind, no ads, only photos of your own work.':
        'For eksempel: vær grei, ingen reklame, bare bilder av egne arbeider.',
    'Change cover': 'Bytt forsidebilde',
    'Change photo': 'Bytt bilde',
    'This is how others will see your Page. The preview changes as you type.':
        'Slik ser andre siden din. Forhåndsvisningen endres mens du skriver.',
    'Hide preview': 'Skjul forhåndsvisning',
    'Show preview': 'Vis forhåndsvisning',
    'You have unsaved changes': 'Du har endringer som ikke er lagret',
    'Save changes': 'Lagre endringer',
    'Discard changes?': 'Vil du forkaste endringene?',
    "Your changes haven't been saved.": 'Endringene dine er ikke lagret.',
    "Couldn't save the changes": 'Kunne ikke lagre endringene',
    'Some changes were saved, but not all':
        'Noen endringer ble lagret, men ikke alle',
    "Couldn't change the name. Try again.":
        'Kunne ikke endre navnet. Prøv igjen.',
    'The name is saved. Press Save again to finish.':
        'Navnet er lagret. Trykk på Lagre en gang til for å fullføre.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Dette bildet kan ikke brukes. Velg en JPG-, PNG- eller WebP-fil.',
    "Couldn't upload the image. Check your connection and try again.":
        'Kunne ikke laste opp bildet. Sjekk tilkoblingen og prøv igjen.',
    'Editing is off right now': 'Redigering er slått av akkurat nå',
    'Editing comes back when Premium or VIP is active again.':
        'Redigering kommer tilbake når Premium eller VIP er aktivt igjen.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Denne siden er suspendert av moderatorene og kan derfor ikke redigeres.',
    'Clear contact details': 'Tøm kontaktopplysninger',
    'Clear contact details?': 'Vil du tømme kontaktopplysningene?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Nettsted, e-post, telefon, adresse, åpningstider og juridisk informasjon fjernes fra siden din. Dette kan ikke angres.',
    'Contact details cleared': 'Kontaktopplysningene er tømt',
    'Cover, photo, name, description and everything visitors see':
        'Forsidebilde, bilde, navn, beskrivelse og alt besøkende ser',
  },
  'fi': <String, String>{
    'pageEdit.appearance': 'Ulkoasu',
    'pageEdit.name': 'Nimi',
    'pageEdit.clear': 'Tyhjennä',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Sivusi kansikuva, kuva ja nimi ovat myös tilisi kansikuva, kuva ja nimi keskusteluissa ja palvelimilla.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Voit vaihtaa nimen kerran 30 päivässä. Vaihdon jälkeen sivu ei näy haussa 7 päivään.',
    'You can change the name again on {date}.':
        'Voit vaihtaa nimen uudelleen {date}.',
    'The name must be 2 to 120 characters long.':
        'Nimen on oltava 2–120 merkkiä pitkä.',
    "The type can't be changed yet": 'Tyyppiä ei voi vielä vaihtaa',
    'For example: be kind, no ads, only photos of your own work.':
        'Esimerkiksi: ollaan reiluja, ei mainoksia, vain kuvia omista töistä.',
    'Change cover': 'Vaihda kansikuva',
    'Change photo': 'Vaihda kuva',
    'This is how others will see your Page. The preview changes as you type.':
        'Näin muut näkevät sivusi. Esikatselu muuttuu kirjoittaessasi.',
    'Hide preview': 'Piilota esikatselu',
    'Show preview': 'Näytä esikatselu',
    'You have unsaved changes': 'Sinulla on tallentamattomia muutoksia',
    'Save changes': 'Tallenna muutokset',
    'Discard changes?': 'Hylätäänkö muutokset?',
    "Your changes haven't been saved.": 'Muutoksiasi ei ole tallennettu.',
    "Couldn't save the changes": 'Muutosten tallentaminen epäonnistui',
    'Some changes were saved, but not all':
        'Osa muutoksista tallennettiin, mutta ei kaikkia',
    "Couldn't change the name. Try again.":
        'Nimen vaihtaminen epäonnistui. Yritä uudelleen.',
    'The name is saved. Press Save again to finish.':
        'Nimi on tallennettu. Viimeistele napauttamalla Tallenna uudelleen.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Tätä kuvaa ei voi käyttää. Valitse JPG-, PNG- tai WebP-tiedosto.',
    "Couldn't upload the image. Check your connection and try again.":
        'Kuvan lataaminen epäonnistui. Tarkista yhteys ja yritä uudelleen.',
    'Editing is off right now': 'Muokkaus on nyt pois käytöstä',
    'Editing comes back when Premium or VIP is active again.':
        'Muokkaus palaa, kun Premium tai VIP on taas aktiivinen.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Moderointi on jäädyttänyt tämän sivun, joten sitä ei voi muokata.',
    'Clear contact details': 'Tyhjennä yhteystiedot',
    'Clear contact details?': 'Tyhjennetäänkö yhteystiedot?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Verkkosivusto, sähköposti, puhelin, osoite, aukioloajat ja oikeudellinen ilmoitus poistetaan sivultasi. Tätä ei voi kumota.',
    'Contact details cleared': 'Yhteystiedot tyhjennetty',
    'Cover, photo, name, description and everything visitors see':
        'Kansikuva, kuva, nimi, kuvaus ja kaikki, mitä kävijät näkevät',
  },
  'lt': <String, String>{
    'pageEdit.appearance': 'Išvaizda',
    'pageEdit.name': 'Pavadinimas',
    'pageEdit.clear': 'Išvalyti',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Tavo puslapio viršelis, nuotrauka ir pavadinimas kartu yra ir tavo paskyros viršelis, nuotrauka ir vardas pokalbiuose bei serveriuose.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Pavadinimą gali keisti kartą per 30 dienų. Po pakeitimo puslapis 7 dienas nerodomas paieškoje.',
    'You can change the name again on {date}.':
        'Pavadinimą vėl galėsi pakeisti {date}.',
    'The name must be 2 to 120 characters long.':
        'Pavadinimas turi būti nuo 2 iki 120 simbolių.',
    "The type can't be changed yet": 'Tipo kol kas keisti negalima',
    'For example: be kind, no ads, only photos of your own work.':
        'Pavyzdžiui: gerbiame vieni kitus, jokios reklamos, tik savo darbų nuotraukos.',
    'Change cover': 'Keisti viršelį',
    'Change photo': 'Keisti nuotrauką',
    'This is how others will see your Page. The preview changes as you type.':
        'Taip tavo puslapį matys kiti. Peržiūra keičiasi, kai rašai.',
    'Hide preview': 'Slėpti peržiūrą',
    'Show preview': 'Rodyti peržiūrą',
    'You have unsaved changes': 'Turi neišsaugotų pakeitimų',
    'Save changes': 'Išsaugoti pakeitimus',
    'Discard changes?': 'Atmesti pakeitimus?',
    "Your changes haven't been saved.": 'Tavo pakeitimai neišsaugoti.',
    "Couldn't save the changes": 'Nepavyko išsaugoti pakeitimų',
    'Some changes were saved, but not all':
        'Dalis pakeitimų išsaugota, bet ne visi',
    "Couldn't change the name. Try again.":
        'Nepavyko pakeisti pavadinimo. Bandyk dar kartą.',
    'The name is saved. Press Save again to finish.':
        'Pavadinimas išsaugotas. Kad užbaigtum, dar kartą paspausk „Išsaugoti“.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Šio paveikslėlio naudoti negalima. Pasirink JPG, PNG arba WebP failą.',
    "Couldn't upload the image. Check your connection and try again.":
        'Nepavyko įkelti paveikslėlio. Patikrink ryšį ir bandyk dar kartą.',
    'Editing is off right now': 'Redagavimas šiuo metu išjungtas',
    'Editing comes back when Premium or VIP is active again.':
        'Redagavimas grįš, kai Premium arba VIP vėl bus aktyvus.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Šį puslapį sustabdė moderatoriai, todėl jo redaguoti negalima.',
    'Clear contact details': 'Išvalyti kontaktinius duomenis',
    'Clear contact details?': 'Išvalyti kontaktinius duomenis?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Svetainė, el. paštas, telefonas, adresas, darbo laikas ir teisinė informacija bus pašalinti iš tavo puslapio. Šio veiksmo anuliuoti negalima.',
    'Contact details cleared': 'Kontaktiniai duomenys išvalyti',
    'Cover, photo, name, description and everything visitors see':
        'Viršelis, nuotrauka, pavadinimas, aprašymas ir viskas, ką mato lankytojai',
  },
  'lv': <String, String>{
    'pageEdit.appearance': 'Izskats',
    'pageEdit.name': 'Nosaukums',
    'pageEdit.clear': 'Notīrīt',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Tavas lapas vāka attēls, fotoattēls un nosaukums ir arī tava konta vāka attēls, fotoattēls un vārds tērzēšanā un serveros.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Nosaukumu vari mainīt reizi 30 dienās. Pēc maiņas lapa 7 dienas netiek rādīta meklēšanā.',
    'You can change the name again on {date}.':
        'Nosaukumu atkal varēsi mainīt {date}.',
    'The name must be 2 to 120 characters long.':
        'Nosaukumam jābūt 2 līdz 120 rakstzīmes garam.',
    "The type can't be changed yet": 'Veidu pagaidām nevar mainīt',
    'For example: be kind, no ads, only photos of your own work.':
        'Piemēram: cienām cits citu, bez reklāmām, tikai savu darbu fotoattēli.',
    'Change cover': 'Mainīt vāka attēlu',
    'Change photo': 'Mainīt fotoattēlu',
    'This is how others will see your Page. The preview changes as you type.':
        'Šādi tavu lapu redzēs citi. Priekšskatījums mainās, kamēr raksti.',
    'Hide preview': 'Paslēpt priekšskatījumu',
    'Show preview': 'Rādīt priekšskatījumu',
    'You have unsaved changes': 'Tev ir nesaglabātas izmaiņas',
    'Save changes': 'Saglabāt izmaiņas',
    'Discard changes?': 'Vai atmest izmaiņas?',
    "Your changes haven't been saved.": 'Tavas izmaiņas nav saglabātas.',
    "Couldn't save the changes": 'Neizdevās saglabāt izmaiņas',
    'Some changes were saved, but not all':
        'Daļa izmaiņu ir saglabāta, bet ne visas',
    "Couldn't change the name. Try again.":
        'Neizdevās mainīt nosaukumu. Mēģini vēlreiz.',
    'The name is saved. Press Save again to finish.':
        'Nosaukums ir saglabāts. Lai pabeigtu, vēlreiz nospied “Saglabāt”.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Šo attēlu nevar izmantot. Izvēlies JPG, PNG vai WebP failu.',
    "Couldn't upload the image. Check your connection and try again.":
        'Neizdevās augšupielādēt attēlu. Pārbaudi savienojumu un mēģini vēlreiz.',
    'Editing is off right now': 'Rediģēšana pašlaik ir izslēgta',
    'Editing comes back when Premium or VIP is active again.':
        'Rediģēšana atgriezīsies, kad Premium vai VIP atkal būs aktīvs.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Šo lapu ir apturējusi moderācija, tāpēc to nevar rediģēt.',
    'Clear contact details': 'Notīrīt kontaktinformāciju',
    'Clear contact details?': 'Vai notīrīt kontaktinformāciju?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Vietne, e-pasts, tālrunis, adrese, darba laiks un juridiskā informācija tiks noņemti no tavas lapas. To nevar atsaukt.',
    'Contact details cleared': 'Kontaktinformācija notīrīta',
    'Cover, photo, name, description and everything visitors see':
        'Vāka attēls, fotoattēls, nosaukums, apraksts un viss, ko redz apmeklētāji',
  },
  'et': <String, String>{
    'pageEdit.appearance': 'Välimus',
    'pageEdit.name': 'Nimi',
    'pageEdit.clear': 'Tühjenda',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Sinu lehe kaanepilt, foto ja nimi on ühtlasi sinu konto kaanepilt, foto ja nimi vestlustes ja serverites.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Nime saad muuta kord 30 päeva jooksul. Pärast muutmist ei kuvata lehte 7 päeva otsingus.',
    'You can change the name again on {date}.':
        'Nime saad uuesti muuta {date}.',
    'The name must be 2 to 120 characters long.':
        'Nimi peab olema 2–120 tähemärki pikk.',
    "The type can't be changed yet": 'Tüüpi ei saa veel muuta',
    'For example: be kind, no ads, only photos of your own work.':
        'Näiteks: austame üksteist, reklaami ei tee, ainult fotod enda töödest.',
    'Change cover': 'Muuda kaanepilti',
    'Change photo': 'Muuda fotot',
    'This is how others will see your Page. The preview changes as you type.':
        'Nii näevad teised sinu lehte. Eelvaade muutub kirjutamise ajal.',
    'Hide preview': 'Peida eelvaade',
    'Show preview': 'Kuva eelvaade',
    'You have unsaved changes': 'Sul on salvestamata muudatusi',
    'Save changes': 'Salvesta muudatused',
    'Discard changes?': 'Kas loobuda muudatustest?',
    "Your changes haven't been saved.": 'Sinu muudatusi ei salvestatud.',
    "Couldn't save the changes": 'Muudatusi ei õnnestunud salvestada',
    'Some changes were saved, but not all':
        'Osa muudatusi salvestati, kuid mitte kõik',
    "Couldn't change the name. Try again.":
        'Nime ei õnnestunud muuta. Proovi uuesti.',
    'The name is saved. Press Save again to finish.':
        'Nimi on salvestatud. Lõpetamiseks puuduta uuesti nuppu Salvesta.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Seda pilti ei saa kasutada. Vali JPG-, PNG- või WebP-fail.',
    "Couldn't upload the image. Check your connection and try again.":
        'Pilti ei õnnestunud üles laadida. Kontrolli ühendust ja proovi uuesti.',
    'Editing is off right now': 'Muutmine on praegu välja lülitatud',
    'Editing comes back when Premium or VIP is active again.':
        'Muutmine tuleb tagasi, kui Premium või VIP on taas aktiivne.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Modereerijad on selle lehe peatanud, seega ei saa seda muuta.',
    'Clear contact details': 'Tühjenda kontaktandmed',
    'Clear contact details?': 'Kas tühjendada kontaktandmed?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Veebileht, e-post, telefon, aadress, lahtiolekuajad ja juriidiline teave eemaldatakse sinu lehelt. Seda ei saa tagasi võtta.',
    'Contact details cleared': 'Kontaktandmed tühjendatud',
    'Cover, photo, name, description and everything visitors see':
        'Kaanepilt, foto, nimi, kirjeldus ja kõik, mida külastajad näevad',
  },
  'id': <String, String>{
    'pageEdit.appearance': 'Tampilan',
    'pageEdit.name': 'Nama',
    'pageEdit.clear': 'Hapus',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Sampul, foto, dan nama halamanmu juga merupakan sampul, foto, dan nama akunmu di chat dan server.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Kamu bisa mengubah nama sekali setiap 30 hari. Setelah diubah, halaman tidak muncul di pencarian selama 7 hari.',
    'You can change the name again on {date}.':
        'Kamu bisa mengubah nama lagi pada {date}.',
    'The name must be 2 to 120 characters long.':
        'Nama harus terdiri dari 2 hingga 120 karakter.',
    "The type can't be changed yet": 'Jenis belum bisa diubah',
    'For example: be kind, no ads, only photos of your own work.':
        'Misalnya: saling menghormati, tanpa iklan, hanya foto karya sendiri.',
    'Change cover': 'Ganti sampul',
    'Change photo': 'Ganti foto',
    'This is how others will see your Page. The preview changes as you type.':
        'Beginilah orang lain akan melihat halamanmu. Pratinjau berubah saat kamu mengetik.',
    'Hide preview': 'Sembunyikan pratinjau',
    'Show preview': 'Tampilkan pratinjau',
    'You have unsaved changes': 'Ada perubahan yang belum disimpan',
    'Save changes': 'Simpan perubahan',
    'Discard changes?': 'Buang perubahan?',
    "Your changes haven't been saved.": 'Perubahanmu belum disimpan.',
    "Couldn't save the changes": 'Perubahan tidak dapat disimpan',
    'Some changes were saved, but not all':
        'Sebagian perubahan tersimpan, tetapi tidak semuanya',
    "Couldn't change the name. Try again.":
        'Nama tidak dapat diubah. Coba lagi.',
    'The name is saved. Press Save again to finish.':
        'Nama sudah disimpan. Ketuk Simpan sekali lagi untuk menyelesaikan.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Gambar ini tidak dapat digunakan. Pilih file JPG, PNG, atau WebP.',
    "Couldn't upload the image. Check your connection and try again.":
        'Gambar tidak dapat diunggah. Periksa koneksimu lalu coba lagi.',
    'Editing is off right now': 'Pengeditan sedang tidak aktif',
    'Editing comes back when Premium or VIP is active again.':
        'Pengeditan kembali saat Premium atau VIP aktif lagi.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Halaman ini ditangguhkan oleh moderasi sehingga tidak dapat diedit.',
    'Clear contact details': 'Hapus detail kontak',
    'Clear contact details?': 'Hapus detail kontak?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Situs web, email, telepon, alamat, jam buka, dan pemberitahuan hukum akan dihapus dari halamanmu. Tindakan ini tidak dapat dibatalkan.',
    'Contact details cleared': 'Detail kontak dihapus',
    'Cover, photo, name, description and everything visitors see':
        'Sampul, foto, nama, deskripsi, dan semua yang dilihat pengunjung',
  },
  'vi': <String, String>{
    'pageEdit.appearance': 'Giao diện',
    'pageEdit.name': 'Tên',
    'pageEdit.clear': 'Xóa',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Ảnh bìa, ảnh và tên trang của bạn cũng là ảnh bìa, ảnh và tên tài khoản của bạn trong các cuộc trò chuyện và máy chủ.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Bạn có thể đổi tên một lần mỗi 30 ngày. Sau khi đổi, trang sẽ không xuất hiện trong tìm kiếm trong 7 ngày.',
    'You can change the name again on {date}.':
        'Bạn có thể đổi tên lại vào {date}.',
    'The name must be 2 to 120 characters long.':
        'Tên phải dài từ 2 đến 120 ký tự.',
    "The type can't be changed yet": 'Chưa thể thay đổi loại trang',
    'For example: be kind, no ads, only photos of your own work.':
        'Ví dụ: tôn trọng nhau, không quảng cáo, chỉ đăng ảnh tác phẩm của chính mình.',
    'Change cover': 'Đổi ảnh bìa',
    'Change photo': 'Đổi ảnh',
    'This is how others will see your Page. The preview changes as you type.':
        'Người khác sẽ thấy trang của bạn như thế này. Bản xem trước thay đổi khi bạn nhập.',
    'Hide preview': 'Ẩn bản xem trước',
    'Show preview': 'Hiện bản xem trước',
    'You have unsaved changes': 'Bạn có thay đổi chưa lưu',
    'Save changes': 'Lưu thay đổi',
    'Discard changes?': 'Hủy bỏ các thay đổi?',
    "Your changes haven't been saved.": 'Các thay đổi của bạn chưa được lưu.',
    "Couldn't save the changes": 'Không thể lưu các thay đổi',
    'Some changes were saved, but not all':
        'Một số thay đổi đã được lưu, nhưng chưa phải tất cả',
    "Couldn't change the name. Try again.": 'Không thể đổi tên. Hãy thử lại.',
    'The name is saved. Press Save again to finish.':
        'Tên đã được lưu. Nhấn Lưu lần nữa để hoàn tất.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Không thể dùng hình ảnh này. Hãy chọn tệp JPG, PNG hoặc WebP.',
    "Couldn't upload the image. Check your connection and try again.":
        'Không thể tải hình ảnh lên. Hãy kiểm tra kết nối và thử lại.',
    'Editing is off right now': 'Hiện không thể chỉnh sửa',
    'Editing comes back when Premium or VIP is active again.':
        'Bạn có thể chỉnh sửa lại khi Premium hoặc VIP hoạt động trở lại.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Trang này đã bị bộ phận kiểm duyệt đình chỉ nên không thể chỉnh sửa.',
    'Clear contact details': 'Xóa thông tin liên hệ',
    'Clear contact details?': 'Xóa thông tin liên hệ?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Trang web, email, điện thoại, địa chỉ, giờ mở cửa và thông báo pháp lý sẽ bị gỡ khỏi trang của bạn. Không thể hoàn tác thao tác này.',
    'Contact details cleared': 'Đã xóa thông tin liên hệ',
    'Cover, photo, name, description and everything visitors see':
        'Ảnh bìa, ảnh, tên, mô tả và mọi thứ khách truy cập nhìn thấy',
  },
  'zh_CN': <String, String>{
    'pageEdit.appearance': '外观',
    'pageEdit.name': '名称',
    'pageEdit.clear': '清除',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        '主页的封面、头像和名称，也是你的账号在聊天和服务器中的封面、头像和名称。',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        '名称每 30 天可以更改一次。更改后，主页在 7 天内不会出现在搜索中。',
    'You can change the name again on {date}.': '你可以在 {date} 再次更改名称。',
    'The name must be 2 to 120 characters long.': '名称长度必须为 2 到 120 个字符。',
    "The type can't be changed yet": '类型暂时无法更改',
    'For example: be kind, no ads, only photos of your own work.':
        '例如：互相尊重、不发广告、只发自己作品的照片。',
    'Change cover': '更换封面',
    'Change photo': '更换头像',
    'This is how others will see your Page. The preview changes as you type.':
        '其他人会这样看到你的主页。预览会随你的输入而变化。',
    'Hide preview': '收起预览',
    'Show preview': '展开预览',
    'You have unsaved changes': '你有未保存的更改',
    'Save changes': '保存更改',
    'Discard changes?': '放弃更改？',
    "Your changes haven't been saved.": '你的更改尚未保存。',
    "Couldn't save the changes": '无法保存更改',
    'Some changes were saved, but not all': '部分更改已保存，但并非全部',
    "Couldn't change the name. Try again.": '无法更改名称。请重试。',
    'The name is saved. Press Save again to finish.': '名称已保存。请再次点按“保存”以完成。',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        '无法使用这张图片。请选择 JPG、PNG 或 WebP 文件。',
    "Couldn't upload the image. Check your connection and try again.":
        '无法上传图片。请检查网络连接后重试。',
    'Editing is off right now': '目前无法编辑',
    'Editing comes back when Premium or VIP is active again.':
        'Premium 或 VIP 重新生效后即可恢复编辑。',
    "This Page is suspended by moderation, so it can't be edited.":
        '此主页已被管理团队停用，因此无法编辑。',
    'Clear contact details': '清除联系方式',
    'Clear contact details?': '清除联系方式？',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        '网站、电子邮箱、电话、地址、营业时间和法律声明将从你的主页移除。此操作无法撤销。',
    'Contact details cleared': '联系方式已清除',
    'Cover, photo, name, description and everything visitors see':
        '封面、头像、名称、简介以及访客看到的一切',
  },
  'zh_TW': <String, String>{
    'pageEdit.appearance': '外觀',
    'pageEdit.name': '名稱',
    'pageEdit.clear': '清除',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        '專頁的封面、相片和名稱，也是你的帳號在聊天和伺服器中的封面、相片和名稱。',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        '名稱每 30 天可以變更一次。變更後，專頁在 7 天內不會出現在搜尋中。',
    'You can change the name again on {date}.': '你可以在 {date} 再次變更名稱。',
    'The name must be 2 to 120 characters long.': '名稱長度必須為 2 到 120 個字元。',
    "The type can't be changed yet": '類型暫時無法變更',
    'For example: be kind, no ads, only photos of your own work.':
        '例如：互相尊重、不貼廣告、只貼自己作品的相片。',
    'Change cover': '更換封面',
    'Change photo': '更換相片',
    'This is how others will see your Page. The preview changes as you type.':
        '其他人會這樣看到你的專頁。預覽會隨著你的輸入而變化。',
    'Hide preview': '收合預覽',
    'Show preview': '展開預覽',
    'You have unsaved changes': '你有尚未儲存的變更',
    'Save changes': '儲存變更',
    'Discard changes?': '要捨棄變更嗎？',
    "Your changes haven't been saved.": '你的變更尚未儲存。',
    "Couldn't save the changes": '無法儲存變更',
    'Some changes were saved, but not all': '部分變更已儲存，但不是全部',
    "Couldn't change the name. Try again.": '無法變更名稱。請再試一次。',
    'The name is saved. Press Save again to finish.': '名稱已儲存。請再按一次「儲存」以完成。',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        '無法使用這張圖片。請選擇 JPG、PNG 或 WebP 檔案。',
    "Couldn't upload the image. Check your connection and try again.":
        '無法上傳圖片。請檢查連線後再試一次。',
    'Editing is off right now': '目前無法編輯',
    'Editing comes back when Premium or VIP is active again.':
        'Premium 或 VIP 重新生效後即可恢復編輯。',
    "This Page is suspended by moderation, so it can't be edited.":
        '此專頁已被管理團隊停權，因此無法編輯。',
    'Clear contact details': '清除聯絡資訊',
    'Clear contact details?': '要清除聯絡資訊嗎？',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        '網站、電子郵件、電話、地址、營業時間和法律聲明將從你的專頁移除。此動作無法復原。',
    'Contact details cleared': '聯絡資訊已清除',
    'Cover, photo, name, description and everything visitors see':
        '封面、相片、名稱、簡介，以及訪客看到的一切',
  },
  'ja': <String, String>{
    'pageEdit.appearance': '外観',
    'pageEdit.name': '名前',
    'pageEdit.clear': '消去',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'ページのカバー画像、写真、名前は、チャットやサーバーでのあなたのアカウントのカバー画像、写真、名前でもあります。',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        '名前は30日に1回変更できます。変更後7日間、ページは検索に表示されません。',
    'You can change the name again on {date}.': '名前は{date}に再び変更できます。',
    'The name must be 2 to 120 characters long.': '名前は2〜120文字で入力してください。',
    "The type can't be changed yet": '種類はまだ変更できません',
    'For example: be kind, no ads, only photos of your own work.':
        '例：お互いを尊重する、広告は禁止、自分の作品の写真のみ。',
    'Change cover': 'カバー画像を変更',
    'Change photo': '写真を変更',
    'This is how others will see your Page. The preview changes as you type.':
        'ほかの人にはページがこのように表示されます。入力に合わせてプレビューが変わります。',
    'Hide preview': 'プレビューを隠す',
    'Show preview': 'プレビューを表示',
    'You have unsaved changes': '保存していない変更があります',
    'Save changes': '変更を保存',
    'Discard changes?': '変更を破棄しますか？',
    "Your changes haven't been saved.": '変更は保存されていません。',
    "Couldn't save the changes": '変更を保存できませんでした',
    'Some changes were saved, but not all': '一部の変更は保存されましたが、すべてではありません',
    "Couldn't change the name. Try again.": '名前を変更できませんでした。もう一度お試しください。',
    'The name is saved. Press Save again to finish.':
        '名前は保存されました。完了するにはもう一度「保存」をタップしてください。',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'この画像は使用できません。JPG、PNG、WebPのいずれかのファイルを選んでください。',
    "Couldn't upload the image. Check your connection and try again.":
        '画像をアップロードできませんでした。接続を確認して、もう一度お試しください。',
    'Editing is off right now': '現在は編集できません',
    'Editing comes back when Premium or VIP is active again.':
        'PremiumまたはVIPが再び有効になると編集できるようになります。',
    "This Page is suspended by moderation, so it can't be edited.":
        'このページはモデレーションにより停止されているため、編集できません。',
    'Clear contact details': '連絡先情報を消去',
    'Clear contact details?': '連絡先情報を消去しますか？',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'ウェブサイト、メール、電話、住所、営業時間、法的表示がページから削除されます。この操作は取り消せません。',
    'Contact details cleared': '連絡先情報を消去しました',
    'Cover, photo, name, description and everything visitors see':
        'カバー画像、写真、名前、説明など、訪問者に表示されるすべて',
  },
  'ko': <String, String>{
    'pageEdit.appearance': '모양',
    'pageEdit.name': '이름',
    'pageEdit.clear': '지우기',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        '페이지의 커버, 사진, 이름은 채팅과 서버에서 사용하는 내 계정의 커버, 사진, 이름이기도 합니다.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        '이름은 30일에 한 번 변경할 수 있습니다. 변경 후 7일 동안 페이지가 검색에 표시되지 않습니다.',
    'You can change the name again on {date}.': '{date}에 이름을 다시 변경할 수 있습니다.',
    'The name must be 2 to 120 characters long.': '이름은 2~120자여야 합니다.',
    "The type can't be changed yet": '유형은 아직 변경할 수 없습니다',
    'For example: be kind, no ads, only photos of your own work.':
        '예: 서로 존중하기, 광고 금지, 직접 만든 작품 사진만 올리기.',
    'Change cover': '커버 변경',
    'Change photo': '사진 변경',
    'This is how others will see your Page. The preview changes as you type.':
        '다른 사람에게 페이지가 이렇게 보입니다. 입력하는 대로 미리보기가 바뀝니다.',
    'Hide preview': '미리보기 숨기기',
    'Show preview': '미리보기 표시',
    'You have unsaved changes': '저장하지 않은 변경 사항이 있습니다',
    'Save changes': '변경 사항 저장',
    'Discard changes?': '변경 사항을 버릴까요?',
    "Your changes haven't been saved.": '변경 사항이 저장되지 않았습니다.',
    "Couldn't save the changes": '변경 사항을 저장하지 못했습니다',
    'Some changes were saved, but not all': '일부 변경 사항만 저장되었습니다',
    "Couldn't change the name. Try again.": '이름을 변경하지 못했습니다. 다시 시도하세요.',
    'The name is saved. Press Save again to finish.':
        '이름이 저장되었습니다. 완료하려면 저장을 한 번 더 누르세요.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        '이 이미지는 사용할 수 없습니다. JPG, PNG 또는 WebP 파일을 선택하세요.',
    "Couldn't upload the image. Check your connection and try again.":
        '이미지를 업로드하지 못했습니다. 연결을 확인하고 다시 시도하세요.',
    'Editing is off right now': '지금은 편집할 수 없습니다',
    'Editing comes back when Premium or VIP is active again.':
        'Premium 또는 VIP가 다시 활성화되면 편집할 수 있습니다.',
    "This Page is suspended by moderation, so it can't be edited.":
        '이 페이지는 운영팀에 의해 정지되어 편집할 수 없습니다.',
    'Clear contact details': '연락처 정보 지우기',
    'Clear contact details?': '연락처 정보를 지울까요?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        '웹사이트, 이메일, 전화번호, 주소, 영업시간, 법적 고지가 페이지에서 삭제됩니다. 이 작업은 되돌릴 수 없습니다.',
    'Contact details cleared': '연락처 정보를 지웠습니다',
    'Cover, photo, name, description and everything visitors see':
        '커버, 사진, 이름, 설명 등 방문자에게 보이는 모든 것',
  },
  'ar': <String, String>{
    'pageEdit.appearance': 'المظهر',
    'pageEdit.name': 'الاسم',
    'pageEdit.clear': 'مسح',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'غلاف صفحتك وصورتها واسمها هي أيضًا غلاف حسابك وصورته واسمه في المحادثات والخوادم.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'يمكنك تغيير الاسم مرة واحدة كل 30 يومًا. بعد التغيير لا تظهر الصفحة في البحث لمدة 7 أيام.',
    'You can change the name again on {date}.':
        'يمكنك تغيير الاسم مجددًا في {date}.',
    'The name must be 2 to 120 characters long.':
        'يجب أن يتكوّن الاسم من 2 إلى 120 حرفًا.',
    "The type can't be changed yet": 'لا يمكن تغيير النوع حاليًا',
    'For example: be kind, no ads, only photos of your own work.':
        'مثلًا: نحترم بعضنا، بلا إعلانات، صور لأعمالك الخاصة فقط.',
    'Change cover': 'تغيير الغلاف',
    'Change photo': 'تغيير الصورة',
    'This is how others will see your Page. The preview changes as you type.':
        'هكذا سيرى الآخرون صفحتك. تتغيّر المعاينة أثناء الكتابة.',
    'Hide preview': 'إخفاء المعاينة',
    'Show preview': 'إظهار المعاينة',
    'You have unsaved changes': 'لديك تغييرات غير محفوظة',
    'Save changes': 'حفظ التغييرات',
    'Discard changes?': 'هل تريد تجاهل التغييرات؟',
    "Your changes haven't been saved.": 'لم تُحفظ تغييراتك.',
    "Couldn't save the changes": 'تعذّر حفظ التغييرات',
    'Some changes were saved, but not all': 'حُفظت بعض التغييرات وليس كلها',
    "Couldn't change the name. Try again.": 'تعذّر تغيير الاسم. حاول مرة أخرى.',
    'The name is saved. Press Save again to finish.':
        'تم حفظ الاسم. اضغط على «حفظ» مرة أخرى للإنهاء.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'تعذّر استخدام هذه الصورة. اختر ملف JPG أو PNG أو WebP.',
    "Couldn't upload the image. Check your connection and try again.":
        'تعذّر رفع الصورة. تحقّق من اتصالك وحاول مرة أخرى.',
    'Editing is off right now': 'التعديل متوقف حاليًا',
    'Editing comes back when Premium or VIP is active again.':
        'يعود التعديل عندما يصبح Premium أو VIP نشطًا من جديد.',
    "This Page is suspended by moderation, so it can't be edited.":
        'تم تعليق هذه الصفحة من قِبل الإشراف، لذلك لا يمكن تعديلها.',
    'Clear contact details': 'مسح بيانات التواصل',
    'Clear contact details?': 'هل تريد مسح بيانات التواصل؟',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'سيُزال الموقع الإلكتروني والبريد الإلكتروني والهاتف والعنوان وساعات العمل والإشعار القانوني من صفحتك. لا يمكن التراجع عن ذلك.',
    'Contact details cleared': 'تم مسح بيانات التواصل',
    'Cover, photo, name, description and everything visitors see':
        'الغلاف والصورة والاسم والوصف وكل ما يراه الزوار',
  },
  'th': <String, String>{
    'pageEdit.appearance': 'รูปลักษณ์',
    'pageEdit.name': 'ชื่อ',
    'pageEdit.clear': 'ล้าง',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'ภาพปก รูป และชื่อของเพจคุณ เป็นภาพปก รูป และชื่อบัญชีของคุณในแชตและเซิร์ฟเวอร์ด้วย',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'คุณเปลี่ยนชื่อได้หนึ่งครั้งทุก 30 วัน หลังเปลี่ยนแล้ว เพจจะไม่แสดงในการค้นหาเป็นเวลา 7 วัน',
    'You can change the name again on {date}.':
        'คุณเปลี่ยนชื่อได้อีกครั้งในวันที่ {date}',
    'The name must be 2 to 120 characters long.':
        'ชื่อต้องมีความยาว 2 ถึง 120 ตัวอักษร',
    "The type can't be changed yet": 'ยังเปลี่ยนประเภทไม่ได้',
    'For example: be kind, no ads, only photos of your own work.':
        'ตัวอย่างเช่น: ให้เกียรติกัน ไม่โฆษณา ลงเฉพาะรูปผลงานของตัวเอง',
    'Change cover': 'เปลี่ยนภาพปก',
    'Change photo': 'เปลี่ยนรูป',
    'This is how others will see your Page. The preview changes as you type.':
        'คนอื่นจะเห็นเพจของคุณแบบนี้ ตัวอย่างจะเปลี่ยนไปตามที่คุณพิมพ์',
    'Hide preview': 'ซ่อนตัวอย่าง',
    'Show preview': 'แสดงตัวอย่าง',
    'You have unsaved changes': 'คุณมีการเปลี่ยนแปลงที่ยังไม่ได้บันทึก',
    'Save changes': 'บันทึกการเปลี่ยนแปลง',
    'Discard changes?': 'ทิ้งการเปลี่ยนแปลงใช่ไหม',
    "Your changes haven't been saved.": 'การเปลี่ยนแปลงของคุณยังไม่ได้บันทึก',
    "Couldn't save the changes": 'บันทึกการเปลี่ยนแปลงไม่สำเร็จ',
    'Some changes were saved, but not all':
        'บันทึกการเปลี่ยนแปลงได้บางส่วน แต่ไม่ครบทั้งหมด',
    "Couldn't change the name. Try again.": 'เปลี่ยนชื่อไม่สำเร็จ ลองอีกครั้ง',
    'The name is saved. Press Save again to finish.':
        'บันทึกชื่อแล้ว แตะบันทึกอีกครั้งเพื่อเสร็จสิ้น',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'ใช้รูปภาพนี้ไม่ได้ โปรดเลือกไฟล์ JPG, PNG หรือ WebP',
    "Couldn't upload the image. Check your connection and try again.":
        'อัปโหลดรูปภาพไม่สำเร็จ ตรวจสอบการเชื่อมต่อแล้วลองอีกครั้ง',
    'Editing is off right now': 'ขณะนี้แก้ไขไม่ได้',
    'Editing comes back when Premium or VIP is active again.':
        'คุณจะแก้ไขได้อีกครั้งเมื่อ Premium หรือ VIP กลับมาใช้งานได้',
    "This Page is suspended by moderation, so it can't be edited.":
        'เพจนี้ถูกระงับโดยทีมดูแล จึงแก้ไขไม่ได้',
    'Clear contact details': 'ล้างข้อมูลติดต่อ',
    'Clear contact details?': 'ล้างข้อมูลติดต่อใช่ไหม',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'เว็บไซต์ อีเมล โทรศัพท์ ที่อยู่ เวลาทำการ และประกาศทางกฎหมายจะถูกนำออกจากเพจของคุณ การดำเนินการนี้ย้อนกลับไม่ได้',
    'Contact details cleared': 'ล้างข้อมูลติดต่อแล้ว',
    'Cover, photo, name, description and everything visitors see':
        'ภาพปก รูป ชื่อ คำอธิบาย และทุกอย่างที่ผู้เข้าชมเห็น',
  },
  'ms': <String, String>{
    'pageEdit.appearance': 'Penampilan',
    'pageEdit.name': 'Nama',
    'pageEdit.clear': 'Kosongkan',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Kulit, foto dan nama halaman anda juga ialah kulit, foto dan nama akaun anda dalam sembang dan pelayan.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Anda boleh menukar nama sekali setiap 30 hari. Selepas ditukar, halaman tidak muncul dalam carian selama 7 hari.',
    'You can change the name again on {date}.':
        'Anda boleh menukar nama semula pada {date}.',
    'The name must be 2 to 120 characters long.':
        'Nama mesti sepanjang 2 hingga 120 aksara.',
    "The type can't be changed yet": 'Jenis belum boleh ditukar',
    'For example: be kind, no ads, only photos of your own work.':
        'Contohnya: saling menghormati, tiada iklan, hanya foto hasil kerja sendiri.',
    'Change cover': 'Tukar kulit',
    'Change photo': 'Tukar foto',
    'This is how others will see your Page. The preview changes as you type.':
        'Beginilah orang lain akan melihat halaman anda. Pratonton berubah semasa anda menaip.',
    'Hide preview': 'Sembunyikan pratonton',
    'Show preview': 'Tunjukkan pratonton',
    'You have unsaved changes': 'Anda ada perubahan yang belum disimpan',
    'Save changes': 'Simpan perubahan',
    'Discard changes?': 'Buang perubahan?',
    "Your changes haven't been saved.": 'Perubahan anda belum disimpan.',
    "Couldn't save the changes": 'Perubahan tidak dapat disimpan',
    'Some changes were saved, but not all':
        'Sebahagian perubahan disimpan, tetapi bukan semua',
    "Couldn't change the name. Try again.":
        'Nama tidak dapat ditukar. Cuba lagi.',
    'The name is saved. Press Save again to finish.':
        'Nama telah disimpan. Ketik Simpan sekali lagi untuk selesai.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Imej ini tidak dapat digunakan. Pilih fail JPG, PNG atau WebP.',
    "Couldn't upload the image. Check your connection and try again.":
        'Imej tidak dapat dimuat naik. Semak sambungan anda dan cuba lagi.',
    'Editing is off right now': 'Penyuntingan dimatikan buat masa ini',
    'Editing comes back when Premium or VIP is active again.':
        'Penyuntingan akan kembali apabila Premium atau VIP aktif semula.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Halaman ini digantung oleh moderasi, jadi ia tidak boleh disunting.',
    'Clear contact details': 'Kosongkan butiran hubungan',
    'Clear contact details?': 'Kosongkan butiran hubungan?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Laman web, e-mel, telefon, alamat, waktu operasi dan notis undang-undang akan dialih keluar daripada halaman anda. Tindakan ini tidak boleh dibuat asal.',
    'Contact details cleared': 'Butiran hubungan dikosongkan',
    'Cover, photo, name, description and everything visitors see':
        'Kulit, foto, nama, penerangan dan semua yang dilihat pelawat',
  },
  'fil': <String, String>{
    'pageEdit.appearance': 'Hitsura',
    'pageEdit.name': 'Pangalan',
    'pageEdit.clear': 'I-clear',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Ang cover, larawan at pangalan ng Page mo ay siya ring cover, larawan at pangalan ng account mo sa mga chat at server.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Maaari mong palitan ang pangalan nang isang beses kada 30 araw. Pagkatapos ng pagpapalit, 7 araw na hindi lalabas ang Page sa paghahanap.',
    'You can change the name again on {date}.':
        'Maaari mong palitan muli ang pangalan sa {date}.',
    'The name must be 2 to 120 characters long.':
        'Dapat 2 hanggang 120 character ang haba ng pangalan.',
    "The type can't be changed yet": 'Hindi pa mapapalitan ang uri',
    'For example: be kind, no ads, only photos of your own work.':
        'Halimbawa: maging magalang, walang ad, mga larawan lang ng sarili mong gawa.',
    'Change cover': 'Palitan ang cover',
    'Change photo': 'Palitan ang larawan',
    'This is how others will see your Page. The preview changes as you type.':
        'Ganito makikita ng iba ang Page mo. Nagbabago ang preview habang nagta-type ka.',
    'Hide preview': 'Itago ang preview',
    'Show preview': 'Ipakita ang preview',
    'You have unsaved changes': 'May mga pagbabago kang hindi pa na-save',
    'Save changes': 'I-save ang mga pagbabago',
    'Discard changes?': 'I-discard ang mga pagbabago?',
    "Your changes haven't been saved.": 'Hindi na-save ang mga pagbabago mo.',
    "Couldn't save the changes": 'Hindi na-save ang mga pagbabago',
    'Some changes were saved, but not all':
        'Na-save ang ilang pagbabago, pero hindi lahat',
    "Couldn't change the name. Try again.":
        'Hindi napalitan ang pangalan. Subukan ulit.',
    'The name is saved. Press Save again to finish.':
        'Na-save na ang pangalan. Pindutin ulit ang I-save para matapos.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Hindi magagamit ang larawang ito. Pumili ng JPG, PNG o WebP na file.',
    "Couldn't upload the image. Check your connection and try again.":
        'Hindi na-upload ang larawan. Suriin ang koneksyon mo at subukan ulit.',
    'Editing is off right now': 'Naka-off muna ang pag-edit',
    'Editing comes back when Premium or VIP is active again.':
        'Babalik ang pag-edit kapag aktibo na ulit ang Premium o VIP.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Sinuspinde ng moderation ang Page na ito kaya hindi ito mae-edit.',
    'Clear contact details': 'I-clear ang contact details',
    'Clear contact details?': 'I-clear ang contact details?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Aalisin sa Page mo ang website, e-mail, telepono, address, oras at legal na abiso. Hindi na ito maibabalik.',
    'Contact details cleared': 'Na-clear ang contact details',
    'Cover, photo, name, description and everything visitors see':
        'Cover, larawan, pangalan, paglalarawan at lahat ng nakikita ng mga bisita',
  },
  'he': <String, String>{
    'pageEdit.appearance': 'מראה',
    'pageEdit.name': 'שם',
    'pageEdit.clear': 'ניקוי',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'תמונת הנושא, התמונה והשם של הדף שלך הם גם תמונת הנושא, התמונה והשם של החשבון שלך בצ׳אטים ובשרתים.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'אפשר לשנות את השם פעם ב-30 יום. אחרי שינוי, הדף לא מופיע בחיפוש במשך 7 ימים.',
    'You can change the name again on {date}.':
        'אפשר יהיה לשנות שוב את השם ב-{date}.',
    'The name must be 2 to 120 characters long.':
        'אורך השם צריך להיות בין 2 ל-120 תווים.',
    "The type can't be changed yet": 'עדיין אי אפשר לשנות את הסוג',
    'For example: be kind, no ads, only photos of your own work.':
        'לדוגמה: מכבדים זה את זה, בלי פרסומות, רק תמונות של עבודות משלך.',
    'Change cover': 'שינוי תמונת הנושא',
    'Change photo': 'שינוי התמונה',
    'This is how others will see your Page. The preview changes as you type.':
        'כך אחרים יראו את הדף שלך. התצוגה המקדימה משתנה בזמן ההקלדה.',
    'Hide preview': 'הסתרת התצוגה המקדימה',
    'Show preview': 'הצגת התצוגה המקדימה',
    'You have unsaved changes': 'יש לך שינויים שלא נשמרו',
    'Save changes': 'שמירת השינויים',
    'Discard changes?': 'לבטל את השינויים?',
    "Your changes haven't been saved.": 'השינויים שלך לא נשמרו.',
    "Couldn't save the changes": 'לא ניתן היה לשמור את השינויים',
    'Some changes were saved, but not all': 'חלק מהשינויים נשמרו, אבל לא כולם',
    "Couldn't change the name. Try again.":
        'לא ניתן היה לשנות את השם. כדאי לנסות שוב.',
    'The name is saved. Press Save again to finish.':
        'השם נשמר. יש ללחוץ שוב על שמירה כדי לסיים.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'אי אפשר להשתמש בתמונה הזו. יש לבחור קובץ JPG, PNG או WebP.',
    "Couldn't upload the image. Check your connection and try again.":
        'לא ניתן היה להעלות את התמונה. כדאי לבדוק את החיבור ולנסות שוב.',
    'Editing is off right now': 'העריכה כבויה כרגע',
    'Editing comes back when Premium or VIP is active again.':
        'העריכה תחזור כש-Premium או VIP יהיו פעילים שוב.',
    "This Page is suspended by moderation, so it can't be edited.":
        'הדף הזה הושעה על ידי צוות הפיקוח, ולכן אי אפשר לערוך אותו.',
    'Clear contact details': 'ניקוי פרטי הקשר',
    'Clear contact details?': 'לנקות את פרטי הקשר?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'האתר, האימייל, הטלפון, הכתובת, שעות הפעילות וההודעה המשפטית יוסרו מהדף שלך. אי אפשר לבטל את הפעולה.',
    'Contact details cleared': 'פרטי הקשר נוקו',
    'Cover, photo, name, description and everything visitors see':
        'תמונת נושא, תמונה, שם, תיאור וכל מה שהמבקרים רואים',
  },
  'fa': <String, String>{
    'pageEdit.appearance': 'ظاهر',
    'pageEdit.name': 'نام',
    'pageEdit.clear': 'پاک کردن',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'کاور، عکس و نام صفحهٔ شما همان کاور، عکس و نام حساب شما در گفتگوها و سرورها هم هست.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'هر ۳۰ روز یک بار می‌توانید نام را تغییر دهید. پس از تغییر، صفحه تا ۷ روز در جستجو نمایش داده نمی‌شود.',
    'You can change the name again on {date}.':
        'می‌توانید در {date} دوباره نام را تغییر دهید.',
    'The name must be 2 to 120 characters long.':
        'نام باید بین ۲ تا ۱۲۰ نویسه باشد.',
    "The type can't be changed yet": 'نوع هنوز قابل تغییر نیست',
    'For example: be kind, no ads, only photos of your own work.':
        'برای مثال: به هم احترام می‌گذاریم، بدون تبلیغ، فقط عکس کارهای خودتان.',
    'Change cover': 'تغییر کاور',
    'Change photo': 'تغییر عکس',
    'This is how others will see your Page. The preview changes as you type.':
        'دیگران صفحهٔ شما را این‌طور می‌بینند. پیش‌نمایش هنگام نوشتن تغییر می‌کند.',
    'Hide preview': 'پنهان کردن پیش‌نمایش',
    'Show preview': 'نمایش پیش‌نمایش',
    'You have unsaved changes': 'تغییرات ذخیره‌نشده دارید',
    'Save changes': 'ذخیرهٔ تغییرات',
    'Discard changes?': 'تغییرات کنار گذاشته شود؟',
    "Your changes haven't been saved.": 'تغییرات شما ذخیره نشده است.',
    "Couldn't save the changes": 'تغییرات ذخیره نشد',
    'Some changes were saved, but not all':
        'بخشی از تغییرات ذخیره شد، اما نه همه',
    "Couldn't change the name. Try again.": 'نام تغییر نکرد. دوباره تلاش کنید.',
    'The name is saved. Press Save again to finish.':
        'نام ذخیره شد. برای پایان، دوباره روی «ذخیره» بزنید.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'این تصویر قابل استفاده نیست. یک فایل JPG، PNG یا WebP انتخاب کنید.',
    "Couldn't upload the image. Check your connection and try again.":
        'تصویر بارگذاری نشد. اتصال خود را بررسی کنید و دوباره تلاش کنید.',
    'Editing is off right now': 'ویرایش در حال حاضر غیرفعال است',
    'Editing comes back when Premium or VIP is active again.':
        'وقتی Premium یا VIP دوباره فعال شود، ویرایش برمی‌گردد.',
    "This Page is suspended by moderation, so it can't be edited.":
        'این صفحه توسط تیم نظارت تعلیق شده است و نمی‌توان آن را ویرایش کرد.',
    'Clear contact details': 'پاک کردن اطلاعات تماس',
    'Clear contact details?': 'اطلاعات تماس پاک شود؟',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'وب‌سایت، ایمیل، تلفن، نشانی، ساعات کاری و اطلاعیهٔ حقوقی از صفحهٔ شما حذف می‌شود. این کار قابل بازگشت نیست.',
    'Contact details cleared': 'اطلاعات تماس پاک شد',
    'Cover, photo, name, description and everything visitors see':
        'کاور، عکس، نام، توضیحات و هر آنچه بازدیدکنندگان می‌بینند',
  },
  'sw': <String, String>{
    'pageEdit.appearance': 'Mwonekano',
    'pageEdit.name': 'Jina',
    'pageEdit.clear': 'Futa',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'Jalada, picha na jina la ukurasa wako pia ni jalada, picha na jina la akaunti yako kwenye gumzo na seva.',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'Unaweza kubadilisha jina mara moja kila siku 30. Baada ya mabadiliko, ukurasa hauonekani kwenye utafutaji kwa siku 7.',
    'You can change the name again on {date}.':
        'Unaweza kubadilisha jina tena tarehe {date}.',
    'The name must be 2 to 120 characters long.':
        'Jina lazima liwe na herufi 2 hadi 120.',
    "The type can't be changed yet": 'Aina haiwezi kubadilishwa bado',
    'For example: be kind, no ads, only photos of your own work.':
        'Kwa mfano: tuheshimiane, hakuna matangazo, picha za kazi zako mwenyewe tu.',
    'Change cover': 'Badilisha jalada',
    'Change photo': 'Badilisha picha',
    'This is how others will see your Page. The preview changes as you type.':
        'Hivi ndivyo wengine watakavyoona ukurasa wako. Onyesho la kukagua hubadilika unapoandika.',
    'Hide preview': 'Ficha onyesho la kukagua',
    'Show preview': 'Onyesha onyesho la kukagua',
    'You have unsaved changes': 'Una mabadiliko ambayo hayajahifadhiwa',
    'Save changes': 'Hifadhi mabadiliko',
    'Discard changes?': 'Ungependa kutupa mabadiliko?',
    "Your changes haven't been saved.": 'Mabadiliko yako hayajahifadhiwa.',
    "Couldn't save the changes": 'Imeshindwa kuhifadhi mabadiliko',
    'Some changes were saved, but not all':
        'Baadhi ya mabadiliko yamehifadhiwa, lakini si yote',
    "Couldn't change the name. Try again.":
        'Imeshindwa kubadilisha jina. Jaribu tena.',
    'The name is saved. Press Save again to finish.':
        'Jina limehifadhiwa. Gusa Hifadhi tena ili kumaliza.',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'Picha hii haiwezi kutumika. Chagua faili la JPG, PNG au WebP.',
    "Couldn't upload the image. Check your connection and try again.":
        'Imeshindwa kupakia picha. Angalia muunganisho wako kisha ujaribu tena.',
    'Editing is off right now': 'Kuhariri kumezimwa kwa sasa',
    'Editing comes back when Premium or VIP is active again.':
        'Kuhariri kutarejea Premium au VIP itakapokuwa hai tena.',
    "This Page is suspended by moderation, so it can't be edited.":
        'Ukurasa huu umesimamishwa na wasimamizi, kwa hivyo hauwezi kuhaririwa.',
    'Clear contact details': 'Futa maelezo ya mawasiliano',
    'Clear contact details?': 'Ungependa kufuta maelezo ya mawasiliano?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'Tovuti, barua pepe, simu, anwani, saa za kazi na ilani ya kisheria vitaondolewa kwenye ukurasa wako. Hatua hii haiwezi kutenduliwa.',
    'Contact details cleared': 'Maelezo ya mawasiliano yamefutwa',
    'Cover, photo, name, description and everything visitors see':
        'Jalada, picha, jina, maelezo na kila kitu ambacho wageni huona',
  },
  'hi': <String, String>{
    'pageEdit.appearance': 'रूप-रंग',
    'pageEdit.name': 'नाम',
    'pageEdit.clear': 'साफ़ करें',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'आपके पेज का कवर, फ़ोटो और नाम ही चैट और सर्वर में आपके खाते का कवर, फ़ोटो और नाम भी हैं।',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'आप हर 30 दिन में एक बार नाम बदल सकते हैं। बदलाव के बाद पेज 7 दिन तक खोज में नहीं दिखता।',
    'You can change the name again on {date}.':
        'आप {date} को फिर से नाम बदल सकेंगे।',
    'The name must be 2 to 120 characters long.':
        'नाम 2 से 120 वर्णों का होना चाहिए।',
    "The type can't be changed yet": 'प्रकार अभी बदला नहीं जा सकता',
    'For example: be kind, no ads, only photos of your own work.':
        'उदाहरण के लिए: एक-दूसरे का सम्मान करें, कोई विज्ञापन नहीं, केवल अपने काम की फ़ोटो।',
    'Change cover': 'कवर बदलें',
    'Change photo': 'फ़ोटो बदलें',
    'This is how others will see your Page. The preview changes as you type.':
        'दूसरे लोग आपका पेज ऐसे देखेंगे। आपके लिखने के साथ पूर्वावलोकन बदलता है।',
    'Hide preview': 'पूर्वावलोकन छिपाएँ',
    'Show preview': 'पूर्वावलोकन दिखाएँ',
    'You have unsaved changes': 'आपके बदलाव सेव नहीं हुए हैं',
    'Save changes': 'बदलाव सेव करें',
    'Discard changes?': 'बदलाव छोड़ दें?',
    "Your changes haven't been saved.": 'आपके बदलाव सेव नहीं किए गए हैं।',
    "Couldn't save the changes": 'बदलाव सेव नहीं हो सके',
    'Some changes were saved, but not all': 'कुछ बदलाव सेव हुए, लेकिन सभी नहीं',
    "Couldn't change the name. Try again.":
        'नाम नहीं बदला जा सका। फिर से कोशिश करें।',
    'The name is saved. Press Save again to finish.':
        'नाम सेव हो गया है। पूरा करने के लिए फिर से सेव करें दबाएँ।',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'यह इमेज इस्तेमाल नहीं की जा सकती। कोई JPG, PNG या WebP फ़ाइल चुनें।',
    "Couldn't upload the image. Check your connection and try again.":
        'इमेज अपलोड नहीं हो सकी। अपना कनेक्शन जाँचें और फिर से कोशिश करें।',
    'Editing is off right now': 'संपादन अभी बंद है',
    'Editing comes back when Premium or VIP is active again.':
        'Premium या VIP के फिर से सक्रिय होने पर संपादन वापस आ जाएगा।',
    "This Page is suspended by moderation, so it can't be edited.":
        'इस पेज को मॉडरेशन ने निलंबित किया है, इसलिए इसे संपादित नहीं किया जा सकता।',
    'Clear contact details': 'संपर्क जानकारी साफ़ करें',
    'Clear contact details?': 'संपर्क जानकारी साफ़ करें?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'वेबसाइट, ईमेल, फ़ोन, पता, समय और कानूनी सूचना आपके पेज से हटा दी जाएगी। इसे वापस नहीं किया जा सकता।',
    'Contact details cleared': 'संपर्क जानकारी साफ़ कर दी गई',
    'Cover, photo, name, description and everything visitors see':
        'कवर, फ़ोटो, नाम, विवरण और वह सब कुछ जो विज़िटर देखते हैं',
  },
  'bn': <String, String>{
    'pageEdit.appearance': 'চেহারা',
    'pageEdit.name': 'নাম',
    'pageEdit.clear': 'মুছুন',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'আপনার পেজের কভার, ছবি ও নামই চ্যাট ও সার্ভারে আপনার অ্যাকাউন্টের কভার, ছবি ও নাম।',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'আপনি প্রতি ৩০ দিনে একবার নাম বদলাতে পারেন। বদলানোর পর ৭ দিন পেজটি সার্চে দেখা যায় না।',
    'You can change the name again on {date}.':
        'আপনি {date} তারিখে আবার নাম বদলাতে পারবেন।',
    'The name must be 2 to 120 characters long.':
        'নাম ২ থেকে ১২০ অক্ষরের মধ্যে হতে হবে।',
    "The type can't be changed yet": 'ধরন এখনও বদলানো যায় না',
    'For example: be kind, no ads, only photos of your own work.':
        'যেমন: একে অপরকে সম্মান করি, বিজ্ঞাপন নয়, শুধু নিজের কাজের ছবি।',
    'Change cover': 'কভার বদলান',
    'Change photo': 'ছবি বদলান',
    'This is how others will see your Page. The preview changes as you type.':
        'অন্যরা আপনার পেজ এভাবেই দেখবে। আপনি লেখার সঙ্গে সঙ্গে প্রিভিউ বদলায়।',
    'Hide preview': 'প্রিভিউ লুকান',
    'Show preview': 'প্রিভিউ দেখান',
    'You have unsaved changes': 'আপনার কিছু পরিবর্তন সংরক্ষণ করা হয়নি',
    'Save changes': 'পরিবর্তন সংরক্ষণ করুন',
    'Discard changes?': 'পরিবর্তন বাতিল করবেন?',
    "Your changes haven't been saved.": 'আপনার পরিবর্তনগুলো সংরক্ষণ করা হয়নি।',
    "Couldn't save the changes": 'পরিবর্তন সংরক্ষণ করা যায়নি',
    'Some changes were saved, but not all':
        'কিছু পরিবর্তন সংরক্ষিত হয়েছে, তবে সব নয়',
    "Couldn't change the name. Try again.":
        'নাম বদলানো যায়নি। আবার চেষ্টা করুন।',
    'The name is saved. Press Save again to finish.':
        'নাম সংরক্ষিত হয়েছে। শেষ করতে আবার সংরক্ষণ করুন চাপুন।',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'এই ছবিটি ব্যবহার করা যাচ্ছে না। একটি JPG, PNG বা WebP ফাইল বেছে নিন।',
    "Couldn't upload the image. Check your connection and try again.":
        'ছবি আপলোড করা যায়নি। আপনার সংযোগ পরীক্ষা করে আবার চেষ্টা করুন।',
    'Editing is off right now': 'সম্পাদনা এখন বন্ধ আছে',
    'Editing comes back when Premium or VIP is active again.':
        'Premium বা VIP আবার সক্রিয় হলে সম্পাদনা ফিরে আসবে।',
    "This Page is suspended by moderation, so it can't be edited.":
        'মডারেশন এই পেজটি স্থগিত করেছে, তাই এটি সম্পাদনা করা যাবে না।',
    'Clear contact details': 'যোগাযোগের তথ্য মুছুন',
    'Clear contact details?': 'যোগাযোগের তথ্য মুছবেন?',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'ওয়েবসাইট, ইমেল, ফোন, ঠিকানা, সময়সূচি ও আইনি নোটিশ আপনার পেজ থেকে সরিয়ে ফেলা হবে। এটি আর ফেরানো যাবে না।',
    'Contact details cleared': 'যোগাযোগের তথ্য মুছে ফেলা হয়েছে',
    'Cover, photo, name, description and everything visitors see':
        'কভার, ছবি, নাম, বিবরণ এবং দর্শকরা যা কিছু দেখেন',
  },
  'ur': <String, String>{
    'pageEdit.appearance': 'ظاہری شکل',
    'pageEdit.name': 'نام',
    'pageEdit.clear': 'صاف کریں',
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.':
        'آپ کے پیج کا کور، تصویر اور نام ہی چیٹس اور سرورز میں آپ کے اکاؤنٹ کا کور، تصویر اور نام بھی ہیں۔',
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.':
        'آپ ہر 30 دن میں ایک بار نام بدل سکتے ہیں۔ تبدیلی کے بعد پیج 7 دن تک تلاش میں نظر نہیں آتا۔',
    'You can change the name again on {date}.':
        'آپ {date} کو دوبارہ نام بدل سکیں گے۔',
    'The name must be 2 to 120 characters long.':
        'نام 2 سے 120 حروف کا ہونا چاہیے۔',
    "The type can't be changed yet": 'قسم ابھی تبدیل نہیں کی جا سکتی',
    'For example: be kind, no ads, only photos of your own work.':
        'مثال کے طور پر: ایک دوسرے کا احترام کریں، کوئی اشتہار نہیں، صرف اپنے کام کی تصاویر۔',
    'Change cover': 'کور تبدیل کریں',
    'Change photo': 'تصویر تبدیل کریں',
    'This is how others will see your Page. The preview changes as you type.':
        'دوسرے لوگ آپ کا پیج اس طرح دیکھیں گے۔ آپ کے لکھنے کے ساتھ پیش نظارہ بدلتا ہے۔',
    'Hide preview': 'پیش نظارہ چھپائیں',
    'Show preview': 'پیش نظارہ دکھائیں',
    'You have unsaved changes': 'آپ کی کچھ تبدیلیاں محفوظ نہیں ہوئیں',
    'Save changes': 'تبدیلیاں محفوظ کریں',
    'Discard changes?': 'تبدیلیاں ترک کریں؟',
    "Your changes haven't been saved.": 'آپ کی تبدیلیاں محفوظ نہیں کی گئیں۔',
    "Couldn't save the changes": 'تبدیلیاں محفوظ نہیں ہو سکیں',
    'Some changes were saved, but not all':
        'کچھ تبدیلیاں محفوظ ہو گئیں، لیکن سب نہیں',
    "Couldn't change the name. Try again.":
        'نام تبدیل نہیں ہو سکا۔ دوبارہ کوشش کریں۔',
    'The name is saved. Press Save again to finish.':
        'نام محفوظ ہو گیا ہے۔ مکمل کرنے کے لیے دوبارہ محفوظ کریں دبائیں۔',
    "Couldn't use this image. Choose a JPG, PNG or WebP file.":
        'یہ تصویر استعمال نہیں ہو سکتی۔ کوئی JPG، PNG یا WebP فائل منتخب کریں۔',
    "Couldn't upload the image. Check your connection and try again.":
        'تصویر اپ لوڈ نہیں ہو سکی۔ اپنا کنکشن چیک کریں اور دوبارہ کوشش کریں۔',
    'Editing is off right now': 'ترمیم اس وقت بند ہے',
    'Editing comes back when Premium or VIP is active again.':
        'Premium یا VIP کے دوبارہ فعال ہونے پر ترمیم واپس آ جائے گی۔',
    "This Page is suspended by moderation, so it can't be edited.":
        'اس پیج کو ماڈریشن نے معطل کر دیا ہے، اس لیے اس میں ترمیم نہیں ہو سکتی۔',
    'Clear contact details': 'رابطے کی تفصیلات صاف کریں',
    'Clear contact details?': 'رابطے کی تفصیلات صاف کریں؟',
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.":
        'ویب سائٹ، ای میل، فون، پتہ، اوقات اور قانونی نوٹس آپ کے پیج سے ہٹا دیے جائیں گے۔ یہ واپس نہیں ہو سکتا۔',
    'Contact details cleared': 'رابطے کی تفصیلات صاف کر دی گئیں',
    'Cover, photo, name, description and everything visitors see':
        'کور، تصویر، نام، تفصیل اور وہ سب کچھ جو وزیٹرز دیکھتے ہیں',
  },
};
