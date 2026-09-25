# Task 2a — server channel messaging parity with DMs (branch `nb/server-messaging`)

Everything the shared docs need for this branch, written here so the two PC
branches and the Mac cannot collide on ADR numbers or on the same paragraph.
Fold each section into the named file at integration; nothing in
`docs/Decisions.md`, `docs/SECURITY.md`, `docs/Roadmap.md`, `docs/Bugs.md`,
`docs/Servers.md` or `docs/Firebase.md` was edited on this branch.

Base: `origin/main` f71a2ae2 (3.0.0+34). Commits on this branch:

| commit | subject |
| --- | --- |
| `dc1e7c40` | feat(servers): emoji reactions on server channel messages, DM style |
| `e5d873fc` | fix(servers): keep the emoji input in the channel composer while membership loads |
| `03f6eff1` | feat(rules): reservation-bound Storage path for server channel photos and videos |
| `4dc6cde9` | feat(functions): photo and video messages in server text channels |
| `a0c668fa` | feat(servers): send and view channel photos and videos in the app |
| this one | docs(briefs): the Task 2a integration brief |

---

## 1. `docs/SECURITY.md` — new section

Place after "GIF trust boundary" and before "Account deletion".

### Server channel reactions and media (source only, NOT deployed)

Server text channels now carry direct-message-style reactions and private
photos/videos. Both are **Admin-SDK-only writes on the existing club message
store**: `firestore.rules`'s `clubs/{clubId}/channels/{channelId}/messages`
match is unchanged — `create: if false`, V1 `update` false, `delete` false —
so no client predicate was widened to ship either feature.

- **Who may react is derived inside the callable, never stored as a
  capability.** `setServerChannelMessageReactionV1` requires the channel's
  `read` capability (including a current restricted-channel grant), a
  non-guest role, an active profile, a verified e-mail and no communication
  mute. A `react` key was deliberately NOT added to `capabilitiesFor`
  (`functions/servers/authority.js`): `grantMatches` compares a stored
  `accessGrants` document against `capabilitiesFor` with an exact key count,
  so a new key would invalidate every stored grant and lock members out of
  their private channels. Ordinary members may therefore react in
  announcements and rules channels, where only moderators may post.
- **The reaction map is bounded and validated, never repaired.** One reaction
  per person from the fixed direct-message six (imported from
  `ALLOWED_DIRECT_REACTIONS`, not copied), at most 500 reactors per message
  (a new reactor past the cap is `resource-exhausted`; changing or removing
  an existing one is not), 60 reactions per minute per account, and a
  malformed stored map fails `data-loss` rather than being rewritten.
- **Upload authority is one live reservation, never the path.**
  `storage.rules`'s new `server_message_media/{serverId}/{channelId}/{userId}/{fileName}`
  accepts a create only for a verified, active uploader whose exact custom
  metadata set {`yovoiceServerId`, `yovoiceChannelId`, `yovoiceOwnerUid`,
  `yovoiceMessageId`, `yovoiceMessagePath`, `yovoiceMediaType`} matches the
  path and whose `serverMessageMediaUploadReservations/{messageId}` document
  (the second and last cross-service read) matches on every field including
  `status: 'uploading'` and `expiresAt > request.time`. Bounds are the DM
  ones: image jpeg/png/webp 128 B–8 MiB, video mp4/quicktime/webm
  1 KiB–64 MiB, duration 1–60 s. `list`, `update` and `delete` are false and
  `get` exists only for the uploader while their reservation is live (upload
  recovery).
- **Viewers never read bytes through Storage rules.** The two-document
  cross-service budget cannot evaluate a V1 channel ACL (root + member +
  profile + channel + grant), so playback uses
  `getServerChannelMessageMediaAccessV1`: up to 20 message ids per call, the
  channel ACL and mute re-checked, removed/non-media/missing ids reported
  `unavailable`, object metadata re-verified against the stored descriptor,
  90-second generation-bound V4 URLs, and the whole batch re-authorized after
  signing (a revision or descriptor change answers `aborted`). This is the
  Company Files pattern.
