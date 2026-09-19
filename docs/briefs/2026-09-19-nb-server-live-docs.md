# Task 2b — a server channel keeps showing LIVE after everyone has left

Branch `nb/server-live`, base `origin/main` 3.0.0+34 (`f71a2ae2`). Everything
below is **source only and NOT deployed**. This file holds every line the
protected documents need (`docs/Decisions.md`, `docs/SECURITY.md`,
`docs/Servers.md`, `docs/DEPLOYMENT.md`, `docs/Firebase.md`, `docs/Bugs.md`,
`docs/Roadmap.md`), plus the deploy order and the manual steps that are
Kamil's.

## What was wrong

Nothing on the backend reacted to the last participant leaving.
`ServerSessionController.leave()` only disconnected the LiveKit link and was
documented as leaving "any live generation … exactly as they are". A V1
generation was retired by exactly three things: an explicit host/moderator
end, a convergence event (archive, delete, transfer), or the ADR-180 stale
sweep — and that sweep waits for every token the generation issued to expire
plus one grace period, then runs on a five-minute cadence, so the badge
survived the room by roughly 5 to 15 minutes. A channel whose public
`liveness.isLive` was still true while its anchor room was not live was worse:
the sweep only ever scanned `rooms.isLive == true`, so nothing enumerated such
a projection and it stayed LIVE indefinitely. Both the channel rows and the
Start screen's "Teraz na żywo" cards read that one projection, so one
server-side fix covers both surfaces.

## What was implemented

Four commits on `nb/server-live`:

1. `feat(functions): end an empty server channel session after a 60 s grace`
   — the grace engine in `functions/servers/session_staleness.js`, the new
   callable in `functions/servers/sessions.js`, its registration, the sweep
   changes and the projection-drift repair.
2. `feat(functions): let LiveKit room_finished start or finish the empty-channel grace`
   — `functions/achievements/livekit_http.js`.
3. `feat(functions): dry-run-first repair script for stale server channel LIVE badges`
   — `functions/scripts/repair_stale_server_channel_liveness.js`.
4. `feat(servers): tell the backend when this device leaves a live channel`
   — `ServerSessionController.leave()`, `ServerService`, the receipt model.

No `firestore.rules` change, no index change, no client write path.
`noClientChannelLiveness()` still refuses every client write that carries a
`liveness` key, and `channelSessions` is still denied to every client.

---

## docs/Decisions.md — amendment to append under ADR-180

### Amendment — 2026-09-19: an empty generation ends one reconnect grace after the backend observed it empty, never on a client's word

**Context.** ADR-180 bounded a generation whose host vanished, and it did that
job: the sweep needs every token to have expired plus one grace period before
it will act, which is what made a single occupancy reading safe. But "bounded
in about fifteen minutes" is also what a member sees — a channel that says
LIVE with nobody in it — and `CLAUDE.md` forbids exactly that kind of
false-but-number-free signal. Two further gaps were measured while
investigating it: leaving a channel told the backend nothing at all, and a
projection left `isLive: true` while its anchor was not live was outside every
sweep's candidate query (`rooms.isLive == true`), so it never expired.

**Decision.** The session ends when the last participant leaves, after a short
reconnect grace (`EMPTY_GENERATION_GRACE_MS = 60_000`; `decisions.md`,
2026-09-19), and the whole grace is observed and timed by the backend.

`functions/servers/session_staleness.js` records an `emptyObservation`
`{schemaVersion, source, observedAtMillis, maxTokenExpiresAtMillis}` on the
private `channelSessions/{sessionId}` document — a server-clock instant plus
the token bound it was taken at. It is written only when the provider reports
nobody else in the generation's `srv_` room and no `tokenRecipients`
`lastIssuedAt` falls inside `ADMISSION_WINDOW_MS = 30_000`. The generation is
staged for end only when, at least one grace later, the room is **still**
empty (nobody at all, not even the caller) and no token was issued since the
observation. A rejoin inside the grace mints a token, which moves
`maxTokenExpiresAtMillis` and therefore supersedes the observation, so nothing
ends; a departure after a rejoin records a fresh observation and the grace
starts again. Somebody present clears the observation.

Three paths feed that one engine, and all three end a generation through the
**same** writer and worker every authorized end uses —
`stageConvergenceSessionEnd` plus the `sessionEnd` outbox job the existing
dispatcher drains (shared `stageEmptyGeneration`, identity
`digest("server.session.empty.v1", binding)`, so a generation is staged at
most once):

