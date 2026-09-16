# YoVoice responsive authentication — engineering handoff

## 1. Intent and source of truth

Redesign the existing Flutter authentication presentation without changing
authentication behavior. The visual source is the dark YoVoice panel shown in
`voice-curtain-preview.html`, `voice-curtain-preview.png`, and
`voice-curtain-preview.webm`. The separate wide-layout implementation is shown
in `desktop-split-preview.html`, `desktop-split-preview.png`, and
`desktop-split-preview.webm`. The supplied desktop recording at
`/Users/kamil/Downloads/ScreenRecording_08-29-2026 22-37-20_1.MP4` is a motion
reference only.

Two deliberately different motion systems are required:

- **Compact and medium single-column layouts:** subtle **Voice Relay**. The
  selected capsule stays inside its 52 px rail; it never grows into a curtain.
- **Wide desktop layout:** separate 50/50 sliding brand panel. The moving panel
  is clipped to the authentication workspace and never covers the whole app or
  viewport.

Do not embed the HTML, PNG, WebM, or reference MP4 in the shipped interface.
Rebuild the design with Flutter widgets and canonical project assets.

## 2. Existing product behavior that must survive

Preserve all current behavior from `LoginScreen`, `RegisterScreen`,
`ForgotPasswordScreen`, `VerifyEmailScreen`, `TotpChallengeScreen`,
`AuthService`, `AuthSocialButton`, and localization:

- email/password login;
- username, email, password, and password-confirmation registration;
- existing username and password validation;
- Google sign-in;
- Apple sign-in availability, loading, temporary-unavailable, and
  not-configured states;
- forgot-password flow;
- email-verification flow after registration;
- Firebase multi-factor/TOTP challenge handling;
- loading locks, error messages, autofill, submit actions, and controller
  disposal;
- current English and Polish copy paths.

Never simulate a successful login or registration. Do not change Firebase,
backend, security, legal, routing, or provider configuration merely to achieve
the visual effect.

## 3. Responsive layout contract

Choose the variant from the **usable width inside safe areas**, not from a
hard-coded device model. Do not scale the entire interface to make it fit.

| Variant | Usable width | Layout and motion |
| --- | ---: | --- |
| Compact | `< 600 dp` | One centered form card, max width 430 dp. Voice Relay. Vertical scrolling is allowed and expected. |
| Medium | `600–999 dp` | One centered form card, max width 560 dp, with more breathing room. Voice Relay. Never use the desktop curtain. |
| Wide desktop | `>= 1000 dp` and each pane can remain `>= 440 dp` | Centered two-column workspace, 50/50 split, separate sliding brand-panel transition. |

If a nominally wide window cannot provide two 440 dp panes after safe-area and
workspace padding, fall back to Medium. Re-evaluate on window resize. Preserve
the active auth mode and typed values when crossing a breakpoint; do not play a
mode-change animation merely because the window resized.

### Compact

- Page minimum size: `min-height: viewport`, but content height is allowed to
  exceed it.
- Safe-area padding: top/bottom `max(16 dp, safe-area inset)`; horizontal
  `max(16 dp, safe-area inset)`.
- At 320–339 dp, horizontal page padding may reduce to 10–12 dp, but control
  padding and touch targets must not shrink.
- Brand stage: transparent canonical logo 72 dp in normal portrait; 56 dp when
  available height is below 700 dp. Wordmark and tagline remain centered.
- Gap from brand stage to card: 12 dp normal, 8 dp in short-height mode.
- Card: width fills available content up to 430 dp; radius 28 dp; 1 dp border.
  Its height is content-driven. Never use fixed 590/680 dp production heights.
- Internal horizontal padding: 20 dp; 16 dp at 320–339 dp.
- Mode rail: 52 dp high, radius 18 dp, full content width.
- Selected capsule: exactly half the rail width. Its travel is exactly one
  half-rail (`Alignment.centerLeft` to `Alignment.centerRight`, or 100% of its
  own width). No constants derived from the 430 px film.
- Fields: minimum 52 dp high. Provider buttons: minimum 48 dp. Primary CTA:
  54 dp. Every link, eye icon, and icon button has a 48×48 dp interactive
  wrapper even if the visible glyph is smaller.
- At 320–339 dp, the Apple availability badge may move below the provider copy
  within a taller provider row; it must never overlap or truncate the label.

### Medium

- Center the single card in the viewport with page padding 32 dp and max card
  width 560 dp.
- Keep the same hierarchy and Voice Relay. Do not enlarge the logo above 88 dp
  or stretch fields edge-to-edge across the whole screen.
- Registration and keyboard states remain vertically scrollable.

### Wide desktop

