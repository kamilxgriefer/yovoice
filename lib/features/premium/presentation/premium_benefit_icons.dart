import 'package:flutter/material.dart';

/// Which Premium benefit card a title names. Surfaces choose the card's
/// glyph and tint from this, keyed on the (English, catalog) title in
/// `PremiumPlans.benefits` — never on the card's position — so adding,
/// removing or reordering a card cannot throw a RangeError on a parallel
/// icon list.
enum PremiumBenefitKind { creator, servers, presence, other }

PremiumBenefitKind premiumBenefitKind(String title) => switch (title) {
  'Creator account & studio' => PremiumBenefitKind.creator,
  'Up to 30 Servers' => PremiumBenefitKind.servers,
  'Premium presence & privacy' => PremiumBenefitKind.presence,
  _ => PremiumBenefitKind.other,
};

/// The benefit card glyph for [title]; an unknown title gets the generic
/// Premium sparkle rather than an error.
IconData premiumBenefitIcon(String title) =>
    switch (premiumBenefitKind(title)) {
      PremiumBenefitKind.creator => Icons.mic_rounded,
      PremiumBenefitKind.servers => Icons.workspace_premium_rounded,
      PremiumBenefitKind.presence => Icons.auto_awesome_rounded,
      PremiumBenefitKind.other => Icons.auto_awesome_rounded,
    };

/// The glyph beside one "Everything Premium includes" line, keyed on the
/// line's text (`PremiumPlans.everythingIncluded`), with a fallback.
IconData premiumIncludedItemIcon(String item) => switch (item) {
  'Creator account and Studio; age confirmation and opt-in enable Follow' =>
    Icons.person_outline_rounded,
  'Up to 30 owned Servers (Free: 5); unlimited joins for everyone' =>
    Icons.dns_outlined,
  'In private chats, Incognito hides read receipts; typing visibility is separate' =>
    Icons.visibility_off_outlined,
  'Premium badge and shimmering profile ring' =>
    Icons.workspace_premium_outlined,
  'Modest Yeels recommendation boost; reach is never guaranteed' =>
    Icons.graphic_eq_rounded,
  'See who liked Voice Moments, Yeels, comments and Server messages' =>
    Icons.favorite_border_rounded,
  'More benefits coming soon' => Icons.auto_awesome_outlined,
  _ => Icons.auto_awesome_outlined,
};
