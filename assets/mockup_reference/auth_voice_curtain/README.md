# YO Voice responsive authentication motion concept

Documentation-only visual concept for the responsive transition between the
existing Log in and Create account flows. The mobile/tablet motion is named
**Voice Relay**: the selector capsule glides within its rail while the card and
form content change gently. It never becomes a full-card curtain.

- `voice-curtain-preview.webm` — final 430×844, 30 fps, eight-second review
  loop.
- `voice-curtain-preview.png` — representative Create account frame.
- `voice-curtain-preview.html` — interactive source; click the canvas or replay
  control to restart.
- `render_voice_curtain.mjs` — deterministic local frame renderer used for
  visual QA and the review export.
- `desktop-split-preview.webm` — separate 1440×900, 30 fps desktop 50/50
  review loop.
- `desktop-split-preview.png` — representative desktop Create account state.
- `desktop-split-preview.html` — interactive wide-layout source.
- `render_desktop_split.mjs` — deterministic desktop renderer and wide-layout
  QA checks.

The eight-second loop is a review presentation. Production must animate only
after a deliberate user action and must provide a reduced-motion path. The
highlight is percentage-based rather than tied to the 430 px capture, and the
interactive preview scrolls instead of clipping on short viewports.

The supplied 50/50 sliding-panel reference is intentionally reserved for the
wide desktop layout. It is a separate clipped two-column transition, not the
mobile animation. Exact breakpoints, geometry, motion timing, accessibility,
keyboard behavior and verification criteria are documented in
`responsive-auth-motion-handoff.md`.

The preview uses the canonical transparent
`assets/images/yo-voice-favicon-512.png`, the real Google provider asset and
the product's Inter font. Apple is deliberately shown as `Coming soon`,
matching the existing not-configured state. No login, registration, email
verification or backend success is simulated. The Flutter authentication code
is not modified by this concept.
