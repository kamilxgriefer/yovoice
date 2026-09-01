# Voice Moment private-media boundary

## Security contract

Published Voice Moments and voice replies store only their canonical Storage
object path, immutable object generation, MIME type and byte size. Firestore
does not store a playable bearer URL. Finalization removes every Firebase
`firebaseStorageDownloadTokens` value before publishing the Firestore record.

Playback calls `getVoiceMomentMediaAccess`. The callable:

1. requires Firebase Authentication and rate-limits the caller;
2. revalidates the caller, the Moment author and (for a voice reply) the reply
   author, including account state, active restrictions and both block
   directions;
3. requires the parent Moment to be published and not past `expiresAt`;
4. validates the current Storage object against its canonical path, custom
   identity metadata, immutable generation, MIME type and size;
5. removes a legacy Firebase download token if one is still present;
6. creates a generation-bound V4 read URL valid for at most 90 seconds and
   never beyond the Moment deadline; and
7. re-runs authorization after signing and before returning the URL, closing
   the Storage/IAM time-of-check-to-time-of-use window.

Storage Rules allow an author to read only their own still-uploading draft or
live voice-reply reservation. Published, expired and finalized media cannot be
read directly through the Firebase Storage SDK. A V4 signed URL is still a
bearer capability for its short lifetime; clients must not log, persist or
share it.

## Client contract

`MomentService.resolveMediaUri` is the only remote playback resolver. It
rejects Firestore `audioUrl`, validates the callable response, accepts only
`https://storage.googleapis.com` on the default port without user-info, and
keys its sub-90-second memory cache by Firebase UID plus Moment/comment ID.
Offline downloads accept only a freshly authorized URI and are stored under a
SHA-256 account key.

Logout coordination must capture the exact UID before Firebase sign-out and
invalidate the process-wide grant cache immediately, then clear that account's
offline media even if Auth state has already disappeared:

```dart
MomentService.clearAllMediaAccessCaches();
await OfflineVoiceMomentService.instance.clearForUser(capturedUid);
```

The cleanup accepts the captured opaque UID after Auth state is gone, is
serialized with every offline mutation, and does not trim or normalize the
UID. The grant cache is shared by every `MomentService` instance, UID-bound,
and epoch-invalidates a response that was already in flight when logout began.

## Migration and rollout

`migrateIntegrityMoment(dryRun: false)` has two distinct phases. Token
hardening is exhaustive across every Firestore-referenced voice reply and runs
even when canonical document migration reports a conflict (including the
bounded comment/like transaction limit). The canonical phase then scrubs
legacy `audioUrl` values while preserving `published`, `expired`, `deleting`
and `uploading` lifecycle semantics and any valid `expiresAt` deadline.

Release must be coordinated because old clients expect durable `audioUrl`
values:

1. grant the Functions runtime service account permission to call IAM
   `signBlob` on itself (normally `roles/iam.serviceAccountTokenCreator`) and
   verify a V4 signed-read smoke test;
2. release/force the private-media-capable clients together with the callable;
3. deploy the restrictive Storage Rules;
4. dry-run, then apply, the Moment integrity migration across every page;
5. verify all results, including conflict ledgers and `mediaHardening` counts;
6. inventory the bucket prefixes `voice_moments/` and `voice_replies/` and
   remove tokens from or delete any unreferenced legacy objects.

Step 6 is an operator/infrastructure gate: a Firestore migration can exhaust
all referenced objects but cannot prove that historical orphan objects do not
exist. P1 must not be declared fully closed in production until the bucket
inventory reports zero durable Firebase download tokens under both prefixes.
