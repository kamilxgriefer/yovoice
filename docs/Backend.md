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

## Notifications

`onNotificationCreated` (`functions/notifications/push.js`) — a Firestore
`onDocumentCreated` trigger on `users/{userId}/notifications/{id}`. The
Flutter client writes the notification document directly (see
`firestore.rules`); this trigger is what turns "a notification doc exists"
into an actual push via FCM. Has a title-builder per notification type,
mirroring the in-app copy in `app_notification.dart`, and respects each
user's per-type notification preferences (`notification_preferences_screen.dart`
→ `NotificationService.setPreference`). The shared, unit-tested payload sets
the high-importance `yovoice_default` Android channel with default sound and
vibration, APNs default sound with active interruption level, and web icon/
badge metadata.

## Friends

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
  rollout sequence in [DEPLOYMENT.md](DEPLOYMENT.md#private-profile-projection-cutover-strict-order).
- `onAuthUserDeleted` — Auth deletion trigger that retires public identity,
  badges/directory projections and marks any lingering private account record
  inactive, preventing an Auth orphan from being republished.
- Social-graph callables own all friend/follow/block writes. Request acceptance
  creates paired private `friendshipGuards` atomically; unfriend/block removes
  them atomically. Transactional per-user quotas, hard graph caps and
  `MAX + 1` bounded reads prevent unbounded fan-out and oversized-graph oracles.

## Direct messaging, Moments and achievements

Recent hardening moved these feature writes from client-authored side effects
to server-authoritative callables:

- `openDirectConversation`, `sendDirectMessage`, `editDirectMessage`,
  `deleteDirectMessage`, `setDirectConversationPreference`, `markDirectConversationRead`,
  `setDirectMessageReaction`, `setDirectTyping` in `functions/index.js`.
- `reserveMomentDraft`, `finalizeMomentDraft`, `reserveVoiceCommentDraft`,
  `finalizeVoiceCommentDraft`, `createMomentComment`, `deleteMomentComment`,
  `deleteMoment`, `setMomentLike`.
- `selectMyAchievementTitle`.

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

## Clubs

- `transferClubOwnershipSelf` — self-service ownership transfer (owner
  hands off to another member).

## Admin

**Deployment status (verified against `firebase functions:list`,
2026-08-08): none of the functions in this section are deployed.** They
are implemented and exported in `functions/index.js`, but no admin UI
exists anywhere (the website's `src/app/admin/` is an empty
placeholder), so there are no callers — and keeping powerful moderation
endpoints undeployed until something actually needs them is the safer
default. Deploy them together with whatever admin surface is built
first.

Every admin function requires a `role` custom claim via `requireRole()` —
roles come from Auth custom claims, never from a Firestore field, which
closes off the most common privilege-escalation path (a user editing their
own `users/{uid}` document can't grant themselves admin).

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

## Deploying

```bash
firebase deploy --only functions --project yovoice-ec54a
```

No CI/CD path deploys functions automatically, and
`functions/package.json`'s own `npm run deploy` only deploys one function,
not all of them — see [DEPLOYMENT.md](DEPLOYMENT.md#deploying-functions-manual)
before assuming otherwise.