- Outer workspace max width: 1180 dp; minimum usable height: 620 dp; page
  padding 40 dp horizontal and 32 dp vertical.
- Workspace radius: 32 dp. Clip all moving material, shadows, and glints to this
  shape.
- Two equal panes. Each pane uses 48 dp internal padding and supports its own
  vertical scroll when height is constrained or text scale is large.
- Login resting state: YoVoice brand/story panel on the left, login form on the
  right.
- Create-account resting state: registration form on the left, brand/story
  panel on the right.
- The transparent canonical logo sits directly on the brand material. Never
  add a black disc, bezel, tile, or fake replacement logo behind it.
- Below the wide breakpoint, discard the two-column geometry immediately and
  render the single-column variant. Do not squeeze the panes.

## 4. Visual tokens

Prefer existing project tokens where an equivalent already exists. If the auth
feature needs scoped aliases, define them once; do not scatter literals across
widgets.

| Token | Value | Use |
| --- | --- | --- |
| `authCanvasTop` | `#130A22` | top radial field |
| `authCanvasBase` | `#080711` | page base |
| `authSurface` | `#12101D` | card base |
| `authSurfaceRaised` | `#20182A` | provider and selected surfaces |
| `authSurfaceMuted` | `#1A1424` | fields |
| `authBorder` | `#30263F` | default borders |
| `authBorderStrong` | `#7C6790` | focused/raised borders at controlled opacity |
| `authText` | `#F8F5FC` | primary text |
| `authTextSecondary` | `#B8AFC2` | body and helper copy |
| `authTextTertiary` | `#958B9F` | inactive and metadata copy |
| `authPrimary` | `#7B2FF7` | gradient start/brand response |
| `authSecondary` | `#C026FF` | gradient end/brand response |
| `authFocus` | `#D986FF` | focus and inline links |
| `authAccent` | `#5CE1E6` | very restrained voice accent/focus companion |
| `authDanger` | `#FF7B88` | validation errors |
| `authSuccess` | `#35D07F` | confirmed success only |

Use the existing Inter family. Production minimums: field/control copy 14–16
sp, labels and helper copy 12 sp, primary heading 26–30 sp depending on
available width. Support text scale to 2.0 without clipping.

Canonical assets:

- `assets/images/yo-voice-favicon-512.png` or the equivalent transparent
  canonical YoVoice symbol already declared in `pubspec.yaml`;
- `assets/icons/icon_google_g.svg` for Google;
- the existing platform-aware Apple treatment and availability logic.

Do not use `assets/images/yo_voice_logo_reference.png` for the new header if it
contains a baked background or oversized whitespace.

## 5. Compact and medium motion: Voice Relay

Animate only after the user deliberately chooses the other mode. Do not
autoplay in production.

Total interaction budget: **520 ms**.

| Time | Element | Behavior |
| ---: | --- | --- |
| `0–80 ms` | pressed mode | restrained press response; no page movement |
| `80–247 ms` | outgoing form | opacity `1 → 0.42`; horizontal offset `0 → 6 dp` away from the destination |
| `80–413 ms` | selected capsule | glide exactly one half-rail; `easeInOutCubic`/equivalent smooth cubic; optional max 5.5% horizontal compression at midpoint |
| `80–413 ms` | card | content-driven `AnimatedSize`; clip during the morph; no fixed endpoint heights |
| `247 ms` | logical mode | atomic swap at capsule midpoint; outgoing semantics off, incoming semantics on; incoming form starts at opacity `0.42` and offset `8 dp` |
| `247–447 ms` | incoming form | opacity `0.42 → 1`; offset `8 → 0 dp` |
| `447–520 ms` | selector/aura | settle only; tiny voice bars and aura may peak at midpoint then return to rest |

The form swap must never create a blank frame or make the UI resemble a
disabled screen. Do not overlap two focusable forms. During the full 520 ms,
block repeated mode taps and form submission. The active capsule remains
inside the rail at all times.

Forward and reverse use the same timing. Motion direction mirrors the selected
destination. Background arcs may drift ambiently but must not react with large
parallax, flashes, or full-surface wipes.

## 6. Wide desktop motion: split brand panel

This is the only variant allowed to use the stronger supplied-reference
effect. It is not a scaled-up Voice Relay and must live in a separate layout
implementation.

Total interaction budget: **760 ms**.

| Time | Element | Behavior |
| ---: | --- | --- |
| `0–80 ms` | trigger | press/hover settles; lock further mode changes |
| `80–620 ms` | brand panel | translate from one half to the other inside the clipped workspace; use a smooth emphasized curve close to `cubic-bezier(.22, 1, .36, 1)` |
| `80–260 ms` | outgoing form | fade and move 16 dp away from its destination |
| `350 ms` | logical mode | swap only when the moving brand panel covers the workspace seam and hides the content replacement |
| `400–650 ms` | incoming form | fade and move 16 dp into place |
| `650–760 ms` | material/shadow | settle without bounce; restore pointer and keyboard interaction |

