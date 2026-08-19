# 2026-08-19/20 — Four features that existed, passed, and did not work

Nine commits, `3d54bc3` → `b0f1062`. The through-line is not the features;
it is that four of them **already existed in source, already passed their
tests, and — where a backend was involved — were already deployed and
ACTIVE, while being unusable by any user.** That pattern is now recorded as
[ADR-082](../Decisions.md#adr-082-a-feature-is-not-shipped-until-a-user-can-reach-it--reachability-is-part-of-done-and-a-green-suite-cannot-prove-it),
and the suite-level reason for it is a stated limitation in
[TESTING.md](../TESTING.md).

**Nothing in this wave is deployed.** Every claim below is about the
repository at `b0f1062`.

## The four

1. **Voice never worked in any Community room or lounge** (`b0f1062`).
   `createLiveKitToken` refuses a token unless the room says status active
   and `isLive` true; performing that transition is the *caller's* job. Only
   `enterClubLounge` ever did it, reachable in practice from the Club
   overview alone — because `HomeScreen` is not mounted anywhere in the
   running app. `RoomService.startCommunityVoice` had **zero callers**, while
   nine call sites pushed `RoomEntryScreen`, whose own comment says callers
   joined beforehand, and the room screen then asked for a token immediately.
   Production agreed: **45 rooms, 3 live**. The report that started it —
   "opening a Family Room I created myself and pressing unmute says the room
   is not live" — was not a Family Room bug.
2. **Club chat moderation had never worked** (`b3c27fd`). Three layers, three
   beliefs: the client authorised moderator, admin and owner; the rule was
   author-only; the UI never offered the action at all.
3. **No message anywhere in the product could be reported** (`9f3ce7f`).
   `createContentReport` was deployed and ACTIVE and already accepted three
   target types. **No Dart file called it.**
4. **Home's "Discover clubs" rail was denied for everyone** (`01c0ab2`,
   `155ad61`), including a club owner listing their own club — `clubs`
   carried `allow list: if false` and the rule's comment claimed no
   legitimate listing remained. The denial was then swallowed by
   `snapshot.data ?? []` with no `hasError`, and the heading vanished with
   the rail. It also lives in the unmounted `HomeScreen`, so it was broken
   twice over, independently.

The mechanism, stated once: the emulator does not enforce composite indexes,
rules tests exercise fixtures the test author wrote rather than what the
client actually sends, and `fake_cloud_firestore` does not evaluate rules at
all. Every layer validates a *model* of its neighbour; nothing validates the
seam.

## Findings that generalize

Each is an ADR rather than a bullet, because each will be relevant to code
nobody has written yet.