- **Publication is server-owned end to end.** Finalize validates metadata,
  runs the trusted GCS probe under the DM contract (real image/video bytes,
  track presence, duration within 1–60 s and within 2 s of the declaration),
  re-reads metadata, revokes the durable download token generation-guarded,
  then in one transaction re-authorizes `write`, consumes the same
  `club.message.send.{server}.{channel}` bucket `sendClubMessage` uses and
  writes `{type, mediaUrl: 'gs://…', media: {schemaVersion, storagePath,
  generation, contentType, size, durationSeconds}}` plus the
  `content: 'Photo'|'Video'` fallback installed clients render.
- **Removal.** A moderator uses the existing `moderateClubMessage`, which now
  also deletes `media`, `mediaUrl` and `reactions` and writes a durable,
  generation-guarded object deletion job in the same transaction; its rank
  ordering and owner protection are unchanged. An author uses the new
  `deleteServerChannelMessageV1` (author only, allowed while muted or
  unverified, like the legacy author branch of the club-chat rule), which
  closes the long-standing gap that a V1 author could not retract anything.
  Staff removal (`adminDeleteMessage`) needed no change: the object metadata
  binds `yovoiceMessagePath` and `yovoiceOwnerUid`, which is exactly what its
  attachment sweep requires.
- **Deletion reaches the bytes.** Channel and server deletion write prefix
  sweep jobs (`server_message_media/{serverId}/{channelId}/` and
  `server_message_media/{serverId}/`) drained page by page, generation
  guarded, by `processServerChannelMessageMediaDeletionJobs`; abandoned
  uploads are removed by `expireServerChannelMessageMediaReservations`; and
  account deletion now sweeps the account's own objects across every server
  through the Admin-only `serverMessageMediaObjects` owner index (the uid is
  the fourth path segment, so no uid prefix delete could reach them).
- **Residual, stated rather than hidden**: an issued V4 URL remains a bearer
  capability for at most 90 seconds after a ban, a leave or a removal — the
  same residual the private-media section already accepts. `adminDeleteMessage`
  leaves the now-unreferenced `media` descriptor on its tombstone (path and
  generation only, the object is deleted). Reaction writes are a transaction
  on the message document, so a very popular announcement can see retries;
  the upgrade path is a `reactions/{uid}` subcollection and needs its own ADR.
  Five new collections (`serverMessageMediaUploadReservations`,
  `…Leases`, `…Budgets`, `serverMessageMediaDeletionJobs`,
  `serverMessageMediaObjects`) are `allow read, write: if false` for every
  client, staff included.

Evidence on this branch: Storage/Firestore rules
`firestore-tests/server_message_media_rules.test.js` 9/9, existing storage
76/0 and firestore 577/0, Functions `server_message_reactions` 14/14,
`server_message_media` 21/21, `server_message_media_admin_delete` 2/2,
moderation 8/8, account deletion 46/46, Flutter 464 across the 32 suites that
touch the changed files plus 25 new cases.

---

## 2. `docs/Decisions.md` — new ADR (number left as ADR-XXX)

### ADR-XXX: server channel reactions and media are Admin-SDK-only, and the "react" permission is derived in the callable, never stored in a channel grant

**Context.** Server text channels reuse the legacy club message store
(`clubs/{s}/channels/{c}/messages`), which was built text- and GIF-only: no
reaction field, no media, no callable, and no context action on the tile. DMs
have had one-reaction-per-person and private photo/video for two builds. The
obvious way to add "may react" to a V1 channel is a new capability key in
`capabilitiesFor` (`functions/servers/authority.js`).

**Decision.**
1. Reactions are a `reactions` map (uid → emoji) on the message, written only
   by `setServerChannelMessageReactionV1`, with the fixed DM vocabulary
   imported from `direct_integrity.js`. The `react` permission is **derived
   inside the callable** from the channel's `read` capability plus role,
   profile, mute and verification — `capabilitiesFor` is untouched.
