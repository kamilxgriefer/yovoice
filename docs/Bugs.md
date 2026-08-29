# Known Issues

Current, living list of known bugs and tracked gaps — not a changelog.
Update this whenever a bug is found or fixed. For "features not built
yet," see [Roadmap.md](Roadmap.md) instead; this file is specifically
about things that are broken, risky, or need verification.

> **A pattern, named once here rather than four times below.** Between
> 2026-08-19 and 2026-08-20, four features were found to exist in source,
> pass their tests, and — where a backend was involved — be deployed and
> ACTIVE, while being unusable by any user: room voice, club chat
> moderation, message reporting, and Home's club-discovery rail. The
> unifying mechanism is that the emulator does not enforce composite
> indexes, rules tests exercise fixtures the test author wrote rather than
> what the client actually sends, and `fake_cloud_firestore` does not
> evaluate rules at all — so **a green suite can coexist with a feature
> that cannot work.** When triaging anything below, check reachability
> before believing the code.
> [ADR-082](Decisions.md#adr-082-a-feature-is-not-shipped-until-a-user-can-reach-it--reachability-is-part-of-done-and-a-green-suite-cannot-prove-it).

## Security

- **FIXED IN SOURCE 2026-08-29 — logout changed AuthGate but left private
  routes, banners and live-room audio attached to the previous session.**
  Profile and Settings are pushed above the first Navigator route, so replacing
  MainShell with LoginScreen underneath them left the pushed screen visible;
  its Firestore listener then rendered “You don't have permission to do that.”
  The app now treats every signed-in principal as an auth epoch: logout,
  direct account replacement and auth-stream failure replace the complete root
  route stack with a zero-duration auth boundary, ignoring route pop vetoes.
  Logout paints the real Login screen on that first replacement frame and
  clears app-level notification SnackBars so account A cannot leave UI on
  account B. The same central sign-out path now disconnects local LiveKit audio
  immediately, best-effort leaves an active room roster and ends an active
  direct-call record while Auth is still valid; bounded network failure can
  never trap the account in-session. Remote Auth loss and direct A→B also force
  the local audio disconnect even when roster/call authority is already gone.
  Registration's intentional signed-out → signed-in Verify Email flow is
  preserved. Route-stack, PopScope, direct A→B, real-Login, presence/FCM and
  active-room/direct-call cleanup regressions cover the boundary.

- **FIXED AND PARTIALLY DEPLOYED 2026-08-27 — the product sound was a retro synth-jingle
  system and one foreground notification could play two different cues.** All
  eight effects used notes, pentatonic rise/fall pairs, glass-bell partials,
  detune or a two-note chime. Worse, native push still packaged the much louder
  original mono WAV while the focused app used a later stereo file; native FCM
  and the Firestore banner could sound together. Velvet Prism replaces the
  entire pack with short, non-musical material cues, removes the conflicting
  Dart generator, derives all native copies from one deterministic 48 kHz
  master, serializes channel playback, dedupes foreground ownership and makes
  room creation one confirmation rather than create+join. Android uses a new
  immutable `yovoice_activity_v3` channel consistently in source. Hosting now
  serves all eight v3 cues; native stores remain on build `+3`, and production
  `onNotificationCreated` deliberately remains on channel v2. Mobile clients
  must create v3 before the Functions payload cutover; physical-device
  listening is still required. See ADR-116.

- **FIXED AND DEPLOYED 2026-08-27 — Voice Moment root lifecycle and the active
  cap could be bypassed by a modified or legacy client.** Before this rollout,
  production rules permitted a direct root create with no `expiresAt`, broad
  author updates that could forge publish/media/status state, and direct root
  deletion that skipped the cleanup outbox. The old cap scanned only the
  newest 100 authored documents and had no shared write on which two
  finalizations of different drafts could conflict. ADR-115 makes
  root and engagement mutation server authority, queries the complete
  published set and serializes
  finalize/delete/expiry through a server-only per-author revision document.
  Draft and retired roots plus their audio become author-private, and all root
  and reply audio becomes client-immutable so deletion cannot race a publish
  transaction. Bounded server workers remove abandoned uploads. Every
  unfinished finalize retry is rate-charged before Storage reads, exact client
  timers stop open playback at the deadline, announce visible transitions
  once, restore focus and preserve the first surviving Story successor;
  engagement callables refuse the same deadline before the sweeper runs.
  Emulator coverage includes direct
  lifecycle/counter/comment attacks, more than 100 newer drafts, concurrent
  publication into the tenth slot, retry-budget attacks and deadline edges.
  The ordered index, Functions, Firestore Rules, Storage Rules and Hosting
  rollout completed with byte read-back and controlled production smokes.

- **FIXED IN SOURCE 2026-08-28 — the conversation root and message documents
  still admitted client-side authority despite a server-owned contract.** The
  old root rule pinned only `participantIds`, allowing a participant to forge
  `lastMessage`, identity snapshots and either party's unread/read state; old
  message rules also kept edit/delete/reaction/read fallback writes alive.
  Current Rules make both surfaces server-write-only while preserving
  participant reads. Text, media, typing, read, mute, archive, edit, delete and
  reactions use their owning callables. The 519-case emulator gate includes
  direct attacks on both participants' state and every retired message write.
  Production Rules remain a separate rollout gate until build 11 is available
  to the permanent tester cohorts.

- **FIXED IN SOURCE 2026-08-27 — the message outbox existed but the chat waited
  for the network and rendered none of its states.** A text send now clears the
  composer after durable local enqueue, renders an optimistic outgoing bubble,
  and drains oldest-first under the original idempotent `requestId`. Pending,
  offline/retrying, server-accepted and terminal failure states remain visible;
  a terminal bubble preserves the words and exposes 44 px Retry/Remove actions
  without showing raw backend errors. The callable response and Firestore
  snapshot are reconciled by the backend's deterministic SHA-256 message id, so
  their arrival order cannot flash or duplicate a bubble. Typing presence is a
  transition/heartbeat instead of one callable transaction per keystroke, and
  expires locally after eight seconds even without another snapshot. One live
  `MessageService` owns one serialized, UID-scoped queue
  (`messages.outbox.v2.<uid>`); the ownerless v1 value is retired rather than
  attributed to whichever account opens the upgrade. MainShell resumes it on a
  cold start, backoff preserves FIFO inside a conversation without blocking a
  different chat, and closing Chat cancels its shared Firestore listener. An
  enqueue refusal restores every draft word, while a local bubble can no longer
  hide a failed server-history stream. FIFO, restart/account-switch,
  cold-callable, 320 px/200% and recovery paths are regression-tested.
  **DEPLOYED TO WEB 2026-08-27; NATIVE STORE BUILD PENDING.** See ADR-105.

- **FIXED IN SOURCE 2026-08-27 — the avatar cropper could shrink a picked
  photo into the upper-left corner on the first pinch.** The initial cover
  transform scaled X/Y below 1 for a large source image but left Z at 1.
  `InteractiveViewer.getMaxScaleOnAxis()` therefore reported 1 instead of the
  real cover scale; the first zoom gesture applied that cover factor again,
  producing the quarter-sized image and empty circular frame visible on iOS.
  The editor now uses one uniform XYZ scale, so reset, pinch and drag preserve
  full cover and the exported JPEG matches the visible crop. Named 44 px
  Zoom −/+ and directional controls provide the same operation without a
  multi-pointer gesture and work from the keyboard; the crop preview exposes
  its current zoom to assistive technology. Gesture- and control-level
  regressions cover portrait and landscape inputs on phone layouts, including
  200% text. **DEPLOYED TO WEB 2026-08-27; NATIVE STORE BUILD PENDING.** This
  is a corrective amendment to ADR-025.

- **FIXED IN SOURCE 2026-08-29 — room covers bypassed the crop editor and
  could not be positioned by their owner.** Create Room and Room Settings sent
  the picked source straight to a fixed `BoxFit.cover` presentation, so a host
  could replace an image but could not choose which faces, logo or text would
  survive the wide room card. Both flows now use one 21:9 editor, upload only
  its final 1600×686 JPEG and retain the previous crop when Replace is
  cancelled. The fix also closes the adjacent lifecycle defects: system Back
  cannot dispose the decoded image during encoding, native codecs are
  released, double taps cannot stack editors, leaving Settings cannot skip
  superseded-object cleanup, and status/delete cannot race an upload. A lost
  Firestore acknowledgement deletes new media only after an authoritative
  server read proves the pointer did not commit; an unavailable read preserves
  it for recovery. Closed/archived rooms explain the active-room Storage rule
  and offer a nearby confirmed Reopen action; a moderation-suspended room has
  no host-controlled status escape hatch. Firestore Rules now also reject
  non-string, oversized, external and cross-room cover pointers, while keeping
  a Club Lounge bound to the exact managed avatar on its live Club root. The
  client parser ignores hostile legacy/Admin data and the decoder bounds both
  encoded dimensions and decoded memory. See ADR-122.

- **FIXED AND DEPLOYED TO WEB 2026-08-29 — the new room-cover crop flow rejected every
  valid image on Web before the editor could open.** Its safety preflight read
  `ImageDescriptor.width/height` from an encoded descriptor, getters that the
  Flutter Web engine deliberately does not support. The resulting
  `UnsupportedError` was flattened into the red “We couldn't process this
  image” state visible in both Community and Podcast creation; Room Settings
  and profile media shared the same latent decoder defect. The decoder now
  reads bounded JPEG/PNG/WebP header metadata and JPEG EXIF orientation first,
  then sends one oriented-axis target to the cross-platform codec. An iPhone
  portrait therefore cannot constrain the wrong axis or decode beyond the
  3200 px memory ceiling. The route launcher retains ownership of the native
  frame until the reverse transition or forced auth reset has fully removed
  the crop overlay. CI now runs decode, EXIF rotation, forced-reset and
  picker-bytes → crop → 1600×686 export regressions in Chrome. Native tester
  build remains part of the coordinated queue.

- **FIXED IN SOURCE 2026-08-27 — Message in Profile Preview appeared to do
  nothing when the preview was opened above another sheet.** The callback
  popped Profile Preview and immediately looked up a navigator through that
  closing route; an `openDirectConversation` refusal was even less visible,
  because its snackbar painted in the root Scaffold underneath both modal
  barriers. Profile Preview now returns a typed destination to the navigator
  captured by its launcher, waits for dismissal, and only then pushes Chat or
  the full profile. The same resolved Auth identity and MessageService follow
  the route so optimistic reconciliation cannot switch users; an internally
  constructed test/preview service is disposed after Chat returns. A failed
  open stays in the preview as a friendly inline
  live-region message; while the request is pending, the button and a concise
  live status both say that the chat is opening. The real two-sheet route,
  delayed/double tap, Back behavior and 320 px/200% failure state are
  regression-tested. **DEPLOYED TO WEB 2026-08-27; NATIVE STORE BUILD
  PENDING.**

- **OPEN, noted not fixed — `enforceAppCheck: false` on the Stage B callables,
  including `sendDirectMessage`.** App Check is supported but not enforced
  (`stage_b_functions.js:24`, default `enforceUserAppCheck = false`; asserted
  by `stage_b_bindings.test.js:138`). Pre-existing posture, unchanged by any
  pending work, and a deliberate separate decision rather than an oversight to
  fix in passing.

- **FIXED AND DEPLOYED 2026-08-25 — the desktop rail could still be
  deliberately scrolled, making primary navigation look displaced.** ADR-107
  correctly separated the rail from the page and fixed controller ownership,
  but kept the nav `SingleChildScrollView` as a short-height safety valve:
  measured `maxScrollExtent` was 40 px at 720 and 82 px at 620. That prevented
  overflow while preserving the exact layout, but a wheel gesture could still
  leave the menu visibly shifted — the visual behavior reported again on
  2026-08-24. The new contract removes the scrollable entirely: Home is a
  pinned 44×44 header action beside Notifications, the creation actions share
  one row below 700 px, and the content-only verification banner/RoomMiniBar
  no longer shorten the rail. At 200% text the informational timezone card
  yields; below 620 logical px the shell uses mobile navigation. The earlier
  diagnosis and measurements remain valid history in
  [ADR-107](Decisions.md#adr-107-the-desktop-rail-owns-its-scroll-position-and-sizes-its-decoration-from-the-rail-not-the-window);
  the superseding layout decision is
  [ADR-109](Decisions.md#adr-109-the-desktop-rail-has-no-scroll-position--home-is-a-pinned-header-destination).

- **FIXED IN SOURCE 2026-08-22 — the desktop rail hard-coded a 24-hour
  clock.** The same defect `message_bubble.dart`, `edit_profile_screen.dart`
  and `club_chat_screen.dart` each had to fix: a 12-hour-clock locale was
  shown "13:04". The timezone card now reads
  `MediaQuery.alwaysUse24HourFormatOf(context)`. Confirmed live — an `en-GB`
  browser rendered "1:37 PM".

- **FIXED BEFORE IT SHIPPED 2026-08-22 — the new web timezone reader returned
  null in every browser.** `external factory` on a bare extension type names
  no global constructor, so `Intl.DateTimeFormat()` resolved to nothing and
  the card silently fell back to the platform abbreviation. Found by looking
  at the running app, in a browser whose own console answered
  `Europe/Amsterdam`. `@JS('Intl.DateTimeFormat')` is the binding that makes
  it work and is load-bearing.

- **FIXED IN SOURCE 2026-08-19, NOT DEPLOYED — room chat was the largest
  unguarded client write surface in the product.** The rule checked
  `senderId` and membership and nothing else about the document, so an
  ordinary member could write another member's `senderName` and photo, a
  60,000-character body, arbitrary extra fields, and a `sentAt` in 2099 that
  pinned the message to the top of every member's list **permanently**.
  Every other client-authored identity snapshot in `firestore.rules` was
  already pinned; room chat was the exception, and the client compensating is
  why it never surfaced. `01c0ab2` adds a six-key allowlist, pins
  `senderName` to the canonical `users` document and `createdAt` to
  `request.time`, caps content at 500 and bounds reactions updates at 32
  keys. **Still open, stated rather than hidden**: `senderPhotoUrl` is
  deliberately NOT pinned, because the client falls back to the Firebase Auth
  mirror when the profile field is empty and a pin would refuse a legitimate
  send — so **an avatar can still point at another member's image**. With the
  name pinned that is much weaker impersonation, but it is a real remaining
  gap, and closing it needs the client to drop the fallback first. Also
  bounded but not closed: the uid list under each reaction key is still
  caller-authored and unbounded, because rules cannot iterate map values —
  the real fix is a `reactions/{uid}` subcollection, which is a schema
  change. See
  [ADR-084](Decisions.md#adr-084-client-authored-writes-carry-an-exact-key-allowlist-and-identity-and-time-are-pinned-to-canonical-server-values-or-the-remaining-gap-is-stated).

- **FIXED IN SOURCE 2026-08-19, NOT DEPLOYED — a plain club member could
  write an unrepairable forged tombstone.** Found by the adversarial review
  of the club-moderation change, and it is the mirror image of that fix: the
  club message create rule had no field allowlist, so a member could write a
  message that was **already** a removal record — reading as "removed by the
  club owner", carrying `deletedByRole: superAdmin` and a `senderName` of
  "YO Voice Support", with `sentAt` in 2099 so it pinned to the top of every
  member's list forever. And it was **unrepairable by any client path**: the
  new update rule refuses already-deleted documents, `delete` is `if false`,
  and `adminDeleteMessage` short-circuits on `isDeleted`, so only a raw Admin
  SDK script could have cleared it. `clubMessageCreateShapeAllowed` closes
  it, with a test that seeds the forged tombstone and proves owner, moderator
  and author are all refused. This is the standing reason the rules and
  client halves of club moderation could not ship apart.

- **FIXED IN SOURCE 2026-08-20, NOT DEPLOYED — `createContentReport` was an
  existence oracle.** The callable answered `not-found` *before* checking
  access, so a caller could learn whether a private room, club, channel or
  message id was real by watching which refusal came back. `2c086c7` runs the
  access check first for every target type; a caller who cannot read the
  container now gets `permission-denied` and nothing else. One live behaviour
  changes with it: a non-participant reporting a DM could previously
  distinguish a missing message from a real one. See
  [ADR-086](Decisions.md#adr-086-a-safety-action-is-never-gated-on-email-verification-and-every-moderation-endpoint-checks-access-before-existence).

- **FIXED IN SOURCE 2026-08-20, NOT DEPLOYED — a first-day victim could not
  report harassment.** `createContentReport` required a verified email:
  `requireActor` defaults to `{verified: true}` and the inner call at
  `functions/moments/integrity.js` overrode an outer binding that already
  passed `{verified: false}`. `firestore.rules` states the opposite policy in
  writing on the client-direct path — reporting is a SAFETY action and sits
  with blocking, which that policy explicitly leaves available to a
  freshly-registered account. A neighbour audit of **every** `requireActor`
  call site found this was the ONLY tightened safety path: `setUserBlock`,
  `unfollow`, conversation mute/archive, mark-read and both delete paths were
  already correct, and every remaining `verified: true` site is genuinely
  outbound.

- **FIXED IN SOURCE 2026-08-19, NOT DEPLOYED — a signed-out account showed as
  online to its friends indefinitely, and two of five sign-out paths left the
  previous account receiving push.** The offline presence write lived in the
  `authStateChanges()` **null branch** — after `FirebaseAuth.signOut()` had
  already cleared the session — so the rule's `isSignedIn()` gate denied it
  and `presence_service` swallowed the denial to a `debugPrint`. `isOnline`
  stayed true and `onUserPrivacySourceChanged` mirrored it into
  `socialPresence`, which is exactly what the DM header dot and the
  conversation list read. The comment above that code claimed it fixed this;
  it did not. A second such write, in the account-switch branch, wrote a
  previous uid under a new identity and failed `isOwner()` just as
  structurally — both removed rather than relocated, because keeping a write
  the ruleset always rejects is the mistake. The FCM token had the same shape
  across five sign-out entry points with five different amounts of cleanup;
  cleanup converged into `AuthService.signOut()` immediately before
  `_firebaseAuth.signOut()`. Both cleanups start while Auth is live, are
  independently time-bounded, and push revokes its identity epoch plus starts
  durable-marker/platform-token rotation before any offline Future can stall
  sign-out. **UNVERIFIED**: presence actually flipping in production needs two
  real accounts. **Half of this is not fixable from the
  client at all** — see the process-death entry under Data integrity. See
  [ADR-090](Decisions.md#adr-090-session-cleanup-converges-on-authservicesignout-because-a-write-the-rules-authorize-by-session-cannot-live-after-the-session-ends).
- **FIXED IN SOURCE 2026-08-19 — a banned or communication-muted account
  could still send direct messages through the client fallback.**
  `conversations/{id}/messages/{id}` create checked `isVerified()` — a token
  claim that says an email was confirmed once, and nothing about account
  standing — but never the sender's `users/{uid}.banned|disabled` or
  `restrictions/{uid}` communicationMute. The server's `activeProfile()` and
  `assertNotRestricted()` run *inside* `sendDirectMessage`, while
  `_sendTextMessageDirectly` wrote the message document straight from the
  client whenever the callable was unreachable, so on that path the rule was
  the only backstop and it did not enforce the sanction. The same bypass
  skipped the per-sender rate limit and the idempotency ledger.

  Adding the missing check to the rule was implemented and then abandoned on
  measurement: it exceeds Firestore's per-request document access-call
  budget (the friends-privacy path had exactly one call of headroom; a
  complete sender-status check needs four), and an exhausted rule errors
  rather than skipping — which denies, breaking legitimate sends. The rule
  is now `allow create: if false`; `sendDirectMessage` is the sole writer.
  A bounded local outbox with Pending / Retrying / Failed states retries
  unsent messages under their original `requestId` when connectivity
  returns, so removing the fallback does not lose a message. See ADR-082.

  Verified: rules **446/446**, Flutter **881/881**, `flutter analyze` clean.
  Not yet deployed — rules deploys are manual, and the app should ship
  before the rule so installs older than this release are not left writing
  into a denial with no queue to catch them.

- **FIXED IN SOURCE 2026-08-18 — live rooms wasted desktop space and left a
  detached chat bubble behind after chat closed.** Community, Podcast, Club
  and Family rooms now use one bounded responsive workspace: desktop keeps a
  readable stage on the left and a permanent chat rail on the right, while
  phones and compact tablets switch between full-width Stage and Chat views.
  The floating latest-message overlay and the synthetic “room is quiet”
  prompt were removed. Responsive tests cover the four room identities,
  desktop split geometry, 320/390/768 compact widths and 200% text. Pending
  the Flutter Hosting deploy for live verification.

- **FIXED LIVE 2026-08-18 — every Firestore-backed Storage upload was denied
  despite green emulator tests.** Production was missing the
  `roles/firebaserules.firestoreServiceAgent` binding on
  `service-80235878542@gcp-sa-firebasestorage.iam.gserviceaccount.com`.
  Consequently `firestore.get()`/`firestore.exists()` inside `storage.rules`
  failed closed before a Voice Moment object could be created; the UI retained
  the recording and reported only that publishing failed. The same missing
  prerequisite affected profile/room/Club/message uploads whose rules read
  Firestore authority. The minimal Google-managed service-agent binding was
  restored in production, then an authenticated resumable upload using the
  exact Voice Moment path, MIME, metadata, size and unpublished-draft contract
  returned HTTP 200 and created a generation; the temporary Auth user,
  Firestore documents and object were deleted. Deployment documentation now
  requires an IAM-policy check plus a real cross-service upload smoke test.
  Emulator coverage remains necessary for rule semantics but cannot model
  production IAM. See ADR-077.

- **FIXED AND DEPLOYED 2026-08-18 (`e524497`) — mobile Home hid both
  legitimate room-deletion paths.** The phone Home never loaded the shared
  staff-capability response, so an administrator or super moderator could not
  see the audited room menu that desktop already rendered. Owners could reach
  deletion only when a room happened to appear under `Your active rooms`, with
  no explicit management affordance on the room card. Home room cards now
  expose a separate owner-only overflow menu backed by `deleteRoomSelf`, while
  the shield menu is backed by `adminDeleteRoom`. Server authorization is
  intentionally asymmetric: exact `hostId` ownership is sufficient only for
  the caller's own room; deleting any room requires `superAdmin` or
  `superModerator`; ordinary `moderator` is denied. Phone navigation now loads
  the same capability object as desktop. See ADR-075.

**Rules status, 2026-08-16: the pending fixes are now DEPLOYED.** Every
"FIXED IN SOURCE, PENDING RULES DEPLOY" marker in this file was cleared on
this date. `firestore.rules` was deployed twice — 20:40 by the operator and
21:06 covering `952d8e4` — and `storage.rules` was deployed the same day,
per Console → Firestore → Rules version history. First-user-document
creation and Club invitation acceptance are no longer open production
risks.

**Rules status, 2026-08-17: the banned-host gap is CLOSED and deployed.**
The room-update host branch, `isHostAdmittedRoomParticipant()`,
`roomMembers` create and message reaction updates all require
`isActiveAccount()` as of `c75720a`. Deployed, and verified by reading the
live ruleset source back through the Firebase Rules API and diffing it
against `firestore.rules` at HEAD — **byte-identical**. That verification
is now the project's standard for a rules deploy; the commands are in
[DEPLOYMENT.md](DEPLOYMENT.md#reading-the-deployed-ruleset-the-verification-standard).

**Two writes behind `canAccessRoom()` are still ungated**, and the claim
that all of them are is false — see
[SECURITY.md](SECURITY.md#still-open-pre-existing-live-in-production) and
[Roadmap 0k](Roadmap.md#0k-gate-the-last-two-writes-behind-canaccessroom).
Neither escalates privilege.

For the full security model (not just this status snapshot), see
[SECURITY.md](SECURITY.md). An earlier full audit
([Archive/SECURITY_AUDIT.md](Archive/SECURITY_AUDIT.md)) found 3 critical, 3
high, and 6 medium-priority issues plus one client/server contract bug. Within
that audit's original 13 items, all are fixed except one:

- **`enforceAppCheck: false` on every Cloud Function** (audit item #12) —
  still open, but deliberately: flipping it needs a token-delivery
  monitoring period first (Firebase Console → App Check has the metrics).
  See [ADR-004](Decisions.md#adr-004-firebase-app-check-integrated-client-side-enforcement-deliberately-off).
  Not urgent on its own — it removes a layer that raises the cost of
  abusing the backend, it isn't itself an open exploit — but shouldn't be
  forgotten either. Tracked as a Roadmap item too:
  [Roadmap.md](Roadmap.md#2-firebase-app-check-enforcement).

- **FIXED AND DEPLOYED 2026-08-16 — first `users/{uid}` create
  bypassed every protected-field update check.** The update rule prevented
  self-assigned Creator/Premium/staff state, but a document that did not exist
  yet could be created with arbitrary fields. The create rule now accepts only
  the non-privileged bootstrap/profile/presence field set, requires any `uid`
  to match the path and permits only `personal` as an initial `accountType`;
  legitimate partial presence-first documents still work. Forged Creator,
  `premiumIdentity` and role creates are rejected in the emulator suite.
  ([ADR-053](Decisions.md#adr-053-paid-capabilities-come-only-from-the-trusted-entitlement-and-every-entry-boundary-fails-closed)).

- **FIXED AND DEPLOYED 2026-08-16 — a Club invitee could self-promote
  while accepting an invitation.** The membership-create branch previously
  verified the pending invite but did not pin the new membership role or shape,
  allowing a modified client to join as owner/co-owner/admin and then inherit
  Club management rights. Rules now allow exactly the seven production fields,
  require the invite's sender in `invitedBy`, and force invite acceptance to
  `role: member`; owner membership creation remains a separate `getAfter()`
  path. The Club-root counter update must also atomically create that membership
  and delete the invite, may change only both counters plus `updatedAt`, and
  pins their deltas and server time. Emulator attack cases cover every
  privileged role, extra permission fields, repeated counter bumps and Club
  metadata mutation.

### Found and fixed 2026-08-17 — live in production, and deployed

- **FIXED (`c75720a`) — a banned or disabled host could still edit room
  metadata and start voice.** The room-root update rule selected its host
  branch on `hostId` alone with no account-status check, while
  `isRoomHost()` did check — so the selector was doing authorization work
  the branch's own helper was careful about. Four conditions now require
  `isActiveAccount()`: the host room-update branch,
  `isHostAdmittedRoomParticipant()`, `roomMembers` create, and message
  reaction updates. **`roomMembers` create mattered independently**: it
  gated on `isRestrictedAccount()`, which reads `banned` only and returns
  false when the account document is *absent*, so disabled accounts passed
  a check that looked like it covered them. Rules suite 310 passed / 8
  failed → **318 passed / 0 failed**. Generalized as
  [SECURITY.md principle 9](SECURITY.md#firestore-security-rules--design-principles).

- **OPEN, pre-existing, live — every non-host room message throws after
  the message lands, and Home never reorders from non-host talk.**
  `sendRoomMessage()` bumps `updatedAt` on the room root after each
  message, and the non-host branch of the room-update rule has no
  transition that accepts a bare `updatedAt`. The message itself is
  written, so nothing is lost; what follows is an **unhandled
  permission-denied** and a room whose ordering in the Home feeds never
  advances no matter how active the conversation is. Found during the
  2026-08-17 rules work, not caused by it. Tracked as
  [Roadmap 0l](Roadmap.md#0l-non-host-room-messages-always-throw-after-the-message-lands).

### Found and fixed 2026-08-16 — all were live in production

Each was proven by a case that failed first, and all are now deployed.

- **FIXED (`56e7ea7`) — every club promotion and demotion was denied.**
  `clubs/{clubId}/members` manager updates allowlisted only
  `['role','updatedAt']`, while both the deployed client and this tree
  write `role`, `roleUpdatedAt` and `roleUpdatedBy`. Club role management
  was entirely non-functional. `clubRoleChangeFieldsAllowed()` widens the
  field set without widening privilege: `roleUpdatedBy` is pinned to the
  acting uid and both timestamps to `request.time`. Also closes an
  unknown-role string falling through `clubRolePower`'s else branch.
- **FIXED (`56e7ea7`) — a private Community room became unreadable to its
  own members, and took the whole Communities list with it.**
  `canAccessRoom()` had no `isRoomMember` branch. The blast radius came
  from the client: `watchMyCommunities()` hydrates every id in a single
  `Future.wait`, so **one** unreadable room emptied the entire list. Worth
  remembering as a pattern — an unbounded `Future.wait` turns a
  single-document permission error into a whole-screen outage.
- **FIXED (`56e7ea7`) — club avatar and banner uploads were denied.**
  `storage.rules` `validClubImageUpload()` accepted only the bare
  `avatar`/`banner` object name; the deployed client uploads
  `{kind}_{millis}.{ext}`. Both shapes are now accepted, with the
  timestamped form validated like the profile path including
  MIME/extension agreement.
- **FIXED (`2fc05e5`) — banned and disabled accounts gained private-room
  access.** `isRoomMember()` required only `isSignedIn()`, so widening
  `canAccessRoom()` handed private rooms, their rosters and their
  participant lists to suspended accounts. Now requires
  `isActiveAccount()`, which also withdraws room chat and voice-start from
  them.
- **FIXED (`2fc05e5`) — club role attribution was forgeable.** Omit
  `roleUpdatedBy`, or resend the value already stored, and the guard never
  fired — because `diff().affectedKeys()` reports only fields whose
  *value* changed and the guards were gated on `hasAny()`. Attribution is
  now required unconditionally whenever `role` changes, checked against
  the post-write document. This is now
  [SECURITY.md principle 6](SECURITY.md#firestore-security-rules--design-principles).
- **FIXED (`2fc05e5`) — a host could permanently and remotely empty a
  victim's Communities tab.** `roomMembers` update had no field allowlist
  on either branch, so a host could repoint their own membership row at a
  victim's uid. The victim's `collectionGroup` query then returned a row
  whose room they cannot read, and `Future.wait` in
  `watchMyCommunities()` emptied their entire Communities tab — with **no
  action available to the victim**. Writes are now limited to
  `displayName`, `photoUrl` and `updatedAt`, with `userId`, `role` and
  `joinedAt` pinned.
- **FIXED (`952d8e4`) — a production trap: rooms nobody could leave.**
  `2fc05e5` made `memberCount` the gate on removing a membership row while
  leaving hosts able to write that counter, so a host — including a banned
  one, since the room-update host branch checks no account status — could
  starve it to zero in three plain writes and make membership unremovable
  for everyone. It also fired **with no attacker at all**, on any room
  whose counter had drifted below its true row count, legacy rooms
  carrying no `memberCount` field being the clearest case. Fixed by
  removing rules-level eviction entirely rather than guarding it. See
  [ADR-056](Decisions.md#adr-056-a-moderation-action-belongs-in-a-callable-that-completes-the-whole-removal-not-in-a-rule-that-deletes-one-row).

If you're about to change `firestore.rules`, `storage.rules`, or anything
in `functions/`, read [SECURITY.md](SECURITY.md#firestore-security-rules--design-principles)'s
design principles and checklist first — each one maps to a specific
failure mode this codebase has actually hit before (self-role assignment,
missing field validation, `collectionGroup()` rule gaps, client-trusted
permission flags).

## Data integrity

- **FIXED IN SOURCE 2026-08-20, NOT DEPLOYED — the two staff surfaces that
  report live rooms both under-reported them, and by the majority shape.**
  `getAdminDashboard`'s `liveRooms` figure and `getStaffOverview`'s live-room
  count *and* list all ran
  `where("status","==","active").where("isLive","==",true)`. That form matches
  only documents where `status` is PRESENT and equal, and **25 of the 45
  production rooms carry no `status` field at all** — so every legacy room was
  invisible to the only people who can act on it. This is the same defect
  `b7c6d99` fixed on the callable side by introducing `roomIsActive()`
  ([ADR-093](Decisions.md#adr-093-an-absent-status-means-active--one-reading-of-the-field-shared-by-the-rules-and-every-callable));
  the aggregates were not part of that change, and
  [DEPLOYMENT.md](DEPLOYMENT.md) recorded them as a known, untouched gap when
  the liveness sweeper shipped. Both now go through one shared
  `listLiveActiveRoomDocs()` (`functions/rooms/live_rooms.js`) that queries
  `isLive` alone and applies `roomIsActive()` in memory, exactly as
  `liveness_sweeper.js` already did
  ([ADR-097](Decisions.md#adr-097-a-live-room-count-that-must-honour-an-absent-status-is-a-bounded-read-not-a-count-aggregate)).
  The staff overview issued that query **twice** — once to count, once to
  list — and now issues it once. **Index impact, checked because dropping a
  clause changes which index serves the query**: the two-equality form needed
  a zigzag merge of two automatic single-field indexes (there is no
  `(status, isLive)` composite in `firestore.indexes.json`); a single equality
  on `isLive` is served by the automatic single-field index alone, so this
  **removes** an index dependency and needs no deploy of
  `firestore.indexes.json`. It is also the identical query the deployed
  sweeper has run every five minutes since `b7c6d99`. Verified: 754 Functions
  tests, 0 failures, on a clean emulator; the three new no-status cases were
  each confirmed to FAIL against the reinstated query. **Not deployed** — this
  is a Cloud Functions change only, no rules, index, client or Storage change.
- **FIXED IN SOURCE 2026-08-20, NOT DEPLOYED — `adminDeleteClub` left
  `activeVoiceSessions/{uid}/rooms/{roomId}` mirrors behind forever.** The
  per-room teardown loop in `functions/admin/clubs.js` called
  `liveKitControl.endRoom`, `cleanupRoomMedia` and
  `deleteDocumentRecursively` for each of the club's rooms but never
  `deleteActiveVoiceSessionsForRoom(roomDocument.id)` — unlike
  `setClubModerationStatus` in the same file, which has always cleared the
  mirrors right after `endRoom`. The mirrors live in a separate top-level
  collection, so recursive room deletion never touches them, and nothing
  else expires them: every voice session active at admin-deletion time
  became a permanent orphan. Fixed by adding the call after `endRoom` in
  the loop; the "admin Club deletion lifecycle" test in
  `functions/test/club_membership_security.test.js` now seeds two session
  mirrors — one with a participant row and one without (the
  collection-group sweep path) — and proves both are gone, and fails
  without the fix (verified by reverting it).

- **FIXED IN SOURCE 2026-08-19, NOT DEPLOYED — extra fields on a room message
  silently dropped the sender's achievement credit.**
  `functions/achievements/sources.js` treats an exact six-key room message as
  canonical; any extra field made the adapter return `null` and the event was
  skipped, with nothing logged and nothing visible to the sender. The
  pre-`01c0ab2` rule allowed arbitrary extra fields, so the two halves of the
  same contract disagreed. The rules allowlist is now that same six-key set,
  so **rules and adapter agree**. Consequence to carry: any new field on a
  room message needs a rules change *and* an `achievements/sources.js` change
  in the same commit, or this recurs.

- **OPEN, and not fixable from the client — presence is never cleared on
  process death.** `AuthService.signOut()` now clears presence inside the live
  session, but a force-quit or a server-revoked refresh token never reaches
  client code, and no client can write for a session that no longer exists.
  `functions/` has no presence sweeper — `public_profiles.js` clears
  `isOnline` only on account deletion — so those accounts stay online to
  their friends indefinitely. Closing it needs a scheduled function expiring
  `users/{uid}` on a stale `presenceUpdatedAt`, or a staleness cutoff when
  reading `socialPresence`. Flagged in the code's doc comment rather than
  approximated. Tracked as Roadmap item 0q.

- **OPEN, reported while writing the club-discovery list rule — a family
  room's owner can still set privacy `public` from the settings screen.** It
  grants nothing today (the new `clubs` list rule excludes family clubs by
  `type`, and the room's own reads are governed separately), but a family
  surface offering a public setting is a contradiction the UI should not
  present. Communication-muted accounts can also still react to messages.

- **[OPEN — needs a product decision] Three direct-conversation threads and
  ~30 rooms belong to dead Auth accounts.** `SqEQ493FrDUnD8l7j0egaoNCHnk2`
  ("Griefer") and `hMwXnWimPQOYhk50TPPw62towbc2` ("testGriefer") no longer
  exist in Firebase Auth, but their `users` docs, empty `publicProfiles`,
  three legacy DM threads (33 messages) and dozens of test rooms remain.
  The 2026-08-18 migration correctly refused those threads
  (`invalidPublicProfile`); the living-party UX is a chat row that cannot
  be operated on. Decide: retire/delete dead-party threads and orphan
  rooms, or keep them frozen. 25 of 43 `users` docs are Auth orphans in
  total. A pre-decision snapshot exists in
  `~/Documents/YO Voice Backups/2026-08-18-pre-dm-migration.json`.

- **[FIXED 2026-08-18] The "beyb" zombie room** (`mwrohOrlGAHQQBfCX2sn`,
  `status: closed`, `deletionInProgress: true`): a `deleteRoomSelf` crash
  (ADR-078) committed the closing transaction and died before teardown.
  The callable fix is deployed; the host's next Delete retry completes the
  removal (verified retryable: `closed` ∈ ROOM_STATUSES and
  `deletionInProgress` does not block deletion). Home no longer renders
  mid-deletion rooms as startable.


- **FIXED IN SOURCE 2026-08-17, NOT YET DEPLOYED — a `not-found` from any
  messaging callable disabled the entire server-side guard set, and a
  failed conversation open wrote a thread the backend can never touch
  again.** `MessageService._isCallableUnavailable` counted `not-found` as
  "the callable is not deployed". The server throws `not-found` itself as
  an ordinary refusal — `functions/integrity/guards.js:157` when
  `users/{uid}` is missing, `functions/messaging/direct_integrity.js:83`
  and `:223`. So a user with no `users` document received `not-found` from
  **every** messaging callable and the client read each as an absent
  deployment, silently bypassing `assertNotBlocked`,
  `assertNotRestricted` and the rate limits across send, edit, delete,
  react, mark-read and typing. The ambiguity is irreducible — an
  undeployed callable is HTTP 404 too — so `not-found` now propagates and
  only `unimplemented` signals absence.

  **The conversation-open path made it a data-integrity bug, not just an
  authorization one.** On that swallowed error, `openOrCreateConversation`
  created the conversation root itself. The client cannot write
  `directConversationPairs/{pairKey}` — no rules match block, by design —
  so the root has no pair guard, and `validateConversation` refuses it
  with `data-loss`, "The canonical conversation is missing.", on every
  later server call, permanently. It also carried 12 keys against the
  required 18. **This is the same class of defect as the
  `_publishRecordedMomentLegacy` entry below** — a client fallback writing
  a document an exact-key server validator will reject forever — with one
  difference that makes it worse: that one is latent because nothing
  reaches the path, while this one had a live trigger in production, and
  the 32 accounts with no public profile
  ([Roadmap 0a](Roadmap.md#0a-run-the-public-profile-backfill-verified-consistent-2026-08-18))
  are the population most likely to have hit it.

  `openDirectConversation` is now the only production path and its answer
  stands, success or failure; `conversations` create is `if false` in
  `firestore.rules` so the invariant holds for installs that will never
  update; `directConversationPairs` keeps no match block, now a recorded
  decision
  ([ADR-062](Decisions.md#adr-062-the-client-never-creates-a-direct-conversation--canonical-binding-is-server-only-and-a-legacy-thread-is-adopted-in-place-not-forked)).
  Covered by `test/direct_conversation_open_test.dart` (18 cases, all
  Firestore-level), an inverted case in
  `test/direct_message_send_test.dart` that previously asserted the
  defective behaviour outright, and three new checks in
  `firestore-tests/rules.test.js`.

  **Roots already written this way are stranded and their count is
  unmeasured.** They are identifiable by a missing `pairKey`/`schemaVersion`
  on the conversation document, or by the absence of a
  `directConversationPairs` entry for the pair. They are repairable —
  unlike the duplicate messages below — because
  `migrateDirectIntegrityConversation` adopts a legacy root **in place** at
  its existing id, preserving history. That migration has never been run
  against production; it is
  [Roadmap 0m](Roadmap.md#0m-run-the-direct-conversation-migration-there-are-stranded-legacy-roots-in-production).
  Until it is, `openDirectConversation` **forks**: it derives a fresh
  `dm_<hash>` id, binds the pair to that, and leaves the legacy thread and
  its history behind. That fork is pinned by a test in
  `functions/test/direct_integrity.test.js` so the cost of not running the
  migration is visible in the suite.

- **FIXED IN SOURCE 2026-08-17 (`8f7aa03`), NOT YET DEPLOYED — every direct
  message was written to Firestore twice.**
  `MessageService.sendTextMessage` called the `sendDirectMessage` callable,
  which creates the canonical message document and updates the conversation
  summary server-side inside one transaction, and then ran its own client
  batch write **unconditionally** — the early return existed only on the
  fallback path. Every send in production therefore produced a second
  message document under a Firestore auto-id and incremented
  `unreadCounts.<recipientId>` twice. Both copies render: `watchMessages`
  orders by `sentAt` with no filter. `sendTextMessage` now returns as soon
  as the callable answers, and the client write is reached only when it
  does not
  ([ADR-061](Decisions.md#adr-061-a-callable-that-answers-is-the-whole-write-and-its-client-fallback-must-write-the-same-document)).

  **It went unnoticed because no test had ever executed that branch.**
  Every Flutter test injected a `NotificationService`, which sets
  `_preferLegacyBehaviour` and short-circuits `_tryCallable` to `false`, so
  the callable-success path was unreachable from the entire suite — a green
  suite covering exactly one side of the fork that mattered.
  `test/direct_message_send_test.dart` now asserts at Firestore level on
  both paths, "exactly one message document" included; against the pre-fix
  service it fails 10 of its cases, the probe reading being
  `messages=2 unread[recipient]=2` where 1 and 1 were expected.

  **The duplicates already in production are permanent, and their volume is
  unmeasured.** They carry 14 keys, not the canonical 16, so `validateMessage`
  refuses them and the server can never edit, delete, react to, or accept
  them as a reply target. Identifying them by their missing `schemaVersion`
  over-selects on its own — it also matches every pre-fix *fallback* write —
  so a cleanup pass needs that paired with a deploy-date cutoff or a
  same-sender-and-content twin. Three things reasoned from code and **not
  yet verified against production data**: read-marking was never poisoned
  (`markDirectConversationRead` filters on `sequence > N`, and a range
  filter excludes documents missing the field), inflated `unreadCounts`
  self-heal on the recipient's next open, and the canonical chain is intact
  because only the server ever advanced `lastMessageSequence`. Duplicates
  keep accruing until a client carrying `8f7aa03` ships — no client release
  is recorded after that commit.

  The same commit closed three messaging failures that were invisible to
  the user, found while in the file: `toggleReaction`, `setTyping` and the
  un-archive inside an unawaited handler all swallowed their errors. They
  now use the shared error mapping, with typing raising at most one
  snackbar per visit because it fires per keystroke. Covered by
  `test/messages_silent_failure_test.dart`.

- **FIXED 2026-08-16 — accounts with no public profile were invisible to
  everyone else.** After the ADR-054 rules cutover, `users` became
  owner-`get` only and non-listable, so an account with no
  `publicProfiles` projection could not be seen by any other user in
  either client. The backfill closed it: 14 projections created, 28 writes
  applied, and a verification re-run planned zero writes with all 33
  accounts unchanged — idempotent against real production data.

  **Worth remembering how the headline number was wrong.** A console count
  of 33 `users` against 1 `publicProfiles` reads as 32 missing. The
  backfill's own dry run showed the truth: **18 of the 33 are Auth
  orphans**, which correctly get no projection. The real gap was 14.
  Counting two collections against each other is not a measurement when one
  of them is derived with conditions.

- **OPEN — 18 `users` documents have no Firebase Auth account.** Surfaced
  by the backfill's `authOrphans: 18` on 2026-08-16. Origin unknown; most
  are likely deleted test accounts from before `onAuthUserDeleted` existed,
  since that trigger only covers deletions occurring after it was deployed
  the same day. They hold no projection and are invisible, so nothing is
  user-facing — but they are stale personal data with no owner, which makes
  this a retention question as much as a tidiness one. Decide deliberately
  whether to delete them; do not fold it into an unrelated migration.

- **FIXED 2026-08-16 — the ADR-054 legacy identity scrub has run.** All
  four phases applied, `conflicts: 0`, 21 documents (conversations 5,
  friendRequests 6, following 5, followers 5), verified by a re-run
  planning zero further scrubs. Note it was run *after* the rules deploy,
  which was the wrong order and briefly a live defect rather than
  housekeeping — the ADR-054 deployed rules required follow edges to carry
  exactly `['uid','followedAt']`, Firestore denies a list query if any single
  document fails the rule, so one legacy five-key edge emptied a user's
  entire followers/following list. ADR-114 source later preserves that legacy
  shape while allowing one optional bounded server-owned generation pointer.
  See
  [DEPLOYMENT.md](DEPLOYMENT.md#private-profile-projection-cutover-strict-order--executed-2026-08-16).

- **FIXED AND DEPLOYED 2026-08-16 — the real Club creation batch was
  rejected even for an entitled owner.** `ClubService` atomically creates the
  Club, owner member, user's Club projection, three default channels and the
  lounge room. Owner-member/channel rules used pre-write `get()`, so they could
  not see the new Club root inside that same commit; the batch also included a
  dead root-user `clubCount` update outside the self-write allowlist. Those
  rules now use `getAfter()`, the unused counter write is removed, and the
  emulator suite exercises the full seven-document batch.

- **KNOWN AND ACCEPTED — `rooms/{roomId}.memberCount` can overcount.** A
  client that deletes its `roomMembers` row without pairing the room write
  leaves the counter high. It can never undercount below a real departure,
  which is the property that matters: an undercount was what trapped
  members in rooms they could not leave. Treat the field as an upper
  bound. Deliberate trade, `952d8e4`,
  [ADR-056](Decisions.md#adr-056-a-moderation-action-belongs-in-a-callable-that-completes-the-whole-removal-not-in-a-rule-that-deletes-one-row).

  **Swept in production 2026-08-17: no victims exist.** 50 rooms examined,
  **28** whose stored count disagrees with their true row count, **0
  trapped** — every mismatched room has zero membership rows, so there was
  never anyone to trap. **24 rooms carry no `memberCount` field at all**,
  which is precisely the legacy shape that *would* have trapped members had
  any of those rooms had one. The trap was real; it simply did not land
  before `952d8e4` removed it. No repair migration is needed, and none
  should be written for the overcount — it is the accepted direction.

- **Possible orphaned `rooms/{roomId}/members` documents.** When that
  subcollection was renamed to `roomMembers` (see
  [ADR-005](Decisions.md#adr-005-roomsroomidmembers-renamed-to-roommembers)),
  any pre-existing production documents under the old name became
  invisible to the app. Never verified whether any existed at rename
  time — no `gcloud`/Application Default Credentials were available in
  the session that made the change. **Action**: check the Firestore
  Console's `rooms/*/members` collections directly, or query via
  `firebase-admin` with a real service account key. If any exist, write a
  one-time copy migration. Tracked in
  [Roadmap.md](Roadmap.md#1-verify-no-orphaned-roomsroomidmembers-documents).
- **`experience: podcast` legacy compatibility.** Still actively read by
  `lib/features/rooms/data/models/room_experience.dart` — do not remove
  until production room documents are confirmed migrated to `broadcast`.
  See [ADR-001](Decisions.md#adr-001-legacy-podcast-room-experience-stays-supported).

## Branding

- **FIXED IN SOURCE 2026-08-28 — Android adaptive launcher icon overfilled
  OEM masks.** The transparent foreground occupied about 84.5% of its source
  layer and was inset by only 8%, leaving the rendered mark up to roughly
  77dp tall against Android's 66dp adaptive safe area. The Android-only inset
  is now 16%, matching the generator default and keeping the symbol within the
  safe area on circle, squircle and rounded-square masks. The canonical PNG,
  legacy Android icon and every iOS/App Store asset are unchanged. Android
  build 7 is available to the existing 10 internal testers; an update and
  fresh-install launcher check remain release evidence.
- **FIXED — native launcher/store icons still contained the retired black
  square.** Web favicons had already moved to the transparent canonical mark,
  but `flutter_launcher_icons` continued reading the old opaque `logo.png`.
  Android adaptive, Android legacy, iOS/App Store, macOS, Windows and the
  in-app compact logo now derive from the favicon artwork. Opaque platforms
  receive only the required full-bleed product background, without a second
  black tile around the symbol.
- **FIXED — opening the app could show two sequential, time-based loading
  screens.** The landing site's `/app` route imposed a 2.8-second animation
  before navigation, then authenticated Flutter sessions imposed another
  four-second welcome timer. `/app` now redirects immediately, the fixed
  Flutter timer is gone, and the app origin owns one matching sound-wave
  startup surface that exists only while the engine/Auth state genuinely
  resolves. Its shared responsive layout uses a larger, lowered logo with the
  title layered across the mark's lower edge instead of floating too high.
- **FIXED IN SOURCE 2026-08-27 — the remaining native-to-Flutter launch handoff
  visibly jumped.** iOS launch images were 1×1 transparent, Android's mark was
  commented out (and Android 12 had no matching system-splash theme), the ring
  opacity reset at its modulo boundary, and Auth replaced the loading surface
  without a transition. Native iOS/Android and Flutter now share the same
  #0D0618 surface, centred 170 logical-pixel mark and Android light/dark API-31 themes;
  the ring envelope reaches zero on both sides of its wrap and Auth crossfades
  for 220 ms (or instantly under Reduce Motion). The mark is positioned in its
  own centred layer, so text metrics and 200% scaling cannot move it. **WEB
  DEPLOYED 2026-08-27; native iOS and Android 12+ handoff remains pending and
  still needs device verification.** See ADR-052.

## Notifications

- **FIXED — notification activity could stop at the numeric bell badge.**
  Android referenced `yovoice_default` but never created the channel, the
  server payload did not select a channel or default sound/vibration, and a
  focused browser tab did not present foreground FCM messages. The app now
  creates a high-importance audible channel, explicitly presents native
  foreground alerts with sound, shows a compact actionable web banner, and
  sends platform-specific audible/visible payload options. Device/browser
  notification permission, Focus/Do Not Disturb and mute settings remain OS
  controls and cannot be overridden by an app.

- **SUPERSEDED — friend requests, acceptances and follows could silently
  produce no notification.** All three were a second client write issued
  after the authoritative write, inside `try { ... } catch (_) {}`. Any
  interruption between the two writes lost the notification permanently
  and reported nothing. ADR-041 first moved them to derived triggers.
  ADR-114 supersedes that implementation with the social callable as the
  single transactional writer, because the trigger and callable later
  overlapped.
  **Deployed 2026-08-16, retired 2026-08-25** — those three historical
  triggers were explicitly deleted when ADR-114 became the production
  single-writer contract.
- **FIXED AND DEPLOYED 2026-08-25 — resolved/cancelled friend requests could leave or
  resurrect an unread alert.** Cancel omitted the notification cleanup and
  legacy source triggers could overwrite the callable's resolved state. The
  callable now retires actionable rows atomically on accept/decline/cancel,
  repairs stale rows on replay, and retires the active lifecycle rows on
  unfriend/unfollow so later lifecycles receive fresh generation ids.
  Friend-request taps open Requests with Accept/Decline, the mobile bell shows
  the unread count, and new lifecycles use generation-specific ids. Push
  delivery re-checks both document generation and the canonical graph source;
  retired compatibility ids were removed during rollout (ADR-114). The
  production journey passed before and after trigger deletion, and the final
  source-aware sweep planned zero further deletions.
- **FIXED — clients could forge these three notification types.** A
  client could write "X accepted your friend request" with no friendship
  existing; rules cannot check that. The three types were removed from
  the client-creatable list, and the server authority validates the
  friendship itself. ADR-114 now keeps that authority inside the deployed
  graph transaction.
- **FIXED — web push configuration.** The service worker
  (`web/firebase-messaging-sw.js`) now exists and ships in the build, and
  `getToken()` passes a `vapidKey` from
  `--dart-define=YOVOICE_WEB_PUSH_VAPID_KEY`. The production public key is
  generated in Firebase and supplied by the Hosting workflow. Without a key,
  local builds still skip web push setup entirely — no permission prompt
  spent, no `getToken()` call, no empty token written, one clear log line.
  End-to-end delivery still needs a signed-in real-browser smoke test.
- **FIXED — the Notifications screen collapsed on an unrelated failure.**
  It returned one "Could not load notifications" state if ANY of three
  streams errored, including the unrelated conversations stream, and
  spun while any one was still loading. Loading and fatal errors now
  depend on the activity feed alone; an auxiliary failure degrades to a
  small notice above the feed, which keeps rendering.
- **OPEN — `mention` has no authoritative writer.** Firestore Rules deny every
  client notification create. Club/room invites, direct messages and replies
  use server paths; mention remains an enum/rendering contract without a
  production writer and must not be described as a client best-effort path.

## Achievements

- **FIXED LIVE 2026-08-19 — three infinite trigger retry loops: the second
  qualifying action of a user-day was an unresolvable ledger collision.**
  `activeDay` events key their dedup identity on (uid, UTC day) but carried
  the triggering event's exact time inside the content fingerprint, so the
  first action of a day wrote the ledger entry and every later action that
  same day derived the same eventId with a different fingerprint. The engine
  threw `AchievementEventIntegrityError` (fail closed) and, with `retry:
  true`, Eventarc redelivered forever — the primary event's transaction had
  already committed, so each loop burned invocations every 1–3 minutes.
  Latent since the 2026-08-16 launch; first tripped 2026-08-18 17:34Z.
  Production had three loops across `onAchievementRoomMessageCreated` and
  `onAchievementDirectMessageCreated` (ledger ids `v1_29153e…`, `v1_96d81c…`
  — hit by both a room message and a DM — and the unreported `v1_3c2af0…`).
  Fixed by ADR-081: mismatches are terminal (quiet replay for
  same-content-different-time recurrences, logged collision otherwise),
  `activeDay` content is now a pure function of (uid, day), and the four
  pre-fix ledger entries were rewritten canonically by
  `functions/scripts/repair_achievement_canonical_ledger.js`. Regression
  tests fail 10/10 against the pre-fix code.

- **FIXED LIVE 2026-08-19 — `reconcileAchievementsV1` was wedged on the
  first user in the collection since its first run (2026-08-16 18:40Z).**
  That user's document is a legacy presence-only skeleton;
  `legacyProgressFromUser` returned `undefined` for two fields, Firestore
  rejected the bootstrap write, and `failUser` then merge-created a partial
  record ({status, failureCode, updatedAt} only) that `beginUser` rejected
  as "Stored user migration state is malformed" on every 15-minute run —
  ~96 failures/day for three days, with the global cursor never advancing
  past user one. Distinct root cause from the retry loops, same
  fail-closed-forever pattern, surfaced in the same incident review. Fixed:
  the bootstrap shape is undefined-safe, `failUser` always writes a
  self-describing record with an attempt counter, `beginUser`
  re-initializes pre-bootstrap failures (terminal after 5 attempts) and
  marks contradictory records failed while the run advances. The production
  poison record was rewritten by the ADR-081 repair script.

- **FIXED IN SOURCE 2026-08-19 (preventive) — the reconciler bootstrap
  would have erased live verified progress.** `beginUser` unconditionally
  overwrote `achievementProgress/{uid}` with a legacy bootstrap. Three
  production users already hold live trigger-accrued verified progress the
  dedup ledger can never replay; once the unwedged reconciler reached them,
  their verified counters would have been reset and the legacy floors
  re-derived from user-document counters the projection had already
  replaced with verified values. `beginUser` now adopts existing progress
  untouched and derives audit floors from it. Caught by review during the
  ADR-081 incident work, before the reconciler ever reached those users.

- **FIXED — every achievement progress transaction was denied by Firestore.**
  `AchievementService` atomically writes the metric counter, unlocked ids,
  unlock timestamps, selected title and reconciliation timestamp, but the
  self-update allowlist omitted `unlockedTitleTimestamps`. Firestore rejected
  the whole transaction, while best-effort callers intentionally swallowed
  the tracking failure so the source action could still succeed. The field is
  now allowed and emulator-covered; Awards also reconciles counters on open.

- **OPEN — `voiceMinutes` is written by nothing, so the entire voice
  achievement category and Creator Studio's "Voice time" tile are
  permanently zero for every account.** Traced end to end on 2026-08-16:
  `ProfileService` seeds the field to `0`;
  `functions/achievements/model.js` only ever *derives* it from
  `voiceSeconds`; and the sole producer of `voiceSeconds` is
  `receiveLiveKitAchievementWebhook` in
  `functions/achievements/livekit_http.js`, which is **never exported from
  `functions/index.js`** and therefore has never been deployed. Nothing is
  broken in the sense of erroring — the number is simply always zero, and
  both surfaces present it as a real measurement. Wiring the webhook also
  fixes the `publishPublicStatsSchedule` data-source problem, since
  LiveKit emits `participant_left` / `participant_connection_aborted` even
  on a crash. Until then, do not read `voiceMinutes` as a metric.

## Moderation & safety

- **FIXED IN SOURCE 2026-08-21, INDEX NOT DEPLOYED — the Admin Center's
  room-status filter did not work for any value, and its "active" value
  asked the wrong question.** `listAdminRooms` built
  `where("status", "==", status).orderBy("updatedAt", "desc")`, and **no
  `status`+`updatedAt` composite index exists in the live project** — so
  every status filter returned `9 FAILED_PRECONDITION`, not a truncated
  list. Underneath that, the "active" value contradicted ADR-093: a
  production census (2026-08-21) finds 45 rooms carrying **9 explicit
  `"active"`, 11 `"closed"`, and 25 no `status` at all**, so the literal
  clause recognised 9 of the 34 rooms the rules call active — while
  `mapRoom`, in the same callable, already reported those 25 as
  `status: "active"` to the browser. "Active" now means active as the rules
  read it (`roomIsActive()`, in memory, for that value only); other values
  keep the indexed equality. Eight cases in
  `functions/test/admin_room_listing.test.js` pin it, three of which fail
  against the unfixed callable. **Still open**: `closed` and `suspended`
  stay broken until `firebase deploy --only firestore:indexes` runs — and
  that deploy must NOT be run from this branch alone, which lacks the live
  `clubs.clubId` exemption and would offer to delete it. Note this callable
  has no caller in `lib/` — the browser it serves is in the website or
  unbuilt — so the user-visible impact is confined to whoever calls it.
  [ADR-101](Decisions.md#adr-101-the-admin-centers-active-room-filter-reads-status-the-way-the-rules-do--and-the-filter-it-replaced-never-ran-at-all).

- **OPEN, found 2026-08-21 — three layers disagree about what an absent club
  `status` means, and one of them invents a value.** Unlike rooms, the club
  rules read the field BARE (`get(clubPath).data.status == 'active'`, three
  sites in `firestore.rules`), so a club with no `status` is not active to
  the ruleset — while `functions/clubs/deletion.js:128` defaults it the
  other way (`String(club.status ?? "active")`), treating the same club as
  deletable-because-active. Separately, `mapClub`
  (`functions/admin/clubs.js`) defaults an absent status to **`"open"`**, a
  value nothing in the codebase ever writes: production clubs carry
  `"active"` or `"closed"`. 1 of 3 production clubs has no `status`, so all
  three disagreements are live, just small. Not fixed with the room filter
  on purpose — picking a direction here is a product call about club
  lifecycle, not a mechanical copy of ADR-093, and the wrong pick changes
  who can delete a club. See ADR-101's Consequences.

- **FIXED IN SOURCE 2026-08-19, NOT DEPLOYED, AND NOT VISUALLY VERIFIED —
  club chat moderation had never worked.** A club owner could not remove an
  abusive message from their own club. Three layers held three different
  beliefs: `ClubChatService.deleteMessage` authorised moderator, admin and
  owner; the rule was **author-only**; and the UI never offered the action at
  all, wiring `onLongPress` solely to the viewer's own messages. `b3c27fd`
  ships all three halves together — rules alone are invisible and the client
  alone is denied. The rule carries two **disjoint** branches (author
  retracts, moderator removes), separated on `senderId == uid` vs `!=`
  **before any document read**, because CEL absorbs errors through `||`
  (`<error> || true` ALLOWS). Both branches pin `content` to the empty
  string, so editing is not expressible by anyone. An early version of the
  moderator branch restated only account status, so a **communication-muted
  or unverified-email moderator kept full reach** over every non-owner
  message in every club where they held a role — both sanctions are now
  required on that branch. `f817b41` then fixed an accessibility and visual
  FAIL: the confirmation dialog **silently truncated at large text sizes**
  (no exception, no overflow stripe — the sentence naming the action simply
  vanished, so a user with bigger type confirmed a removal without being told
  what it did), the message header overflowed and **erased the sender name at
  DEFAULT text size** whenever the staff badge was wide, and long-pressing
  the club owner's message did nothing at all so the local refusal copy
  reached nobody. **UNVERIFIED**: nothing was rendered after the reworked
  header and dialog — both review agents died on a session limit — so this
  must not deploy on a UI claim until it has been looked at. See
  [ADR-085](Decisions.md#adr-085-authorization-branches-in-a-rule-are-disjoint-by-construction-because-cels--absorbs-errors).

- **OPEN — a club moderator's removal is recorded nowhere.** Named in the
  rule's own comment as an accepted gap rather than left for a reader to
  discover. The only trigger on that collection is
  `onAchievementClubMessageCreated`, an `onDocumentCreated`, so a moderator
  removal leaves **no `adminAuditLogs` entry**. The client writes
  `deletedBy`/`deletedAt` from day one so an audit trigger has what it needs
  when one exists. Three siblings in the same comment: **no rate limit**, **no
  restore path**, and **no rank ordering** — a moderator can clear an admin's
  or a co-owner's messages.

- **FIXED IN SOURCE 2026-08-19 → 2026-08-20, NOT DEPLOYED — no message
  anywhere in the product could be reported.** Not a DM, not a room message,
  not a club message. `createContentReport` was **deployed and ACTIVE** and
  already accepted `directMessage`, `voiceMoment` and `voiceMomentComment`;
  **no Dart file called it.** The only report action in the product was on a
  profile, with `reason` hardcoded to `harassment`, a fabricated note reading
  "Reported from profile", and no reach into club chat at all. Reporting the
  same person twice showed the raw string
  `[cloud_firestore/permission-denied] The caller does not have permission`,
  because the client was reading back its own report to tell "already filed"
  from a refusal — but `reports` is staff-read by design, so
  `ReportAlreadyFiledException` was **unreachable in production** and one raw
  string covered both the 30-second cooldown and the 20-per-day cap. `9f3ce7f`
  wires every target the callable supports to every surface where that
  content appears, replaces the read-back with the owner-readable
  `reportLimits` document checked before the write, maps nine callable status
  codes to nine distinct sentences, and replaces the hardcoded reason with a
  picker. `2c086c7` adds `roomMessage` and `clubMessage` server-side. Visual
  verification caught what widget tests could not: **both snackbars rendered
  as dim grey on near-black**, because the Material 3 dark snackbar theme
  paints its own colour.

- **OPEN, and actively misleading — the Moderation Center renders a v2 report
  badly.** Two report schemas now coexist in `reports/` after `2c086c7`.
  `targetType` parses to null so **the queue title is blank**, and
  `reportedUserId` defaults to empty so the detail pane says **"This account
  no longer exists"** about a live account. That is worse than blank: a
  moderator reading it will make the wrong call. The fix spans Dart and
  Functions together. Tracked as Roadmap item 0o.

- **OPEN — moderators can triage room and club message reports but cannot
  action them.** `removeAndResolve` is still globalChat-only, so the queue
  now accepts reports it has no removal path for. The vocabulary is already
  aligned (`roomMessage`/`clubMessage` are exactly the target names
  `admin/messages.js` uses for the removal callable), so this is a branch to
  add, not a design to invent.

- **OPEN — `reason` has no server-side enum on the callable path.** The
  client-direct v1 rule in `firestore.rules` constrains `reason` to eight
  values; `createContentReport` does not. So a report whose reason is
  off-list is **invisible to the Moderation Center's equality filter** — it
  exists in the collection and never appears in the filtered queue.

- **OPEN, inherited and restated rather than discovered later — a report
  cannot be re-filed after a moderator dismisses it.** Deduplication rides
  the server's operation ledger with the idempotency key derived from the
  **target** rather than the attempt, so a second report of the same content
  replays the first outcome. The previous deterministic-id path had the same
  limitation. See
  [ADR-087](Decisions.md#adr-087-an-idempotency-key-derived-from-a-request-payload-is-a-compatibility-surface--new-fields-fold-in-only-when-the-target-carries-them).

- **BY DESIGN, not a gap to fill by re-adding a rule — host eviction does
  not exist anywhere in the product.** Removed deliberately in `952d8e4`.
  A rules-level delete removed a roster row and nothing else: the evicted
  account stayed connected to the live audio, kept chat through
  `isRoomParticipant`, and could rejoin a public room immediately. It also
  created a starvation primitive, because the delete was gated on a
  counter the host could write. If the product wants eviction, it needs a
  **callable** that completes the whole removal — roster row, live-audio
  disconnect, chat withdrawal — in the shape of
  `removeRoomParticipantSelf`. Do not restore the rule. Full reasoning:
  [ADR-056](Decisions.md#adr-056-a-moderation-action-belongs-in-a-callable-that-completes-the-whole-removal-not-in-a-rule-that-deletes-one-row).


- **FIXED — Staff Center user lookup could not find existing users.**
  `users.username` is stored AS TYPED (seeded verbatim from the display
  name, e.g. `Sieeema`) while the lookup lowercased the input into a
  case-sensitive Firestore equality — so every casing the owner could
  type missed, and display-name search did not exist at all. Reproduced
  against the emulator with the exact client query, fixed 2026-08-15
  ([ADR-046](Decisions.md#adr-046-user-search-lives-in-a-server-only-directory-behind-an-owner-callable-staff-center-becomes-seven-capability-gated-sections)):
  search now runs server-side over the normalized `userDirectory` index
  (owner-only callable), and `listAdminAuditLogs` was remapped to the
  flat audit schema its queries never actually matched.

- **FIXED — a forged non-owner `superAdmin` role would have been
  mirrored, and rendered, as the owner badge.** `deriveBadge()` never
  saw the uid, so a stale or planted `superAdmin` value in a user
  document reached `publicBadges` verbatim. Fixed 2026-08-15
  ([ADR-045](Decisions.md#adr-045-one-authoritative-identity-badge-system--owner-guarded-derivation-a-batched-client-repository-and-a-single-family-of-badge-widgets)):
  derivation is owner-guarded (publishes `superModerator` + writes the
  `security_alert_non_owner_super_admin` audit event), the batch
  callable demotes stale stored rows, and the backfill refuses to run
  without the owner secret. Global Chat also no longer renders identity
  from the message-embedded `senderIsStaff` flag — badges resolve by
  sender uid from the projection.

- **RESOLVED 2026-08-16, and the premise inverted.** This entry read
  "Production is running a client that is ahead of its backend. Pushing to
  `main` auto-deploys Hosting…" — describing the Global Chat and
  Moderation Center clients shipping ahead of their Functions, indexes and
  rules. `moderateReport`, `listReportAuditTrail` and the `reports` indexes
  are all now deployed (`firebase functions:list`,
  `firebase firestore:indexes`, 2026-08-16).

  Two corrections worth keeping, because both were load-bearing beliefs:
  **(1)** pushing to `main` has not auto-deployed Hosting since `409c7ee`
  — releases are a manual `workflow_dispatch`. **(2)** The drift therefore
  reversed direction: production sat on commit `9fdd8a9` while ~60 Cloud
  Functions were deployed and *inert* because no client called them.
  Backend-ahead-of-client is harder to spot than client-ahead-of-backend,
  because nothing visibly fails. See
  [ADR-055](Decisions.md#adr-055-the-2026-08-16-production-cutover--order-the-deploy-by-what-fails-closed-and-verify-by-fingerprinting-served-bytes).
- **FIXED — the audit timeline's status arrow rendered as a tofu box.**
  `'open → resolved'` used U+2192, and Roboto — the font CanvasKit falls
  back to on web — has no glyph for it. Caught by actually looking at a
  rendered screenshot, not by any test. Now `'open › resolved'`
  (U+203A, which Roboto has). A sweep of every UI string literal found
  no other missing glyph; the remaining non-ASCII characters are emoji,
  which resolve through CanvasKit's emoji fallback.
- **FIXED — a failed audit page took the loaded history with it.** A
  pagination failure in the timeline replaced the whole list with an
  error box, so a moderator lost the history they already had. The error
  is now inline beneath the events, and Retry resumes from the same
  cursor.

- **FIXED — Mobile More could hide Moderation behind Staff Center.** The
  capability mapping returned only one staff destination, so owners and
  super moderators saw Staff Center but lost the separate Moderation entry
  available on desktop. Mobile now lists every destination their server
  capabilities grant; ordinary accounts remain unchanged.
- **FIXED IN SOURCE 2026-08-27 — Mobile More used four rows of oversized
  160–176 px destination cards and forced a normal expanded sheet to scroll.**
  At ordinary text scale destinations are now compact 78 px two-/three-column
  tiles and staff/settings are 58 px rows; a 320×568 ordinary sheet and
  390×844/430×932 owner sheets fit without scrolling. At enlarged text the
  sheet deliberately reflows to full-width rows and keeps scrolling as the
  accessible safety valve. Every action and capability gate remains intact,
  with named ≥44 px targets. **DEPLOYED TO WEB 2026-08-27; NATIVE STORE BUILD
  PENDING.**
- **`adminAuditLogs` has no BROAD staff-facing view.** Entries are
  written deterministically and stay unreadable by every client, staff
  included. A moderator can now see one report's own history through the
  scoped `listReportAuditTrail` callable (ADR-040), which is the only
  client-reachable path into the collection and cannot be pointed
  anywhere else. Reviewing the whole log still means the Firestore
  Console or the admin-only `listAdminAuditLogs` callable.
- **A newly promoted moderator must refresh their token.** Staff access
  requires the signed claim as well as the server record, so promotion
  takes effect when the ID token refreshes (up to an hour, or instantly
  on sign-out/in). Revocation is immediate. This asymmetry is deliberate:
  it fails closed.
- **Global Chat had no report-triage UI** — now addressed by the
  Moderation Center; the note below covers what is still missing. Reports land in `reports`
  and are readable only by accounts holding a `moderator`/`admin`/
  `superAdmin` role claim — through the Firestore Console, because no
  Admin Center screen lists them yet. Filing one records it; nothing is
  automated, and the reporter gets no follow-up. Tracked as the first
  gap to close if Global Chat sees real use
  ([ADR-037](Decisions.md#adr-037-global-chat-is-one-canonical-public-channel-written-directly-under-security-rules-with-a-rules-enforced-rate-limit)).
- **Blocking on Global Chat is a UI filter, not a read boundary.**
  Firestore delivers every channel message to every active account,
  including ones from senders the reader blocked; the panel drops them
  from the rendered list (and waits for the block list before its first
  paint, so nothing flashes). Anyone reading the collection through the
  SDK sees everything. It is also one-directional: an account that
  blocked *you* still sees your public messages. Symmetry, or a real
  per-recipient boundary, would need a mirrored `blockedBy` edge or
  per-user fan-out — deliberately not built here.
- **A ban reaches Firebase Auth slightly after it reaches Firestore.**
  `setUserBan` disables the account, revokes refresh tokens, and writes
  `users/{uid}.banned`. Firestore rules read that field, so database
  access stops on the **next request**. The ID token itself stays
  cryptographically valid until it expires — at most one hour — so any
  surface that trusts the token alone (currently none in this app, but
  worth knowing before adding one) has that window.
- **Global Chat rate limiting is a floor, not a shield.** Rules cap a
  sender at one message every 3 seconds AND 200 per FIXED one-hour
  window, and a reporter at one report every 30 seconds AND 20 per fixed
  24-hour window. The windows tumble rather than slide, so an account can
  send up to 400 messages across two adjacent hours by straddling a
  boundary — still a 3x reduction on the floor's 1,200/h. That
  stops flooding from one account; it does not stop a distributed
  abuser, and there is no content filtering of any kind. Combined with
  [ADR-004](Decisions.md#adr-004-firebase-app-check-integrated-client-side-enforcement-deliberately-off)'s
  open App Check gap, a script holding a valid ID token can post at that
  rate.

## UI

- **FIXED IN SOURCE 2026-08-29 — collapsing a live-room chat exposed a large
  multi-row control panel that obscured the Home feed.** Phone and compact-
  tablet layouts now use one 82 px YO Live Capsule with a separate room-return
  zone and circular 48 px Chat, Mic and More controls; low-frequency Return and
  Leave/End actions live in a compact modal. The redesign also closes two
  lifecycle hazards found during review: remote session replacement dismisses
  only the exact controls route (never the underlying screen during the
  sheet's reverse transition), and a stale host confirmation cannot disconnect
  the next room. Busy Mute consumes input without advertising an accessibility
  action; mobile honors the full system text scale. Twenty-six focused widget
  regressions and Dark/Pearl production-dock renders cover these boundaries.

- **Fixed in source 2026-08-29 — Home Moments rendered a large filler card,
  friend-only identities and profile suggestions without audio.** Mobile and
  desktop Home now render a story-style avatar rail: the signed-in avatar
  first, followed authors only, and only when an active Voice Moment has a
  playable audio URL. Multiple Moments from one author become one ordered
  chain. The empty card, duplicate Find creators/Record actions, desktop
  profile shortcuts and divider are gone; a quiet rail ends after the user's
  avatar. Following-load failure fails closed. See ADR-123. The source change
  awaits the next coordinated tester build.

- **FIXED AND RELEASED TO WEB/MOBILE BETA 2026-08-28 — Vibe saved successfully but disappeared on
  full profiles.** The editor wrote `statusMessage`, the model read it back,
  and compact profile previews already used it; both the signed-in member's
  older Voice identity card and the full friend-profile route omitted it.
  Both routes now share one labeled, full-width Vibe headline, treat Vibe alone
  as a populated identity, and wrap the full 80-character value at narrow
  widths and enlarged text. The signed-in card's stale identity predicate also
  omitted `website`, so a website-only profile falsely showed the empty state;
  that branch is fixed too. One regression drives Save through Firestore and
  the shared profile stream; production-widget coverage pins both full-profile
  routes, including 320 px/200% accessibility layouts. Browser inspection
  covered the shared card at 390, 768 and 1180 px plus the actual friend route
  at 1280 px with no visible overflow. The pinned Hosting artifact is live,
  TestFlight build 10 is Testing in both permanent tester groups, and Google
  Play Internal Testing exposes version code 10 to the selected cohort.
  **FOLLOW-UP FIXED IN SOURCE 2026-08-29 — HTTPS links inside the now-visible
  Vibe were still inert text.** Own profile, another member's profile and the
  compact Profile Preview now share one actionable renderer. It removes each
  URL from the prose and presents a separate 48 px link row with the real host,
  a provider label for boundary-verified YouTube, Spotify, Apple Music and
  other known music domains, keyboard focus/Enter, link semantics and an
  external universal-link handoff so the installed music app can claim it and
  the browser remains the fallback. Unknown public HTTPS destinations stay
  honestly labeled External link. User-generated non-HTTPS, credentialed,
  local/private-style, IP, custom-port and non-ASCII-authority URLs remain
  plain text; false/throwing launch attempts stay visible inline without
  exposing platform errors. Parser, double-fire/cooldown, disposal,
  accessibility, preview-bio fallback and 320 px/200% regressions cover the
  path. See ADR-126. **FOLLOW-UP FIXED AND RELEASED TO WEB 2026-08-29 — the Dark Vibe
  surface and identity chips used primary purple beneath primary-purple
  icons, collapsing the visual hierarchy and dropping informative icon
  contrast as low as 1.46:1.** Vibe now uses a calm opaque semantic surface
  with a separate focus accent, music-link actions use the tertiary
  cyan/teal role, errors use the paired `errorContainer/onErrorContainer`
  roles, and identity metadata sits on neutral surfaces with distinct
  external/voice/learning accents. Dark and Pearl contrast regressions pin
  text at 4.5:1 and informative icons at 3:1; exact production-card renders
  cover 320/390/768/1440 px plus 320 px at 200% text without clipping. The
  served `main.dart.js` on both Hosting domains is byte-identical to the
  verified release (SHA-256 `1a23f11d8e816a0d`, 6,445,943 bytes). The native
  change still waits for the next coordinated tester build.

- **FIXED AND RELEASED TO WEB/MOBILE BETA 2026-08-28 — Podcast Room behaved like a recolored
  Community Room and ignored parts of its own creation contract.** The screen
  showed description/category where the episode topic belonged, counted every
  stage member as “Speaking,” did not expose show format, guidelines or the
  host's `handRaisingEnabled` choice, and required producers to manage requests
  through the generic People sheet. A role-row event also disconnected audio
  immediately even though the moderation callable already updates LiveKit
  permissions in place. Podcast Studio now has an editorial episode hero,
  accurate On stage / speaking now / Audience metrics, producer desk, desktop
  request queue, listener state, and podcast-specific settings. The current
  request path is the participant row only; Rules refuse a new request when
  the producer closes the queue but always permit the listener to lower an
  existing one. Reconnect is a delayed permission-recovery fallback rather
  than the normal promotion path. Responsive frames were rendered at
  320/390/768/1100/1440 px; inspection caught and fixed a short-desktop stage
  overlap before release. Production Firestore Rules and Hosting were verified
  after deployment; the same client is available as TestFlight build 9 and
  Android Internal Testing build 9. See ADR-120.

- **FIXED IN SOURCE 2026-08-27 — a rapid double tap on More could stack
  sheets or pop two different routes.** The shell previously started a new
  modal for every callback, while a More destination's persistent dock
  unconditionally popped and acted on every tap before the first reverse
  transition had removed its overlay. A burst could therefore leave one More
  sheet hidden under another destination, close the newly opened sheet with a
  stale second callback, or pop the shell itself. More presentation is now
  single-flight through the complete modal transition. Destination dock/rail
  actions commit once, pop once, wait for `Route.completed`, and only then
  invoke the shell action. Regressions cover a same-frame double callback,
  launcher-position retap during entry and the closing-animation boundary.
  **DEPLOYED TO WEB 2026-08-27; NATIVE STORE BUILD PENDING.**

- **FIXED IN SOURCE 2026-08-27 — a Voice Moment could not be heard before it
  was published, and availability was limited to fixed presets.** Review now
  plays, pauses and seeks the temporary native file or browser Blob locally,
  before Firestore reservation or Storage upload. The author chooses any whole
  24–720 hours, 1–30 days, or Until deleted; the 24-hour wire default remains
  compatible. Playback is stopped and disposed before publish, record-again,
  Back or discard, and caption/lifetime lock after a first publish attempt so
  an idempotent retry cannot silently change its contract. Voice replies gain
  preview without their own lifetime selector. **DEPLOYED TO WEB 2026-08-27;
  NATIVE STORE BUILD PENDING.**

- **FIXED IN SOURCE 2026-08-27 — desktop Recent Chats could show a ghost
  initial or turn a real portrait into an unrecognizable color stripe.** The
  desktop card trusted only `conversations.participantPhotoUrls`, so an older
  empty/stale denormalized value disagreed with profile surfaces already
  reading the current public projection. A loaded image was then enlarged
  1.14×, blurred at sigma 12 with low-quality filtering and covered by a scrim
  reaching 98%, erasing identity. Desktop Home now keeps at most three active
  public-profile point listeners for visible chat partners and falls back to
  conversation metadata on load/error. Artwork uses a sharp, face-biased
  full-bleed cover, medium filtering and a lower text scrim; missing/broken
  photos get a deliberate branded accent/monogram. Mobile remains unchanged.
  Widget/integration coverage pins the live-photo repair, image treatment,
  fallback, semantics, keyboard path and 200% layout; a production-theme frame
  was rendered and inspected. **DEPLOYED TO WEB 2026-08-27; NATIVE STORE BUILD
  PENDING.** See ADR-111.

- **FIXED AND DEPLOYED 2026-08-25 — modal sheets drew two detached
  drag handles and offered no obvious universal way to close them.** The app
  theme enabled Material's automatic bottom-sheet handle globally while many
  custom sheets also painted their own bar. On transparent draggable routes,
  notably New Message, the framework bar belonged to the full route at the
  top of the viewport and the custom bar belonged to the visible panel, so one
  sheet looked like two stacked layers. Every production modal route now owns
  exactly one shared chrome contract: one attached cue on phones/tablets, no
  drag cue on pointer-first desktop, and an explicit named Close target of at
  least 44 px everywhere. Scrim, swipe, Back and Escape remain available.
  New Message uses `DraggableScrollableSheet(expand: false)`, and Profile
  Preview now scrolls and stacks its actions when enlarged text or narrow
  geometry makes a fixed row unsafe. See
  [ADR-113](Decisions.md#adr-113-modal-sheets-own-one-chrome-contract-instead-of-inheriting-a-global-drag-handle).

- **FIXED AND DEPLOYED 2026-08-22 — the bottom-nav center logo lost its
  circle.** Per the operator's before/after spec: the 58pt gradient disc,
  border ring and circular BoxShadow are gone; the standalone transparent
  mark renders at the spec's responsive sizes (56/62/66 for 320-/360-/400+),
  floats 12px above the row inside an invisible 72pt tap target, and glows
  along its own silhouette (a blurred tinted copy of the same asset —
  logo-glow.png was rejected: no alpha channel, baked background). The
  live-in-a-room state warms the glow to the live red instead of drawing a
  ring. Pinned by tests that fail on ANY circular ancestor of the mark.

- **FIXED PRE-DEPLOY 2026-08-22 (ADR-103 review) — deleting your own Moment
  failed on any Moment somebody else had engaged with.** The client swept
  the comments/likes subcollections directly, but rules only let each
  engager delete their own docs — permission-denied mid-batch, and under
  the availability amendment deletion is the ONLY exit for a permanent
  Moment. Now routed through the deployed deleteMoment callable (wiring
  pinned by test). Also closed from the same review: own uploading drafts
  offered a Details page that claimed the Moment "reached the end of its
  availability"; the detail header could show "Comments (1)" directly above
  "Be the first to comment." on counter drift; stale 24h-era rules
  comments. OPEN, deferred by the brief: availability cannot be changed
  after publishing; dock "Moments" label ellipsizes at the 320pt floor and
  the feed error state prints a raw exception line (both pre-existing).

- **FIXED AND DEPLOYED 2026-08-22 (ADR-102) — Mute on the live-room bar
  could navigate into the room.** Root cause: the whole bar was one parent
  InkWell(onTap: return-to-room); Flutter forwards taps THROUGH a disabled
  child, and Mute disables briefly on every toggle — so a tap in that
  window (or in inter-icon padding) navigated. Rebuilt as isolated targets;
  a disabled Mute now consumes the tap. Also fixed pre-release from review:
  the mobile expanded-chat sheet outlived a remotely-ended room with a live
  composer; "End room" overclaimed for persistent-room hosts (the server
  ends those on empty roster — label now follows the tap's real effect);
  Expand chat measured 26px tall (now a 44pt floor); tile labels announced
  twice to screen readers; preview overline contrast 4.41:1.

- **OPEN (Voice Moments stories, 2026-08-22)** — known edges shipped with
  ADR-101, deliberately: (1) playback through the row sheet / MomentCard
  does not write the viewed-mark, so a chain fully heard there keeps its
  gradient "unviewed" ring (the story viewer marks correctly); (2) the
  website's `yovoice.app/?moment=` share links outlive the chosen finite
  availability and land on an `isPublished:false/status:'expired'` doc — the
  website's rendering of that shape is unverified; (3)
  `users/{uid}/momentViews` accepts unbounded
  self-writes (same accepted class as the sibling owner-writable
  subcollections).

- **OPEN — Voice Moment expiry is feed visibility, not bearer-media
  revocation.** Published Moments store a Firebase download-token URL. After
  the exact deadline the client hides the Moment and the server refuses new
  engagement; only after the scheduled sweeper retires it do the root and
  authenticated Storage path become private again. A previously copied token
  URL remains usable until explicit deletion/cleanup or token rotation.
  Product copy therefore says how long a Moment stays visible in the feed; it
  does not promise that expiry destroys the bytes.

- **FIXED AND DEPLOYED 2026-08-21 — the redesign's three post-release reviews
  returned FIX_FIRST; every high and medium is closed.** Highlights: the
  podcast HOST's filled column overflowed at 720-850px heights (gate is now
  role-aware: 880 host / 780 guest, pinned by a 1100x800 harness frame whose
  takeException assertion is the regression net); a dormant podcast showed
  "1 Speaking" beside NOT LIVE YET with an unmuted accent mic chip (dormant
  now reports 0 and defaults the placeholder host muted; the dormant host
  dock also no longer offers a red End for a session that does not exist);
  the chat send button and the participants-sheet close had no accessible
  name; the white mic glyph failed non-text contrast on the emerald and gold
  accents (2.0-2.25:1 — glyphs now follow the fill's brightness in the dock
  and the stage chip); '+N' overflow/audience counts and the own-name chat
  color sat under the 4.5:1 small-text bar; dock labels truncated to "Sta…"
  at 200% text (two lines + a caption-only scale cap, full label always in
  Semantics); sidebar nav rows never exposed `selected` to assistive tech
  and sat at 40px (now 44); the bell's "unread" was the rail's one
  unlocalized word; the 768 tablet kept the dead band (fill gate now 700);
  the family hero's lone ↗ became the labeled "Open family space" button;
  chat messages gained real per-message timestamps; the sidebar harness
  rendered under a generic theme (now AppTheme.darkTheme), which immediately
  exposed a real 1px overflow of the Home room card under Inter metrics.

- **OPEN, accessibility (from the 2026-08-21 review) — recorded, not yet
  fixed.** (1) Compact room chat is widget state, not a route: system Back
  exits the whole room instead of closing the chat. (2) Room lifecycle
  transitions (connecting/reconnecting/live/ended) make no polite
  screen-reader announcement; ADR-058's single-LiveRegion constraint applies.
  (3) Sub-44px targets remain: counter pills 34px (informational, but
  tappable in places), reaction chips ~22px. (4) The speaking pulse and
  waveform have no rendered-frame proof (animation; stills cannot show it).

- **FIXED AND DEPLOYED 2026-08-21 (`84ab319`) — three rendering defects found
  only by opening the redesign's PNGs.** (1) The hero's "View club" drew as
  solid blocks: `styleFrom(textStyle:)` replaces a button's text style, so an
  omitted `fontFamily` dropped the control off Inter. (2) The room screenshot
  harness rendered under `ThemeData.dark()` instead of `AppTheme.darkTheme` —
  its PNGs proved nothing about the shipped screens until corrected. (3)
  Letter-fallback avatars stayed app-purple inside emerald/gold/coral rooms
  (stage, header, audience strip, podcast hero credit) — fallback colour now
  derives from the room identity.

- **FIXED AND DEPLOYED 2026-08-20 — family and club rooms were permanently
  undeletable.** The room delete dialog opened for a lounge and its Delete
  button could only display the server refusal "A Club Lounge is deleted
  through the Club lifecycle" — a lifecycle that did not exist anywhere.
  Closed by ADR-096: `deleteClubSelf` plus dialog routing on both delete
  surfaces. Review caught two ship-blockers first: the missing
  `clubs.clubId` COLLECTION_GROUP exemption (production-verified absent;
  emulator-invisible) and a recycled Home menu state that could delete a
  DIFFERENT club than the tile tapped (unkeyed stateful widget in a
  reordering list; regression test fails against the unfixed widget).

- **FIXED AND DEPLOYED 2026-08-20 (`eb51e96`) — muting yourself removed the
  microphone and could never be undone.** `deriveVoiceGrant` and both
  permission-recompute callables folded the participant's OWN `isMuted` into
  LiveKit `canPublish`; the client reads a missing grant as "you are
  audience", hides the mute toggle, and the persisted flag reproduced the trap
  on every re-entry. Same root: self-service joins are rules-pinned to
  `role: 'listener'` while the grant required host-or-speaker, so every
  non-host in a Community/Family room was permanently voiceless. Both fixed —
  see [ADR-094](Decisions.md#adr-094-a-self-mute-is-a-track-state-not-a-permission--and-outside-a-broadcast-everyone-present-may-speak).
  The permission had NO test before this; 7 cases now pin it, 3 failing
  against the old code.

- **FIXED AND DEPLOYED 2026-08-20 (`7938c88`) — Moments counts froze until a
  full page reload.** The feed was a deliberate one-shot `get()`. Counts now
  stream via `watchEngagement()` and patch in place while the board order
  stays frozen per load ([ADR-095](Decisions.md#adr-095-the-moments-board-ranks-deterministically-and-freezes-its-order-while-counts-update-live-in-place)).
  Limitation, stated: live counters cover the 60 most recent published
  Moments.

- **FIXED AND DEPLOYED 2026-08-20 (`7938c88`) — tapping "Your Moment" on Home
  did nothing, and the working part opened the wrong screen.** Only the 66pt
  disc was wrapped in an InkWell — the label and status line under it were
  dead — and the callback pushed the COMMENTS screen, which owns no player,
  so Home was the one surface where a Moment could not be heard. The whole
  tile is now the target and both rails open the playing sheet; mobile's own
  bubble opened the recorder even when a Moment existed and the strip was
  hidden entirely when nobody else had posted.


- **FIXED IN SOURCE 2026-08-20, NOT DEPLOYED AND NOT ROUND-TRIPPED — voice
  had never worked in ANY Community room or lounge.** Reported as "opening a
  Family Room you created yourself and pressing unmute returns *This room is
  not currently live*"; it was not a Family Room bug.
  `createLiveKitToken` refuses a token unless the room says status active and
  `isLive` true. Performing that transition is the **caller's** job, and only
  `enterClubLounge` ever did it — reachable in practice from the Club
  overview alone, because `HomeScreen` is not mounted in the running app (see
  the next entry). `RoomService.startCommunityVoice` had **zero callers**.
  Nine call sites push `RoomEntryScreen`, whose own comment says callers
  joined the room beforehand, and the room screen then asks for a token
  immediately. **Production agreed: 45 rooms, 3 live.** `b0f1062` makes
  entering a room perform the liveness transition for anyone the deployed
  rules would accept, through one coordinator running liveness → roster →
  token. Legacy documents are tolerated deliberately because most production
  rooms are legacy — **25 of 45 carry no `membersCanStartVoice` and 24 have
  neither `roomType` nor `experience`** — so every read defaults rather than
  raising. All 3 club-lounge documents carry `clubId` and `roomKind`, read
  from production, so the operator's own room is genuinely covered. Fixed in
  passing: `CommunityVoiceRoomScreen.dispose` never removed its listener from
  the process-wide `RoomMuteCoordinator` singleton. **UNVERIFIED**: no
  production or emulator round trip, no real LiveKit, no device run — rules
  were read, not executed, and `fake_cloud_firestore` does not evaluate
  rules, so every "the client may start voice" test proves the mirror, not
  the server. Audio quality, reconnect, device routing and the web permission
  path are untouched and unretested. See
  [ADR-088](Decisions.md#adr-088-entering-a-room-performs-the-liveness-transition-through-one-ordered-coordinator-that-mirrors-the-deployed-rule).

- **FIXED AND DEPLOYED 2026-08-20 — a member-started room could stay live
  with nobody in it.** The server dropped `isLive` at zero
  participants **only for lounges**, which was survivable only while nothing
  could set `isLive: true` on an ordinary room. `b0f1062` removed that
  protection: a Community room whose host opted into `membersCanStartVoice`,
  started by a member who then left last, had no exit — `endRoomVoiceSelf` is
  host-only and there was no scheduled sweeper — so it stayed
  `isLive: true, participantCount: 0` and kept advertising itself on
  `watchLivePublicRooms` (Home, Discover) as a live room nobody is in.
  `3ff80e6` fixes it: the last participant out ends the session in **any**
  room, and emptiness is proved from the roster inside the transaction rather
  than from the denormalised `participantCount`
  ([ADR-091](Decisions.md#adr-091-the-roster-not-participantcount-decides-that-a-room-is-empty--and-the-leave-path-asks-the-server-to-prove-it)).
  `executeEndRoomVoice` gained the matching `onlyIfEmpty` re-check.
  **Still open from this cluster**: an ended room still offers Start voice to
  someone who never held a participant row. Tracked as Roadmap item 0p.

- **FIXED AND DEPLOYED 2026-08-20 — a failed join stranded a room live with
  an empty roster, and no client could ever close it.**
  `RoomVoiceEntryCoordinator.enter()` writes liveness first and calls
  `joinRoom` second (it must — `joinRoom` refuses a dormant room and
  `createLiveKitToken` refuses both a dormant room and a caller with no
  participant row). When the join failed the coordinator returned
  `RoomVoiceEntryOutcome.failed` and did **not** call `leaveRoomSelf`: there
  was nothing to leave, the roster row was never written. The room sat
  `isLive: true, participantCount: 0` with an empty `participants`
  subcollection, advertising itself on Home and Discover. A process death
  between the two calls produced the identical document. The state was
  self-healing only if somebody else happened to enter and leave; a room
  nobody revisited stayed a ghost forever, and — because
  `roomVoiceStartAllowed()` requires `isLive == false` — could never be
  *started* again either, only joined. `executeLeaveRoom` deliberately does
  **not** repair it: it returns early without a participant row, and
  extending the repair there would let any signed-in account drop `isLive` on
  a live room during somebody else's start→join window. Closed instead by the
  scheduled `sweepStrandedLiveRoomsSchedule`, which has no caller to
  impersonate
  ([ADR-092](Decisions.md#adr-092-a-scheduled-sweep-closes-the-room-no-client-can-close-and-the-roster-is-still-the-only-thing-that-proves-it-empty)).
  **Still open, and not the same bug**: a client that crashes *while in a
  room* leaves its participant row behind, so the roster is not empty and the
  sweeper correctly skips it — that needs the unexported LiveKit webhook
  (Roadmap item 0h).

- **OPEN, and it is the root cause of two other entries — `HomeScreen` is not
  mounted anywhere in the running app.** `main_shell` holds it at
  `_screens[0]`, but `_slotChildren` special-cases index 0 to
  `MobileHome`/`DesktopHome` and **never reads `_screens[0]`**. So
  `DiscoverClubsRail`, `FromYourClubs` and `LiveNowHero` are finished,
  tested, rendered at three widths and two text scales, and **unreachable by
  any user**. "Discover clubs" exists in exactly one file and that file is
  dead. Placing them into the live compositions is a Home
  information-architecture decision nobody has taken — deliberately not taken
  unilaterally by the implementing session — and the widget APIs make it
  about ten lines per composition. Tracked as Roadmap item 0n.

- **FIXED IN SOURCE 2026-08-19, NOT DEPLOYED — Home's "Discover clubs" rail
  was denied for everyone, and the denial was invisible.** `clubs` carried
  `allow list: if false`, so even a club owner listing their own club was
  refused; the rule's comment claimed no legitimate listing remained, which
  was wrong — the caller had simply been missed. The denial was then
  swallowed by `snapshot.data ?? []` with **no `hasError`**, and the heading
  vanished along with the rail, which is the exact mechanism that hid this
  for the product's life. `01c0ab2` writes the rule entirely in bare field
  accesses so the caller's query must carry three equalities, `155ad61` sends
  them and gives the rail visibly distinct loading, error, empty and
  populated states with `hasError` checked **before** any read of `data`
  (`StreamBuilder` retains data alongside an error) and a Try again that
  re-subscribes (a Firestore subscription is terminated by its first error).
  The same swallowing was fixed where it was actively lying: **"Rooms for
  you" printed "No rooms to show yet, start one and your community will see
  it here" over a permission denial**, and "From your clubs" vanished
  entirely. **The user-visible defect is still not closed** — the rail lives
  in the unmounted `HomeScreen`, so it was broken twice over, independently.
  Several remaining `snapshot.data ?? []` instances are listed in that
  change's report rather than fixed, because each needs a widget's public API
  to grow an error channel.

- **FIXED IN SOURCE 2026-08-19, NOT RENDERED — the Moments screen showed
  engagement it would not let you create, and reported every failure as
  "No Moments yet".** `MomentsScreen` rendered a heart and a like count with
  **no tap target**, while the same feature worked fine on Home; both of its
  `StreamBuilder`s used `snapshot.data ?? []` with no `hasError`, so a
  permission error, a missing index and a still-connecting stream all
  rendered identically; and the screen imported `AppColors` and then
  hardcoded six off-palette colours anyway. All three are addressed in
  `cef05e6`. **UNVERIFIED, and it gates the deploy rather than the commit**:
  nothing has been rendered at any width, the stack interaction has never
  been seen, and the empty state — the state most users on a pre-launch
  product will actually hit — is unconfirmed.

- **A Firestore trap worth carrying forward, found while building the Moments
  feed:** `orderBy('likeCount')` **silently omits every document missing that
  field**. A popularity ordering would therefore have hidden exactly the
  Moments that had never been liked — most of them, on a pre-launch product —
  and the omission would have looked like an empty feed rather than a bug.
  Recorded here because it is the same failure shape as the swallowed
  permission error above: an absence that renders as an empty state.

- **FIXED IN SOURCE 2026-08-18 — the full Profile screen opened on a huge,
  mostly-empty gradient banner with the Back arrow floating alone in the far
  corner.** `ProfileHeader` was a fixed 300–320px banner Stack (38–56% of a
  phone viewport, worse on desktop where the empty gradient stretched across
  the window). It is now a compact, content-sized header: a toolbar row
  (Back when the route can pop — min 44px target, safe-area aware — the
  title, and Edit) aligned with the 18px content gutter inside the same
  bounded frame as the page panels, a slim 104/132px banner accent card
  that keeps the cosmic gradient and any user-uploaded banner, and one
  readable identity block (avatar overlapping the card, name, @username,
  badges, title). The Premium/account-type chips also gained
  Flexible+ellipsis labels, which previously overflowed at 320px width with
  2.0 text scale. Pinned by test/profile_header_compact_test.dart
  (320/390/768/1100/1440, 2.0 text scale at 320 and 1440, header ≤ 30% of a
  390x844 viewport, Back pops) alongside the existing
  test/profile_header_layout_test.dart matrix, and rendered for visual
  proof via test/profile_header_screenshot.dart. A 2026-08-29 density
  follow-up fixes the remaining owner-profile failure visible in production:
  OWNER/VIP/Creator/Premium/title no longer form a four-floor staircase beside
  the avatar. The pseudonym now sits on a compact theme-safe name plate and a
  full-width two-level identity rail separates authority from product and
  achievement labels. Dark/Pearl real-font frames, 320 px/200% text, heading
  semantics, exact two-row owner geometry, Pearl AA contrast and repository
  listener replacement are regression-tested. The follow-up is live on both
  Hosting domains: served `main.dart.js` is byte-identical to the verified
  production build (SHA-256 `a9024e2e02fe0cb3`, 6,444,765 bytes); see ADR-131.

- **FIXED IN SOURCE 2026-08-29 — Light mode painted white-on-white headings,
  stale dark cards and the wrong system-bar icons.** The setting previously
  changed only the root Material theme while Home, dock, modals and most
  journeys still owned dark literals. Pearl now has one semantic palette,
  brightness-aware native chrome, migrated normal-product surfaces and
  explicit immersive-dark voice/media islands. Automated contrast,
  responsive/200% text and real light/dark render checks cover the release;
  see ADR-127.

- **OPEN migration limit — Polish is a bounded Beta, not a claim of complete
  localization.** Framework controls plus migrated navigation,
  authentication and Settings copy switch between English and Polish, while
  product screens with raw English literals remain English. The language
  screen discloses the mixed-language state. A complete translation still
  needs catalog extraction, Polish linguistic QA, long-copy wrapping and
  accessibility verification at every breakpoint.

- **Known platform limitation in the not-yet-deployed source implementation —
  downloaded audio is durable only for as long as this device keeps app/site
  data.** Native files live in the application
  support directory; web copies live in browser Cache Storage, which a browser
  may evict or a user may clear. YO Voice filters a missing object from its
  manifest-backed list and asks for a fresh download; it cannot promise
  permanent browser storage. Server deletion or unpublishing also cannot
  recall a public audio file already downloaded to a user's device. Limits are
  12 MB per item and 250 MB per account/device to bound storage and download
  memory.

- **Not a bug — Devices & sessions does not enumerate or individually revoke
  Firebase logins.** Firebase Auth's Admin SDK supports account-wide refresh-
  token revocation, not a trustworthy device/session list or one-token revoke.
  FCM registrations are push endpoints, not login sessions. The implemented
  control therefore shows the current token session and signs out everywhere;
  it explicitly warns that already-issued stateless ID tokens can continue for
  up to about one hour. See ADR-073 and
  [ACCOUNT_SESSIONS.md](ACCOUNT_SESSIONS.md).

- **Fixed in source (deployment pending): room creation failures and four
  unrelated-looking room interiors.** Podcast creation was denied because
  `showFormat` arrived before its `experience`; Family creation could fail on
  a missing deterministic-root pre-read against the deployed rules; Club
  artwork was uploaded before a canonical Club existed and surfaced a false
  "deploy rules" instruction. Podcast now writes its immutable type
  atomically, Family lets the create batch remain authoritative, and ordinary
  Club media is root-first with a generation-pinned server finalizer. All
  four interiors use the shared stage with purple Community, coral Podcast,
  gold Club and emerald Family identity. Family artwork is intentionally
  disabled: the previous public/token URL model could not revoke access when
  a member left. The fix is verified locally but does not affect production
  until Hosting, Functions and both rulesets are released.

- **Fixed (2026-08-17, this revision): photo and microphone actions in a
  direct chat were placeholders.** Both buttons only displayed “prepared in
  the interface” notices. They now run a real private-media flow: gallery
  selection or a 1–60 second recorder, server reservation, immutable Storage
  upload, canonical message finalization, authenticated image loading and
  voice play/pause/resume. Lost upload/finalize responses reuse the same
  reservation and request id. Independent review also caught and fixed two
  pre-release UI defects: resume restarted audio from zero, and recycled list
  state could briefly show/play the previous message's media.

- **Fixed in code (2026-08-17, this revision; post-deploy iPhone verification
  still required): Safari Voice Moment publish stopped after draft
  reservation but before Storage upload.** Production evidence showed two
  canonical one-second drafts, zero finalizations and zero bucket objects.
  The web path converted a native `MediaRecorder` Blob through
  Blob→ArrayBuffer→Dart bytes→JS bytes. It now gives the native Blob directly
  to Firebase Storage `putBlob`, recovers object generation after an ambiguous
  commit and never deletes a valid object merely because finalization failed.
  The investigation also found a backend bootstrap bug that could replace the
  configured `.firebasestorage.app` bucket with a guessed `.appspot.com`
  bucket; the Admin SDK now respects `FIREBASE_CONFIG` unless an explicit
  bucket override is supplied.

- **Fixed (2026-08-17, `6ef4380`): no production user could record a Voice
  Moment at all.** The recorder called `getTemporaryDirectory()`, which
  `path_provider` does not implement on web, and a broad catch turned the
  `MissingPluginException` into "Could not start recording". Web is the
  only published client, so the entire creator content loop was closed —
  and the error text named nothing that would lead anyone to the platform.
  Fixed by a conditional-export platform seam
  ([ADR-057](Decisions.md#adr-057-voice-moment-recording-splits-only-at-byte-acquisition-and-byte-upload-and-the-server-pins-the-audio-container)).
  **The generalizable part: a catch broad enough to swallow
  `MissingPluginException` converts "this platform is not implemented"
  into "your action failed", which is the one distinction the user needs.**

- **Fixed (2026-08-17, `6ef4380`): the recording waveform was fabricated
  data.** It drew `(index * 17) % 48` — a fixed pattern that moved
  identically whether the microphone heard anything or not — in direct
  violation of this project's no-fake-data rule, and nobody had caught it.
  It now draws the real amplitude stream from the recorder backend.

- **Fixed (2026-08-17, `cefa81a`): a failed publish announced a
  success-sounding line to screen readers.** Flutter web has **no
  per-node `aria-live`** — `LiveRegion` writes into a single shared
  announcement element and clears it after 300 ms, so two live regions
  changing in the same frame overwrite each other. The rule that came out
  of it, and which applies to every screen:
  [ADR-058](Decisions.md#adr-058-one-polite-live-region-per-screen-and-errors-go-out-on-the-assertive-channel).
  **UNVERIFIED with a real screen reader** — no VoiceOver, NVDA or
  TalkBack run has been performed; keyboard tabbing is widget-tested only.

- **Fixed (2026-08-17, `cefa81a`): missing and busy microphones were
  reported as a browser block.** `record_web` collapses every
  `getUserMedia` rejection to a bare `false`, so "no microphone
  connected", "microphone held by another app" and a merely dismissed
  prompt all surfaced as "your browser blocked access" — blaming the user
  for a hardware condition and pointing them at a setting already reading
  Allow. The flow now calls `getUserMedia` directly and maps
  `DOMException.name` onto distinct outcomes with distinct copy
  (`lib/features/moments/data/services/audio_capture/web_microphone_errors.dart`).
  **UNVERIFIED against a real browser refusal** — the mapping is unit-
  tested against synthetic exception names; no real denial, unplugged
  device or device-in-use condition has been reproduced in a browser.

- **Fixed (2026-08-17, `cefa81a`): the recording timer could read
  `0:60 / 1:00`.** The minute component was hard-coded while the seconds
  clamped to 60, and the 60-second auto-stop landed users on exactly that
  frame — so the impossible value was what the last moment of every
  full-length recording showed, not a rare edge.

- **Fixed (2026-08-17, `cefa81a`): the preview harness rendered under
  `ThemeData.dark`, not `AppTheme.darkTheme`.** Screenshots taken through
  it showed neither production typography nor the real input field, so
  earlier visual sign-off on this screen was evidence about the harness.
  The screen also migrated wholesale off raw hex onto `AppColors`, so its
  primary purple finally matches `moments_screen.dart` beside it.
  **Worth remembering: a preview harness that does not install the
  production theme produces screenshots that look like proof and are not.**

- **OPEN release verification (2026-08-17): a real post-deploy iPhone Safari
  publish is still required.** The native-Blob browser seam, native-file seam,
  reservation/finalization retries and Firestore+Storage contracts are now
  automated, but no physical iPhone has exercised the new build against
  production yet. The format decision is described in
  [ADR-057](Decisions.md#adr-057-voice-moment-recording-splits-only-at-byte-acquisition-and-byte-upload-and-the-server-pins-the-audio-container).
  Firefox is
  **known unsupported** and shows an honest unavailable panel — see
  [Roadmap 0i](Roadmap.md#0i-voice-moment-recording-on-firefox-needs-a-coordinated-backend-change).

- **Fixed (2026-08-16): Profile journey metrics expanded into four enormous
  desktop panels.** Their grid height followed the available width, so four
  short values occupied most of a wide screen. `Your YO Voice journey` is now
  one intrinsic-height, four-row list with an icon, label and trailing real
  value. The same production widget is regression-tested at 320, 390, 768,
  1024 and 1440 px without overflow or width-derived height growth.

- **Fixed (2026-08-16): Creator and paid More destinations could look
  available to free accounts.** Creator in Edit profile, Creator Studio and
  More → Clubs now show a lock and contextual Premium explanation unless the
  trusted entitlement grants the matching capability. Navigation preflight,
  a reactive destination guard and the Edit-profile Save recheck all fail
  closed. A visible VIP/Premium badge never authorizes access; existing club
  memberships/invites and Family Rooms remain free.

- **Fixed (2026-08-17): Family Room creation could fail before its batch or
  strand the one deterministic id.** `createFamilyRoom()` probes
  `clubs/family_{uid}` before creating it, but the missing-document rules path
  dereferenced `resource.data`; a first create could therefore stop at its
  initial read. Conversely, a modified client could create only the root and
  consume the account's one canonical id without its membership, channels or
  lounge. The missing self probe is now explicitly allowed, while create is
  accepted only as the complete seven-write graph. Reopen and concurrent
  create attempts converge on the canonical winner before upload cleanup, the
  selected banner is retained, and the success screen opens the actual Family
  Room with Family-specific copy. Emulator, lifecycle and responsive tests
  pin all of these paths.

- **Fixed (2026-08-10): the web app's browser tab showed the YO Voice
  mark inside a solid black square** while the landing page's tab showed
  the clean transparent one. Not a CSS or padding problem — the icon
  files themselves were RealFaviconGenerator output built from a version
  of the artwork with the square baked in, 100% opaque at every size
  (`web/favicon.ico`, `favicon-96x96.png`, `apple-touch-icon.png`,
  `web-app-manifest-*.png`). All of them are now straight downscales of
  the marketing site's canonical transparent icon
  (`yovoice-website/src/app/icon.png`), so both tabs render the same
  mark at the same scale and padding. `favicon.svg` (a 1.6 MB traced
  raster), `favicon.zip`, `favicon.png` and the unreferenced
  `flutter create` `manifest.json` + `icons/Icon-*.png` were deleted with
  them. `test/web_favicon_test.dart` decodes each PNG's corner pixel and
  fails if an opaque one ever comes back; `web/README.md` documents how
  to regenerate. **Needs a Flutter web deploy to reach production** —
  the `?v=2` links and the Hosting `no-cache` header on the icon
  filenames are what stop the cached black-square version from surviving
  it.

- **Fixed (P1, 2026-08-09): room rosters, members and chat messages
  wrote STALE identity (FirebaseAuth displayName/photoURL) instead of
  the canonical profile.** FirebaseAuth's cached identity is not updated
  by profile edits, so a member who changed their name/avatar kept
  appearing with the old one on stage tiles, roster previews and chat
  rows (observed live: CeoGriefer's messages carried a long-replaced
  avatar). Every identity write in `RoomService` (create, join,
  community join, sendRoomMessage) now goes through `_identity()`, which
  reads `users/{uid}` — the avatar system's source of truth — with
  FirebaseAuth only as the unseeded-profile fallback. Verified live in a
  production two-user room: consecutive messages show the stale-then-
  correct avatar (old docs are immutable by design; the server-side
  fan-out repairs rosters on the NEXT profile change, and new writes are
  correct from the start).
- **Fixed (2026-08-09): club lounges stayed `isLive` forever after the
  last member left.** The lounge flow opened the legacy `VoiceCallScreen`,
  whose leave path calls plain `leaveRoom` — `leaveClubLounge` (which
  drops `isLive` at zero participants) had NO callers. Club lounges now
  route through `RoomEntryScreen` into the shared room shell, whose
  leave is lounge-aware. (Part of the board-screen-6 club room rebuild,
  ADR-032.)
- **Fixed (2026-08-09): false "This room has ended" ejection from a
  still-live room.** Observed once: ~80s after creating a community
  room, the host's screen flipped to the ended state with no
  leave/moderation action, while the room stayed live. Root cause:
  both room screens treated "my participant doc is missing from the
  roster snapshot" as proof of removal, but `watchParticipants` is a
  `snapshots()` stream that ALSO emits cache-sourced snapshots (listener
  re-establishment after a network blip, cold-cache re-targeting) — a
  transient snapshot without the own document is indistinguishable at
  the stream level from a moderator removal. The ended state is now
  gated on `RoomService.isParticipantRemovedOnServer()`, an explicit
  `Source.server` read that fails CLOSED (any error ⇒ "still present",
  never an ejection); both screens guard against re-entry while the
  check is in flight. Applies to Community AND Podcast rooms.
  Regression tests: `test/room_removal_confirmation_test.dart`.
  NOTE: the original sighting was never reproduced on demand, so this
  is a root-cause fix for a mechanism that can produce exactly the
  observed symptom, not a confirmed reproduction of that one event.

- **Fixed (P0, 2026-08-08): raw Dart exception text shown to users when
  opening a chat.** Tapping the message icon on a friend could render
  "Dart exception thrown from converted Future…" directly in the UI. Two
  stacked root causes: (1) `openOrCreateConversation`'s
  `transaction.get()` on a not-yet-existing conversation hit a Firestore
  rule that dereferenced `resource.data` on a null resource — a rule
  *evaluation error*, not a permission denial — which Flutter Web boxes
  into that exception text (rules fixed: `get` and `list` split, null
  resource handled by checking the caller's uid inside the deterministic
  conversation id; deployed); (2) 15+ screens rendered `error.toString()`
  directly — all now route through `intentionalOrFriendly()` /
  `friendlyErrorMessage()` (`lib/core/helpers/error_messages.dart`), and
  `auth_provider` stores mapped messages instead of raw exceptions.
  Verified live on iOS Simulator and the deployed web app (first-chat
  bootstrap opens cleanly). Regression tests: `test/error_messages_test.dart`,
  rules suite conversation-bootstrap cases.
- **Superseded by ADR-114 (DEPLOYED 2026-08-25). Fixed (P0,
  2026-08-08): friend-request acceptance never notified the
  original sender.** `notify()`'s dedupe path queried the *recipient's*
  notification subcollection, which rules forbid — the permission-denied
  silently aborted every deduped notify, so the `friendAccepted`
  notification was never written. Rewritten to use deterministic doc IDs
  (the dedupe key IS the doc id; a duplicate becomes a forbidden
  cross-user update, caught and treated as already-sent — zero extra
  reads). Acceptance also retires the acceptor's own `friendRequest`
  notification via `markMatchingRead()`, failures are logged instead of
  swallowed, and decline/cancel stay intentionally silent. Verified by
  emulator rules tests and `test/friend_accept_notification_test.dart`;
  a live two-account UI check needs a second signed-in session
  (UNVERIFIED live — no second test-account session was available to
  this session's tooling). This paragraph records the historical repair; the
  current source no longer uses client `notify()`/`markMatchingRead()` for the
  social lifecycle and instead binds each event to a server-owned generation.
- **Fixed (P0, 2026-08-08): bottom navigation disappeared on More
  destinations.** Deterministic, not random: `_openMoreDestination`
  pushed full-screen routes that covered the shell. Main More
  destinations now keep the persistent bar via `MoreDestinationHost`
  (single source of truth re-hosting the shell's own `_BottomNavigation`;
  bar taps pop back to the shell first). Deep detail flows still cover
  the bar by design. See
  [ADR-026](Decisions.md#adr-026-more-destinations-re-host-the-shells-bottom-navigation-amends-adr-019).
  Verified live on iOS (Settings, Friends) and deployed web
  (Notification preferences). Regression tests:
  `test/more_destination_nav_test.dart`.
- **Fixed: Settings screen was a blank grey panel on Flutter Web.**
  `settings_screen.dart` imported `dart:io`'s `Platform` and called
  `Platform.isIOS` unconditionally inside `_deviceLabel()`, which is
  called directly from `build()`. On web, `dart:io`'s `Platform` is a
  stub that throws `Unsupported operation: Platform._operatingSystem` on
  any access — crashing the whole screen's build and leaving Flutter's
  default grey `ErrorWidget` background with no visible error text (the
  "large white/grey empty area" report). Fixed by returning a `kIsWeb`
  branch before ever touching `Platform`. Verified server-side: the
  deployed `main.dart.js` was confirmed via direct `curl` (bypassing any
  browser cache) to contain the fix and no longer reference the crashing
  path. **Not re-verified as a live screenshot** — every standard
  cache-bypass technique (`Cache-Control: no-cache`, `Clear-Site-Data`,
  full browser-process restart, brand-new tabs, query-string busting on
  both `main.dart.js` and `flutter_bootstrap.js`, an isolated iframe
  loaded entirely from `no-store` fetches) still rendered stale,
  pre-fix content in this session's sandboxed browser tool — strong
  evidence of a caching layer in that tool's own network path, not an
  app defect, but it means the fix is server-verified, not yet
  eyes-verified. Needs a real end-user browser (or a future session with
  working tooling) to close the loop.
- **Fixed (root cause): Firebase Hosting served `main.dart.js` (and other
  build output) with `Cache-Control: max-age=3600`, and Flutter's default
  web build doesn't content-hash that filename.** This meant any browser
  that had visited before a deploy could keep running the *previous*
  build's JS for up to an hour after a fix shipped — exactly the kind of
  gap that made the Settings fix above hard to verify live. Added
  explicit `Cache-Control: no-cache` header rules for `**/*.@(js|json|wasm)`
  and `/index.html` in `firebase.json`, forcing browsers to revalidate
  (via ETag) on every load instead of trusting a stale copy.
- **Fixed: profile avatar (and, incidentally, display name) silently
  reverted to blank/placeholder minutes after being set correctly.**
  `PresenceService.setOnline()` (`lib/core/presence/presence_service.dart`)
  runs unconditionally every 45 seconds and on every app foreground, and
  was writing `photoUrl: user.photoURL` (FirebaseAuth's own, separate,
  often-null `currentUser.photoURL`) into the *same* Firestore
  `users/{uid}.photoUrl` field that `ProfileService` treats as the
  authoritative profile photo. Any time those two diverged, the next
  heartbeat clobbered the real value. Reproduced directly: set
  `photoUrl` via the Storage/Firestore REST API on the shared diagnostic
  account, confirmed it read back correctly, then watched it revert to
  `null` on its own within one heartbeat interval while a session was
  open. Fixed by stripping `displayName`/`email`/`photoUrl` out of the
  presence write entirely — presence now only ever touches
  `isOnline`/`lastSeen`/`presenceUpdatedAt`. The one legitimate reason
  those fields were being seeded there (bootstrapping a brand-new user's
  profile doc before they ever open Profile) is now handled once, at
  sign-in, by `ProfileService.ensureProfile()` called from
  `AuthGate`'s `_AuthenticatedEntryState.initState()` — already
  idempotent (no-ops if the doc exists), so this is a straight move, not
  new behavior. Also fixed the *display* side of the same class of bug in
  `home_screen.dart`: its header read `FirebaseAuth.instance.currentUser`
  directly (a non-reactive snapshot, and the same wrong source of truth)
  instead of the Firestore profile stream every other screen
  (Settings, Creator Studio) already uses correctly — now wired to
  `ProfileService.watchCurrentProfile()` like the rest. **Verified**:
  root cause reproduced live via REST before the fix; the fix itself is
  a small, mechanical, `flutter analyze`-clean change reviewed against
  the same reactive pattern already proven correct elsewhere in the
  app. **Not yet re-confirmed with a live client running the patched
  build** — blocked by the same Web caching-tool issue above, and by the
  iOS Simulator being unresponsive to input in this session (reboot,
  relaunch, and home+relaunch recovery attempts were all tried and all
  failed identically).
- **Not a bug, confirmed by direct check: profile banner (`bannerUrl`)
  was never affected by the avatar issue above.** `PresenceService`
  never touched `bannerUrl`, and `profile_screen.dart` already reads
  `profile.bannerUrl` correctly from the same reactive stream. Confirmed
  directly: set both `photoUrl` and `bannerUrl` via REST on the
  diagnostic account at the same time — after the same wait,
  `bannerUrl` was untouched while `photoUrl` had been wiped again (by a
  still-open browser tab running the *old*, pre-fix code) — a clean,
  direct confirmation that the two fields' behavior genuinely differs
  for the reason described above, not a shared/systemic Firestore issue.
- **Fixed: white panel flashing behind sheet transitions (e.g. New Chat)
  on devices with the OS set to Light mode.** Root cause was native
  Android/iOS window chrome following the *system* light/dark setting
  instead of the app's own dark-only theme — not a bug in the Dart-side
  sheet code. See
  [ADR-016](Decisions.md#adr-016-native-android-and-ios-window-chrome-is-pinned-dark-not-os-controlled)
  for the full root cause and fix.
- **Fixed: the New message sheet showed a large light-grey panel filling
  everything below the search field (Flutter Web).** A *separate* bug from
  the native window-chrome one above, which stays valid — this one is
  pure Dart and reproduces on every platform.
  `FriendService.watchFriends()` returned a plain
  `StreamController<List<FriendUser>>()`, i.e. a **single-subscription**
  stream. `MessagesScreen` builds that stream once in `initState` and
  hands the same instance to two widgets: `_FriendsRow` (always mounted,
  subscribes first) and `NewMessageSheet`. Opening the sheet therefore
  made a second `listen()` call, which throws
  `Bad state: Stream has already been listened to.` inside the sheet's
  `StreamBuilder`. Flutter replaced that subtree with the default
  `ErrorWidget` — red with text in debug, an **unlabelled light-grey
  rectangle in release** — occupying exactly the `Expanded` region below
  the search field, which is why the handle/title/search stayed correctly
  dark. Same failure signature as the Settings grey-panel bug above: an
  exception during build, rendered as a blank grey box in a release web
  build. Fixed by making `watchFriends()` return a broadcast stream that
  also replays its last value to late subscribers (via `Stream.multi`) —
  replay matters because the sheet subscribes *after* the first emission
  and would otherwise sit on a spinner. **Verified**: reproduced live in
  Flutter Web with a debug build via `lib/dev/new_message_preview.dart`
  (screenshot showed the panel and the "already been listened to"
  message), then re-checked after the fix with the sheet rendering fully
  dark end to end. Regression covered by `test/new_message_sheet_test.dart`.
- **Fixed: the New message sheet painted its surface with a bare
  `Container`.** `showModalBottomSheet` is invoked with
  `backgroundColor: Colors.transparent`, so that `Container` *was* the
  sheet's surface — but it sat between the tiles and the nearest
  `Material`, so every `ListTile` background and ink splash was painted
  behind it and never seen. Flutter's own assertion ("ListTile background
  color or ink splashes may be invisible") fired in debug. The sheet now
  owns a `Material`.
- **Fixed: a failed friends/conversations query in the New message sheet
  rendered as "You're all caught up".** The sheet read `snapshot.data`
  but never checked `hasError`, so a permission failure was
  indistinguishable from having no friends. There is now a distinct dark
  error state.
- **Fixed: a newly chosen avatar/banner appeared to do nothing in Edit
  profile.** Not a caching bug: `ProfileService` already uploads to a
  timestamped path (`avatar_<millis>.jpg`), so every upload produces a
  genuinely new download URL and neither the browser HTTP cache nor
  Flutter's `ImageCache` can serve a stale image. The real causes were
  in the UI: (1) `EditProfileScreen` rendered **no avatar or banner
  preview at all** — just two "Change avatar/Change banner" buttons — so
  after a successful upload nothing on screen could change; and (2) it
  received a `UserProfile` as a plain constructor argument and threw away
  the URL returned by `pickAndUploadImage`, so its own copy of the
  profile was stale the moment the upload finished. Edit profile now
  shows a live preview of both images, and a freshly picked file renders
  instantly from memory (`MemoryImage`) with no upload or network round
  trip. `ProfileScreen` was already correct — it reads
  `watchCurrentProfile()` — so it updates as soon as Firestore does.
- **Changed: avatar/banner now commit on Save instead of uploading
  immediately.** Previously images were written to Storage and Firestore
  the instant they were picked, while every text field waited for Save —
  so pressing Back after choosing an avatar still changed it remotely,
  and a discarded pick left an orphaned Storage object behind. Picks are
  now held in memory as pending changes and uploaded by `_save()`, which
  gives the screen one consistent rule and means nothing reaches Storage
  unless the user commits.
- **Known, not yet fixed: other people still see your old avatar.** The
  photo URL is denormalised into `conversations.participantPhotoUrls`,
  `users/{uid}/friends/*`, room participants and club members, each
  written from `FirebaseAuth.currentUser.photoURL` at the time that
  document was created. Changing your profile photo updates
  `users/{uid}.photoUrl` but nothing back-fills those copies, so your
  avatar stays stale in other users' Chats/Friends/Rooms lists (and in
  your own conversation list). Needs a fan-out — realistically a Cloud
  Function on `users/{uid}` write — plus a one-off backfill. Also
  `home_screen.dart:568` still reads `FirebaseAuth.instance.currentUser
  ?.photoURL` directly, which is a non-reactive snapshot and will not
  rebuild when the avatar changes.
- **Fixed: Broadcast Room listeners were left stranded in a dead room.**
  When a host ended or deleted a Broadcast Room, every participant doc
  (including every listener's own) was deleted server-side, but the
  screen only watched the participants list, not the room's own status —
  so listeners just saw the stage go empty with no explanation and no
  way back except manually tapping back. Now detected and the listener is
  shown "This room has ended." and navigated out automatically. See
  `broadcast_room_screen.dart`'s `_handleParticipantsUpdate`.
  `community_voice_room_screen.dart` already had equivalent handling
  (`_handleParticipantState`) before this pass; `podcast_room_screen.dart`
  didn't get this fix — see the dead-code note below.
- **Fixed: "Sign up" / "Log in" cross-links on the auth screens had a
  near-zero tap target.** Both `login_screen.dart` and
  `register_screen.dart` explicitly shrank the `TextButton`'s hit box to
  the bare text glyphs (`padding: EdgeInsets.zero` +
  `minimumSize: Size.zero` + `tapTargetSize: MaterialTapTargetSize.shrinkWrap`),
  well under Apple/Material's 44/48pt minimum touch target — a tap that
  looked like it landed on the text would frequently miss. Removed the
  override so the theme's default `TextButton` sizing applies (the shared
  `textButtonTheme` doesn't set its own padding/minimumSize, so this falls
  through to Flutter's own default, already comfortably tappable).
  Regression-guarded by `test/auth_link_tap_target_test.dart`, which taps
  each link via `find.text(...)` (real hit-testing, not a coordinate
  guess) and asserts the resulting navigation.
- **Fixed: every "More" menu destination had doubled or broken chrome.**
  Reported as "Settings is broken — white background, content missing";
  the actual cause was every one of the seven More destinations being
  wrapped in a second, redundant `Scaffold`+`AppBar` on top of each
  screen's own. Settings only doubled its title text; Achievements showed
  two full stacked Material app bars. See
  [ADR-019](Decisions.md#adr-019-more-menu-destinations-own-their-full-chrome-no-wrapper-scaffold).

## Test reliability

- **FIXED (2026-08-19) — `firestore-tests/storage.test.js` was green only
  on a brand-new emulator; a second run against the same instance reported
  five failures that were not rules regressions.** `active owner can create a
  JPEG profile image`, `unverified active owner can upload during onboarding`,
  `legacy exact M4A MIME remains compatible for replies`, `reserved direct
  image uploads with exact identity` and `reserved direct voice media is
  private and enforces the 12 MB cap` all came back `storage/unauthorized` on
  re-run. (It was three failures when first reported; the direct-media cases
  added two more leaking create-only paths, so this was getting worse, not
  settling.)

  Root cause: **`clearStorage()` from `@firebase/rules-unit-testing` removed
  nothing at all here.** It deletes only the `items` a single `listAll()`
  returns at the bucket root, and `listAll()` does not recurse — every object
  this suite writes lives under a prefix (`users/`, `clubs/`,
  `message_attachments/`, `voice_replies/`, …), so every leftover survived it,
  confirmed by listing the bucket immediately after the call. The failing
  cases are the ones whose objects the suite never deletes and whose paths are
  create-only (`allow create: if resource == null`), so the rules correctly
  denied the re-upload. Leftovers on the Club path did not fail, because that
  path permits a replacement — which is why only some of them went red.

  Fixed by walking the prefix tree and deleting every object, then asserting
  the bucket is actually empty so a future unreachable path fails loudly up
  front instead of posing as an authorization regression. No assertion was
  weakened and `storage.rules` was not touched; proven with **three
  consecutive 52/0 runs against one emulator**, immediately after the same
  emulator had produced 47/5 from the unfixed suite. This mattered because red
  lines on an ordinary re-run train people to discount failures in the one
  suite that gates a `storage.rules` deploy.

  `family-media.test.js` calls the same no-op `clearStorage()` but is not
  affected: it seeds its objects through `withSecurityRulesDisabled`, which
  overwrites regardless, and its rules deny all client writes.

  A further failure (`Voice Moment requires exact filename, audio MIME and
  size bounds`, reported as `storage/unknown` rather than a denial) was
  observed once before the fix and is **not explained by leftover state** —
  that object is deleted by the suite itself, and `assertFails` rejects any
  non-permission error, so a transient transport/emulator error surfaces as a
  failure. It did not reproduce in 55 targeted attempts of that exact oversize
  upload (25 sequential, 30 at 6-way concurrency, all clean
  `storage/unauthorized`) nor in any full run. Treat a lone `storage/unknown`
  as transient and re-run; if it becomes frequent, suspect emulator contention
  (e.g. another suite sharing the hub) rather than a rule.

- **Open (2026-08-09): `profile_save_e2e_test.dart`'s "full save
  pipeline" case is FLAKY under full-suite parallelism.** It passes
  reliably in isolation (`flutter test test/profile_save_e2e_test.dart`)
  and passes on most full-suite runs, but failed twice in a row during
  the 2026-08-09 session and then passed again with the identical tree —
  so it is timing/scheduling sensitive, not a real regression, and NOT
  caused by the room-eviction change it appeared alongside (verified by
  running the same tree both ways). Worth stabilizing before it erodes
  trust in a red CI run: the likely culprit is the test's real-async
  Storage/Firestore fakes racing the shared-profile stream assertion.

- **FIXED (2026-08-16, `38b29f7`) — CI was red on three consecutive
  pushes, including a docs-only commit.** `legacy_identity_scrub.test.js`
  asserted an absolute document count (`scanned === 1`) while
  `scrubIdentitySnapshots` scans the whole `conversations` collection and
  takes no uid or prefix scope, so it could not isolate itself the way its
  own `wipe()` isolates its fixtures. `node --test test/*.test.js` runs
  files **concurrently against one emulator**, so a conversation seeded by
  any other file was counted here too, and the assertion held or broke
  purely on interleaving — green locally, red on the runner. 509 of 510
  passed every time, which is what gave it away. Fixed by measuring the
  **delta** around this test's own write: exactly as strong an assertion
  (one document scanned, one scrub planned, nothing written), independent
  of what else exists. **Generalizable rule**: in the Functions suite,
  never assert an absolute count over a collection your file does not
  exclusively own.

## Code quality / consolidation

- **Dead rule code in `firestore.rules`, left over from the `952d8e4`
  eviction removal — and it reads as though a capability exists that does
  not.** `roomParticipantLeaveRootExists()` has no callers, and
  `roomParticipantLeaveTransitionAllowed()` is unreachable because
  `participants` delete is `if false`. Flagged 2026-08-17, deliberately
  not removed in a security commit. **The hazard is the reading, not the
  bytes**: the ternary that calls the second helper looks like members can
  leave a voice room through rules, and they cannot — so anyone reasoning
  about the leave path from these lines reasons about a path that is off.
  Remove them in a change of their own, with the emulator suite re-run.

- **`_publishRecordedMomentLegacy` writes a 14-key document where
  `validateMoment()` requires exactly 20.** The callable fails `data-loss`
  on a mismatch, so any moment created through this fallback would break
  every later callable operating on it. Latent only because Stage B is
  deployed and nothing reaches the path today. It needs a deliberate
  decision — delete it, or write the canonical shape — not continued
  coexistence. Tracked as
  [Roadmap 0j](Roadmap.md#0j-decide-the-fate-of-_publishrecordedmomentlegacy).

- **`RoomScreen` (`lib/features/rooms/presentation/screens/room_screen.dart`,
  ~1,164 lines) and `PodcastRoomScreen`
  (`.../screens/podcast_room_screen.dart`, ~987 lines) are dead code.**
  Confirmed by tracing actual navigation, not by filename: `RoomEntryScreen`
  only routes to `BroadcastRoomScreen` or `CommunityRoomLobbyScreen`, and
  legacy `experience: podcast` Firestore values are mapped to `broadcast`
  before that routing decision happens (see
  [ADR-001](Decisions.md#adr-001-legacy-podcast-room-experience-stays-supported)) —
  so neither screen class is reachable from anywhere in the app. Not
  deleted per this project's rule against removing functionality without
  being explicitly asked (see [CLAUDE.md](../CLAUDE.md)) — flagging for a
  deliberate decision instead. See
  [ADR-018](Decisions.md#adr-018-per-screen-firestore-streams-are-created-once-in-initstate-never-inline-in-build)
  for how this was found.
- **Several screens create a fresh `Stream` inline inside `build()`**
  instead of once in `initState()`, causing `StreamBuilder` to tear down
  and re-subscribe its Firestore listener on every rebuild. Fixed in the
  four highest-traffic instances
  (`broadcast_room_screen.dart`, `community_voice_room_screen.dart`,
  `podcast_room_screen.dart`, `club_overview_screen.dart`) — see
  [ADR-018](Decisions.md#adr-018-per-screen-firestore-streams-are-created-once-in-initstate-never-inline-in-build).
  A handful of lower-traffic instances remain
  (`friends_screen.dart`, `friend_profile_screen.dart`, an invite sheet in
  `club_overview_screen.dart`) — lower severity since they don't sit
  behind a frequently-rebuilding `build()`, but worth a future pass.
- **RESOLVED IN CURRENT SOURCE 2026-08-28 — two parallel hand-raise APIs no
  longer write two schemas.** Podcast Studio, Participants and the deprecated
  `RoomExperienceService` compatibility methods all read/write
  `rooms/{roomId}/participants/{uid}.isHandRaised`. The separate
  `handRequests` Rules contract remains temporarily readable/writable only so
  an already-installed older client is not broken without a minimum-version
  migration; current source neither creates nor watches those documents. See
  ADR-120.
- **RESOLVED IN CURRENT SOURCE 2026-08-29 — normal product journeys now use
  the semantic theme system.** Remaining inline dark colour systems belong to
  documented immersive voice/media surfaces or specialized workbenches; new
  brightness-dependent UI must use `AppPalette`/`ColorScheme` (ADR-127).
- **CORRECTED 2026-08-16 — this entry said "Cloud Functions still have
  zero automated test coverage."** That was false, and had been for some
  time: `functions/test/` holds **510 tests across 82 suites** in 45
  files, running against the Auth + Firestore emulators and gating the
  Hosting release in CI. Current counts live in one place now —
  [TESTING.md](TESTING.md#current-counts) — so this file should
  reference them rather than restate them.

  What remains true, and is the useful part of the original entry:
  coverage is uneven, not absent. Many older functions have no focused
  tests. **No suite anywhere proves anything about production** — they all
  run against emulators or fakes, and the emulator does not require
  composite indexes, which is precisely how a broken `expirePremiumIdentity`
  survived 510 green tests for the entire life of the Premium feature.
  Broad cross-service integration and real store billing still have no
  executable path. A green suite is strong evidence for the cases it
  names, not blanket proof for every feature — and never evidence about
  what is deployed.

## Infrastructure

- **RESOLVED 2026-08-20 — `firestore.indexes.json` had drifted BEHIND
  production: the deployed `clubs.clubId` single-field exemption was never
  backported, so the next index deploy would have deleted it and bricked
  club deletion.** `adminDeleteClub` sweeps the `users/{uid}/clubs`
  projections with `db.collectionGroup("clubs").where("clubId", "==",
  clubId)` (`functions/admin/clubs.js:1005`), which requires a
  COLLECTION_GROUP-scope exemption on `clubs.clubId`. The repo file listed
  overrides for `rooms.roomId`, `participants.userId`, `roomMembers.userId`
  and `invites.inviteeId` but not this one; production (checked via
  `firebase firestore:indexes`, 2026-08-20) already HAS it — evidently
  console-created and never committed. Club deletion therefore works today,
  but `firebase deploy --only firestore:indexes` offers to delete live
  indexes the file omits (`--force` deletes silently), after which the
  sweep's `.get()` would throw `FAILED_PRECONDITION` after
  `deletionInProgress: true` is set — a retryable state no retry could ever
  complete. Exemption backported; the full live config was diffed against
  the file and now matches exactly. The emulator does not enforce
  single-field exemptions, so no test could see any of this. See
  [ADR-096](Decisions.md#adr-096-firestoreindexesjson-mirrors-the-deployed-index-state-exactly--a-console-created-exemption-is-backported-to-the-repo-the-day-it-is-found).
- **OPEN — App Store/Google Play Premium checkout is not operational.** The
  entitlement model, admin grant and access gates exist, but no IAP client or
  store receipt-verification adapter is configured; `verifyPurchase`
  deliberately declines rather than trusting the device. Only the guarded
  protected-owner-only `adminSetPremiumEntitlements` callable can grant working
  Premium today. See
  [Roadmap.md](Roadmap.md#0e-premium-billing-adapters).
- **RESOLVED 2026-08-16 — `app.yovoice.app` is LIVE.** This entry said
  "DNS record not added yet … needs Cloudflare access only the domain
  owner has" and had been stale. The CNAME resolves to
  `yovoice-ec54a.web.app` and HTTPS returns 200; the Flutter web client
  was fetched from that host and fingerprinted (5,139,256 bytes,
  containing `publicProfiles`, `searchPublicProfiles`,
  `selectMyAchievementTitle`).

  **Remaining, and UNVERIFIED**: `NEXT_PUBLIC_APP_URL` must be flipped to
  `https://app.yovoice.app` in all three of the website repo's Vercel
  environments (production, preview, development) and the redirect
  verified end-to-end. That lives in the other repo and could not be
  checked from here — assume the website still points at the default
  `web.app` domain until someone confirms otherwise.
- **FIXED AND DEPLOYED 2026-08-16 — Premium never expired for anyone.**
  The deployed scheduled `expirePremiumIdentity` sweep queries
  `entitlements where isPremium == true and currentPeriodEnd < now`
  (`functions/premium/entitlements.js:163`), which requires a composite
  index on `entitlements(isPremium, currentPeriodEnd)`. The index was
  committed but had never been deployed, so every run threw
  `FAILED_PRECONDITION` and expired entitlements were never revoked. The
  function looked healthy in `functions:list` and the Functions suite was
  green throughout, because the emulator does not require composite
  indexes — the failure existed only in the scheduler logs. Index deployed
  2026-08-16. **UNVERIFIED**: no successful run has yet been observed in
  Console → Functions → Logs; check that before calling Premium expiry
  proven.
- **OPEN, deliberate — `publishPublicStatsSchedule` is committed
  (`cb4651a`) but NOT deployed.** Three preconditions first: `publicStats/live`
  needs the project's first `allow read: if true` rule (with its own ADR and
  emulator coverage), the live count needs a `COLLECTION_GROUP` index on
  `rooms.expiresAt`, and the data source is known to be wrong —
  `activeVoiceSessions.expiresAt` is a token-issuance TTL that is never
  renewed and never cleaned up on a crash, so counting by freshness
  reports zero for a full room while counting without it reports ghosts
  forever. Do not sweep it into a blanket `--only functions` deploy. See
  [DEPLOYMENT.md](DEPLOYMENT.md#deliberately-held-back-publishpublicstatsschedule).
- **Fixed: `flutter build apk` failed outright** (missing core library
  desugaring for `flutter_local_notifications`, then a follow-on AAPT2
  drawable-resource error). See
  [ADR-017](Decisions.md#adr-017-android-build-fixes-core-library-desugaring-and-drawable-resource-references).
  Nothing in CI builds Android (only the Flutter web target does — see
  [DEPLOYMENT.md](DEPLOYMENT.md)), so a regression like this has no way
  to surface on its own; worth keeping in mind next time something in
  `android/` changes.
- **Android build is verified; Android runtime is not.** No emulator
  (AVD) or physical device was available in the session that fixed the
  above — `flutter build apk --debug` succeeds and produces a real APK,
  but nobody has actually run this build and watched it boot. Needs a
  session with an Android emulator/device attached to close the loop.
- **Fixed (root cause, demonstrated): a saved avatar was wiped seconds
  later by the friends stream.** `FriendService.ensureUserDocument()`
  merged `'photoUrl': user.photoURL` — FirebaseAuth's own, separate,
  frequently-null value — into `users/{uid}.photoUrl`, the exact field
  `ProfileService` owns. It runs from `watchFriends()`'s `onListen`, so
  every Home mount, every Messages mount and every browser refresh
  overwrote the freshly uploaded avatar with whatever Auth happened to
  hold: `null` for email/password accounts (→ the purple placeholder with
  the person icon on Home) or a stale Google avatar for Google accounts.
  This is the third instance of the same defect — `PresenceService` had
  it, `home_screen` read the same wrong source — and it explains why the
  earlier "Edit profile has no preview" fix, though real, did not make
  the avatar appear. Proven, not inferred: `test/profile_photo_source_of_
  truth_test.dart` fails with `Actual: https://i.stack.imgur.com/34AD2.jpg`
  when the old line is restored and passes with it removed.
  `ensureUserDocument()` now writes only `uid`/`isOnline`/`lastSeen`.
- **Fixed: removing that write exposed an ordering hazard in
  `ProfileService.ensureProfile()`.** It bailed out on
  `if (existing.exists) return;`, but `ensureUserDocument()` (and
  presence) legitimately *create* `users/{uid}` with presence-only
  fields — so a friends stream that started before AuthGate's
  `ensureProfile()` left a brand-new account permanently without a
  displayName. It now keys off whether `displayName` is actually present,
  seeds the Auth avatar only when the profile has none, and writes the
  zeroed counters only on true first creation so it can never reset
  progress.
- **Fixed: Home mixed two profile-image sources.** The header read
  `profile?.photoUrl ?? FirebaseAuth.currentUser?.photoURL` and the "Your
  Moment" bubble read `currentUser?.photoURL` directly — a non-reactive
  store that never updates after an avatar change. Both now read the
  shared profile stream, so Home, Profile, Settings and Creator Studio
  cannot disagree.
- **Added: `ProfileService.watchCurrentProfile()` is now one shared,
  replayed broadcast stream cached per uid**, so every screen observes the
  same value from one Firestore listener, and a screen opened after the
  first emission renders immediately instead of flashing a placeholder.
  Cleared on sign-out via `resetCurrentProfileCache()`.
- **PARTIALLY RELEASED 2026-08-27 — password reset / email verification links still
  dump production users on Firebase's generic white `__/auth/action` page.**
  Not a bug in
  ActionCodeSettings — its `url` only ever becomes the post-action
  continueUrl (established empirically in a prior session). The user-facing
  handler simply didn't exist for reset (`/reset-password` on the website
  was an empty directory) and the console's action URL was never
  customized. Source now provides a tested `yovoice.app/auth/action`
  dispatcher → branded `/reset-password`, `/verify-email`, `/recover-email`
  and `/revert-second-factor` pages; full reset
  lifecycle verified against the Firebase Auth emulator (old password
  rejected, new accepted, code replay rejected, reused link shows a
  branded error, hostile continueUrl stripped by allowlist). Token routes are
  private/no-store, no-referrer and noindex; the MFA recovery path validates
  the exact operation and requires a deliberate click so a mail scanner cannot
  remove an authenticator. Website commit `ce11602` is live and all five token
  routes pass production probes. The narrow Identity Toolkit callback/template
  request was rejected with HTTP 400 `EMAIL_TEMPLATE_UPDATE_NOT_ALLOWED`, and
  immediate read-back confirmed no targeted field changed; production
  `callbackUri` therefore remains the Firebase handler. Do not broaden the
  update mask. The retained leaf scope, read-back and rollback gates are
  documented in docs/email-templates/README.md. See ADR-022.
- **Fixed: login's "Forgot password?" required the login form's email and
  only answered with a SnackBar.** It now opens a dedicated responsive
  reset-password route with its own email form, then a neutral "Check your
  inbox" result. `user-not-found` deliberately takes the same path as success
  so the form cannot probe which emails have accounts.
- **Fixed: user-facing copy wrote the brand as "YoVoice" in ~30 strings**
  (share messages, fallback display names, settings copy). All user-facing
  occurrences are now "YO Voice"; code identifiers (`YoVoiceApp`) and
  URLs/package ids unchanged.
- **Fixed (fourth and final clobber writer): registration merged
  `photoUrl: null` into `users/{uid}`.**
  `FirestoreService.createUserProfile()` — called from email/password
  registration and first-time Google sign-in — wrote the avatar field as
  a literal null with merge:true. Mostly invisible at account creation,
  but it made the field's ownership ambiguous and could null a Google
  avatar seeded in the same sign-in flow. It no longer touches photoUrl
  (regression-pinned in test/profile_photo_source_of_truth_test.dart);
  its dead updatePhotoUrl/updateDisplayName siblings were deleted.
- **Fixed: other people finally see profile changes.** New Cloud
  Function `onProfileIdentityChanged` fans photoUrl/displayName changes
  out to conversations, club member docs and voice_moments (see
  ADR-023). NOT yet deployed — requires `firebase deploy --only
  functions`, and until then other users' Chats lists keep showing the
  avatar from when the conversation was created.
- **Fixed: Edit profile was enormous on desktop.** The screen was an
  unconstrained full-width ListView, so its AspectRatio(16:9) banner
  preview scaled with the window — ~810px tall at 1440px wide. The form
  is now centered and capped at 640px (preview ≤ ~275px tall at 21:9),
  and the Profile header renders the banner as a centered rounded cover
  card above 900px instead of a full-bleed stretch. Verified visually
  via lib/dev/profile_preview.dart at 390 and 1024/1440-class widths;
  mobile keeps the previous full-bleed composition.
- **Fixed: broken image URLs were indistinguishable from "no image".**
  CircleAvatar(backgroundImage:) and DecorationImage swallow load errors
  silently. Shared UserAvatar/ProfileBanner widgets now render explicit
  fallbacks (initials / brand gradient) via errorBuilder, and replaced
  Storage objects are cleaned up after a successful save instead of
  orphaning forever.
- **Fixed (regression from 82c1746, mine): Profile avatar clipped at the
  top of the page on mobile.** The header refactor returned the inner
  Stack (title row + identity row) as a NON-positioned child of the
  header's outer Stack on <900px widths. A non-positioned Stack child
  sizes to its own children, so the inner Stack collapsed to the title
  row's height and the identity row's `bottom: 20` anchored to that
  collapsed ~70px box at the top — avatar drawn above the viewport, name
  at the top, dead space below. The width-matrix test written for the fix
  then caught the SAME collapse on ≥900px widths (avatar 76px above the
  header): ConstrainedBox capped width but left height loose. Both
  branches now wrap the content in Positioned.fill (+SizedBox.expand on
  the wide branch). The header was also extracted to a public
  ProfileHeader widget rendered by the screen, the dev harness AND
  test/profile_header_layout_test.dart (8 sizes: 320/375/390/393/430/
  768/1024/1440 — avatar-fully-inside asserted at each), because the
  regression shipped precisely while the harness mirrored the layout
  instead of importing it.
- **Proven end to end (not merely reviewed): the profile media save
  pipeline.** test/profile_save_e2e_test.dart drives the real
  EditProfileScreen with generated "YO TEST AVATAR"/"YO TEST BANNER"
  images through real pick→validate→pending→Save code against
  firebase_storage_mocks/fake_cloud_firestore, and asserts: Storage
  object exists at users/{uid}/profile/<kind>_<ts>.png with byte-exact
  content; Firestore photoUrl/bannerUrl/bio updated; Auth photoURL
  mirrored; the shared watchCurrentProfile stream emits the new values;
  replacement mints a new URL and deletes the old object; an oversized
  file is rejected with the product's exact copy. Structured [PROFILE]
  stage logging (deliberately present in release web) traces
  SELECTED→VALIDATED→UPLOAD_STARTED/COMPLETE→URL_RECEIVED→
  FIRESTORE_UPDATE→STATE_REFRESHED in the browser console for field
  debugging.
- **Fixed: silent no-op Save.** Edit profile's Save returned without ANY
  feedback when form validation failed — indistinguishable from success.
  It now says so, and a real success ("Profile saved.") is announced only
  after every stage completes.
- **Fixed and deployed 2026-08-27: direct Voice call button in chat did
  nothing.** This was not a tap-target bug: the product had no 1:1 signaling
  subsystem. Friends can now start a server-authoritative call from a DM,
  receive an immediate ringing surface, accept/decline/cancel/end it, mute
  locally and reconnect through a short-lived LiveKit token. Per-user locks prevent overlapping calls; block,
  restriction, account and bilateral-friendship state are rechecked before
  answer and token minting. A 60-second timeout becomes a useful missed-call
  notification that returns to the conversation. See ADR-117.
- **Fixed: reciprocal friend requests could invalidate their Firestore
  transaction under contention.** The request path opened two transaction
  query streams concurrently; the emulator repeatedly closed one while two
  users requested each other at the same moment. The bounded quota reads are
  now ordered, preserving the same caps while the reciprocal-request
  convergence test and the full Functions suite remain stable.
- **Fixed (THE root cause of "saved but no avatar/banner", found with
  production evidence): the default Storage bucket had no CORS
  configuration.** Full diagnostic chain: fan-out logs proved Firestore
  photoUrl updates on Save (uid + object path captured); the stored
  objects fetched publicly as valid images (curl 200, correct
  content-type, real photo bytes); THEN the in-browser test from the
  app's own origin showed the asymmetry — fetching a MISSING object
  returned a clean JSON 404 (the Storage API front-end adds
  Access-Control-Allow-Origin to error responses), while fetching the
  REAL object threw `TypeError: Failed to fetch`, because successful
  alt=media downloads are served with the BUCKET's CORS config, which
  was empty. Browsers therefore blocked every real image byte; the
  errorBuilder fallbacks rendered initials/gradient, indistinguishable
  from "no image set". This also explains why NO Storage-hosted image
  (avatars, banners, club avatars, room images) has ever rendered in
  the web app, and why the earlier CORS probe — run against an error
  response — was misleading. Fix: bucket CORS set to allow GET/HEAD
  from any origin (media on this bucket is public-read by rules design
  anyway) via a one-shot admin function, executed once and deleted;
  functions/admin/apply-storage-cors.js is kept unexported as the
  documented reapply path. Verified after: the same fetch+decode from
  the app origin succeeds (200, 1024x1819, 352,362 bytes) with
  access-control-allow-origin present on the real object. No client
  change was needed — stored URLs were always correct.
- **Known minor issue: replaced profile images may not be cleaned up.**
  The user's superseded avatar (avatar_1786204059179.png) was still
  fetchable after being replaced — `_deleteReplacedImage`'s best-effort
  delete is failing silently, most likely refFromURL vs the
  `.firebasestorage.app` bucket URL format. Cosmetic storage cost only;
  needs a debugPrint in the catch and a look at refFromURL handling.
- **Fixed: mobile Home's "Create Room" empty state opened the Moment
  recorder.** `MobileHome` had no `onCreateRoom` callback, so
  `HomeActiveRooms`'s empty-state button was wired to `onCreateMoment`.
  Starting a room and recording a Moment are different flows; the shell
  now passes `_openCreateRoom`.
- **Not a bug: the "DesktopHome renders one banner of two" report.** The
  stream and `rankRoomsForHome` were always correct — instrumentation
  showed `board=[r1, r2]` and two `HomeRoomBanner` widgets in the tree.
  The failing test simply never set a viewport, so the 800x600 default
  clipped the second banner out of the lazily-built `ListView` and the
  finder saw one. Every other test in that file called `useDesktop`;
  that one did not. Fixed by giving it a viewport, not by changing
  production code.
- **Fixed: room identity snapshots trusted the Firebase Auth display name.**
  Broadcast `handRequests` and Family `checkIns` pinned the uid but accepted a
  client-supplied `displayName`, while the app sourced that value from the Auth
  mirror. A stale mirror could regress a recent canonical rename and a modified
  client could forge any label. Both services now read `users/{uid}` and both
  create rules require byte-for-byte equality with its `displayName`, exact
  schemas and server-time timestamps; focused Flutter tests and Rules emulator
  cases cover canonical, stale, forged and missing-profile paths.
- **PARTIALLY DEPLOYED 2026-08-28 — revised Stripe Premium catalog is live,
  but provider rollout and checkout remain disabled.** The secret-free
  production callable now returns the truthful catalog with checkout and
  Portal unavailable; no Stripe mutation handler was deployed. ADR-118
  replaces ADR-067's old PLN
  19.99/199.99 recurring catalog with card/PayPal at EUR 6 monthly or EUR 60
  annually, plus non-renewing BLIK at PLN 26/30 days or PLN 260/365 days. The
  source owns hosted Checkout/Portal, signed webhook authority, idempotent
  billing-to-entitlement projection and production live/test separation. No
  live Product/Prices, PayPal/BLIK activation, secrets, webhook, Portal or
  four-method production smoke is recorded here, so source readiness must not
  be presented as a working purchase path. Launch also remains blocked on
  approved seller/business, applicable tax, B2B and customer-facing
  refund/dispute handling. Do not publish legal, tax or refund claims until
  those decisions exist, and never use Stripe test mode in production
  `yovoice-ec54a`.
- **Fixed in source — Google Sign-In on Flutter Web returned Google error 400
  `redirect_uri_mismatch`.** The deployed bundle used
  `auth.yovoice.app/__/auth/handler`, but that redirect was not registered on
  the Google OAuth client. Flutter Web now uses Firebase's registered
  `yovoice-ec54a.firebaseapp.com` Auth handler. The Android Firebase app also
  has both debug and release/upload SHA-1 and SHA-256 fingerprints, and the
  checked-in SDK config contains the release OAuth client. The registered
  Firebase handler is now live; each auth release still requires a real popup
  smoke rather than relying on static configuration alone.
- **Fixed and deployed to web/Android internal build 6 — Google/Apple authentication could succeed and
  then return the user to Login, while Registration did not expose either
  provider.** Firebase publishes the authenticated user before the provider
  future completes; if concurrent first-profile provisioning then failed, the
  old rollback signed out a valid provider session. Provider names outside the
  Firestore 2–120 UTF-16-unit contract could fail the same boundary. Federated
  auth now preserves the Firebase Auth session, normalizes provider identity
  without splitting graphemes, aborts an in-flight cross-account bootstrap,
  and blocks `MainShell` behind bounded, idempotent profile-bootstrap retries
  with an explicit retry/sign-out state. Registration reuses the Google/Apple
  actions from Login, transient Apple availability failures can be retried,
  and iOS declares `GIDClientID`. Automated tests/config checks are not a real
  provider login: new-account and returning-account smokes on production web
  and store-installed builds remain release evidence. The signed iOS build 7
  artifact passed entitlement/configuration inspection and App Store Connect
  accepted it for TestFlight processing; tester-group availability and a
  real-account smoke remain pending. Android build 7 remains active on
  Internal Testing; testers must opt in with an address registered as a Google
  account rather than searching for the still-draft app in Play Store.
- **Fixed in source and provider configuration — Sign in with Apple was a
  placeholder.** Apple App ID `app.yovoice` now has the capability, Service ID
  `app.yovoice.web` owns the three verified web domains and Firebase callback,
  a dedicated Sign in with Apple key configures the enabled Firebase
  `apple.com` provider, and the regenerated `YO Voice App Store` profile
  carries the entitlement. The client has a real Firebase Apple flow, shared
  profile provisioning and a runtime provider probe. Every configured shipped
  target enables Apple by default; an explicitly disabled build still fails
  closed. Deployment and real-account web/Android/iOS smoke tests remain the
  release evidence, not the existence of source code.
- **Fixed in source — Profile visibility was a disabled placeholder.** The
  reusable Settings surface now persists `public`/`friends`/`private` through a
  server-authoritative callable. Rules, search and website publication enforce
  it; invalid state fails closed. A backend-only generation also closes the race
  where a scheduled showcase build could otherwise reinsert a profile just
  after it became private. Source and production still differ until Functions,
  Rules and clients are deliberately deployed.
- **Fixed in source, not deployed — “Who can message you” was a disabled
  placeholder with no delivery policy.** A recipient now selects Everyone,
  People you follow, Friends only, or Nobody. The server rechecks the setting
  on canonical conversation open, every text send, media reservation, and
  media finalization; existing threads and a pre-change upload reservation are
  not bypasses. Firestore Rules also protect the legacy direct-write path.
  Directional-follow, one-sided-friendship, malformed-value, existing-thread,
  and preference-change-during-upload attacks are covered by the Functions and
  Rules emulator suites; responsive Flutter widget/service tests cover 320 px
  and desktop widths.
- **Fixed in source — mobile Staff Center left too little room for its
  content.** The pushed Staff Center kept both a seven-item horizontal section
  strip and the application dock visible while every section scrolled inside
  the remaining viewport. The section strip now collapses when content moves
  toward the bottom and returns when the user scrolls back; an always-visible
  app-bar menu keeps every capability-gated section reachable. Phone headers
  also keep their action beside the title instead of wasting a separate row.
  Geometry and interaction regressions cover 320/390/430 px at 200% text, and
  the real-font screenshot harness includes the scrolled state.
- **Fixed in source 2026-08-28 — direct chats could nag, duplicate alerts,
  strand media and lose call setup.** The visible “Unread counts may not update right now.”
  banner came from background read-receipt bookkeeping, which ran even for the
  sender's own messages and surfaced an unactionable failure inside the chat.
  Read work is now incoming-only, silent, single-flight and paged past the
  server's 100-message boundary. An active conversation suppresses only its
  foreground native alert, app banner and shell overlay; background delivery
  remains enabled. Activity-trigger replay can no longer reset a notification
  to unread or resurrect a deleted row, and each Firestore notification
  generation uses a source-revalidated terminal FCM dispatch claim, platform
  collapse ids and a managed 30-day event-ledger TTL. Text outbox delivery
  remains FIFO per conversation without allowing one failed conversation to
  block another. Photo and voice payloads now survive process restarts in an
  account-scoped, bounded outbox; expired reservations rotate safely even when
  the device clock is wrong, and Retry/Discard cannot race an active finalize.
  Direct-call start persists one account/peer-scoped request id before the
  network write and recovers the canonical call after restart or lost response,
  instead of leaving the callee ringing while the caller cannot open or cancel
  the call. Firestore Rules also enforce the documented
  server-only conversation root, preventing a participant from forging either
  member's unread/read cursor, typing state or last-message summary. See
  ADR-121. Physical two-device background push, APNs/FCM, LiveKit audio and
  weak-network media smoke remain release evidence rather than automated-test
  claims.
- **Fixed in source 2026-08-29 — the mobile bottom navigation did not match the
  approved compact floating-dock interaction.** The old private shell widget
  mixed layout, routing and its centre action, used a standalone logo treatment
  and transitioned whole pages vertically. One reusable floating dock now owns
  the five responsive visual slots, one shared animated selection capsule,
  the contained circular YO action, transient More selection, safe-area
  reservation and reduced-motion behavior. `MainShell` remains the sole owner
  of domain tab indexes and keeps its existing lazy page instances; a keyed
  Offstage/TickerMode stack adds the 12 px directional fade-through without
  dropping scroll, form or loaded state. The real centre room/Moment action,
  More transition guard, unread badge and pop-before-action behavior are
  preserved. Widget regressions cover 320 px, 1.3 text scale, gesture inset,
  keyboard inset, rapid retargeting, actionable semantics, active-animation
  disposal, Android system Back, final-row
  visibility and retained page state. A physical iOS/Android visual and haptic
  pass remains release evidence for the next native tester build. The first
  visual pass still painted YO over a complete rounded rectangle, so the
  approved central cradle read as an overlap instead of a deliberate cut-out.
  The shipping surface now uses one tangent notched path for fill, border,
  shadow and child clipping, with the 64/68 px YO control centred inside a
  five-pixel `surfaceSunken` socket. Dark/Pearl real-font renders and
  path-level widget assertions guard the corrected silhouette. The follow-up
  accessibility pass also gives the whole painted ring one circular hitbox,
  orders keyboard focus Home → Chats → YO → Moments → More, paints a visible
  YO focus boundary and switches 160%+ text to a taller two-by-two destination
  layout instead of truncating labels. Firebase Hosting workflow
  `33238217610` deployed the pinned `17b386b` artifact on 2026-08-29; the live
  `main.dart.js` matches that artifact byte-for-byte.
- **Fixed in source 2026-08-29 — iOS silently disabled System/Pearl at the
  native application boundary.** ADR-016 correctly pinned a formerly
  dark-only product to `UIUserInterfaceStyle=Dark`, but that override survived
  the complete Pearl migration and forced iOS to keep reporting Dark even
  when Flutter selected `ThemeMode.system`. The application-wide override is
  removed for build 12. The launch storyboard and native window background
  remain branded dark while device-local preferences load; Flutter then owns
  the live surface and status-bar brightness. A source regression asserts the
  global pin stays absent.
- **Fixed in source 2026-08-29 — profile photos could update in the Chats
  people strip but remain stale in conversation rows and Home.** Direct
  conversations and Voice Moments keep denormalized identity for offline
  rendering. Their profile trigger used the triggering event's `after` image,
  so an older at-least-once Firestore event finishing last could permanently
  restore an obsolete avatar. The fan-out now re-reads the canonical user in
  the same retryable transaction as each bounded target chunk. Chats overlays
  its reactive friend identity immediately, open chat routes watch the
  privacy-safe `publicProfiles` projection through `ProfileService`, and mobile
  Home resolves that same projection for recent-chat cards just like desktop.
  A production-pinned, dry-run-first repair converges already-stale snapshots
  but fails closed for missing/disabled Auth accounts and retired profiles.
  Emulator regressions cover out-of-order delivery, avatar removal, retired
  identities and a conversation-membership race; widget regressions cover the
  Chats row, open route and standard Home card. Coordinated native tester build
  13 remains the physical-device release evidence.
