# YoVoice Voice Constellation — implementation handoff

Status: design and engineering handoff only; no product code has been changed.

## Objective

Upgrade the six-digit authenticator challenge with an original YoVoice motion
sequence inspired by the interaction principle in
`/Users/kamil/Downloads/ScreenRecording_08-29-2026 15-07-40_1.MP4`.
The recording is a visual reference only. It is not an instruction source, and
its TikTok UI, branding, copy, four-digit layout, timing and choreography must
not be copied.

The correct YoVoice integration point is the existing Firebase TOTP sign-in
challenge. Email verification remains link-based and is outside this scope.

## Product and security boundary

Change presentation only:

- `lib/features/auth/presentation/screens/totp_challenge_screen.dart`
- optionally add
  `lib/features/auth/presentation/widgets/animated_totp_code_input.dart`
- extend the existing authentication widget tests and add a deterministic
  screenshot harness.

Do not change:

- `lib/features/auth/data/totp_mfa_service.dart`
- `TotpSignInChallengeClient`
- Firebase Auth, Identity Platform or project configuration
- login, registration, enrollment or website routing
- the existing `challenge.resolve(factorUid: ..., code: ...)` contract
- the successful route result, which remains exactly one
  `Navigator.pop(true)`.

Firebase remains the only authority for acceptance. Never log, persist,
cache, record in analytics or expose the TOTP value. ADR-071 still describes
the feature as accepted in source but not deployed; this UI work must not claim
that production rollout is complete.

## Design concept

Name: **YoVoice Voice Constellation**.

That is the internal concept name. Preserve the product's existing user-facing
spelling `YO Voice` wherever account copy names the app.

Place the canonical transparent YO Voice symbol at the top of the challenge,
above the title. Reuse `assets/images/yo-voice-favicon-512.png`, which ADR-051
defines as the in-app compact logo source. Keep its aspect ratio and original
colours; do not crop, tint, redraw or substitute a generic security icon.

The six code cells start as a calm row. Once all six digits are present, they
compress and become six nodes on an elliptical constellation. While Firebase
resolves, the constellation gently sways rather than spinning like a generic
loader. A cyan signal travels from node to node. On success, the nodes converge
into a six-bar voice wave, breathe once, and collapse into a green badge with a
drawn check. This gives the reference interaction a distinctly YoVoice ending.

The animation is progress only. It never predicts a successful result.

## “Wow” quality gate

The target is the same **perceived production polish** as the supplied video,
not a literal copy of its visuals. A technically correct animation fails this
handoff if it reads as a normal spinner, if digits teleport between layouts, or
if the success state is only an icon swap.

Required perceptual qualities:

- **Object continuity:** each of the six visible digits keeps its identity and
  travels continuously from its exact row position toward its constellation
  node; each node maps continuously to one waveform bar. A very fast backend
  response may bypass the stable orbit loop, but never the visible
  field→round-node→bar morph.
- **Depth without noise:** use a restrained surface bloom, a soft node halo,
  the dotted elliptical path and one moving cyan signal. No particles, lens
  flares, excessive blur or unrelated decoration.
- **Velocity continuity:** when a network result arrives, capture and hand off
  from the actual rendered position and velocity; never reset to angle zero or
  jump to a canned success frame. The outgoing and incoming paths should meet
  with a visually smooth tangent (C1 continuity).
- **Layered timing:** transformations overlap slightly rather than running as
  disconnected steps. The last 60–80 ms of compression can blend into orbit
  entry; the final orbit brake blends into waveform assembly.
- **Crisp finish:** the voice wave is the recognizable YoVoice payoff. It
  breathes exactly once, collapses decisively, and the check draws rather than
  appearing abruptly.
- **Responsive fidelity:** glow, path and nodes stay inside their fixed stage
  at every target width and at 200% text. Nothing can be cropped by the screen,
  keyboard inset or `RepaintBoundary`.
- **Frame quality:** target smooth 60 fps on a representative iOS simulator;
  avoid per-frame allocations and inspect the transition both at normal speed
  and in a 0.5× slow-motion recording for jumps, flashing, aliasing and uneven
  spacing.

