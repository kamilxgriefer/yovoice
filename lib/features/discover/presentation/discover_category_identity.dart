import 'package:flutter/material.dart';

/// Stable Discover category seed plus a brightness-aware presentation layer.
///
/// The seed is category branding and may be used for decorative glows or
/// low-opacity artwork tint. Normal-route text, meaningful icons, boundaries,
/// badges and actions must use [resolve] so Pearl never places a bright Dark
/// accent directly on a porcelain surface.
@immutable
class DiscoverCategoryIdentity {
  const DiscoverCategoryIdentity({required this.label, required this.seed});

  final String label;
  final Color seed;

  static const talk = DiscoverCategoryIdentity(
    label: 'Talk',
    seed: Color(0xFF9D20FF),
  );
  static const chill = DiscoverCategoryIdentity(
    label: 'Chill',
    seed: Color(0xFFA226FF),
  );
  static const broadcast = DiscoverCategoryIdentity(
    label: 'Broadcast',
    seed: Color(0xFFFF3F8E),
  );
  static const music = DiscoverCategoryIdentity(
    label: 'Music',
    seed: Color(0xFFFFA63D),
  );
  static const gaming = DiscoverCategoryIdentity(
    label: 'Gaming',
    seed: Color(0xFF4D8DFF),
  );
  static const business = DiscoverCategoryIdentity(
    label: 'Business',
    seed: Color(0xFF3FD19B),
  );
  static const study = DiscoverCategoryIdentity(
    label: 'Study',
    seed: Color(0xFF6E7CFF),
  );
  static const tech = DiscoverCategoryIdentity(
    label: 'Tech',
    seed: Color(0xFF37D6E8),
  );

  /// Every category family with a distinct stable seed. `All` resolves to the
  /// Talk/community family because it is a filter rather than room metadata.
  static const all = <DiscoverCategoryIdentity>[
    talk,
    chill,
    broadcast,
    music,
    gaming,
    business,
    study,
    tech,
  ];

  static DiscoverCategoryIdentity forCategory(
    String category, {
    bool isBroadcast = false,
  }) {
    if (isBroadcast) return broadcast;
    final normalized = category.trim().toLowerCase();
    if (normalized.contains('music')) return music;
    if (normalized.contains('gaming')) return gaming;
    if (normalized.contains('business')) return business;
    if (normalized.contains('study')) return study;
    if (normalized.contains('tech')) return tech;
    if (normalized.contains('chill')) return chill;
    return talk;
  }

  DiscoverCategoryVisuals resolve(Brightness brightness) =>
      DiscoverCategoryVisuals.fromSeed(seed, brightness);
}

/// Semantic category roles derived from one stable Discover seed.
@immutable
class DiscoverCategoryVisuals {
  const DiscoverCategoryVisuals._({
    required this.surface,
    required this.onSurface,
    required this.foreground,
    required this.border,
    required this.action,
    required this.onAction,
  });

  factory DiscoverCategoryVisuals.fromSeed(Color seed, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return DiscoverCategoryVisuals._(
      surface: scheme.primaryContainer,
      onSurface: scheme.onPrimaryContainer,
      foreground: scheme.primary,
      border: scheme.primary,
      action: scheme.primary,
      onAction: scheme.onPrimary,
    );
  }

  final Color surface;
  final Color onSurface;
  final Color foreground;
  final Color border;
  final Color action;
  final Color onAction;
}
