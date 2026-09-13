import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';

/// Presentation-only localization for copy owned by Premium data models.
///
/// Product identifiers and billing values stay unchanged. Only their visible
/// labels are translated at the UI boundary, so model and server contracts do
/// not become locale-dependent.
String localizedPremiumPlanLabel(AppLocalizations copy, PremiumPlan plan) =>
    switch (plan) {
      PremiumPlan.monthly => copy.text('Monthly', 'Miesięczny'),
      PremiumPlan.yearly => copy.text('Yearly', 'Roczny'),
      PremiumPlan.none => copy.text('Free', 'Bezpłatny'),
    };

(String, String) localizedPremiumBenefit(
  AppLocalizations copy,
  (String, String) benefit,
) {
  final title = switch (benefit.$1) {
    'Creator account & studio' => copy.text(
      'Creator account & studio',
      'Konto twórcy i Studio',
    ),
    'Up to 30 Servers after launch' => copy.text(
      'Up to 30 Servers after launch',
      'Do 30 serwerów po uruchomieniu',
    ),
    'Premium presence & privacy' => copy.text(
      'Premium presence & privacy',
      'Wygląd i prywatność Premium',
    ),
    _ => copy.text(benefit.$1, 'Korzyść Premium'),
  };
  final subtitle = switch (benefit.$2) {
    'Unlock Creator Studio; age confirmation and opt-in enable Follow' =>
      copy.text(
        'Unlock Creator Studio; age confirmation and opt-in enable Follow',
        'Odblokuj Studio twórcy; potwierdzenie wieku i zgoda włączają Obserwuj',
      ),
    'After Servers launch, Free includes 5; joining stays unlimited for everyone' =>
      copy.text(
        'After Servers launch, Free includes 5; joining stays unlimited for everyone',
        'Po uruchomieniu Serwerów konto bezpłatne obejmuje 5; każdy dołącza bez limitu',
      ),
    'Badge, shimmer, privacy controls and a modest Yeels boost' => copy.text(
      'Badge, shimmer, privacy controls and a modest Yeels boost',
      'Odznaka, połysk, ustawienia prywatności i umiarkowane wsparcie rekomendacji w Yeels',
    ),
    _ => copy.text(benefit.$2, 'Więcej możliwości w YO Voice'),
  };
  return (title, subtitle);
}

String localizedPremiumChecklistItem(
  AppLocalizations copy,
  String item,
) => switch (item) {
  'Creator access' => copy.text('Creator access', 'Dostęp do funkcji twórcy'),
  'Audience tools' => copy.text('Audience tools', 'Narzędzia dla publiczności'),
  'Premium profile appearance' => copy.text(
    'Premium profile appearance',
    'Wygląd profilu Premium',
  ),
  'Up to 30 Servers after launch' => copy.text(
    'Up to 30 Servers after launch',
    'Do 30 serwerów po uruchomieniu',
  ),
  'Privacy controls' => copy.text('Privacy controls', 'Ustawienia prywatności'),
  'Yeels discovery boost' => copy.text(
    'Yeels discovery boost',
    'Wsparcie rekomendacji w Yeels',
  ),
  'Exclusive features' => copy.text(
    'Exclusive features',
    'Ekskluzywne funkcje',
  ),
  _ => copy.text(item, 'Funkcja Premium'),
};

String localizedPremiumIncludedItem(
  AppLocalizations copy,
  String item,
) => switch (item) {
  'Creator account and Studio; age confirmation and opt-in enable Follow' =>
    copy.text(
      'Creator account and Studio; age confirmation and opt-in enable Follow',
      'Konto twórcy i Studio; potwierdzenie wieku oraz zgoda włączają przycisk Obserwuj',
    ),
  'After Servers launch: up to 30 owned Servers (Free: 5); unlimited joins for everyone' =>
    copy.text(
      'After Servers launch: up to 30 owned Servers (Free: 5); unlimited joins for everyone',
      'Po uruchomieniu Serwerów: do 30 własnych serwerów (bezpłatnie: 5); dołączanie bez limitu dla każdego',
    ),
  'In private chats, Incognito hides read receipts; typing visibility is separate' =>
    copy.text(
      'In private chats, Incognito hides read receipts; typing visibility is separate',
      'W prywatnych czatach tryb incognito ukrywa potwierdzenia odczytu; wskaźnik pisania ustawiasz osobno',
    ),
  'Premium badge and shimmering profile ring' => copy.text(
    'Premium badge and shimmering profile ring',
    'Odznaka Premium i połyskujący pierścień profilu',
  ),
  'Modest Yeels recommendation boost; reach is never guaranteed' => copy.text(
    'Modest Yeels recommendation boost; reach is never guaranteed',
    'Umiarkowane wsparcie rekomendacji w Yeels; zasięg nie jest gwarantowany',
  ),
  'Creator profile & tools' => copy.text(
    'Creator profile & tools',
    'Profil i narzędzia twórcy',
  ),
  'Verified audience tools' => copy.text(
    'Verified audience tools',
    'Zweryfikowane narzędzia dla publiczności',
  ),
  'Premium presence in conversations' => copy.text(
    'Premium presence in conversations',
    'Obecność Premium w rozmowach',
  ),
  'More benefits coming soon' => copy.text(
    'More benefits coming soon',
    'Wkrótce więcej korzyści',
  ),
  _ => copy.text(item, 'Korzyść Premium'),
};