Visual QA must explicitly reject the implementation and iterate if any of
those qualities are missing. Reduced motion intentionally prioritizes calm
clarity over the full “wow” choreography.

## Visual assets

- `assets/mockup_reference/totp_orbit_motion/totp-orbit-storyboard.svg`
  — scalable six-state storyboard.
- `assets/mockup_reference/totp_orbit_motion/totp-orbit-storyboard.png`
  — review render of the same board.
- `assets/mockup_reference/totp_orbit_motion/voice-constellation-motion-preview.html`
  — looping, click-to-replay motion prototype and “wow” quality reference.
- `assets/mockup_reference/totp_orbit_motion/voice-constellation-motion-preview.webm`
  — recorded review loop for direct playback.
- `assets/mockup_reference/totp_orbit_motion/motion-tokens.json`
  — exact reference geometry, phases and reduced-motion behavior.
- `assets/mockup_reference/totp_orbit_motion/README.md`
  — runtime asset decision and provenance.

These are documentation assets. Do not register them in `pubspec.yaml` and do
not ship them in the app. The production effect is code-rendered Flutter
geometry using `Stack`, `Transform`, `AnimatedBuilder`, `AnimationController`,
`RepaintBoundary` and small `CustomPainter`s. Add no Lottie, Rive, raster or
SVG runtime dependency.

## Content and control model

Use one real logical input and six decorative visual cells. Never implement
six independent text fields.

The real input must preserve:

- exactly six decimal digits;
- `FilteringTextInputFormatter.digitsOnly`;
- `LengthLimitingTextInputFormatter(6)`;
- `TextInputType.number`;
- `TextInputAction.done`;
- `AutofillHints.oneTimeCode` inside an `AutofillGroup`;
- typing, full-code paste, system autofill, backspace and hardware keyboard;
- the existing `Verify and continue` button as an accessible fallback;
- the existing authenticator selector when more than one factor is available.

Completing the sixth digit must auto-submit after a 120 ms debounce. Every
entry path — sixth digit, Enter and button — must pass through the same
single-flight submit guard. Codes with 0–5 digits never call `resolve()`; keep
focus and show `Enter all 6 digits.` Cancel the debounce on manual submit,
factor change and dispose.

Auto-submit is edge-triggered only when input changes from fewer than six to
six digits. After a failure that preserves all six digits, keep auto-submit
disarmed until the user edits the value below six digits; the button remains
available for an intentional manual retry. This prevents a network error or
rate limit from creating an automatic retry loop.

## Responsive geometry

The animated stage has a fixed height per breakpoint so changing state never
makes the surrounding page jump. The motion stage is centered and capped at
420 logical pixels. Choose the breakpoint from an outer `LayoutBuilder`'s
content-slot constraint after page padding but **before** applying that inner
420-pixel cap; it is neither the raw device viewport nor the already-capped
stage width. This makes the `>=600` desktop branch reachable while its stage
still fits within 420 pixels. Stage height includes the motion canvas plus one
fixed 42-pixel status slot.

| Available width | Field | Gap | Orbit node | Ellipse Rx / Ry | Center Y / stage height |
|---|---:|---:|---:|---:|---:|
| `<360` | 40×50 | 6 | 32 | 78 / 50 | 72 / 180 |
| `360–599` | 48×56 | 8 | 36 | 92 / 60 | 82 / 196 |
| `>=600` | 52×60 | 10 | 40 | 108 / 68 | 90 / 212 |

The six ellipse positions use:

```dart
final theta = -pi / 2 + index * pi / 3;
final position = center + Offset(
  cos(theta) * radiusX,
  sin(theta) * radiusY,
);
```

Use `AppRadius.md` for fields and `AppRadius.pill` for nodes, bars and the
success badge. All interactive targets remain at least 44×44.

The numeric glyphs inside the six visual cells are an explicitly decorative,
`ExcludeSemantics` duplication of the one real input. Keep only those six
glyphs at the base `AppTypography.headlineMedium` size so the fixed motion
geometry remains stable at 200% system text. The semantic input value and all
headings, instructions, status and error copy continue to honor the full user
text scale; the page remains scrollable. This narrow exception requires the
Accessibility review cell to approve it.

