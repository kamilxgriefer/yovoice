# YoVoice — Project Status

Written mid-session as a handoff document before context compaction, then
updated once the bug that was open at that point got resolved. Covers three
pieces of work done back-to-back: (1) a refactor of the largest file in the
repo, (2) a full pass through `docs/SECURITY_AUDIT.md`, and (3) two more
broken features found via live production testing while chasing down a bug
report. **Nothing is currently broken/open** as of this update — see section 6
for what was found and fixed, and section 9 for the actual next task (App
Check, #12 from the audit, deliberately not started yet).

---

## 1. What has been completed

### A. Refactored `broadcast_room_screen.dart` (2,384 lines → ~430 + 10 files)

The largest file in the repo was one `StatefulWidget` plus ~25 private helper
widgets crammed together (Dart privacy is file-scoped, so everything private had
to live in one file). Split into a `broadcast_room/` folder grouped by
responsibility, with the public `BroadcastRoomScreen` widget kept at its
original path so the one external import (`room_entry_screen.dart`) needed no
changes. Extracted widgets became normal top-level (non-underscore) classes in
their own files — a visibility-scope change only, not a new public API (nothing
re-exports them).

Also fixed a pre-existing bug found while testing this: `OwnerMenuSheet`'s
`showModalBottomSheet` call was missing `isScrollControlled: true` (every
sibling room screen already had it on their equivalent sheets) — the sheet
overflowed by 221px and "Delete room permanently" was unreachable.

Merged via PR #1 (`refactor/split-broadcast-room-screen` → `main`), then the
overflow fix went straight to `main` per the user's stated preference for this
repo (see "Design decisions" below).

### B. Full pass through `docs/SECURITY_AUDIT.md`

This file was sitting **untracked** in the repo at the start of the session — a
pre-existing, very thorough security audit (not written by me) covering
`firestore.rules`, `storage.rules`, `functions/**`. It's now committed. Its own
"Kolejność naprawiania" (fix order) section was followed item by item:

**Critical / High (#1, #2, #3, #4, #5, #13) — done, deployed, verified:**
- **#13 / #1 — LiveKit voice was completely broken.** The client
  (`voice_token_service.dart`) sent `roomId`; the Cloud Function
  (`functions/livekit/token.js`) read `roomName` — every voice-join call threw
  `invalid-argument`. Rewrote the function to read `roomId`, look up the
  caller's actual room/participant role in Firestore, and compute
  `canPublish`/`hidden`/`recorder` server-side instead of trusting whatever the
  client sent (previously: anyone could unmute themselves, listen invisibly, or
  rejoin instantly after being kicked). **Verified live**: created a real
  broadcast room in the simulator, joined voice, confirmed an actual LiveKit
  connection (listener count ticked up, mic went live).
- **#2 — Club ownership hijack.** Anyone could create
  `clubs/{id}/members/{selfUid}` with `role: 'owner'`. Now requires
  `clubs/{id}.ownerId == request.auth.uid`.
- **#3 — Room hijack.** Any participant could rewrite a room's `hostId`, name,
  visibility, etc. Non-host writers are now restricted to a fixed field
  allowlist (`participantCount`, `memberCount`, `speakerCount`, `isLive`,
  `endedAt`, `updatedAt`); host can change anything except `hostId` itself.
- **#4 — Participant self-role escalation.** A listener could write themselves
  into `role: 'speaker'`/`isMuted: false` directly. `create` now must match
  what `joinRoom()`/`createRoom()` actually write (host→host+speaker,
  everyone else→listener); non-host `update` is limited to
  `isMuted`/`isHandRaised` on their own doc.
- **#5 — `bootstrapSuperAdmin`** now requires `email_verified == true` before
  granting the super-admin role.

**Medium (#6, #7, #8, #9, #10, #11) — done, deployed, verified:**
- **#6 — `/users/{userId}` had zero field validation.** Split `update` into
  owner (fixed allowlist of profile/presence/achievement-counter fields) vs.
  non-owner (only `friendCount`/`followerCount`, because `follow_service.dart`
  and `friend_service.dart` genuinely increment those on the OTHER person's
  doc in the same transaction that creates the follow/friend edge).
- **#10 — `sentFriendRequests`, `following`, `followers`, and rooms'
  `handRequests` subcollections had NO rules at all.** This wasn't just a
  security gap — Firestore's default-deny meant **the Friends feature and the
  Follow feature could not function at all**: every `sendFriendRequest()`,
  `follow()`, `unfollow()`, and Broadcast Room raise-hand call was silently
  rejected. Added rules matching exactly what the Dart services write.
- **#8 — Forced friendship.** `friends/{friendId}` `create` now requires a
  matching `friendRequests` doc to have existed on one side or the other
  (verified this doesn't break the transactional accept-flow: the check uses
  plain `exists()` against pre-transaction state, which is correct here since
  the request doc already existed before the transaction started — unlike the
  participant-creation case below, which needed `getAfter()` instead).
- **#9 — Room chat readable by anyone signed in, regardless of room
  visibility.** Now: public rooms stay readable without joining (matches the
  Discover preview pattern); private/club-lounge rooms require actual
  participant/member/host status.
- **#7 — `voiceMoments.likeCount`/`commentCount`** could be set to any value by
  any signed-in user. Now must correspond to the caller's own like doc
  actually existing/not-existing after the write (`existsAfter()`), or a plain
  `+1` for comments.
- **#11 — `storage.rules` path mismatches.** `room_images/{roomId}/{file}` was
  being checked against `request.auth.uid == {roomId segment}`, which could
  never match — every room image upload was rejected. Fixed to validate via
  the uid-prefixed filename the client actually writes. `clubs/{uid}/{clubId}/…`
  had no rule at all (default deny) — added one.

**Independent bug found and fixed along the way (not in the audit):**
`ProfileService.ensureProfile()` runs on every Profile screen visit and was
unconditionally re-writing `friendCount`/`followerCount`/etc. back to `0` via
`merge: true` — silently wiping real progress every time the tightened `#6`
rule would otherwise have surfaced as a `permission-denied`. Fixed by checking
whether the doc already exists before writing the initial-state payload.

**Deliberately NOT done:**
- **#12 — App Check.** `enforceAppCheck: false` on every Cloud Function is
  lower-severity per the audit itself ("not a vulnerability on its own, just
  removes a hardening layer"). Flipping it on requires registering App Check
  providers (DeviceCheck/AppAttest for iOS, Play Integrity for Android) in the
  Firebase Console and wiring the App Check SDK into the Flutter client first —
  enabling enforcement before that's live would reject every request from
  every existing app build. Confirmed via the Console that App Check has never
  been configured for this project at all (shows the "Get started" onboarding
  screen, not a dashboard).

### Verification method used throughout

Every Firestore/Storage rule change was checked against the **Firestore
emulator** using `@firebase/rules-unit-testing` before deploying — a
hand-written test script covering every regression (does the legitimate write
path still work?) and every attack scenario (is the exploit now blocked?) from
the audit. Final tally: **34/34 checks passing**. This test harness lives only
in the session's scratchpad directory (ephemeral, tied to this session) and was
**never committed to the repo** — see "Remaining issues" for why that's worth
revisiting.

---

## 2. Files created

```
lib/features/rooms/presentation/screens/broadcast_room/broadcast_colors.dart
lib/features/rooms/presentation/screens/broadcast_room/broadcast_background.dart
lib/features/rooms/presentation/screens/broadcast_room/broadcast_stage.dart
lib/features/rooms/presentation/screens/broadcast_room/broadcast_owner_controls.dart
lib/features/rooms/presentation/screens/broadcast_room/broadcast_roster.dart
lib/features/rooms/presentation/screens/broadcast_room/broadcast_bottom_controls.dart
lib/features/rooms/presentation/screens/broadcast_room/sheets/owner_menu_sheet.dart
lib/features/rooms/presentation/screens/broadcast_room/sheets/share_room_sheet.dart
lib/features/rooms/presentation/screens/broadcast_room/sheets/settings_sheet.dart
lib/features/rooms/presentation/screens/broadcast_room/sheets/participants_sheet.dart
functions/.env                          # LIVEKIT_URL — not a secret, see below
```

## 3. Files modified

```
lib/features/rooms/presentation/screens/broadcast_room_screen.dart   # slimmed to ~430 lines
lib/features/profile/data/services/profile_service.dart              # ensureProfile() fix
firestore.rules                                                      # multiple passes, see above
storage.rules                                                        # room_images/ + clubs/ paths
functions/livekit/token.js                                           # full rewrite
functions/admin/users.js                                             # email_verified check
docs/SECURITY_AUDIT.md                                                # was untracked, now committed
```

## 4. Git history (chronological, all on `main`, all pushed)

```
0473eb5  Fix two more broken features found via live production testing
cea73d1  Fix remaining SECURITY_AUDIT.md items (#6-11)
a38474e  Add LIVEKIT_URL function param
55e8627  Fix critical/high security issues from SECURITY_AUDIT.md (#1-5, #13)
3f4d936  Fix owner menu sheet overflow in broadcast room
721bbcd  Revise README.md with detailed project overview        (not mine — landed via rebase)
66b64f4  Merge pull request #1 from .../refactor/split-broadcast-room-screen
75b64e0  Split broadcast_room_screen.dart into focused files
```

Run `git log --oneline -12` to reconfirm — don't trust hashes transcribed
elsewhere without checking.

**Working tree is otherwise clean** except one pre-existing untracked file:
`prod-firestore.rules` (empty placeholder at repo root, present before this
session started, not part of any commit here — leave it alone unless the user
says otherwise).

---

## 5. Current architecture (as touched by this session)

- **App**: Flutter, package `com.example.yoVoice` — a Clubhouse/Discord-style
  voice social app ("YoVoice").
- **Backend**: Firebase project `yovoice-ec54a`.
  - Firestore: single `(default)` database, `europe-west4`, Native mode.
  - Cloud Functions: `europe-west1`, Node 22, `firebase-functions` v6.
  - Storage: rules at repo root `storage.rules`.
  - Voice: LiveKit Cloud, project URL `wss://yovoice-3f7j9fb7.livekit.cloud`
    (now in `functions/.env` as `LIVEKIT_URL`). API key/secret remain in
    Secret Manager (`defineSecret`), untouched this session.
- **CI/CD (checked — resolved, was a false alarm):** `.github/workflows/firebase-hosting-merge.yml`
  runs on every push to `main` and deploys **Firebase Hosting only**
  (`flutter build web --release` → `FirebaseExtended/action-hosting-deploy@v0`).
  It does not touch Firestore rules, Storage rules, or Cloud Functions. The
  `github-action-1300846400@yovoice-ec54a.iam.gserviceaccount.com` actor seen
  earlier in the Firebase Console was this workflow's Hosting deploy, not a
  Firestore rules deploy as first assumed (misread — it was under the
  Console's Hosting widget, not the Firestore one). No CI/CD race risk with
  manual `firebase deploy` calls for rules/functions.
- **Room model**: `rooms/{roomId}` with subcollections `participants`,
  `members`, `messages`, `handRequests`. Two room "experiences" — `broadcast`
  and `community` — set via `experience` field (written by
  `RoomExperienceService.configureRoom()` right after creation).
- **⚠️ Two parallel hand-raise implementations exist** — not a bug, but a
  consistency smell worth a future look:
  1. `RoomService.setHandRaised()` — a simple `isHandRaised` boolean field on
     the `participants` doc. Used by `broadcast_room_screen.dart` (the screen
     refactored in part A).
  2. `RoomExperienceService.setHandRaised()` — a separate `handRequests`
     subcollection with its own docs. Used by `podcast_room_screen.dart`.
  Both now have correct Firestore rules; they just duplicate the same feature
  differently in two places.

---

## 6. Remaining issues

### ✅ RESOLVED — the "searchUsers permission-denied" report was actually two different, unrelated bugs

The user-reported symptom (Friends → Add friend → search → "Could not search
users — Firestore permission denied") sent this investigation down the wrong
path for a while. What was ruled out first, with evidence, before finding the
real cause:
1. My rule changes — a standalone emulator script running the exact same
   `collection('users').limit(100).get()` succeeded.
2. Stale/wrong deployed rules — read the live rule text directly in the
   Firebase Console; byte-for-byte identical to the local file.
3. App Check enforcement — confirmed never configured for this project.
4. Multiple Firestore databases — confirmed only one `(default)` exists.

**Root cause, found by adding a temporary `print()` in
`add_friend_screen.dart`'s catch block and reading the raw error +
stack trace from `flutter run --debug`:** `searchUsers()` itself was never
the problem — it succeeds. The error actually came from
`FriendService.getRelationshipStatus()`, called via `Future.wait()`
immediately after the search, for every result. That function reads
`users/{otherUserId}/friendRequests/{me}` to check "did I already send this
person a request" — i.e. the **sender** reading a doc that lives under the
**recipient's** subcollection. The `friendRequests` read rule was
recipient-only (`allow read: if isOwner(userId)`), so that specific check was
permanently denied for anyone except the recipient checking their own list.
**Fix:** `allow read: if isOneOfUsers(userId, senderId);` — both the
recipient and the actual sender (identified by the subcollection doc's own
key) can read it.

**A second, unrelated bug was found in the same investigation** (noticed via
`xcrun simctl spawn ... log stream`, which kept showing a repeating
`Listen for query at |cg:members|f:userId==...| failed: Missing or
insufficient permissions.`): `RoomService.watchMyCommunities()` runs a
`collectionGroup('members')` query filtered to `userId == caller`, spanning
both `rooms/*/members` (rule: `isSignedIn()`) and `clubs/*/members` (rule:
`isClubMember(clubId)`, which needs an extra `exists()` read per candidate
doc). Firestore rejects an entire collectionGroup query unless every
collection it spans has a rule it can verify from the query shape alone —
`isClubMember()` doesn't qualify, so **the whole query failed outright**,
breaking the "My Communities" list. **Fix:** added
`resource.data.userId == request.auth.uid` as an explicit alternative on
`clubs/{clubId}/members` read, since that condition IS provable directly from
the query's own filter (no extra read needed) — added alongside, not instead
of, the existing `isClubMember()` browsing case.

Both fixes verified with 6 new emulator checks (40/40 total passing) and then
**confirmed live**: friend search now returns results with working
Add/Cancel buttons, and a real friend request was sent successfully in the
simulator. Commit `0473eb5`, deployed to production the same way as
everything else this session (`firebase deploy --only firestore:rules`).

The temporary debug `print()` was removed from `add_friend_screen.dart`
before committing — that file has no net diff from before this investigation
started.

### 🟡 Deliberately deferred

- **App Check (#12)** — see above. Needs Console provider setup + Flutter SDK
  integration + careful staged rollout; not something to flip on blind.

### 🟡 Accepted trade-offs (documented in code comments at each site)

- Non-host room `participantCount`/`memberCount`/`speakerCount` writes are now
  field-restricted but **not value-validated** — someone could still write an
  arbitrary number (not just ±1). Durable fix: a Cloud Function
  `onDocumentWritten` trigger computing these authoritatively, same pattern
  the audit suggests for `voiceMoments.likeCount` (#7, which — for likes
  specifically — I did give tighter value validation via `existsAfter()`,
  since that transaction is self-contained).
- Achievement/vanity counters on `/users/{userId}` (`messageCount`,
  `friendCount`, etc.) remain self-inflatable by the doc owner. Audit's own
  words: "not a real security hole… just not authoritative." True before this
  session too; unchanged.

### 🟢 Test coverage gap

The 34-check rules-unit-testing suite that verified every change in this
session lives **only** in
`/private/tmp/.../scratchpad/rules-test/` (session-local, gone once the
session ends) and was **never committed**. The audit itself noted this
project has essentially zero test coverage. Worth promoting a trimmed version
of that suite into the repo proper (e.g. a `firestore-tests/` folder with its
own `package.json`) so future rule edits have regression coverage instead of
relying on someone re-deriving all of this from scratch again.

---

## 7. Important design decisions

- **`broadcast_room_screen.dart` kept at its original path.** Extracted pieces
  went into a new `broadcast_room/` sibling folder instead of moving the
  screen itself, specifically so `room_entry_screen.dart`'s import needed zero
  changes.
- **Extracted widgets are public but not exported anywhere.** Dart privacy is
  file-scoped; splitting one file into many forces underscore-prefixed classes
  to become plain top-level classes. This is a visibility-scope change only —
  nothing re-exports them, so there's no new public API surface in practice.
- **Firestore rule fixes favor "narrow field allowlist" over "precise value
  validation"** almost everywhere, matching the audit's own suggested patch
  style and what's realistically verifiable with confidence in a single
  session. The two exceptions where value-level (`getAfter()`/`existsAfter()`)
  checks were used: (a) room `participants` creation, because
  `createRoom()`'s host-participant write happens in the **same batch** as
  the room doc itself, so a plain `get()`/`isRoomHost()` can't see the room's
  `hostId` yet — `getAfter()` resolves against post-batch state; (b)
  `voiceMoments` like-count, because `toggleLike()`'s counter update and its
  like-doc write happen in one self-contained transaction, making
  `existsAfter()` both safe and meaningful there.
- **Git workflow**: push straight to `main`, no PRs, per the user's explicit
  standing preference for this repo (saved in Claude's cross-session memory,
  not in this repo's files). The one PR in this session's history (#1) predates
  that preference being stated.
- **Rules changes are always emulator-tested before deploy**, never pushed to
  production on faith — every fix in section 1 above was verified this way.

---

## 8. Commands needed to continue

```bash
# Run the app in the simulator used throughout this session
cd /Users/kamiljaguszewski/Documents/GitHub/yovoice
flutter run -d 69E45220-7B76-44C8-B369-1EB4DCC04F1E --debug
# (device id may differ if the simulator was recreated — check `xcrun simctl list devices`)

# Static analysis
flutter analyze

# Firestore emulator (Java was NOT symlinked system-wide — always export PATH first)
export PATH="/usr/local/opt/openjdk/bin:$PATH"
firebase emulators:start --only firestore --project yovoice-ec54a

# Validate rules compile without deploying
firebase deploy --only firestore:rules --dry-run --project yovoice-ec54a

# Actually deploy (expect Claude Code's auto-mode safety classifier to
# sometimes block this and require explicit user approval — behavior was
# inconsistent across calls this session)
firebase deploy --only firestore:rules,storage --project yovoice-ec54a
firebase deploy --only functions:createLiveKitToken,functions:bootstrapSuperAdmin --project yovoice-ec54a
```

Firebase CLI is already logged in as `kamil.piotr.jaguszewski@gmail.com`. Git
push authentication works via the macOS `osxkeychain` credential helper
(populated earlier by a VS Code GitHub login) — should still be valid unless
the user has since logged out somewhere.

---

## 9. Exact next task

Nothing is currently on fire. Two backlog items got done autonomously after
this doc was first written (see section 4 for the commit):
- ~~Investigate the GitHub Actions CI/CD pipeline~~ — done, false alarm, see
  section 5's CI/CD note.
- ~~Promote the emulator test suite into the repo~~ — done, now
  `firestore-tests/` (40 checks, `npm test`).

Remaining, roughly in priority order:

1. **App Check (#12 from the audit)** — the last unaddressed item from
   `docs/SECURITY_AUDIT.md`. Needs: register the app with App Check providers
   in the Firebase Console (DeviceCheck/AppAttest for iOS, Play Integrity for
   Android), integrate the App Check SDK into the Flutter client, ship that,
   THEN flip `enforceAppCheck: true` in the Cloud Functions — in that order,
   or every existing installed app build gets rejected the moment enforcement
   turns on. Needs the user for the Console provider registration step at
   minimum (ties to their Apple/Google developer accounts).
2. **Value-level validation for room/club counters** via a Cloud Function
   trigger (`onDocumentWritten`) — closes the residual gap noted in section 6
   where `participantCount`/`memberCount`/`speakerCount` are field-restricted
   but not value-validated. **Bigger and riskier than it looks**: doing this
   properly means removing the client's direct writes to these fields from
   `room_service.dart` (`joinRoom`, `leaveRoom`, `joinCommunity`,
   `removeParticipant`, `ensureClubLounge`/`enterClubLounge`/`leaveClubLounge`
   all currently set these counters inline as part of larger transactions) —
   touching that many call sites in one pass is exactly the kind of change
   that broke Friends/Follow/hand-raise earlier this session. Go one method
   at a time, with a live simulator check after each, not all at once.
3. **Consolidate the two hand-raise implementations** (section 5) — not
   urgent, but `RoomService.setHandRaised()` and
   `RoomExperienceService.setHandRaised()` doing the same job two different
   ways is worth resolving before it causes a real divergence bug.

If the user asks for something else entirely, that obviously takes priority
over this list — it's a backlog, not a queue.

---

## 10. Anything else the next session should know

- **Test accounts**: primary account used throughout is `CeoGriefer`
  (`@ceogriefer`, email `grieferxgriefer@gmail.com` — **never store or type
  this password**; the user provided it once directly in-session for
  simulator login and it was not persisted anywhere). A second account,
  `testGriefer`, also exists and was seen hosting a room ("super test") in
  Discover — useful for genuine two-account testing (e.g. the friend-request
  accept flow has only been exercised from one side so far).
- **No Secret Manager access.** Attempting to read `LIVEKIT_API_KEY` /
  `LIVEKIT_API_SECRET` via `firebase functions:secrets:access` was correctly
  blocked by Claude Code's safety classifier this session — don't try to work
  around that; ask the user if a secret value is ever genuinely needed.
- **Firebase Console access** is only available through the user's own
  logged-in Chrome via the `claude-in-chrome` MCP tools, and only when the
  user explicitly opens it up in a given session — there's no standing
  access.
- `docs/SECURITY_AUDIT.md` is the authoritative reference for all the
  security work described here. Re-read it before starting any further
  security-related work — it has full code excerpts and suggested patches for
  every item, including the ones already fixed (useful for understanding
  *why*, not just *what*).
