import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/discover/presentation/discover_category_identity.dart';

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + .05) / (darker + .05);
}

void main() {
  group('Discover category identity', () {
    const expectedSeeds = <String, Color>{
      'Talk': Color(0xFF9D20FF),
      'Chill': Color(0xFFA226FF),
      'Broadcast': Color(0xFFFF3F8E),
      'Music': Color(0xFFFFA63D),
      'Gaming': Color(0xFF4D8DFF),
      'Business': Color(0xFF3FD19B),
      'Study': Color(0xFF6E7CFF),
      'Tech': Color(0xFF37D6E8),
    };

    test('preserves stable branding seeds and category routing', () {
      expect({
        for (final identity in DiscoverCategoryIdentity.all)
          identity.label: identity.seed,
      }, expectedSeeds);
      expect(
        DiscoverCategoryIdentity.forCategory('music production'),
        same(DiscoverCategoryIdentity.music),
      );
      expect(
        DiscoverCategoryIdentity.forCategory('business'),
        same(DiscoverCategoryIdentity.business),
      );
      expect(
        DiscoverCategoryIdentity.forCategory('talk', isBroadcast: true),
        same(DiscoverCategoryIdentity.broadcast),
      );
      expect(
        DiscoverCategoryIdentity.forCategory('uncategorized'),
        same(DiscoverCategoryIdentity.talk),
      );

      for (final identity in const [
        DiscoverCategoryIdentity.broadcast,
        DiscoverCategoryIdentity.music,
        DiscoverCategoryIdentity.business,
      ]) {
        expect(
          identity.resolve(Brightness.light).foreground,
          isNot(identity.seed),
          reason:
              '${identity.label} must not reuse its bright seed as Pearl ink',
        );
      }
    });

    for (final brightness in Brightness.values) {
      final palette = brightness == Brightness.dark
          ? AppPalette.dark
          : AppPalette.light;

      for (final identity in DiscoverCategoryIdentity.all) {
        test('${identity.label} ${brightness.name} roles meet WCAG AA', () {
          final visuals = identity.resolve(brightness);

          expect(
            _contrastRatio(visuals.onSurface, visuals.surface),
            greaterThanOrEqualTo(4.5),
            reason: '${identity.label} badge text on its tonal surface',
          );
          expect(
            _contrastRatio(visuals.onSurface, visuals.surface),
            greaterThanOrEqualTo(3),
            reason: '${identity.label} meaningful icon on its tonal surface',
          );
          expect(
            _contrastRatio(visuals.border, visuals.surface),
            greaterThanOrEqualTo(3),
            reason: '${identity.label} category boundary',
          );
          expect(
            _contrastRatio(visuals.border, palette.background),
            greaterThanOrEqualTo(3),
            reason: '${identity.label} boundary against the app canvas',
          );
          for (final surface in [
            palette.background,
            palette.surface,
            palette.surfaceRaised,
          ]) {
            expect(
              _contrastRatio(visuals.foreground, surface),
              greaterThanOrEqualTo(4.5),
              reason: '${identity.label} compact copy on a semantic surface',
            );
          }
          expect(
            _contrastRatio(visuals.onAction, visuals.action),
            greaterThanOrEqualTo(4.5),
            reason: '${identity.label} action label',
          );
        });
      }
    }
  });
}