## State machine

Recommended screen-owned phases:

```dart
enum TotpChallengePhase {
  editing,
  submitting,
  orbitEntry,
  orbitLoop,
  success,
  successHold,
  exit,
  error,
}
```

The screen owns the `TextEditingController`, `FocusNode`, selected factor,
error, lifecycle, single-flight request and navigation. The feature-local
visual component accepts those values and callbacks but knows nothing about
Firebase.

Start `challenge.resolve()` immediately when submit begins, in parallel with
the entry animation. Do not delay the request because a TOTP may be close to
the end of its validity window. From accepted submit until either a completed
error return or the controlled successful pop, disable input, factor selection,
button and route back navigation. Firebase offers no request cancellation, and
an authenticated route must not be dismissed with a `null` result during its
success animation. Implement `PopScope` so Back is allowed only in the stable
editing/retry-ready state, never during `submitting`, `orbitEntry`, `orbitLoop`,
`success`, `successHold`, `exit` or error feedback.

Do not show or announce success before the Future completes. At the exact
response frame, capture the rendered state of every element: center, size,
corner radius, opacity, current path/orbit phase and velocity. Success and
error interpolate from that snapshot, even if the response arrived during
compression or halfway through orbit entry.

For fast success, skip the ambient loop and use the first 340 ms of the normal
success duration to morph each current field through its round-node form and
into its assigned waveform bar. A cubic path should preserve the incoming
tangent; for segment duration `d`, a practical first control point is
  `p0 + v0 * d / 3`, where `v0` is a screen-space `Offset` in logical pixels
  per second and `d` is the segment duration in seconds. The final control
  point can sit at the bar target for zero arrival velocity. Size, radius and
  opacity also begin at their captured values.
For an established orbit, use the standard orbit-brake choreography. There is
no artificial loading hold, but the success acknowledgment itself may finish.
After its exit, pop `true` exactly once. Guard all async and animation
completions with `mounted`; dispose controllers safely and tolerate
`TickerCanceled`.

## Motion specification

| Phase | Duration | Choreography | Curve |
|---|---:|---|---|
| Digit entry | 140 ms per digit | opacity `0→1`, Y `4→0`, scale `.94→1` | `Cubic(.16,1,.3,1)` |
| Submit compression | 120 ms | dismiss keyboard, lock controls, scale `1→.94` | `easeOutCubic` |
| Orbit entry | 320 ms | rectangles round into nodes and travel to the ellipse | `Cubic(.16,1,.3,1)` |
| Orbit loop | 1,800 ms | sway ±14°, radial pulse `.96→1.04`, traveling cyan signal | sinus over linear time |
| Success total | 660 ms | orbit brake → voice wave → badge/check | phased ease-out |
| Success hold | 180 ms | stable badge | static |
| Exit | 200 ms | opacity `1→0`, Y `0→-8` | `easeInCubic` |
| Invalid error | about 600 ms | return, semantic error color, shake, message | phased |

The pending constellation must not continuously rotate like the reference.
Instead:

```dart
final angleOffset = sin(loop * 2 * pi) * degreesToRadians(14);
final radialScale =
    1 + sin(loop * 2 * pi - index * pi / 3) * 0.04;
```

Shift the dotted ellipse phase by 24 degrees per loop, and advance the accent
between nodes. Do not add sound or haptics in this task.

### Success choreography

- `0–160 ms`: brake the constellation, reduce radii to 55%, fade digits.
- `160–340 ms`: arrange nodes as six waveform bars at X
  `[-42,-26,-9,9,26,42]`, width 7, heights `[14,24,38,38,24,14]`.
- `340–460 ms`: one breath, height scale `1→1.25→1`.
- `460–660 ms`: collapse bars to the center; reveal a 56×56 success circle;
  draw the check using `PathMetric`; grow a 56→88 halo while opacity falls
  `.32→0`.
