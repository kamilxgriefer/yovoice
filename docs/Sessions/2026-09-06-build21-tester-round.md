# Build 21 tester round — 2026-09-06

Status: source fixes and review captures complete; nothing published or
deployed. Server-side proposals recorded in DEPLOYMENT.md for the owner.

## Reports handled in source

1. Torn screen on tab switch → fade-through without offset; Home keeps its
   last feed page across the return refresh (ADR-147).
2. Dock lit Home inside a pushed More destination → More capsule stays lit.
3. Friends chat bubble → busy state per row, 15 s bound, timeout copy.
4. Moments feed → refresh in place, keep content on error.
5. Moderation Center → staff/role/counts resolved concurrently; Staff Center →
   cache-first paint, fresh confirmation.
6. Reel composer own music on iOS → UTIs added to the picker type group.
7. Avatar rings → thinner status/Premium/achievement/plain rings; palette
   colours unchanged (3:1 contrast invariant).
8. UI sounds → Soft Bells v4 pack, native notification masters replaced
   (ADR-148).

## Verification

`flutter analyze` clean; full suite 2532 passed before the ring-colour revert,
ring theme tests 6/6 after it; review captures produced by
`test/.screenshots/tab_transition_review_capture.dart`. The iOS Simulator
build launched to the sign-in screen only — no test account session was
available and credentials are never typed by the assistant, so on-device
navigation was not exercised.

## Left for the next round (see Bugs.md "Build 21 tester round")

Trim/crop on the video, draggable overlays, music library decision, Reel
length above 90 s, delete chat / remove friend affordances, mute latency,
background-call drop (Android foreground service), keyboard Done affordance,
TestFlight invite-code explanation for one tester.
