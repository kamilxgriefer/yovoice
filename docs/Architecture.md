# Architecture

High-level map of how the system fits together, plus the actual flows a
new engineer needs to hold in their head: how sign-in works, how a write
gets from a tap to Firestore, when a Cloud Function gets involved, and how
a voice connection gets established. For per-layer depth, follow the
links — this file stays a map, not the full reference, so it doesn't drift
as fast as the specifics do.

Ground truth as of the documentation-evolution pass following commit
`26d11a2`. If this drifts from the code, trust the code and fix this file.

## The core architectural choice

This app is built the way Firebase's platform is designed to be used:
**clients read and write Firestore directly**, and **Firestore Security
Rules are the authorization layer** — not a REST API sitting in front of
the database. Cloud Functions exist, but they're the exception path, used
only where rules structurally can't do the job (a secret the client can
never hold, a privilege rules can't safely grant, a side effect the writer
shouldn't have to orchestrate). This single choice explains most of what
otherwise looks unusual about the codebase — why `firestore.rules` is
hundreds of lines of real authorization logic instead of a thin
allow-if-signed-in policy, why `functions/` is comparatively small, and
why a new feature's first design question should be "can Security Rules
express this correctly" before reaching for a Cloud Function. See
[ADR-013](Decisions.md#adr-013-clients-write-firestore-directly-cloud-functions-are-reserved-for-privileged-work)
for the full reasoning and the four conditions that *do* justify a Cloud
Function.

**ADR-115 server-authoritative exception — deployed 2026-08-27.** Voice Moment
root lifecycle is one of the
explicit server-authoritative exceptions to the client-direct model. Capacity
spans multiple roots, publication binds a Storage generation, expiry races
deletion, and deletion must queue cleanup; Security Rules cannot make those
effects atomic. Clients still query published/owned data directly, but reserve,
finalize, root delete, abandoned-media cleanup and expiry belong to Cloud
Functions/Admin workers. Client timers enforce the selected deadline on live
UI, while engagement callables enforce it independently on the write boundary.
This boundary is live in production; see ADR-115 and the retained rollout /
recovery record in
[DEPLOYMENT.md](DEPLOYMENT.md#released-2026-08-27-voice-moment-local-review-custom-availability-and-authoritative-capacity).

**ADR-117 server-authoritative audio exception — deployed 2026-08-27.** A private 1:1
call spans a bilateral permission check, atomic busy locks, ringing delivery,
short-lived LiveKit authority and retryable external room teardown. Rules
cannot make those effects atomic, so Cloud Functions own every status
transition and token; clients receive participant-scoped snapshots and render
the call state. **The following 2026-08-31 video extension is source-only and
not deployed.** It adds immutable `mediaType`
(`audio` or `video`) and LiveKit grants scoped to declared track sources:
microphone for audio, microphone plus camera for video, and no screen-share
label. This constrains the standard SDK but is not proof of capture origin; a
modified client can mislabel a track, so exact media enforcement needs trusted
track inspection. Camera starts only after an explicit video answer, is revoked
locally on backgrounding, and is not auto-restored. The current LiveKit/WebRTC
path is encrypted in transit; it is not application-level E2EE. This is
intentionally separate from the room lifecycle. See ADR-135 and the current
security audit. A broad rollout remains blocked on an authoritative recipient
capability/minimum-build gate and physical two-device testing.

## Two repos, one Firebase project

```
yovoice              → this repo: the Flutter app (mobile + web + desktop)
yovoice-website       → /Users/kamiljaguszewski/yovoice-website, Next.js 16 +
                        React 19 + Tailwind, deployed on Vercel — marketing
                        site, auth, and account pages. Separate deployable,
                        not embedded in this app.
```

Both share Firebase project **`yovoice-ec54a`** — one account, one Auth
domain (`auth.yovoice.app`), one Firestore database, one set of Cloud
Functions. Domain layout:

```
yovoice.app            → Vercel (yovoice-website) — public marketing site
auth.yovoice.app        → Firebase Hosting — shared Auth domain
app.yovoice.app          → Firebase Hosting — the Flutter web build; LIVE
                          since 2026-08-16 (CNAME resolves to
                          yovoice-ec54a.web.app, HTTPS 200)
```

This split — two independent deployables sharing one backend — is itself
a deliberate decision, not just how things happened to end up; see
[ADR-014](Decisions.md#adr-014-two-deployables-one-firebase-project) for
why a single Flutter-web-as-marketing-site or a single Next.js-as-app
approach was rejected.

## Layers, and where to read about each one

```
┌─────────────────────────────┐   ┌─────────────────────────────┐
│   yovoice (this repo)        │   │   yovoice-website             │
│   Flutter — mobile/web/desk. │   │   Next.js — marketing/auth   │
│   see Flutter.md, UI.md      │   │   see that repo's own docs   │
└───────────────┬───────────────┘   └───────────────┬───────────────┘
                │                                     │
                │        both write Firestore          │
                │        directly, both authenticate    │
                │        against the same Firebase Auth │
                └───────────────┬─────────────────────┘
                                 ▼
                  ┌───────────────────────────────┐
                  │   Firebase (yovoice-ec54a)     │
                  │   Auth, Firestore, Storage,     │
                  │   Hosting, App Check, FCM       │
                  │   see Firebase.md, SECURITY.md    │
                  └───────────────┬───────────────┘
                                 │  only for privileged/secret/
                                 │  fan-out work — see ADR-013
                                 ▼
                  ┌───────────────────────────────┐
                  │   Cloud Functions (Node)         │
                  │   admin/friends/clubs/livekit/    │
                  │   notifications                  │
                  │   see Backend.md                 │
                  └───────────────┬───────────────┘
                                 │
                                 ▼
                       LiveKit Cloud (voice)
```

- **[Flutter.md](Flutter.md)** — app structure, state management, feature
  modules, dev setup and commands.
- **[UI.md](UI.md)** — design system status: Material 3, the theme/shared
  widget system, the inline-hex convention most screens still use, and the
  "Coming soon" pattern.
- **[Firebase.md](Firebase.md)** — Firestore schema/collections, Storage
  rules, Auth setup, App Check, email delivery.
- **[Backend.md](Backend.md)** — the Cloud Functions codebase: what each
  function does, LiveKit token minting, notification triggers.
- **[Features.md](Features.md)** — what's actually built, feature by
  feature.
- **[PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)** — the physical repo
  layout, directory by directory.
- **[SECURITY.md](SECURITY.md)** — the security model as a whole: auth,
  rules design principles, secrets, current posture.
- **[DEPLOYMENT.md](DEPLOYMENT.md)** — what deploys automatically, what's
  manual, and how.
- **[TESTING.md](TESTING.md)** — what test coverage exists and what
  doesn't.
- **[DEPENDENCIES.md](DEPENDENCIES.md)** — why the key third-party
  packages were chosen.
- **[Decisions.md](Decisions.md)** — the full ADR log: why things are the
  way they are.
- **[Bugs.md](Bugs.md)** — current known issues.

## Authentication flow

Firebase Authentication (email/password + Google Sign-In) is the single
identity provider for both deployables, via the shared `auth.yovoice.app`
domain — a user who registers in the Flutter app can log into the website
with the same credentials and vice versa, with no account-linking step
required, because there was only ever one account.

```
 Flutter app  or  website
       │
       │ 1. signUp() / signIn()
       ▼
 Firebase Authentication  (auth.yovoice.app)
       │
       │ 2. on register: sendEmailVerification()
       │    (via Resend SMTP — ADR-008, not Firebase's default sender)
       ▼
 User clicks the emailed link
       │
       ▼
 Firebase's own hosted action page confirms the email
 (deliberately NOT a custom handleCodeInApp deep link — see ADR-008)
       │
       │ 3. client calls reload() to pick up the fresh emailVerified flag
       │    (the cached User object never updates this on its own)
       ▼
 request.auth.token.email_verified == true
       │
       ├─→ Firestore rules gate content-creation writes on this claim
       └─→ Cloud Functions gate privileged calls on this claim
           (e.g. bootstrapSuperAdmin — see ADR-003)
```

Role/permission state (`superAdmin` and the staff roles used by privileged
Cloud Functions) requires a signed **Firebase Auth custom claim**. Privileged
requests also compare that claim with the server-written, client-immutable
`users/{uid}.role` mirror so a revocation takes effect before a stale token
expires. The mirror alone is never staff authority. See
[SECURITY.md](SECURITY.md#identity-and-roles).

## Data flow: a concrete example (joining a Broadcast Room)

Rather than describe Firestore/Cloud-Functions/LiveKit interaction in the
abstract, here's one real flow that touches all three, in the order it
actually happens:

```
1. User taps "Join" on a live Broadcast Room
        │
        ▼
2. RoomService.joinRoom(roomId) — CLIENT-DIRECT FIRESTORE WRITE
   Runs a Firestore transaction that:
     - reads the room doc (checks it's active and live)
     - reads the caller's own participant doc (no-ops if already joined)
     - writes a new rooms/{roomId}/participants/{uid} doc:
       role='listener' (or 'host' if this is the room's own host),
       isSpeaker=false, isMuted=<room's autoMuteNewUsers setting>
     - increments the room's participantCount
   No Cloud Function involved — Firestore Security Rules alone authorize
   this write (see Firebase.md's participants rule).
        │
        ▼
3. VoiceTokenService calls the createLiveKitToken CLOUD FUNCTION
   This is a case where a Cloud Function is required, not optional:
   minting a valid LiveKit token needs LIVEKIT_API_SECRET, which no
   client can ever hold (condition 1 of ADR-013).
        │
        ▼
4. createLiveKitToken (functions/livekit/token.js), server-side:
     - looks up the room and the caller's OWN participant doc just
       written in step 2 — 404s if either is missing
     - computes canPublish = (isHost || isSpeaker) && !isMuted from
       that real, just-read data — never from anything the client's
       token request claims
     - mints a LiveKit AccessToken scoped to that room, with those
       real permissions
        │
        ▼
5. Client connects to LiveKit Cloud with the returned token
   Voice starts flowing. If the user is later muted by a moderator,
   that's a Firestore write to their participant doc (step 2's shape)
   PLUS a LiveKit Server API call to revoke already-issued permissions
   — the token itself doesn't expire just because Firestore changed.
```

**The step this diagram used to omit, and what it cost.** Step 2 reads the
room doc and *checks* that it is active and live; nothing above says who
makes it live. That transition is the **caller's** job, and until `b0f1062`
only `enterClubLounge` ever performed it — so `createLiveKitToken` refused a
token and **voice did not work in any Community room or lounge**, for the
product's life (production at the time: 45 rooms, 3 live). A liveness step
now runs first, in one coordinator ordering **liveness → roster → token**,
for anyone the deployed rules would accept. Read it as **step 1.5** of the
flow above. The generalizable form: when a server precondition exists,
document the caller that satisfies it in the same place you document the
check, or the check reads as if something else guarantees it. See
[ADR-088](Decisions.md#adr-088-entering-a-room-performs-the-liveness-transition-through-one-ordered-coordinator-that-mirrors-the-deployed-rule)
and [ADR-082](Decisions.md#adr-082-a-feature-is-not-shipped-until-a-user-can-reach-it--reachability-is-part-of-done-and-a-green-suite-cannot-prove-it).
This is **source state, not production state** — see
[DEPLOYMENT.md](DEPLOYMENT.md#pending-release-the-2026-08-1920-reachability-wave).

The pattern to notice: **step 2 is a plain client-direct write** (the
default per ADR-013), while **step 3–4 is a Cloud Function** specifically
because it needs a secret — not because "voice stuff" is inherently
special. A different room-related write (changing the room's title,
raising a hand, sending a chat message) follows step 2's pattern all the
way through, no Cloud Function involved at all. See
[Backend.md](Backend.md#livekit-token-minting) for the full token-minting
logic and [Firebase.md](Firebase.md#firestore-schema) for the schema this
flow reads and writes.

## Firestore interaction

Almost every read in the app is a `Stream` from a Firestore query,
consumed directly by a `StreamBuilder` in the UI — there is no API layer
translating between "what the screen needs" and "what's in the database."
This is fast to build against and keeps data reactive for free (a
moderator's mute shows up on the muted user's screen the moment Firestore
propagates it, no polling), but it also means:

- **The schema is part of the public contract.** Every screen that reads
  a collection is coupled to its exact field names and shapes — there's no
  API version to insulate a schema change behind. See the "never break the
  schema" rule in [CLAUDE.md](../CLAUDE.md) and
  [Firebase.md](Firebase.md#firestore-schema) for what's actually in it.
- **Security rules are the only thing standing between a signed-in user
  and the raw database.** A bug in a rule is not a bug in one feature —
  it's a bug in the authorization system itself. See
  [SECURITY.md](SECURITY.md) for the design principles this project has
  learned (often the hard way — [ADR-003](Decisions.md#adr-003-security-fixes-move-permission-authority-to-the-server))
  to hold rules to.
- **Query shape is constrained by what rules can prove.** The
  `collectionGroup()` incidents behind
  [ADR-005](Decisions.md#adr-005-roomsroomidmembers-renamed-to-roommembers)
  through [ADR-007](Decisions.md#adr-007-firestore-rules-changes-are-always-emulator-tested-against-a-real-collectiongroup-query)
  exist because this constraint is easy to violate without realizing it
  until the query fails in production.

## Cloud Functions interaction

Cloud Functions are called two ways in this app: `httpsCallable()` for
client-initiated calls (LiveKit tokens, admin actions, self-service club
ownership transfer), and Firestore triggers for server-initiated reactions
to a write (`onNotificationCreated` turning a notification document into a
push). Neither path mediates the *ordinary* Firestore writes described
above — see [ADR-013](Decisions.md#adr-013-clients-write-firestore-directly-cloud-functions-are-reserved-for-privileged-work)
for exactly which four situations justify reaching for a function instead
of a direct write, and [Backend.md](Backend.md) for the full inventory of
what exists today.

## Premium billing boundary (source-ready; provider rollout disabled)

Premium billing is another explicit server-authoritative exception to the
client-direct model. The client may request only the allowlisted contract
`{plan, paymentMethod?}`. `paymentMethod` defaults to `recurring`,
which opens hosted Checkout with card and PayPal for either the EUR 6 monthly
or EUR 60 annual subscription. `blik` opens a separate one-time Checkout:
PLN 26 grants 30 days on the monthly plan, while PLN 260 grants 365 days on
the annual plan. Neither BLIK purchase renews automatically.

Cloud Functions, not either client, bind that request to immutable Stripe
Prices, Checkout mode, permitted payment methods and fixed return URLs. A
Checkout redirect never grants access. Signed Stripe webhooks re-read the
canonical provider object and project the paid period into the server-owned
`entitlements/{uid}` document. Recurring card/PayPal access follows the
Subscription and paid-Invoice lifecycle; both BLIK offers follow the
successful one-time payment and are represented from the start as fixed
prepaid windows with no renewal.

The secret-free `getPremiumBillingContext` catalog was deployed to production
on 2026-08-28 and reports `checkoutAvailable=false`; no provider mutation
handler, provider configuration or public checkout is live. Rollout remains
disabled until the four live Prices,
PayPal, BLIK, Portal, signed webhook, legal copy and reconciliation gates in
[DEPLOYMENT.md](DEPLOYMENT.md#stripe-premium-rollout-source-ready-provider-rollout-disabled)
pass. Production project `yovoice-ec54a` accepts live Stripe objects and
credentials only; Stripe test mode belongs to local/emulator or a future
non-production project and must never be configured in production. See
[ADR-118](Decisions.md#adr-118-premium-pairs-recurring-eur-with-non-renewing-prepaid-blik).
The deployed catalog remains renderable while
`STRIPE_BILLING_EXPORTS!=enabled`; that operator flag withholds Checkout,
Portal, webhook and Auth-deletion billing exports and reports checkout as
unavailable.

Moderator product verification is deliberately independent of billing.
Active accounts whose exact role is `moderator` or `superModerator` receive a
derived Premium-preview overlay for identity, Creator and Clubs. Acting Rules
and callables require the signed claim to exactly match the server role mirror;
background/public projections use the client-immutable mirror because they
cannot inspect another account's token. The overlay never writes or changes
`entitlements/{uid}`, a plan, period, renewal state or provider source, and it
does not confer any additional moderation or ownership capability. Demotion,
ban, disablement or deletion removes it independently of paid access. See
[ADR-119](Decisions.md#adr-119-moderator-premium-preview-is-a-derived-product-benefit-not-a-paid-entitlement).

Auth claims and Firestore cannot change atomically. A privileged-to-privileged
role change therefore passes through a fail-closed `role=user` mirror with the
server-only `roleTransitionInProgress=true` marker. Authority is unavailable
while the claim and mirror differ. Destructive Creator cleanup and the website
showcase defer while an active profile carries the marker; paid billing truth
still expires normally, and missing/deleted accounts are never deferred. The
final role mirror clears the marker and retriggers convergence.

## LiveKit interaction

Summarized in the data-flow example above; full detail — token structure,
secrets handling, what happens on mute/remove — lives in
[Backend.md](Backend.md#livekit-token-minting). The one thing worth
repeating here because it's easy to get backwards: **the Flutter client
never has access to `LIVEKIT_API_SECRET` and never computes its own
publish permissions.** Every voice permission a client ends up with was
computed server-side, from real Firestore state, by `createLiveKitToken`.

## Website integration

`yovoice-website` is a fully separate Next.js codebase — no shared UI
components, no shared Dart/TypeScript code — that integrates with this
project at exactly two points:

1. **Shared Firebase project.** Same Auth users, same Firestore database,
   same Cloud Functions. The website's own Firebase client config points
   at `yovoice-ec54a`, same as this app's `lib/firebase_options.dart`.
2. **Shared Auth domain** (`auth.yovoice.app`), which is what makes "one
   account, works everywhere" true without any account-linking code on
   either side — Firebase Auth sessions issued under that domain are valid
   for both.

Both clients read Firestore directly under the same Security Rules —
rules don't know or care which client is asking. This means a Firestore
schema change is a **two-codebase change** in practice, even though only
one of those codebases lives in this repo — see
[ADR-014](Decisions.md#adr-014-two-deployables-one-firebase-project) for
the tradeoff this represents and `yovoice-website`'s own docs for its
internals.

> **CORRECTION, 2026-08-16 — read this before writing website code that
> touches user identity.** Until this date, this section told the website
> it could query "a user's profile, their rooms, their settings" directly
> from Firestore under the same rules. **That is no longer true for user
> identity, and any website code still written against it is broken in
> production right now.** The ADR-054 privacy rules were deployed to
> production on 2026-08-16: `users/{uid}` is now **owner-`get` only and
> not listable by anyone**, including moderator and super-admin client
> sessions. A website query against `users` — by uid, by username, by
> email, or a `list` of any kind — fails closed.

What the website must use instead, all of it live in production as of
2026-08-16:

| Need | Path |
|---|---|
| Another account's public identity | `get publicProfiles/{uid}` — known id only, never `list` |
| Online / last-seen | `get socialPresence/{uid}` — self, or both server-owned `friendshipGuards` must exist |
| Finding a person by name/username | the `searchPublicProfiles` callable — bounded prefixes, per-uid quota |
| Finding a person by email | staff-only, through the protected owner directory callable |
| The signed-in account's own record | `get users/{uid}` for that same uid — still allowed |

`publicProfiles` is server-owned: no client of either codebase can write
it. Full model in [SECURITY.md](SECURITY.md#private-account-records-and-public-profiles),
schema in [Firebase.md](Firebase.md#firestore-schema), decision in
[ADR-054](Decisions.md#adr-054-private-account-records-are-split-from-exact-server-owned-public-profiles),
executed cutover in [ADR-055](Decisions.md#adr-055-the-2026-08-16-production-cutover--order-the-deploy-by-what-fails-closed-and-verify-by-fingerprinting-served-bytes).

**Known live gap the website will hit**: the projection is written by a
trigger on `users/{uid}`, so accounts that have not been written since the
cutover have no `publicProfiles` document and are invisible. Production
held **33** `users` documents and **1** `publicProfiles` document when
counted in the Firebase console on 2026-08-16. Design website surfaces to
render a missing projection as "not available" rather than assuming a
document exists — see [Bugs.md](Bugs.md#data-integrity).

## Deployment overview

Summary only — full detail, including the CI workflow's exact steps, is in
[DEPLOYMENT.md](DEPLOYMENT.md).

- **This repo's Flutter web build** is *verified* automatically on every
  push to `main` (analyze, Flutter tests, all three rules suites, the
  Functions suite, then the release build) but **is not published by that
  push**. Releasing to Hosting is a manual `workflow_dispatch` with
  `deploy_hosting: true`.
  **CORRECTION, 2026-08-16:** this section previously said the web build
  "deploys automatically to Firebase Hosting on every push to `main`".
  That stopped being true in `409c7ee`, which split verification from
  release. The old wording is what let production sit on commit `9fdd8a9`
  while `main` moved on — see
  [ADR-055](Decisions.md#adr-055-the-2026-08-16-production-cutover--order-the-deploy-by-what-fails-closed-and-verify-by-fingerprinting-served-bytes).
- **Firestore rules/indexes, Storage rules and Cloud Functions** deploy
  manually, on purpose — see
  [DEPLOYMENT.md](DEPLOYMENT.md#why-rulesfunctions-are-tested-but-not-auto-deployed)
  for why that's a deliberate choice, not a gap.
- **`yovoice-website`** deploys automatically to Vercel on push to `main`
  in that separate repo.

## Third-party services

- **LiveKit Cloud** — voice room infrastructure.
- **Resend** — transactional email (verification, password reset), via
  Firebase Auth's custom SMTP settings ([ADR-008](Decisions.md#adr-008-resend-smtp-instead-of-firebases-default-email-sender)).
- **Stripe** — hosted Premium Checkout, recurring billing, the customer
  cancellation portal and signed payment webhooks; source-ready, provider
  rollout disabled.
- **PayPal** — an optional recurring payment method presented inside Stripe
  Checkout after the Stripe account is approved and enabled; YO Voice does not
  integrate a second entitlement authority.
- **Vercel** — hosts `yovoice-website`.

See [DEPENDENCIES.md](DEPENDENCIES.md) for why these specific services and
packages were chosen over the obvious alternatives.