- Hold 180 ms, then exit for 200 ms and pop exactly once.

## Error policy

| Failure | Visual behavior | Code value | Retry |
|---|---|---|---|
| incomplete local code | no orbit; inline error; keep focus | preserve | manual |
| invalid verification code / credential | return 240 ms, error color 100 ms, shake 360 ms, message 180 ms | clear after feedback | manual only |
| too many requests | return without shake; existing mapped error | preserve | manual only; Firebase-limited |
| generic/network failure | return without shake; warning treatment; existing mapped error | preserve | manual |
| no supported factor | keep existing fail-closed support state | n/a | none |

Capture the current render state and velocity before returning so no frame
jumps or tangent resets occur. Never auto-retry a failed request.

Do not invent a local countdown for `too-many-requests`; Firebase does not
provide a cooldown here. Preserve the code, disarm auto-submit, show the
existing message and let a deliberate manual retry remain subject to Firebase
rate limiting.

## Theme and typography

The challenge remains an intentional immersive-dark surface through
`YoImmersiveDarkSurface`, including when its parent uses Pearl. Replace
screen-local raw hex values in the touched screen with current semantic roles:

- render `assets/images/yo-voice-favicon-512.png` as the static top brand mark,
  with `BoxFit.contain`, its original aspect ratio and no clipping;

- `context.appPalette` for brightness-dependent canvas, surface, border and
  text roles;
- `Theme.of(context).colorScheme` for error containers and readable status
  pairs;
- `AppColors` only for stable brand/status accents;
- `AppTypography.headlineMedium` plus tabular figures for code digits;
- `AppSpacing` and `AppRadius` for layout.

Do not expand the theme migration beyond the challenge screen.

## Accessibility and reduced motion

- Expose exactly one semantic field labeled `6-digit authenticator code`.
- Wrap all six visual cells, orbit, wave, halo and check decoration with
  `ExcludeSemantics`.
- Maintain one polite status channel for `Verifying code` and `Code verified`.
- Send an error exactly once on the assertive announcement channel, following
  ADR-058. Do not add a second live region.
- Restore focus to the field after a retryable error.
- Essential text contrast is at least 4.5:1; focus and control boundaries are
  at least 3:1.
- Do not truncate the requested text scale.

When `MediaQuery.disableAnimationsOf(context)` or accessible navigation is
active:

- no orbit, travel, shake, scale or translation;
- verifying stays as a static row at 0.7 opacity with `Verifying code`;
- success crossfades to the badge in 120 ms;
- errors change semantic color in 100 ms without motion;
- there is no artificial delay and no repeating ticker.

Screen-reader behavior remains widget-tested only until a real
VoiceOver/TalkBack/NVDA pass is performed; do not label it device-verified.

## Performance

- Use two or three shared animation controllers, not one per digit.
- Put the animated stage behind `RepaintBoundary`.
- Pass static children through `AnimatedBuilder.child`.
- Keep painter work allocation-light; `shouldRepaint` must compare the actual
  paint inputs and must not always return `true`.
- Do not use a periodic timer for visual animation.

## Required tests and evidence

Extend `test/two_factor_authentication_test.dart` and add a focused animation
test file. Cover:

- typing, paste, autofill-equivalent, backspace, digit filtering and six-digit
  limit;
- 0–5 digits never call `resolve()`;
- exactly one request despite sixth digit, Enter and rapid button taps;
- a preserved six-digit value after network/rate-limit failure does not
  auto-submit again until edited, while the button can retry once;
- selected factor UID and multi-factor dropdown behavior;
- a pending `Completer` locks input, dropdown, button and Back;
- Back remains locked after resolver success through success hold/exit, and
  the route eventually returns exactly one `true`;
- no success state or pop before the Future resolves;
- success pops `true` once after its sequence;
- invalid, too-many-requests, `FormatException` and generic failures;
- correct clear/preserve/focus/retry policy for each error;
- empty factors remain fail-closed;
- dispose during a pending Future produces no exception;
- deterministic success/error responses during compression, halfway through
  orbit entry and during the loop start from captured geometry without a
  position, size, radius or opacity reset;