1. **The new callable `releaseServerChannelSessionIfEmptyV1`** (ledger kind
   `server.session.release.v1`), which a client calls after it has left. Its
   authority is an active member with `joinVoice` on the channel **and** a
   `tokenRecipients` record of this exact generation, so a member who never
   joined can neither probe nor end somebody else's session. The provider is
   read once, outside any transaction, with the caller's own identity excluded
   (a clean disconnect may not have reached LiveKit yet). It answers
   `ended | pending | occupied | changed | unknown`, never errors on an
   occupied room, and on `pending` reports how much of the grace is left so a
   live client can ask once more instead of waiting for the next sweep.
2. **The provider's `room_finished`**, consumed by the already-verified
   `receiveLiveKitAchievementWebhook` for `srv_` names and gated on
   `workersEnabled`. It is isolated from voice-time accounting in both
   directions: it runs after the achievement close whatever that close did,
   and nothing it does or throws can change the HTTP answer LiveKit receives.
   The provider's own timestamp may only widen the admission window; it can
   never shorten the grace.
3. **`sweepStaleServerChannelSessionsSchedule`**, which completes an elapsed
   observation, never cuts a running grace short, and keeps ADR-180's
   token-expiry rule unchanged as the fallback for a generation nobody
   observed emptying. The same sweep now also repairs projection drift: it
   pages `clubs where serverSchemaVersion == 1`, reads each server's
   `channels where liveness.isLive == true`, and writes only two provably dead
   shapes — no generation claims the channel (the exact fence
   `session_control.js` applies on a late terminal ACK, projection only), or
   the pointer names an ending/ended/failed/missing session while the anchor
   is idle (pointer and projection cleared, `revision + 1`, like every end
   writer). A live-looking generation whose anchor is idle and whose badge is
   older than `MAX_UNPROVEN_LIVE_AGE_MS` (24 h) has its badge reset only after
   the provider reports its room empty. Everything else is counted
   (`driftUnresolved`) and never written.

**Reasoning.** A grace is the difference between "the room is empty" and "the
conversation is over": a dropped connection, a tunnel, a phone call are all
the same twenty seconds, and ending on the first empty reading would make
rejoining impossible in exactly the moments people need it. But a grace can
only be measured by a clock nobody can lie about, so the observation is a
server-written field on a document no client can read or write, and every
decision re-reads it inside the staging transaction along with the whole
reciprocal graph. Storing the token bound with the observation is what makes
a rejoin self-evident: `maxTokenExpiresAtMillis` moves on every issuance, so
an observation that no longer matches it describes a generation that has been
joined since, and no separate presence state machine is needed. Reusing the
existing end writer keeps the recipient revocation ledger, the terminal
DeleteRoom and every fence reviewed under ADR-174/176/177 applying unchanged;
this amendment still only decides *when*.

The one new field is additive and private. No Rules change is required
(`channelSessions` is denied to clients, `noClientChannelLiveness` keeps them
out of the projection), and no new index: `tokenRecipients.lastIssuedAt`,
`channels.liveness.isLive` and `clubs.serverSchemaVersion` ordered by document
id are all automatic single-field indexes. A collection-group scan for drifted
projections was deliberately avoided for that reason.

**Consequences.**

- A badge now clears about one grace after the last person leaves when the
  leaving client is alive to ask (the callable and its single re-check), about
  one grace plus one sweep cadence when only the provider webhook saw it, and
  on ADR-180's original bound when neither did (an old client with the webhook
  unregistered). The 15-minute figure in ADR-180's Consequences stands only
  for that last case.
- **Accepted eviction trade-off.** Somebody whose token was issued more than
  `ADMISSION_WINDOW_MS` ago and who has still not connected — a very slow
  network, an app suspended between token and connect — can have the
  generation ended under them by a release or a `room_finished` for the
  otherwise empty room. They are revoked by the end worker like everybody
  else and must start a new session; they are never left with a live token
  against a dead generation. The 30 s recent-issuance window and the
  `maxTokenExpiresAtMillis` compare-and-set are the mitigations, and the
  window is deliberately not longer: a window long enough to cover every
  pathological connect would keep an empty badge alive for exactly as long.
- Every uncertainty still fails towards honesty debt rather than eviction: a
  provider error is `unknown` and writes nothing, an answer that cannot prove
  who is in the room counts as occupied, a malformed observation is treated as
  absent, and a projection the classifier cannot prove dead is counted and
  left alone.
