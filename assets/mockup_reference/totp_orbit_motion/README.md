# YoVoice Voice Constellation references

This folder contains an original YoVoice motion-design handoff for the
six-digit authenticator challenge. The supplied screen recording was used only
to understand the broad interaction idea; none of its TikTok chrome, branding,
copy, code or exact four-digit choreography is reproduced here. The YoVoice
version turns the six digits into a gently swaying voice constellation, then a
six-bar waveform, and finally a success badge.

## Files

- `totp-orbit-storyboard.svg` — scalable six-state visual storyboard.
- `totp-orbit-storyboard.png` — rendered review copy of the same board.
- `voice-constellation-motion-preview.html` — looping, click-to-replay motion
  prototype for visual-quality review; documentation only. It computes the
  breakpoint from the motion component's post-padding width and becomes truly
  static when the browser requests reduced motion.
- `voice-constellation-motion-preview.webm` — one recorded review loop of the
  prototype, convenient for direct playback; documentation only.
- `motion-tokens.json` — exact geometry, colour, timing and reduced-motion
  values for engineering handoff. It is documentation, not a runtime asset.

## Runtime asset decision

The top brand mark must reuse the existing canonical transparent in-app logo,
`assets/images/yo-voice-favicon-512.png`. Do not redraw, recolour, crop or
replace it with a generic security icon. This asset is already covered by the
app's `assets/images/` bundle.

The production implementation should add **no new image, SVG, Lottie or Rive
runtime dependency**. Apart from that existing logo, the six cells, dotted
orbit, check mark and transitions are simple Flutter geometry and should be
rendered with Material widgets, `Stack`, `Transform`, `AnimationController`
and small `CustomPainter`s.

The storyboard is deliberately non-production and should not be registered in
`pubspec.yaml`. Runtime colours must come from `AppPalette`, `ThemeData` and
the canonical YoVoice brand tokens rather than from the hexadecimal review
values in these files. The current Firebase TOTP resolver remains the only
authority for success; the animation must never predict acceptance.
