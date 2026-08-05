# Security

The security model as a whole — what enforces what, the principles this
project has learned to hold itself to (some of them the hard way), and
where to find current status versus historical record. For the day-to-day
mechanics (rules syntax, schema, testing commands), see
[Firebase.md](Firebase.md) and [TESTING.md](TESTING.md); this file is the
model and the reasoning that tie those mechanics together.

## The model in one sentence

Firestore Security Rules are this app's entire authorization layer —
there is no API server standing between a client and the database — so a
bug in a rule is not a bug in one feature, it's a bug in the authorization
system itself. Everything else in this document follows from taking that
sentence seriously. See
[ADR-013](Decisions.md#adr-013-clients-write-firestore-directly-cloud-functions-are-reserved-for-privileged-work)
for why this architecture was chosen anyway.

## Identity and roles

- **Identity**: Firebase Authentication, shared across the Flutter app and
  `yovoice-website` via the `auth.yovoice.app` domain — one account, one
  identity, everywhere. See
  [Architecture.md](Architecture.md#authentication-flow) for the full
  sign-up → verify → claim flow.
- **Email verification is a real gate**, not a UI nicety:
  `request.auth.token.email_verified` is checked directly in Firestore
  rules and Cloud Functions before allowing outbound/content-creation
  actions (posting, creating rooms/clubs/moments, admin bootstrap).
- **Roles live in Auth custom claims, never in a Firestore document.**
  This is the single most load-bearing security decision in the project:
  a user can always write their own `users/{uid}` document (that's how
  profile editing works), but a user can never write their own auth
  token. If role checks ever read from Firestore instead of custom
  claims, self-granting `role: 'superAdmin'` would be a one-line write
  away from any client. Every admin Cloud Function calls a shared
  `requireRole()` helper that reads the claim, not the document — see
  [Backend.md](Backend.md#admin).

## Firestore Security Rules — design principles

These aren't abstract best practices; each one maps to a specific incident
in [Decisions.md](Decisions.md) where violating it caused a real,
production-shipped bug:

1. **Never trust a permission, role, or ownership claim the request itself
   carries.** Check it against a document the requester doesn't control.
   This is [ADR-003](Decisions.md#adr-003-security-fixes-move-permission-authority-to-the-server)
   — the pattern behind nearly every finding in the original security
   audit ([Archive/SECURITY_AUDIT.md](Archive/SECURITY_AUDIT.md)).
2. **`hasOnly()` restricts which fields change, not whether the new values
   are true.** A field-allowlist alone doesn't stop someone from writing a
   *false* value into an allowed field (`likeCount: 999999`) — that needs
   value-level validation (matching a real transaction, or an
   `existsAfter()`/`getAfter()` check against a document they don't
   control), not just a narrower field list.
3. **A `collectionGroup()` query needs a top-level rule the query's own
   filter can prove — full stop.** A nested `match /parent/{id}/collection/{doc}`
   rule, no matter how correct, cannot authorize a `collectionGroup()`
   query spanning that collection name across every parent. See
   [ADR-005](Decisions.md#adr-005-roomsroomidmembers-renamed-to-roommembers)
   and [ADR-006](Decisions.md#adr-006-top-level-collectiongroup-wildcard-rules-stay-read-only-and-narrow)
   for the incident this came from and how narrowly the fix was scoped.
4. **Two collections should never share a subcollection name unless
   they're actually related.** A coincidental name collision
   (`rooms/{id}/members` and `clubs/{id}/members`, unrelated in every way
   except the string `members`) constrains what rules can safely express
   for *either* one. Check this before naming a new subcollection.
5. **Test every rule with the access pattern the app actually uses**, not
   just the easiest one to write a test for. See
   [ADR-007](Decisions.md#adr-007-firestore-rules-changes-are-always-emulator-tested-against-a-real-collectiongroup-query) —
   a rule that only gets `getDoc()`-tested but is actually reached via
   `collectionGroup()` in the app is untested, no matter how green the
   suite looks.

Full schema and the exact current rules structure: [Firebase.md](Firebase.md).

## Storage rules

Four upload paths (profile photos, room images, club images, Voice
Moments audio), each size- and content-type-limited. Uploads tied to
content shown to other users require `email_verified`; profile photos are
deliberately exempt, since setting one during onboarding — before
verification completes — is normal, expected behavior, not a gap. Full
table in [Firebase.md](Firebase.md#storage).

## Secrets

LiveKit's API key and secret are Google Secret Manager secrets
(`defineSecret()` in `functions/livekit/token.js`) — never committed to
the repo, never sent to a client. `LIVEKIT_URL` is a plain `defineString`,
not a secret, since it's just the public WebSocket endpoint every client
needs to connect (equivalent to a hostname, not a credential). No other
Cloud Function in this project currently holds a secret — see
[Backend.md](Backend.md) for the full function inventory.

## Firebase App Check

Integrated client-side; **enforcement is deliberately off** on every Cloud
Function today (`enforceAppCheck: false`). This means a script holding a
valid Firebase Auth ID token — obtained however, not necessarily through a
real instance of this app — can currently call any Cloud Function without
proving it's a genuine client. This is a real, accepted, currently-open
gap, not an oversight: see
[ADR-004](Decisions.md#adr-004-firebase-app-check-integrated-client-side-enforcement-deliberately-off)
for why enforcement needs a monitoring period before it's safe to flip,
and [Bugs.md](Bugs.md#security) for current status.

**What this gap does and doesn't affect**: App Check raises the cost of
casual backend abuse. It does not gate anything that Firestore rules and
each Cloud Function's own authorization checks (principle 1, above)
don't already gate — those remain the actual authorization boundary
regardless of App Check's status.

## Current status

**No known critical open vulnerabilities.** A full audit found 13 issues
(3 critical, 3 high, 6 medium, 1 client/server contract bug); 12 are
fixed, verified directly against current `firestore.rules`,
`storage.rules`, and `functions/` — not assumed from the audit's own
"fixed" claims. Only App Check enforcement remains open, deliberately.
Live-updated detail: [Bugs.md](Bugs.md#security). Full historical audit,
findings, and the exact fix for each: [Archive/SECURITY_AUDIT.md](Archive/SECURITY_AUDIT.md).

## If you find a security issue

This is currently a solo project with no formal disclosure program.
Report anything you find directly to the maintainer
(`kamil.piotr.jaguszewski@gmail.com`) rather than opening a public issue —
the same practice any project handling real user data should follow,
scaled to this project's actual size rather than a boilerplate policy no
one would act on. See [CONTRIBUTING.md](CONTRIBUTING.md) for what this
looks like if the project ever gains outside contributors.

## Checklist for new privileged write paths

Before shipping any new write path that grants a role, a permission, or
access to something another user controls:

- [ ] Does the rule (or Cloud Function) check the claim against a real,
      independently-controlled document — not just against the shape of
      the request?
- [ ] If it's a Cloud Function, does it actually need to be one (see
      [ADR-013](Decisions.md#adr-013-clients-write-firestore-directly-cloud-functions-are-reserved-for-privileged-work)'s
      four conditions), or could a correctly-scoped rule do the same job
      with less latency and less code?
- [ ] If it involves a `collectionGroup()`-queried collection, is there a
      real `collectionGroup()` test for it, not just a direct-path one?
- [ ] Does a value-level check exist where a field's *truth*, not just its
      presence in an allowlist, matters (counters, roles, ownership)?
- [ ] Is a role or permission ever read from a Firestore document that the
      affected user (or an attacker impersonating them) could write? If
      so, that's a bug — move it to a custom claim or a
      Cloud-Function-computed value instead.
