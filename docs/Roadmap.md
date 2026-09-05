# Roadmap

Update this file whenever a feature ships — move it into **Done**, note the
commit. This is a working backlog reflecting engineering judgment, not a
promise to users or a fixed queue — re-prioritize freely as the product's
needs change.

**Done** items are a lighter changelog-style list — "status: Done" and
"dependencies: none remaining" would be noise for something already
shipped. **In Progress** and **Planned/Backlog** items below carry the
full structure (status, description, dependencies, priority, future
considerations) since those are the ones where that context actually helps
someone decide what to pick up next.

---

## Done

- **Animated top notifications and mobile edge Back** (2026-09-05,
  source commit `e99bed73`, ADR-143/144; **SOURCE + LOCAL VISUAL/SIMULATOR
  VERIFIED, NOT PUBLISHED**): activity, foreground social pushes and incoming
  MainShell messages share one safe-area-aware Dark/Pearl card, with localized
  Open/Close controls, restrained motion, Reduced Motion, readable long content,
  explicit keyboard region access and session-bound cleanup. Native call and
  OS background handling remain unchanged. Retained mobile tabs have bounded
  visit history and leading-edge Back; center media gestures, the dock and
  guarded recording/call exits retain their existing contracts. Independent
  source/QA/visual review approved both changes, including 98 inspected render
  states. Full-tree analysis is clean and **2426/2426 Flutter tests pass**.
  Local iPhone Simulator previews confirmed Chats → Rooms → Home by gesture,
  Dark/Pearl top notifications, opening and native detail Back. This is not
  physical-device, native assistive-technology or live-push acceptance. No store
  build, Hosting deployment or tester email was sent.
  [Evidence and limits](Sessions/2026-09-05-top-notifications-mobile-back.md).

- **Meniscus mobile navigation and approved live-first Home** (2026-09-05,
  source commit `315bfef`, ADR-141/142; **SOURCE + VISUAL QA VERIFIED, NOT
  PUBLISHED**): Home → Rooms →
  Chats → Your Moments → More replaces the fixed center-logo action. The
  moving bead/socket supports tap, drag release/cancel, keyboard, RTL and
  Reduced Motion while preserving stable page identities and desktop
  navigation. Real Create room entry points and guided-tour anchors remain.
  Home follows the owner-selected second concept using existing room, followed
  Moment and conversation streams, not fictional activity. Five original
  static WebP scenes (224,674 bytes total, bounded 864px decode) serve the main
  destinations with Dark/Pearl/high-contrast handling; Rooms receives the
  approved sofa/neon setting and uploaded covers retain precedence.
  Navigation/Home copy and the updated Chats tooltip cover all 43 locales.
  Independent engineering, visual/accessibility/QA and final source reviews
  approved the changes; full analysis is clean and **2364/2364 Flutter tests
  pass**. Real-font renders cover phone/tablet/desktop, 320px at 200% text,
  long/RTL labels, bright uploaded covers and expiry-focus recovery. The
  production dock/background preview was also checked in iOS Simulator.
  Exact motion parity to the compressed reference and native screen-reader
  acceptance are not claimed. No new store build, Hosting deployment or tester
  mail is included. Evidence and limits:
  [session record](Sessions/2026-09-05-meniscus-live-first-home.md).

- **The Dark/Pearl colour system now has one enforceable semantic contract**
  (2026-08-30, ADR-133, **SOURCE + VISUAL QA VERIFIED; BUILD 19 TESTING**):
  navigation chrome, interactive copy, control boundaries,
  status pairs and focus-on-brand are separate roles instead of variations of
  one purple. Normal Home, social, Profile, Moments, Settings, Notifications,
  Premium, onboarding and public report surfaces now follow the active theme;
  documented voice/media, branded-auth and staff/creator workspaces keep a
  complete dark atom. A dynamic source guard derives all 26 Dark and Pearl
  roles (52 declarations), rejects their exact raw copies, dark-only immersive
  container copies and immersive imports on normal routes, and permits only a
  line-local uploaded-media exception. Profile status/fact chips and
  Club/Family identity treatments now resolve readable Dark/Pearl pairs.
  Discover keeps stable category branding seeds but resolves feature-local
  surface, foreground, boundary and action pairs, so Music/Business/Broadcast
  accents no longer become low-contrast compact ink in Pearl.
  Automated contrast/component/state tests pass, and real-font Dark/Pearl
  renders cover 320 px at 200% text plus 390/430/768/1440 px, populated,
  empty, error, focus, loading, disabled and overlay states. The 320 px header,
  section actions, Moment labels and dock reflow rather than overlap; public
  Home errors remain distinct and retryable, and primary gradient buttons now
  retain their full raster contrast. Dark/Pearl report sheets, standalone
  snackbars and real emoji fallback are included in the evidence set.
  The implementation is in Build 19 tester distribution; physical-device
  acceptance remains pending before any public release.

- **Authentication now shares one responsive stage and fails closed during
  password-profile provisioning** (2026-08-31, ADR-134, **SOURCE + ADVERSARIAL
  TESTS VERIFIED; BUILD 19 TESTING**): compact and medium
  layouts use one Voice Relay transition, wide screens use the matching
  two-panel curtain and reduced motion swaps atomically. Controllers and
  validation survive breakpoint changes, keyboard/focus remain reachable and
  registration retains the root Navigator long enough to open verification
  after Firebase publishes Auth state. The shipped registration screen now
  drives the AuthGate provisioning interlock. Independently, ProfileService
  reloads Auth and re-reads Firestore before bootstrapping an unverified
  password account with no display name; if the chosen pseudonym is still not
  authoritative it stops rather than deriving identity from the email. That
  second boundary covers another browser tab/process and keeps the existing
  server-authoritative display-name rule intact.

- **New users now get a short, optional guided tour instead of an unexplained
  Home screen** (2026-08-29, ADR-132, **SOURCE VERIFIED; WEB + BUILD 19
  TESTING**): five focused steps introduce YO creation, Moments, Chats and
  More using the real mobile dock or desktop rail as live spotlight anchors.
  Skip, Back, Next and Done are always reachable; keyboard, reduced-motion,
  Dark/Pearl and 320 px at 200% text are first-class states. The tour opens
  automatically only for a genuinely new account's initial session, records
  Skip/Done per account and version, and can always be replayed from Settings.
  It waits for initial deep links, cold-start notification destinations,
  reverse route transitions and the bounded native notification permission
  prompt, while token/network work stays parallel and a single-flight guard
  prevents rapid taps from stacking guides. Responsive resize, persistence,
  modal blocking, focus retention, permission failure/hangs and twelve
  real-theme visual frames are covered without adding a remote profile field.

- **The collapsed live-room panel is now a single compact YO Live Capsule**
  (2026-08-29, ADR-102 amendment, `838bddb`, **WEB HOSTING DEPLOYED +
  BYTE-EXACT; BUILD 19 TESTING**): the old multi-row mobile card is
  replaced below 880 px by an 82 px capsule with a dedicated room-return zone
  and three 48 px circular Chat, Mic and More controls. Latest chat, unread,
  audience and reconnecting state stay glanceable without occupying the Home
  feed. Return and Leave/End move into a compact modal; temporary hosts still
  receive the truthful destructive confirmation. Dark/Pearl, 320/390/430 px,
  200% text, long copy and all interaction states were rendered against the
  production YO dock. Desktop keeps its established four-zone dock.

- **Profile identity is now a compact two-level passport, not a badge
  staircase** (2026-08-29, ADR-131, **WEB HOSTING DEPLOYED + BYTE-EXACT;
  BUILD 19 TESTING**): the avatar and pseudonym share one responsive hero
  row with a small semantic name plate, while official role/VIP and
  Creator/Premium/achievement identity use the full profile width beneath it.
  The owner case that previously stacked into four floors now remains two
  deliberate rows at normal phone text sizes; 320 px at 200% text wraps
  without hiding or clipping any identity. Avatar size steps down at compact
  breakpoints, the display name is a semantic heading, Pearl fallback initials
  stay visible and every small role/account/Premium label has measured AA
  contrast. Repository-swap coverage also pins badge-listener ownership.

- **The signed iOS shell now follows YO Voice's selected runtime theme**
  (2026-08-29, ADR-129, **TESTFLIGHT BUILD 19 TESTING**): the obsolete
  `UIUserInterfaceStyle=Dark` application-wide override is gone, so System can
  report the device appearance and Pearl can reach the Flutter surface and
  platform controls. The branded launch storyboard and initial native window
  stay dark while preferences load, preventing the old white startup flash.
  A source-level release regression prevents a future global appearance pin.

- **The final mobile dock uses one continuous sculpted rise and transparent YO
  mark** (2026-08-30, ADR-128, **SOURCE IMPLEMENTED; BUILD 19 TESTING**): the
  old circular notch, socket and resting centre tile are gone.
  Dark and Pearl share one responsive Bézier outline while keeping distinct
  material hierarchy. The official transparent favicon rests directly on the
  surface; compact navigation is icon-only with semantic labels and 48 px
  targets. One 52 px glass capsule commits only after `MainShell` accepts the
  route, retargets rapid taps from its live position, stretches between
  neighbours and fades behind YO on cross-dock travel. More is selected only
  while its actual panel is open. Geometry, focus, unread `99+`, reduced
  motion, safe areas and 320/390/430 plus 200% text are covered; physical
  tester-device acceptance remains pending.

- **Pearl light theme is a complete, premium normal-product experience**
  (2026-08-29, ADR-127, **WEB HOSTING DEPLOYED; BUILD 19 TESTING**):
  a semantic `AppPalette` now owns paired canvas,
  surface, copy, border, navigation, focus and status roles. Home/dock, Chats,
  Friends, Moments, Profile, Settings, Notifications, Premium, modal chrome
  and shared controls migrate as complete surfaces; system status/navigation
  icons follow brightness. Voice rooms, calls, room creation/settings/entry,
  recording/review, story viewing, cropping, achievements and creator/staff
  workspaces remain explicitly immersive dark with matching system chrome.
  Light no longer carries a Beta label. Polish's later production graduation
  and the expanded locale registry are recorded in ADR-136. Contrast contracts,
  a real desktop sidebar/right-column gate, dark-route tests, 320/768/1440 at
  200% text, responsive journeys and real-font light/dark Home PNGs guard the
  result.

- **Home Voice Moments are a truthful avatar-only story rail** (2026-08-29,
  ADR-123, **DEPLOYED TO WEB; BUILD 19 TESTING**): mobile and desktop now
  keep the signed-in avatar first and show only followed authors who have
  active, playable Voice Moments. One author occupies one bubble and opens the
  complete ordered chain. Friend-only profiles, silent documents, profile
  suggestions, the large empty card and its duplicate CTAs no longer fill the
  rail. Relationship failures fail closed to the own-avatar entry point;
  recommendations are deferred until a block-safe server source exists.
  Responsive regression coverage includes 320 px at 200% text and 44 px create
  targets.

- **Profile avatars converge across Chats, open conversations and Home**
  (2026-08-29, ADR-130, **SOURCE + EMULATOR VERIFIED; BACKEND DEPLOYED;
  BUILD 19 TESTING**): live surfaces now read the privacy-safe current profile while
  conversation snapshots remain an offline fallback. Retryable server fan-out
  re-reads canonical identity per bounded transaction, validates Auth/profile
  activity and exact conversation membership, and cannot let an old delivery
  restore an obsolete or deliberately removed photo. A dry-run-first,
  resumable and aggregate-only repair is ready for existing stale snapshots.
  The production backend is deployed; a two-account physical Chats/Home cache
  smoke remains tester acceptance.

- **Room covers can be composed by the host instead of being silently
  center-cropped** (2026-08-29, ADR-122, **DEPLOYED TO WEB + RULES; BUILD 19
  TESTING**): Create Community/Podcast Room and Room Settings now share a real
  21:9 editor with pinch zoom, drag, reset, keyboard/single-pointer controls
  and a central compact-card safety guide. Only the confirmed 1600×686 JPEG is
  uploaded; cancelling Replace preserves the prior composition. Upload and
  lost-acknowledgement recovery never delete a potentially published object,
  superseded media is cleaned after a confirmed pointer flip even if the
  settings route closes, and status/delete actions cannot race an upload.
  Closed/archived rooms explain that they must be reopened before Storage can
  accept new art and offer a nearby Reopen action, while suspended rooms stay
  under moderation control. The production-themed editor was visually
  inspected in real local web renders at 320×640 and 1440×900; automated
  coverage pins 320 px/200% text, pixel-level zoom/pan output, validation,
  cancellation, replacement and every recovery branch. Firestore Rules and
  the defensive model parser also reject malformed, external or cross-room
  public cover pointers while preserving the live Club-bound avatar on Club
  Lounges; source allocation and decoded dimensions are bounded.
  A corrective Web pass replaced the unsupported encoded-descriptor dimension
  getters with a header-bounded, EXIF-aware codec and retains the decoded frame
  through reverse navigation. The Chrome gate now exercises valid JPEG, PNG,
  WebP, a rotated iPhone-style JPEG, forced route reset and the complete
  confirmation/export path.
  The complete Firestore Rules suite passes 523/523; production Rules were
  deployed and read back byte-identically before tester assignment.

- **Podcast Studio is a producer-led show surface, not a recolored Community
  Room** (2026-08-28, ADR-120, **DEPLOYED TO WEB + FIRESTORE RULES; iOS
  BUILD 9 TESTING; ANDROID BUILD 9 INTERNAL**): the
  episode topic, show format, host credit and live stage/audience/speaking
  metrics now form the editorial hero. Hosts get an in-room producer desk and
  a real-time request queue with one-tap accept/decline; listeners get explicit
  audience, request-sent and listening-only states. Podcast settings now edit
  the episode, format, guest guidelines and whether listener stage requests
  are open. The current client uses only
  `participants/{uid}.isHandRaised`; the old service API is a deprecated
  adapter onto that field, while the legacy `handRequests` Rules contract is
  retained solely for already-installed clients. Promotion waits for the
  callable's gapless LiveKit permission update and reconnects only as a
  delayed recovery. Responsive visual evidence covers 320–1440 px plus the
  desktop producer queue; short canvases scroll instead of overlapping stage
  cards. Production Hosting serves the pinned workflow artifact, Firestore
  Rules were read back byte-for-byte, TestFlight build `1.0.0 (9)` is assigned
  to the permanent internal group, and Google Play build `1.0.0 (9)` is
  available to the selected 11-account tester list.

- **iOS build 7 accepted by App Store Connect** (2026-08-28,
  **SUPERSEDED BY TESTFLIGHT BUILD 9**): signed
  `1.0.0 (7)` was uploaded from `9a92072`, passed App Store package analysis
  and entered Apple processing. Build `1.0.0 (9)` is now the verified current
  TestFlight build in `YO Voice Internal Testers`; Android Internal Testing is
  likewise on build 9.

- **Android adaptive launcher icon respects the platform safe area**
  (2026-08-28, **RETAINED IN ANDROID BUILD 9 INTERNAL — AVAILABLE TO 11
  TESTERS**): the
  Android 8+ foreground inset moves from 8% to 16%, bringing the full YO mark
  inside the 66dp adaptive safe area used by circle, squircle and OEM masks.
  iOS/App Store artwork, the canonical transparent mark and legacy Android
  rasters are byte-unchanged. A regression test pins both generator
  configuration and the source adaptive-icon XML consumed by the Android
  build.

- **P0 Google/Apple sign-in and registration recovery** (2026-08-28,
  **DEPLOYED TO WEB; ANDROID BUILD 9 INTERNAL; iOS BUILD 9 TESTING**;
  real-account smoke pending):
  Login and Registration now expose the same federated actions. Valid provider
  sessions are no longer rolled back by a concurrent or transient Firestore
  profile failure;
  authenticated entry waits for a bounded, retried, rules-safe profile
  bootstrap. Provider names are normalized to the canonical 2–120 UTF-16-unit
  contract without splitting graphemes, an in-flight account switch cannot
  retarget provider identity into another profile, iOS supplies `GIDClientID`,
  Apple probe outages are retriable, and Apple is available on Android through
  Firebase OAuth. Automated coverage is credential-independent; production web
  and store-installed new/returning-account smokes remain release evidence.

- **Friends can call each other directly from a DM** (2026-08-27, ADR-117,
  **DEPLOYED TO BACKEND + WEB; ANDROID BUILD 5 INTERNAL**): the formerly inert
  phone action now creates a private ringing session, presents incoming calls
  app-wide, supports answer/decline/cancel/end and fast local mute, and connects
  both participants to a dedicated LiveKit room only after acceptance.
  Server-owned locks prevent overlapping calls, terminal transitions revoke the room, and unanswered
  calls expire after 60 seconds into a missed-call notification. Bilateral
  friendship, blocks, restrictions and active accounts are revalidated at
  start, answer and token issuance.
- **Fixed in source 2026-08-31 — direct video calls extend the same
  server-authoritative lifecycle** (ADR-135, **BUILD 19 TESTING; PHYSICAL
  MIXED-VERSION ACCEPTANCE PENDING**): Chats
  exposes a distinct video action; incoming/outgoing UI supports remote video,
  mirrored local PiP, camera flip, camera/mic/speaker controls and audio-only
  fallback. The backend stores immutable audio/video intent and scopes LiveKit
  publication by the client's declared source (microphone, or microphone plus
  camera; screen-share labels omitted). This is not capture-origin proof
  against a modified client. Late joins are canceled across
  logout/hang-up/account changes,
  backgrounding invalidates any camera-enable race, microphone teardown
  re-stops captured track objects after delayed SDK work, active calls expire
  with durable room teardown, and external room links confirm then start muted.
  Transport is encrypted by WebRTC/LiveKit, but app-level E2EE and native
  CallKit/ConnectionService presentation remain separate release work. A
  server-checked recipient/minimum-build capability provides the compatibility
  boundary. Web/Functions and Build 19 tester channels are deployed; the
  two-device mixed-version result is not inferred from that rollout.

