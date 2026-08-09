# Mockup Implementation — Session Handoff (2026-08-09)

Written for a FRESH agent instance with zero conversation context. The
repository + this file are authoritative. Reconcile with the session
task ledger (Task #18) before changing anything; where they disagree,
the newer task ledger wins.

## State at handoff

- Branch: `main`, clean, in sync with `origin/main`.
- Latest commits (all verified present):
  - `b5e9797` — mockup reference asset extraction + notes
  - `ee30f6f` — Mockup M2 part 1: room chat + reactions, From your Clubs
  - `e7ebe04` — avatar-system compliance (participants sheet → UserAvatar)
  - `c979d20` — Mockup M1: Home Live Social Hub (real-data Voice Core hero)
  - Earlier same-day: `d4d952b` (room cards/covers), `149a00d` (role
    token refresh), `4368b43` (scalable stage, ADR-030), plus ADR-025..029.
- Deployed web (yovoice-ec54a.web.app) contains `ee30f6f` content
  (verified via deployed-bytes grep). Firestore rules deployed through
  the room-chat rules change. Storage rules deployed (2 MB profile cap).
- Gates at handoff: `flutter analyze` clean · `flutter test` 78/78 ·
  rules suite 93/0 (firestore) + 22/22 (storage) · iOS + web release
  builds green.

## Reference images (visual source of truth)

- `assets/mockup_reference/yo_voice_home_reference.png` (853×1844) —
  the standalone Home mockup; primary Home reference.
- `assets/mockup_reference/yo_voice_product_reference.png` (954×1649) —
  six-phone presentation board: (1) compact Home, (2) Community Room,
  (3) Premium presentation, (4) Plans & Purchase, (5) Premium
  Profile/Creator, (6) Club Room. Board captions and decorative
  background are NOT product UI.
- Extraction state: see `assets/mockup_reference/EXTRACTION_NOTES.md`.
  Extracted: `assets/clubs/cyber_lounge_art_reference.png`,
  `assets/clubs/gaming_nl_art_reference.png` (both clean),
  `assets/premium/premium_hero_reference_partial.png` (`_partial`
  because the source overlays the Club-Owner/Premium-Identity pills onto
  the ring glow; hidden pixels were not reconstructed). Everything else
  in the mockups is implemented as CODE, not crops. Mockup people
  (Maya/Alex/Noah/…) are demo/marketing fixtures only — never
  production data.

## PROTECTED — do not casually rewrite

1. **Canonical avatar system.** `lib/shared/widgets/profile/user_avatar.dart`
   is the ONE image-loading avatar. All new UI wraps it
   (PremiumAvatarFrame, PeopleStatusAvatar, SpeakerTile, preview sheet).
   Do NOT touch: avatar/banner upload (`ProfileService.pickProfileImage`
   → crop editor → `uploadProfileImage`), Storage paths
   (`users/{uid}/profile/*`), Firestore fields (`photoUrl`/`bannerUrl`),
   `ProfileService` (shared replay streams, `watchProfile(uid)`),
   server-side fan-out (`onProfileIdentityChanged`, deployed), cache
   strategy (new timestamped filename per upload). ADR-021/023/025.
2. **Home Live Social Hub** (shipped `c979d20`, details below).
3. **Room stage system** (`lib/features/rooms/presentation/widgets/room_stage.dart`,
   ADR-030) and the continuous-room shell (no lobby, minimize-not-
   disconnect, `RoomMiniBar`, `RoomEndedState`) — ADR-028.
4. **Mic state**: `VoiceCallService.micState` (`MicState` enum) is
   LiveKit-authoritative; one-way roster mute sync (never auto-unmute) —
   ADR-029 + the mute-race fix. Broadcast promotion/demotion triggers a
   guarded token-refresh rejoin (`_reconnectForRole`, `149a00d`).
5. **Premium business rules**: Monthly €9.99, Yearly €89.99 (Best
   Value, ~-25%); Creator and Club creation REQUIRE the server-managed
   entitlement (`EntitlementService`, `functions/premium/entitlements.js`,
   rules-enforced; `premiumIdentity` only writable by Admin SDK). No
   fake checkout; billing adapters blocked on store credentials
   (Roadmap 0e).
6. Floating navigation dock (`main_shell.dart`): Home/Chats/Voice/
   Friends/More, traveling capsule, tab fade transition, IndexedStack
   state preservation, `MoreDestinationHost` re-hosting the same bar.

## Architecture map (feature → files)

- Shell/nav: `lib/features/home/presentation/screens/main_shell.dart`
  (dock, `MoreDestinationHost`, `RoomMiniBar` mount, tab transition).
- Home: `lib/features/home/presentation/screens/home_screen.dart`;
  widgets: `live_now_hero.dart` (VoiceCore hero, real featured room via
  `RoomService.watchLivePublicRooms` + `watchParticipants`),
  `from_your_clubs.dart` (real memberships + lounge state).
- Shared visual system: `lib/shared/widgets/voice/voice_core.dart`,
  `lib/shared/widgets/profile/people_status_ring.dart` (PeopleStatus
  ring-color language), `user_avatar.dart`, `premium_avatar_frame.dart`,
  `profile_preview_sheet.dart` (relationship-aware preview; opens from
  every avatar).
- Rooms: services `lib/features/rooms/data/services/room_service.dart`
  (join/leave, moderation, `sendRoomMessage`,
  `toggleRoomMessageReaction`, `deleteRoomMessage`, `moderateHandLowered`,
  `setParticipantSpeakerStatus` clears hands, `enterClubLounge`,
  `watchClubLounge`), `room_experience_service.dart`; screens
  `community_voice_room_screen.dart` (stage grid + chat/people bar),
  `broadcast_room_screen.dart` + `broadcast_room/*` (podcast; stage,
  sheets, one-tap raised-hand Accept/Decline in
  `sheets/participants_sheet.dart`); widgets `room_stage.dart`,
  `room_card.dart` (typed identity cards: community purple / podcast
  red / club teal via `club_lounge_` id prefix), `room_chat_sheet.dart`,
  `room_mini_bar.dart`, `room_ended_state.dart`; entry
  `room_entry_screen.dart` (straight in, no lobby); settings
  `room_settings_screen.dart` (cover upload via `RoomImageService` →
  `updateImageUrl`).
- Audio: `lib/features/calls/data/services/voice_call_service.dart`
  (ChangeNotifier singleton; `micState`, `canPublish`, listen-only-token
  tolerance). Club room audio currently =
  `lib/features/calls/presentation/screens/voice_call_screen.dart`
  (the screen board-6 replaces).
- Clubs: `lib/features/clubs/data/services/club_service.dart`
  (`watchMyClubs`, roles via `clubRolePower`), `club_overview_screen.dart`
  (`_openClubLounge` pattern).
- Premium app UI: `lib/features/premium/*` (entitlements model/service,
  `premium_upsell_sheet.dart`, existing paywall/pricing screens).
- Website: `/Users/kamiljaguszewski/yovoice-website` (Next.js 16,
  Vercel, push-to-main deploys). Premium: homepage `PremiumSection` +
  `/premium` plans page (`src/app/(marketing)/premium/`), entitlement
  hook. Podcast rename applied (`bbfe13a`).
- Rules/tests: `firestore.rules` (+ room-message reactions/delete),
  `storage.rules`; suites `firestore-tests/rules.test.js` (93) and
  `storage.test.js` (22); Flutter tests in `test/` (78). CI
  (`.github/workflows/firebase-hosting-merge.yml`) gates deploy on
  analyze + tests + both rules suites.

## Milestone 1 completed (Home)

Time-of-day greeting header (real profile stream, notification badge);
LIVE NOW hero — real featured live room, VoiceCore centerpiece (static
unless real energy passed), up to 5 real orbiting participants with
speaking rings, real counts, working Join, quiet empty state; Your
People status-ring row (only truthful statuses: online/away; speaking/
in-room/in-club colors reserved until presence carries room context);
Rooms for you (RoomCard family); Live Pulse card retired. Verified on
iOS with a genuinely live room.

## Milestone 2 completed (part 1)

- From your Clubs: `watchMyClubs` + per-club `watchClubLounge`; Join
  room CTA runs the `enterClubLounge` flow; hides with no memberships.
- Room chat: `RoomChatSheet` over the live stage in BOTH room types —
  existing `rooms/{id}/messages` backend, composer (500 chars),
  long-press 5-emoji reaction picker, reaction chips, host delete.
- Rules (deployed): room-message updates limited to the `reactions` map
  for room participants/members/host; text immutable; delete host-only.
  Test: "room chat: reactions-only updates…" in rules.test.js.

## Verification truth table (do NOT upgrade these)

VERIFIED LIVE: chat message + 🔥 reaction round-tripped production
Firestore from inside a real live room WITH a second human present;
canonical avatars on Home/hero/people/chat rows; avatar change
propagated across surfaces and survived relaunches (observed when the
user changed CeoGriefer's avatar mid-session).
PARTIALLY VERIFIED: message/reaction rendering on the OTHER user's
screen not directly observed (their device not controllable).
NOT VERIFIED: listener→speaker→demotion live round-trip (needs two
humans; code + rules + one-sided decline observed only); Club-room
canonical avatars (no live club room existed; CeoGriefer has no club
memberships and club creation is Premium-gated); From-your-Clubs live
states beyond the hidden state; cover-upload tap-through in Room
Settings; full responsive matrix.

## Next-work ledger (priority order — matches Task #18)

1. Premium presentation visual pass (board screen 3) — app.
2. Plans visual pass (board screen 4) — keep pricing/architecture.
3. Website Premium landing visual refresh (screen 3 as reference).
4. Profile/Creator refinement (screen 5) — presentation only.
5. Club Room rebuild (screen 6) — replace `VoiceCallScreen` for club
   lounges with a club-identity room on the shared stage system; keep
   club permissions; FINALLY verify canonical avatars in a live club
   room here.
6. Floating recent-messages overlay on the stage (board screen 2).
7. Design-token consolidation (only values used by the new surfaces).
8. Responsive matrix 320→1440 (app web + website).
9. Side-by-side reference comparisons for all six screens.
10. Live two-user verifications (chat both-screens; raise-hand
    accept→speak→demote; needs the second tester, e.g. Sieeema live).
Backlog behind these: whiteboard (M6), room privileges/VIP grants,
Spotify feasibility note, room analytics, desktop-adaptive navigation,
ephemeral floating reactions (needs LiveKit data channel).

## Constraints (unchanged)

Real data only — no fake users/speaking/reactions/analytics; no second
chat backend, avatar system, or state-management framework; preserve
LiveKit/Firebase/room permissions/Premium entitlements; Coming-soon
honesty (ADR-012); rules changes always emulator-tested before deploy;
visual claims need screenshots; deploys: hosting auto via CI on push,
rules/functions manual.

## Commands that work here

- `flutter analyze` · `flutter test` · `flutter build web --release` ·
  `flutter build ios --simulator`
- Rules: `npx firebase-tools emulators:exec --only firestore --project
  demo-yovoice 'npm --prefix firestore-tests test'` (storage variant:
  `--only storage` + `run test:storage`)
- Deploy: `firebase deploy --only hosting|firestore:rules|storage
  --project yovoice-ec54a`
- Website: `npm run build` in `/Users/kamiljaguszewski/yovoice-website`
- iOS run/verify: simulator MCP tools (build first, then launch with
  `build/ios/iphonesimulator/Runner.app`, bundle `com.example.yoVoice`).
- Dev harnesses (`.claude/launch.json`): stage preview :5607, crop
  preview :5606 — real widgets, no sign-in.
- NEVER use infinite `pgrep`/sleep polling loops; use run_in_background
  with `until` conditions.

## Test-account landscape

CeoGriefer signed in on the iOS simulator AND the user's Chrome
(deployed web). Sieeema is a real second human who is intermittently
live (podcast room). No second controllable session exists and
credentials must never be typed by the agent. A pending friend request
CeoGriefer→testGriefer may still exist.