- **A `list` rule is evaluated against the QUERY'S CONSTRAINTS, never against
  the documents it would return** ([ADR-083](../Decisions.md#adr-083-a-firestore-list-rule-is-evaluated-against-the-querys-constraints-so-every-clause-is-a-bare-field-access-and-the-clients-query-carries-the-equality)).
  A clause written with a default — `get('type','community') == 'community'`
  — was **measured to ADMIT a family club**, because with no matching filter
  in the query the clause satisfies itself. Bare field accesses force the
  caller's query to carry the equality, which makes the client's filters the
  authorization rather than defensive narrowing.
- **CEL absorbs errors through `||`** ([ADR-085](../Decisions.md#adr-085-authorization-branches-in-a-rule-are-disjoint-by-construction-because-cels--absorbs-errors)).
  `<error> || true` ALLOWS, so an erroring branch silently hands its decision
  to the other one. Authorization branches are now disjoint by construction,
  selected on `senderId == uid` vs `!=` before any document read.
- **A create rule with no allowlist can write a state no update rule will
  repair.** The forged club tombstone — "removed by the club owner",
  `deletedByRole: superAdmin`, a 2099 `sentAt` — would have been permanent:
  the update rule refuses already-deleted documents, `delete` is `if false`,
  and `adminDeleteMessage` short-circuits on `isDeleted`.
- **Extra-field freedom silently dropped achievement credit.**
  `functions/achievements/sources.js` requires an exact six-key room message;
  any extra field made the adapter return null and the event was skipped.
  Rules and adapter now agree on the same keyset
  ([ADR-084](../Decisions.md#adr-084-client-authored-writes-carry-an-exact-key-allowlist-and-identity-and-time-are-pinned-to-canonical-server-values-or-the-remaining-gap-is-stated)).
- **Rules `String.size()` counts UTF-16 code units**, the same unit as Dart's
  `String.length`, so a 500 cap matches what the app allows rather than
  rejecting emoji-heavy messages.
- **`createContentReport` was an existence oracle** — it answered `not-found`
  before checking access, so a caller could learn whether a private room,
  club, channel or message id was real by watching which refusal came back.
  Access is now checked first
  ([ADR-086](../Decisions.md#adr-086-a-safety-action-is-never-gated-on-email-verification-and-every-moderation-endpoint-checks-access-before-existence)).
- **A safety action must not require a verified email.**
  `createContentReport` did, contradicting the policy written in
  `firestore.rules` that reporting sits with blocking and must be available
  to a first-day account. An audit of every neighbouring `requireActor` call
  site found this was the **only** tightened safety path.
- **Adding a field to a callable re-keys every report already filed**, because
  the idempotency hash is computed over the target and the client derives its
  `requestId` from the same thing. New fields fold in only when the target
  carries them, pinned by a regression test that recomputes the legacy hash
  ([ADR-087](../Decisions.md#adr-087-an-idempotency-key-derived-from-a-request-payload-is-a-compatibility-surface--new-fields-fold-in-only-when-the-target-carries-them)).
- **A write the rules authorize by session cannot live after the session
  ends** ([ADR-090](../Decisions.md#adr-090-session-cleanup-converges-on-authservicesignout-because-a-write-the-rules-authorize-by-session-cannot-live-after-the-session-ends)).
  The offline presence write sat in the `authStateChanges()` null branch, was
  denied, and the denial was swallowed to a `debugPrint` — so a signed-out
  account showed as online to its friends indefinitely, under a comment
  claiming that exact bug was fixed.

## Verified, not assumed

- `flutter analyze` clean. **1036** Flutter tests, **466** Firestore rules
  cases, **699** Cloud Functions tests, measured by the implementing sessions
  and confirmed for this pass. `docs/TESTING.md` had been claiming **593/98**
  for Functions and **363** for rules; both are corrected, with provenance
  stated under the table.
- Fail-before discipline, per change: sign-out 8 of 10 new tests fail against
  the pre-fix code; club moderation 22 rules cases fail against HEAD's
  ruleset; room chat and club listing 12 cases fail against HEAD's ruleset;
  reporting demonstrated by restoring the old read-back (4 failures) and the
  hardcoded reason (6 failures), then reverting; the backend report change 7
  of 9 fail against the unmodified function; room voice 3 cases fail against
  the pre-fix service; club discovery reverting the query fails 4 of 6
  service tests.
- Read directly from production while reviewing: **45 rooms, 3 live**; all 3
  club-lounge documents carry `clubId` and `roomKind`; **25 of 45 rooms have
  no `membersCanStartVoice`** and **24 have neither `roomType` nor
  `experience`** — which is why every read in the new liveness path defaults
  rather than raising.
- Rendered and inspected: room voice states, 45 screenshots with the real
  typeface at 320/390/768/1100/1440 and 200% text; club-discovery rail states
  at three widths and two text scales.

## UNVERIFIED, and the difference is the point

- **Nothing is deployed.** No rules deploy, no Functions deploy, no index
  deploy, no Hosting release. `firestore.indexes.json` now carries **21
  composites and 4 fieldOverrides**; the last production reading, on
  2026-08-19, was 19 and 4. Rollout order and gates:
  [DEPLOYMENT.md](../DEPLOYMENT.md#pending-release-the-2026-08-1920-reachability-wave).
- **Room voice has had no round trip of any kind** — no production, no
  emulator, no real LiveKit, no device run. Rules were read, not executed,
  and `fake_cloud_firestore` evaluates no rules, so every "the client may
  start voice" test proves the mirror and not the server. Audio quality,
  reconnect, device routing and the web permission path are untouched and
  unretested.
- **The club moderation UI and the Moments destination have never been
  rendered.** Both sessions' visual and accessibility reviews died on a
  session limit. [ADR-059](../Decisions.md#adr-059-a-ui-change-is-reviewed-before-it-is-deployed-on-the-same-terms-as-a-rules-change)
  makes that a deploy gate, not a caution.
- **Presence actually flipping in production** needs two real accounts on two
  devices.

## Open, and recorded as open

- `HomeScreen` is unmounted, so `DiscoverClubsRail`, `FromYourClubs` and
  `LiveNowHero` are unreachable. Placing them is a Home
  information-architecture decision nobody has taken (Roadmap 0n).
- v2 report documents render badly in the Moderation Center: `targetType`
  parses to null so the queue title is blank, and `reportedUserId` defaults to
  empty so the detail pane says **"This account no longer exists"** —
  actively misleading. The fix spans Dart and Functions together (Roadmap 0o).
- Moderators can triage room and club message reports but cannot action them;
  `removeAndResolve` is still globalChat-only.
- `reason` has no server-side enum on the callable path, so the Moderation
  Center's equality filter cannot see an off-list reason.
- A member-started room can stay live with nobody in it (the server drops
  `isLive` at zero participants only for lounges), and `executeEndRoomVoice`
  re-checks nothing before tearing a room down. **A concurrent session had
  uncommitted working-tree changes addressing both while this documentation
  pass ran** — `executeLeaveRoom` ending the session for any room, proving
  emptiness from the roster rather than the denormalised counter, plus an
  `onlyIfEmpty` re-check in `executeEndRoomVoice`. Read from the working tree
  at `HEAD = b0f1062`, **not from a commit**; confirm against `git log`
  before citing it as fixed (Roadmap 0p).
- Room chat `senderPhotoUrl` is not pinned, because the client falls back to
  the Auth mirror; an avatar can still point at another member's image.
- A family room's owner can still set privacy public from the settings
  screen.
- A club-chat moderator removal is recorded nowhere — no audit trigger, no
  rate limit, no restore path, no rank ordering.
- Presence is never cleared on process death; `functions/` has no sweeper
  (Roadmap 0q).

## One process note

The `f817b41` increment was lost from the working tree once and re-applied
from the implementing agent's context; `b3c27fd` was never at risk, only the
delta on top of it. Whatever reverted it is unidentified, and agents working
in this repo have since been told not to run any path-reverting git command
outside the files they own. Worth keeping in mind when several sessions share
a tree — this documentation pass ran alongside three of them.
