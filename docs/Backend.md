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
→ `NotificationService.setPreference`).

## Friends

- `getMutualFriends` — mutual-friend lookup for a given pair of users.
- `getFriendSuggestions` — friend-suggestion logic.

## Clubs

- `transferClubOwnershipSelf` — self-service ownership transfer (owner
  hands off to another member).

## Admin

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
