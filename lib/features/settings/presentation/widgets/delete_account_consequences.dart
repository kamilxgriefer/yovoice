import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';

/// One line of "this is what happens", with the icon that names its category.
@immutable
class DeleteAccountConsequence {
  const DeleteAccountConsequence({required this.icon, required this.text});

  final IconData icon;
  final String text;
}

/// Exactly what the pipeline deletes, in the user's own vocabulary rather than
/// a schema dump. Every line here is a claim the backend has to keep, so this
/// list and the retained set below are the same contract the privacy policy
/// and `yovoice.app/delete-account` state.
///
/// EVERY LINE IS BACKED BY A LINE OF `functions/account/stages.js`. Three
/// categories that an earlier draft claimed are deliberately NOT claimed here,
/// because the pipeline does not do them (ADR-206 Consequences, docs/Bugs.md):
/// comments and reactions left on other people's posts, uploads that live in
/// somebody else's Storage container (Family memories, Company channel files),
/// and `directCalls` records. Do not re-add a line without the stage that
/// keeps it and the emulator test that proves it.
List<DeleteAccountConsequence> deleteAccountConsequences(
  AppLocalizations copy,
) => [
  DeleteAccountConsequence(
    icon: Icons.person_off_outlined,
    text: copy.text(
      'Your profile, and the photos, videos, voice recordings and files you '
          'uploaded to your own account, are deleted.',
      'Twój profil oraz zdjęcia, filmy, nagrania głosowe i pliki przesłane na '
          'Twoje własne konto zostaną usunięte.',
    ),
  ),
  DeleteAccountConsequence(
    icon: Icons.graphic_eq_rounded,
    text: copy.text(
      'The Voice Moments and Yeels you posted are deleted, together with the '
          'comments and reactions people left on them.',
      'Opublikowane przez Ciebie Voice Moments i Yeele zostaną usunięte wraz '
          'z komentarzami i reakcjami, które inni pod nimi zostawili.',
    ),
  ),
  DeleteAccountConsequence(
    icon: Icons.group_off_outlined,
    text: copy.text(
      'Your friends, followers, blocks and viewing history are deleted.',
      'Twoi znajomi, obserwujący, blokady i historia oglądania zostaną usunięte.',
    ),
  ),
  DeleteAccountConsequence(
    icon: Icons.dns_outlined,
    text: copy.text(
      'Your name and photo are removed from every server you were in. Servers '
          'you own keep running under an anonymous owner until we transfer or '
          'close them.',
      'Twoje imię i zdjęcie zostaną usunięte z każdego serwera, na którym '
          'byłeś(-aś). Serwery, których jesteś właścicielem, działają dalej '
          'pod anonimowym właścicielem, dopóki ich nie przekażemy lub nie '
          'zamkniemy.',
    ),
  ),
  DeleteAccountConsequence(
    icon: Icons.forum_outlined,
    text: copy.text(
      'Messages you sent stay visible to the person you sent them to, shown '
          'as from a deleted account. Files and voice notes you sent are deleted.',
      'Wiadomości, które wysłałeś(-aś), pozostaną widoczne dla odbiorcy jako '
          'pochodzące z usuniętego konta. Wysłane pliki i notatki głosowe '
          'zostaną usunięte.',
    ),
  ),
  // functions/account/stages.js: the `records` stage's step 5
  // (deleteBugReports) and the bug_reports/{uid}/ Storage prefix; proved by
  // functions/test/bug_reports.test.js ("account deletion sweeps …"). Team
  // alerts about a report carry only its reference, platform, version and
  // screen name, never the words or the screenshot (bug_reports/delivery.js).
  DeleteAccountConsequence(
    icon: Icons.bug_report_outlined,
    text: copy.text(
      'Bug reports you sent, and any screenshots you attached to them, are '
          'deleted.',
      'Wysłane przez Ciebie zgłoszenia błędów oraz dołączone do nich zrzuty '
          'ekranu zostaną usunięte.',
    ),
  ),
  DeleteAccountConsequence(
    icon: Icons.key_off_outlined,
    text: copy.text(
      'Your sign-in is deleted — the email address, the password and any '
          'linked Google or Apple account.',
      'Twoje logowanie zostanie usunięte — adres e-mail, hasło oraz powiązane '
          'konto Google lub Apple.',
    ),
  ),
];

/// The retained set, item by item, each with the reason that justifies it.
/// Nothing may be added here without the same line appearing in the privacy
/// policy and on the public deletion page.
List<DeleteAccountConsequence> deleteAccountRetentions(AppLocalizations copy) =>
    [
      DeleteAccountConsequence(
        icon: Icons.block_outlined,
        text: copy.text(
          'If your account was banned, a one-way hash of your email address, '
              'so that deleting an account cannot reset a ban. The address '
              'itself is not kept.',
          'Jeśli Twoje konto było zablokowane — jednokierunkowy skrót adresu '
              'e-mail, aby usunięcie konta nie znosiło blokady. Sam adres nie '
              'jest przechowywany.',
        ),
      ),
      DeleteAccountConsequence(
        icon: Icons.flag_outlined,
        text: copy.text(
          'Reports you sent, with your name replaced. Erasing them would '
              'destroy evidence of harassment against somebody else.',
          'Zgłoszenia, które wysłałeś(-aś), z zastąpioną Twoją tożsamością. '
              'Ich usunięcie zniszczyłoby dowody nękania innej osoby.',
        ),
      ),
      DeleteAccountConsequence(
        icon: Icons.gavel_rounded,
        text: copy.text(
          'Reports about your account and moderation audit logs, so that '
              'moderation decisions stay accountable.',
          'Zgłoszenia dotyczące Twojego konta oraz dzienniki decyzji '
              'moderacyjnych, aby te decyzje pozostały rozliczalne.',
        ),
      ),
      DeleteAccountConsequence(
        icon: Icons.receipt_long_outlined,
        text: copy.text(
          'Payment records we are required by law to keep. They contain no '
              'card details.',
          'Dokumenty płatnicze, które musimy przechowywać zgodnie z prawem. '
              'Nie zawierają danych karty.',
        ),
      ),
      DeleteAccountConsequence(
        icon: Icons.shield_outlined,
        text: copy.text(
          'Short-lived records that stop an in-flight operation from being '
              'replayed.',
          'Krótkotrwałe zapisy, które uniemożliwiają powtórzenie operacji '
              'będącej w toku.',
        ),
      ),
      DeleteAccountConsequence(
        icon: Icons.terminal_rounded,
        text: copy.text(
          'Technical service logs and crash reports held by Google, under '
              'those services\' retention settings.',
          'Techniczne dzienniki usług i raporty awarii przechowywane przez '
              'Google, zgodnie z ustawieniami retencji tych usług.',
        ),
      ),
    ];

/// The consequences list, as a semantic list — one node per item, so a screen
/// reader reads "item 3 of 6" rather than one unbroken paragraph.
class DeleteAccountConsequenceList extends StatelessWidget {
  const DeleteAccountConsequenceList({
    required this.items,
    this.danger = true,
    super.key,
  });

  final List<DeleteAccountConsequence> items;

  /// Deletions are drawn with the destructive pair; retentions are neutral,
  /// because keeping a moderation record is not a warning.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < items.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == items.length - 1 ? 0 : 14,
              ),
              child: ConstrainedBox(
                // Every row is a real 48 dp target's worth of space even when
                // the sentence is one line at 100 % text scale.
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        items[index].icon,
                        size: 20,
                        color: danger ? colors.error : palette.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        items[index].text,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 14.5,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