- The ADR-180 token rule, kept as the fallback, can still end a generation
  less than a grace after its last departure, but only when no release call
  and no webhook observed the emptiness and no token was issued for at least
  a token TTL plus a grace (about 10 minutes). Closing that last gap needs
  the webhook registered, which is an operator action, not a code change.
- One extra callable: **62 Servers V1 exports** (55 base plus the seven
  Podcast-recording names), and 56 registered callables. The documented
  54-callable table in `docs/Servers.md` is unchanged: like
  `createServerBroadcastIngressV1`, the release signal lives in its own
  registration table. Its options match the other provider-touching
  callables — LiveKit secrets bound, 120 s timeout, `minInstances: 0`, App
  Check as source-configured — and it passes the same runtime activation gate.
- Nothing is deployed and `appConfig/serversV1` is unchanged.

---

## docs/SECURITY.md — new subsection (after "Servers V1 runtime activation authority")

### Ending an empty server channel session (ADR-180 amendment, source only, NOT deployed)

A channel that says LIVE with nobody in it is a false claim about people, so
the fix had to end generations sooner without ever ending one somebody is in.
What holds:

- **The reconnect grace is a backend clock.** The decision reads an
  `emptyObservation` the backend wrote on the private
  `channelSessions/{sessionId}` document, never a timestamp, duration or
  "I left" claim from a client. The new callable's only inputs are the exact
  four ids of `sessionInput`; its answer to a client is a closed set of
  outcome words.
- **Who may signal a leave.** `releaseServerChannelSessionIfEmptyV1` requires
  an active, verified, unrestricted account that is a member with `joinVoice`
  on that channel **and** holds a `tokenRecipients` document for that exact
  generation. A member who never joined cannot use it to probe whether a room
  is empty or to end a conversation they were never in, and a session id from
  another channel does not bind. Every refusal is the same
  `permission-denied`.
- **A release can only ever end an empty room.** The provider is read outside
  the transaction (excluding the caller, whose clean disconnect LiveKit may
  not have processed); completion additionally requires nobody at all in the
  room and no token issued since the observation, and the staging transaction
  re-proves the whole reciprocal graph and compares
  `maxTokenExpiresAtMillis`. A provider error is `unknown` and writes nothing.
  Acting on a generation the caller does not name, or on a newer one, is not
  expressible.
- **Cost is bounded.** Each release charges a dedicated actor-only budget
  (12 per uid per minute) before any target read, and costs at most one
  `ListParticipants`. The budget is separate from the token budget so leaving
  can never starve a rejoin.
- **The webhook boundary is unchanged.** `room_finished` still authenticates
  by HMAC over the exact raw body inside its freshness window; the lifecycle
  hook trusts nothing else from the event, is gated on
  `appConfig/serversV1.workersEnabled`, and cannot change the HTTP answer —
  so a lifecycle fault can never drop voice-time accounting, and a failed
  accounting close can never keep a finished room LIVE.
- **Drift repair writes only provably dead projections**, in a transaction
  that re-reads channel, anchor and session, and never clears a projection
  that names a live generation — the same fence `session_control.js` applies
  on a late terminal ACK. The one-off repair script is dry run by default,
  holds no provider credential, and is idempotent.
- **Schema and Rules.** One additive, server-only field on a document no
  client can read (`channelSessions` stays `if false`), no Rules change, no
  new index, and no new client-writable surface. Clients still learn liveness
  only from the channel's own `liveness` projection.
- **Accepted trade-off, stated plainly:** a token holder who has not
  connected for more than 30 s can be ended under, and must start a new
  session. See the ADR-180 amendment.

---

## docs/Servers.md — replacement and additions

**Replace the paragraph that begins "`isLive` means \"a generation is open\", not
\"people are here\"…" (currently around line 351) with:**