- reduced motion has no repeating ticker and `pumpAndSettle` terminates;
- one semantic text field, correct label, one polite status and one assertive
  error announcement;
- no overflow or clipping at 320×640, 390, 430, 768, 1100, 1440 and 2560,
  with 200% text, keyboard inset and a long authenticator name;
- geometry selection proves narrow below 360, medium at 390/430 content-slot
  constraints, and the wide branch at parent widths 768 and 1440 even though
  the inner stage itself remains capped at 420;
- the immersive-dark challenge remains correct under `AppTheme.lightTheme`.

Do not use `pumpAndSettle` while a normal pending orbit intentionally loops;
pump deterministic durations instead.

Add `test/totp_challenge_screenshot.dart` using the real Inter font and
`AppTheme`. It reads `TOTP_SCREENSHOT_DIR` through `String.fromEnvironment`,
defaulting to `/private/tmp/yovoice-totp-visual-qa`, and must not write to the
existing `assets/generated/`. It should render deterministic frames for empty, three digits,
mid-orbit verifying, success, invalid error, reduced motion and multiple
factors at 390×844 and 1440×900, plus narrow/200% text coverage. Render the
PNGs and inspect them; a successful widget test is not visual evidence.

Because the production TOTP rollout is still pending, also add the non-shipping
developer target `tool/totp_challenge_preview.dart`. It injects a fake
`TotpSignInChallengeClient` and exposes deterministic fast success, slow
success, invalid code, network failure and reduced-motion modes using only
synthetic `123456`-style values and names. It is never added to product routing
or release configuration. Use it for simulator review:

```text
flutter run -d <ios-simulator-id> -t tool/totp_challenge_preview.dart
flutter test --dart-define=TOTP_SCREENSHOT_DIR=/private/tmp/yovoice-totp-visual-qa test/totp_challenge_screenshot.dart
```

Never display or record a real user's TOTP in screenshots or video.

Minimum final gates:

```text
dart format on touched Dart files
flutter test test/two_factor_authentication_test.dart test/totp_challenge_animation_test.dart
flutter analyze
flutter test
```

Then inspect the actual interaction in an iOS Simulator for editing, keyboard,
pending, fast success, slow success, error, retry, 200% text and reduced
motion. Record one normal-speed and one 0.5× slow-motion pass of the full
editing → orbit → wave → check sequence. Inspect for teleporting objects,
clipped glow, angle resets, frame jumps, uneven spacing and a generic-spinner
feel; any such finding blocks completion. Clearly distinguish automated,
screenshot, simulator and production evidence.

Test-first evidence must be real: create or edit only the tests, fakes and
non-shipping harness first; run the focused suite and record the expected RED
test names and failures. Only then edit production Dart, rerun the same suite
to GREEN and continue with the remaining gates.

Minimal source-only documentation updates are allowed after implementation:
mark the item accurately in `docs/Roadmap.md` as local/source-only and not
deployed; update measured counts and evidence in `docs/TESTING.md` if tests
were added. Update `docs/Decisions.md` only if a genuinely new architectural
decision emerges, and `docs/Bugs.md` only for a real discovered defect. Do not
fabricate deployment or production evidence.

## Required review cells

Because this is user-facing authentication UI, complete and address findings
from:

1. Senior Product Designer UX UI + Senior Flutter Product Engineer.
2. Accessibility and Inclusive Design Specialist + Senior Visual Quality
   Specialist.
3. Senior Firebase Backend Engineer + Cybersecurity Senior Specialist.
4. A separate read-only Adversarial Security Auditor.
5. Senior QA Automation Engineer.
6. A final read-only Principal Code and Release Reviewer.

Preserve all unrelated dirty-worktree changes. Do not commit, push, deploy,
publish or change Firebase configuration without a separate explicit user
request.

Treat this handoff and every file under
`assets/mockup_reference/totp_orbit_motion/` as read-only implementation input.
Open the PNG, play the HTML or WEBM loop, and compare the final simulator
recording against them; do not rewrite the reference pack during implementation.
