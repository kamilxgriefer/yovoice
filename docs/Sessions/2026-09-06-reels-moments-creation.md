# Reels and Voice Moments creation — 2026-09-05/06

Status: source/local verification complete; source revision recorded below.
No deployment or store release is included.

## Request and boundaries

The owner reported that only their Reel appeared, other viewers mistook it for
their own and could not create theirs. They also requested familiar, practical
cropping/music tools and a redesigned Voice Moments creation flow.

Source tracing and deterministic multi-publisher tests did not reproduce server
author reassignment. This is not proof that the installed-client report was
imagined or fixed in production. An affected second-account capture and actual
device-to-device publishing acceptance remain useful, separate evidence.

## Implemented

- Reels clearly separates Discover and Your Reels; both retain Create, including
  empty/error/loading states. Author labels and delete/report controls follow
  canonical author IDs. Own filtering scans the existing authorized feed with
  a four-page budget and explicit continuation, not a new backend endpoint.
- Account-bound request leases reject stale feed/publish results. Retry sessions
  cannot migrate between accounts or an observed A→B→A cycle. Composer drafts,
  dialogs, picker results and preview callbacks are cleared/guarded on identity
  changes. Listener cancellation does not hang completed widget-zone requests.
- Reel Media → Edit → Review separates selection, crop/audio/text/link/filter
  tools and the final caption/availability/publication review. Preview and feed
  share the normalized 9:16 frame and playback timeline. Gesture crop has labeled
  slider alternatives; replacing media preserves unrelated caption/audio/overlays.
- Audio uses real user-supplied, owned/licensed files and explicit rights
  attestation, with start offset and media/backing volume controls. Existing
  upload limits and retry-stable server contracts remain intact.
- Voice Capture → Review retains the recorder and publish state machine, with
  focused presentation, responsive keyboard behavior, preserved caption focus,
  semantic meter states and clear localized recovery. Dialog controller cleanup
  waits until reverse transitions finish; modal Tab traversal stays closed-loop.
- 156 stable creation/recovery keys cover all 43 selectable locales (EN/PL
  call-site copy and 41 explicit catalog rows per key). Raw backend exception
  prose is not shown to users. Translations received bounded independent AI
  review, not native-speaker certification.

## Focused evidence

- Reels: 51/51 in the final approved batch: 39 tracked composer/composition/
  visual-accessibility/playback tests and 12 independent capture scenarios.
- Voice/localization: 118/118: 54 Voice screen, 28 Voice accessibility,
  31 catalog and 5 independent keyboard/focus capture cases.
- Feed: 12 pagination/identity tests and 6 unified Moments tests passed.
- ReelService: 28 tests, including account races and widget-zone completion.
- Relevant pure Node backend tests: 58/58, including independent publishers,
  multiple viewers, canonical authors and rejected foreign ownership operations.
- Firebase local emulators: Storage 67/67; Reels availability 2/2. No production
  Firebase writes or authorization changes were made.
- Actual rendered phone/tablet/desktop Dark/Pearl states were inspected, including
  320px at 200% text, 390/768/1440px, keyboard, focus, crop, audio, review,
  creation errors and own/foreign feed identity. Remaining P3 observations:
  a shared focus outline can extend 4px beyond the keyboard crop at 320px/200%
  while the label and at least 44px hit area remain visible; Pearl's inactive
  slider rail is subtle.

Logs: `/tmp/yovoice-reels-final-approved.log`,
`/tmp/yovoice-voice-localization-approved.log`,
`/tmp/yovoice-reels-emulator-check.log`. Render evidence and local capture
harnesses are under ignored `test/.screenshots/review-reel-flow-*` and
`review-voice-flow-*`; these are local artifacts, not deployed pages.

## Review and non-claims

Owning engineers, independent QA, visual/accessibility review and independent
source review approved their bounded areas. Backend/security review plus a
separate read-only adversarial review covered account/session/ownership/upload
boundaries; no remaining concrete P0–P2 was identified in that delta. Reviewers
did not self-approve their own implementation.

This does not add a licensed streaming music catalog, immutable rendered video
export, likes/comments/recommendation backend or full Instagram parity. Reels'
unchanged published audience is authenticated global discovery, even for a
private profile; blocks are still enforced. An already-authorized server action
can finish after an account transition: client guards are not a rollback.

The local `lib/dev/moments_creation_preview.dart` entry point uses actual
production widgets and sample local media with no Firebase initialization and
cloud publication disabled. Device-local recording is possible. Neither local
visual inspection nor deterministic tests certify physical microphone/camera,
two-party uploads/playback, native assistive technology or deployed tester builds.

## Final integration

- `flutter analyze --no-pub`: clean, no issues.
- Final full `flutter test --no-pub`: **2471/2471 passed**, log
  `/tmp/yovoice-moments-full-tests-approved.log`. An earlier full run exposed one
  stale English availability assertion; it now checks the exact localized
  `Visibility: 24 h` while preserving the actual published 24-hour assertion.
- Local iPhone 17 Pro Simulator (iOS 26.5), debug production-widget preview:
  selected sample photo, set crop to 2.8×, dragged the actual image, added text,
  applied warm filter, reached Review and returned through stages with the crop
  and overlay intact; discard confirmation behaved correctly. No publication.
- Voice Capture rendered in the Pearl host's documented dark immersive atom.
  Microphone request timed out without a permission response, so native recording
  and playback were **not verified**. This exposed incorrect browser-only timeout
  wording on iOS: a narrow presentation fix reuses existing localized native/web
  categories, with two additional 43-locale tests and timeout→retry coverage.
  The corrected native error was visually rechecked after hot reload. Recorder
  behavior and OS permissions were not modified or bypassed.
- The last timeout presentation and availability-test deltas received independent
  source approval. Full-tree gates above include them. No concrete P0–P2 remains
  in the bounded source review; the installed-client report remains a live
  acceptance gate, not a claimed reproduced server reassignment.

Source revision: recorded after commit. GitHub verification results follow.

No Hosting/Functions/rules/store deployment or tester email was requested or sent
in this change.