> `isLive` means "a generation is open", not "people are here". A generation
> is now closed from three directions, all of them server-authoritative and
> all of them ending it through the **same** writer and worker every
> authorized end uses (`stageConvergenceSessionEnd` plus the `sessionEnd`
> outbox job): the leaving client's `releaseServerChannelSessionIfEmptyV1`,
> the provider's signed `room_finished` for the generation's `srv_` room, and
> `sweepStaleServerChannelSessionsSchedule` every five minutes. Each of them
> records or completes one empty-generation grace
> (`EMPTY_GENERATION_GRACE_MS`, 60 s, ADR-180 amendment): a server-clock
> `emptyObservation` on the private session document, taken only when the
> provider reports nobody else in the room and no token was issued in the last
> 30 s, and honoured only if the room is still empty a full grace later with
> no token issued since. A rejoin mints a token, which moves
> `maxTokenExpiresAtMillis` and supersedes the observation, so the generation
> survives; a later departure starts a fresh grace. A generation nobody
> observed emptying keeps ADR-180's original bound — every token expired at
> least one grace period ago and the provider reports the room empty or gone.
> A provider error is an unknown, and an unknown never ends a generation. The
> same sweep repairs a public projection that no live generation backs (a
> pointer-less badge, or one naming an ending/ended/failed/missing session
> while the anchor is idle); anything it cannot prove dead is counted in
> `driftUnresolved` and never written. The anchor scan is still the legacy
> sweep's bare `rooms.isLive == true` query, the drift scan is a bounded
> per-server `channels where liveness.isLive == true`, and
> `tokenRecipients.lastIssuedAt` is a single-field index, so no composite
> index is introduced.

**Callable contract note (add under the table):**

> Two callables sit outside this frozen table on purpose and are registered
> from their own tables in `functions/servers/registration.js`:
> `createServerBroadcastIngressV1` (OBS ingress) and
> `releaseServerChannelSessionIfEmptyV1` (the last-leave signal of the
> empty-generation grace). Both bind the LiveKit secrets and pass the same
> runtime activation gate. Registered callables: 56; Servers V1 exports: 62
> (55 without Podcast recording).

**Named activation precondition 4 — append to the existing entry:**

> **The same drill now has to observe three more provider facts** (ADR-180
> amendment), because the release path and `room_finished` act sooner than the
> token-expiry rule did:
> 1. whether `ListParticipants` still lists a participant who has just
>    disconnected cleanly, and for how long (the release callable excludes the
>    caller for exactly this reason, and never ends a generation the provider
>    still reports anybody in);
> 2. how long after the last departure `room_finished` actually arrives (the
>    LiveKit default departure timeout is 20 s; the grace is 60 s, so a
>    `room_finished` normally records the observation and a later pass ends
>    the generation);
> 3. whether an OBS ingress participant of a Community broadcast and an Egress
>    recorder appear in `ListParticipants` — they must, or a broadcast with a
>    stepped-away host would be ended while it is still publishing. Record
>    what was observed.

---

## docs/DEPLOYMENT.md — corrections and the new runbook

**Correction to the Build-19-era deploy table (line 4394),** which still says
the achievement webhook is "Not deployed, and not deployable":

> *(Corrected 2026-09-19: `receiveLiveKitAchievementWebhook` **is** exported
> from `functions/index.js` and has been deployed since 2026-09-07. What is
> still missing is the provider side: the URL is not registered in the LiveKit
> Cloud project, so the function has received no deliveries. Registering it is
> an operator action — see the Servers channel-liveness runbook below.)*

**New runbook section (source only, not deployed):**

