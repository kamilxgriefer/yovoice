# Servers and channels

Working specification, 2026-09-10. The approved architectural direction is a
Server domain facade over the existing `clubs` data graph. The current product
limit is **5 owned Servers for a Free account and 30 for an active Premium
account**. Joining Servers is unlimited for both account types. All five
templates remain in scope.
This document defines the implementation and acceptance contract; it does not
declare that the implementation, migration, media integration or release is
complete.

The original implementation task did not authorize production deployment,
production data migration, publishing or store submission. A subsequent owner
instruction on **2026-09-10 conditionally authorizes a new Apple/Android tester
build only after all requested work and required verification are complete**;
see [the release authorization](Roadmap.md#conditional-tester-release-authorization--2026-09-10).
This does not authorize activation of incomplete held features or waive the
other original approval gates, including production data migration. The source
audit below was performed locally before implementation. No production data
or deployed capability was verified during that audit. Existing unrelated
working-tree changes must be preserved.

## Product and visual authority

The supplied implementation request and accepted references control product
scope. The complete reference folder is
[/Users/kamil/Documents/GitHub/yovoice-server-concepts-2026-09-10](</Users/kamil/Documents/GitHub/yovoice-server-concepts-2026-09-10>).

| Reference | Required use |
| --- | --- |
| [index.html](</Users/kamil/Documents/GitHub/yovoice-server-concepts-2026-09-10/index.html>) | Exact five-card selector, typography, colors, hierarchy and responsive behavior |
| [01-znajomi.png](</Users/kamil/Documents/GitHub/yovoice-server-concepts-2026-09-10/01-znajomi.png>) | Friends: Po godzinach |
| [02-spolecznosc.png](</Users/kamil/Documents/GitHub/yovoice-server-concepts-2026-09-10/02-spolecznosc.png>) | Community: Tech po godzinach |
| [05-podcast.png](</Users/kamil/Documents/GitHub/yovoice-server-concepts-2026-09-10/05-podcast.png>) | Podcast: Między słowami |
| [03-rodzina.png](</Users/kamil/Documents/GitHub/yovoice-server-concepts-2026-09-10/03-rodzina.png>) | Family: Nasz dom |
| [04-firma.png](</Users/kamil/Documents/GitHub/yovoice-server-concepts-2026-09-10/04-firma.png>) | Company: Studio North |
| [PROMPTS.md](</Users/kamil/Documents/GitHub/yovoice-server-concepts-2026-09-10/PROMPTS.md>), [PROMPT-PODCAST.md](</Users/kamil/Documents/GitHub/yovoice-server-concepts-2026-09-10/PROMPT-PODCAST.md>) | Supporting intent and scene descriptions |

Inspect the selector and all five PNGs at full resolution before implementing
or accepting layouts. Reproduce the application interiors, excluding device
frames, presentation captions and concept labels. Reference people, photos,
counts and conversations belong only in isolated test fixtures. A real new
server starts with its owner and empty content.

The production Polish selector uses the exact supplied text **Stwórz swój
serwer.**, **Dla kogo tworzysz miejsce?** and **Wybierz
początek. Potem nadaj mu własny charakter.** Cards appear in this order:
friends, community, podcast, family, company. Selecting a card opens real
configuration; the reference gallery's image modal is not product behavior.
Changing templates preserves the entered name and description. Creation never
starts microphone or camera capture.

Keep Material 3, Inter and the existing theme ownership described in
[UI.md](UI.md). Extend `AppColors`, `AppPalette`, `AppImmersiveColors`,
`SpaceIdentity` and existing typography, spacing, radius and motion tokens;
do not scatter new literal colors through widgets. Server identity must not
redefine platform role/status colors or the global logo.

| Identity | Accepted dark reference colors |
| --- | --- |
| Canvas / raised surface / border / primary text | `#080711` / `#17121F` / `#342A43` / `#F8F5FC` |
| Friends | `#5CE1E6` |
| Community | `#8A2BE2`, `#C026FF` |
| Podcast | `#FF3D68`, `#FF6B81` |
| Family | `#28D17C`, `#35E58D` |
| Company | `#4DA3FF`, `#63C7FF` |

Selector breakpoints are 640 and 1150 logical pixels: vertical compact cards,
then 3+2, then five across. Server screens use available content width and the
existing responsive system: one main surface with a Channels action on narrow
screens, two intentional panels on medium screens, and a compact global rail,
channel panel, main content and optional context panel on wide screens. The
shell owns global navigation; local server tabs do not create five different
global docks. The active conversation dock stays reachable independently of
scrolling and local tab changes. Retain Pearl preferences and documented
immersive-dark surfaces. This task requires **48 logical pixel** touch targets
even where older general documentation describes 44.

## Source audit baseline

The following describes source observed on 2026-09-10 before this feature's
implementation. It is not an assertion about current production or a record
of acceptance tests run in this task. [Roadmap.md](Roadmap.md) and older
architecture documents contain historical status; current code governs the
baseline when they disagree.

| Area | Existing local source | Work required by this request |
| --- | --- | --- |
| Persistent spaces | `clubs/{id}`, members, invites, channels, user membership mirrors; `createCommunityClub` writes its graph atomically | Five server types, complete template seeding and new public product vocabulary |
| Families | `ClubType.family`, deterministic `family_{uid}`, free creation, invitation flow and real check-ins | Calendar, shared list, private memories/media and safe ownership transfer |
| Voice channels | Backend channel rows can store `roomId` | `ClubChannel` drops that field and every voice tile opens the same lounge |
| Room lifecycle | Actual collection is `rooms`; authoritative `startRoomVoice`, `voiceSessionId`, participants, retries and teardown controls exist | Reciprocal channel binding, durable session records and session-scoped RTC names |
| Text | `sendClubMessage` validates identity, membership, role, quotas and retry; existing composer supports text/GIF | Restricted channel checks, supported attachment lifecycle and module-aware routing |
| Channel security | Current Rules read channels/messages for any Club member; `isPrivate` is not an ACL | Enforced per-channel reads, writes, listings, files, rosters and media grants |
| Server metadata/media | Non-family root GET ignores privacy; ordinary Club artwork is public | Versioned private-root boundary and authenticated private artwork |
| LiveKit | Current room JWTs grant microphone only; role/membership checks and revocation helpers exist | Camera, screen, generation binding and source-aware permission updates |
| Dedicated modules | No complete event/RSVP, Q&A/vote, episode/egress, list or whiteboard backend located | Real persistent implementations, errors, retention and verification |
| Family media | Metadata rules exist; `family_moments` writes and family artwork are intentionally disabled | Reservation, upload, validation, playback, privacy and cleanup before enabling UI |
| Ownership | Existing owner transfer/remove/delete are privileged operations | Transfer currently rejects family and resets only the default lounge |

Primary audited sources:
[Club models](../lib/features/clubs/data/models/),
[ClubService](../lib/features/clubs/data/services/club_service.dart),
[Club overview](../lib/features/clubs/presentation/screens/club_overview_screen.dart),
[creation/quota](../functions/clubs/),
[room creation](../functions/rooms/creation.js),
[message writer](../functions/messaging/community_integrity.js),
[token authority](../functions/livekit/token.js),
[Firestore Rules](../firestore.rules) and [Storage Rules](../storage.rules).

## Architecture decision: extend the existing data graph

**Context.** Existing clients, Functions, notifications, moderation, media and
the website depend on the `clubs` and `rooms` schemas. Clubs already provide
the persistent membership/channel structure; a family is an existing private
Club variant. Replacing collection names would require simultaneous authority
and history migration without providing a missing product capability.

**Decision, accepted for implementation.** Introduce Server, ServerType,
ServerChannel and ChannelSession domain models and a shared Server service.
Persist them additively over `clubs/{serverId}` and its existing subcollections.
Keep legacy fields, identifiers, roles, message paths, media objects and
callable adapters. Do not introduce a second authoritative `servers` collection.

**Reasoning.** One membership and moderation authority avoids inconsistent
copies, preserves history and permits an idle, versioned rollout. Privileged
cross-document changes reuse existing transaction, operation-ledger, quota,
outbox and media-validation patterns. This follows
[Architecture.md](Architecture.md), [SECURITY.md](SECURITY.md) and the
compatibility rules in [CLAUDE.md](../CLAUDE.md).

**Consequences.** `Club` remains an internal compatibility term. Every old
writer and read path that can reach a versioned root needs the new boundary;
adding domain models alone is insufficient. Old broad channel queries cannot
read a mixed restricted-channel collection safely. Backend compatibility and
an explicit old-client gate precede migrating existing spaces. Formal ADR
numbering and cross-document integration belong to the primary integration
pass; this section is the agreed ADR-ready decision.

The durable relationship is:

```text
clubs/{serverId}                     persistent Server
  channels/{channelId}               persistent channel or module
    channelSessions/{sessionId}      one live session lifecycle
             |
             +-- rooms/{roomId}      retained media/history anchor
                     |
                     +-- canonical session-specific LiveKit room name
```

Server type, channel kind and participation experience are independent.
`RoomExperience` keeps exactly `community` and `broadcast`; legacy persisted
`experience: podcast` continues to map to broadcast. Podcast template identity
does not turn the enum into five values. A community server can contain both
ordinary conversation and a moderated broadcast stage.

## Versioned data contract

The following is the target V1 contract. A definition in this section is not
evidence of implementation. Missing version fields invoke the legacy adapter;
unknown values on an explicitly versioned record fail closed as unsupported
or malformed rather than silently becoming public/community defaults.

### Server and memberships

Keep existing root fields, including `name`, `description`, `ownerId`,
`ownerName`, `privacy`, `defaultLanguage`, `status`, default channel IDs,
`loungeRoomId`, counts and timestamps. `type` remains `family` for families and
`community` for other templates. The V1 additions are:

| Field | Meaning and authority |
| --- | --- |
| `serverSchemaVersion: 1` | Server-owned boundary selector; immutable to clients |
| `serverActivationState` | Raw factories and migrations seed `held`; only the exact registered creation runtime may seed a brand-new V1 graph as `active` in its original transaction |
| `serverType` | `friends`, `community`, `podcast`, `family`, `company` |
| `templateVersion: 1` | Server-owned seed definition version |
| `entitlementPolicyId` | Server-owned allocation policy, independent of type and local role |
| `revision` | Monotonic revision for conflicting metadata/structure operations |
| `migration` | Optional `{version, sourceKind, sourceId, state}` provenance |

`members/{uid}` remains canonical; `users/{uid}/clubs/{serverId}` remains a
private discovery mirror, never authority. Preserve the six existing roles:
`owner`, `coOwner`, `admin`, `moderator`, `member`, `guest`. Company UI may
label `member` Employee without minting platform staff privileges. Add a
server-owned `authorizationRevision` for V1 memberships. Role/ban/removal
changes invalidate access grants through this revision and durable cleanup.
An owner cannot leave before successful ownership transfer or deletion.

Family ownership also has the server-owned
`serverFamilyOwnerReservations/{uid}` reservation. A transferred Family keeps
its original server ID, so the old `family_{uid}` creation ID is no longer a
complete ownership limit. The legacy seven-write bootstrap is allowed only
when the caller has no reservation. Any existing reservation, including an
orphaned, stale or malformed one, requires server reconciliation and cannot
be cleared, rewritten or bypassed by a client batch. Legacy accounts without
a reservation retain their existing complete creation flow.

`onlineCount` and live participant counters must come from actual supported
presence/session data. Do not seed fake activity. `memberCount: 1` is valid
after the canonical owner membership commits; creation alone does not make
other people or a media session present.

The raw creation factory and every migration deliberately seed
`status: preparing` with `serverActivationState: held`. Only the canonical
owner can read held preparation metadata; content, rosters, media and voice
remain closed. The runtime constructed by `servers/registration.js` may seed
an **absent** root and all of its room anchors directly as `active` in that
same atomic creation transaction. Request payloads cannot select this mode,
and replay against an existing held or migrated graph returns it unchanged.
Runtime authority still requires the exact `status: active` / activation
`active` pair; unknown or mismatched pairs do not receive legacy fallback.

Registration and use are separate boundaries. The reviewed source statically
registers the 53 base Server exports so Firebase can discover them without an
environment variable. A deployed callable still cannot reach this creation
mode until the server-owned runtime gate below admits its authenticated UID.
No production deploy or activation is implied by source registration.

### Runtime deployment and activation boundary

`YOVOICE_SERVERS_V1` is obsolete and has no effect. Every base callable reads
`appConfig/serversV1` after authentication and before any product work; every
maintenance/outbox worker reads its independent `workersEnabled` value. The
document is server-only under Firestore Rules and has exactly these fields:

| Field | Runtime contract |
| --- | --- |
| `schemaVersion` | Exactly `1` |
| `callableAccess` | `disabled`, `testers` or `all` |
| `testerUids` | At most 100 unique valid Auth UIDs; non-empty only for `testers` |
| `workersEnabled` | Boolean independent of callable admission |
| `revision` | Positive safe integer, incremented for every operator change |

A missing document behaves as disabled with workers paused. Unknown keys,
invalid values, duplicates, a non-empty tester list outside `testers`, read
failure or malformed data fails closed. Reads are uncached so the next fresh
invocation observes a rollout or rollback revision. An invocation admitted
before a freeze may finish.

The static base is 48 callables, two dispatcher exports and three maintenance
sweeps. Podcast events, reminders, questions and voting are included. The six
Podcast recording/Egress callables and
`reconcileServerPodcastEgressSchedule` are source-disabled; while disabled,
their provider credential is not declared and their Egress/episode services
are not constructed. [ADR-176](Decisions.md#adr-176-servers-v1-exports-are-static-and-activation-is-a-server-owned-runtime-decision)
and [DEPLOYMENT.md](DEPLOYMENT.md#servers-v1-static-registration-and-runtime-activation)
own the decision and operator sequence.

### Channels and categories

Keep legacy `name`, `type`, `position`, `isPrivate`, `createdBy`, `createdAt`
and stored `roomId`. V1 adds:

| Field | Contract |
| --- | --- |
| `serverSchemaVersion: 1` | Versioned schema and write authority |
| `kind` | `text`, `voice`, `stage`, `events`, `announcements`, `rules`, `questions`, `episodes`, `calendar`, `memories`, `list`, `meeting`, `whiteboard`, `files` |
| `categoryId` | Null or a category in this server |
| `status` | `active`, `archived`, `deleting` |
| `roomId` | Null for non-media modules; immutable reciprocal binding for media |
| `activeSessionId` | Null when idle; server-owned current generation |
| `liveness` | Server-owned client-visible projection `{schemaVersion, isLive, startedAt}`. Written only by the session start/end transactions and the convergence end path; no client may write any part of it. **No `participantCount`** — see below |
| `experience` | `community` or `broadcast` for media channels |
| `mediaMode` | `audio`, `video`, `meeting` for media channels |
| `accessMode` | `members` or `restricted`; `isPrivate` mirrors this for V1 |
| `aclRevision`, `revision` | Server-owned access and content-structure revisions |
| `historySource` | `{kind: channelMessages}` or `{kind: legacyRoomMessages, roomId}` |

Legacy `type` remains the compatibility projection `chat`, `voice` or
`announcement`; the new module is selected by `kind`. A legacy writer must
not accept an unsupported module simply because its projection says `chat`.
Categories use `clubs/{sid}/channelCategories/{categoryId}` with name,
position and revision. Category labels must not expose restricted channel
subjects to unauthorized users.

### Channel listing and access

New private server metadata requires current membership or the precise
invitation/discovery permission. New versioned roots cannot inherit the
legacy non-family public GET branch. Public discovery uses exact filterable
fields and contains no private-channel previews.

In the current held implementation, private V1 root GET requires current
membership; there is no legacy invitation exception. A pending, declined,
accepted, expired or malformed invitation must not open the current root.
The only pre-join preview is the invitation document itself (ADR-178): it is
server-written with exact generation, expiry and inviter authority revision,
it carries the server name and the inviter's canonical display name and
nothing else, and it is readable only by its invitee and the server's
managers. It opens no root, channel, roster or message.

For channels, store server-owned effective
`channels/{cid}/accessGrants/{uid}` with capabilities, `aclRevision` and
`membershipRevision`. Current channel and membership revisions must match.
The mutable policy is validated by `setServerChannelAccessV1`; its subjects
must be current server members or the existing server-local role enum.
Never accept platform-role or client-supplied effective-grant authority.

All-member channel discovery queries both `accessMode == members` and
`status == active`, then orders by position. Restricted channel discovery uses private
`users/{uid}/serverChannelRefs/{digest(serverId,channelId)}` pointers, followed
by authorized point reads. These pointers contain opaque IDs, not names,
participant lists or previews. Selected channel reads still recheck current
access; a stale mirror cannot restore access.

ACL revocation updates the canonical revision first, then a retryable outbox
converges projections and LiveKit removal or source permission changes.
Apply the same authority to messages, rosters, questions, events, files,
recordings, search, reports, notifications and token issuance. Legacy direct
channel/member writes are not an alternate mutation path for V1 roots.

### Sessions

`rooms/{roomId}` remains the existing media anchor. A V1 bound room adds
immutable `serverId` and `channelId`, requires `clubId == serverId`, and must
match the channel's `roomId`. Continue using existing `voiceSessionId` and
liveness controls; do not build an independent competing audio coordinator.

Held anchors use `status: preparing`, `serverActivationState: held`,
`visibility: private`, `isLive: false`, `hostId: null` and
`serverOwnerId: ownerId`. This matters for real legacy discovery queries:
neither public-room queries nor `hostId == caller` queries can return them.
An emulator probe confirmed that field-presence checks and map defaults do
not make a safe LIST filter for the version field. Do not replace this
canonical held shape with a presence-only list predicate. Legacy room
get/chat/token/control/artwork callables reject V1 bindings; migration and
activation require the reviewed V1 session path, not a legacy endpoint.

`channelSessions/{sessionId}` stores `serverId`, `channelId`, `roomId`,
`sessionId`, `experience`, `mediaMode`, `startedById`, `startedAt`, `endedAt`,
`livekitRoomName`, optional `recordingId`, and status
`starting | live | ending | ended | failed`. One start transaction writes the
session, active channel pointer and room liveness fields. An end transition
keeps the server, channel and history.

`channelSessions` is **not** client-readable and the V1 room anchor stays
closed, so pre-join liveness reaches clients only through the channel
document's own `liveness` map, written by the same start/end transactions
(ADR-177). The channel's existing ACL governs it: the grant that reveals the
channel reveals its liveness, and nothing new is opened. The map carries
`isLive` and, when live, the `startedAt` instant — and deliberately **no
participant count**. Token admission is not provider-connected presence, so
until the verified presence webhook exists there is no honest writer for a
count, and a surface must render "live, count unknown" rather than deriving a
number from token issuance. Archiving or deleting a channel, and the
ownership-transfer convergence path, retire the projection in the same
transaction that clears `activeSessionId`.

`isLive` means "a generation is open", not "people are here", and a
generation whose starter vanished without calling
`endServerChannelSessionV1` is bounded by `sweepStaleServerChannelSessionsSchedule`
(`functions/servers/session_staleness.js`, ADR-180), every five minutes like
the legacy `sweepStrandedLiveRoomsSchedule` that deliberately skips versioned
anchors. It stages such a generation for end through the **same** writer and
worker every authorized end uses — `stageConvergenceSessionEnd` plus the
`sessionEnd` outbox job the existing dispatcher drains — so there is no
second state machine. It decides only *when*, from two facts that must both
hold: every token the generation ever issued expired at least one grace
period (one token TTL, 300 s) ago, measured by `maxTokenExpiresAtMillis` or
by `startedAt` when no token was ever issued; and the provider reports the
generation's `srv_` room absent or holding zero participants. Token expiry
alone is deliberately not enough — a LiveKit JWT is checked at connect time
and an established connection outlives it — but it does prove nobody new can
arrive, which is what makes the occupancy reading safe to act on. The
staging transaction re-proves the whole reciprocal graph and re-reads
`maxTokenExpiresAtMillis`; a token minted after the occupancy reading moves
the bound and the commit is refused as `changed`. A provider error is an
unknown, and an unknown never ends a generation. The scan is the legacy
sweep's bare `rooms.isLive == true` query on the automatic single-field
index, so no new composite index is introduced.

**Session participation (ADR-181).** `rooms/{roomId}/participants/{uid}`
is the participant's authorization state for one generation — binding,
`role` (`host | guest | listener`), `authorizationRevision`, `hostMuted`,
`serverMuted`, `isMuted`, `isHandRaised`, `handRaisedAt`, `displayName`,
`tokenAuthorityFingerprint`, `joinedAt` — written by token issuance and by
the three participation callables only. `host` is bound to
`channelSessions.startedById` and is never assignable; a host or a
moderate-capable member (owner, coOwner, admin, moderator — the server role
model on the channel ACL, never a platform staff claim) moves a participant
between `listener` and `guest` and applies `hostMuted` (host standing) or
`serverMuted` (moderator standing); each clears only its own flag, so a host
cannot lift a moderator's mute. The server hierarchy outranks the session
hierarchy: a host governs peers and everyone below their own server role, a
moderator governs members they strictly outrank and may act on themselves.
Every role or mute change bumps the participant's `authorizationRevision`,
which the token authority fingerprint includes, so an already-issued
receipt stops replaying at once and a `sessionParticipantChanged` outbox job
(one `recipient` target for exactly that identity and generation) revokes
the bearer through the existing convergence worker with a positive provider
cutoff. That holds for a promotion as well as a demotion or a mute, because
the recipient ledger binds one fingerprint per identity per generation; the
person re-mints a token under the new grant and reconnects. A promotion
grants permission only: the new token permits publishing, nothing unmutes a
microphone, and `isMuted` stays the person's own capture consent. A hand is
a request, not authority: it is the participant's own write, the fingerprint
does not include it, no revision moves and no token is revoked; a promotion
lowers it. The session's own `authorizationRevision` never moves for a
participant change.

Two client reads exist, both under the channel's own ACL (`firestore.rules`
`canReadOwnServerSessionParticipant`, `canListServerSessionHands`): a
participant point-reads their **own** document of the **live** generation
(the anchor's `isLive`/`voiceSessionId` and the channel's `activeSessionId`
must agree), and the session host or a moderate-capable member lists the
**raised hands** of the live generation with the query pinning all four
equalities — `serverId`, `channelId`, `sessionId`, `isHandRaised == true`.
Nothing else: the roster is not listable (there is no honest presence
writer, and a listing of token holders would be rendered as one), another
person's document is never readable, `channelSessions` and the anchor stay
closed, and no client writes any of it. The four equalities are served by
single-field indexes; a client that adds an `orderBy` needs a composite
index that is not committed (the G8 trap).

For V1 sessions, derive the RTC name from all three identities, for example
`srv_` plus the first 40 hex characters of SHA-256 over an unambiguous encoding
of server ID, channel ID and session ID. A JWT for one generation cannot join
the next. Keep the old `roomId` RTC adapter until idle cutover. Update every
active-session mirror, control outbox, cleanup worker and achievement webhook
binding together; changing only JWT room names would strand revocation.

The V1 end worker has a two-phase terminal cleanup. Durable positive
revocation receipts and a fully scanned recipient cursor precede the private
`serverControlOutbox/{endOperationId}.terminalDelete` checkpoint. Its exact
fields are `version: 1`, `endOperationId`, `bindingFingerprint`,
`authorizationRevision`, `recipientCursor` and `readyAt`. The checkpoint binds
the canonical ending generation; its fingerprint is not a client capability
or a substitute for the server-owned scan history. Missing readiness resumes
the ordinary validated scan; malformed readiness, an unsettled cursor or a
nonempty tail cannot authorize deletion.

After a fresh owned-lease check the adapter sends one direct SDK DeleteRoom,
without roster queries or automatic retry, then commits a separately fenced
final ACK. Lost provider/final-commit ACKs retry only that old immutable RTC
generation, without repeating settled removals. Terminal-room NOT_FOUND is
idempotent. Participant NOT_FOUND is terminal only when the adapter proves the
same RemoveParticipant request carried the explicit `revokeTokenTs`; a generic
absence receipt still fails closed. Every pass uses at most twenty SDK requests
with at most four concurrent removals; a full twenty-removal pass leaves
deletion for the next invocation. Every bounded batch is dispatched even when
an earlier recipient fails, then the first failure releases the lease without
committing a partial cursor. This is local held-runtime behavior, not provider
acceptance evidence.

## Callable contract

All listed names are the agreed V1 names. Unless evidence below says otherwise,
they are target contracts, not deployed exports. Mutations accept a stable
`requestId`, exact allowlisted input and canonical authenticated identity.
Use existing operation identity/hash helpers: same input plus request ID
replays the result; reusing a request ID for different input is refused.
Charge target-independent attempt quotas before target-dependent reads.
Never fall back to direct writes after a callable denies an action.

The table contains all 54 callable contracts. The static base registers 48 of
them. The six Podcast recording/Egress callables — start, stop, finalize,
retry, publish and episode access — remain documented for the later provider
slice but are absent from the current export map.

| Callable | Request-specific input and result |
| --- | --- |
| `createServerV1` | `{requestId, serverType, templateVersion, name, description, privacy, defaultLanguage}`; returns `{serverId, defaultChannelId, channelIds, alreadyExisted}` |
| `updateServerV1` | `{serverId, requestId, expectedRevision, patch}`; exact metadata patch, returns updated revision |
| `deleteServerV1` | `{serverId, requestId}`; owner only; refuses while any channel in the server holds a live generation, releases a family's one-per-owner reservation, marks `deletionInProgress` (which every canonical read already treats as closed) and stages bounded resumable cleanup after RTC acknowledgement; returns `{serverId, deleted, revision, cleanupPending, contentCleanupPending}` |
| `createServerChannelV1` | `{serverId, requestId, kind, name, categoryId, accessMode}` plus validated media configuration when applicable; returns channel and reciprocal room IDs |
| `updateServerChannelV1` | `{serverId, channelId, requestId, expectedRevision, patch}`; no silent room/history rebinding |
| `reorderServerChannelsV1` | `{serverId, requestId, expectedRevision, channelIds}`; exact permitted channel set, no duplicate or foreign IDs |
| `setServerChannelAccessV1` | `{serverId, channelId, requestId, expectedAclRevision, policy}`; validates local subjects, bumps ACL revision and queues convergence |
| `archiveServerChannelV1` | `{serverId, channelId, requestId}`; ends affected media and retains authorized history |
| `deleteServerChannelV1` | `{serverId, channelId, requestId}`; explicit destructive action; marks the exact channel/room/revision and stages durable bounded cleanup after every captured RTC generation is positively ended |
| `createServerEventV1` | `{serverId, channelId, requestId, title, description, startsAtMillis, endsAtMillis, timeZone}`; only Friends/Community `events`, Family `calendar` and Podcast `events` (Program) modules; derives the immutable profile and persists a canonical scheduled event |
| `updateServerEventV1` | `{serverId, channelId, eventId, requestId, expectedRevision, patch}`; author or moderator only; upcoming scheduled event and exact revision required |
| `cancelServerEventV1` | `{serverId, channelId, eventId, requestId, expectedRevision}`; author or moderator only; cancellation is retained as a revisioned status transition |
| `respondToServerEventV1` | `{serverId, channelId, eventId, requestId, expectedRevision, response: going | maybe | declined, reminderRequested?}`; one canonical response per member; response and supported Family/Podcast reminder opt-in counts change in one transaction |
| `createServerPodcastQuestionV1` | `{serverId, channelId, requestId, body}`; Podcast `questions` channel only; member-only write with canonical author identity and a stable operation-derived question ID; returns `{serverId, channelId, questionId, status, revision}` |
| `setServerPodcastQuestionVoteV1` | `{serverId, channelId, questionId, requestId, expectedRevision, voted}`; one vote row per member UID and the aggregate `voteCount` change in one transaction; returns `{…, voted, changed, voteCount, questionRevision}` |
| `setServerPodcastQuestionOnAirV1` | `{serverId, channelId, questionId, requestId, expectedRevision, onAir}`; moderator-capable roles only; selects or clears the single `onAir` question for a Podcast Questions channel and revision-demotes the previous selection atomically; returns `{…, onAir, changed, revision, previousQuestionId}` |
| `startServerPodcastRecordingV1` | `{serverId, channelId, studioChannelId, sessionId, title, requestId}`; Podcast moderator only; binds the active audio Studio generation to one deterministic episode ID and durable Egress job, then idempotently starts or discovers the canonical MP3 output; returns `{schemaVersion, serverId, channelId, studioChannelId, episodeId, sessionId, status, revision, providerStatus}` |
| `stopServerPodcastRecordingV1` | `{serverId, channelId, studioChannelId, episodeId, expectedRevision, requestId}`; exact-revision Podcast moderator transition to `processing`, and a durable stop job that survives provider timeouts and retries |
| `finalizeServerPodcastEpisodeV1` | Same exact mutation input as stop; rechecks both channels and current moderator authority, polls the generation-bound Egress job, validates the private MP3 MIME/size/provider duration and moves the episode to `ready` only after the object matches |
| `retryServerPodcastRecordingV1` | Same exact mutation input; only an explicit provider-error episode may restart, with the same canonical output path and idempotent Egress discovery so a retry cannot create a second recording |
| `publishServerPodcastEpisodeV1` | Same exact mutation input; Podcast moderator only; atomically promotes an exact `ready` revision into the member-visible `published` archive |
| `getServerPodcastEpisodeAccessV1` | `{serverId, channelId, episodeId}`; current channel reader for published audio, or current moderator for a ready preview; probes the exact stored generation and returns a generation-bound HTTPS grant valid for at most 90 seconds after a second authority/revision check |
| `createServerListItemV1` | `{serverId, channelId, requestId, text}`; Family `list` channel only; creates one canonical unchecked item with a stable operation-derived ID |
| `updateServerListItemV1` | `{serverId, channelId, itemId, requestId, expectedRevision, patch: {text?, checked?}}`; authorized Family member; exact revision and non-empty patch required |
| `deleteServerListItemV1` | `{serverId, channelId, itemId, requestId, expectedRevision}`; item author or server moderator; exact revision required and retry remains stable after deletion |
| `createServerFamilyCheckInV1` | `{serverId, requestId, status: home | onMyWay | allGood | callMe}`; Family member only; persists one immutable location-free status snapshot |
| `deleteServerFamilyCheckInV1` | `{serverId, checkInId, requestId}`; check-in author or server manager; retry remains stable after deletion |
| `reserveServerFamilyMemoryV1` | `{serverId, channelId, requestId, caption, photoContentType, photoSize, voiceContentType, voiceSize, voiceDurationMs}`; Family `memories` channel only; reserves exactly one canonical private photo and one `audio/mp4` voice note for at most ten minutes |
| `finalizeServerFamilyMemoryV1` | `{serverId, channelId, memoryId, requestId, photoGeneration, voiceGeneration}`; rechecks current membership, exact reservation and both object generations, then probes image/audio bytes and publishes immutable descriptors without durable download URLs |
| `getServerFamilyMemoryMediaAccessV1` | `{serverId, channelId, memoryId, requestId}`; current authorized member only; returns generation-bound signed photo and voice URLs valid for at most 90 seconds after a second authority check |
| `deleteServerFamilyMemoryV1` | `{serverId, channelId, memoryId, requestId, expectedRevision}`; author or moderator; tombstones the exact revision and drains a durable generation-bound media deletion job before removing the document |
| `setCommunityServerFollowV1` | `{serverId, requestId, following}`; active Community member only; writes or removes the private server preference and the caller's private mirror atomically; it is discovery state, never access authority |
| `createServerWhiteboardStrokeV1` | `{serverId, channelId, requestId, points, color, lineWidth}`; Company `whiteboard` channel only; active non-guest member; persists one immutable operation-derived normalized polyline with 2-64 points, an allowlisted color and 1-16 px width; returns `{serverId, channelId, strokeId, generation, sequence, revision, boardRevision}` |
| `undoServerWhiteboardStrokeV1` | `{serverId, channelId, strokeId, requestId, expectedRevision}`; removes only the caller's own exact-revision stroke from the active board generation and transactionally updates the count; returns `{serverId, channelId, strokeId, undone, boardRevision}` |
| `clearServerWhiteboardV1` | `{serverId, channelId, requestId, expectedRevision}`; server manager only; atomically deletes the current generation's bounded stroke set and advances generation/revision; returns `{serverId, channelId, cleared, deletedCount, generation, revision}` |
| `reserveServerCompanyFileV1` | `{serverId, channelId, requestId, displayName, contentType, size}`; Company `files` channel only; active non-guest member; reserves one canonical private object for ten minutes, bounded to 1 byte-25 MiB and the PDF/JPEG/PNG/WebP/plain-text allowlist; returns the stable file ID, exact Storage path and required immutable metadata |
| `finalizeServerCompanyFileV1` | `{serverId, channelId, fileId, requestId, generation}`; rechecks current channel authority, reservation, metadata, generation, declared size and bounded file bytes before publishing a descriptor without a durable download token |
| `getServerCompanyFileAccessV1` | `{serverId, channelId, fileId, requestId}`; current channel reader only; returns a generation-bound HTTPS read grant valid for at most 90 seconds after a second authority/revision check |
| `deleteServerCompanyFileV1` | `{serverId, channelId, fileId, requestId, expectedRevision}`; file author or server moderator; exact-revision transition to a durable deletion job, with generation-bound object removal and retry-safe descriptor cleanup |
| `joinServerV1` | `{serverId, requestId}`; only canonical public admission or applicable invitation, never arbitrary role assignment |
| `createServerInviteV1` | `{serverId, inviteeId, requestId}`; inviter-capable roles only, active server only, friends only, blocks and sanctions fail closed; writes the pending generation, its expiry and the invitee's private pointer; returns `{serverId, inviteeId, generation, status, expiresAtMillis, alreadyExisted}` |
| `revokeServerInviteV1` | `{serverId, inviteeId, requestId}`; inviter-capable roles only; pending → revoked as a status transition bound to the current generation, removes the pointer; returns `{…, status, revoked}` |
| `respondToServerInviteV1` | `{serverId, requestId, response: accept | decline}`; binds the invite to the caller, current status and generation |
| `leaveServerV1` | `{serverId, requestId}`; member/mirror/count transition and all-channel access/media cleanup |
| `setServerMemberRoleV1` | `{serverId, memberId, requestId, role}`; existing role hierarchy, revision and media consequences |
| `removeServerMemberV1` | `{serverId, memberId, requestId}`; the four removal-capable roles Club already uses (`owner`, `coOwner`, `admin`, `moderator`), strict rank, never the owner and never self (that is `leaveServerV1`); bumps the target's `authorizationRevision`, drops every private grant and discovery pointer and stages the revocation that ends their live session; returns `{serverId, memberId, removed, membershipRevision, cleanupPending}` |
| `setServerMemberBanV1` | `{serverId, memberId, requestId, banned, reason}`; same authority as removal; sets AND lifts, because a ban nobody can lift is a second defect; a reason is required to set one and refused to lift one; the membership document survives so the ban is durable and `memberCount` is unchanged; every change bumps `authorizationRevision` and stages the revocation; returns `{serverId, memberId, banned, changed, membershipRevision, cleanupPending}` |
| `transferServerOwnershipV1` | `{serverId, newOwnerId, requestId}`; both owner guards, canonical memberships, policy quota and all-channel cleanup |
| `startServerChannelSessionV1` | `{serverId, channelId, requestId}`; returns canonical `{roomId, sessionId}` after authorized start or compatible concurrent join |
| `createServerChannelTokenV1` | `{serverId, channelId, sessionId, requestId}`; returns existing connection fields plus canonical binding and explicit permitted track sources |
| `endServerChannelSessionV1` | `{serverId, channelId, sessionId, requestId}`; generation-bound end and durable RTC teardown |
| `setServerSessionParticipantRoleV1` | `{serverId, channelId, sessionId, participantId, role: guest | listener, requestId}`; session host or moderate-capable role, server hierarchy outranks the session host, `host` is never assignable; bumps the participant's `authorizationRevision` and stages the bearer's revocation; a promotion grants permission only and lowers the raised hand; returns `{…, role, hostMuted, serverMuted, participantRevision, changed, cleanupPending}` |
| `setServerSessionHandV1` | `{serverId, channelId, sessionId, raised, requestId}`; the participant's own write only, refused for the host and for anyone without a participant document; no revision moves and no token is revoked; returns `{…, raised, changed}` |
| `setServerSessionMuteV1` | `{serverId, channelId, sessionId, participantId, muted, requestId}`; the host's standing writes `hostMuted`, a moderator's writes `serverMuted`, each clears only its own, self is refused; every change bumps `authorizationRevision` and stages the bearer's revocation; returns `{…, hostMuted, serverMuted, participantRevision, changed, cleanupPending}` |

Creation derives stable server/channel identities from the operation and
server-owned template. Retries recover the same graph even after a lost
response. The family compatibility path retains its deterministic identifier
and owner checks. The server seeds exactly one owner membership and one
template channel set; the client never submits sample members or activity.

Retain adapters for `createCommunityClub`, `finalizeClubMedia`,
`transferClubOwnershipSelf`, `removeClubMemberSelf`, `deleteClubSelf`,
`sendClubMessage`, `startRoomVoice`, `createLiveKitToken` and existing invite,
room and moderation operations. They must enforce V1 authority when their
target is versioned. A new callable facade must not leave a permissive old
callable that can bypass it.

### The admin and staff surface on a versioned root (ADR-188)

Trust & Safety does not get a second set of callables. `functions/admin/clubs.js`
keeps staff authentication, step-up and the audit log and delegates the
versioned branch of four of its callables to staff adapters in
`functions/servers/management.js`, required lazily so a legacy-only staff
action loads none of the server domain:

| Staff callable | Versioned root | What the adapter adds that a raw admin write would skip |
| --- | --- | --- |
| `listAdminClubs`, `getAdminClub` | unchanged | Neither ever refused a versioned root; they read it as they always did |
| `setClubModerationStatus` | `staffSetServerModerationStatus` | Root `status` → `suspended` (which `canonicalServer` and `isClubMember()` both already treat as closed) AND an authorized end for every live generation — a suspension that leaves the voice channel running suspends nothing, and the legacy per-room batch cannot end an `srv_` generation |
| `removeClubMember` | `staffRemoveServerMember` | `authorizationRevision` bump, the `memberAuthorizations` record, the private grant and discovery-pointer sweep, and the outbox job that revokes the bearer |
| `setClubMemberBan` | `staffSetServerMemberBan` | The writer for `member.banned`, in both directions, with the same revision fence and revocation |
| `adminDeleteClub` | `staffDeleteServer` | Ends every live generation, marks `deletionInProgress` and stages the same bounded, revision-fenced cleanup as owner deletion. The legacy recursive sweep is NOT reused: it would delete the root while V1 sessions, grants and reciprocal bindings are still live |
| `transferClubOwnership` | **still refuses** | The only V1 transfer is the owner-initiated `transferServerOwnershipV1`. Staff recovery of an absent owner needs transfer's entitlement and guard adapter and is a separate slice |

A staff adapter takes no `requestId`, because its legacy caller has none:
idempotence is idempotence of STATE. Re-running a suspension, a ban, a removal
or a deletion converges on the same document and reports `changed: false`.

Every adapter refuses a **held** root with the uniform `permission-denied`.
A held root has never been activated and nobody but its owner can reach it;
refusing it is what keeps the legacy staff path from becoming the activation
writer this surface deliberately does not have.

Use structured existing error codes for unauthenticated/permission-denied,
invalid argument, stale revision, unavailable, exhausted capacity and
unsupported state. Authorization precedes existence disclosure for private
targets. Return no private preview in a denied response. Pagination cursors
carry position, never authorization; every page rechecks current access.

## Creation, ownership and capacity

**Approved:** a Free account may own up to 5 Servers and an active paid Premium
account may own up to 30, across the five templates. A Family Server consumes
one slot in this shared allowance and also keeps the separate maximum of one
Family Server per owner. There is no blanket legacy Club paywall on the new
selector or hub. Both account types may join an unlimited number of Servers;
joining and continuing to use an existing server never consume creation
capacity.

Use an explicit server-owned policy such as `freeServersV1` for new servers,
`legacyRoomV1` for adopted standalone room allocations,
`legacyCommunityPremiumV1` for retained paid Club allocations, and
`familyFreeV1` where the existing family allocation applies. These identifiers
describe allocation provenance, not a user-editable subscription setting.

The free allowance counts persistent server allocations, not each seeded
voice channel or session. A migrated standalone room retains its allocation;
it is not counted twice and cannot disappear from quota by acquiring `clubId`.
Existing `isActiveOrdinaryRoom` excludes Club-bound rooms, and current
`requireCommunityClubCapacity` counts every non-family Club: both old count
paths therefore need version-aware shared accounting. Owner guards and exact
canonical allocation queries must cover create, delete, migrate and transfer.
Existing legitimate over-limit data is retained; report it and block only
additional allocation according to the applicable policy. Do not rewrite paid
entitlement documents to implement this feature.

Preserve existing family privacy and deterministic-ID protection. Family
transfer requires a server-owned owner reservation, because `family_{uid}`
alone cannot enforce one-owned-family correctly after transfer. Keep the
original document ID and media paths; update current-owner discovery and both
owner reservations atomically. An original creator must not regain ownership
by reopening their historical deterministic path. Changing existing family
allocation constraints beyond this compatibility requirement is not implied
by template identity.

Friends, family and company default to invite-only. Community and podcast
require an explicit privacy choice; public access is not silently preselected.
Invites have canonical target identity/generation, revocation and expiration
semantics. Leaving a conversation and leaving its server are separate actions.

### Invitations

`createServerInviteV1` and `revokeServerInviteV1` (`functions/servers/invites.js`,
ADR-178) are the only writers of `clubs/{serverId}/invites/{inviteeId}` on a
versioned root; Firestore Rules keep every client create and update at
`false`, the legacy delete stays legacy-only, and `sendClubInvite` refuses a
versioned root. The document is exactly what `respondToServerInviteV1`
already consumed before a writer existed:

| Field | Authority |
| --- | --- |
| `serverSchemaVersion: 1`, `serverId`, `inviteeId` | Identity; the consumer denies any mismatch with the path |
| `inviterId`, `inviterAuthorizationRevision` | The inviter and the exact membership revision they held; a later demotion, removal or ban makes the invitation dead on arrival |
| `status` | `pending → accepted | declined | revoked`; only `pending` admits |
| `generation` | Monotonic per (server, invitee); every re-issue advances it, so a receipt, a decline or a revocation bound to an older generation acts on nothing |
| `expiresAt` | Seven days from issue (`SERVER_INVITE_TTL_MS`); an expired invitation admits nobody and is re-issued as a new generation |
| `serverName`, `inviterName` | The reviewed pre-join preview: server-owned snapshots, no channel, roster, count or artwork |
| `createdAt`, `updatedAt`, `respondedAt`, `revokedAt`, `revokedById` | Server timestamps; a re-issue replaces the whole document so an older generation's answer does not linger |

Who may invite: the inviter roles the consumer re-proves at acceptance —
`owner`, `coOwner`, `admin`, `moderator` — and nobody else, on an **active**
server only. A held server refuses invitations entirely, including from its
owner: `admission` denies a preparing root, so an invitation issued while held
would be undeliverable, and it would disclose the server's name to a third
party before activation, which the held boundary exists to prevent. The
invitee must be an active account that is a canonical friend of the inviter
(both `friendshipGuards`, never the client-writable mirror), not blocked in
either direction, not communication-muted and not already a member. Every
invitee-state refusal is one `permission-denied`, so the callable is not an
oracle for another account's ban, sanction, block or friendship state. Each
attempt also charges the actor-wide `server.v1.invite` budget (30 per minute,
the legacy invite rate) before any target read.

Discovery reuses the `serverChannelRefs` precedent rather than opening a
query: `users/{inviteeId}/serverInviteRefs/{serverId}` holds
`{serverId, generation, expiresAt}` only — no name, no inviter — is
owner-readable, never client-writable, and is removed by revocation,
acceptance and decline. Because expiry itself emits no document write, the
bounded `sweepExpiredServerInvitesSchedule` queries at most 50 expired
pointers every 15 minutes and transactionally removes each pointer plus only
the matching generation-bound notification. The invitation document remains
as history and still fences the next generation. It is discovery, never authority: the client
point-reads the invitation, whose rule rechecks the invitee, and a stale or
forged pointer opens nothing. The pre-existing self-scoped
`collectionGroup('invites')` rule is untouched and still returns only the
caller's own invitations.

`onServerInviteWritten` is the V1 notification authority. It re-proves the
active V1 root, the inviter's exact role and authorization revision, both
canonical friendship guards, the absent invitee membership, the exact pending
generation and its pointer before writing `type: clubInvite`,
`targetId: serverId`, `sourceGeneration: String(generation)`. Its hashed
notification id is generation-bound, so a re-issue cannot reuse or resurrect
the prior bell row. Accept, decline, revoke, delete and malformed transitions
remove only a notification whose source path and generation still match. The
legacy on-create trigger ignores `serverSchemaVersion: 1` documents.

Revocation is a status transition, not a delete, so the revoked generation
stays on record and a "revoked or expired invite must not gain new life"
check has something to compare against; the next invitation to the same
person is generation + 1. Revocation also works under a communication
restriction and on a held server, because it only ever narrows.

## Five complete template experiences

All rows remain acceptance obligations. “Coming soon” may honestly expose an
unfinished dependency during development but does not satisfy these rows.

| Template | Seeded channel/module intent | Required working experience |
| --- | --- | --- |
| Friends | `ogólny`, `memy`, `Salon`, `Gaming`, `Wydarzenia`, `Zasady` | Multiple persistent chat/voice channels, actual speaker activity, avatars, compact controls, context chat and upcoming event with RSVP |
| Community | Announcements, rules, general, questions, voice lounge, `Scena LIVE`, events | Real 16:9 video broadcast, title/host/viewers and live chat; host/moderator/invited participant/viewer roles, moderated stage requests; ordinary lounge stays a conversation; truthful offline state |
| Podcast | `Studio LIVE`, `Odcinki`, `Program`, discussion, questions, announcements, rules | Audio host/guest/audience hierarchy, real speaker rings, episode title/number, voted questions and On air selection, stage queue, reminders, explicit recording, processing, playback and publication |
| Family | Family chat, `Salon`, `Kalendarz`, `Wspomnienia`, `Lista zakupów`; preserve check-ins | Private easy-join dashboard, zoned calendar/RSVP/reminders, photo plus short voice memory, synchronized list and existing home/on-my-way/all-good/call-me check-ins |
| Company | General, announcements, team/project channels, private `HR`, private `Zarząd`, meetings, board, files | Explicit local access, voice/camera/presentation/screen, meeting chat, durable collaborative board, participant context and continuous meeting across presentation/board/chat tabs |

Reuse common server header, channel list, member/role UI, invitation flow,
context panel, composer and conversation dock. Template-specific content owns
the different central scenes; five copies of the whole application are not
the architecture. User-entered names are persisted content; seed labels and
all surrounding controls use the existing localization system.

### Dedicated module persistence

All module documents inherit exact server and channel authorization. Reuse
existing family `clubs/{sid}/moments` and `checkIns` through explicit adapters;
do not expose family data through public Voice Moments or duplicate bytes.

| Module | Target persistence and lifecycle |
| --- | --- |
| Events/calendar/program | Channel `events/{eventId}` and `responses/{uid}`; UTC timestamp plus IANA timezone; cancelled rows remain revisioned. Friends/Community events, Family calendar and Podcast Program share the implemented RSVP contract; Family/Podcast responses also persist reminder opt-in state and a transactional count |
| Questions | Channel `questions/{questionId}` and `votes/{uid}`; one vote per authorized member, server-derived count, explicit host selection for On air |
| Episodes | Channel `episodes/{episodeId}`; draft/recording/processing/ready/published/error/deleting; canonical immutable media path/generation and private recording job outbox |
| Shared list | Channel `listItems/{itemId}`; validated text, checked state and revision; concurrent edits/retries converge |
| Whiteboard | Company channel `whiteboardState/main` plus `whiteboardStrokes/{strokeId}`; durable ordered normalized polylines, one active generation capped at 180 strokes, author-only undo and manager-only atomic clear |
| Files/memories | Canonical private descriptors and upload reservations; actual probe/finalization, authorized read, deletion and abandoned-upload cleanup. Company Files accepts PDF/JPEG/PNG/WebP/plain text up to 25 MiB, enforces a 256 MiB per-user daily reservation budget and returns only 90-second generation-bound signed reads |

Module callables use the same exact-input, retry, limits, authority and cleanup
patterns. Their specific schemas and numeric processing/storage limits must
be recorded with the implemented module before acceptance; a metadata-only
placeholder is not a completed module. Whiteboard viewing and collaboration
do not depend on opening another media session.

Company Files stores descriptors under
`clubs/{serverId}/channels/{channelId}/files/{fileId}` and immutable bytes under
`server_company_files/{serverId}/{channelId}/{ownerId}/{fileId}.{ext}`. A client
may create the object only while its exact server-written reservation is live;
clients cannot list or delete Storage objects and cannot write descriptors.
Finalize performs a bounded trusted probe before publication and removes any
download token. Delete, abandoned-upload expiry and server/channel teardown use
durable fenced cleanup jobs, generation checks and resumable checkpoints. A
replay after expiry or completed deletion fails closed instead of returning a
historical receipt that suggests a file still exists.

The implemented Events V1 service accepts exactly four canonical root/channel
pairs: `friends/events`, `community/events`, `family/calendar` and
`podcast/events` (the seeded Program channel). The server derives and persists
`serverType`, `channelKind`, `eventKind`, RSVP support and reminder capability;
clients cannot submit those authority-bearing fields. Events start from now
through two years ahead, last at most seven days and carry a validated IANA
timezone. `going`, `maybe` and `declined` counts change in the same transaction
as the member's response. Family and Podcast members may additionally set the
exact optional boolean `reminderRequested`; its count changes atomically with
the response. This stores reminder intent only. A delivery/scheduling worker is
a separate integration and is not claimed by this contract.

Firestore clients may read events and response rows only through the parent
channel ACL; every client write is closed and all mutations go through the four
callables above. Deleting the channel or server drains response rows before
event rows as part of the same bounded content-cleanup state machine.

The implemented Family shared list is confined to a canonical Family root and
`list` channel. Items have stable operation-derived IDs, validated text, a
boolean checked state, the member who checked them and a monotonic revision.
All Family members with channel write access may add, edit and toggle; only the
author or a moderator may delete. Clients read through the active channel ACL
and write only through the three exact-input callables. Channel/server deletion
drains `listItems` in bounded validated pages before removing the channel.

The implemented V1 Family check-in adapter keeps the existing four statuses
(`home`, `onMyWay`, `allGood`, `callMe`) and deliberately accepts no location
field. Each immutable row snapshots the canonical author display name and is
private to active Family members. The author or a server manager may remove a
row through the callable; V1 clients have no direct write path. Root cleanup
already drains `checkIns` in bounded pages.

The implemented Family Memories adapter pairs one image with one short
`audio/mp4` voice note in the existing `clubs/{serverId}/moments` collection
and `family_moments/{serverId}/...` Storage namespace. A ten-minute,
server-owned reservation fixes both paths, MIME types, sizes and the claimed
voice duration. Finalization rechecks the active Family Memories channel,
object generations and trusted media probes before publishing descriptors;
it removes durable Firebase download tokens. Playback is callable-authorized
and returns generation-bound V4 URLs with a 90-second expiry. Author/moderator
deletion uses a durable job, and whole-server deletion first retires every
upload reservation and pending deletion job, then drains the isolated Storage
prefix in bounded leased pages before removing the root. This order prevents a
late upload from racing an apparently empty prefix.

Community Follow stores only the current member's boolean preference in
`clubs/{serverId}/followers/{uid}` plus the private
`users/{uid}/serverFollows/{serverId}` mirror. Both projections are exact,
callable-owned and transactionally identical; neither grants membership or
channel access. Server deletion drains primary rows and any orphaned private
mirrors in bounded pages before the server root disappears.

## Media and lifecycle safety

The existing room JWT grants only declared microphone tracks. Camera and
screen require explicit server policy and `canPublishSources` in both token
issuance and later permission updates. LiveKit source labels constrain the
normal SDK but do not prove where a hostile client captured bytes. No new
client receives provider secrets or an E2EE claim.

Token authority validates the full reciprocal server/channel/room/session
binding, current account, membership, ACL revision, sanctions and session
role. **A cached token operation is reauthorized before replay**: the current
legacy handler can return a still-unexpired JWT before its normal authority
read, which is not acceptable for revoked V1 channel access. Listener→guest
promotion grants permission but never enables the person's microphone. The
person explicitly consents to starting their own microphone.

Microphone, camera and screen each have independent permission, requested,
actual and cleanup state. Membership removal, demotion, local leave, session
end, account replacement and stale asynchronous results stop the relevant
tracks. Reuse current room entry/leave/mute coordinators and the existing
coordination with direct calls and recording. Browsing another server/text
channel does not leave a call. Starting another media session first finishes
the prior session's cleanup barrier.

Recording is an explicit host action backed by a real provider job. Show
recording only after authoritative job state. Signed egress callbacks bind
the expected session/job, validate output generation and drive processing;
failure/retry never publishes a nonexistent episode. The installed server SDK
has an egress API, but that is not evidence of an implemented or configured
recording service. External credentials, output configuration and provider
verification are separate release dependencies.

Private uploads reuse reservation → upload → probe → finalize → authorized
read → cleanup. Preserve canonical IDs/generations, revoke durable download
tokens and prohibit public URLs for private server artwork/files/episodes.
Storage rules alone do not revoke an already disclosed bearer URL. If using
short-lived signed media grants, document their exact residual validity;
strict per-request revocation needs an authenticated reader, including range
requests. The client stops playback and purges scoped caches on lost access,
without claiming that already downloaded bytes can be remotely erased.

### Platform capability and verification matrix

These are implementation/test obligations, not claims of current device
support. Derive availability from the actual platform adapter and backend
contract; separate watching from starting a capture.

| Operation | Phone/native | Tablet | Web | Supported desktop apps |
| --- | --- | --- | --- | --- |
| Receive voice/video/screen | Verify two-client playback | Verify adaptive stage | Verify representative browsers | Verify packaged app/device |
| Microphone/camera publication | Explicit OS consent; lifecycle/background tests | Same with rotation | Browser permission/device/reconnect tests | OS device selection and permission tests |
| Start screen/presentation share | Enable only after actual platform implementation/extension verification | Same; receiving remains independent | Require actual browser display-capture availability and user choice | Verify supported capture adapter and OS permissions |
| Recording/episode playback | Server job plus actual playback test | Same | Same plus browser media support | Same |
| Collaborative board | Touch/pan/zoom, keyboard where present | Two-panel adaptive use | Pointer/keyboard/zoom | Pointer/keyboard/zoom |

Test network loss/reconnect, expired token, rejected permission, absent device,
audio-device switch, background/foreground and host ending the stream. Record
specific unsupported operations honestly. Source compilation or a screenshot
does not prove inter-client media, screen sharing or collaboration.

## Deterministic migration and compatibility

No read operation creates a server or writes migration data. Operator tooling
defaults to dry-run, supports local/emulator fixtures and requires a separate
approved production execution step. All mappings have version 1 and explicit
provenance; use stable hashing and verify collisions against source identity.

| Source | Mapping |
| --- | --- |
| Ordinary Club | Same `serverId == clubId`; community template unless an explicit owner override exists |
| Family Club | Same `family_{originalUid}` ID and family boundary; retain membership/media/check-ins |
| Canonically bound room | Follow `room.clubId`, validate the root and reciprocal channel; repair missing linkage deterministically |
| Standalone room | `legacy_room_` + first 40 hex characters of SHA-256 of `rooms/` + original room ID; default channel `legacy_voice`; original room/media/history IDs stay |
| Standalone experience | Broadcast or legacy podcast → podcast template; community → community template; owner manifest override wins |

An owner override cannot broaden privacy, rewrite paid access or move private
history without the corresponding explicit authorized operation. Never infer
type from color. Missing owners, malformed references, multiple candidate
channel bindings and unresolved legacy private flags are reported, not guessed.

For standalone rooms, the root host becomes owner. Only legitimate durable
`roomMembers` become durable server members. Transient participants/listeners
must not silently become permanent members, and session speaker/moderator
roles must not become server admins. Keep old private admission through a
controlled compatibility adapter until the conversion has an explicit access
mapping. Preserve existing ban state and invitations without granting a revoked
invitation new life. Retain the user follow graph and source IDs used by room
notifications; do not invent a separate server-follow graph.

Message history stays at its source path through `historySource`; the mapped
legacy channel uses the corresponding existing writer/report/moderation
adapter. Do not create two simultaneously writable copies of a history. The
migration inventory covers attachments, media generations, roles, owners,
banlists, invites, user projections, counters, notification targets, follows,
default-channel pointers and active-session mirrors in addition to roots.

### Dry-run, apply and validation

1. Inventory source roots and related records without copying message bodies
   or bearer material into aggregate logs. Record counts, reference identities,
   source update generations and unresolved cases in a versioned manifest.
2. Compute deterministic mappings and owner overrides. Produce a local
   old-ID→server/channel-ID report and expected unchanged media/history paths.
3. Validate required owner/membership relations, unique reciprocal channels,
   scope of private data and both free/paid quota allocations. Report existing
   count drift separately from proven canonical counts.
4. Apply bounded transactions/batches from the reviewed manifest. Each step
   compares source fingerprints, prior provenance and mapping identity. Persist
   cursors and completed steps so interrupted runs resume without duplicates.
5. Defer active sessions. Recheck liveness, voice generation, participant graph
   and source update generation at mutation time; a concurrent start changes
   the transaction outcome to deferred. Do not end an active session to migrate.
6. Reconcile source/target counts and references, unchanged history/media IDs,
   quota guards, restricted access, membership mirrors, notification/link
   resolution and absent duplicate roots. Preserve the report and exceptions.

Large membership graphs use a staged migration state with bounded pages and
remain behind the legacy gate until final validation. A partially copied
membership graph is not exposed as a complete V1 server.

**The engine (ADR-182).** `functions/servers/migration_apply.js` implements
steps 4-6 above. Three stages per root, in the only safe order — **members**
(add `authorizationRevision`, create `memberAuthorizations`), **channels**
(derive `kind`, pin `accessMode: "members"`, write `accessPolicy`, revisions,
`historySource`), then **root**. The first two are additive and inert while the
root is unversioned, so legacy Rules still govern the space and an interrupted
run leaves a Club that behaves exactly as it did. "Inert" is load-bearing and
has one sharp edge: the `liveness` projection is deliberately NOT written by
the channels stage, because `noClientChannelLiveness()` refuses a legacy
manager's channel update whose post-write document carries a `liveness` map —
staging it would break rename, reorder and delete for that Club's managers for
as long as the window lasted. It is written in the same transaction that
versions the root, where that legacy rule no longer applies to anyone. Writing the
root is the only irreversible step, so it goes last, it is what the client gate
guards, and its transaction re-reads liveness so a session that starts mid-run
defers the root instead of racing the write. Each stage is one transaction that
buffers its writes and flushes them only after every validation passed; the
run's step record — stage, member cursor, member count, source fingerprint — is
written in that same transaction, which is what makes resume exact. Every write
is a patch reduced against the observed document, so a re-run is a zero-write
no-op. Write mode refuses anywhere but a local emulator and `applyReady` is
permanently `false`.

**Refusals come from one registry, not from prose.** `V1_CLIENT_READ_PATHS`
records what a client can still read once a root is versioned, read off the
committed Rules. Legacy content whose read path is `false` and which is
**non-empty** refuses the root by name: `clubs/{id}/moments`,
`clubs/{id}/checkIns`, a bound room's `rooms/{id}/messages`, a bound room's
cover (`imageUrl`, whose only read path is `getRoomCoverMediaAccess` and which
denies once the parent is versioned), Club artwork under
`/clubs/{uid}/{clubId}/**`, and any legacy `status: "pending"` invitation.
ADR-E's family exclusion is the conjunction of the three family flags, so it
stops firing by itself when those Rules branches land.

**A Club's rooms are found from the room side, not only from the Club's
pointers (ADR-189, proven in ADR-190).** The boundary the migration crosses is
keyed on `room.clubId` — `firestore.rules` `isLegacyRoomData()` reads it, and
`functions/clubs/deletion.js` and `functions/clubs/voice.js` both enumerate with
`rooms.where("clubId","==",clubId)`. The liveness, transient-participant,
stranded-history and bound-cover probes therefore run over the UNION of
`channel.roomId`, `root.loungeRoomId`, the lazy `club_lounge_{clubId}`
convention, and a bounded back-pointer query that refuses the root
(`bound-room-set-exceeds-bounded-page-budget`) rather than paging past its
budget. Forward pointers alone missed a room a deleted voice channel left
behind, a lazily created lounge the root never recorded, and a room whose
channel pointer names something that is gone — each one live and
history-bearing, each one reading clean. `counts.boundRooms` in the manifest
counts rooms that exist, never the ids that were probed. `serverMigrationRuns/{runId}`
and its `rootSteps` subcollection are the run ledger and are denied to every
client.

### Old-client gate

The old client queries every channel with bare `orderBy(position)`. Rules deny
that whole query; they do not filter it. Additive fields do not by themselves
make that read backward compatible.

**Corrected 2026-09-12, measured on the emulator, not assumed.** The sentence
that used to stand here said the denial began "once a collection contains
properly protected restricted documents". It does not. `isLegacyClub()` reads
the **root**, so the denial begins the instant the root carries any of the
three server markers — with every channel `accessMode: "members"` and no
restricted document anywhere in the collection.
`firestore-tests/server_rules.test.js` proves both halves against a live
emulator: the real bare `orderBy('position')` query succeeds against an
unversioned twin and is denied, wholesale, against a migrated root; adding a
restricted channel changes neither result. The installed client renders that
`permission-denied` as an empty channel list, because its `StreamBuilder` has
no error branch — so the failure is silent to the person using it, which is why
the gate must be enforced before the write rather than detected after it.

**The mechanism (ADR-183).** Two published pieces, both required before any
root is versioned:

- `serverMigrationGates/clientCompatibilityV1` — server-written, readable by any
  signed-in caller, writable by nobody
  (`firestore.rules`, `match /serverMigrationGates/{gateId}`). It carries
  `minimumClientVersion`, `minimumClientBuild`, a `platformMinimumBuild` floor
  for every platform the app builds for, `status` (`open`/`satisfied`), a
  monotonic `revision`, and the uid and time of whoever attested it. A platform
  floor may be stricter than the global minimum and never laxer; a missing or
  malformed gate is an OPEN gate, never an absent constraint.
- An operator-supplied installed-base census of `{platform, build, sessions}`.
  Nothing in this repository observes live client versions, so this is evidence
  a person supplies. An absent census is `unknown` and refuses; any incompatible
  session refuses; an unrecognised platform counts as incompatible.
  **Zero observations is the same `unknown` (ADR-189).** An empty census, a
  census whose rows all report `sessions: 0`, and a census that does not
  observe every platform in `CLIENT_PLATFORMS` are each `supplied: false` and
  refuse through the same `client-compatibility-census-not-supplied` reason.
  An empty array used to satisfy the gate outright, which made the one control
  standing between a migration and every installed client losing its channel
  list pass by the *absence* of evidence. A run therefore needs a row with a
  real session count for each of the six platforms.

`functions/servers/migration_gate.js` is the contract and its pure evaluator;
`functions/servers/migration_apply.js` reads the gate **inside** the
transaction that versions the root and pins its `revision` to the one the
operator reviewed. The apply engine refuses a missing, malformed or stale
`expectedGateRevision` before it creates a run ledger or stages a write, and
the CLI requires `--gate-revision`. The root transaction re-reads that exact
revision, closing the review-to-apply TOCTOU window. The three reversible
stages may be resumed only within the pinned run; only the root flip crosses
the client compatibility boundary.

Keep existing spaces on the legacy contract until the compatible client cohort
and idle-upgrade conditions are met. New restricted V1 spaces require the new
client/capability gate. The chosen gate must also cover old callable paths;
mixed-version acceptance explicitly verifies safe denial/upgrade guidance for
unsupported spaces, and continued behavior for retained legacy spaces. A
future safe directory adapter is a separate implementation, not permission to
weaken content Rules. Do not claim old unrestricted queries pass after upgrade.

### Rollback

Keep before-images for migration-owned additive fields and generation
preconditions. Remove a generated record only when it is provably untouched
and no later user content, membership or reference depends on it. Otherwise
roll back the entry/capability flag and retain data for forward repair.

Never restore broad legacy Rules over newly private server/channel data.
Removing `serverSchemaVersion` can itself reopen a legacy read branch and is
not a safe generic inverse. Rollback must preserve the stricter authorization
boundary. Media cleanup is generation-scoped and separately recorded; an
operator rollback does not delete original media or history.

## Global integration and compatibility inventory

Generate canonical `?server=<id>&channel=<id>` links while retaining `?club=`,
`?room=` and legacy `/rooms/<id>` resolution. The link adapter reads an existing
mapping and rechecks access; it neither migrates data nor starts capture.
Existing notification types and preference keys remain valid while visible
copy and routing use Servers. Maintain all unrelated destinations: accounts,
profiles, friends, DMs, 1:1 calls, Moments, Reels, notifications, settings,
moderation and current entitlements.

| Transitional term/contract | Why it remains | Removal condition |
| --- | --- | --- |
| `clubs` collections, `clubId`, six stored roles, legacy `type` | Shared data/authority and historical IDs | Explicit future data/consumer migration; not a find-and-replace |
| Club callable names and old Dart adapters | Installed clients and existing integration contracts | Compatible client retirement plus verified absence of old traffic |
| `clubInvite`, `clubInviteAccepted`, related notification IDs | Preferences, histories and website consumer | Coordinated versioned notification migration |
| `publicShowcase.clubs`, Club consent keys | Website's exact aggregate parser and consent boundary | Versioned aggregate rollout on both sides, preserving opt-in privacy |
| `?club=`, `?room=`, `/rooms/<id>`, website `/clubs` | Saved links and old messages | Retain redirects/adapters until explicit retirement; no automatic expiry |
| Historical ADRs, sessions, published campaign logs | Evidence of prior product/release state | Remain historical; do not rewrite evidence |

The adjacent [website](</Users/kamil/Documents/GitHub/yovoice-website>) contains
current Club navigation, `/clubs`, Premium copy, feature/FAQ pages, account
notification labels and `public-showcase.ts`. Change visible product wording
and add `/servers` with an old-route redirect; preserve exact wire keys and
consent checks until their coordinated migration. The adjacent
[marketing repository](</Users/kamil/Documents/GitHub/yovoice-marketing>) is
Markdown/content, not a second Firebase client. Update current reusable
product briefs and copy, preserving published historical logs and references
to other products such as Clubhouse. No separate website redesign is in scope.

## Acceptance checklist and evidence

The checklist deliberately starts open. Implementation agents may satisfy
individual items only with named evidence; a successful selector, source file,
test fixture or callable definition does not satisfy the complete migration.

- [ ] Five selector cards match the accepted HTML and create the chosen type;
      configuration preserves draft fields, explicit privacy and retry identity.
- [ ] Creation persists one owner and one template channel set; empty state is
      real; all five types are available within the approved free allowance.
- [ ] Server shell, channel navigation and global conversation dock work on
      phone/tablet/web/desktop without disrupting unrelated product routes.
- [ ] Friends has multiple working text/voice channels and event RSVP.
- [ ] Community has real video broadcast, audience/chat, moderation and a
      distinct ordinary conversation lounge.
- [ ] Podcast has audio stage/queue/Q&A/votes/reminders and actual
      recording→processing→playback→publication, including failure recovery.
- [ ] Family has private calendar/RSVP/reminders, memories, shared list,
      check-ins and authorized artwork/media.
- [ ] Company has restricted HR/management channels, meeting camera/screen,
      chat/files and a persistent collaborative board with own-operation undo.
- [ ] Channel/category create/rename/reorder/access/archive/delete, invites,
      leave/removal/bans and ownership transfer work with canonical authority.
- [ ] Membership/role/access changes revoke direct reads, writers, private
      media and active publishing; all legacy endpoints enforce V1 boundaries.
- [ ] Token/session isolation and revoked-token replay are verified; no
      cross-server/channel/session credential grants another scope.
- [ ] Migration has deterministic dry-run/report, replay tests, relation/count
      validation, idle deferral, quota mapping and safe rollback evidence.
- [ ] Old and new clients are tested against legacy/V1 schemas and the chosen
      minimum-client gate; saved links and notification targets resolve.
- [ ] Current product/navigation/paywall/search/profile/settings/notification
      text and localization use Servers; controlled remnants are inventoried.
- [ ] Current documentation describes the implemented result and marks every
      remaining dependency; no fabricated activity or unexplained dead CTA.
- [ ] Owning engineering, QA, design, visual, accessibility, security,
      adversarial and final reviews required by [AGENTS.md](../AGENTS.md) finish
      with actionable findings addressed. Media/reliability and
      moderation/privacy/entitlement specialists review their affected areas.

Automated verification includes meaningful model/migration/idempotency and
channel/session tests, actual Firebase emulator authorization queries, denied
direct private reads, old-writer bypass attempts, concurrent creates, stale
invites/memberships/ACLs, cleanup retries and existing-feature regressions.
Exercise real `collectionGroup()` queries if a new path uses them; point reads
are not a substitute. Run clean `flutter analyze` and the relevant project
gates from [TESTING.md](TESTING.md). Emulator success does not prove deployed
indexes exist or that provider integrations work.

Rendered verification covers all five templates at **320, 390, 768, 1100,
1440 and 1920** logical pixels, small height, 200% text, long names, Polish and
other supported localization behavior, keyboard, focus, scrolling, rotation,
safe areas, reduced motion and Pearl where supported. For each type inspect
loading, empty, populated, denied, network-error/retry and return navigation,
plus before/during/after a conversation. Compare controlled real Flutter
renders side-by-side or overlaid with the corresponding reference interiors
at matched width/theme/state. Demonstration fixtures never enter the normal
authenticated creation flow.

Media acceptance requires at least two clients and representative supported
platforms. Record physical-device tests separately; if unavailable, mark the
specific result **UNVERIFIED**. A screenshot cannot pass transmission,
microphone cleanup or shared-board synchronization.

| Evidence category | Status at this document's creation |
| --- | --- |
| Source audit / facade decision | Completed locally; direction accepted for implementation |
| Owned Server capacity | 5 for Free, 30 for active paid Premium; Family counts in the same allowance and remains max 1; joins unlimited |
| Implementation and automated tests | In progress; no completion claimed by this document |
| Reference comparison / accessibility | Required; no acceptance claimed by this document |
| Firebase emulator migration/security | Required; no result claimed by this document |
| Two-client media / physical devices | Required; unverified here |
| Production data migration / deployment | Not performed and not authorized by this task |

## Separate release sequence

### Local security implementation checkpoint

The V1 Firestore/Storage boundary and legacy authorization consumers have
local regression coverage in
[server_rules.test.js](../firestore-tests/server_rules.test.js) and
[server_legacy_boundary.test.js](../functions/test/server_legacy_boundary.test.js).
The isolated emulator run passed 31 Rules/Storage scenarios and 20 callable
boundary scenarios, including genuine filtered queries, broad old-query
denial, stale/cross-scope grants, membership removal, cached token/chat/report
replay, held staff restore and public artwork refusal. The existing Firestore
suite passed 564 scenarios. The Family bootstrap regression uses the exact
seven-document client batch and covers transferred ownership, valid and
malformed reservations, atomic refusal, tamper attempts and successful
legacy creation without a reservation. These results are local evidence only, not a
claim that the full feature checklist or independent review is complete.

Before any in-place migration, outstanding legacy upload leases/reservations
must be drained or invalidated and durable download tokens revoked. The
existing room upload rule spends its two cross-service document reads on
profile and reservation; a third live server-root lookup is not an available
revocation mechanism. No legacy uploader may carry a live reservation across
the version cutover. The migration implementation, full private media flow,
session lifecycle, source-specific RTC enforcement, provider integrations,
mixed-client gate and independent adversarial review remain release gates.

### Reviewed runtime and offline mapping checkpoint — 2026-09-11

The unexported session factories passed independent Node22 emulator QA 83/83
and security/realtime/final review after closing duplicate per-recipient
revocation and historical terminal-convergence defects. Unknown provider
outcomes remain blocked; elapsed lease time never proves a pending removal
finished. Recovery uses authorized whole-generation end rather than blindly
retrying the same identity in a live generation.

The subsequent immutable-target convergence bridge passed independent
Node22 emulator QA **111/111** and Principal/security/realtime review, with a
fresh **28/28** reviewer subset. It connects mutation receipts to internal
ledger cleanup without completing uncertain work or restoring stale grants.
The later registration and bounded Firestore cleanup slices connect this
runtime behind exact `YOVOICE_SERVERS_V1=enabled`; the production flag remains
absent, so the endpoints are still inactive. Global consumer cutover and
provider acceptance remain release gates. The historical
V1 endRoom fanout caveat is closed by the subsequent reviewed adapter slice:
direct terminal DeleteRoom follows durable revocation readiness. The extended
runtime/bridge union passed 128/128 and a new independent terminal set passed
11/11 twice, without skips. These overlap earlier focused counts and must not
be added as a complete Functions total.

The preceding paragraph records the 2026-09-11 checkpoint. Its environment
registration design is superseded by ADR-176's static export/runtime-gate
model; its runtime and dispatch evidence remains historical evidence only.

The pure root/room mapping report passed independent 33/33 and final review.
It reports partial V1 boundaries and owner conflicts, preserves IDs and
allocation provenance, and always returns `applyReady:false`. It is not a
complete inventory, apply engine or rollback. No production data was read or
written by it. Details and unfulfilled integration/provider/device gates are
in [the checkpoint](Sessions/2026-09-11-servers-runtime-and-mapping.md).

### Offline inventory page integrity — 2026-09-11

`functions/servers/migration_inventory.js` now provides the pure
`inspectLegacyMigrationInventory` helper. This is **inventory-page-chain-only**,
not a collector or full inventory. It has no production importer, SDK, I/O,
clock, mutation, role-conversion or activation path. The existing mapper and
its required-next-gates list are unchanged; see ADR-175.

The exact input is `{inventoryVersion:1, source, observedRoot, readTime, pages}`.
`source` contains `{kind,id,path,expectedUpdateTime}`; `observedRoot` contains
`{path,updateTime,readTime}`. Both use the same canonical `clubs/{id}` or
`rooms/{id}` parent. Each page contains exactly
`{scope,parentPath,readTime,pageIndex,startAfter,nextCursor,exhausted,records}`;
each record contains only `{id,updateTime}`. Timestamps retain integer seconds
and nanoseconds. Every claimed read time must match; observed root/record
updates cannot be later than that read time. A different expected root version
marks every present scope unresolved rather than authorizing stale input.

Required scopes are fixed: Club `members`, `invites`, `channels`; room
`roomMembers`, `participants`, `messages`. An omitted scope is not an empty
collection. Indices start at zero; cursors match the preceding page and IDs
strictly increase by UTF-8 bytes. Nonterminal pages must make progress; a
terminal page may be empty or nonempty. No page follows exhaustion. Unsupported
scopes, foreign parents, gaps, duplicates or malformed values reject uniformly.

Limits are 1000 pages per input, 500 records per page and 10000 records overall.
Root IDs follow the existing mapper's ASCII 1–128 envelope; record/cursor IDs
support 1–128 UTF-16 units of well-formed Unicode, without slash, control
characters, dot/dot-dot or reserved `__...__` IDs. This is deliberately narrower
than general Firestore IDs, including imported numeric IDs; unsupported data
must be reported by a future collector and never silently omitted.

The report contains claimed coverage, counts, exact root versions and a digest
binding canonical page metadata without emitting record IDs. Root identity
remains in the local report. Read time and exhaustion are supplied claims,
not authenticated observations; a digest is not completeness or privacy proof.
`fullInventoryComplete:false`, `applyReady:false` and `writeCount:0` always remain.
Nested channel content, media/generations, mirrors, bans, membership semantics,
concurrent snapshots, quota/idle checks, apply and rollback are still unverified.
Independent QA and Principal/adversarial review passed 78/78 focused cases
(18 new author, 27 new independent, 33 unchanged mapping); this does not close
the full migration checklist above.

### Authorized-later deployment order

Prepare concrete deploy artifacts and reviewed migration reports before asking
for the final production action. Follow [DEPLOYMENT.md](DEPLOYMENT.md); this
sequence is a plan, not an instruction to deploy now.

The production sequence must use the exact-SHA package generated by
`tool/servers_activation_package.js`. Record its returned `manifestSha256` in
an operator-controlled file outside both the clean source and package, pass the
exact commit and external manifest hash to `--prepare-dependencies`, and run the
same anchored `--verify` after preparation and immediately before every
dry-run/deploy. Generic `firebase deploy`, `firebase deploy --only functions`,
`npm run deploy` and `npm --prefix functions run deploy` commands are forbidden
for this release. They can publish source-static Server exports outside the
reviewed phases. A production deploy still requires the maintainer's explicit
authorization.

1. Create `appConfig/serversV1` as `disabled`, with an empty tester list,
   workers off and revision 1. Refuse to overwrite an existing document.
2. After the exact Build 27 non-Server selectors, deploy and read back the
   generated phase-0 compatibility selector, then the generated phase-1 inert
   Server worker selector. `createRoom` belongs to phase 0 and must not also be
   appended to the earlier non-Server batch. Keep callables disabled and
   workers off.
3. Deploy indexes and wait for READY; deploy Firestore/Storage Rules and the
   generated phase-2 non-creation selector. Run cross-account and cross-server
   negative probes.
4. Enable workers only, verify a no-work pass, then deploy `createServerV1`.
   It must be the sole target in the generated phase-3 selector. Prove an
   intended tester is still refused while callable access is disabled.
5. Atomically move to `testers` with the exact intended Auth UID list. Complete
   one disposable Friends-server create/channel/message/session cleanup canary
   and prove a non-allowlisted account remains refused.
6. `callableAccess: all` is a later reviewed revision with an empty tester list.
   Legacy-root migration and Podcast recording/Egress remain separate releases.

### Named activation preconditions — updated 2026-09-13

Activation is the moment held anchors become discoverable and joinable by legacy
queries and RTC consumers. Four preconditions are named here because deployed
indexes, deployed revisions and provider behavior are invisible to ordinary
emulator tests. Static export discovery does not discharge any of them. Keep
`appConfig/serversV1.callableAccess` disabled until the rollout read-backs and
negative probes in DEPLOYMENT.md pass.

1. **The `channelSessions.livekitRoomName` collection-group index must be
   verified as deployed, not merely committed.** The field override exists in
   `firestore.indexes.json`, and a committed override is not a deployed index.
   `resolveRtcBindingForLiveKitRoom` issues a `collectionGroup("channelSessions")`
   query; with no index it throws `FAILED_PRECONDITION`. The revocation itself
   still happens, so the boundary stays fail-closed and no sanctioned identity is
   left connected. The enforcement event can then never reach `completed`, so
   every event touching a `srv_` provider room becomes a permanent retry loop.
   Read the project's deployed index list before activation and record what was
   observed, never the intent to deploy.
2. **The `channels` composite index must be verified as deployed, not merely
   committed.** The all-member channel query pins `accessMode ==` and
   `status ==` and orders by `position`, which needs the
   `channels(accessMode ASC, status ASC, position ASC)` COLLECTION-scope
   composite index now committed in `firestore.indexes.json`. A committed
   index is not a deployed index. Emulators create indexes on demand, so this
   query passes every local suite and fails only in production, with
   `FAILED_PRECONDITION` on the client's first real channel list — the same
   failure mode as precondition 1 and as the Premium expiry defect recorded in
   [Firebase.md](Firebase.md). Read the project's deployed index list before
   activation and record what was observed, never the intent to deploy.
3. **The enforcement retry must gain a ceiling before activation.**
   `staff/voice_enforcement.js` rethrows `unbound-live-generation` under a
   `retry: true` trigger with no terminal state, and every attempt re-runs
   `findParticipantRooms`, which is one `listRooms()` plus one `getParticipant`
   per room. On its own that is a bounded annoyance. Combined with precondition
   1 it turns a single stalled event into an unbounded loop of O(all rooms)
   provider calls with no dead-letter.
   **Closed in source on 2026-09-12 (ADR-179), not yet deployed:** the eighth
   `unbound-live-generation` attempt (`MAX_UNBOUND_GENERATION_ATTEMPTS`)
   writes the terminal `status: "needsReconciliation"` with
   `lastErrorCode: "unbound-live-generation"`, logs an ERROR naming the event
   id, and returns instead of rethrowing; every other failure class keeps
   retrying. The deployed Functions still carry the unbounded version until
   the next Functions deploy, so the precondition stays listed until that
   deploy is verified.
4. **The provider's empty-room semantics must be verified against LiveKit
   Cloud, not the emulator, before the stale-generation sweep is trusted.**
   `sweepStaleServerChannelSessionsSchedule` (ADR-180) reads "nobody is here"
   from `ListParticipants` returning zero participants or NOT_FOUND (LiveKit
   deletes an empty room after its `emptyTimeout`). Every local suite proves
   the sweep against a stub adapter. Before activation, observe against the
   real project that an ended-and-empty `srv_` room answers NOT_FOUND or an
   empty list, and that a room holding a participant whose JWT has expired
   still lists that participant — the sweep must skip that room, and the
   staleness tests encode exactly that expectation. Record what was observed.
   Until then a misreport can only err on the side of leaving a stale badge
   in place: a provider error or any non-integer answer is treated as
   occupied, so the failure mode is honesty debt, never an evicted room.

   **Preflight observed 2026-09-13:** the LiveKit Cloud canary passed and its
   sanitized evidence was retained in the activation package. This closes the
   provider observation for the current provider configuration; repeat it if
   that configuration changes. It does not replace the production export,
   index, Rules or runtime-gate read-backs above.

The final handoff must state what actually works for each template, where to
open the app and visual comparisons, test categories/results, migration
status, remaining blockers and exact separate release steps. Until all target
requirements have their evidence, the full server migration remains open.
