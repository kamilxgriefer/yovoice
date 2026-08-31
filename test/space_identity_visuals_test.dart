import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/space_identity.dart';

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
  group('normal-route SpaceIdentity visuals', () {
    for (final brightness in Brightness.values) {
      final palette = brightness == Brightness.dark
          ? AppPalette.dark
          : AppPalette.light;

      for (final identity in const [SpaceIdentity.club, SpaceIdentity.family]) {
        test(
          '${identity.kind.name} ${brightness.name} pairs meet contrast',
          () {
            final visuals = identity.resolve(brightness);

            expect(
              _contrastRatio(visuals.onSurface, visuals.surface),
              greaterThanOrEqualTo(4.5),
              reason: 'identity content on its tonal surface',
            );
            expect(
              _contrastRatio(visuals.border, visuals.surface),
              greaterThanOrEqualTo(3),
              reason: 'identity container boundary',
            );
            expect(
              _contrastRatio(visuals.border, palette.background),
              greaterThanOrEqualTo(3),
              reason: 'identity boundary against the app canvas',
            );
            for (final surface in [
              palette.background,
              palette.surface,
              palette.surfaceRaised,
            ]) {
              expect(
                _contrastRatio(visuals.foreground, surface),
                greaterThanOrEqualTo(4.5),
                reason: 'identity copy on a semantic app surface',
              );
            }
            expect(
              _contrastRatio(visuals.onCta, visuals.cta),
              greaterThanOrEqualTo(4.5),
              reason: 'primary action label',
            );
            expect(visuals.spinner, visuals.onCta);
            for (final endpoint in visuals.heroGradient.colors) {
              expect(
                _contrastRatio(visuals.heroForeground, endpoint),
                greaterThanOrEqualTo(4.5),
                reason: 'hero label across every gradient endpoint',
              );
            }
          },
        );
      }
    }

    test('Club and Family remain visually distinct in both themes', () {
      for (final brightness in Brightness.values) {
        final club = SpaceIdentity.club.resolve(brightness);
        final family = SpaceIdentity.family.resolve(brightness);

        expect(club.foreground, isNot(family.foreground));
        expect(club.surface, isNot(family.surface));
        expect(club.cta, isNot(family.cta));
      }
    });
  });
}
