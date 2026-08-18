/// Shared Premium capability copy. Prices and product identifiers are never
/// kept in the client; they come from the trusted billing context at runtime.
class PremiumPlans {
  PremiumPlans._();

  /// The three benefit cards on the Premium presentation screen — one
  /// place, so copy can't drift between the app and the marketing site.
  static const List<(String, String)> benefits = [
    ('Become a Creator', 'Unlock real Creator tools'),
    ('Create your own Clubs', 'Build spaces for your people'),
    ('Stand out', 'Premium look across YO Voice'),
  ];

  /// The short per-plan checklist on the plans screen. Identical for both
  /// plans on purpose — the plans differ in billing, not capabilities.
  static const List<String> planChecklist = [
    'Creator access',
    'Create Clubs',
    'Premium identity',
    'Exclusive features',
  ];

  /// The "Everything Premium includes" list on the plans screen.
  static const List<String> everythingIncluded = [
    'Creator profile & tools',
    'Club creation (up to 3 clubs)',
    'Premium presence in rooms',
    'More benefits coming soon',
  ];
}