2. Photos and videos follow Company Files exactly: a reservation-bound
   Storage path, a finalize that probes the bytes and revokes the download
   token, batched 90-second generation-bound V4 read grants issued by a
   callable that re-runs the channel ACL, and durable generation-guarded
   deletion jobs. The message keeps a `content: 'Photo'|'Video'` fallback so
   installed clients render a readable line.
3. A new author-only `deleteServerChannelMessageV1` gives V1 authors the
   retraction the rules never allowed them.
4. The five new callables and two schedules are registered through a
   **separate extension table** in `functions/servers/registration.js`
   (`SERVER_MESSAGE_CALLABLE_METHODS`, built by
   `createServerMessageFunctions`), outside `ALL_SERVER_CALLABLE_METHODS` and
   `SERVERS_V1_EXPORT_NAMES`.

**Reasoning.** `grantMatches` compares a stored `accessGrants` document to
`capabilitiesFor` with an **exact key count**, so adding `react` would have
invalidated every stored grant and silently removed read access to every
restricted channel until a sweep rewrote them — a lockout, in exchange for a
permission the callable can derive for free. Keeping the messages rule
untouched means neither feature widens a client predicate: Storage rules can
authorize an upload against a reservation (two cross-service documents) but
cannot evaluate a V1 channel ACL, which is why reads are a callable grant.
The separate registration table exists because the reviewed Servers manifest
is pinned at 61 total / 55 callable / 54 base by
`tool/servers_activation_package.js`, the registration suites and the frozen
table in `docs/Servers.md`; spreading six new names into it would have
rewritten those numbers and the activation package's phase plan for a feature
that deploys on its own selector anyway.

**Consequences.**
- Members can react in announcements and rules channels they cannot post in;
  guests can react nowhere.
- The reaction map is capped at 500 reactors per message; a busy announcement
  contends on one document. The upgrade path (a `reactions/{uid}`
  subcollection with counters) is a schema change and needs its own ADR.
- Media reads cost one callable per ≤20 visible bubbles, cached until shortly
  before the grant expires; a minted URL stays valid for up to 90 s after
  access is lost.
- Account deletion gains a fifth Admin-only collection
  (`serverMessageMediaObjects`) purely so an author's objects can be found
  under other people's servers.
- The Servers export surface is now 54 base + 1 broadcast + 6 message-parity
  names, deployed by two selectors instead of one.

---

## 3. `docs/Bugs.md` — lines to add

- **Fixed (2026-09-19, source only):** *a V1 server author could not retract
  their own message at all.* `firestore.rules` allows a client message update
  only on a legacy club, so the app's "Delete" silently could not apply to a
  Servers V1 channel; posting a photo you cannot take back would have shipped
  with media. Closed by `deleteServerChannelMessageV1` (author only,
  tombstone plus a durable object deletion job).
- **Fixed (2026-09-19, source only):** *the emoji input vanished from a server
  channel composer whenever the viewer's membership row had not arrived yet.*
  `ClubChatAuthority.canSendToChannel` is false both for a real refusal and
  for "not known yet", and the scene swapped the whole composer — emoji
  button and panel included — for the read-only sentence on that predicate.
  Now only a resolved refusal does (`showsReadOnlyNotice`).
- **Known limit (new):** a moderator's redaction of a media message removes
  the object through a durable job drained every 10 minutes; between the
  redaction and that sweep the bytes exist but are unreachable (no grant is
  issued for a removed message).
- **Known limit (new):** `adminDeleteMessage` strips `mediaUrl` but leaves the
  `media` descriptor (path + generation) on the tombstone; the object itself
  is deleted by its metadata binding.
- **Account deletion (update the existing entry):** `server_message_media` is
  **swept** (through the `serverMessageMediaObjects` owner index), so the
  cross-container gap list shrinks to `family_moments`,
  `server_company_files`, `room_images` and `server_podcast_episodes`. The
  public `/delete-account` copy in `yovoice-website` should drop
  channel photos/videos from "what deleting your account does not do" **only
  after** this branch's Functions are deployed.

## 4. `docs/Roadmap.md` — lines to add

- **Done (source, pending deploy):** Server channel messaging parity with DMs
  — emoji reactions, photo/video messages, author retraction, moderator and
  staff removal paths, channel/server/account deletion sweeps
  (`nb/server-messaging`).
