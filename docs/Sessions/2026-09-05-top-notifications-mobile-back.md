# Top notifications and mobile Back

## Scope

The owner requested an attractive animated notification surface at the top of
the app, then added mobile swipe-back without repeatedly selecting Home.
This work changes local Flutter presentation/navigation. It does not deploy
Hosting, publish a mobile build or notify testers. Existing unrelated untracked
artwork and handoff files remain untouched.

## Implementation

- One session-bound top notification host replaces the bottom activity SnackBar
  and separate MainShell incoming-message overlay. Native foreground social
  pushes prefer the same card with existing native fallback; calls and background
  delivery keep their existing handling. Delivery IDs, routing, unread baselines,
  active-conversation suppression, recipient policy and audio settings are unchanged.
- Dark/Pearl semantic surfaces, safe-area/keyboard constraints, restrained
  slide/fade/scale, instant Reduced Motion, localized 44 px Open/Close controls,
  full wrapping/scrolling, one-card replacement and generation-bound dismissal.
- Explicit F6 region access/return and local keyboard scrolling resolve the
  Navigator focus-scope boundary without changing modal/route traversal policy.
  Arrival never requests focus. External/session cleanup never restores old input.
- Root mobile history is bounded to 24 entries and preserves Home. Back and
  edge release reuse the real selection path without duplicating pages/listeners.
  Explicit Home clears the trail. Native pushed-page gestures and protected
  call/recording/processing/fullscreen exits are not weakened.
- A logical leading-edge translucent listener preserves child vertical scrolling
  and taps while recognizing horizontal Back ahead of edge-start media drags.
  Center-screen gestures and the dock are untouched; canceled/stale drags cannot
  navigate. The indicator respects landscape safe insets and RTL.

## Review fixes

Independent source, visual and accessibility review caught and resolved:

- A tooltip overlay surrounding Navigator changed rootOverlay ordering and
  could put a chat dismiss barrier above the notification. It now wraps only
  the notification sibling.
- A keyboard-short screen could accept a card without room for its controls.
  Acceptance now rejects that state and the existing source retries on recovery.
- Route closed-loop Tab could not reach the sibling notification. Explicit F6
  access and a local control focus scope preserve normal route/modal isolation.
- Replacement of long scrolled content could inherit the prior scroll offset.
  A new arrival resets content while retaining Open/Close focus nodes.
- Delayed native fallback could attempt a stale payload after auth exit. Every
  foreground attempt checks captured authenticated UID plus identity epoch.
- Root Back originally had no history because tab selection is not route push.
  A bounded retained-slot trail now handles both touch and system Back.
- The edge indicator needed a logical safe-inset offset in notched landscape.

## Evidence and limits

Source review approved the bounded deltas without remaining actionable P0–P2.
Independent QA passed 212 tracked regression cases, 14 gesture capture cases and
the final 56-case notification replay (35 capture cases plus 21 tracked host
tests). All 98 final rendered states were inspected: 56 notification and 42
gesture frames spanning Dark/Pearl, narrow/large text, RTL, keyboard, safe insets,
Reduced Motion, overlay ordering and explicit focus access/return.
The independent harnesses use actual production widgets/themes/fonts with
explicit fixtures, never fabricated production recipients or live push events.
MainShell is Firebase-backed; isolated history/gesture/PopScope composition and
existing shell regression tests are not two-account production acceptance.
Native VoiceOver/TalkBack, physical delivery and native OS background banners
are separate gates. A native alert already accepted before auth exit cannot be
retracted by the foreground selector. No release/deployment claim is implied.

## Root completion gate

Full-tree `flutter analyze --no-pub` is clean. Full
`flutter test --no-pub --concurrency=2 --reporter expanded` passes **2426/2426**.
The first run identified one localization source guard failure: literal `F6`
looked like untranslated prose. The keycap now uses the actual keyboard key's
`keyLabel`, without weakening the guard or changing the displayed symbol.
Independent readback approved the correction; the complete suite was rerun.

The two developer-only entrypoints ran on iPhone 17 Pro / iOS 26.5 Simulator.
Screen-control verification confirmed Home → Rooms → Chats and successive
leading-edge returns to Rooms then Home, and Dark/Pearl top notification display,
Open clearing the banner before a pushed detail, and native swipe back from that
detail. These are production components in explicit local previews, not an
authenticated production-account flow. The notification fixture gained its own
transparent Material beneath switches to avoid an iOS debug ListTile paint
assertion; the production notification host was unaffected. The corrected
preview restarted without that assertion. Full-tree analysis includes the preview;
the complete regression suite was rerun after this correction.

Logs for the final local full-suite run were saved to
`/tmp/yovoice-notification-back-check.vvXG4M/flutter-tests.log` during this session.
No native store, Hosting or tester-email action occurred.
