import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';

Color reelOverlayColor(ReelOverlayColor color) => switch (color) {
  ReelOverlayColor.light => Colors.white,
  ReelOverlayColor.dark => const Color(0xFF17121F),
  ReelOverlayColor.accent => const Color(0xFFE18CFF),
  ReelOverlayColor.cyan => AppColors.accent,
};

/// A media-independent surface/foreground pair keeps custom overlays legible
/// over both the brightest photo and a near-black video frame.
Color reelTextOverlaySurface(ReelOverlayColor color) {
  final foreground = reelOverlayColor(color);
  return foreground.computeLuminance() < .25
      ? const Color(0xF2FFFFFF)
      : const Color(0xEB191022);
}

Color reelTextOverlayOutline(ReelOverlayColor color) {
  final foreground = reelOverlayColor(color);
  return foreground.computeLuminance() < .25
      ? const Color(0xFF4B3659)
      : const Color(0xFFE8C5FF);
}

const Color reelLinkOverlaySurface = Color(0xF221162B);
const Color reelLinkOverlayForeground = Color(0xFFFFFFFF);
const Color reelLinkOverlayOutline = Color(0xFFD986FF);

String localizedReelFilter(AppLocalizations copy, ReelFilter filter) =>
    switch (filter) {
      ReelFilter.original => copy.text('Original', 'Oryginalny'),
      ReelFilter.vivid => copy.text('Vivid', 'Żywy'),
      ReelFilter.warm => copy.text('Warm', 'Ciepły'),
      ReelFilter.cool => copy.text('Cool', 'Chłodny'),
      ReelFilter.monochrome => copy.text('Mono', 'Czarno-biały'),
    };

String localizedReelOverlayColor(
  AppLocalizations copy,
  ReelOverlayColor color,
) => switch (color) {
  ReelOverlayColor.light => copy.text('Light', 'Jasny'),
  ReelOverlayColor.dark => copy.text('Dark', 'Ciemny'),
  ReelOverlayColor.accent => copy.text('Violet', 'Fioletowy'),
  ReelOverlayColor.cyan => copy.text('Cyan', 'Turkusowy'),
};

List<double> reelFilterMatrix(ReelFilter filter) {
  return switch (filter) {
    ReelFilter.original => const <double>[
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ],
    ReelFilter.vivid => const <double>[
      1.18,
      -.08,
      -.08,
      0,
      4,
      -.08,
      1.18,
      -.08,
      0,
      4,
      -.08,
      -.08,
      1.18,
      0,
      4,
      0,
      0,
      0,
      1,
      0,
    ],
    ReelFilter.warm => const <double>[
      1.12,
      0,
      0,
      0,
      9,
      0,
      1.02,
      0,
      0,
      3,
      0,
      0,
      .9,
      0,
      -3,
      0,
      0,
      0,
      1,
      0,
    ],
    ReelFilter.cool => const <double>[
      .92,
      0,
      0,
      0,
      -2,
      0,
      1.02,
      0,
      0,
      2,
      0,
      0,
      1.12,
      0,
      8,
      0,
      0,
      0,
      1,
      0,
    ],
    ReelFilter.monochrome => const <double>[
      .2126,
      .7152,
      .0722,
      0,
      0,
      .2126,
      .7152,
      .0722,
      0,
      0,
      .2126,
      .7152,
      .0722,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ],
  };
}
