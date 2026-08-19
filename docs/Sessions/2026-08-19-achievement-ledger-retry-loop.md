# 2026-08-19 — Achievement ledger retry loops and the wedged reconciler

One session took the reported incident — `onAchievementRoomMessageCreated`
retrying `AchievementEventIntegrityError: Canonical source collision`
forever on two ledger ids — from forensics through fix, tests, deploy and
production repair. Full decision record in ADR-081.

## What was actually happening

1. **Three retry loops, not two, across two functions.** Production
   forensics (read-only Admin SDK inspection of `achievementEvents`)
   proved both reported ids are `activeDay` entries whose doc id and
   `sourceKeyHash` re-derive exactly from (uid, UTC day 2026-08-18) — and
   found a third unreported loop on `onAchievementDirectMessageCreated`
   (`v1_3c2af0…`), plus one id (`v1_96d81c…`) looping from *both* a room
   message and a DM. Root cause: `adaptActiveDay` keyed identity on the
   UTC day but fingerprinted the triggering event's exact time, so the
   second qualifying action of any user-day derived the same eventId with
   a different fingerprint — a permanent mismatch the engine answered by
   throwing, which `retry: true` turned into redelivery every 1–3 minutes.
   Not build drift: latent since the 2026-08-16 launch (the achievements
   module had zero commits between launch and incident); it first tripped
   2026-08-18 17:34Z when a user first acted twice in one UTC day.
2. **`reconcileAchievementsV1` had been wedged since its first run ever**
   (2026-08-16 18:40Z — doc `createTime` evidence), on the *first* user in
   the collection: a presence-only skeleton profile made
   `legacyProgressFromUser` return `undefined` fields, Firestore rejected
   the bootstrap write, `failUser` merge-created a partial record, and
   `beginUser` rejected that record as malformed on all ~96 runs/day while
   `afterUid` stayed `null`. Different root cause, same
   fail-closed-forever shape. The "3× on 2026-08-18" from the report was a
   partial view of a three-day stream.
3. **Found preventively:** the bootstrap overwrote existing
   `achievementProgress`, which would have erased unreplayable live
   verified progress for the three users the triggers had already reached.

## The fix (ADR-081)

- Engine: fingerprint mismatch → terminal. Same-content-different-time
  recurrences (re-joins, re-reactions, pre-repair redeliveries) replay
  quietly; anything else returns `collision` with a forensic error log.
  Nothing is applied, the stored entry always wins — dedup untouched.
- Sources: `activeDay` content is a pure function of (uid, day) — UTC
  day-start timestamp.
- Migration: undefined-safe bootstrap, self-describing failure records
  with attempt counts, re-init of pre-bootstrap failures (terminal after
  5), contradictory records fail per-user while the run advances, existing
  progress adopted instead of overwritten.

## Verified, not assumed

- 690/690 functions tests green under `emulators:exec`; the 10 new
  regression tests all fail against the stashed pre-fix code (ADR-079's
  A/B discipline).
- Repair script rehearsed in the emulator first — including its
  refuses-on-anomaly gate, uid redaction and idempotent re-runs.
- Deployed all 12 achievement functions 2026-08-19 ~05:30Z; repair applied
  ~05:34Z: 4 activeDay entries rewritten to canonical form (audit fields
  keep the previous fingerprint/time), 1 poisoned migration record
  rewritten well-formed; post-apply dry run reports 4/4 canonical, 0
  poisoned.
- Loops: last `AchievementEventIntegrityError` at 05:36:54Z (rollout
  tail); silent thereafter — Cloud Logging reads at 05:42Z and 05:49Z show
  a ~13-minute gap and counting against the former 1–3-minute cadence,
  spanning several retry intervals of each of the three loops.
- Reconciler: the 05:40:07Z run bootstrapped the formerly wedged user
  (`status: verified`), processed 5 users, advanced `afterUid` off `null`
  for the first time, and logged no malformed-state error. User `1ghm…`'s
  live verified progress (2 messages, 1 active day, 2 titles) survived the
  bootstrap intact.

Remaining watch items: the reconciler now marches the full user collection
(~15-minute pages of 5); any `collision` ERROR log from here on is a real
content divergence worth investigating, not the recurrence noise ADR-081
silenced.
