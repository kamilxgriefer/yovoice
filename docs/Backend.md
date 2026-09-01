# Backend (Cloud Functions)

The compute layer: `functions/` (Node, Firebase Functions v2), region
`europe-west1` for every function. For the data layer these functions read
and write, see [Firebase.md](Firebase.md); for *why* this comparatively
small set of functions exists at all rather than mediating every write
(most of the app doesn't go through here), see
[ADR-013](Decisions.md#adr-013-clients-write-firestore-directly-cloud-functions-are-reserved-for-privileged-work) —
every function below exists because it needs a secret the client can
never hold, grants a privilege rules can't safely compute, fans out a side
effect, or coordinates an atomic cross-document operation. If you're
adding a new function and it doesn't clearly need one of those four
things, it probably shouldn't be a function.

## LiveKit token minting

`createLiveKitToken` (`functions/livekit/token.js`) is the **only** way a
client gets a LiveKit token — never minted client-side. This is the
reference example for
[ADR-013](Decisions.md#adr-013-clients-write-firestore-directly-cloud-functions-are-reserved-for-privileged-work)'s
"needs a secret the client can never hold" condition. Since the
[security audit](Archive/SECURITY_AUDIT.md) fix
([ADR-003](Decisions.md#adr-003-security-fixes-move-permission-authority-to-the-server)),
permissions are computed server-side, not trusted from the request. See
[Architecture.md](Architecture.md#data-flow-a-concrete-example-joining-a-broadcast-room)
for how this fits into the full join-a-room flow, start to finish:

0. **Requires the room to say status active and `isLive` true.** The
   function performs no transition of its own — making the room live is the
   *caller's* job, and until `b0f1062` no reachable caller did it for an
   ordinary Community room, so this refusal was the product's actual voice
   behaviour (45 rooms, 3 live in production). See
   [ADR-088](Decisions.md#adr-088-entering-a-room-performs-the-liveness-transition-through-one-ordered-coordinator-that-mirrors-the-deployed-rule).
1. Looks up the room (`rooms/{roomId}`) and the caller's own participant
   doc (`rooms/{roomId}/participants/{uid}`) — 404s if either is missing.
2. Derives `canPublish` from real state: `(isHost || isSpeaker) &&
   !participant.isMuted`. `hidden` and `recorder` are never taken from the
   client.
3. The LiveKit room name is the Firestore `roomId` itself, not an arbitrary
   client-supplied string.

`LIVEKIT_API_KEY`/`LIVEKIT_API_SECRET` are Secret Manager secrets, never in
code. `LIVEKIT_URL` (`wss://yovoice-3f7j9fb7.livekit.cloud`) is a plain
`defineString` — a public endpoint, not a secret.

## Direct 1:1 calls

> **VIDEO STATUS: SOURCE ONLY / NOT DEPLOYED.** The deployed audio lifecycle is
> backward compatible with the new schema, but video must not be broadly
> enabled until the recipient has an authoritative compatible-build
> capability and the physical device matrix passes. Safe rollout order is:
> backward-compatible Functions first, then capability registration and
> server gate, compatible clients, and only then video enablement.

`functions/calls/direct_calls.js` owns the friend-call lifecycle:
`startDirectCall`, `acceptDirectCall`, `declineDirectCall`,
`cancelDirectCall`, `endDirectCall` and `createDirectCallToken`. Start and the
answer/token boundaries revalidate active accounts, both canonical friendship
guards, both block directions and both communication restrictions.
Transactional `directCallLocks/{uid}` documents allow one ringing/active call
per account.

Ringing lasts 60 seconds. `expireDirectCallsSchedule` converts an unanswered
call to `missed`, frees both locks and creates the canonical missed-call
notification. Calls store an immutable server-validated `mediaType`; legacy
documents without it remain audio. An accepted call gets an eight-hour ceiling
and a five-minute LiveKit token scoped to `call_<callId>`. Audio receives a
declared-microphone source grant. Video receives declared microphone and camera
source grants; screen-share labels are omitted, and normal voice rooms use the
same microphone label boundary. LiveKit trusts the client's `TrackSource`, so
this is defense in depth for normal clients rather than proof of actual capture
origin. Active calls that hit the ceiling are now ended by the same scheduler
and queue durable room teardown instead of leaving a valid RTC room behind.
Ending an active call writes
`directCallControlOutbox/{callId}`; `onDirectCallControlCreated` retries the
LiveKit room deletion/revocation and active-session cleanup.

## Notifications

> **ADR-114 social lifecycle is DEPLOYED (2026-08-25).** The generation-bound
> friend/follow behavior is live and the three older social writers are absent
> from production. Deployment evidence and the retained recovery runbook are in
> [DEPLOYMENT.md](DEPLOYMENT.md#friends-notification-single-writer-rollout--executed-2026-08-25).

> **ADR-116 is partially deployed.** Hosting serves the v3 in-app pack, while
> production `onNotificationCreated` deliberately remains on
> `yovoice_activity_v2` until a new native build creates v3 and passes the
> physical acceptance matrix in
> [DEPLOYMENT.md](DEPLOYMENT.md#partial-release-2026-08-27-velvet-prism-product-sound).

`onNotificationCreated` (`functions/notifications/push.js`) — a Firestore
`onDocumentCreated` trigger on `users/{userId}/notifications/{id}`. The
authoritative server mutation writes the notification document; rules deny
client creates. This trigger turns "a notification doc exists" into an actual
push via FCM. Before sending it re-reads the document, requires the same
Firestore create generation and, for social events, revalidates the live graph
source. During the ADR-114 compatibility window a retired pair-lifetime id is
allowed only for a genuine old source with no generation pointer; once the
source is upgraded it is removed rather than delivered. These checks close delayed-event races they can
observe; FCM remains best effort and a resolution can still race the final
network send after the last read. Has a title-builder per notification type,
mirroring the in-app copy in `app_notification.dart`, and respects each
user's per-type notification preferences (`notification_preferences_screen.dart`
→ `NotificationService.setPreference`). The shared, unit-tested source payload
uses the high-importance `yovoice_activity_v3` Android channel with the custom
`yovoice_notification` sound and vibration, the matching APNs sound with active
interruption level, and web icon/badge metadata. Flutter, Functions and the
manifest fallback carry the same channel id; v3 is required because Android
persists a channel's sound. The app/Android/iOS WAVs are byte-identical.
Incoming direct calls use a separate max-priority `yovoice_calls_v1` Android
channel, an APNs time-sensitive category and a require-interaction web
notification; ordinary activity remains on v3.
Foreground FCM and the independent Firestore banner claim the notification id
through one gate, so only the first presentation owns a sound; a native
presentation failure falls back to the in-app banner without replaying it.
The ADR-114 rollout also includes the bounded
`scrub:retired-social-notifications` Admin command. It runs only after the old
social triggers are gone, reports aggregate counts, preserves genuine legacy
rows with a live pointer-less source, and converges source-less or upgraded-
source duplicates that a transient event-time cleanup could have missed.

## Friends

> **The ADR-114 friend/follow lifecycle below is DEPLOYED (2026-08-25).**
> Production uses the six social callables as the single lifecycle authority;
> all three ADR-041 trigger writers were explicitly deleted and verified absent.

- `sendFriendRequest`, `respondToFriendRequest`, `cancelFriendRequest`,
  `removeFriend`, `setFollow`, `setUserBlock` — transactional graph mutations
  and the single authority for their notification lifecycle (ADR-114).
- `getMutualFriends` — mutual-friend lookup for a given pair of users.
- `getFriendSuggestions` — friend-suggestion logic.
- `searchPublicProfiles` — authenticated, bounded display-name/username prefix
  discovery over server projections for verified accounts. It filters self and
  both block directions, rechecks source-account activity and returns an exact
  five-field result. A transactional Admin-only quota is consumed before
  validation/querying (30/minute and 300/hour per uid while App Check
  enforcement is off).
- `onUserPrivacySourceChanged` — retryable `users/{uid}` projection trigger.
  It converges exact `publicProfiles/{uid}` and narrower
  `socialPresence/{uid}` documents from current state, heals extra fields and
  removes both for inactive/deleted accounts. The production backfill reuses
  the same pure derivation in bounded, cursor-resumable pages; see the strict
  rollout sequence in [DEPLOYMENT.md](DEPLOYMENT.md#private-profile-projection-cutover-strict-order--executed-2026-08-16).
- `onAuthUserDeleted` — Auth deletion trigger that retires public identity,
  badges/directory projections and marks any lingering private account record
  inactive, preventing an Auth orphan from being republished.
- Social-graph callables own all friend/follow/block writes. Request acceptance
  creates paired private `friendshipGuards` atomically; unfriend/block removes
  them atomically. Transactional per-user quotas, hard graph caps and
  `MAX + 1` bounded reads prevent unbounded fan-out and oversized-graph oracles.
- Push identity binding rotates on cold start and account replacement, not only
  the happy-path Sign out button. Registration writes are serialized behind an
  identity epoch, so a delayed token refresh cannot attach Account A's token
  during Account B's transition.

## Profile identity

`updateMyDisplayName` (`functions/profile/display_name.js`) is the only
post-bootstrap writer of `users/{uid}.displayName`. It runs in
`europe-west1`, requires an authenticated, verified, active account and accepts
exactly `{displayName: string}`. Leading/trailing whitespace is trimmed;
the result must contain 2–120 Unicode code points and no control, invisible
format, line-separator or paragraph-separator character.

An actual change transactionally writes the canonical display name,
server-owned `displayNameChangedAt` and `profileUpdatedAt`. The next actual
change is refused until exactly `30 * 24 * 60 * 60 * 1000` milliseconds later.
A legacy profile without `displayNameChangedAt` may change immediately.
Replaying the exact canonical name is idempotent even during cooldown: it does
not move either timestamp and returns the existing window.

After the Firestore transaction, the callable mirrors the canonical value to
Firebase Auth. It first reads the Auth user and skips `updateUser` when the
mirror is already equal, so an idempotent replay is not a free Auth-write
amplifier while App Check enforcement is off. A private transactional
server-time budget permits 10 profile-reaching, locally valid requests per uid
per fixed minute. It is consumed before profile/Auth reads, including when a
later profile decision refuses the request. Same-name retries consume that
budget, and the limit still leaves room for an immediate repair attempt after
a transient failure. A transient Auth failure never rolls Firestore back; the
callable returns `unavailable` with
`reason: auth-display-name-sync-pending`, and replaying the same name safely
repairs the mirror. Existing profile/directory triggers project the canonical
Firestore value into `publicProfiles`, `userDirectory` and identity snapshots;
the callable does not duplicate those fan-outs.

The successful response has exactly `displayName`, `changed`,
`displayNameChangedAtMs`, `nextDisplayNameChangeAtMs` and `canChange`;
timestamps are epoch milliseconds or `null` for an untouched legacy name.
Structured failures keep separate machine-readable meanings:
`email-verification-required` and `display-name-state-invalid` are
`failed-precondition`; `display-name-cooldown` additionally returns
`nextDisplayNameChangeAtMs` and `retryAfterSeconds`;
`auth-account-missing` and `auth-display-name-sync-pending` return the already
committed canonical name plus both canonical timestamps. Missing/inactive
profiles remain `not-found`/`permission-denied`, and the private fixed-window
budget returns `resource-exhausted`.

Client-authored room attribution never falls back to the Firebase Auth mirror.
Current Podcast stage requests are a boolean on the caller's canonical
participant row and carry no duplicated identity snapshot. The deprecated
`handRequests` collection remains only for already-installed clients; those
legacy rows and Family `checkIns` must copy the exact current
`users/{uid}.displayName`, and Rules deny stale or forged snapshots. Current
Flutter source does not create a `handRequests` row.

## Direct messaging, Moments and achievements

Recent hardening moved these feature writes from client-authored side effects
to server-authoritative callables:

- `openDirectConversation`, `sendDirectMessage`, `editDirectMessage`,
  `deleteDirectMessage`, `setDirectConversationPreference`, `markDirectConversationRead`,
  `setDirectMessageReaction`, `setDirectTyping`,
  `reserveDirectMessageAttachment` and `finalizeDirectMessageAttachment` in
  `functions/index.js`. The attachment pair binds an immutable Storage object
  to one canonical message after rechecking both participants, blocks,
  restrictions, MIME, size, metadata and object generation. Expired
  reservations and deleted-message objects are handled by the bounded cleanup
  worker; clients never receive a public download URL.
- `reserveMomentDraft`, `finalizeMomentDraft`, `reserveVoiceCommentDraft`,
  `finalizeVoiceCommentDraft`, `createMomentComment`, `deleteMomentComment`,
  `deleteMoment`, `setMomentLike`.
- `selectMyAchievementTitle`.

### Voice Moment publication contract (ADR-115, deployed 2026-08-27)

Local review never touches the backend: native playback reads the temporary
file and web playback owns a temporary Blob URL. The first server operation is
still `reserveMomentDraft`, followed by Storage upload and
`finalizeMomentDraft`.

`availabilityHours` is absent/24 for the backward-compatible default, any safe
whole integer from 24 through 720, or the literal `permanent`. The default
stays out of the operation hash so deployed replays keep their identity; every
non-default value participates in the hash. Reserve performs an advisory exact
published-set capacity check. Finalize repeats that exact check
authoritatively and advances `momentCapacityLedgers/{uid}` in the same
transaction. Delete and scheduled expiry advance the same document, forcing a
finalize racing either operation to retry against current truth. The ledger is
a mutex/version, never a counter; the complete published set remains the
reconstructible source of truth.

Root reserve, publication, expiry and deletion have no direct-write fallback.
Neither do like or comment mutation: their former direct fallbacks could not
bind a counter change to one canonical edge/comment in Rules and permitted
negative or fabricated counters. ADR-115 makes that boundary explicit in
Rules as well as client code. A completed finalize replay returns from its
operation ledger without another Storage read or quota charge; every
unfinished retry is charged before its external Storage reads, including a
retry that already owns a matching preflight. At `expiresAt` (not at the later
sweeper pass), like, text-comment and voice-comment reserve/finalize callables
reject new engagement. Root and reply audio are immutable to clients; bounded
abandoned-upload workers and the cleanup outbox are the only deletion paths.
This contract and its new `(authorId, isPublished)` index are live. The index
reached READY, all thirteen ordered Functions became ACTIVE, both Rules sources
were read back byte-for-byte, production authority/media smokes passed, and the
verified client was then released through Hosting run `33043536603`.

All of these are attempted from the Flutter clients first via callable.
When a callable is genuinely **absent** — no Firebase app, or
`unimplemented` — some of them fall back to a bounded local transaction.

Two limits on that sentence, both learned the hard way:

**A fallback is for an ABSENT callable, never a refusing one.** Only
`unimplemented` and the appless `no-app` case count as absence. `not-found`
does **not**, however much it looks like "no such function": the server
throws it itself for a missing profile (`functions/integrity/guards.js:157`)
or a missing conversation (`functions/messaging/direct_integrity.js:83`,
`:223`). Treating it as absence meant a user with no `users/{uid}` document
bypassed `assertNotBlocked`, `assertNotRestricted` and the rate limits on
every messaging callable. The HTTP status cannot distinguish the two cases,
so it fails closed
([ADR-062](Decisions.md#adr-062-the-client-never-creates-a-direct-conversation--canonical-binding-is-server-only-and-a-legacy-thread-is-adopted-in-place-not-forked)).

**`openDirectConversation` has no fallback at all, and the claim that a
fallback "keeps invariants" was false for it.** The client cannot write
`directConversationPairs/{pairKey}` — that collection is default-denied on
purpose — so a conversation root created locally is missing the guard that
binds the pair, and `validateConversation` then refuses it with `data-loss`,
"The canonical conversation is missing.", on every later server call,
permanently. It also writes 12 of the required 18 keys. That is the exact
opposite of preserving invariants: it manufactures a thread the backend can
never touch again. `conversations` create is `if false` in `firestore.rules`
for the same reason. Where a fallback *does* exist, it owes the server's
document key for key
([ADR-061](Decisions.md#adr-061-a-callable-that-answers-is-the-whole-write-and-its-client-fallback-must-write-the-same-document)).

The Admin SDK bootstrap deliberately does not derive a bucket name from the
project id. New Firebase projects use `<project>.firebasestorage.app`, while
the historic suffix is `<project>.appspot.com`; guessing the latter makes an
upload succeed in the client bucket and finalization inspect a different
bucket. `functions/index.js` therefore lets `FIREBASE_CONFIG` select the
canonical bucket unless an operator explicitly sets one of the documented
bucket override environment variables.

### Recipient-authoritative direct-message privacy

`openDirectConversation`, `sendDirectMessage`,
`reserveDirectMessageAttachment`, and `finalizeDirectMessageAttachment` read
the recipient's private `messagePrivacy` value inside their Firestore
transaction. `peopleYouFollow` requires
`users/{recipient}/following/{sender}`; `friends` requires both canonical
`friendshipGuards`. Those graph records are server-owned. The checks run again
on existing threads and at both ends of a media upload, so neither a stale UI
nor an upload reserved before a preference change can bypass the recipient.
Missing values preserve the legacy Everyone behavior; malformed values return
`data-loss` and do not widen access.

## Clubs

- `transferClubOwnershipSelf` — self-service ownership transfer (owner
  hands off to another member).

## Creator Studio

- `setCreatorPinnedPost` — authenticated, verified Creator callable that
  accepts only `{momentId}` (or `null` to unpin), rechecks active account,
  canonical effective Creator access, ownership and published schema-v2
  Moment state, then writes one server-owned pointer. Paid access comes from
  `entitlements`; moderator-preview access requires an exact signed
  claim/server-mirror match and never rewrites billing truth.
- `onPinnedMomentEligibilityChanged` — removes a pointer when its Moment is
  deleted, unpublished, moved out of the canonical published state or changes
  author.
- `onPinnedCreatorEntitlementChanged` / `onPinnedCreatorProfileChanged` —
  remove pins after Premium/Creator/account eligibility changes. The profile
  trigger filters harmless presence/counter writes before doing Firestore
  work. A server-only role-transition marker defers destructive pin/account
  mode cleanup during the neutral claim/mirror interlock; the final role write
  retriggers convergence. Billing revocation still updates the entitlement,
  and missing/deleted profiles still remove orphaned pins without recreating a
  `users/{uid}` document.

Creator Analytics has no backend endpoint: it is a clearly labelled snapshot
computed from the already loaded canonical profile/room/Club/Moment streams.

## Content reporting

`createContentReport` (`functions/moments/integrity.js`) is the callable
behind every in-product report of a piece of content. **It has been deployed
and ACTIVE since the 2026-08-16 cutover; until `9f3ce7f` no Dart file called
it** — a deployed function nothing invokes looks identical, in every console,
to a working one (ADR-055's lesson, in its second instance).

Target types: `directMessage`, `voiceMoment`, `voiceMomentComment`, and — in
source at `2c086c7`, **not yet redeployed** — `roomMessage` and `clubMessage`.
The two new names are exactly the ones `admin/messages.js` already uses for
the callable a moderator uses to *remove* a message, so a report and the
action taken on it name the same thing with the same ids.

Three contract properties worth knowing before changing it:

- **It runs for any active account, verified or not.** Reporting is a safety
  action and follows the blocking precedent, matching the policy written into
  `firestore.rules`. The relaxation carries a comment ending "Do not restore
  the default here" —
  [ADR-086](Decisions.md#adr-086-a-safety-action-is-never-gated-on-email-verification-and-every-moderation-endpoint-checks-access-before-existence).
- **Access is checked before existence**, for every target type. Answering
  `not-found` first made the endpoint an existence oracle for private room,
  club, channel and message ids.
- **Deduplication rides the operation ledger, keyed on the target rather than
  the attempt**, and the client derives its `requestId` the same way. New
  fields fold into the ledger's `inputHash` **only when the target carries
  them**, because folding them in unconditionally re-keys every report
  already filed in production —
  [ADR-087](Decisions.md#adr-087-an-idempotency-key-derived-from-a-request-payload-is-a-compatibility-surface--new-fields-fold-in-only-when-the-target-carries-them).
  The cost, inherited from the previous deterministic-id path: a report
  cannot be re-filed after a moderator dismisses it.

`reason` is **not** validated server-side here — only the client-direct v1
`reports` create rule constrains it to eight values — so two report schemas
now coexist in `reports/` and the Moderation Center does not yet render the
v2 shape correctly. See [Bugs.md](Bugs.md#moderation--safety) and Roadmap
item 0o.

## Admin

**Deployment status (verified against `firebase functions:list`,
2026-08-08): none of the functions in this section are deployed.** They
are implemented and exported in `functions/index.js`, but no admin UI
exists anywhere (the website's `src/app/admin/` is an empty
placeholder), so there are no callers — and keeping powerful moderation
endpoints undeployed until something actually needs them is the safer
default. Deploy them together with whatever admin surface is built
first.

Every admin function requires a `role` custom claim via the shared authority
helpers and exact agreement with the server-written, client-immutable
`users/{uid}.role` mirror. A profile write cannot forge the signed claim, and
a stale signed claim cannot survive a synchronous mirror revocation.

- **Bootstrap/roles**: `bootstrapSuperAdmin`, `assignUserRole`,
  `getUserRole`, `listAdminUsers`, `setUserBan`.
- **Dashboard**: `getAdminDashboard`.
- **Room moderation**: `listAdminRooms`, `getAdminRoom`,
  `setRoomModerationStatus`, `forceEndRoom`, `removeRoomParticipant`,
  `setParticipantMute`, `adminDeleteRoom`.
- **Club moderation**: `listAdminClubs`, `getAdminClub`,
  `setClubModerationStatus`, `removeClubMember`, `setClubMemberBan`,
  `transferClubOwnership`, `adminDeleteClub`.
- **Audit log**: `listAdminAuditLogs`, `getAdminAuditLog`,
  `getAuditLogFilters`.

`bootstrapSuperAdmin` additionally requires the caller's email to match a
fixed super-admin address **and** `email_verified == true` — added after
the security audit found registering an unverified account with that same
address was enough to claim the role.

## App Check

Every function currently sets `enforceAppCheck: false` — see
[SECURITY.md](SECURITY.md#firebase-app-check),
[ADR-004](Decisions.md#adr-004-firebase-app-check-integrated-client-side-enforcement-deliberately-off),
and [Bugs.md](Bugs.md) for current status and why it's not flipped yet.

## Stripe Premium billing (source-ready; provider rollout disabled)

`functions/premium/stripe_billing.js` owns the deterministic billing catalog,
server-created Checkout and Customer Portal sessions, the signed webhook and
Auth-deletion cancellation. The request contract is exactly
`{plan, paymentMethod?}`: `plan` is `monthly` or `yearly`, and
`paymentMethod` defaults to `recurring` and may otherwise be only `blik`.

The server maps that request to four immutable Stripe Prices:

| Plan | Checkout mode | Payment methods | Price | Paid access |
|---|---|---|---|---|
| Monthly | subscription | card + PayPal | EUR 6 | recurring monthly |
| Annual | subscription | card + PayPal | EUR 60 | recurring annually |
| Monthly | one-time | BLIK | PLN 26 | 30 days, no renewal |
| Annual | one-time | BLIK | PLN 260 | 365 days, no renewal |

The client cannot submit an amount, currency, Price id, Customer id, Firebase
uid, Checkout mode, payment-method list or return URL. Stripe Checkout owns the
payment credential surface and final pre-confirmation amount disclosure; YO
Voice performs no client-side exchange-rate or tax calculation.

Recurring access is projected only after a signed event re-reads the canonical
Subscription and paid latest Invoice. An unpaid renewal cannot extend the
previous paid window. Subscription Checkout sends the exact provider allowlist
`payment_method_types=[card,paypal]`; BLIK Checkout sends only `[blik]`.
BLIK never creates renewal authority: a signed successful
one-time payment grants exactly the configured 30- or 365-day window and writes
`source=stripe_prepaid` with `renewalBehavior=none`. The success redirect is informational
for every method and cannot grant Premium. A user must complete a new BLIK
purchase after expiry to continue.

The Stripe Customer Portal manages only recurring card/PayPal billing. Cancel
at period end prevents a future renewal while retaining the already-paid window.
BLIK has nothing to cancel or switch in the Portal. Auth deletion expires open
Checkout and cancels nonterminal subscriptions; private provider bindings and
event receipts remain available for reconciliation and late signed events.
Refund, dispute, seller, tax and B2B handling remain separate launch-policy
gates; technical access safeguards are not a published refund policy.

Required secrets are `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET`. Required
parameters are `STRIPE_MONTHLY_PRICE_ID`, `STRIPE_YEARLY_PRICE_ID`,
`STRIPE_BLIK_MONTHLY_PRICE_ID`, `STRIPE_BLIK_YEARLY_PRICE_ID`,
`STRIPE_PORTAL_CONFIGURATION_ID` and `STRIPE_EXPECTED_MODE`. Production project
`yovoice-ec54a` accepts only `live`, `sk_live_`, live Prices and live events;
test-mode objects belong only in local/emulator or a future non-production
Firebase project. Source readiness does not mean provider readiness or a live
checkout. See
[DEPLOYMENT.md](DEPLOYMENT.md#stripe-premium-rollout-source-ready-provider-rollout-disabled).

`getPremiumBillingContext` is a separate secret-free export so Premium can
render the truthful catalog while mutations are withheld. Unless
`STRIPE_BILLING_EXPORTS=enabled`, it reports `checkoutAvailable=false` and
`functions/index.js` does not register Checkout, Portal, webhook or
Auth-deletion Stripe handlers. Enable that flag only in the ordered live
rollout, after every required provider object and secret exists.

That catalog-only callable was deployed to `yovoice-ec54a` on 2026-08-28 and
its production response was verified as EUR 6 monthly, EUR 60 annually,
17% annual savings, `checkoutAvailable=false` and `portalAvailable=false`.
This deploy did not publish any Stripe mutation handler.

## Profile visibility (source only; not deployed)

`setMyProfileVisibility({visibility})` accepts only `public`, `friends` or
`private`, requires an active authenticated profile and uses a private
per-minute rate limit. A non-public transition atomically changes the canonical
private preference, disables website marketing consent, clears public showcase
people and advances `privateShowcaseControl/live.privacyGeneration`. Public
profile search filters candidates against the same canonical value and exact
bilateral friendship guards before returning a bounded projection.

## Deploying

```bash
firebase deploy --only functions --project yovoice-ec54a
```

No CI/CD path deploys functions automatically, and
`functions/package.json`'s own `npm run deploy` only deploys one function,
not all of them — see [DEPLOYMENT.md](DEPLOYMENT.md#cloud-functions-manual)
before assuming otherwise.
