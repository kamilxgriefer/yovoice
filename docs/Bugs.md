# Known Issues

Current, living list of known bugs and tracked gaps — not a changelog.
Update this whenever a bug is found or fixed. For "features not built
yet," see [Roadmap.md](Roadmap.md) instead; this file is specifically
about things that are broken, risky, or need verification.

## Security

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
  ([Roadmap 0a](Roadmap.md#0a-run-the-public-profile-backfill-32-accounts-currently-invisible))
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
  housekeeping — the new rules require follow edges to carry exactly
  `['uid','followedAt']`, Firestore denies a list query if any single
  document fails the rule, so one legacy five-key edge emptied a user's
  entire followers/following list. See
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

- **FIXED — friend requests, acceptances and follows could silently
  produce no notification.** All three were a second client write issued
  after the authoritative write, inside `try { ... } catch (_) {}`. Any
  interruption between the two writes lost the notification permanently
  and reported nothing. They are now derived from their source documents
  by `onFriendRequestCreated`, `onFriendRequestResolved` and
  `onFollowerCreated` (ADR-041), which Cloud Functions retries.
  **Deployed 2026-08-16** — all three appear in `firebase functions:list`.
  *(This bullet read "Needs the Functions deploy to take effect in
  production" until that date.)*
- **FIXED — clients could forge these three notification types.** A
  client could write "X accepted your friend request" with no friendship
  existing; rules cannot check that. The three types were removed from
  the client-creatable list, and the trigger reads the friendship itself.
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
- **OPEN — remaining client-written notification types still fail
  silently.** Club/room invites and `mention` keep the old best-effort path.
  Direct messages and replies are now derived by the server from the message
  document.

## Achievements

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
- **Fixed (P0, 2026-08-08): friend-request acceptance never notified the
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
  this session's tooling).
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
- **Two parallel hand-raise implementations exist**, unconsolidated. Not
  actively broken, but a maintenance risk — a fix applied to one may be
  missed in the other. See
  [Roadmap.md](Roadmap.md#12-consolidate-the-two-parallel-hand-raise-implementations).
- **Most screens don't use the shared theme system** (`lib/core/theme/`,
  `lib/shared/widgets/`) yet — they use a consistent-but-inline hex-color
  convention instead. Not a bug, but tracked as a migration in progress —
  see [UI.md](UI.md) and
  [Roadmap.md](Roadmap.md#app-wide-theme-migration).
- **CORRECTED 2026-08-16 — this entry said "Cloud Functions still have
  zero automated test coverage."** That was false, and had been for some
  time: `functions/test/` holds **510 tests across 82 suites** in 45
  files, running against the Auth + Firestore emulators and gating the
  Hosting release in CI. Current counts live in one place now —
  [TESTING.md](TESTING.md#current-counts-2026-08-17) — so this file should
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

- **OPEN — App Store/Google Play Premium checkout is not operational.** The
  entitlement model, admin grant and access gates exist, but no IAP client or
  store receipt-verification adapter is configured; `verifyPurchase`
  deliberately declines rather than trusting the device. Only the guarded
  `adminSetPremiumEntitlements` callable can grant working Premium today. See
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
- **Fixed: password reset / email verification links dumped users on
  Firebase's generic white `__/auth/action` page.** Not a bug in
  ActionCodeSettings — its `url` only ever becomes the post-action
  continueUrl (established empirically in a prior session). The user-facing
  handler simply didn't exist for reset (`/reset-password` on the website
  was an empty directory) and the console's action URL was never
  customized. Now: `yovoice.app/auth/action` dispatcher → branded
  `/reset-password`, `/verify-email`, `/recover-email` pages; full reset
  lifecycle verified against the Firebase Auth emulator (old password
  rejected, new accepted, code replay rejected, reused link shows a
  branded error, hostile continueUrl stripped by allowlist). Requires the
  one-time console steps in docs/email-templates/README.md before it's
  live for real emails. See ADR-022.
- **Fixed: login's "Forgot password?" ended in a bare SnackBar and could
  leak account existence.** Now opens a dark "Check your inbox" sheet with
  neutral copy and a 60s resend cooldown; `user-not-found` deliberately
  takes the same path as success so the reset form can't be used to probe
  which emails have accounts.
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
- **Fixed: dead Voice call button in chat** — empty onPressed since the
  screen was built. Now explicitly disabled + labeled per ADR-012; 1:1
  calls need a signaling subsystem (ringing notifications,
  accept/decline, call sessions) that doesn't exist yet.
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
