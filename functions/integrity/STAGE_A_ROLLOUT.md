# DM and Voice Moments integrity rollout

Stage A contains injectable backend services and bounded migration helpers. It is
deliberately not exported from `functions/index.js` yet. Direct client writes
must remain available until the migrations, callable clients, Firestore rules,
and Storage rules can be released as one coordinated cutover.

## Preconditions

- Deploy callable wrappers with App Check enforcement staged and server-time
  rate limits enabled. Keep every ledger and `privateRateLimits` document
  server/Admin-only.
- Add TTL or a scheduled bounded purge for completed operation/preflight
  ledgers after the maximum retry window.
- Add composite indexes for:
  - `voiceMoments`: `status ASC`, `createdAt ASC`, document ID ASC.
  - `voiceMomentUploadReservations`: `status ASC`, `expiresAt ASC`, document ID
    ASC.
- Schedule bounded workers for Moment cleanup, abandoned Moment drafts, and
  expired voice-comment reservations. Alert on quarantine/conflict documents.

## Safe release order

1. Export the new callables and scheduled workers without closing legacy reads.
2. Run DM and Moment migration scans in dry-run mode with conservative page
   sizes. Resolve every `directMigrationConflicts` and
   `momentMigrationConflicts` document; never auto-merge an underscore-ID
   collision.
3. Release a client that uses callables for all writes, resolves the pair guard
   for legacy conversation IDs, understands message sequences/read cursors,
   and no longer reads, renders, or searches legacy e-mail fields.
4. Apply bounded migrations. DM migration preserves the existing conversation
   ID/history, creates the canonical pair guard, assigns deterministic message
   sequences, and scrubs `participantEmails`. Moment migration derives canonical
   identities, media, comments, likes, and counters in place.
5. Re-run dry-run scans and verify zero unresolved conflicts, zero schema-v1
   roots/children, zero non-empty DM participant e-mails, and consistent edge
   counts.
6. Deploy restrictive Firestore and Storage rules, then disable all legacy
   direct writers. Keep dual-read only for the short, measured adoption window.
7. Remove the compatibility reader after the minimum supported client version
   is enforced and telemetry confirms no legacy traffic.

## Stage B rule requirements

- Deny client writes to canonical DM roots/messages, pair guards, ledgers,
  private limits, Moment counters/media identity, upload reservations, cleanup
  outboxes, and migration/quarantine records.
- Permit users to read only conversations they participate in and published,
  non-deleted Moment content allowed by block/sanction policy.
- `voice_replies` uploads must require an exact, unexpired
  `voiceMomentUploadReservations/{commentId}` proof matching owner, Moment,
  comment, path, status, content type, size, and custom metadata. Deny overwrite.
- `voice_moments` uploads must require the deterministic schema-v2 draft in
  `status == uploading`; `isPublished == false` alone is not sufficient.
- Add Storage emulator attack tests for arbitrary parent/path, missing/expired
  reservation, forged metadata, overwrite, oversized/wrong-MIME uploads, and
  cross-user reservation reuse.

## Compatibility checks

- Preserve reactions through `setDirectMessageReaction`; users can mutate only
  their own reaction edge.
- Preserve read receipts with paginated `readBy` updates plus the server-derived
  root read cursor. The root unread count reaches zero only after the final page.
- Preserve voice replies through reserve-upload-finalize; never allow an upload
  to create a comment directly.
- Notification and achievement triggers must consume canonical server-created
  message/reaction/comment/like/publish events and must not trust legacy client
  previews, counters, names, or role fields.

## Rollback

Callable deployment can be rolled back while legacy rules remain open. Once
restrictive rules are deployed, rollback must retain the callable layer and
schema-v2 readers; reopening legacy writes is not a safe rollback path.
