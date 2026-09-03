# Reels Build 19 integration manifest

The feature module is complete, but intentionally does not mutate shared
navigation, root exports, Security Rules, indexes, localization catalogs or
release metadata. Apply every item below before exposing Reels to testers.

## 1. Runtime dependencies

- Flutter: `video_player ^2.14.0`, `file_selector ^1.1.0`.
- Functions: exact pin `music-metadata 11.15.0` on Node 18 or newer.
- Keep existing `image_picker`, `audioplayers`, `firebase_storage`,
  `cloud_functions` and `url_launcher` dependencies.

## 2. Cloud Functions exports

Add after `strictBooleanEnvironment` is available in `functions/index.js`:

```js
const { createReelFunctions } = require("./reels");
Object.assign(exports, createReelFunctions({
  enforceAppCheck: strictBooleanEnvironment(
    "YOVOICE_ENFORCE_REELS_APP_CHECK",
  ),
}));
```

Registered names are:

- `reserveReelDraft`
- `finalizeReelDraft`
- `listReels`
- `getReelMediaAccess`
- `deleteReel`
- `createReelReport`
- `expireAbandonedReelDraftsSchedule`
- `processPendingReelCleanupSchedule`
- `onReelCleanupOutboxCreated`

App Check must follow the staged project rollout. Do not enable enforcement
until iOS, Android and Web attestation telemetry is healthy.

## 3. Flutter route

Expose `ReelsFeedScreen`. Its `onCreate` callback must complete only after the
composer route closes; the feed then refreshes itself.

```dart
ReelsFeedScreen(
  onCreate: () async {
    await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const ReelComposerScreen(),
      ),
    );
  },
)
```

Use a stable product destination (More or a dedicated route); do not overload
the central voice action without an explicit product decision. On sign-out,
call `ReelService.clearAllMediaAccessCaches()` before changing auth state.

## 4. Firestore Rules

All Reel reads/writes are callable-mediated. Add explicit client denial:

```text
match /reels/{reelId} {
  allow read, write: if false;
}
match /reelUploadReservations/{reelId} {
  allow read, write: if false;
}
match /reelCleanupOutbox/{outboxId} {
  allow read, write: if false;
}
match /integrityOperationLedgers/{ledgerId} {
  allow read, write: if false;
}
```

`reports` already permits active staff reads and denies direct workflow
updates. Reel reports are written by the callable in the existing canonical
shape: `targetType`, `targetId`, `reportedUserId`, `contextPath`, `reason`,
`note`, `status`, and timestamps.

## 5. Storage Rules

Add a private reservation-bound match under `/b/{bucket}/o`. The rule must use
the existing `isVerified()` and `isActiveUser(userId)` helpers.

