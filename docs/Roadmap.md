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

- **Sign in with Apple provider and dedicated password-reset route**
  (2026-08-18, source/configuration ready; Hosting deployment and real-account
  smoke pending): the former Apple placeholder now uses Firebase's real Apple
  provider with a dedicated Service ID/key, enabled App ID capability,
  regenerated release provisioning profile and runtime availability probe.
  Production web builds enable the otherwise fail-closed compile-time gate.
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
  Appearance now offers System/Dark/Light Beta and app language offers
  System/English/Polish Beta,
  persisted locally with backward-compatible Dark/English fallbacks. Coverage is intentionally
  bounded to the shared theme plus migrated navigation, auth, Settings and
  framework controls; remaining inline-dark/English screens are still tracked
  work, not silently described as translated. Published Voice Moments can be
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
  [TESTING.md](TESTING.md#current-counts-2026-08-17). **These rules were
  DEPLOYED on 2026-08-16.** This entry read "The new Firestore rules still
  require a manual deploy" until then. Store verification adapters remain
  unconfigured, so `adminSetPremiumEntitlements` is still the only working
  grant path — and note that Premium expiry had never once run in
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

- Server-derived social notifications (2026-08-12): friend requests,
  acceptances and follows are no longer a best-effort second client
  write. Three Firestore triggers derive them from the authoritative
  documents, with deterministic ids so an at-least-once redelivery
  cannot duplicate a row, and the three types were removed from the
  client-creatable set so they can no longer be forged. Proven
  end-to-end through the real triggers in the emulator: 13 pipeline
  stages, from the source write to the recipient's bell feed and unread
  badge. 224 Flutter tests, 173 rules tests, 65 Functions tests.
  **Needs a Functions deploy, then the rules deploy, in that order**
  ([ADR-041](Decisions.md#adr-041-friend-request-acceptance-and-follow-notifications-are-derived-from-their-source-documents-by-firestore-triggers-not-written-by-the-acting-client)).
  Web push remains broken for a separate, documented reason, and
  `@mentions` are not started.

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
- Full documentation system — Vision/Architecture/Features/Roadmap/
  Firebase/Backend/Flutter/UI/Decisions/Bugs plus this evolution pass
  (`02275bd`, `26d11a2`, and this session's commit).

---

## In Progress

### App-wide theme migration

- **Status**: In progress — the root System/Dark/Light Beta switch and shared
  light/dark themes are complete in source; per-feature-area passes remain.
- **Description**: `lib/core/theme/` (`AppColors`, `AppTypography`, etc.)
  and `lib/shared/widgets/` (`YoButton`, `YoCard`, the `Yo*State` widgets)
  exist as the intended long-term design system, but most screens still
  define their own consistent-but-duplicated inline hex color constants
  instead of importing them. The new root Light mode cannot override those
  literals, which is why it remains explicitly Beta — see [UI.md](UI.md) for
  the two systems in detail and ADR-072 for the preference boundary.
- **Dependencies**: None technical — this is pure migration effort, one
  feature area at a time (home/friends/notifications/messages; discover/
  clubs/profile/achievements; auth screens; rooms; messages/moments/
  notification-prefs; a final consistency pass).
- **Priority**: Low-Medium. Not urgent — the inline convention already
  reads as visually consistent to a user, so this is an internal
  maintainability concern, not a user-facing bug. Worth finishing before
  the two systems drift further apart, since every new screen written
  against the old convention is more code that eventually needs migrating.
- **Future considerations**: Migrate a screen wholesale, not widget by
  widget — mixing both systems in one file is worse than either alone.
  Once complete, consider a lint rule or a code-review checklist item that
  flags a new raw `Color(0xFF...)` literal outside `lib/core/theme/`, so
  the migration doesn't quietly regress.

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

### 0a. Run the public-profile backfill (32 accounts currently invisible)

- **Status**: Blocked on credentials; the unblock is committed and unrun.
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

- **Status**: Not started. **There is no record of this migration ever
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
  client is configured. Stripe web Checkout/Portal and webhook authority are
  implemented and tested in source under ADR-067, but not deployed; live Stripe
  and legal/tax configuration remain blocked.
- **Actions**:
  1. ~~Deploy the tested `firestore.rules` update.~~ **DONE 2026-08-16.**
     Instead, confirm one real `expirePremiumIdentity` run succeeds.
  2. Complete ADR-067's blocked Stripe rollout: one live Product, inclusive PLN
     Prices at 19.99/month and 199.99/year (17% annual saving), Adaptive
     Pricing, Tax registrations, Portal and signed webhooks. Separately create
     equivalent App Store/Play products only when mobile IAP adapters are
     designed; store-localized prices remain authoritative on those platforms.
  3. Interim: grant premium via the `adminSetPremiumEntitlements`
     callable (admin/superAdmin only).

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

- **Status**: Implemented and tested in source on 2026-08-18; Firebase TOTP
  provider configuration and the coordinated client rollout remain pending.
- **Description**: A Firebase Auth TOTP factor managed from Settings, including
  enrollment, removal, recent-login reauthentication and the second-factor
  resolver shown after password, Google or Apple primary sign-in.
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

- **Status**: Foundation and bounded Polish Beta complete in source on
  2026-08-18; not deployed. System, English and Polish Beta are selectable and
  saved on the current device.
- **Description**: This controls UI language, distinct from a user's
  spoken/native content-language fields. `flutter_localizations` supplies
  framework delegates and the YO Voice delegate covers migrated navigation,
  authentication and Settings copy. The interface states that other product
  screens remain English while migration continues.
- **Dependencies**: No backend or Firestore schema. Completing Polish requires
  moving remaining raw English literals into the localization contract and
  performing linguistic/visual QA at every breakpoint.
- **Priority**: Low-Medium continuation. The switcher and honest Beta are
  usable; complete-app translation is still substantial work.
- **Future considerations**: Add a translation-maintenance workflow before
  declaring Polish stable, then evaluate ARB/code generation if the catalog
  grows beyond the deliberately small delegate. See ADR-072.

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

### 12. Consolidate the two parallel hand-raise implementations

- **Status**: Not started.
- **Description**: Two separate hand-raise implementations exist in the
  rooms feature, unconsolidated — see [Bugs.md](Bugs.md#code-quality--consolidation).
- **Dependencies**: Precisely identifying both implementations and
  confirming behavioral parity before merging them — this needs
  investigation before it needs code.
- **Priority**: Medium — not actively broken, but a real maintenance risk:
  a fix applied to one implementation can be silently missed in the other.
- **Future considerations**: Once identified, prefer keeping whichever
  implementation is used by the more actively developed room type
  (Broadcast Room, per [Features.md](Features.md)) as the canonical one,
  rather than a from-scratch third implementation.

### 13. App-store distribution

- **Status**: Not started — no published iOS/Android builds exist yet.
- **Social-auth readiness (2026-08-18)**: Google web OAuth and Android
  debug/release configuration are fixed in source; deploy plus real-account
  device smoke tests remain. Sign in with Apple has a real fail-closed client
  flow, but stays disabled until the Apple Service ID/key, Firebase provider,
  capability and regenerated release profile exist.
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
