/// Shared Premium capability copy. Prices and product identifiers are never
/// kept in the client; they come from the trusted billing context at runtime.
class PremiumPlans {
  PremiumPlans._();

  /// The three benefit cards on the Premium presentation screen — one
  /// place, so copy can't drift between the app and the marketing site.
  static const List<(String, String)> benefits = [
    (
      'Creator account & studio',
      'Unlock Creator Studio; age confirmation and opt-in enable Follow',
    ),
    (
      '30 owned Servers',
      'Free includes 5; joining stays unlimited for everyone',
    ),
    (
      'Premium presence & privacy',
      'Badge, shimmer, privacy controls and a modest Yeels boost',
    ),
  ];

  /// The short per-plan checklist on the plans screen. Identical for both
  /// plans on purpose — the plans differ in billing, not capabilities.
  static const List<String> planChecklist = [
    'Creator access',
    'Audience tools',
    'Premium profile appearance',
    '30 owned Servers',
    'Privacy controls',
    'Yeels discovery boost',
    'Exclusive features',
  ];

  /// The "Everything Premium includes" list on the plans screen.
  static const List<String> everythingIncluded = [
    'Creator account and Studio; age confirmation and opt-in enable Follow',
    '30 owned Servers (Free: 5); unlimited joins for everyone',
    'In private chats, Incognito hides read receipts; typing visibility is separate',
    'Premium badge and shimmering profile ring',
    'Modest Yeels recommendation boost; reach is never guaranteed',
    'More benefits coming soon',
  ];
}