```text
match /reels/{userId}/{reelId}/{fileName} {
  function reservationPath() {
    return /databases/(default)/documents/reelUploadReservations/$(reelId);
  }

  function liveReservation() {
    let path = reservationPath();
    return firestore.exists(path) &&
        firestore.get(path).data.schemaVersion == 1 &&
        firestore.get(path).data.status == 'uploading' &&
        firestore.get(path).data.ownerId == userId &&
        firestore.get(path).data.reelId == reelId &&
        firestore.get(path).data.expiresAt is timestamp &&
        firestore.get(path).data.expiresAt > request.time;
  }

  function exactMetadata(metadata, kind) {
    return metadata.keys().hasOnly(['ownerId', 'reelId', 'assetKind']) &&
        metadata.ownerId == userId &&
        metadata.reelId == reelId &&
        metadata.assetKind == kind;
  }

  function reservedMedia(size, contentType, metadata) {
    let reservation = firestore.get(reservationPath()).data;
    return exactMetadata(metadata, 'media') &&
        reservation.mediaStoragePath ==
            'reels/' + userId + '/' + reelId + '/' + fileName &&
        reservation.mediaContentType == contentType &&
        reservation.mediaSize == size &&
        size >= 128 &&
        (
          (
            reservation.mediaKind == 'image' &&
            size <= 10 * 1024 * 1024 &&
            (
              (fileName == 'media.jpg' && contentType == 'image/jpeg') ||
              (fileName == 'media.png' && contentType == 'image/png') ||
              (fileName == 'media.webp' && contentType == 'image/webp')
            )
          ) ||
          (
            reservation.mediaKind == 'video' &&
            size <= 100 * 1024 * 1024 &&
            (
              (fileName == 'media.mp4' && contentType == 'video/mp4') ||
              (fileName == 'media.mov' && contentType == 'video/quicktime') ||
              (fileName == 'media.webm' && contentType == 'video/webm')
            )
          )
        );
  }

  function reservedAudio(size, contentType, metadata) {
    let reservation = firestore.get(reservationPath()).data;
    return reservation.hasBackingAudio == true &&
        exactMetadata(metadata, 'backingAudio') &&
        reservation.backingAudioStoragePath ==
            'reels/' + userId + '/' + reelId + '/' + fileName &&
        reservation.audioContentType == contentType &&
        reservation.audioSize == size &&
        size >= 512 && size <= 15 * 1024 * 1024 &&
        (
          (fileName == 'backing-audio.mp3' && contentType == 'audio/mpeg') ||
          (fileName == 'backing-audio.m4a' && contentType == 'audio/mp4') ||
          (fileName == 'backing-audio.wav' && contentType == 'audio/wav')
        );
  }

  function reservedAsset(size, contentType, metadata) {
    return liveReservation() &&
        (
          reservedMedia(size, contentType, metadata) ||
          reservedAudio(size, contentType, metadata)
        );
  }

  // Metadata recovery is limited to the uploader while the exact reservation
  // is live. Published playback always uses a generation-bound V4 grant.
  allow get: if isActiveUser(userId) &&
      reservedAsset(resource.size, resource.contentType, resource.metadata);
  allow list: if false;
  allow create: if resource == null && isVerified() &&
      isActiveUser(userId) &&
      reservedAsset(
        request.resource.size,
        request.resource.contentType,
        request.resource.metadata
      );
  allow update, delete: if false;
}
```

Compile and emulator-test the merged rule file before deployment.

## 6. Indexes

No new composite index is required by this module:

- feed: `reels.orderBy(sortKey desc)` (single field),
- reservation expiry: range/order on `expiresAt` (single field),
- cleanup queue: equality on `status` (single field).

If the moderation UI adds a Reel-only queue, its existing
`status + createdAt` report index remains sufficient unless it also combines
`targetType`; that optional filtered view needs
`reports(targetType ASC, status ASC, createdAt DESC)`.

## 7. Moderation integration

Add `reel` to Flutter `ReportTargetType` and its localized filter label. Extend
`moderateReport` so `removeAndResolve` for a Reel updates the same transaction:

```js
transaction.update(db.collection("reels").doc(String(report.targetId)), {
  moderationStatus: "hidden",
  updatedAt: FieldValue.serverTimestamp(),
});
```

Keep bytes for evidence/appeal. Author deletion already tombstones the Reel
and enqueues private media cleanup. A moderator restore path may set
`moderationStatus: "visible"` after review; it must never accept a client
write.

## 8. Localization catalog additions

English and Polish are supplied inline. Add every new English key used under
`lib/features/reels` to all non-English translation catalogs before release.
The groups are:

- feed/state: Reels, loading, empty, create, retry, unavailable;
- playback: play/pause/open video and backing audio;
- composer: media sources, caption, crop, filter, trim, overlays, licensed
  audio attestation, publish progress;
- lifecycle: delete confirmation/success/failure;
- safety: report reasons, confidentiality, success/failure.

Run the repository localization catalog integrity test after merging.

## 9. Trusted media probe reuse

`createTrustedGcsMediaProbe(bucket)` in `probe.js` supports generation-bound
GCS streams for MP4, MOV, WebM, MP3, M4A and WAV. The same helper is safe for
DM video only if the DM pipeline independently verifies its canonical path,
owner, generation, metadata, magic bytes, byte cap and duration policy before
and after probing. Duration returned by the client is display/edit metadata;
never use it for authorization or quota enforcement.

## 10. Known product boundary

Crop, filters, trim, text/link overlays and user-owned backing audio are a
non-destructive composition recipe rendered by YO Voice. This MVP does not
transcode or bake a new distributable video. It deliberately does not ingest
or download Spotify, Apple Music or other catalog audio. A future immutable
export requires a licensed media catalog plus a sandboxed transcoding,
thumbnail and content-scanning worker.
