# Meniscus navigation, live-first Home and destination atmospheres

Source implementation: `315bfef` (2026-09-05).

## Scope and approval

The owner requested the supplied Meniscus-style mobile navigation, selected
the second Home concept and approved a sofa/YO-neon environment for Rooms
with companion scenery for the other main destinations. This session changes
presentation only. It does not publish a new mobile build, deploy Hosting,
send tester mail, change Firebase schemas, or reopen Build 20 rollout work.

## Implementation

- Mobile order is Home → Rooms → Chats → Your Moments → More, with stable
  underlying page identities. The center logo/action is removed; real room
  creation remains reachable on Home and Rooms. Desktop navigation is retained.
- The moving bead/socket supports taps, drag release, cancellation, denied
  routing, re-selection, keyboard input, RTL and Reduced Motion. Unread badges
  and enlarged active labels have independent layout space.
- Home uses actual room, followed-Moment and conversation streams: compact
  greeting/avatar rail, one featured live room, Create/Friends actions, circle
  activity, recent conversations and preserved owned-room management.
- Five original bundled WebP environments total 224,674 bytes, with an 864px
  maximum decode width, static alpha and high-contrast suppression. Uploaded
  room covers take precedence. Image-generation provenance and prompts live
  in `assets/images/atmospheres/README.md`.
- Short Chats screens scroll their header with the lazy conversation list;
  200% text uses full-width primary identities. Rooms' decorative pulse stops
  for Reduced Motion and offstage TickerMode. No new backend query was added.
- New navigation/Home copy is present in all 43 supported locale catalogs.

## Review findings resolved

- Drag cancellation could commit a destination and RTL unread badges used a
  physical edge instead of logical end.
- Large text could obscure Chats content or truncate its primary names.
- Expired Moments could strand keyboard focus on a hidden target. Recovery
  now targets a visible action/heading; the own-avatar action scrolls onscreen.
- Arbitrarily bright uploaded covers needed guaranteed dark backing beneath
  both featured copy and owner/staff controls. Menu authority, callbacks and
  native 44px targets remain unchanged.

## Independent evidence

- Navigation focused QA: 70/70 tests; 13 rendered checks and a 43-locale
  caption-fit sweep including RTL Arabic with a real fallback font.
- Home/expiry focused suite: 60/60 tests before the final top-control backing;
  its affected desktop suite was rerun afterward: 30/30 passed.
- Root-change independent suite: 82/82 passed across Chats failure/recovery,
  Rooms motion, locale catalog and atmosphere asset/contrast contracts.
- Final Home render cases: 25 captures plus 10 focus/bright-cover captures.
  Section review also covers Rooms, Chats, Moments and adaptive More in Dark
  and Pearl, from 320px/200% text through tablet and desktop widths.
- Principal read-only source review and independent visual/accessibility/QA
  review approved the final deltas. No remaining actionable P0–P2 finding was
  reported within this bounded UI scope.

These renders exercise production widgets, themes and fonts with explicit
test fixtures, not invented production records. Wide More evidence covers
the adaptive sheet; the separate desktop anchored menu remains unchanged.
Native screen readers, physical devices and end-to-end production network
flows are not covered by those widget renders.

## Root completion gate

Full-tree `flutter analyze --no-pub` is clean. Full `flutter test --no-pub
--concurrency=2 --reporter expanded` passes **2364/2364**. The first full run
caught a duplicated legacy interpolated Chats tooltip; both responsive branches
now use the same stable named template with all 43 locales covered. Independent
source readback confirmed array alignment and placeholder preservation.

The refreshed developer preview ran on iPhone 17 Pro / iOS 26.5 Simulator.
All five tab taps/selected states, destination scenery and Dark/Pearl appearance
were visually inspected. This is the production dock/background in a local
preview entrypoint, not an authenticated production-network acceptance test.
Home and section layouts were verified separately in the rendered-widget cases
above. Store distribution and Hosting deployment remain outside this session.