> ### Ending an empty server channel session (ADR-180 amendment)
>
> Deploy order, one step at a time, verifying each before the next:
>
> 1. **Cloud Functions.** The changed code is
>    `servers/session_staleness.js`, `servers/sessions.js`,
>    `servers/session_livekit.js`, `servers/registration.js` and
>    `achievements/livekit_http.js`, which the whole Servers V1 surface loads,
>    so deploy the Servers exports and the webhook together rather than three
>    names:
>    `firebase deploy --only functions` (or, if a narrower plan is wanted, at
>    minimum
>    `functions:releaseServerChannelSessionIfEmptyV1,functions:sweepStaleServerChannelSessionsSchedule,functions:receiveLiveKitAchievementWebhook,functions:createServerChannelTokenV1,functions:endServerChannelSessionV1,functions:startServerChannelSessionV1`).
>    `releaseServerChannelSessionIfEmptyV1` is new, so expect a creation, not
>    an update; it binds `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET`, which
>    already exist in Secret Manager. No Firestore Rules, index or Storage
>    deploy is part of this change.
> 2. **Read the deploy back.** `firebase functions:list` shows
>    `releaseServerChannelSessionIfEmptyV1` ACTIVE in `europe-west1`, and the
>    next `sweepStaleServerChannelSessionsSchedule` log line carries the new
>    counters (`stagedEmpty`, `graceRunning`, `driftRepaired`,
>    `driftUnresolved`, `driftTruncated`). `appConfig/serversV1` needs no
>    change: the callable uses the existing `callableAccess` cohort and the
>    sweep and webhook use the existing `workersEnabled`.
> 3. **Register the LiveKit webhook (Kamil, LiveKit Cloud dashboard).** URL
>    `https://europe-west1-yovoice-ec54a.cloudfunctions.net/receiveLiveKitAchievementWebhook`,
>    signed with the same `LIVEKIT_API_KEY` the function already binds. Then
>    confirm deliveries with
>    `firebase functions:log --only receiveLiveKitAchievementWebhook`: a
>    `room_finished` for a `srv_` room logs
>    `livekit server lifecycle handled room_finished` with an outcome of
>    `pending`, `ended`, `occupied`, `not-live` or `unbound`. This also starts
>    voice-time accounting, which has never run — watch for unexpected
>    achievement volume.
> 4. **Repair the existing stale badges (Kamil).** Dry run first:
>    `node functions/scripts/repair_stale_server_channel_liveness.js --project yovoice-ec54a`
>    (needs operator Application Default Credentials; it writes nothing and
>    prints one line per live projection). Review the classifications, then
>    `node functions/scripts/repair_stale_server_channel_liveness.js --project yovoice-ec54a --apply`
>    and finally the dry run again, which must report `writes: 0` and no
>    `reset-*` lines. `unresolved` lines are deliberately left to the sweep
>    and to review; they are not a script failure.
> 5. **App build.** The next TestFlight/Play/web build carries
>    `ServerSessionController.leave()`'s release signal. Every already
>    installed client is covered by the webhook and the sweep without it.

---

## docs/Firebase.md — correction (the `voiceMinutes` bullet, around line 225)

> *(Corrected 2026-09-19: `receiveLiveKitAchievementWebhook` **is** exported
> from `functions/index.js` and deployed. `voiceMinutes` is still zero for
> every account for a different reason: the webhook URL is not registered in
> LiveKit Cloud, so the function receives no events. Registering it (see
> DEPLOYMENT.md) is what starts both voice-time accounting and the
> provider-driven end of an empty channel session.)*

## docs/Bugs.md — line (under Servers / voice)

> - **A server channel kept showing LIVE after everyone left.** Leaving only
>   disconnected the provider link, so the badge survived the conversation by
>   5–15 minutes, and a projection whose anchor was not live never expired at
>   all. **Fixed in source on `nb/server-live` (ADR-180 amendment), not
>   deployed:** a 60 s reconnect grace observed by the backend, ended by the
>   new `releaseServerChannelSessionIfEmptyV1`, by the provider's
>   `room_finished` and by the tightened sweep, which also repairs drifted
>   projections. Needs the Functions deploy, the LiveKit webhook registration
>   and a one-off dry-run-then-apply of
>   `functions/scripts/repair_stale_server_channel_liveness.js`.

## docs/Roadmap.md — line (Done, pending deploy)

> - **Empty server channel sessions end themselves** (ADR-180 amendment,
>   `nb/server-live`): last-leave release callable, provider `room_finished`
>   path, tightened stale sweep with projection-drift repair, and a
>   dry-run-first repair script. Source complete; deploy, webhook
>   registration and the provider drill outstanding.

---

## Deviations from the investigation in `t2b.json`

1. **The grace itself.** The investigation ended a generation the moment the
   room was empty; `decisions.md` requires a ~60 s reconnect grace. The grace
   is implemented server-authoritatively and is the reason for items 2 and 3.
2. **One additive field.** Recording "empty since" needs somewhere to put it,
   so `channelSessions/{sessionId}.emptyObservation` was added: additive,
   server-written, on a document no client can read. The investigation's "no
   schema change" held for a design with no grace; every other field written
   is an existing one, and there is still no Rules or index change.
3. **The sweep keeps ADR-180's admission rule** instead of replacing it with
   "occupancy plus the recent-issuance window" (investigation design 5a). The
   existing staleness tests pin that rule (a young generation is skipped
   without a provider read), and `AGENT_RULES.md` forbids editing an existing
   assertion; more importantly, the grace is what the new paths add, and an
   observation is what carries it. The result: an observed generation ends a
   grace (plus at most one cadence) after it empties, and an unobserved one
   keeps the old bound instead of gaining a shorter one.