- **Next:** adopt Task 4's shared preview-and-confirm sheet on the server
  channel attach flow (this branch deliberately sends immediately, exactly as
  DMs do today, so there is only ever one confirm implementation).
- **Next:** server-side video thumbnails for channel media (needs ffmpeg or
  Transcoder; DMs have none either, so the poster placeholder is parity).

---

## 5. `docs/Servers.md` — additions

Leave the frozen 54-entry "Callable contract" table exactly as it is (a test
parses it). Add a new subsection after the OBS ingress extension:

### Message parity extension (6 exports, separate selector)

| export | service | notes |
| --- | --- | --- |
| `setServerChannelMessageReactionV1` | `messageReactions` | read capability + non-guest, DM's six emoji, 500 reactors, 60/min |
| `reserveServerChannelMessageMediaV1` | `messageMedia` | write capability, 15-min reservation, one live lease, 512 MiB/day |
| `finalizeServerChannelMessageMediaV1` | `messageMedia` | probe + token revocation + message publication (512 MiB, 120 s) |
| `getServerChannelMessageMediaAccessV1` | `messageMedia` | ≤20 ids, 90 s V4 grants, re-authorized after signing |
| `deleteServerChannelMessageV1` | `messageMedia` | author-only retraction + object deletion job |
| `expireServerChannelMessageMediaReservations` | schedule | every 10 min, drops abandoned uploads |
| `processServerChannelMessageMediaDeletionJobs` | schedule | every 10 min, object and prefix jobs |

They are built by `createServerMessageFunctions` (not
`createServersV1Functions`), behind the same `appConfig/serversV1` activation
gate and the same Auth binding, and are **not** part of the frozen 54-name
manifest or of `tool/servers_activation_package.js`'s phase plan.

## 6. `docs/Firebase.md` — additions

- **Storage table:** `server_message_media/{serverId}/{channelId}/{userId}/{messageId}.{jpg|png|webp|mp4|mov|webm}`
  — channel photos and videos. Create: verified, active uploader with a live
  server reservation and exact metadata; image 128 B–8 MiB, video 1 KiB–64 MiB
  and 1–60 s. Get: uploader only while reserved. List/update/delete: never.
  Reads: `getServerChannelMessageMediaAccessV1` V4 grants (90 s).
- **Collections (Admin-SDK-only, `allow read, write: if false`):**
  `serverMessageMediaUploadReservations/{messageId}`,
  `serverMessageMediaUploadLeases/{uid}`,
  `serverMessageMediaUploadBudgets/{digest}`,
  `serverMessageMediaDeletionJobs/{jobId}`,
  `serverMessageMediaObjects/{messageId}` (owner index: ownerId, serverId,
  channelId, messageId, storagePath, generation, createdAt).
- **Message schema (additive, on the existing club message document):**
  `reactions` map uid→emoji; `type: 'image'|'video'` (new values of the
  existing optional field); `mediaUrl` (`gs://`); `media
  {schemaVersion, storagePath, generation, contentType, size,
  durationSeconds}`; `content` carries 'Photo'/'Video' for media messages.
  Nothing renamed or removed. No new index: the sweeps use a single-field
  range on `expiresAt` and equality filters.

---

## 7. Deploy order and manual steps (for Kamil)