The moving layer is opaque enough to conceal the content swap but retains the
YoVoice plum/violet material, transparent logo, subtle voice lines, and soft
depth. No fake screenshots, no black logo disc, no whole-screen wipe, and no
spring overshoot.

Desktop hover and keyboard focus states must be independent of the travel
animation. Tab/Shift+Tab focus order always follows the currently active form.

## 7. Reduced motion and accessibility

- Respect Flutter's `MediaQuery.disableAnimations` and platform accessibility
  settings.
- Reduced-motion mode: no translation, capsule compression, card height tween,
  glint, or drifting reaction. Change mode atomically with a maximum 120 ms
  opacity crossfade, or instantly when necessary.
- The mode control is a real two-option selector. Announce `Log in, selected`
  and `Create account, selected`; expose selected state and 48 dp targets.
- Decorative logo glow, waves, voice arcs, and glints are excluded from
  semantics.
- While switching, use one modal semantics state: the inactive form is hidden
  from semantics and cannot receive focus or pointer events. Announce the new
  heading after the atomic swap without announcing every animation frame.
- Preserve visible focus indicators with at least 3:1 contrast.
- Error text is associated with its field and announced once. Do not rely on
  color alone.
- Keep logical traversal order: mode selector, social providers, email fields,
  helper/forgot link, primary CTA, switch-mode link.

## 8. Keyboard, safe areas, and scrolling

- Build the page with `SafeArea`, `LayoutBuilder`, and a vertical scrollable;
  do not use absolute Y positions for the production form.
- Apply animated bottom padding from `MediaQuery.viewInsets.bottom`.
- When the keyboard opens or validation inserts text, ensure the focused field
  and its error remain visible (`Scrollable.ensureVisible` or equivalent).
- Dismissing the keyboard must not reset mode or form values.
- On compact landscape, keep a single column and scroll; never activate the
  desktop panel solely because the raw landscape width crossed a number while
  usable pane widths/heights are inadequate.
- Avoid nested primary scroll views. Wide desktop may use one scroll controller
  per form pane only because the outer workspace itself remains fixed.

## 9. Component and state model

Prefer a shared presentation layer rather than two competing visual systems:

- `AuthMode { login, register }`;
- one responsive auth shell that selects Compact/Medium/Wide from constraints;
- a reusable mobile/medium `AuthModeRail`;
- a separate wide `AuthDesktopSplitShell`;
- extracted login and registration form bodies that keep their existing auth
  callbacks and validation;
- compatibility wrappers for current routes if tests or app entry points still
  refer to `LoginScreen` and `RegisterScreen`.

Keep form controllers/state alive across a mode animation. If the current
route architecture makes a shared shell unsafe, make the smallest refactor
that preserves back navigation, Android predictive back, iOS swipe-back, MFA,
and verification routing. Do not solve motion by duplicating `AuthService` or
creating a second authentication flow.

Required states for every actionable control: default, hover where supported,
focus, pressed, loading, disabled, validation error, and provider unavailable.
Long localized copy wraps; it does not ellipsize critical authentication or
legal text.

## 10. Verification matrix

Visually inspect and add targeted widget/golden coverage for at least:

- 320×568, text scale 1.0 and 2.0;
- 390×667 and 430×844;
- compact landscape with keyboard open;
- 600×960 and 834×1112 Medium layouts;
- 999×800 fallback Medium;
- 1000×700 and 1440×900 Wide layouts;
- both auth modes, forward/reverse transition, loading, disabled Apple,
  validation errors, Google error, MFA challenge route, and verify-email route;
- reduced motion;
- window resize across both breakpoints while fields contain text.

Acceptance criteria:

1. No yellow/black overflow stripes, clipping, hidden focused field, or overlap
   at any matrix size.
2. Compact/Medium never shows a full-card or full-screen curtain.
3. Wide desktop is a real 50/50 split transition and remains clipped to the
   rounded workspace.
4. No fixed capsule travel distance; selection is correct at every width.
5. No blank or disabled-looking frame during the mode swap.
6. All current authentication, MFA, verification, provider, validation,
   localization, and back-navigation tests continue to pass.
7. `flutter analyze` and the targeted auth/widget tests pass with no new
   warnings.

The design is complete only after real-device/emulator screenshots have been
reviewed at the smallest compact size, a representative phone, Medium, and
Wide—not merely after the widgets compile.
