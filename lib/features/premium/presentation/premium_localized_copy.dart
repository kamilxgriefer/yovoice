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
    'Become a Creator' => copy.text('Become a Creator', 'Zostań twórcą'),
    'Create your own Clubs' => copy.text(
      'Create your own Clubs',
      'Twórz własne kluby',
    ),
    'Stand out' => copy.text('Stand out', 'Wyróżnij się'),
    _ => copy.text(benefit.$1, 'Korzyść Premium'),
  };
  final subtitle = switch (benefit.$2) {
    'Unlock real Creator tools' => copy.text(
      'Unlock real Creator tools',
      'Odblokuj pełne narzędzia twórcy',
    ),
    'Build spaces for your people' => copy.text(
      'Build spaces for your people',
      'Buduj miejsca dla swojej społeczności',
    ),
    'Premium look across YO Voice' => copy.text(
      'Premium look across YO Voice',
      'Wygląd Premium w całym YO Voice',
    ),
    _ => copy.text(benefit.$2, 'Więcej możliwości w YO Voice'),
  };
  return (title, subtitle);
}

String localizedPremiumChecklistItem(AppLocalizations copy, String item) =>
    switch (item) {
      'Creator access' => copy.text(
        'Creator access',
        'Dostęp do funkcji twórcy',
      ),
      'Create Clubs' => copy.text('Create Clubs', 'Tworzenie klubów'),
      'Premium identity' => copy.text('Premium identity', 'Tożsamość Premium'),
      'Exclusive features' => copy.text(
        'Exclusive features',
        'Ekskluzywne funkcje',
      ),
      _ => copy.text(item, 'Funkcja Premium'),
    };

String localizedPremiumIncludedItem(AppLocalizations copy, String item) =>
    switch (item) {
      'Creator profile & tools' => copy.text(
        'Creator profile & tools',
        'Profil i narzędzia twórcy',
      ),
      'Club creation (up to 3 clubs)' => copy.text(
        'Club creation (up to 3 clubs)',
        'Tworzenie klubów (maksymalnie 3)',
      ),
      'Premium presence in rooms' => copy.text(
        'Premium presence in rooms',
        'Obecność Premium w pokojach',
      ),
      'More benefits coming soon' => copy.text(
        'More benefits coming soon',
        'Wkrótce więcej korzyści',
      ),
      _ => copy.text(item, 'Korzyść Premium'),
    };