> **Superseded (2026-09-25).** Do not deploy from this section. The one deploy
> order for the whole next build is in
> [DEPLOYMENT.md](../DEPLOYMENT.md#next-build-after-300--one-deploy-order-for-the-whole-build-source-only-nothing-deployed),
> and it puts Storage Rules (step 2b) **before** the Functions that issue
> reservations, as ADR-216 requires — the order below has them second, which
> would refuse every upload after a reservation was granted.

1. **Functions first** — the six new exports plus the two changed ones:
   ```
   firebase deploy --only functions:setServerChannelMessageReactionV1,\
   functions:reserveServerChannelMessageMediaV1,\
   functions:finalizeServerChannelMessageMediaV1,\
   functions:getServerChannelMessageMediaAccessV1,\
   functions:deleteServerChannelMessageV1,\
   functions:expireServerChannelMessageMediaReservations,\
   functions:processServerChannelMessageMediaDeletionJobs,\
   functions:moderateClubMessage,functions:onServerControlOutboxCreated,\
   functions:processPendingServerControlOutboxSchedule,\
   functions:onAccountDeletionOutboxCreated,\
   functions:processAccountDeletionOutboxSchedule
   ```
   (the last four carry the content-cleanup and account-deletion changes).
   Read every one back ACTIVE in `europe-west1`.
2. **Confirm the runtime service account can sign V4 URLs** —
   `iam.serviceAccountTokenCreator` / `signBlob`, the same grant
   `getServerCompanyFileAccessV1` already relies on. Without it every media
   grant fails `failed-precondition`.
3. **Storage rules second**: `firebase deploy --only storage`. Until this
   lands every upload is denied (the path has no rule at all). Read the
   deployed ruleset back and diff it against `storage.rules`.
4. **Firestore rules third**: `firebase deploy --only firestore:rules` — only
   the five explicit deny blocks; default-deny already covers them, so this is
   hygiene, not a blocker. Diff the read-back.
5. **No index deploy.** If a future revision filters the reservation sweep on
   `status` as well as `expiresAt`, that needs a committed AND deployed
   composite `(status ASC, expiresAt ASC)`; the emulator will not tell you.
6. **App release afterwards.** Older installs keep working: they ignore
   `reactions` and show the server-written 'Photo'/'Video' line. Shipping the
   client BEFORE step 1 makes every attach and reaction fail; the UI maps
   `not-found`/`unimplemented` and the activation refusal to "This part of YO
   Voice is still being prepared", never a raw error.
7. **Website copy** (`yovoice-website`, manual): once step 1 is live, remove
   server channel photos/videos from the `/delete-account` "what deleting your
   account does not do" list — they are swept now. The other four prefixes
   stay listed.
8. **Smoke, in a test server**: react in a text channel and in an
   announcements channel as an ordinary member (both must work) and as a
   guest (must fail); send a photo and a 5-second video; reopen the thread on
   a second account to prove the grant path; retract your own media message
   and confirm the object is gone; have a moderator remove another member's
   media message and confirm the deletion job drains within one sweep.

---

## 8. Deviations from the investigation's design, with reasons

1. **Registration**: a separate extension table and builder instead of
   spreading into `ALL_SERVER_CALLABLE_METHODS`. The reviewed 61/55/54
   manifest is asserted by `tool/servers_activation_package.js`,
   `functions/test/servers_registration*.test.js` and the frozen
   `docs/Servers.md` table; spreading would have required editing those
   numbers, which the working rules forbid. Behaviour (activation gate, Auth
   binding, options, error mapping) is identical.
2. **Legacy clubs are refused `permission-denied`, not `failed-precondition`.**
   The design asked for `failed-precondition`; `readServerAccess` already
   denies a legacy, missing or private target with one indistinguishable
   shape, and keeping that avoids an existence oracle for legacy club ids.
3. **Content cleanup does not gain an inline Storage phase.** Channel and
   server deletion write durable prefix sweep jobs instead, drained by the
   new schedule. This keeps `CHANNEL_PHASES`/`SERVER_PHASES` and every
   existing cleanup-runtime constructor untouched (they have no media storage
   adapter) at the cost of bytes surviving for at most one 10-minute sweep
   after the documents are gone.
4. **Account deletion sweeps the prefix** (the task's instruction) rather than
   only documenting it. Because the uid is the fourth path segment, this
   needed a fifth Admin-only collection, the `serverMessageMediaObjects`
   owner index written by finalize.
5. **No preview-and-confirm sheet here.** Task 4 owns one shared confirm sheet
   for every immediate-send site; a second one on this surface would have to
   be deleted at integration.
6. **Reaction chips are the DM summary pill, not tappable count chips.** The
   task asked for "the same reaction affordance and display the DM bubble
   uses"; toggling happens in the actions sheet, where the viewer's current
   reaction is marked. `MessageReactionSummaryPill`/`MessageReactionPickerRow`
   live in `lib/shared/widgets/interactions/message_reactions.dart` with
   caller-supplied copy (ADR-209); the DM files were left untouched so their
   suites did not have to be re-baselined.
7. **The access grant does not re-harden object metadata** the way
   `getServerCompanyFileAccessV1` does; finalize already revoked the token
   generation-guarded, and the grant path verifies the metadata binding
   before signing.

## 9. Deferred / not done / unverified

- **UNVERIFIED visually.** No simulator or device run: the reaction pill, the
  actions sheet, the attach button, the sending row and the media bubbles are
  proven by widget tests at 390 / 768 / 1440 px, not by looking at them.
  CLAUDE.md's responsive rule wants a real look before this is called done.
- **Hover-revealed reactions on wide screens** and a desktop side-sheet
  actions menu were not built; the sheet is the adaptive modal DMs use at
  every width (right-click and the keyboard open it on desktop).
- **Video posters** are a placeholder with the duration; no server-side
  thumbnail (DMs have none either).
- **`functions/test/cold_start_module_graph.test.js` test 1 and the
  `servers_registration*` cold-start cases fail on Windows only**, before and
  after this branch: they compare `path.relative` output with POSIX
  separators. Verified identical against base f71a2ae2; the normalized module
  set matches the pinned list exactly (39/39).
- **`firestore-tests` `test:servers` is 68/3 with and without this branch** —
  its three Storage cases initialize a project id the Storage emulator's
  cross-service reads cannot see. Pre-existing; the new suite avoids it by
  using the emulator project, as `storage.test.js` does.
- Web uploads read the whole pick into memory (`putData`) rather than
  streaming; images are ≤8 MiB and videos ≤64 MiB, which bounds it. On io this
  was fixed after the gate below — see §11, the channel upload is now
  platform-split exactly as the DM store is.
- A signed grant lasts 90 s, so a video that buffers slowly may need a retry;
  the poster re-requests a fresh grant on every play.

## 10. Final gate evidence (2026-09-20, this worktree)

- `flutter analyze`: **No issues found!**
- Flutter: the **32** suites that import a changed Dart file, **464/464**,
  no assertion edited; of those, 25 cases are new
  (`server_message_reactions_test.dart` 9, `server_composer_emoji_test.dart` 5,
  `server_channel_media_test.dart` 11).
- Rules emulator: `test:server-message-media` **9/9** (new),
  `test:storage` **76/0**, `test` (firestore) **577/0**,
  `test:servers` **68/3 — the same 3 with and without this branch**.
- Functions emulator: `npm --prefix functions test` does not fit the shared
  emulator wrapper's 8-minute cap on this machine (two agents share the
  ports), so the same 171 files were run through the wrapper in six slices:
  `[a-c]` 422, `[d-m]` 547, `[n-p]+u+v` 238, `r` 401,
  `server_*`+`servers_[a-i]`+`stripe` 312, `servers_[j-r]` 296,
  `servers_[s-z]` 107 — **2323 tests, 2316 pass, 7 fail**, every failure a
  Windows-platform artifact in a file this branch does not touch:
  - 4 × "the cold-start Servers module set / base map is statically
    discoverable / registrationCached" — the inspectors build
    `process.cwd() + '/servers/'` and compare it with `require.cache` keys,
    which use `\` on Windows. Verified identical at base f71a2ae2, and the
    module set matches the pinned list **39/39** once separators are
    normalized (the numeric 61/55/54 assertions in the same tests pass).
  - 3 × POSIX file-mode assertions (`mode & 0o777 == 0o600 / 0o700`) in
    `direct_conversation_photo_poison_repair` and the two
    `servers_migration_collector` CLI tests; Windows reports `0o666`/`0o777`.
- `npm --prefix functions run test:smoke`: **exit 0** (all three binding
  smokes).
- `git status`: clean; nothing pushed, nothing tagged.

## 11. Channel uploads are platform-split (memory defect, 2026-09-20)

**The defect.** Sending a channel photo or video put the whole pick through the
Dart heap twice: the scene called `XFile.readAsBytes()` only to measure it
(`server_text_channel_scene.dart`, `_sendPickedPhoto`/`_sendPickedVideo`) and
`ClubChatService` handed that buffer to `reference.putData`, which copies it
again on the way out. A 64 MiB video therefore had a ~128 MiB transient peak —
an out-of-memory kill on a mid-range Android phone. Direct messages never had
this: their payload store is platform-split and uploads with `putFile`
(`direct_attachment_payload_store_io.dart:112`), keeping `putData` for the web
path only.

**The split.** `lib/features/clubs/data/services/club_media_upload_source.dart`
is the new seam, with the same conditional-import shape as the DM store:

| implementation | chosen by | how the bytes reach Storage |
| --- | --- | --- |
| `club_media_upload_source_io.dart` | `dart.library.io` | `putFile(File(pick.path), metadata)` — the plugin streams the file; only the handle and the length are retained |
| `club_media_upload_source_web.dart` | `dart.library.js_interop` | `putData(await pick.readAsBytes(), metadata)`, delegating to the stub's byte transport |
| `club_media_upload_source_stub.dart` | default | that byte transport |

The scene now measures with `XFile.length()` (a file stat on io, the Blob's own
size on web) and hands the `XFile` to the source.
`ClubChatService.sendServerMediaMessage` takes the source instead of a
`Uint8List` and still owns everything else — reservation, progress listener,
committed generation, lost-acknowledgement recovery — so the two platforms
differ in exactly one call. The injectable `mediaUploader` seam survives; it now
carries the source, whose `length` is what the reservation declares.

**What did NOT change.** What may be sent, and the backend contract. Image
128 B .. 8 MiB, video 1 KiB .. 64 MiB and the 60-second cap are still decided in
`_sendPickedPhoto`/`_sendPickedVideo` with the same failure copy; the reservation
still declares the size and finalize still checks the committed object against
it; no device path reaches a callable or the upload metadata. No `functions/**`,
`firestore.rules`, `storage.rules` or `firestore-tests/**` file was touched, so
no backend suite is implicated by this change.

**What it means for the integrating session.**
- **Web is unchanged.** Same `putData`, same bytes, same caps.
- **On io the bytes are read at send time, from the picked path.** The file must
  still exist and still be the declared length. If the OS evicted the picker's
  temporary file, or it changed size, the source refuses locally (a `StateError`
  the scene maps to the existing "could not be sent" copy) and the reservation
  is left unused — no object, no message, no retry loop. Before this change an
  evicted file was invisible, because the bytes had already been copied at pick
  time; this is the one new failure mode, and it is the same one Reels accepted
  in `reel_upload_transport_io.dart`.
- **An upstream review/confirm sheet (Task 4) is compatible** as long as it
  holds the same `XFile` and neither moves, deletes nor rewrites the file, and
  the send still happens while the pick is on disk. Previewing is safe: io reads
  the same path, web the same Blob. Anything that consumes or rewrites the pick
  (a resized copy, a move into app storage, a cleanup after preview) must hand
  the send the NEW `XFile` — a sheet that deletes the original after previewing
  it would turn a working send into the "no longer on this device" refusal.
- Tests: `test/server_channel_media_test.dart` covers the io path with a pick
  whose `readAsBytes()`/`openRead()` throw (it still sends, which is the proof
  the bytes are gone), the web transport's `putData` reached directly through
  `club_media_upload_source_web.dart`, the io refusals (moved / evicted file),
  and the full size and duration bounds — the 64 MiB edge without allocating
  64 MiB, since nothing reads the pick. One case writes a real temporary file
  under `Directory.systemTemp` because `putFile` streams a real file.
- Gate for this change: `flutter analyze` **No issues found!**;
  `server_channel_media_test.dart` **17/17** (6 new, no assertion edited) and
  the other **41** suites that import a changed Dart file **674/674**
  (14 direct importers 317, 27 transitive 357); no emulator suite re-run,
  because no backend file is touched. `git status` clean, nothing pushed or
  tagged.