> **DEPLOYED 2026-08-20.** This banner previously said the whole 2026-08-19/20
> wave was fixed in source and unreachable in production. That is no longer
> true: rules, Cloud Functions, Firestore indexes and the Flutter web client
> were all released on 2026-08-20, in that order. The individual
> "**NOT DEPLOYED**" markers on the entries below date from before that release
> and are stale — treat
> [DEPLOYMENT.md](DEPLOYMENT.md#released-2026-08-20-the-reachability-wave) as
> authoritative, since it records what was deployed and how each artifact was
> verified.
>
> **Still true, and the reason ADR-082 exists:** reachability was verified by
> reading production back, not by using the product. The deployed ruleset and
> the deployed `main.dart.js` were each compared byte for byte against the
> working tree, the Moments feed queries were executed against production, and
> 45 rooms were measured read-only. **No signed-in round trip was performed** —
> nobody has yet opened a dormant room and pressed Start voice against the live
> backend. See
> [ADR-082](Decisions.md#adr-082-a-feature-is-not-shipped-until-a-user-can-reach-it--reachability-is-part-of-done-and-a-green-suite-cannot-prove-it)
> for why that distinction is the whole point of this wave.

- **Voice Moments can be reviewed before publish and use a user-sized
  availability window** (2026-08-27, ADR-115, **DEPLOYED TO WEB; NATIVE STORE
  BUILD PENDING**):
  finished audio can be played, paused and sought locally before any draft or
  Storage upload exists. Timed availability is any whole 24–720 hours or 1–30
  days, plus Until deleted. Publish retries keep the original caption and
  lifetime. The backend validates the same range, enforces the exact 10-active
  cap through a per-author transaction mutex, and makes root lifecycle plus
  canonical media state server-only. Exact deadline timers remove an already
  open Moment and stop playback without waiting for a new Firestore snapshot;
  the visible transition is announced once, keyboard focus recovers to a
  stable target, and Story selects the first surviving successor after a
  multi-deadline resume. Home circle strips and the Following feed preserve
  that contract even when their source stream emits the already-pruned list.
  Engagement callables reject at that same deadline.
  Client media deletion is disabled so it cannot race finalization; bounded
  server cleanup owns both explicit deletion and abandoned uploads.

- **Desktop Recent Chats keeps profile artwork current and recognizable**
  (2026-08-27, ADR-111 corrective follow-up, **DEPLOYED TO WEB; NATIVE STORE
  BUILD PENDING**):
  the cards now refresh an empty or stale conversation avatar from the other
  participant's server-owned `publicProfiles` projection while retaining the
  conversation copy as a loading/error fallback. The portrait is a sharp,
  face-biased full-bleed cover under a lower text scrim instead of a heavily
  blurred color band. Missing/broken photos use a deliberate hashed accent and
  monogram, the redundant chat glyph is gone, and unread remains the only
  top-corner status. Desktop stays 116 px, 200% text stays 212 px, and the
  shared mobile avatar presentation is unchanged.

- **Avatar cropping keeps the selected photo covering its frame through the
  first pinch** (2026-08-27, ADR-025 corrective follow-up, **DEPLOYED TO WEB;
  BUILD 19 TESTING**): the editor now seeds a uniform XYZ cover transform instead of
  leaving Z at 1, which had made Flutter apply the below-1 cover scale twice
  and shrink the image into the upper-left corner. Named 44 px Zoom −/+ and
  directional controls add single-pointer and keyboard equivalents to pinch
  and drag, while the crop preview reports its zoom semantically.
  Portrait/landscape tests pin reset, both control paths and final output
  geometry at normal and 200% text.

- **Profile Preview's Message action survives stacked modal sheets**
  (2026-08-27, ADR-113 corrective follow-up, **DEPLOYED TO WEB; BUILD 19
  TESTING**):
  Preview returns a typed Chat/Profile destination to its launcher's navigator
  and navigation begins only after the sheet is gone. Callable refusal remains
  visibly actionable inside the preview instead of placing a snackbar under
  the modal barriers. A route-level test reproduces Profile Preview above an
  already-open modal, then pins a delayed double tap, announced opening state,
  one routed Chat, Back behavior and 320 px/200% failure feedback.

- **Modal sheets have one attached drag cue and an explicit Close action**
  (2026-08-24, ADR-113, **DEPLOYED 2026-08-25**, Hosting byte-verified): the
  global Material drag handle is disabled and all 26 production bottom-sheet routes use the
  shared `YoModalSheetChrome`. Phones and tablets show one cue on the actual
  sheet surface plus a 44 px-or-larger Close action; pointer-first desktop
  omits the misleading drag cue and keeps Close. New Message no longer expands
  an invisible route-sized sheet behind its visible panel, and the same route
  remains dismissible by scrim, swipe, Back/Escape and Close with focus
  restored to the launcher. Chrome colors are derived from each sheet's real
  surface rather than the ambient theme, preserving non-text contrast in dark
  and light mode. New Message and Profile Preview route tests cover 320–2560
  px and 200% text; production-theme frames were rendered and inspected at
  390, 768 and 1440 px.

- **Desktop Recent Chats is a compact full-bleed conversation rail**
  (2026-08-24, ADR-111, **DEPLOYED 2026-08-25**, Hosting byte-verified): the
  detached 40 px avatars and 148 px mostly-empty cards are replaced on desktop by 116 px
  cards whose real participant photo fills and softly blurs behind a dark
  legibility scrim. Missing or broken photos resolve to deterministic brand
  gradients with a quiet initial. Name, preview and unread state remain, and
  the whole card is a named keyboard-accessible chat action. Mobile retains
  its established avatar presentation and dimensions. The source-only
  2026-08-27 corrective follow-up above supersedes the deployed blur and
  conversation-only artwork details without changing this compact geometry.

- **Desktop People & Moments keeps discovery, but no longer embeds Follow
  buttons** (2026-08-24, ADR-110, **DEPLOYED 2026-08-25**, Hosting
  byte-verified): the profile suggestions after the divider remain visible and open the existing profile
  preview, while the low-context inline Follow chips and their duplicate
  mutation path are gone. Existing following edges are still read so already
  followed people are not suggested. Widget coverage pins both the absence of
  the inline action and continued profile reachability; the dedicated creator
  and profile follow controls are unchanged.

- **The desktop rail no longer scrolls; Home is a pinned header action beside
  Notifications** (2026-08-24, ADR-109, **DEPLOYED 2026-08-25**, Hosting
  byte-verified): the full-width Home row and the rail's `SingleChildScrollView` are gone. Home
  keeps the same slot/routing but renders as a 44×44 selected icon beside the
  44×44 bell. At rail heights below 700 px the two creation actions share one
  row; at 200% text the informational timezone card yields, and below 620
  logical px the shell uses the existing mobile navigation rather than
  clipping a desktop rail; enlarged text also widens the rail so primary
  labels stay complete rather than ellipsized. Verification and the live-room
  mini-player now belong to the content column, so neither can shorten the
  rail. Widget coverage verifies no descendant `Scrollable`, every action
  in-bounds at 620 px, selected semantics, callbacks, 44 px targets and 200%
  text. Visual harness frames were rendered and inspected at 1440×900 and
  1280×620.

- **The desktop rail is pinned, and its clock becomes a timezone world-map
  card** (2026-08-22, ADR-107, **DEPLOYED 2026-08-23** — Hosting, byte-verified): the rail owns its
  scroll position explicitly (`controller` + `primary: false`, matching the
  Home feed and the 344px right rail), and the map tier now sizes from the
  RAIL's height via a `LayoutBuilder` in the rail rather than
  `MediaQuery.height`, which could not see `RoomMiniBar` or the verification
  banner shrinking it. The reported "sidebar scrolls with the page" was
  measured, not guessed: the rail's `maxScrollExtent` is 0 at 1440x768, 40 at
  720, 82 at 620, and past that a wheel over the rail scrolls it and it stays
  scrolled. **Two plausible causes were tested and REJECTED** — a shared
  `PrimaryScrollController` does not couple scrollables (delta 0.0), and
  macOS bouncing physics does not rubber-band at zero extent (held drag and
  trackpad pan-zoom both 0.0). `SidebarClock` becomes `TimezoneWorldMapCard`,
  keeping its painter and minute-boundary timer and gaining card chrome, a
  UTC-offset pill, an IANA city/region line and a day/night tint; detection
  is privacy-shaped and stores nothing. Flutter suite 1198 -> 1208; the new
  coupling test was confirmed to fail with the fix removed. Visually verified
  in a real browser at 1440x900 and 1366x700. **Released to production on
  2026-08-23** by manual `workflow_dispatch` with `deploy_hosting: true`;
  verified by fingerprinting the SERVED bytes rather than trusting the deploy
  log — `https://app.yovoice.app/main.dart.js` is now byte-identical to the
  local release build (sha256 `c293968af468f1ae`, 6,091,200 bytes) and
  contains the `Intl.DateTimeFormat` binding, where the previously served
  artifact (`1ee69af6…`, 6,060,653 bytes) contained neither it nor
  `resolvedOptions`.

- **Mobile Moments 1:1 to the mockup: feed, detail screen, YO-logo nav,
  author-chosen availability, delete-own** (2026-08-22, ADR-103, DEPLOYED —
  functions then hosting, byte-verified): availabilityHours whitelist
  24h/3d/7d/30d/permanent (missing expiresAt now MEANS permanent — the
  deliberate ADR-101 reversal), replay-safe ledger hash, cap counts
  permanent forever and frees on delete; delete routed through the
  deleteMoment callable after review caught the client-side sweep breaking
  on foreign engagement; new MomentDetailScreen with REAL likers as "Top
  reactions"; bottom-nav center is the YO logo. Flutter → 1177; functions →
  775; rules → 485 (untouched file, one new strip-the-field pin). Reviews:
  security PASS, visual PASS, principal FIX_FIRST fully closed pre-deploy.

- **The active-room mini-player is rebuilt to the reference mockups**
  (2026-08-22, ADR-102, DEPLOYED — hosting, byte-verified): desktop
  four-zone dock and mobile card with live latest-chat preview (limit(1)),
  expand-in-place chat reusing RoomChatPanel, session-local "N new", and
  the navigation bugs fixed at the root — a disabled Mute used to forward
  its tap to the bar's parent InkWell and NAVIGATE INTO THE ROOM. Flutter
  suite → 1132 (18-test isolation matrix, bug reproduced RED first). Three
  pre-deploy reviews; every high/medium fixed before release.

- **The final dock now hands a real room session into the existing compact
  player** (2026-08-30, ADR-102 amendment, **SOURCE IMPLEMENTED; NATIVE STORE
  BUILD PENDING**): a non-interactive clone of the official transparent YO mark
  rises from the central dock axis, gains the real room orb treatment and
  yields to the sole production `CompactActiveRoomBar`. Direct calls never
  create the bar, an already-active mount never replays the flight, reduced
  motion is immediate and interrupted end/new-room transitions retarget safely.
  A projected session model also prevents 20 Hz audio-meter notifications from
  rebuilding the whole bottom chrome. Every async Return, mute, host lookup,
  chat sheet and confirmation is pinned to a monotonic room-session generation;
  a completion from room A cannot navigate, unmute or disconnect room B. Hosted
  destinations suppress the covered shell's player until their reverse route
  completes, preserving a single listener/subscription owner. The focused
  dock/room/mute/onboarding verification is now 147 passing tests, with
  Dark/Pearl and 320 px / 200% renders checked before release.

- **Voice Moments are 24-hour audio stories** (2026-08-22, ADR-101,
  DEPLOYED — indexes/rules/functions/hosting in that order): many Moments
  per author consumed as story chains (viewer with progress bars, "1 of 3",
  auto-advance, per-user viewed rings), server-side 24h expiry (finalize
  stamp + 10-min sweeper + client gap filter), a 10-active cap, and the
  stories feed (chips, featured, recent, detail panel, share via the
  existing ?moment= link) plus the sidebar clock's procedural world map.
  Flutter suite → 1114; functions → 768; rules → 484. Three pre-deploy
  reviews: security PASS, principal+visual FIX_FIRST with every high and
  medium fixed before release.

- **The room experience and the desktop sidebar are visually rebuilt onto one
  design system** (2026-08-21, `84ab319`, DEPLOYED — hosting, byte-verified;
  ADR-098): four room identities (violet/emerald/gold/coral) over shared
  RoomHeader/HeroBanner/Stage/AudienceStrip/ControlDock/QuickActions
  components; the stage takes the column's leftover height on wide viewports;
  floating centered dock; sidebar with the notification bell on top, a true
  More overlay and internal scroll. Flutter suite 1096 → 1098; 52 room + 9
  sidebar frames rendered and inspected. The three independent reviews (visual,
  accessibility, principal) ran post-release on 2026-08-21 — all three
  returned FIX_FIRST and every high and medium finding was fixed and
  redeployed the same day (see Bugs.md). Still UNVERIFIED: no real
  browser/simulator pass; animations have no still-frame proof.
- **The Admin Center's room-status filter reads `status` the way the rules do**
  (2026-08-21, SOURCE ONLY — the index is NOT deployed; ADR-104):
  `listAdminRooms`' "active" filter recognised 9 of the 34 rooms the deployed
  ruleset calls active, because 25 of 45 production rooms predate the field —
  and it never returned even those 9, since no `status`+`updatedAt` composite
  index exists (`9 FAILED_PRECONDITION`, verified against production twice).
  "Active" now means active as the rules read it, via the shared
  `roomIsActive()`; every explicit value keeps its indexed equality, and the
  two missing indexes are checked in. Functions suite 746 → 754, with three of
  the eight new cases failing against the unfixed callable. **`closed` and
  `suspended` remain broken until an index deploy** — which must not be run
  from this branch alone (see ADR-101's Consequences). Clubs were checked and
  deliberately left alone; two live club-`status` disagreements are logged in
  [Bugs.md](Bugs.md).

- **Family and club rooms are deletable — from the same dialog as any room**
  (2026-08-20, DEPLOYED: indexes → `deleteClubSelf` → hosting, each verified;
  ADR-096): owner-only whole-club teardown with honest copy naming the club.
  Functions suite → 746 (12-case deletion suite incl. banned/disabled/no-
  profile callers), Flutter → 1096 (incl. a recycling regression that fails
  pre-fix). Security audit SHIP; correctness review found and we fixed the
  missing collection-group index (production-verified) and a wrong-club
  deletion hazard in a recycled menu state.

- **The microphone works like Discord's: self-mute never costs the right to
  speak, and everyone in a non-broadcast room may talk** (2026-08-20,
  `eb51e96`, DEPLOYED — functions + hosting, byte-verified): fixes the
  reported loop where re-entering a room left you muted and a few unmute
  attempts degraded the control to "Listening". ADR-094. Functions suite
  727 → 734.

- **Moments: Discover is an avatar board (most-engaged on top), Following is
  compact tiles, counts are live, and the Home "Your Moment" tile actually
  opens your Moment** (2026-08-20, `7938c88`, DEPLOYED — hosting,
  byte-verified): ADR-095. Flutter suite 1053 → 1081; 36 screenshot frames at
  390/768/1100/1440 + 2× text, key frames inspected. UNVERIFIED: no
  simulator/browser pass yet.

- **Rooms can go live at all — voice now starts in Community rooms and
  lounges** (2026-08-20, `b0f1062`, **NOT DEPLOYED**): opening a Family Room
  you created yourself and pressing unmute returned "This room is not
  currently live," and it was not a Family Room bug — **voice had never
  worked in any Community room or lounge.** `createLiveKitToken` refuses a
  token unless the room says status active and `isLive` true; performing that
  transition is the caller's job, and only `enterClubLounge` ever did it,
  reachable in practice from the Club overview alone.
  `RoomService.startCommunityVoice` had **zero callers**. Production
  confirmed it: **45 rooms, 3 live.** Entering a room now performs the
  liveness transition for anyone the deployed rules would accept, through one
  coordinator running liveness → roster → token;
  `RoomVoiceStartAuthority` mirrors the deployed rule branch for branch and
  `startRoomVoice` sends exactly the three keys the rule permits, as a
  standalone update. Exposure stays host-opt-in (`membersCanStartVoice`
  defaults false; lounges are private and auto-started), and legacy documents
  are tolerated deliberately because most production rooms are legacy — 25 of
  45 carry no `membersCanStartVoice` and 24 have neither `roomType` nor
  `experience`. All 3 club-lounge documents carry `clubId` and `roomKind`,
  read from production. Fixed in passing:
  `CommunityVoiceRoomScreen.dispose` never removed its listener from the
  process-wide `RoomMuteCoordinator` singleton. Flutter 978 → **1036**; 45
  screenshots rendered with the real typeface at 320/390/768/1100/1440 and
  200% text. **UNVERIFIED**: no production or emulator round trip, no real
  LiveKit, no device run — rules were read, not executed. See
  [ADR-088](Decisions.md#adr-088-entering-a-room-performs-the-liveness-transition-through-one-ordered-coordinator-that-mirrors-the-deployed-rule).

- **Reporting a message is possible at all, and a first-day victim can do
  it** (2026-08-19 → 2026-08-20, `9f3ce7f` client + `2c086c7` backend,
  **NOT DEPLOYED**): across the whole product there was no way to report a
  message — not a DM, not a room message, not a club message.
  `createContentReport` was deployed and ACTIVE and already accepted
  `directMessage`, `voiceMoment` and `voiceMomentComment`; **no Dart file
  called it.** The only report action was on a profile, with `reason`
  hardcoded to `harassment` and a fabricated note. Every target the callable
  supports is now reachable from every surface where that content appears
  (DM chat, both Moments feeds, the comment thread), never on your own
  content; a reason picker replaces the hardcoded label, argued from
  triage-response-time rather than convention; provenance moved from an
  invented note to a `contextPath`; and nine callable status codes map to
  nine distinct sentences, each traced to a real `fail()` in the deployed
  function. The backend half relaxed the email-verification gate that
  contradicted the policy written in `firestore.rules`, added `roomMessage`
  and `clubMessage` targets using the same vocabulary
  `admin/messages.js` already uses, and moved the access check **before** the
  existence check, closing an existence oracle. Functions 690 → **699**.
  Still open and tracked below: v2 report rendering in the Moderation Center,
  `removeAndResolve` being globalChat-only, and `reason` having no
  server-side enum on the callable path. See
  [ADR-086](Decisions.md#adr-086-a-safety-action-is-never-gated-on-email-verification-and-every-moderation-endpoint-checks-access-before-existence)
  and [ADR-087](Decisions.md#adr-087-an-idempotency-key-derived-from-a-request-payload-is-a-compatibility-surface--new-fields-fold-in-only-when-the-target-carries-them).

- **Club chat moderation works, and cannot be used to rewrite history**
  (2026-08-19, `b3c27fd` + `f817b41`, **NOT DEPLOYED**): a club owner could
  not remove an abusive message from their own club. `ClubChatService`
  authorised moderator, admin and owner; the rule was author-only; and the UI
  never offered it. All three halves ship together on purpose. The rule
  carries two **disjoint** branches — author retracts, moderator removes —
  separated on `senderId == uid` vs `!=` before any document read, because
  CEL absorbs errors through `||`. Both branches pin `content` to the empty
  string, so editing is not expressible by anyone. The blocker the review
  caught was the mirror image: the create rule had no field allowlist, so a
  plain member could write a message that was **already a forged tombstone**
  — reading as "removed by the club owner", carrying `deletedByRole`
  `superAdmin`, a `senderName` of "YO Voice Support" and a 2099 `sentAt` —
  and it was **unrepairable** by any client path.
  `clubMessageCreateShapeAllowed` closes it. The second pass (`f817b41`)
  fixed an accessibility and visual FAIL: the confirmation dialog silently
  truncated at large text sizes, the message header erased the sender name at
  **default** text size whenever the staff badge was wide (the test fixture
  had been setting `role`/`vip` instead of `staffRole`/`isVip`, so the wide
  case was never exercised), and long-pressing the club owner's message did
  nothing at all — the local refusal copy added in the first pass reached
  nobody. Rules 403 → 446. **UNVERIFIED**: nothing rendered after the
  reworked header and dialog; both review agents died on a session limit.
  Accepted gaps named in the rule's own comment: removals are not
  audit-logged, no rate limit, no restore path, no rank ordering. See
  [ADR-085](Decisions.md#adr-085-authorization-branches-in-a-rule-are-disjoint-by-construction-because-cels--absorbs-errors).

- **Moments becomes a primary destination with a global discovery feed**
  (2026-08-19, `cef05e6`, **NOT DEPLOYED**): Moments was buried in the More
  menu while the product it belongs to is voice-first. It now sits directly
  above Discover in the desktop rail and takes a slot in the mobile dock —
  which has five slots and no room for a sixth, so **Moments displaced
  Friends there**; Friends keeps its desktop rail entry, its More entry, its
  screen and its state, and the trade is asserted in
  `more_destination_nav_test`. Nothing was removed. The screen behind it now
  shows Moments from every user: the service pulls a bounded popular pool,
  weights each Moment by a strictly increasing function of engagement,
  shuffles under a held seed so paging stays stable, and spaces authors
  apart — because Firestore can neither order by a computed sum nor
  randomise server-side. Two composite indexes were added
  (`isPublished`+`likeCount` desc, `isPublished`+`createdAt` desc) and are
  **committed, not confirmed deployed**. Three pre-existing screen defects
  closed with it: a heart and like count with **no tap target**, two
  `snapshot.data ?? []` reads with no `hasError`, and six hardcoded
  off-palette colours in a screen that imports `AppColors`. **UNVERIFIED,
  and it gates the deploy rather than the commit**: nothing has been rendered
  at any width, and the empty state — the state most users on a pre-launch
  product will hit — is unconfirmed. See
  [ADR-089](Decisions.md#adr-089-moments-is-a-primary-destination-and-its-discovery-feed-ranks-client-side-because-firestore-can-neither-order-by-a-computed-sum-nor-randomise).

- **Room chat can no longer be forged, and club discovery can be listed**
  (2026-08-19, `01c0ab2` rules + `155ad61` client, **NOT DEPLOYED**): room
  chat was the largest unguarded client write surface in the product — the
  rule checked `senderId` and membership and nothing else, so an ordinary
  member could write another member's `senderName` and photo, a
  60,000-character body, arbitrary extra fields and a 2099 `sentAt` that
  pinned a message to the top of every member's list permanently. It now
  carries a six-key allowlist matching the keyset
  `functions/achievements/sources.js` already treats as canonical (extra
  fields had been **silently dropping the sender's achievement credit**),
  `senderName` pinned to canonical, `createdAt` pinned to `request.time`, a
  500-character cap and a 32-key bound on reactions. `senderPhotoUrl` is
  deliberately **not** pinned and the residual gap is stated. Club `list` was
  `if false`, so Home's "Discover clubs" rail was denied for everyone
  including a club owner listing their own club; the new rule is written
  entirely in bare field accesses, so the caller's query must carry the
  three equalities, and `watchSuggestedClubs` now sends them. The rail gained
  loading, error, empty and populated states it never had, with `hasError`
  checked before any read of `data`; the same swallowing was fixed where it
  was actively lying, in "Rooms for you" and "From your clubs". Rules 446 →
  **466**; Flutter 948 → 978. **The user-visible defect is not closed**:
  `HomeScreen` is not mounted in the running app, so the rail is still
  unreachable — tracked as item 0n below. See
  [ADR-083](Decisions.md#adr-083-a-firestore-list-rule-is-evaluated-against-the-querys-constraints-so-every-clause-is-a-bare-field-access-and-the-clients-query-carries-the-equality)
  and [ADR-084](Decisions.md#adr-084-client-authored-writes-carry-an-exact-key-allowlist-and-identity-and-time-are-pinned-to-canonical-server-values-or-the-remaining-gap-is-stated).

- **Signing out now actually takes you offline, on every path** (2026-08-19,
  `3d54bc3`, **NOT DEPLOYED**): the offline presence write lived in the
  `authStateChanges()` null branch — after `FirebaseAuth.signOut()` had
  already cleared the session — so the rule's `isSignedIn()` gate denied it
  and `presence_service` swallowed the denial to a `debugPrint`. `isOnline`
  stayed true, `onUserPrivacySourceChanged` mirrored it into
  `socialPresence`, and **a signed-out account showed as online to its
  friends indefinitely.** There were two such writes; the second wrote a
  previous uid under a new identity and failed `isOwner()` just as
  structurally. Both are removed rather than relocated. The FCM token had the
  same shape of bug across five sign-out entry points with five different
  amounts of cleanup, two of which left the previous account receiving push
  on a shared device. Cleanup converged into `AuthService.signOut()`,
  immediately before `_firebaseAuth.signOut()`; both cleanup operations are
  independently bounded, and push revokes its identity epoch and starts token
  invalidation before any offline Future can stall sign-out. Settings, Profile
  and the 2FA path needed no edit at all, which is the convergence working. The tests
  record `_auth.currentUser != null` at the moment of each write, so a write
  recorded outside a live session is one the deployed ruleset denies — 8 of
  10 fail against the pre-fix code. **Not fixed and not fixable from the
  client: process death** — there is no presence sweeper in `functions/`
  (item 0q below). **UNVERIFIED**: presence actually flipping in production
  needs two real accounts. See
  [ADR-090](Decisions.md#adr-090-session-cleanup-converges-on-authservicesignout-because-a-write-the-rules-authorize-by-session-cannot-live-after-the-session-ends).
- **Direct messages became server-only, and an unsendable one now waits in
  a bounded outbox** (2026-08-19, this revision — NOT YET DEPLOYED):
  `conversations/{id}/messages/{id}` create checked `isVerified()` but never
  the sender's account standing, so a banned or communication-muted account
  kept full direct messaging through `_sendTextMessageDirectly`, the client
  fallback that ran whenever `sendDirectMessage` was unreachable — bypassing
  the rate limit and idempotency ledger with it. Adding the missing check to
  the rule was measured against the emulator and **does not fit** in
  Firestore's per-request access-call budget, so the rule is now
  `allow create: if false` and the callable is the sole writer. The fallback
  is replaced by `MessageOutbox`: a bounded (50), persisted queue with
  Pending / Retrying / Failed states that retries under the original
  `requestId` — which the server ledger deduplicates — and drains when
  connectivity returns. See ADR-105. Release gates: Flutter **881/881**,
  Firestore rules **446/446**, `flutter analyze` clean. Storage,
  family-media and Cloud Functions untouched.

  **Deploy the app before the rules.** The reverse order strands installs
  older than this release: their fallback sends will be denied with no queue
  to catch them.

  **Follow-up deployed to web 2026-08-27; native store build pending:** Chat now
  renders the bounded outbox optimistically, reconciles it against the exact
  deterministic server message id, and keeps Pending / Waiting for connection /
  Failed visible with manual Retry and Remove. The composer clears after local
  persistence rather than callable latency, and typing presence is
  transition/heartbeat based rather than one write per character. The one live
  service owns a serialized `messages.outbox.v2.<uid>` queue, resumes it at
  authenticated cold start, preserves FIFO per conversation while allowing an
  unrelated chat through another chat's backoff, and never reassigns the
  ownerless v1 queue across accounts. Enqueue refusal cannot erase a draft,
  local bubbles cannot mask a failed history stream, and leaving the screen
  cancels its shared Firestore listener. The recovery UI passes 320 px and 200%
  text coverage.

- **The 2026-08-18 production-regression wave: room callables, friend
  lists, legacy DM roots, missing indexes** (2026-08-18, `3f28462` →
  `4cad282`, backend DEPLOYED same evening; client fixes in the same-day
  Hosting release): seven room callables (`deleteRoomSelf`,
  `leaveRoomSelf`, `setRoomStatusSelf`, `endRoomVoiceSelf`,
  `setOwnRoomParticipantMute`, `moderateRoomParticipantSelf`,
  `removeRoomParticipantSelf`) had been broken in production since
  2026-08-16 by the firebase-functions v2 two-argument calling convention
  (ADR-078) — room deletion returned INTERNAL and stranded zombie rooms,
  Leave errored after removing the roster row, server-authoritative mute
  failed from the main room screen. Friend-request/friends owner LISTs were
  denied wholesale by wildcard liveness reads in list evaluation (ADR-079)
  — no accept/decline controls anywhere and a 0 friend counter. Every DM
  send and mark-read failed permission-denied on unmigrated legacy
  conversation roots; the 2 threads between living accounts were migrated
  in place (item 0m). The two moment-cleanup schedules had never once
  succeeded (missing composite indexes, ADR-055's failure class —
  `4cad282`). Client side, one shared `RoomMuteCoordinator` now serves the
  room screens and the mini bar (stale sessions are torn down instead of
  looping "not currently live"), `RoomLeaveCoordinator` navigates
  immediately with background cleanup, room deletion uses a simple
  name+cannot-be-undone confirm with friendly errors, Home hides
  mid-deletion rooms and disables ended ones, Discover's empty state stops
  blaming the search phrase for an empty universe, add-friend routes
  requestReceived to a real accept with a decline affordance, watchFriends
  degrades unreadable profiles instead of dropping them, chat mark-read
  runs once per newest message with a visible failure notice, and the
  foreground notification banner is driven by the Firestore stream, not
  FCM. Profile's full-screen header became a compact toolbar + slim banner
  accent (header ≤30% of a phone viewport). Website: PR #2 merged after an
  adversarial review (single-login app hand-off, no tokens in URLs) plus a
  same-PR hardening of `resolveAuthRedirect` against the backslash open
  redirect. See ADR-078, ADR-079, ADR-080.

- **Sign in with Apple provider and dedicated password-reset route**
  (2026-08-18, configuration ready; superseded by the build 6 recovery entry
  above): the former Apple placeholder now uses Firebase's real Apple
  provider with a dedicated Service ID/key, enabled App ID capability,
  regenerated release provisioning profile and runtime availability probe.
  Every configured shipped target enables Apple by default; an explicitly
  disabled build still fails closed.
  “Forgot password?” now opens its own responsive email form instead of
  requiring a value in the login screen. See ADR-068.

- **Owner and senior-staff room deletion has mobile/desktop parity**
  (2026-08-18, `e524497`, DEPLOYED): every room host now sees
  the same Room settings and typed-name Delete room action from a compact
  overflow menu on Home at phone and desktop widths. That action still calls
  `deleteRoomSelf`, whose server boundary requires the caller to be the exact
  canonical `hostId`. Separately, the audited staff shield is now loaded on
  mobile as well as desktop; permanent deletion of any room is granted only
  to `superAdmin` and `superModerator`. A regular moderator cannot invoke or
  see that destructive action. See ADR-075.

- **Device-local Appearance, Polish Beta and offline Voice Moment playback**
  (2026-08-18, web/PWA deployed from `8fa0192`; native store release pending):
  Appearance introduced System/Dark/Light (Light was labelled Beta at this
  point and later graduated as Pearl in ADR-127) and app language offers
  System/English/Polish Beta,
  persisted locally with backward-compatible Dark/English fallbacks. Coverage is intentionally
  initially bounded to the shared theme plus migrated navigation, auth,
  Settings and framework controls. Published Voice Moments can be
  downloaded into account-isolated storage on the current device, with a
  12 MB item cap, 250 MB device/account cap, real usage display, direct native
  file playback, web Cache Storage playback and removal controls. Neither
  feature creates a server database or pretends to synchronize between
  devices. See ADR-072 and ADR-074.

- **Truthful account-wide session revocation** (2026-08-18, Function and
  web/PWA deployed from `8fa0192`; native store release pending): Devices &
  sessions shows the current Firebase token session and can revoke all refresh
  tokens for the caller after a recent-auth check, unregister the current push
  token and sign out locally. It does not
  label FCM registrations as login sessions or fabricate a per-device list:
  Firebase exposes neither individual refresh-token enumeration nor
  per-device revoke. The screen discloses that already-issued ID tokens can
  remain valid for up to one hour. See ADR-073 and
  [ACCOUNT_SESSIONS.md](ACCOUNT_SESSIONS.md).

- **One responsive stage for all room identities and reliable creation**
  (2026-08-17, this revision — NOT YET DEPLOYED): Community, Podcast, Club
  Lounge and Family Lounge now share the same bounded, responsive interior
  with purple, coral/red, gold and emerald identity respectively. Podcast
  writes its immutable authorization type atomically; ordinary Club artwork
  is root-first and generation-pinned by `finalizeClubMedia`; Family creation
  tolerates the older missing-root probe while its complete graph remains the
  authority. Family artwork is intentionally disabled until authenticated
  reads and synchronous revocation replace public bearer-token URLs. See
  ADR-064. Release gates: Flutter **620/620**, Firestore rules **353/353**,
  Storage rules **52/52**, Family media **11/11**, Cloud Functions **579/579**,
  `flutter analyze` clean and the release web build successful.

- **Private photo/voice DMs and reliable Safari Voice Moment uploads**
  (2026-08-17, this revision — NOT YET DEPLOYED): the two chat attachment
  actions were placeholders; they now use server-reserved immutable private
  Storage objects and canonical message finalization. Voice Moment web upload
  preserves the native `MediaRecorder` Blob instead of round-tripping it
  through Dart bytes. Both flows reuse reservation/request/generation state
  after ambiguous network failures. A release review additionally fixed
  pause/resume, recycled media state and an Admin SDK bootstrap that guessed
  the wrong bucket suffix. See ADR-063. Physical iPhone Safari and native
  device verification remain post-deploy checks, not claims made by the
  automated suite. Release gates: Flutter **591/591**, Firestore rules
  **351/351**, Storage rules **53/53**, Family media **11/11**, Cloud Functions
  **572/572**, `flutter analyze` clean and the release web build successful.

- **A `not-found` refusal was read as an undeployed callable, disabling
  every messaging guard and writing conversation roots the backend can
  never touch again** (2026-08-17, UNCOMMITTED — in the working tree,
  NOT YET DEPLOYED; fill in the hash on commit):
  `MessageService._isCallableUnavailable` counted `not-found` as "not
  deployed", but the server throws it as an ordinary refusal
  (`functions/integrity/guards.js:157` for a missing `users/{uid}`,
  `functions/messaging/direct_integrity.js:83` and `:223`). Any user
  without a `users` document therefore bypassed `assertNotBlocked`,
  `assertNotRestricted` and the rate limits on send, edit, delete, react,
  mark-read and typing. On the conversation-open path the swallowed error
  was worse than a bypass: the client created the conversation root
  itself, and since it cannot write `directConversationPairs/{pairKey}`,
  that root fails `validateConversation` with `data-loss` forever.
  `openDirectConversation` is now the only production path and its answer
  stands, success or failure; `conversations` create is `if false` in
  `firestore.rules`; `directConversationPairs` keeps no match block, now a
  recorded decision.
  [ADR-062](Decisions.md#adr-062-the-client-never-creates-a-direct-conversation--canonical-binding-is-server-only-and-a-legacy-thread-is-adopted-in-place-not-forked).
  New `test/direct_conversation_open_test.dart` (18 Firestore-level
  cases), an inverted case in `test/direct_message_send_test.dart` that
  had previously asserted the defective behaviour outright, 3 new checks
  in `firestore-tests/rules.test.js`, and 1 in
  `functions/test/direct_integrity.test.js` pinning the pre-migration
  fork. Suites after: Flutter **573 / 59 files**, rules **351**, Functions
  **564 / 93**; `flutter analyze` clean. **The stranded roots already in
  production are not repaired by this** — that needs the migration run,
  tracked as [item 0m](#0m-run-the-direct-conversation-migration-there-are-stranded-legacy-roots-in-production).

- **Every direct message was being written to Firestore twice — the send
  path now has one writer** (2026-08-17, `8f7aa03`, IN `main`, NOT YET
  DEPLOYED): `MessageService.sendTextMessage` called the
  `sendDirectMessage` callable — which creates the canonical message and
  updates the conversation summary server-side in one transaction — and
  then ran its own client batch **unconditionally**, the early return
  sitting only on the fallback path. Every production send left a second
  message document under a Firestore auto-id and incremented
  `unreadCounts.<recipientId>` twice, and both copies render because
  `watchMessages` orders by `sentAt` with no filter. The branch is now
  inverted: the callable is authoritative when it answers, and the client
  write is reached only when it does not. The fallback was also writing a
  document the server refuses — 14 keys against the exact 16-key set
  `validateMessage` demands, missing `schemaVersion` and `sequence` — so it
  became a `runTransaction` rather than a `WriteBatch`, deriving `sequence`
  from the conversation's `lastMessageSequence` and advancing it.
  [ADR-061](Decisions.md#adr-061-a-callable-that-answers-is-the-whole-write-and-its-client-fallback-must-write-the-same-document).
  **The coverage hole was as much the bug as the code**: every test
  injected a `NotificationService`, which forces the legacy path, so the
  callable-success branch had never executed once.
  `test/direct_message_send_test.dart` (Firestore-level assertions on both
  send paths) and `test/messages_silent_failure_test.dart` (error surfacing
  for reactions, typing presence and un-archive) close it. Suites **546
  tests / 57 files** (from 521/55); `flutter analyze` clean. The duplicates
  already in production are permanent and unmutable — scope and cleanup
  tracked in [Bugs.md](Bugs.md#data-integrity), not here.

- **Voice Moment recording works on the web — until this landed, no
  production user could record one at all** (2026-08-17, `6ef4380` →
  `cefa81a`, DEPLOYED): the recorder called `getTemporaryDirectory()`,
  which `path_provider` does not implement on web, and a broad catch
  turned the resulting `MissingPluginException` into "Could not start
  recording". Web is the only published client, so the entire creator
  content loop was closed with no signal that the platform was the cause.
  The fix is one conditional export
  (`lib/features/moments/data/services/audio_capture/`) splitting **byte
  acquisition and byte upload only** — native keeps file → `putFile`, web
  uses a MediaRecorder blob → `fetch` → `arrayBuffer` → `putData`. State,
  service, reservation, metadata and UI stay single-implementation.
  The audio container is **pinned by the server**, not chosen by the
  client, and the negotiation was measured rather than assumed:
  `MediaRecorder.isTypeSupported('audio/mp4;codecs=mp4a')` is **false** in
  Chromium 148 while `'audio/mp4;codecs=mp4a.40.2'` is **true**, so
  normalizing the codec parameter away before comparing against
  `AUDIO_TYPES` is load-bearing.
  [ADR-057](Decisions.md#adr-057-voice-moment-recording-splits-only-at-byte-acquisition-and-byte-upload-and-the-server-pins-the-audio-container).
  `cefa81a` closed two independent review FAILs — a Flutter-web live-region
  collision that announced a success-sounding line on a failed publish
  ([ADR-058](Decisions.md#adr-058-one-polite-live-region-per-screen-and-errors-go-out-on-the-assertive-channel)),
  and `record_web` collapsing every `getUserMedia` rejection to `false` so
  absent or busy hardware was reported as a browser block. It also fixed a
  `0:60 / 1:00` timer, corrected a preview harness that rendered under
  `ThemeData.dark` instead of `AppTheme.darkTheme`, and migrated the screen
  wholesale onto `AppColors`. **The waveform had been fabricated data**
  (`(index * 17) % 48`), against this project's own no-fake-data rule; it
  now draws the real amplitude stream. Suites **521 tests / 55 files**
  (from 486/54, and 438/52 before this work); `flutter analyze` clean;
  `flutter build web` and `flutter build ios --simulator` both pass.
  Still open, tracked below: Firefox (item 0i) and the legacy publish path
  (item 0j).

- **A suspension now suspends on every room write path** (2026-08-17,
  `c75720a` → `c7cea3e`, DEPLOYED — closes the former backlog item 0b):
  the room-root update rule selected its host branch on `hostId` alone with
  no account-status check, while `isRoomHost()` did check, so a banned or
  disabled host could still edit room metadata and start voice. Four
  conditions now require `isActiveAccount()`: the host room-update branch,
  `isHostAdmittedRoomParticipant()`, `roomMembers` create, and message
  reaction updates. `roomMembers` create mattered independently because it
  gated on `isRestrictedAccount()`, which reads `banned` only and returns
  false when the account document is **absent** — so disabled accounts
  passed. Rules suite **310 passed / 8 failed → 318 passed / 0 failed**.
  Deployed and verified by fetching the live ruleset source through the
  Firebase Rules API and diffing it: **byte-identical to `firestore.rules`
  at HEAD** (see [DEPLOYMENT.md](DEPLOYMENT.md#reading-the-deployed-ruleset-the-verification-standard)).
  `c7cea3e` corrected the comment justifying the broad ternary selector:
  it claimed the tighter variant would be *looser*, and a built-and-measured
  variant is identical, denial for denial — the fall-through it described
  was real only against the `roomMembers` create rule the same commit had
  already closed. Generalized as
  [ADR-060](Decisions.md#adr-060-an-explanatory-comment-is-a-claim-measure-it-or-delete-it).
  The rules design principle is
  [SECURITY.md principle 9](SECURITY.md#firestore-security-rules--design-principles).

- **Production cutover — everything below this line is now LIVE**
  (2026-08-16, `952d8e4`): Cloud Functions 51 → **111** deployed, Firestore
  indexes 14 → **15** composites and 1 → **3** `fieldOverrides`,
  `storage.rules` deployed, `firestore.rules` deployed twice (20:40 and
  21:06), and the Flutter web client released to `app.yovoice.app` —
  verified by fetching `main.dart.js` (5,139,256 bytes, containing
  `publicProfiles`, `searchPublicProfiles`, `selectMyAchievementTitle`),
  not by trusting deploy output. Production had been serving commit
  `9fdd8a9`. The index deploy fixed a silent live defect: the scheduled
  `expirePremiumIdentity` had been failing on a missing composite index, so
  **Premium never expired for anyone**. Ordering lessons — deploy by what
  fails closed; a deployed function nothing calls is inert and looks
  identical to a working one — in
  [ADR-055](Decisions.md#adr-055-the-2026-08-16-production-cutover--order-the-deploy-by-what-fails-closed-and-verify-by-fingerprinting-served-bytes).
  The cutover is **complete, 5/5 steps**: the projection backfill applied
  28 writes and a verification re-run planned zero, and the legacy identity
  scrub cleared 21 documents across four phases with zero conflicts. Two
  numbers worth carrying forward: the apparent "32 accounts missing a
  profile" was really 14, because **18 of the 33 `users` documents are Auth
  orphans**; and the scrub ran *after* the rules, which was the wrong order
  and briefly broke follower lists outright rather than merely leaving
  stale data. Both in [Bugs.md](Bugs.md#data-integrity).

- Private account records split from server-owned public profiles
  (2026-08-16, ADR-054 — the largest change in the repo's history, and
  missing from this list until 2026-08-16): `users/{uid}` became private
  account state, readable only by its owner and listable by nobody,
  including moderator and super-admin client sessions. Public identity
  moved into two exact, server-owned, client-unwritable projections —
  `publicProfiles/{uid}` and `socialPresence/{uid}` — written by the
  retryable `onUserPrivacySourceChanged` trigger, with `onAuthUserDeleted`
  retiring them. People search became the bounded `searchPublicProfiles`
  callable (verified accounts only, prefix-limited, blocks filtered both
  directions, five-field response, per-uid transactional quota because App
  Check is still off). Friendship authority became a pair of server-owned
  `friendshipGuards`; client-writable friend mirrors can no longer mint
  one. New requests and conversations carry no email snapshot. **Note for
  the `yovoice-website` repo**: this repo's Architecture.md told it to
  query user profiles directly from Firestore until 2026-08-16. It cannot.
  See [Architecture.md](Architecture.md#website-integration).
  [ADR-054](Decisions.md#adr-054-private-account-records-are-split-from-exact-server-owned-public-profiles).

- Server-authoritative DM / Voice Moment / achievement actions
  (2026-08-16, `c1d6cd9` — also missing from this list until 2026-08-16):
  the Stage B integrity set, exported via
  `Object.assign(exports, createStageBFunctions())` and deployed in the
  same cutover. Moves DM, moment and achievement mutations off direct
  client writes and onto server-authoritative paths.

- Firestore and Storage rules hardening — seven defects, all live in
  production when found (2026-08-16, `56e7ea7` → `2fc05e5` → `952d8e4`):
  every club promotion and demotion was denied; a private Community room
  became unreadable to its own members and one such room emptied the whole
  Communities list; club avatar/banner uploads were denied; banned accounts
  gained private-room access; role attribution was forgeable because
  `diff().affectedKeys()` reports only *value* changes; a host could
  repoint their membership row at a victim and permanently empty that
  victim's Communities tab remotely; and `2fc05e5`'s own eviction path
  created a trap in which a host — or ordinary counter drift — made rooms
  nobody could leave. That last one was fixed by **removing rules-level
  eviction entirely** rather than guarding it
  ([ADR-056](Decisions.md#adr-056-a-moderation-action-belongs-in-a-callable-that-completes-the-whole-removal-not-in-a-rule-that-deletes-one-row)).
  Rules suite 268 → **301**, Storage 43 → **46**, family-media 11.
  ADR-005's claim that a bad `collectionGroup` top-level rule fails closed
  was **disproved by experiment and corrected** in `794454b` — it fails
  OPEN, returning every document in the collection group across the whole
  database.

- Public-stats publisher, held back deliberately (2026-08-16, `cb4651a`):
  `publishPublicStatsSchedule` is committed and **not deployed**, behind
  three stated preconditions. Functions suite 487 → **510** across 82
  suites. Also on this date: a manual dry-run-by-default public-profile
  backfill workflow (`4f9ad47`, not yet run) and a CI fix for a
  concurrency-sensitive absolute assertion that had turned three
  consecutive pushes red (`38b29f7`).

- Compact Profile journey + capability-specific Premium boundaries
  (2026-08-16): replaced the four desktop-stretched journey panels with one
  intrinsic-height list that keeps the same real Communities, Messages, Voice
  time and Rooms created values at phone and desktop widths. Creator account,
  Creator Studio and the More → Clubs hub now require the matching capability
  from the trusted `entitlements/{uid}` document at the menu, navigation,
  destination and save boundaries; a public VIP/Premium badge never grants
  access. Existing club memberships/invites and Family Rooms remain free, and
  ordinary Club creation still has its server gate. The real seven-document
  Club creation batch is now accepted atomically: owner-member/default-channel
  rules read the post-write Club via `getAfter()`, and the unused root-user
  `clubCount` write that sat outside the profile allowlist is gone. The same
  pass closed the
  `users/{uid}` first-create loophole that could seed Creator, Premium or staff
  fields before update rules applied, plus the Club-invite path that let an
  invitee create an owner/co-owner/admin membership. Verified at the time
  with 396/396 Flutter tests across 41 files and 225/225 Firestore emulator
  cases; current counts are 521 across 55 files and 318 — see
  [TESTING.md](TESTING.md#current-counts). **These rules were
  DEPLOYED on 2026-08-16.** This entry read "The new Firestore rules still
  require a manual deploy" until then. Store verification adapters remain
  unconfigured, so the protected-owner-only `adminSetPremiumEntitlements` is
  still the only working grant path — and note that Premium expiry had never once run in
  production until this date's index deploy (see
  [Bugs.md](Bugs.md#infrastructure)). See
  [ADR-053](Decisions.md#adr-053-paid-capabilities-come-only-from-the-trusted-entitlement-and-every-entry-boundary-fails-closed).

- One real startup transition instead of two timed loaders (2026-08-16): the
  landing `/app` hand-off now redirects immediately, the authenticated
  four-second welcome delay is removed, and direct/landing entry share one
  app-owned animated voice-wave surface using the existing `YO VOICE` and
  `Create your space` copy. Its enlarged, lowered mark sits behind the title for
  a responsive lock-screen-style depth effect. It disappears after the first
  Flutter frame/Auth resolution rather than after a fabricated countdown. See
  [ADR-052](Decisions.md#adr-052-the-app-origin-owns-the-only-startup-surface-and-no-startup-animation-imposes-a-minimum-delay).
  Follow-up deployed to web (2026-08-27; native build pending) replaces transparent/missing
  native launch art, matches one centred 170 logical-pixel mark through the first Flutter
  frame, smooths ring/wave boundaries, and crossfades Auth state without adding
  a minimum delay.

- One canonical logo across favicon and app launchers (2026-08-16): replaced
  the retired black-square source used by native generation with the exact
  favicon mark, regenerated Android adaptive/legacy and iOS/App Store icons,
  and aligned macOS, Windows and the in-app compact logo. Opaque store assets
  use only the required full-bleed product background. See
  [ADR-051](Decisions.md#adr-051-the-transparent-favicon-mark-is-the-canonical-logo-source-for-every-platform).

- Audible and visible push-notification presentation (2026-08-15): created
  the missing high-importance Android notification channel, made foreground
  native pushes request alert/sound/vibration, added a compact actionable
  banner for focused web tabs, and hardened the FCM payload for Android, APNs
  and web. The payload contract is unit-tested and the banner is covered at
  320, 390 and 430 px. See
  [ADR-050](Decisions.md#adr-050-push-presentation-is-explicit-per-platform-and-focused-web-tabs-use-an-in-app-banner).

- Original event sound system (2026-08-18): synthesized eight compact YO Voice
  cues for room creation, local room join/leave, remote participant join/leave,
  microphone mute/unmute and notifications. Playback is lazy, failure-isolated,
  burst-coalesced and controlled by one device-local Sound effects preference.
  Android/iOS notification payloads use the matching packaged cue, while the
  web foreground banner uses the in-app player. See
  [ADR-076](Decisions.md#adr-076-product-sounds-are-original-bounded-and-reserved-for-meaningful-events).

- Velvet Prism product-sound redesign (2026-08-27, **HOSTING DEPLOYED; NATIVE
  BUILD/FCM CUTOVER HELD**): replaced the rejected glass-bell/pentatonic jingles with eight
  95–360 ms material cues built from a filtered contact, muted inharmonic body
  and quiet air layer. One deterministic Python authority now writes the app,
  Android and iOS masters; notification bytes are identical, Android moves to
  the versioned v3 channel, native FCM and the Firestore banner cannot both
  sound, and room creation no longer chains into a second join cue. Playback
  is serialized per channel and Android UI cues request no media audio focus.
  Physical phone/headphone/LiveKit/Bluetooth listening remains the release
  gate. See
  [ADR-116](Decisions.md#adr-116-product-sound-is-a-material-feedback-system-not-a-set-of-jingles).

- Achievement ledger incident repair (2026-08-19): ended three infinite
  trigger retry loops (`activeDay` dedup entries fingerprinted the exact
  event time under a per-day identity, so a user's second action of a UTC
  day was an unresolvable collision the engine answered by throwing
  forever) and unwedged `reconcileAchievementsV1`, stalled on its very
  first user since 2026-08-16 by a malformed partial failure record.
  Fingerprint mismatches are now terminal (quiet replay for
  same-content-different-time recurrences, logged collision otherwise),
  activeDay content derives from (uid, day) alone, and the migration
  recovers per-user instead of stalling globally. All 12 achievement
  functions redeployed and the four pre-fix ledger entries plus the poison
  record repaired in production, commit `138085a`. See
  [ADR-081](Decisions.md#adr-081-ledger-fingerprint-mismatches-are-terminal-and-canonical-content-is-a-pure-function-of-the-events-identity).

- Achievements end-to-end repair (2026-08-15): fixed the Firestore self-write
  allowlist that rejected every atomic achievement update because
  `unlockedTitleTimestamps` was missing, added an emulator regression for the
  full counter/unlock/timestamp/selection write, initialized timestamp maps on
  new profiles, and made Awards reconcile real counters whenever it opens.
  Category chips now state earned/available counts (`0/30`) instead of the
  misleading bare zero. Verified with the source-event suite, clean static
  analysis and all 211 Firestore rules cases. See
  [ADR-049](Decisions.md#adr-049-achievement-updates-are-one-allowed-atomic-write-and-awards-reconciles-source-owned-counters-on-open).

- Global Chat retired from the app UI; Home recent-chat preview
  (2026-08-15): the public Global Chat entry point and Home feed were
  replaced on mobile and desktop by `Your recent chats`, backed by the
  existing private `conversations` stream. It shows at most the three
  newest non-archived chats side by side, with real avatars, previews,
  unread counts, direct navigation to the existing DM screen and honest
  loading/empty/error states. Existing Global Chat Firestore data and
  compatibility rules remain untouched so older clients and moderation
  history are not broken. See [ADR-048](Decisions.md#adr-048-global-chat-is-retired-from-the-app-ui-and-home-previews-three-real-private-conversations).

- One-shell navigation + Moderation console redesign (2026-08-15):
  every More destination (Staff Center included) now swaps the desktop
  shell's content slot in place — the page-shift on opening Staff
  Center is gone, pinned by a slot-contract test — and staff screens
  adapt chrome to context (shell slot: breadcrumb, no app bar; pushed
  route: Back + Home + human role badge). The Moderation Center became
  a responsive console: summary aggregates, status segmented control,
  search + filter sheet/dialog with active chips, 900px master-detail,
  coherent empty/loading/error states. CLAUDE.md now carries the
  three-breakpoint completeness rule. See
  [ADR-047](Decisions.md#adr-047-one-shell-one-slot-per-more-destination-staff-screens-adapt-chrome-to-how-they-were-opened-three-breakpoint-completeness-is-a-hard-rule).


- Staff Center redesign + owner user search that actually finds people
  (2026-08-15): the production lookup failure (mixed-case usernames
  stored as typed vs. a lowercased case-sensitive equality) is fixed by
  a server-only `userDirectory` index with normalized search fields,
  searched exclusively through the owner-only `searchUserDirectory`
  callable — exact uid, case-insensitive email, username with or
  without `@`, exact display name, and case-insensitive prefix over
  both, always as a result list. Staff Center itself became seven
  capability-gated sections (Overview / Users / Reports / Rooms &
  Spaces / Sanctions / Staff & Roles / Audit Log) behind an internal
  rail, every counter a real `count()` aggregate and every list a real
  query, with a user detail drawer carrying authoritative status,
  history and confirm-with-reason owner actions. Full mobile parity
  landed the same day: the mobile More sheet gained a capability-driven
  Staff section (owner/super-moderation → Moderation plus Staff Center,
  moderation → Moderation, derived from getMyStaffCapabilities alone), the
  same screens rendering natively at phone widths with tab chips and
  full-width detail drawers, verified at 320/390/430 with rendered and
  live 390×844 inspections. See
  [ADR-046](Decisions.md#adr-046-user-search-lives-in-a-server-only-directory-behind-an-owner-callable-staff-center-becomes-seven-capability-gated-sections).
  A 2026-08-27 web-deployed density follow-up reduces ordinary More destinations
  to 78 px tiles and staff/settings to 58 px rows: ordinary 320×568 and owner
  390×844/430×932 sheets fit without scrolling, while enlarged text reflows to
  full-width scrollable rows.

- Authoritative identity badges on every surface (2026-08-15): one
  shared badge system (`OfficialRoleBadge` / `VipBadge` /
  `UserIdentityBadges` / `DecoratedUserAvatar`) renders the official
  role — USER included, always visible — plus a separate VIP badge on
  every identity surface: profile card/headers/preview sheet, Global
  Chat, DMs, room chat, Club & Family chat, stages, rosters, participant
  sheets, Moments and comments, the People & Moments rail,
  friends/follow lists, search, Discover cards, Top creators,
  notifications, Staff Center and Moderation Center. Resolution goes
  through a batched `PublicIdentityRepository` over the `getPublicBadges`
  callable (no N+1 reads, USER fallback, cache cleared on account
  switch, invalidated after role changes); message-embedded staff flags
  are no longer trusted for rendering. Server-side, badge derivation is
  now owner-guarded: a forged non-owner `superAdmin` publishes as
  `superModerator` and raises the security audit event, with the same
  demotion applied to stale stored rows in the batch callable, and the
  backfill refusing to run without the owner secret. `AchievementStyle`
  is reserved (cosmetics only, contract documented) but deliberately not
  built. See
  [ADR-045](Decisions.md#adr-045-one-authoritative-identity-badge-system--owner-guarded-derivation-a-batched-client-repository-and-a-single-family-of-badge-widgets).

- **SUPERSEDED by ADR-114** — server-derived social notifications
  (2026-08-12): friend requests,
  acceptances and follows are no longer a best-effort second client
  write. Three Firestore triggers derive them from the authoritative
  documents, with deterministic ids so an at-least-once redelivery
  cannot duplicate a row, and the three types were removed from the
  client-creatable set so they can no longer be forged. Proven
  end-to-end through the real triggers in the emulator: 13 pipeline
  stages, from the source write to the recipient's bell feed and unread
  badge. 224 Flutter tests, 173 rules tests, 65 Functions tests.
  This records the historical ADR-041 trigger rollout; those three trigger
  writers were retired in production by ADR-114's single-writer rollout on
  2026-08-25
  ([ADR-041](Decisions.md#adr-041-friend-request-acceptance-and-follow-notifications-are-derived-from-their-source-documents-by-firestore-triggers-not-written-by-the-acting-client)).
  At that time web push was still broken for a separate, documented reason.
  Its service worker, VAPID and payload configuration are now fixed, while a
  real-browser push E2E remains unverified; `@mentions` are not started.

- Moderation Center completion pass (2026-08-11): each report now shows
  its own moderation history, served by a new scoped
  `listReportAuditTrail` callable rather than the broad
  `listAdminAuditLogs` browser — the caller sends a report id and both
  target ids are derived from the report server-side, so there is no
  parameter that reaches another report or an unrelated admin action,
  and `adminAuditLogs` stays denied to every client. Report-workflow and
  content-removal events are shown as distinct kinds, never merged. The
  queue's target and reason filters became real server-side clauses with
  a composite index per combination, replacing the in-memory narrowing
  that made a filtered page look like a filtered collection. 224 Flutter
  tests, 170 rules tests, 54 Functions tests and two emulator smoke
  tests pass; the populated detail and timeline were rendered and
  inspected at 1440×820, 1440×620 and 1100×820. **Deployed 2026-08-16** —
  this entry read "Needs the ordered deploy in DEPLOYMENT.md" until then;
  `moderateReport`, `listReportAuditTrail` and the `reports` indexes are
  all live, per
  [DEPLOYMENT.md](DEPLOYMENT.md#production-state-as-of-2026-08-16-post-cutover)
  ([ADR-040](Decisions.md#adr-040-a-reports-audit-trail-is-served-by-a-scoped-callable-not-by-the-admin-audit-browser-queue-filters-are-server-side-clauses)).

- Staff Moderation Center (2026-08-11): desktop-only report triage,
  reached from the existing More popover — listed only for accounts that
  pass the staff check, opening in a fixed-shell content slot. The rail
  keeps its six items. Staff authority is the signed `role` claim AND the
  server-written `users/{uid}.role` mirror AND an unrestricted account,
  so a revoked role stops working on the next request instead of
  whenever the ID token expires. Triage runs through a new
  `moderateReport` callable — `firestore.rules` denies client writes to
  report workflow fields outright, so one path enforces the state
  machine (`open → inReview → resolved|dismissed`), refuses to overwrite
  another moderator's active claim, is idempotent on a caller-supplied
  requestId, soft-deletes a reported message and resolves its report in
  one transaction, and writes a deterministic audit entry. Banning stays
  admin-only, as `setUserBan` always was; moderators get an escalation
  note rather than a button that would be refused. 203 Flutter tests,
  170 rules tests, 30 Functions tests and two emulator smoke tests pass.
  **Needs a rules + indexes + functions deploy**
  ([ADR-039](Decisions.md#adr-039-the-moderation-center-is-a-staff-gated-more-destination-triage-is-a-callable-and-staff-authority-is-claim--server-record)).

- Global Chat + the rail's Voice Moment action (2026-08-11): the
  Conversations module's `All` tab is gone — merging a public channel
  into someone's private chats presented the two as the same kind of
  thing. The tabs are now `Global` (first, default), `Friends`, `Clubs`,
  `Private`, and Global is a REAL shared community channel:
  `globalChat/main/messages`, one canonical conversation for every
  authenticated account, embedded in Home as a paginated live feed with
  a composer, Creator/Team badges validated server-side, and
  removed-message, empty, loading, offline and error states. Sends are
  direct client writes under Security Rules (per ADR-013), with a
  rules-enforced 3s cooldown built on a `getAfter()` cooldown document
  bound to the specific message id, so a batch cannot buy N sends for
  one slot. Soft delete only, by the author or a role-claim moderator,
  with an `adminAuditLogs` entry written by the new
  `onGlobalMessageModerated` trigger whenever a moderator removes
  someone else's message. A `reports` collection was added (create-only
  for members, staff-read) because the product had no reporting at all
  before opening a public channel. The desktop rail regained
  `Create Voice Moment` beneath `Create Room`, wired to the same single
  recorder the Moments strip and mobile Home use. 128 emulator rules
  tests (28 new) and 174 Flutter tests pass. **Needs a rules + functions
  deploy and one manually created `globalChat/main` document**
  ([ADR-037](Decisions.md#adr-037-global-chat-is-one-canonical-public-channel-written-directly-under-security-rules-with-a-rules-enforced-rate-limit)).

- Desktop Home modules + app favicon (2026-08-10): the three empty
  regions of the desktop Home are now real modules — "Moments from your
  circle" between the greeting and Live around you
  (`HomeFeedService.watchSocialMoments`, one tile per person, ring/"New"
  = posted in the last 24h because `voiceMoments` has no seen flag),
  a "Conversations" hub under For you with All/Clubs/Friends/Private
  filters over the existing `MessageService` + `ClubService` +
  `FriendService` data (filters are local state; the shell never
  rebuilds), and "Top creators you follow" under the Premium card
  (`FollowService.watchFollowing`, live signal from `rooms.hostId`,
  never fabricated follower counts, never silently swapped for suggested
  people). The two "For you" gradient slabs became compact dark-glass
  editorial cards (cover, LIVE, title, host, topic, real chips, avatar
  stack, count, Join); `Your circle` lost its duplicate "Start a room"
  button and gained a real online count. Live around you scrolls at a
  readable card width near the 1100px breakpoint instead of ellipsising
  every room name. The browser tab now uses the same clean transparent
  YO Voice symbol as the landing page — the old RealFaviconGenerator set
  had a solid black square baked into every size; regenerated from
  `yovoice-website/src/app/icon.png`, with `favicon.svg`/`favicon.zip`/
  `favicon.png` and the `flutter create` `manifest.json` + `icons/`
  leftovers deleted, `?v=` cache-busting and a Hosting `no-cache` header
  for the icon files. Mobile Home, the rail, More, Notifications and
  every backend surface untouched
  ([ADR-036](Decisions.md#adr-036-desktop-home-is-composed-of-real-source-modules-each-one-states-the-state-it-cannot-prove)).

- Post-landing entry transition (2026-08-09, `yovoice-website` `7c623f1`;
  the `web/index.html` half landed here in `8115f56`): the jump from
  `yovoice.app` into the Flutter web app is now a ~2.8s animated launch
  screen on a single route (`yovoice-website` `/app`) instead of seven
  scattered instant cross-origin links and a bare `Loading…`. Reuses the
  shipped mark unaltered, existing Framer Motion, existing theme tokens;
  progress is bound to real initialization (auth resolution, mark decode,
  webfonts) and parks at 92% rather than inventing a percentage. Hands
  off with `location.replace()` so it never becomes a back-button trap.
  `web/index.html` in this repo now paints `AppColors.background` so the
  hand-off no longer flashes white — **this half only takes effect on the
  next Flutter web deploy**
  ([ADR-035](Decisions.md#adr-035-one-launch-route-app-owns-the-hand-off-into-the-application-the-flutter-host-page-paints-the-apps-background)).
- Mockup visual overhaul — Home + rooms + Premium (2026-08-09): M1 Home
  Live Social Hub (real-data VoiceCore hero, Your People status row,
  `c979d20`); M2 room chat + reactions in both room types and From your
  Clubs on Home (`ee30f6f`, rules deployed); M3 Premium presentation
  (board screen 3) + dedicated plans screen (board screen 4) — the old
  single paywall split into `PremiumScreen` (marketing presentation with
  the member's real avatar in the canonical premium ring) and
  `PremiumPlansScreen` (toggle, side-by-side plan cards, real
  `verifyPurchase` wiring; decline path live-verified against production)
  ([ADR-031](Decisions.md#adr-031-premium-is-two-surfaces--presentation-and-plans-the-hero-is-the-members-real-identity));
  website Premium surfaces aligned to the same language
  (`yovoice-website` `ed606b3`); board screen 5 profile refinement —
  header chips row (AccountTypeBadge + server-mirrored
  `PremiumIdentityChip`), compact stat formatting (1.8K), website chip
  in Voice identity, owner crown + "· Owner" on owned club tiles (all
  real-data-conditional; no XP bar or Moments/Activity tabs — those
  systems don't exist and honesty wins over the mockup); board screen 6
  club room rebuild — lounges route into the shared community shell with
  club banner/teal identity and lounge-aware leave, plus the canonical-
  identity fix for all room writes
  ([ADR-032](Decisions.md#adr-032-club-lounges-are-club-identity-rooms-on-the-shared-community-shell-room-writers-source-identity-from-the-profile-document)).
  The later responsive room-workspace pass replaced the detached recent-
  message overlay with a bounded desktop stage + chat rail and full-width
  Stage/Chat views on compact devices; it also removed synthetic silence
  prompts from every room identity.
  Still open: live club-room verification (blocked on a Premium grant —
  `adminSetPremiumEntitlements` has no caller UI), responsive matrix,
  remaining two-user checks.

- Rooms 2.0 — M1/M2/M3/M8 (2026-08-09): LiveKit-authoritative MicState
  + mute-race fix; Podcast rename (ADR-029); scalable stage system
  replacing the orbit, verified at 2/10/50/500 participants (ADR-030);
  promotion/demotion token refresh; floating navigation dock with
  Friends as a primary tab. Remaining milestones (covers/cards,
  whiteboard, permissions, analytics, Spotify
  feasibility, landing page) tracked in the session task ledger.

- Product-audit hardening pass (2026-08-08) — CI now gates deploys on
  `flutter test` + the Firestore AND Storage rules suites (run against
  real emulators in the workflow); `storage.rules` got its first
  emulator test suite (`firestore-tests/storage.test.js`, 22 checks)
  and the profile-upload cap dropped 10 MB → 2 MB with test proof;
  Crashlytics installed as the production crash channel (iOS/Android;
  debug builds excluded)
  ([ADR-027](Decisions.md#adr-027-ci-gates-on-the-full-test-suite-crashlytics-is-the-production-crash-channel)).
- P0/P1 bugfix + profile media pass (2026-08-08) — (1) raw
  Dart/Firebase exception text can no longer reach the UI: root cause of
  the "Dart exception thrown from converted Future" chat error was a
  Firestore rule evaluation error on `transaction.get()` of a
  not-yet-existing conversation (rules fixed + deployed), and every
  `error.toString()` render was replaced with
  `intentionalOrFriendly()`/`friendlyErrorMessage()`
  (`lib/core/helpers/error_messages.dart`, `test/error_messages_test.dart`);
  (2) accepting a friend request now notifies the ORIGINAL SENDER —
  `notify()`'s dedupe query was permission-denied and silently killed the
  write; replaced with deterministic dedupe doc IDs
  (`test/friend_accept_notification_test.dart`); (3) More destinations
  keep the persistent bottom navigation via `MoreDestinationHost`
  ([ADR-026](Decisions.md#adr-026-more-destinations-re-host-the-shells-bottom-navigation-amends-adr-019),
  `test/more_destination_nav_test.dart`); (4) real avatar/banner crop
  editor — pinch-zoom/drag/reset, circular avatar preview, 16:9 banner
  frame, final cropped JPEG uploaded
  ([ADR-025](Decisions.md#adr-025-profile-media-crop-editor-ships-the-final-cropped-jpeg-not-crop-metadata),
  `test/image_crop_test.dart`).
- New message sheet grey-panel fix — `FriendService.watchFriends()` now
  returns a broadcast + last-value-replay stream, so the sheet can share
  one stream instance with `_FriendsRow` without throwing
  `Bad state: Stream has already been listened to` and rendering Flutter's
  grey `ErrorWidget` over everything below the search field. Sheet also
  owns a real `Material` surface and has a distinct dark error state.
  ([ADR-020](Decisions.md#adr-020-service-streams-shared-by-more-than-one-widget-must-be-broadcast--replay),
  `test/new_message_sheet_test.dart`, `lib/dev/new_message_preview.dart`.)
- Profile image save semantics + validation — avatar/banner are picked and
  validated (JPEG/PNG/WebP sniffed from magic bytes; 5 MB/1024 px and
  10 MB/1920 px budgets in `ProfileImageRules`), previewed instantly from
  memory in Edit profile, and committed on Save alongside the text fields
  instead of uploading the instant they are chosen.
  ([ADR-021](Decisions.md#adr-021-profile-images-are-pending-local-changes-until-save).)
- Voice Rooms — broadcast, podcast, and community rooms; host/speaker/
  listener roles; hand-raise; moderation; live participant management.
- Clubs — channels (chat + voice), member roles, invites, ownership
  transfer (`2c27c6e`).
- Friends system — requests, blocking, mutual friends, suggestions
  (`2abda0a`).
- Friends lifecycle hardening — one transactional notification writer,
  actionable request deep links, cancel/accept/decline cleanup, replay-safe
  generation-specific re-requests/refollows, compatibility-row suppression,
  account-switch FCM token rotation, mobile unread badge, resilient blocked
  rows and 44 px Add Friend actions (ADR-114).
  **DEPLOYED 2026-08-25** — Rules, ordered Functions cutover and byte-verified
  Hosting; physical two-device FCM presentation was explicitly not performed.
- Direct messages + club channel chat.
- Voice Moments — recorded audio posts, likes, comments, voice replies.
- Achievements/Awards — full 100-title catalog; Level/XP header, category
  filters, and a real (not fabricated) "recent unlocks" feed backed by
  per-achievement unlock timestamps (`6cfd208`, [ADR-010](Decisions.md#adr-010-real-per-achievement-unlock-timestamps)).
- Creator Studio — real dashboard over owned rooms/clubs/Voice Moments with
  working quick actions, truthful snapshot Analytics, and one server-verified
  pinned published Voice Moment shown on profiles (`6cfd208`, ADR-065).
- Settings — full account/privacy/security/notifications/permissions/
  storage/legal/danger-zone screen, backed by real Firebase Auth,
  `permission_handler`, and image-cache stats (`6cfd208`).
- Notifications — in-app center + deep-link routing (`a4c78c6`), triggered
  from real friend/follow/club/room/message events (`1760a6f`), preferences
  screen (`467b6c8`).
- Email verification flow (Flutter) — full journey, gates outbound/
  content-creation actions on `email_verified` (`a21d00d`, `04882cc`),
  `ActionCodeSettings` wired into password reset too (`14cc7f7`).
- Email deliverability fixed — moved off Firebase's default sender to
  Resend SMTP ([ADR-008](Decisions.md#adr-008-resend-smtp-instead-of-firebases-default-email-sender)).
- Firebase App Check — client-side integration
  ([ADR-004](Decisions.md#adr-004-firebase-app-check-integrated-client-side-enforcement-deliberately-off));
  enforcement itself is tracked below, not done.
- Two production-breaking `collectionGroup()` query bugs found and fixed
  (`watchMyCommunities`, `watchMyClubInvites`) —
  [ADR-005](Decisions.md#adr-005-roomsroomidmembers-renamed-to-roommembers),
  [ADR-006](Decisions.md#adr-006-top-level-collectiongroup-wildcard-rules-stay-read-only-and-narrow),
  [ADR-007](Decisions.md#adr-007-firestore-rules-changes-are-always-emulator-tested-against-a-real-collectiongroup-query).
- 12 of 13 findings from the security audit fixed —
  [ADR-003](Decisions.md#adr-003-security-fixes-move-permission-authority-to-the-server),
  current status in [Bugs.md](Bugs.md#security).
- `yovoice-website` — Firebase Auth wired in (login/register/forgot-
  password/verify-email), account section, SEO/metadata foundation,
  full design-system rebuild (pill buttons, glass panels, reusable
  `src/components/ui/` library), 15 new marketing pages.
- Home rebuilt as one room board, both surfaces (2026-08-13): the three
  overlapping room sections collapsed into a single ranked, deduplicated
  column of full-bleed cover banners shared by desktop and mobile, a
  combined `People & Moments` rail (presence dots, VIP from
  `premiumIdentity`, Follow through the existing `FollowService`),
  `View all` on both room sections, a dashed `Create room` tile, and
  cover thumbnails plus listener counts in Voice Trending. Two write-only
  per-room roster subscriptions removed. See
  [ADR-043](Decisions.md#adr-043-home-is-one-room-board-of-full-bleed-banners-presence-vip-and-follow-on-the-rail-come-from-existing-server-written-sources).
  NOT built, and why: the mockups' `SCHEDULED` banner with a date (rooms
  carry no start time in Firestore) and the mobile rail's people segment
  (`MobileMomentsStrip` still shows Moments only).
- Find Creators identity taxonomy corrected (2026-08-24; **DEPLOYED
  2026-08-25**, Hosting byte-verified): every directory result now presents the
  account status `Creator`, while the server-owned
  legacy `official` value adds a separate `Verified by YO Voice` badge. The
  directory filters are `All creators` and `Verified`; wire values, callable
  queries, rules and stored profiles are unchanged. See
  [ADR-112](Decisions.md#adr-112-find-creators-presents-official-as-a-verified-creator-not-a-separate-account-type).
- Family Room, first slice (2026-08-13): a fourth creation choice on the
  Create screen, implemented as a Club with `type: family` at the
  deterministic id `family_{uid}` — reusing club membership, roles,
  invites, chat, announcements and the private lounge rather than
  building parallel systems. Free to create (ordinary Clubs stay
  Premium-gated), invite-only, and invisible to non-members at the rules
  level. See
  [ADR-044](Decisions.md#adr-044-family-room-is-a-club-with-type-family-pinned-to-a-deterministic-id-with-a-private-read-boundary).
  The creation path is now end-to-end verified: the deterministic missing-id
  probe, owner membership, user projection, chat, announcements, voice
  channel and Family Lounge must commit as one seven-write batch; reopen and
  concurrent retry converge on that one graph, and the selected banner is
  preserved. Quick check-ins and invitation accept/decline are implemented
  and tested. Still to build: production Family Moment recording/upload;
  Storage rules alone are not a shipped user-facing feature.
- Saved Vibe on the full profile (2026-08-28; **RELEASED TO WEB, TESTFLIGHT
  BUILD 10 AND ANDROID INTERNAL BUILD 10**): `statusMessage` now appears on
  both the signed-in Voice identity card and the full friend-profile route
  through one responsive headline. Vibe alone counts as a populated identity,
  a website-only identity no longer falls into the empty state, the exact
  80-character editor limit remains readable at 320 px/200% text, and long
  website values are bounded. The pinned Hosting artifact was byte-verified;
  App Store Connect shows build 10 as Testing in the permanent internal and
  external groups, while Google Play shows version code 10 available to the
  11-account internal cohort. Full Flutter VM: 1410/1410; analyze: clean.
  A 2026-08-29 source follow-up makes every safe HTTPS URL in that shared Vibe
  actionable on own profile, another member's profile and Profile Preview.
  Provider-aware 48 px link rows open through platform universal links, while
  strict public-host validation prevents untrusted Vibe text from receiving a
  music-brand label or launching local/custom-scheme destinations. Keyboard,
  link semantics, double-fire, failure, disposal and 320 px/200% behavior are
  regression-tested. See ADR-126. The native change waits for the next
  coordinated tester build rather than creating a one-off store upload. A
  second 2026-08-29 web-released follow-up separates Vibe and Voice identity
  accents from their surfaces: Vibe is now a quiet semantic card, provider
  actions use the tertiary cyan/teal role, identity chips are neutral with
  external/voice/learning accents, and inline failure uses the paired error
  roles. Real Dark/Pearl production-card frames at 320/390/768/1440 px and
  320 px/200% text plus automated contrast gates prevent another
  purple-on-purple regression. Both Hosting domains serve the byte-identical
  verified bundle (SHA-256 `1a23f11d8e816a0d`, 6,445,943 bytes); the native
  tester build remains held for the coordinated queue release.
- Full documentation system — Vision/Architecture/Features/Roadmap/
  Firebase/Backend/Flutter/UI/Decisions/Bugs plus this evolution pass
  (`02275bd`, `26d11a2`, and this session's commit).

---

## In Progress

### Build 20 YO Moments, Voice read v2, Reels retention and moderation candidate

- **Status**: **Both invited tester channels available on 2026-09-05;
  functional acceptance remains open.** Mobile/Web runtime `941376e` is live
  on both Hosting domains; Google Play code 20 is
  available to the existing 15-person internal cohort (10:36 CEST). Both
  signed artifacts were uploaded once; iOS processing completed and its
  internal cohort of one is assigned and the existing external cohort of six
  has Build 20 `Testing`. Five non-owner TestFlight testers show `Installed 20`
  at 12:07/12:11/12:13 CEST observations, and the user separately confirmed
  availability. The older cleanup P1 found in post-deploy logs is repaired
  with independently verified recovery; external TestFlight advanced afterward.
  Twenty separate plain-text emails have verified Gmail `SENT` evidence, but
  four confirmed hard bounces and reported spam leave email deliverability
  blocked. Manual resends are paused. One owner-only probe from the authorized
  `hello@yovoice.app` domain alias reached Inbox in twelve seconds with
  SPF/DKIM/DMARC PASS; tester deliverability remains unresolved. Marketing
  commit `975e5c6` was pushed to its own `main`, deployed successfully on
  Vercel and passed live HTTP 200/content read-backs for home, updates, download
  and features, preserving the historical Build 19 updates anchor.
  This is not public-store or physical-device acceptance.
- **Description**: Build 20 presents Voice Moments and Reels through one
  localized YO Moments destination. Foreign Voice Moment feed/detail data now
  comes from bounded, server-owned v2 projections; likes use server-owned
  mutation and stale auth/lifecycle generations fail closed. The legacy v1
  direct-read compatibility boundary remains deliberately available for Build
  19 until observed adoption and a separately authorized cutover. Reels adds
  bounded availability, retry/lease cleanup and moderation-safe retention;
  canonical Voice Moment reports can be actioned without trusting client object
  paths. The source adds four required composite indexes plus managed TTL on
  `reelCleanupOutbox.deleteAfter` and
  `voiceMomentReportReceipts.expiresAt`.
- **Measured evidence**: analysis clean; complete Flutter 2255/2255; Chrome
  18/18; production Flutter Web build PASS; Playwright built-artifact smoke
  2/2 PASS; YO Moments screenshot harness 50/50; dock Dark/Pearl screenshot
  harness 8/8; Voice re-review 84/84 APPROVE; Functions 1277/1277 in non-
  overlapping shards after an emulator transaction-lock hang; Firestore Rules
  524/524; Storage Rules 67/67; Family media 11/11; Functions smoke and
  deterministic sound-asset checks PASS. Inspected PNGs show Frame Echo Clean
  without internal lines/skew or observed overlap. Production npm audits
  report 0 vulnerabilities in both `functions` and `firestore-tests`; physical
  visual acceptance remains pending. CI `33950203890`, browser smoke
  `33950203943`, CodeQL `33950203888` and Hosting `33954305037` are green for
  the frozen runtime. Both live domains match the Hosting artifact and
  required headers. Index/TTL readiness, Functions/Rules read-backs and the
  explicit one-pair reconciliation/no-op post-check are complete; unchanged
  Storage Rules were not redeployed.
- **Backend follow-up**: `06e94c6` fixes the shared cleanup allowlist for
  expired direct-message video reservations (`mp4|mov|webm`), retaining all
  canonical path/owner checks. The older defect produced repeated scheduled
  errors on both prior and new revisions. Focused 2/2, independent Moment
  76/76 and fresh full Functions 1279/1279 across 118 suites pass; required
  reviews APPROVE. Scoped deployment of the two cleanup workers succeeded
  by 09:39:39 UTC; independent recovery APPROVED 09:59:13 UTC after automatic
  completion on attempt one, pending aggregate zero, four scheduler HTTP 200
  results and zero worker ERROR entries over more than 19 minutes. Both latest
  ready revisions serve 100% traffic. This does not change runtime `941376e`
  or require another mobile upload. Follow-up browser CI `33958465500` and
  CodeQL `33958465503` passed; full verification `33958465563` succeeded at
  09:50:19 UTC and its Hosting deployment correctly skipped.
- **Remaining dependencies**: Resolve tester email deliverability before
  any manual resend. Twenty individual plain-text emails to unique recipients
  have Gmail `SENT` records and a matching sent-mail search count, but four
  Apple-cohort hard bounces confirm `5.7.1 Message rejected` referencing Gmail
  help 69585. The user reports Android spam placement; recipient mailboxes
  were not independently inspected. Sending is not delivery, the remaining
  sixteen messages are not assumed delivered, and email rollout is not
  complete. Gmail policy rejection is under investigation; manual resends are
  paused. A separate owner-only test from the existing authorized
  `hello@yovoice.app` Workspace alias was sent at 13:05:51 CEST on 2026-09-05,
  reached Inbox at 13:06:03 and had original SPF/DKIM/DMARC PASS. No DNS,
  sender, account or security settings changed; no tester resend occurred.
  Independent recipient-side Gmail read confirms Inbox-only placement, actual
  From `hello@yovoice.app` and the same original authentication results.
  This single authenticated delivery neither resolves the earlier rejection
  nor proves tester-wide delivery. Future tester email is intended to use the
  domain mailbox's authorized alias; a personal Gmail connector cannot assume
  company-sender authority. On 2026-09-05 the maintainer declined current
  resends and confirmed the domain sender for subsequent update notifications,
  following the delivery-test procedure in DEPLOYMENT.md. No tester retry
  occurred. Marketing `975e5c6` deployment and live
  read-back are complete. Finish authenticated production smoke with
  dedicated QA accounts, non-owner Android installation, physical two-account
  and mixed-version call/media testing, and app-wide keyboard/RTL visual QA.
  Seven unavailable vendor iOS dSYMs remain a crash-symbolication limitation,
  not an upload failure. Native TestFlight notification was enabled/triggered
  with submission; recipient inbox delivery is unverified. Record separate
  email send/delivery outcomes distinctly; no inbox-placement guarantee is made.
- **Priority**: Critical release integrity. Cleanup recovery and both invited
  channel releases are verified; record announcement outcomes as observed and
  retain the remaining physical acceptance gaps explicitly in the
  [Build 20 session ledger](Sessions/2026-09-05-build-20-release-candidate.md).

### Post-Build-19 P0 tester compatibility repair

- **Status**: **Implemented at the 2026-09-04 P0 checkpoint and now incorporated
  into the Build 20 runtime `941376e` above: Web and Google Play internal
  testing released; iOS internally assigned and external TestFlight `Testing`,
  with five non-owner Build 20 installations observed after verified cleanup
  recovery. Physical/mixed-version acceptance is still pending.** That
  intermediate checkpoint passed Flutter
  2192/2192, direct-call plus localization Flutter 67/67,
  friend recovery 22/22, Functions 1218/1218 across 118 suites, Firestore Rules
  523/523, Storage Rules 67/67, Family media 11/11, direct-call backend 47/47,
  direct-media integrity 39/39, focused media probing 29/29 and reviewed
  friendship reconciliation 12/12, with clean static analysis, eight Node
  syntax checks, 615 Dart files formatted with zero changes and
  `git diff --check`. Avatar/profile review passes 91/91 without P0/P1, the DM
  media/outbox focused aggregate passes 68/68 and the independent cleanup
  re-review passes 41/41 without P0/P1/P2. At that checkpoint the dependency
  audit was unavailable because all three npm advisory requests ended with
  `socket hang up`; the later complete Build 20 candidate records both current
  production dependency audits at 0 vulnerabilities.
- **Description**: Repair the production failures reported from Build 19
  without weakening the privacy boundary. Direct-call refusals now carry safe,
  localized reason codes; video compatibility remains additive for older
  clients. Valid iOS MOV/MP4 ISO-BMFF variants are accepted only after probing
  their immutable generation. A bounded, always-on corroborator validates all
  playable audio/video tracks, sample counts and movie/track/media/decode/
  composition/edit timelines, with explicit request/byte/track limits and
  fail-closed handling of fragmented or ambiguous files.
  Production-shaped authoritative reservation expiry/change responses rotate
  the reservation and `messageId` before generic ambiguity handling. Canonical
  lost-ack reconciliation requires exact sender/conversation/message/type and
  completes durably by deleting payload before the manifest; delete failures
  stay queued across retry/restart, while wrong sender, type or conversation
  never suppresses or cleans a real failed entry. Concurrent delivery and
  reconciliation converge on one completion.
  Friends and requests share account-scoped ref-counted replay fanouts instead
  of duplicate 2N+1 reads, avatar grants invalidate only the changed target,
  and rapid profile/chat navigation is single-flight while retaining injected
  Auth/Firestore/service context.
  The private-avatar cache is viewer/auth-bound, capped by a 256-entry LRU and
  clears mounted providers plus Flutter `ImageCache` entries at expiry/global
  boundaries. Mutual-friend avatars use `UserAvatar` and the current grant;
  preview, full-profile and social-stat routes have explicit navigation locks.
  A root friends/requests source failure remains terminal for its shared
  generation. Child public-profile/presence listeners instead degrade
  fail-closed and retry at 250 ms, 500 ms, 1 s, 2 s and exponentially up to a
  30 s cap; their backoff resets only after 30 s of stable health. Malformed
  child snapshots use the same bounded recovery path, and generation/child
  epochs plus explicit timer/subscription cancellation prevent stale
  remove/re-add, retirement, auth-switch or sign-out resurrection.
  Direct video now negotiates at `Answer` rather than guessing from push-token
  inventory; legacy/camera-denied answers downgrade atomically to audio. New
  calls bind tokens to call-scoped hashed installation identity, other devices
  never auto-open media, terminal disconnect exposes Retry and passive Close/
  system-back cannot end the active call elsewhere.
- **Legacy friendship boundary**: affected long-lived friendships cannot be
  trusted merely because bilateral client-writable mirrors exist. The
  operator-only repair consumes an explicit independently reviewed allowlist,
  is capped at 100 pairs/64 KiB, defaults to dry-run, requires the exact
  SHA-256 plan digest for apply, and uses a schema-v2 timestamp containing exact
  `seconds` and `nanoseconds` rather than lossy milliseconds. It rechecks active
  verified Auth users, exact profile/mirror shape and timestamp, blocks,
  communication restrictions and existing guards, then atomically creates the
  two guards for each pair. It
  never scans or auto-blesses legacy rows. No production reconciliation has
  been run from this source tree.
- **Dependencies**: independent media security review is approved with no
  high- or medium-risk blocker. Independent call review found two blocking UI
  races; both were repaired and are regression-tested. The target-scoped avatar
  epoch map has one non-blocking P2 housekeeping item: it may grow across a very
  long session with many unique target evictions, but is cleared globally/on
  logout and does not weaken privacy or correctness. Next, freeze the exact
  commit and deploy the additive Functions revision with read-back; prepare
  and independently review the minimum explicit allowlist; run dry-run,
  controlled apply and post-apply
  no-op evidence; then execute physical mixed-version two-device audio/video,
  avatar and iOS camera/library media checks. The locked host prevented the
  final automated screen-control pass, so visual/native acceptance is still a
  real gate.
- **Priority**: Critical. Production calls and friends-only avatars remain
  unavailable for affected legacy pairs until both the backend revision and
  the reviewed data reconciliation are applied. Keep this as one coordinated
  compatibility wave; do not publish another isolated native build first.

### Coordinated Build 19 tester rollout and acceptance

- **Status**: **Released to the bounded tester cohorts on 2026-09-03 from
  `7ef9816fd3ee289cd065b37b83bd14d748a44e0c`; not publicly released.** The
  production Functions/index/Firestore Rules/Storage Rules/Hosting sequence
  and read-back checks passed. Google Play Internal Testing shows Build 19
  available to 15 testers since 18:29 CEST. TestFlight Build 19 is `Testing`
  for the persistent external 7 and internal 1 cohorts, with installs observed.
  The physical visual/device and two-device mixed-version matrices remain
  acceptance work before any public store release.
- **Description**: This candidate joins the work that must travel together:
  Shared Media; DM photo, video and voice with camera/library capture and a
  durable replay-safe outbox; canonical avatar refresh and single-flight
  profile routing; mixed-version direct audio/video compatibility; Voice
  Moment generation grants and retry recovery; a real Reels MVP; compact
  achievement/More presentation; Polish production copy and the guarded 41
  additional locale variants; and atomic moderation/audit mutation.
- **Media boundary**: Reels may use media and audio the user owns or is
  licensed to publish, with an explicit rights attestation. It does not ingest,
  download or re-publish Spotify, Apple Music or another provider's catalogue.
  Its edit recipe is non-destructive metadata, not a claim that a server-side
  transcoded master already exists.
- **Production data evidence (2026-09-03)**: the Voice Moment migration
  dry-run examined 5 legacy objects: 1 ready, 4 already migrated and 0
  conflicts. The ready record was migrated; hardening scanned 1, revoked 1
  legacy token and found 0 missing objects. A post-run found all 5 already
  migrated. Firestore has 0 legacy `audioUrl` values; bucket inventory reports
  `voice_moments` 5 objects / 0 download tokens and `voice_replies` 0 / 0.
  No media bytes were deleted. Identifiers, URLs and token material are
  deliberately absent from this aggregate record.
- **Measured source evidence**: `flutter analyze` is clean; complete Flutter is
  2123/2123; independent Build 19 QA is 229/229; Reels pagination/catalog is
  19/19 and source review is 40/40; Functions is 1166/1166; Firestore Rules is
  523/523; Storage Rules is 67/67; Reels/moderation security is 64/64; Family
  media is 11/11; browser media/crop/Reels is 39/39; and the production Web
  build succeeds. The shared DM media probe contract passes 9/9, a
  fresh-emulator direct-integrity gate passes 38/38, and syntax checks for
  seven changed Node files plus the diff check pass. These are not a substitute
  for pending physical-device acceptance.
- **Production/distribution evidence**: all 166 intended Functions were ACTIVE;
  the required index was READY; Firestore and Storage Rules read back
  byte-identically; the exact source Hosting workflow passed. The separate
  website release is production-verified from `9cc6d72550ce6e0b603136f7bb71e7e11891ab47`
  with a 43/43 route/header smoke. Signed Build 19 artifacts were assigned to
  both persistent tester channels; neither channel is a public store release.
- **Dependencies**: complete the physical visual/two-device and mixed-version
  matrices, preserve the zero-token inventory and review tester feedback
  before considering public submission. The executed sequence and rollback
  boundary are in
  [DEPLOYMENT.md](DEPLOYMENT.md#build-19-coordinated-tester-release--2026-09-03).
- **Priority**: Critical acceptance monitoring. Keep Build 19 as one
  compatibility wave rather than creating isolated follow-up uploads. The
  evidence ledger and directly observed results live in
  [the Build 19 session record](Sessions/2026-09-03-build-19-release-candidate.md).

### Moderator and super-moderator Premium preview (ADR-119)

- **Status**: Implemented and reviewed in source; **production release
  pending**. No Functions, Rules, projection backfill, Hosting or native-store
  deployment is claimed by this entry.
- **Description**: Active exact `moderator` and `superModerator` roles derive a
  revocable product-preview overlay for Premium identity, Creator and Clubs
  without fabricating `isPremium`, a plan, billing period, renewal or provider
  record. Acting operations require the signed claim and server role mirror to
  agree; public/background projections use the client-immutable mirror only.
  Demotion or an inactive account removes the preview while an independently
  valid paid entitlement survives.
- **Release work**: Complete the measured release gates, deploy Functions
  before Rules, read the deployed rules back byte-for-byte, and run the
  `publicBadges`, `publicProfiles` and `userDirectory` backfills through
  dry-run, apply and post-apply no-op. Read back moderator, super-moderator and
  demotion fixtures before releasing Hosting or native build 8. The exact
  procedure and rollback boundary are in
  [DEPLOYMENT.md](DEPLOYMENT.md#adr-119-moderator-premium-preview-rollout-source-complete-release-pending).
- **Priority**: High — existing moderators do not receive converged public
  identity projections merely because new trigger code exists, and a client
  must not be released ahead of its backend authority.

### ~~Server-only Direct Message Firestore rules~~ DEPLOYED 2026-08-23

- **Status**: **DEPLOYED 2026-08-23T18:53:33Z** (ruleset `9257845f-…`, commit `57ac1e8`, live source byte-verified against the commit). Rules only — no Hosting, Functions, indexes or Storage. The rules
  delta is exactly one authorization — `conversations/{id}/messages/{id}`
  `allow create` becomes `if false`; `read`, `update` and `delete` are
  byte-identical to the deployed ruleset. Every automated gate passes (rules
  485, storage 52, family-media 11, functions 783, Flutter 1208, analyze
  clean), the production callable is ACTIVE, the served web bundle contains no
  direct-write path, the website has no DM capability, and no store client
  exists.
- **Blocker**: stale browser sessions. A tab or PWA loaded before the
  2026-08-23 Hosting release still carries the pre-migration direct-write
  fallback, and nothing forces a reload. The failure would be loud and
  self-healing rather than silent, and the population is probably empty — but
  "probably empty" is not PROVEN SAFE, which is the bar for a production rules
  change.
- **Closure**: ask the ~4 maintainer-owned test accounts to hard-reload, or
  revoke their refresh tokens, or extend the observation window and confirm no
  new 14-field client-written documents appear. Any one is sufficient. Full
  evidence and the pre-staged rollback are in
  [DEPLOYMENT.md](DEPLOYMENT.md).
- **Priority**: High — it closes a real authorization gap, and the remaining
  work is confirmation rather than engineering.



### App-wide theme migration

- **Status**: Completed for normal product journeys on 2026-08-29 (ADR-127).
- **Description**: `lib/core/theme/` (`AppColors`, `AppTypography`, etc.)
  and `lib/shared/widgets/` (`YoButton`, `YoCard`, the `Yo*State` widgets)
  now install `AppPalette` as the semantic brightness contract. Normal product
  journeys use it; media/voice workspaces retain a complete local dark visual
  contract by design rather than masquerading as partially themed pages.
- **Dependencies**: None remaining for Pearl.
- **Priority**: Done. Future work is regression prevention, not completion of
  the user-facing theme.
- **Future considerations**: Migrate a screen wholesale, not widget by
  widget — mixing both systems in one file is worse than either alone.
  Add a lint or review check that flags new raw surface/text hex literals
  outside the theme and explicitly documented immersive components.

### `app.yovoice.app` — DNS DONE, one website-side step left

- **Status**: **The DNS block is gone.** Corrected 2026-08-16: this item,
  [DEPLOYMENT.md](DEPLOYMENT.md#domains) and [Bugs.md](Bugs.md) all
  described it as blocked on a Cloudflare CNAME only the domain owner
  could add. The CNAME resolves to `yovoice-ec54a.web.app`, HTTPS returns
  200, and the Flutter web client was fetched from that host and
  fingerprinted (5,139,256 bytes). It is serving production traffic.
- **Remaining work — UNVERIFIED, and in the other repo**: flip
  `NEXT_PUBLIC_APP_URL`
  ([ADR-009](Decisions.md#adr-009-next_public_app_url-as-an-env-var-website-repo))
  to `https://app.yovoice.app` in **all three** Vercel environments
  (production/preview/development — easy to update one and forget the
  others), redeploy, then verify the redirect end-to-end rather than
  assuming the env var change alone is sufficient. This could not be
  checked from this repo; until someone confirms it, assume the website
  still points at Firebase's default `web.app` domain.
- **Dependencies**: Vercel dashboard access for the `yovoice-website`
  project.
- **Priority**: Medium — genuinely low effort now, and it closes the last
  visible seam in the two-deployable architecture
  ([ADR-014](Decisions.md#adr-014-two-deployables-one-firebase-project)).

---

## Planned / Backlog

Ordered by rough priority — re-prioritize freely, this isn't a queue.

### 0n. Place the finished Home widgets, or mount `HomeScreen` — a Home information-architecture decision nobody has taken

- **Status**: Not started, and **blocking three finished features**. This is
  a product decision first, not an engineering one, which is why the
  implementing session deliberately did not take it unilaterally.
- **Description**: `HomeScreen` is **not mounted anywhere in the running
  app**. `main_shell` holds it at `_screens[0]`, but `_slotChildren`
  special-cases index 0 to `MobileHome`/`DesktopHome` and never reads it. So
  `DiscoverClubsRail` (rebuilt with real loading/error/empty/populated states
  in `155ad61`), `FromYourClubs` and `LiveNowHero` are complete, tested,
  rendered at three widths and two text scales — and **unreachable by any
  user**. "Discover clubs" exists in exactly one file, and that file is
  unreachable; it was broken twice over, since the rule denied it as well
  until `01c0ab2`.
- **Dependencies**: A decision about what Home shows and in what order.
  The widget APIs make the mechanical part about **ten lines per
  composition** (`mobile_home.dart` and `desktop_home.dart`), so the cost is
  entirely in the IA call.
- **Priority**: **High.** Three built features currently deliver nothing,
  and the club-discovery rules work has no consumer until this lands.
- **Future considerations**: Whatever the decision is, record whether
  `HomeScreen` survives at all. A screen that has been dead code through two
  rebuilds is a maintenance liability, and leaving it in `_screens[0]` is
  what made this invisible for the product's life. See
  [ADR-082](Decisions.md#adr-082-a-feature-is-not-shipped-until-a-user-can-reach-it--reachability-is-part-of-done-and-a-green-suite-cannot-prove-it).

### 0o. The Moderation Center cannot render or action a v2 report

- **Status**: Not started. Introduced by `2c086c7` shipping new report
  targets ahead of the queue that displays them; **two report schemas now
  coexist in `reports/`**.
- **Description**: Three separate gaps, in descending severity.
  **(1)** A v2 report document renders badly: `targetType` parses to null so
  the queue title is blank, and `reportedUserId` defaults to empty so the
  detail pane says **"This account no longer exists"** — actively
  misleading rather than merely blank. The fix spans Dart and Functions
  together. **(2)** Moderators can **triage** room and club message reports
  but cannot **action** them: `removeAndResolve` is still globalChat-only.
  **(3)** `reason` has no server-side enum on the callable path — only the
  client-direct v1 rule in `firestore.rules` constrains it to the eight-value
  list — so the Moderation Center's equality filter cannot see a report whose
  reason is off-list.
- **Dependencies**: (1) needs a paired Dart + Functions change. (2) needs
  `removeAndResolve` to grow room and club branches, in the shape
  `admin/messages.js` already uses. (3) is a Functions-side validation plus a
  decision about what the canonical enum is across both schemas.
- **Priority**: **High** for (1) — a moderator reading "This account no
  longer exists" about a live account will make wrong calls. Medium for
  (2) and (3).

### 0p. A member-started room can stay live with nobody in it

- **Status**: **LANDED IN SOURCE, NOT DEPLOYED (2026-08-20).** Both halves are
  committed. `3ff80e6` made `executeLeaveRoom` end the voice session when the
  last participant leaves **any** room rather than only a lounge — proving
  emptiness from the roster inside the transaction rather than from the
  denormalised `participantCount`, so a stale-low counter cannot evict people
  who are still talking — and gave `executeEndRoomVoice` an `onlyIfEmpty`
  roster re-check ([ADR-091](Decisions.md#adr-091-the-roster-not-participantcount-decides-that-a-room-is-empty--and-the-leave-path-asks-the-server-to-prove-it)).
  The residual gap that fix named — the `RoomVoiceEntryCoordinator` start→join
  window, where the liveness write lands and the join fails, leaving a room
  live with **no participant row for anyone to leave** — is closed by the
  scheduled `sweepStrandedLiveRoomsSchedule`
  ([ADR-092](Decisions.md#adr-092-a-scheduled-sweep-closes-the-room-no-client-can-close-and-the-roster-is-still-the-only-thing-that-proves-it-empty),
  `functions/rooms/liveness_sweeper.js`, 14 emulator-backed tests). **Deploy
  is pending** — see
  [DEPLOYMENT.md](DEPLOYMENT.md#pending-release-sweepstrandedliveroomsschedule).
  The third sub-item below (Start voice offered on an ended room) remains
  unaddressed.
- **Still open after this**: a client that crashes **while in a room** leaves
  its participant row behind, so the roster is not empty and the sweeper
  correctly skips it. That case needs item 0h.
- **Description**: The server drops `isLive` at zero participants **only for
  lounges**, so an ordinary room started by a member under
  `membersCanStartVoice` can remain live and empty. Separately,
  `executeEndRoomVoice` re-checks nothing before tearing a room down, and an
  ended room still offers Start voice to someone who never held a participant
  row. All three surfaced while building
  [ADR-088](Decisions.md#adr-088-entering-a-room-performs-the-liveness-transition-through-one-ordered-coordinator-that-mirrors-the-deployed-rule)
  and were named there rather than silently left.
- **Dependencies**: A Functions change to the zero-participant sweep, plus
  an authority re-check in the teardown callable. Related to item 0h — the
  unexported LiveKit webhook is the component that would know about a crashed
  client.
- **Priority**: Medium-High. It is the same class of defect as the club
  lounge one fixed in 2026-08-09: a room that looks live and is not.

### 0q. A presence sweeper for process death

- **Status**: Not started. Named in `3d54bc3` rather than approximated.
- **Description**: `AuthService.signOut()` now clears presence inside the
  live session ([ADR-090](Decisions.md#adr-090-session-cleanup-converges-on-authservicesignout-because-a-write-the-rules-authorize-by-session-cannot-live-after-the-session-ends)),
  but a **force-quit or a server-revoked refresh token never reaches client
  code**, and no client can write for a session that no longer exists.
  `functions/` has no presence sweeper — `public_profiles.js` clears
  `isOnline` only on account deletion — so those accounts stay online to
  their friends indefinitely.
- **Dependencies**: Either a scheduled function expiring `users/{uid}` on a
  stale `presenceUpdatedAt`, or a staleness cutoff applied when reading
  `socialPresence`. The read-side cutoff is cheaper and needs no deploy
  cadence; the scheduled function is the one that makes the stored value
  honest.
- **Priority**: Medium. Bounded blast radius (a wrong dot), but it is the
  remaining half of a bug that was just fixed, and a partially-fixed bug is
  the kind that gets re-reported.

### 0a. ~~Run the public-profile backfill~~ VERIFIED CONSISTENT (2026-08-18)

- **Status**: Closed. A dry run with Application Default Credentials on
  2026-08-18 scanned all 43 `users` documents and planned **zero writes**:
  every live account already has its projection (18 real accounts = 18
  `publicProfiles`), and the other 25 are Auth orphans whose projections are
  intentionally absent/empty. The projection layer drained itself as owners
  signed in. Original description kept below for history.
- **Original status**: Blocked on credentials; the unblock is committed and unrun.
- **Description**: After the ADR-054 cutover, production holds 33 `users`
  documents and 1 `publicProfiles` document. `users` is owner-`get`-only
  and non-listable, so the other 32 accounts cannot be seen by any other
  user in either client. Each repairs itself when its owner next opens the
  app (`onUserPrivacySourceChanged` fires on any `users/{uid}` write), so
  this drains slowly and unevenly on its own.
- **Dependencies**: Application Default Credentials, or the
  `workflow_dispatch` runner path added in `4f9ad47`
  (`.github/workflows/public-profile-backfill.yml`, dry-run by default,
  using the existing `FIREBASE_SERVICE_ACCOUNT_YOVOICE_EC54A` secret).
- **Priority**: **High.** It fails closed rather than leaking, but it is a
  live product defect affecting almost every account.
- **Future considerations**: Run dry-run first and read `nextCursor`;
  apply the same page, then repeat with `--start-after CURSOR` until
  `reachedEnd`. Attach a required reviewer to the `production` environment
  before the first `apply` run.

### 0b. ~~Close the banned-host room-update branch~~ DONE

Closed 2026-08-17 in `c75720a`, deployed and verified against the live
ruleset. See the Done entry above. Two *other* writes behind
`canAccessRoom()` remain ungated — tracked as item 0k below, which is a
different and much smaller problem.

### 0m. Run the direct-conversation migration, there are stranded legacy roots in production

- **Status**: **RUN on 2026-08-18 for every migratable thread.** A local
  ADC runner reused `createDirectMigrationService` verbatim: scan found 5
  legacy roots; the 2 whose participants all still exist in Firebase Auth
  were migrated (dry-run → apply → `alreadyMigrated` idempotency re-run;
  verified 18-key roots, `schemaVersion: 2`, both `directConversationPairs`
  guards). The remaining 3 are **unmigratable by design**: each involves
  `SqEQ493FrDUnD8l7j0egaoNCHnk2` and/or `hMwXnWimPQOYhk50TPPw62towbc2`,
  whose Firebase Auth accounts no longer exist (Auth orphans with empty
  projections), so `canonicalPublicProfile` correctly refuses
  (`invalidPublicProfile`). Their fate — retire/delete the dead-party
  threads or keep them frozen — is a product decision, tracked in
  Bugs.md. A pre-migration JSON snapshot of all 5 roots + 52 messages is at
  `~/Documents/YO Voice Backups/2026-08-18-pre-dm-migration.json`.
- **Original status**: Not started. **There is no record of this migration ever
  having been run**, which is itself the finding — the callables
  (`migrateDirectIntegrityConversation`, `scanDirectIntegrityMigration`)
  have existed and been tested since the Stage B work, and nothing has
  invoked them against production.
- **Description**: Two populations of non-canonical conversation roots
  exist. (1) Threads predating the `directConversationPairs` guard. (2)
  Roots written by the client fallback that
  [ADR-062](Decisions.md#adr-062-the-client-never-creates-a-direct-conversation--canonical-binding-is-server-only-and-a-legacy-thread-is-adopted-in-place-not-forked)
  removed — every one of them created when a `not-found` refusal was
  misread as an undeployed callable. Both lack the pair guard, so every
  server call against them fails `data-loss`, "The canonical conversation
  is missing." **Until they are migrated, `openDirectConversation` forks
  them**: it derives a fresh `dm_<hash>` id, binds the pair to that, and
  strands the legacy thread's history. `migrateDirectIntegrityConversation`
  adopts in place at the existing id, preserving history — so the
  migration must run *before* the affected users next open those chats.
- **Dependencies**: Sequenced behind [item 0a](#0a-run-the-public-profile-backfill-32-accounts-currently-invisible).
  `migrateDirectIntegrityConversation` calls `canonicalPublicProfile` to
  fill `participantNames`/`participantPhotoUrls`; running it while 32
  accounts still have no `publicProfiles` document would bake placeholder
  identities into the canonical roots. Backfill first, then migrate. Also
  needs owner credentials.
- **Priority**: **High**, and it grows: every chat opened against a
  stranded root forks a new thread that then has to be reconciled by hand.
- **Runbook** (documented, **not run** — this is an owner-credentialed,
  partly irreversible production operation and is the user's call):
  1. Confirm item 0a is complete; spot-check that
     `publicProfiles/{uid}` exists for the accounts in scope.
  2. Take a Firestore export first. Message and root rewrites are not
     reversible in place.
  3. `scanDirectIntegrityMigration` to enumerate candidates and get the
     count and cursor. Read-only — safe to repeat.
  4. `migrateDirectIntegrityConversation` with `dryRun: true` on a single
     known conversation id. Expect `status: "ready"` and verify the root
     still has `schemaVersion: undefined` afterwards, proving the dry run
     wrote nothing.
  5. Same id with `dryRun: false`. Expect `status: "migrated"`; verify
     `schemaVersion == 2`, `participantEmails` blanked, and that the
     child messages carry a `sequence`.
  6. Re-invoke the same id to confirm idempotency — expect
     `status: "alreadyMigrated"`, not a second rewrite.
  7. Proceed in pages using the scan cursor, re-running the scan between
     pages. The migration aborts atomically if a child changes after
     inspection, so a partial page is safe to retry.
  8. After each page, open one migrated thread in the app and confirm
     send/edit/react/mark-read all succeed against it.
- **Future considerations**: the end-to-end proof already exists in
  `functions/test/direct_integrity.test.js` ("legacy history migrates in
  place and every guarded operation remains usable"), and the adjacent
  test pins the pre-migration fork so the cost of delay stays visible.

### 0i. Voice Moment recording on Firefox needs a coordinated backend change

- **Status**: Not started. Firefox users currently get an honest
  "unavailable" panel naming the reason, not a silent failure.
- **Description**: Firefox has no MP4/AAC `MediaRecorder`, and MP4/AAC is
  the only container this product can publish because the **server** pins
  it ([ADR-057](Decisions.md#adr-057-voice-moment-recording-splits-only-at-byte-acquisition-and-byte-upload-and-the-server-pins-the-audio-container)).
  Supporting another container is not a client change.
- **Dependencies**: A coordinated Functions **and** rules change, in that
  order — `momentStoragePath()` / `voiceReplyStoragePath()` taking a
  container argument, `reserveMomentDraft` accepting it, `AUDIO_TYPES`
  widening, and `validateMoment()` following. **A rules-only widening
  fails closed against the current server**, so do not start there.
- **Priority**: Medium. It is a real audience gap, but it fails closed and
  explains itself, which is the acceptable form of an unsupported platform.
- **Future considerations**: Whatever container is added has to be
  playable everywhere the feed renders, not just recordable in Firefox.

### 0j. ~~Decide the fate of `_publishRecordedMomentLegacy`~~ DONE

Closed 2026-08-17 in the same working tree as ADR-063. The only accepted
absence signal remains explicit `unimplemented`; `not-found` fails closed.
If that compatibility path is deliberately reached, it now writes the exact
canonical 20-field document shape expected by `validateMoment()`, with a
regression test pinning the contract.

### 0k. Gate the last two writes behind `canAccessRoom()`

- **Status**: Not started. Pre-existing; **no client issues either write**,
  which is what makes this cheap.
- **Description**: `roomMembers` update lets a banned account rewrite
  `displayName` / `photoUrl` on its roster row — including a blind write
  into a private room it can no longer read, with no type or length check
  — and `participants` update lets it un-mute itself and raise its hand.
  Neither escalates privilege and neither bypasses audio, because LiveKit
  will not issue a token to a suspended account. The claim in the
  2026-08-17 notes that "every write behind `canAccessRoom()` is now
  gated" was **false**; these two are the remainder.
- **Dependencies**: Emulator cases and a rules deploy.
- **Priority**: Low-Medium. Worth doing mostly because gating a write no
  client makes carries **zero trap risk** — the opposite of the eviction
  rule that had to be removed in `952d8e4`.

### 0l. Non-host room messages always throw after the message lands

- **Status**: Not started. Pre-existing and **live in production**;
  unrelated to the 2026-08-17 rules work, found during it.
- **Description**: `sendRoomMessage()` bumps `updatedAt` on the room root
  after every message, and the non-host branch of the room-update rule has
  no transition accepting a bare `updatedAt`. Every non-host message send
  therefore raises an unhandled permission-denied *after* the message has
  already been written, and **room ordering in the Home feeds never
  advances from non-host conversation** — an active room looks stale.
- **Dependencies**: Either a narrow rules transition accepting exactly
  `updatedAt` from an admitted participant, or dropping the client-side
  root write. Decide which side owns room recency before writing either.
- **Priority**: **High** for a small change: it is user-visible on the main
  surface, and the thrown error is unhandled.
- **Future considerations**: The counter-drift lesson from
  [ADR-056](Decisions.md#adr-056-a-moderation-action-belongs-in-a-callable-that-completes-the-whole-removal-not-in-a-rule-that-deletes-one-row)
  applies — do not let a room-root field a participant can write become a
  gate on anything else.

### 0g. Host eviction as a callable (the rule is gone on purpose)

- **Status**: Not started, and deliberately absent — see
  [ADR-056](Decisions.md#adr-056-a-moderation-action-belongs-in-a-callable-that-completes-the-whole-removal-not-in-a-rule-that-deletes-one-row).
- **Description**: There is no host-eviction path anywhere in the product.
  The rules-level one was removed in `952d8e4` because deleting a roster
  row is not a removal — the evicted account stayed connected to the live
  audio, kept chat through `isRoomParticipant`, and could rejoin a public
  room immediately. If the product wants eviction, it is a callable in the
  shape of `removeRoomParticipantSelf` that completes the whole removal.
  **Do not restore the rule.**
- **Priority**: Medium — a product decision first, not an engineering one.
  Nothing is broken today; a capability simply doesn't exist.

### 0h. Wire the LiveKit webhook — `voiceMinutes` has no writer

- **Status**: Not started. The code exists and is unreachable.
- **Description**: `receiveLiveKitAchievementWebhook`
  (`functions/achievements/livekit_http.js`) is never exported from
  `functions/index.js`, so it has never been deployed. It is the sole
  producer of `voiceSeconds`, from which `voiceMinutes` is derived —
  meaning Creator Studio's "Voice time" tile and the entire voice
  achievement category are permanently zero for every account, presented
  as real measurements.
- **Priority**: Medium-High. It also unblocks
  `publishPublicStatsSchedule`, whose current data source
  (`activeVoiceSessions.expiresAt`, a never-renewed token TTL) is known
  wrong; LiveKit emits `participant_left` /
  `participant_connection_aborted` even on a crash.
- **Future considerations**: An HTTP webhook is a new public surface —
  signature verification and App Check posture need deciding before it
  ships.

### 0c. Username uniqueness is not enforced

- **Status**: Not started; recorded as an explicit decision in
  [ADR-023](Decisions.md#adr-023-one-profile-source-of-truth-identity-fans-out-server-side).
- **Description**: `users/{uid}.username` is seeded from display names
  (and email prefixes), so duplicates already exist in production.
  Real uniqueness needs a `usernames/{normalized}` claims collection
  written transactionally with the profile, rules that enforce the
  claim, a normalization policy, and a backfill migration for existing
  accounts. Client-side checking alone would be theatre.

### 0d. ~~Deploy the profile identity fan-out~~ DONE

- **Status**: Deployed — confirmed live via `firebase functions:list`
  during the 2026-08-08 product audit (this item had gone stale; the
  fan-out was deployed the same day it was written).

### 0e. Premium billing adapters

- **Status**: Entitlement architecture and the original Premium rules are
  shipped (ADR-024). The 2026-08-16 capability-specific gates and
  first-create hardening (ADR-053) are **deployed and live** as of
  2026-08-16 — this item said "not live until the updated
  `firestore.rules` is manually deployed" until then. The same cutover
  deployed the `entitlements(isPremium, currentPeriodEnd)` composite index
  that the scheduled `expirePremiumIdentity` sweep needs, so **Premium
  expiry can run for the first time**; no successful run has been observed
  in Console → Functions → Logs yet, so treat that as UNVERIFIED. Real
  mobile-store checkout is still not operational: `verifyPurchase`
  deliberately declines because no App Store/Play verification adapter or IAP
  client is configured. The revised Stripe web catalog is deployed under
  ADR-118: recurring card/PayPal is EUR 6 monthly or EUR 60 annually; prepaid
  BLIK is PLN 26 for 30 days or PLN 260 for 365 days and never renews. Provider
  mutation handlers, signed live webhook and controlled four-method production
  verification are **not deployed**, so the catalog reports checkout and Portal
  unavailable. The 2026-08-28 production smoke verified the secret-free
  callable response without exposing any payment entry point.
- **Actions**:
  1. ~~Deploy the tested `firestore.rules` update.~~ **DONE 2026-08-16.**
     Instead, confirm one real `expirePremiumIdentity` run succeeds.
  2. Complete ADR-118's blocked provider rollout: one live Product, two
     recurring EUR Prices, two one-time PLN Prices, approved card/PayPal/BLIK
     activation, recurring-only Portal, reviewed Terms/Privacy, live secrets,
     signed webhooks and four-path smoke/reconciliation. Keep all Stripe test
     objects outside production `yovoice-ec54a`.
  3. Keep the superseded ADR-067 PLN 19.99/199.99 two-Price catalog out of
     production; it is not a rollback target for the four-Price lifecycle.
  4. Separately create App Store/Play products only when mobile IAP adapters
     are designed; store-localized prices remain authoritative there.
  5. Interim: grant Premium via the protected-owner-only
     `adminSetPremiumEntitlements` callable.

### 0f. Room experience redesign on shared primitives

- **Status**: Not started this round (premium architecture took the
  slot). PremiumAvatarFrame + the entitlement system are ready for room
  surfaces; the Community Room's _CommunityHeart is the natural seed for
  a shared VoiceCore. Planned: extract VoiceCore/RoomHeader/
  ParticipantAvatar primitives, then recompose Community, Broadcast and
  Club rooms; premium presence must never outrank speaking state.

### 1. Verify no orphaned `rooms/{roomId}/members` documents

- **Status**: Not started.
- **Description**: When that subcollection was renamed to `roomMembers`
  ([ADR-005](Decisions.md#adr-005-roomsroomidmembers-renamed-to-roommembers)),
  any pre-existing production documents under the old name became
  invisible to the app. Never verified whether any actually existed at
  rename time.
- **Dependencies**: `gcloud`/Application Default Credentials, or a real
  Firebase service account key, or manual Firestore Console inspection —
  none were available in the session that made the rename.
- **Priority**: Medium-High. Low effort once someone has the right access,
  and it's a concrete, checkable data-integrity question rather than an
  open-ended investigation — see [Bugs.md](Bugs.md#data-integrity).
- **Future considerations**: If any orphaned documents are found, write a
  one-time copy migration (old path → `roomMembers`) rather than a
  standing dual-read compatibility layer — this is a one-time cleanup, not
  an ongoing concern like ADR-001's `podcast` mapping.

### 2. Firebase App Check enforcement

- **Status**: Not started — deliberately deferred, see
  [ADR-004](Decisions.md#adr-004-firebase-app-check-integrated-client-side-enforcement-deliberately-off).
- **Description**: Flip `enforceAppCheck: true` on Cloud Functions so
  requests without a valid App Check token are rejected.
- **Dependencies**: A monitoring period on real token-delivery data
  (Firebase Console → App Check) — needs the client-side integration to
  have been live long enough to see how reliably genuine devices are
  attaching valid tokens across platforms.
- **Priority**: Medium. Not gating an active exploit (Firestore rules and
  Cloud Function authorization checks are the actual gates — see
  [SECURITY.md](SECURITY.md)), but it's a real hardening layer sitting
  unused.
- **Future considerations**: Flip function-by-function rather than
  globally, starting with the lowest-traffic/lowest-risk functions, so a
  provider misconfiguration on one platform doesn't take down every
  backend call at once.

### 3. Creator analytics

- **Status**: Partially complete — Creator Studio has a working snapshot over
  current canonical profile, room, Club and published Voice Moment totals.
  It explicitly labels the capture time semantics and never substitutes a
  load failure with zero.
- **Remaining scope**: listens, unique reach, historical attendance, follower
  activity and trend charts. Those metrics still require a real server-owned
  event/rollup model and must not be inferred from current counters.
- **Dependencies**: schema and retention design for the remaining historical
  metrics. The snapshot implementation deliberately creates no analytics
  collection and therefore cannot be mistaken for that future model.
- **Priority**: Low-Medium — a genuine creator-facing feature, but no
  urgency signal (no creators currently asking for it) and real design
  work needed before any code.
- **Future considerations**: Decide early whether this is computed
  on-read (aggregation queries) or maintained incrementally (Cloud
  Function triggers updating rollup documents) — the latter scales better
  but is more moving parts. Given ADR-013's default toward client-direct
  writes, lean toward triggers only where a client can't safely compute
  the aggregate itself.

### 4. Monetization

- **Status**: Not started.
- **Description**: Tipping and/or subscriptions for creators.
- **Dependencies**: A payment processor integration decision hasn't been
  made. Likely needs Cloud Functions for anything touching money (see
  [ADR-013](Decisions.md#adr-013-clients-write-firestore-directly-cloud-functions-are-reserved-for-privileged-work)
  — this is a textbook case for server-mediated writes, not client-direct
  ones).
- **Priority**: Low — largest lift on this list, no immediate product
  need identified.
- **UI**: hidden from Creator Studio until a real payment product and trusted
  settlement model exist; there is no disabled/dead Monetization card.
- **Future considerations**: Whatever processor is chosen, payment state
  should never be client-writable even indirectly; treat this the same
  way `createLiveKitToken` treats secrets — computed and verified
  server-side, full stop.

### 5. Audience growth tracking

- **Status**: Not started.
- **Description**: Historical follower/audience growth over time; today
  `followerCount` is a point-in-time counter with no history.
- **Dependencies**: A time-series data model — likely a daily rollup
  document per user, written by a scheduled or trigger-based Cloud
  Function rather than computed live.
- **Priority**: Low-Medium — feeds directly into Creator analytics (#3);
  worth sequencing together.
- **Future considerations**: Decide a retention window up front (unbounded
  history is rarely worth the storage/query cost) rather than defaulting
  to "keep everything."

### 6. Two-factor authentication

- **Status**: Implemented and tested in source; the sign-in challenge received
  its local-only Voice Constellation interaction and accessibility refinement
  on 2026-08-30. Firebase TOTP provider configuration and the coordinated
  client rollout remain pending; none of this work is deployed.
- **Description**: A Firebase Auth TOTP factor managed from Settings, including
  enrollment, removal, recent-login reauthentication and the second-factor
  resolver shown after password, Google or Apple primary sign-in.
- **Challenge presentation**: The six-digit challenge keeps one real,
  autofill-ready input while its decorative cells move through the branded
  field-to-orbit-to-wave confirmation sequence. Firebase remains the sole
  validity authority. An invalid credential now shows a red X, clears all six
  digits after feedback and refocuses the input; network and rate-limit errors
  preserve the code for one deliberate manual retry. Reduced-motion users get
  a static row and short semantic colour transitions instead of travel, shake
  or looping motion.
- **Dependencies**: Identity Platform TOTP must be enabled immediately before
  the compatible clients are released. The app deliberately does not offer SMS
  MFA.
- **Priority**: Medium — a real account-security improvement, not urgent
  since there's no evidence of account-takeover activity today.
- **Future considerations**: Recovery codes and support-assisted account
  recovery need a separate, audited policy. Never log or persist the TOTP
  enrollment secret outside Firebase Auth.

### 7. Profile visibility / message-privacy controls

- **Status**: Profile visibility implemented and emulator-tested in source on
  2026-08-18; not deployed. Message privacy is tracked separately.
- **Description**: Let a user restrict who can view their profile or send
  them direct messages.
- **Implementation**: `public`, `friends` and `private` are canonical private
  profile states changed only through `setMyProfileVisibility`. Known-id reads,
  search and the signed-out website showcase enforce that same source value;
  friend-only reads require exact bilateral server-owned friendship guards.
- **Message privacy**: Implemented and emulator-tested in source on 2026-08-18;
  not deployed. The reusable Settings route offers Everyone, People you follow,
  Friends only and Nobody. Functions recheck the recipient's choice for
  conversation open, every text send, media reservation and media finalization;
  Rules protect the legacy message-create path. Missing legacy values default
  to Everyone and malformed values fail closed
  ([ADR-070](Decisions.md#adr-070-direct-message-privacy-is-recipient-authoritative-on-every-new-send)).
- **Priority**: Medium — a real trust/safety feature.
- **Future considerations**: This is exactly the kind of feature ADR-013
  warns about: if enforcement can live entirely in Firestore rules
  (checking the target's visibility field before allowing a read), keep it
  there; only reach for a Cloud Function if rules genuinely can't express
  the check.

### 8. Multi-device session management

- **Status**: Honest Firebase-bounded implementation complete in source on
  2026-08-18; Cloud Function and client are not deployed.
- **Description**: Settings shows the current token session and provides
  account-wide sign-out by revoking the authenticated caller's refresh tokens.
  It deliberately does not list or revoke an individual remote device because
  Firebase Auth exposes neither capability. Already-issued ID tokens can live
  for up to one hour.
- **Dependencies**: Deploy `revokeMyRefreshTokens` before the compatible
  client. The action requires `auth_time` within ten minutes; restricted
  accounts retain this recovery action.
- **Priority**: The truthful account-wide security control is complete. A
  real individual-device product is deferred unless the authentication
  architecture changes.
- **Future considerations**: A cosmetic device registry is not sufficient.
  True single-device revoke would require a server-issued session identifier
  and enforcement at every Firestore, Storage and callable boundary. See
  ADR-073.

### 9. Self-serve account deletion

- **Status**: Not started — currently routes to a real, working
  support-email flow instead.
- **Description**: Let a user delete their own account (Auth + Firestore +
  Storage) without emailing support.
- **Dependencies**: A dedicated Cloud Function that can atomically (or at
  least reliably) clean up a user's Auth record, Firestore documents
  across every collection they appear in, and Storage files — a
  meaningfully bigger lift than it sounds like, since "every collection
  they appear in" spans most of the schema in [Firebase.md](Firebase.md).
- **Priority**: Medium-High. Beyond the product-completeness argument,
  self-serve deletion is the kind of capability that's often expected —
  and in some jurisdictions may be legally required — for any service
  handling personal data; worth confirming against the actual compliance
  requirements for wherever this app is offered, rather than treating it
  as purely a UX nice-to-have.
- **Future considerations**: Decide up front whether deletion is
  immediate or has a grace/undo period (common in consumer apps to guard
  against accidental or coerced deletion) — that's a product decision that
  changes the Cloud Function's design, not an afterthought to bolt on
  later.

### 10. App language switcher

- **Status**: Expanded and source-complete on 2026-09-01; coordinated tester
  release pending. System plus 43 explicit locale variants are selectable and
  saved on the current device. Polish has graduated from Beta.
- **Description**: This controls UI language, distinct from a user's
  spoken/native content-language fields. `flutter_localizations` supplies
  framework delegates; YO Voice owns a strict 179-key multi-language core for
  navigation, authentication, onboarding, Settings and system controls.
  Polish additionally receives the complete product-copy migration and a
  source guard against raw English regressions. Region/script resolution is
  explicit for Portuguese and Chinese. Native permission prompts, Firebase
  Auth and web document metadata follow the resolved locale.
- **Dependencies**: No backend or Firestore schema. Catalog completeness,
  placeholders, plurals, date formatting, RTL direction, platform bundles and
  direct-copy regression checks are automated. Physical-device visual review
  remains a release gate.
- **Priority**: High release verification. Source is implemented; native and
  Hosting publication is intentionally deferred until the current combined
  tester build is requested.
- **Future considerations**: Grow specialist feature dictionaries from the
  guarded core only with native-speaker editorial review; do not describe an
  English fallback screen as fully translated. Re-evaluate ARB/code generation
  if catalog maintenance stops being tractable. See ADR-136.

### 11. Value-level counter validation

- **Status**: Not started — flagged as bigger/riskier than it looks.
- **Description**: A Cloud Function trigger validating that counters like
  room/club member counts actually match reality, rather than trusting
  client-side increments/decrements.
- **Dependencies**: An audit of every call site in `room_service.dart`
  (and likely `club_service.dart`) that touches a counter today, to make
  sure a new trigger doesn't double-count or fight with existing writes.
- **Priority**: Medium — these counters are currently self-inflatable by a
  motivated client (see the `users/{userId}` rule comment in
  [Firebase.md](Firebase.md)), but that's a data-integrity/vanity-metric
  concern, not a privilege-escalation one (see
  [ADR-003](Decisions.md#adr-003-security-fixes-move-permission-authority-to-the-server)
  for why the latter class of bug was the urgent one).
- **Future considerations**: A Firestore trigger recomputing a counter
  from the actual subcollection size on every relevant write is the
  robust option but adds write amplification; a periodic reconciliation
  job is cheaper but only catches drift, not prevents it. Worth deciding
  which failure mode is more acceptable before building either.

### 13. App-store distribution

- **Status (2026-08-26)**: In progress — TestFlight build `1.0.0 (3)` is in
  `Testing`, and the matching Google Play internal-test release is active.
  Production App Store and Google Play releases have not been submitted.
- **Social-auth readiness (2026-08-26)**: Google web OAuth and Android
  debug/release configuration are fixed in source. Google Play App Signing
  fingerprints are registered in Firebase and the checked-in
  `google-services.json` is refreshed. Sign in with Apple is configured and
  enabled in the signed iOS build, while the Android beta intentionally shows
  it as unavailable. Real-account, store-installed device smoke tests remain.
- **Description**: Publish to the Apple App Store and Google Play. The
  website's download center is honest about this today ("coming soon" + a
  GitHub link) rather than linking to store pages that don't exist.
- **Dependencies**: Apple Developer and Google Play developer accounts,
  store listing assets, and passing each platform's review — which may
  itself surface findings (e.g. a reviewer flagging a "Coming soon"
  feature, or requiring account-deletion self-service per store policy —
  see item #9) worth resolving before submission, not during review.
- **Priority**: High from a product-growth perspective — this is likely
  the single highest-leverage remaining item for reaching real users,
  though it's an execution/process lift more than an engineering one.
- **Future considerations**: Review each store's policy on account
  deletion and data handling before submitting — Apple in particular has
  historically required in-app account deletion for apps that support
  account creation, which would pull item #9 forward as a hard
  prerequisite rather than a nice-to-have.

### 14. Windows/macOS installers

- **Status**: Not started — same "coming soon" treatment as app-store
  distribution.
- **Description**: Packaged installers for desktop platforms.
- **Dependencies**: Code-signing certificates per platform, plus installer
  packaging (MSIX for Windows, a signed/notarized DMG for macOS).
- **Priority**: Low — desktop is a secondary platform for a mobile-first
  voice-social product; revisit if desktop usage data ever suggests
  otherwise.
- **Future considerations**: None pressing until mobile distribution
  (#13) is further along.

### 15. Direct chat reliability and latency

- **Status (2026-08-28)**: Critical correctness pass complete in source;
  deployment and two-device release smoke pending.
- **Delivered**: immediate optimistic text bubbles; per-conversation outbox
  isolation; silent, single-flight and paged read receipts; replay-safe
  activity/FCM notifications with source revalidation, terminal dispatch and a
  managed 30-day TTL; active-chat foreground suppression; restart-safe
  direct-call start; bounded exactly-one foreground call alerts; local
  voice-message preview; a durable account-scoped photo/voice outbox with
  reservation rotation and failed Retry/Discard; and a server-only conversation
  root/message mutation boundary enforced by Rules. Profile repair also
  converges exact participant identity-map key sets so an obsolete malformed
  avatar key cannot disable every guarded operation in one conversation;
  typing presence now degrades silently and never attempts a forbidden client
  root write when its callable is absent.
- **Release target**: local tap-to-bubble p95 <= 50 ms, warm server ACK p95 <=
  750 ms, recipient visibility p95 <= 1 s, exactly zero message alerts while
  that same conversation is foregrounded, and one background alert per
  notification generation. These are measurable targets, not a 1 ms
  internet-delivery promise.
- **Known next work**: byte-level media upload progress; shared/ref-counted
  conversation and notification listeners; older message pagination past the
  current 250-message live window; production latency traces/dashboards; and a
  synthetic two-account canary.
- **Cost decision for build 18 (2026-09-02)**: the tester release keeps exactly
  one warm instance for the five latency-critical entry points
  (`sendDirectMessage`, `sendRoomMessage`, `createLiveKitToken`,
  `startDirectCall`, `createDirectCallToken`). Search and suggestion callables
  remain at zero. This is a deliberate recurring-cost tradeoff for the
  product's critical chat/join/call latency work, guarded by an exact export
  configuration test. Monitor invocation latency, instance count and spend
  during the tester cycle; rollback is `minInstances: 0` for those five
  endpoints if the measured benefit does not justify the cost.

---

## Explicitly not planned right now

Don't build these speculatively — revisit only if the product direction
changes:

- **Text-first chat as a primary surface** — voice-first is the point
  (see [Vision.md](Vision.md)); a text-first pivot would be a product
  direction change, not an incremental roadmap item.
- **A custom (non-Firebase) backend** — see
  [ADR-013](Decisions.md#adr-013-clients-write-firestore-directly-cloud-functions-are-reserved-for-privileged-work)
  for why the current Firebase-direct-write model is a deliberate choice,
  not a placeholder waiting to be replaced.
