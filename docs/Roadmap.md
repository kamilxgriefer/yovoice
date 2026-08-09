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

- Mockup visual overhaul — Home + rooms + Premium (2026-08-09): M1 Home
  Live Social Hub (real-data VoiceCore hero, Your People status row,
  `c979d20`); M2 room chat + reactions in both room types and From your
  Clubs on Home (`ee30f6f`, rules deployed); M3 Premium presentation
  (board screen 3) + dedicated plans screen (board screen 4) — the old
  single paywall split into `PremiumScreen` (marketing presentation with
  the member's real avatar in the canonical premium ring) and
  `PremiumPlansScreen` (toggle, side-by-side plan cards, real
  `verifyPurchase` wiring; decline path live-verified against production)
  ([ADR-031](Decisions.md#adr-031-premium-is-two-surfaces-presentation-and-plans-the-hero-is-the-members-real-identity));
  website Premium surfaces aligned to the same language
  (`yovoice-website` `ed606b3`); board screen 5 profile refinement —
  header chips row (AccountTypeBadge + server-mirrored
  `PremiumIdentityChip`), compact stat formatting (1.8K), website chip
  in Voice identity, owner crown + "· Owner" on owned club tiles (all
  real-data-conditional; no XP bar or Moments/Activity tabs — those
  systems don't exist and honesty wins over the mockup). Board screen 6
  (club room) still open — see the agent handoff ledger.

- Rooms 2.0 — M1/M2/M3/M8 (2026-08-09): LiveKit-authoritative MicState
  + mute-race fix; Podcast rename (ADR-029); scalable stage system
  replacing the orbit, verified at 2/10/50/500 participants (ADR-030);
  promotion/demotion token refresh; floating navigation dock with
  Friends as a primary tab. Remaining milestones (covers/cards, room
  chat, whiteboard, reactions, permissions, analytics, Spotify
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
  working quick actions (`6cfd208`).
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
- Full documentation system — Vision/Architecture/Features/Roadmap/
  Firebase/Backend/Flutter/UI/Decisions/Bugs plus this evolution pass
  (`02275bd`, `26d11a2`, and this session's commit).

---

## In Progress

### App-wide theme migration

- **Status**: In progress — foundation complete, per-feature-area passes
  ongoing.
- **Description**: `lib/core/theme/` (`AppColors`, `AppTypography`, etc.)
  and `lib/shared/widgets/` (`YoButton`, `YoCard`, the `Yo*State` widgets)
  exist as the intended long-term design system, but most screens still
  define their own consistent-but-duplicated inline hex color constants
  instead of importing them — see [UI.md](UI.md) for the two systems in
  detail.
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

### `app.yovoice.app` DNS

- **Status**: In progress — blocked on an external dependency, everything
  on this project's side is ready.
- **Description**: Firebase Hosting has `app.yovoice.app` configured as a
  custom domain, waiting on one CNAME record
  (`app.yovoice.app → yovoice-ec54a.web.app`) on Cloudflare, where
  `yovoice.app`'s DNS is managed.
- **Dependencies**: Cloudflare access — only the domain owner has it. Not
  something engineering effort can unblock.
- **Priority**: Medium — low effort once unblocked (see below), but it's
  the last visible seam in the two-deployable architecture
  ([ADR-014](Decisions.md#adr-014-two-deployables-one-firebase-project)),
  and the website currently points at Firebase's default domain instead of
  its real one.
- **Future considerations**: Once the record is live and Firebase finishes
  domain verification: flip `NEXT_PUBLIC_APP_URL`
  ([ADR-009](Decisions.md#adr-009-next_public_app_url-as-an-env-var-website-repo))
  to `https://app.yovoice.app` in all three Vercel environments
  (production/preview/development — easy to update one and forget the
  others) and redeploy. Verify the redirect end-to-end afterward rather
  than assuming the env var change alone is sufficient.

---

## Planned / Backlog

Ordered by rough priority — re-prioritize freely, this isn't a queue.

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

- **Status**: Architecture shipped (ADR-024). Rules ARE live: a JVM was
  installed 2026-08-08, the emulator suite passed 87/0 (including the
  six premium cases) and firestore.rules deployed — club creation and
  accountType:creator are now enforced server-side.
- **Actions**:
  2. Create store products `yovoice_premium_monthly` (€9.99) and
     `yovoice_premium_yearly` (€89.99) in App Store Connect + Play
     Console; add an IAP plugin client-side; implement the verification
     adapters in functions/premium/entitlements.js (App Store Server
     API key, Play service-account, or web provider webhooks). Each
     adapter ends by calling applyEntitlements() — nothing else changes.
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

- **Status**: Not started — Creator Studio currently shows this as an
  honest, disabled "Coming soon" card.
- **Description**: Real audience/engagement insights for creators
  (listens, room attendance trends, follower activity).
- **Dependencies**: A real analytics/event data model doesn't exist yet —
  this needs schema design, not just a UI. Overlaps conceptually with
  Audience growth tracking (below); worth designing both together rather
  than as two unrelated data models.
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

- **Status**: Not started — Settings has a visible, honestly-disabled
  "Coming soon" entry.
- **Description**: An additional sign-in factor beyond password/Google
  Sign-In.
- **Dependencies**: Firebase Auth supports multi-factor auth natively;
  this is mostly Flutter UI + enrollment-flow work, not new backend
  infrastructure.
- **Priority**: Medium — a real account-security improvement, not urgent
  since there's no evidence of account-takeover activity today.
- **Future considerations**: SMS-based MFA has real cost-per-message and
  SIM-swap risk; an authenticator-app (TOTP) flow avoids both and is worth
  defaulting to if Firebase's SDK support is equivalent.

### 7. Profile visibility / message-privacy controls

- **Status**: Not started — Settings has a visible, honestly-disabled
  "Coming soon" entry.
- **Description**: Let a user restrict who can view their profile or send
  them direct messages.
- **Dependencies**: New fields on `UserProfile` plus corresponding
  Firestore rules updates — and, importantly, every existing read path
  that shows profile/message data needs to actually respect the new
  setting, not just the write path that sets it.
- **Priority**: Medium — a real trust/safety feature.
- **Future considerations**: This is exactly the kind of feature ADR-013
  warns about: if enforcement can live entirely in Firestore rules
  (checking the target's visibility field before allowing a read), keep it
  there; only reach for a Cloud Function if rules genuinely can't express
  the check.

### 8. Multi-device session management

- **Status**: Not started — Settings currently shows only "this device."
- **Description**: List and revoke active sessions across devices.
- **Dependencies**: A session/device registry data model doesn't exist —
  Firebase Auth doesn't expose this out of the box the way it exposes the
  current user.
- **Priority**: Medium — a real security/trust feature, no urgency signal.
- **Future considerations**: Revoking a session likely means invalidating
  a refresh token or forcing a re-auth — check what Firebase Auth actually
  supports here before designing the data model, rather than assuming
  arbitrary remote sign-out is possible.

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

- **Status**: Not started — app is English-only today.
- **Description**: A UI-language switcher, distinct from the per-user
  spoken/native *content* language fields that already exist on
  `UserProfile` (those describe the user, not the app's UI).
- **Dependencies**: No i18n/localization framework is wired up yet
  (`flutter_localizations` + `.arb` files, or an equivalent) — this is
  infrastructure work before it's a feature.
- **Priority**: Low — no urgency signal, meaningful upfront lift to wire
  up the framework even before the first translation exists.
- **Future considerations**: Once the framework exists, decide a process
  for keeping translations in sync with new UI copy as it ships — a
  language switcher with stale translations for half the app is worse
  than not having one.

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