4. **The release callable returns `pending` and a remaining-grace hint**, and
   the client asks once more when that hint runs out. The investigation had
   only `ended | occupied | changed | unknown`, because without a grace there
   was nothing to wait for. The hint is capped at two minutes client-side and
   is never authority: the backend re-decides from its own clock.
5. **The repair script does not stage empty generations** and never reads the
   provider. Running it would need the LiveKit secrets on an operator's
   machine; the deployed sweep already does that job with the credential it
   legitimately holds. The script therefore classifies a bound-live
   projection as `ok-live` and a 24-hour-old unprovable one as `unresolved`,
   and repairs only the two dead shapes. Its classification names are
   `ok-live`, `ok-idle`, `reset-null-session`, `reset-terminal-session`,
   `unresolved` and `changed` (the investigation named `ok-live-occupied` and
   `staged-empty`, which need the provider).
6. **Export counts.** The investigation said "21 → 22 V1 exports", which was
   ADR-180's count; the real surface is 61 → 62 (54 → 55 base exports without
   Podcast recording). The registration, independent-QA and cold-start pins
   were updated for exactly that one new name, as `t2b.json`'s
   `existingTestsTouched` planned.
7. **The drift sweep logs counts, never ids.** The investigation suggested a
   `servers.liveness_drift` line carrying ids; the registration suite's
   existing expectation is that this sweep logs no ids at all, and the repair
   script's dry run is the place that names channels.
8. **`ServerSessionController` records its release signal in a separate list
   in the test fake** (`releases`, not `calls`), so the existing pins on what
   a person's press asked for stay byte-for-byte. Worth a reviewer's eye:
   `server_independent_qa_test.dart`'s "leaving releases the link and ends
   nothing server-side" still passes and is still true (leaving ends nothing),
   but leaving does now send one best-effort signal, and that test's reason
   text ("leaving called something server-side; it must not") is the old
   contract. Refresh that wording during integration if you want it to read
   exactly.

## Evidence

- New Functions tests: `servers_session_release.test.js` (9),
  `servers_session_last_leave.test.js` (7),
  `servers_session_room_finished.test.js` (3),
  `servers_liveness_repair_script.test.js` (2), three cases in
  `achievement_livekit_webhook_http.test.js`, two cases in
  `servers_registration.test.js`.
- New Flutter tests: `server_session_release_test.dart` (5), one case in
  `server_service_test.dart`, one case in `home_live_now_test.dart`.
- `functions/test/servers_session_staleness.test.js` (the ADR-180 suite) is
  unchanged and green.
- Whole Functions suite on this Windows machine, run in six batches because
  the shared emulator wrapper caps a run at eight minutes: **2371 tests, 2364
  pass, 7 fail**, and all seven fail identically on `origin/main` for
  environment reasons — four compare `require.cache` keys and paths with `/`
  against Windows `\` (the cold-start module set and three
  `servers_registration*` discovery cases), two assert POSIX file modes
  (`0600`) that Windows does not have, and one spawns a CLI whose `status`
  came back `null` under load. `npm --prefix functions run test:smoke`: exit
  0.
- `firestore.rules`, `storage.rules`, `firestore.indexes.json` and the whole
  `firestore-tests/` directory are byte-identical to `origin/main` on this
  branch. `npm --prefix firestore-tests run test:servers` through the shared
  wrapper reports **68 passed, 3 failed**: the three are the suite's Storage
  cases, which need its own `demo-yovoice-server-acl` project
  (`docs/TESTING.md`), while the shared wrapper pins `--project demo-yovoice`.
  Control: `run test:storage` on the same wrapper passes 76/76, and every
  Firestore case of the server suite passes, including "no client writes
  liveness, including a member holding manage rights on that channel". Re-run
  that suite with the documented project id during integration.

## Deferred / unverified

- **The provider drill is not done** (activation precondition 4 above): every
  local suite proves these paths against a stub adapter. No automated test can
  hold a real LiveKit connection (`docs/TESTING.md`), so the timings — how long
  a cleanly disconnected participant is still listed, when `room_finished`
  arrives, whether an OBS ingress participant is listed — remain an
  observation Kamil has to make and record.
- **Nothing here is deployed**, so the production sweep still runs the old
  code and the webhook still receives nothing.
- The 24-hour max-age reset clears a badge but deliberately leaves the
  private graph (an `activeSessionId` naming an unprovable live session) for
  an operator; such a channel cannot start a new session until that is
  repaired by hand. It is reported by the script as `unresolved`.
