# Decisions

Architecture Decision Records. Add a new entry whenever you make or change
an architectural decision — schema change, new dependency, a workaround and
why it was necessary, a pattern future code should follow. Keep entries
short: what was decided, why, what it rules out. Newest first.

---

### Security audit remediation: server-side permission checks over client-trusted flags

**Decision**: Every critical/high finding from
[Archive/SECURITY_AUDIT.md](Archive/SECURITY_AUDIT.md) (room takeover via
`hostId` self-assignment, club ownership takeover, LiveKit publish
permissions trusted from the client, self-assigned participant roles,
`bootstrapSuperAdmin` missing an `email_verified` check, and more) was
fixed by moving the authority for "what am I allowed to do" onto the
server — a Firestore rule that reads the *real* stored role/relationship,
or a Cloud Function that looks up the participant document itself — rather
than trusting any field the client sends in the request.

**Why**: The common thread across nearly every finding was the same shape:
a write or a token request that carried its own claimed permission
(`role: 'owner'`, `canPublish: true`, `hostId: <my uid>`) with nothing on
the server actually checking it against reality. Firestore's `hasOnly()`
field-allowlisting stops the *wrong fields* from changing, but says nothing
about whether the *values* being written are true — that needed either an
`exists()`/`get()` check against the real relationship, or moving the
write into a Cloud Function that can enforce it properly.

**Rules out**: Accepting a permission/role/ownership claim from
`request.resource.data` (Firestore rules) or `request.data` (Cloud
Functions) without checking it against a document the writer doesn't
control. If a new write path needs to grant a role or a capability,
default to computing it server-side from an existing relationship, the way
`createLiveKitToken` now derives `canPublish` from the caller's real
participant document (see [Backend.md](Backend.md)).

**Status**: all findings fixed except App Check enforcement (audit #12,
tracked separately below) — see [Bugs.md](Bugs.md) for current status.

---

### `experience: 'podcast'` stays supported until production data is migrated

**Decision**: `room_experience.dart` maps the legacy Firestore value
`'podcast'` to `RoomExperience.broadcast` for backward compatibility. New
and updated rooms only ever write `'community'` or `'broadcast'` — but
reading `'podcast'` must keep working.

**Why**: Rooms were renamed/restructured from a three-type model
(`community`/`broadcast`/`podcast`) down to two, but no migration of
existing production documents was ever run. Removing the mapping before
confirming that migration would make any pre-existing `podcast` room
unreadable or mis-rendered.

**Rules out**: Deleting the `'podcast'` branch in `room_experience.dart`
without first confirming (Firestore Console or an admin query) that zero
production documents still contain that value. See
[Bugs.md](Bugs.md#data-integrity).

---

### "Coming soon" instead of fabricated data or dead buttons

**Decision**: When a screen needs a feature with no real backend support
yet, show it visibly, disabled, labeled "Coming soon" — never fake the data,
never silently hide the option, never leave a dead button with no
explanation.

**Why**: Applied across the Settings, Awards, and Creator Studio rebuild
(commit `6cfd208`). A convincing-looking fake (a fabricated analytics chart,
a hardcoded "recent activity" feed) is worse than an honest gap, because it
erodes trust the moment a user notices the numbers don't move. This mirrors
the same call made earlier for the website's download center (honest
"coming soon" instead of fake store links) and account pages
(Firestore-backed preferences deliberately not built until they'd be done
right).

**Rules out**: Placeholder screens with lorem ipsum or invented stats.
Hiding a whole section just because one part of it isn't ready — partial
real data (e.g. rooms hosted, real follower count) ships even when the
section also has a "Coming soon" subsection (e.g. analytics) next to it.

---

### Real per-achievement unlock timestamps (`unlockedTitleTimestamps`)

**Decision**: Added a `Map<achievementId, Timestamp>` field on
`users/{userId}`, written by `AchievementService.incrementMetric()` and
`refreshUnlockedTitles()` whenever an achievement is newly unlocked (merged,
never overwritten for already-unlocked ones).

**Why**: The Awards screen needed a genuine "recent unlocks" feed. The
existing `unlockedTitleIds` list has no ordering information — it's fully
recomputed from the catalog every time, so list order is deterministic by
catalog definition order, not by when the user actually unlocked something.
Rather than fake recency (e.g. reverse catalog order, or "most recently
computed" which is meaningless), a real timestamp was added.

**Rules out**: Achievements unlocked *before* this field existed have no
timestamp and simply don't appear in "recent unlocks" — not backfilled with
a guessed date. That's a deliberate honesty tradeoff, not a bug.

---

### `permission_handler` for real device-permission status in Settings

**Decision**: Settings' Permissions section queries actual OS-level
microphone/camera/notification permission status via `permission_handler`
(already a dependency, previously only used for the mic-permission request
inside `voice_call_service.dart`) and offers a real "open system settings"
action when denied — not a static description of what permissions the app
uses.

**Why**: Same "real data or Coming soon" principle. This was easy to make
real (dependency already existed) so there was no reason to fake it.

---

### Git workflow: push straight to `main`, no PRs

**Decision**: Commit and push directly to `main` in both `yovoice` and
`yovoice-website` — no feature branches, no PR ceremony, by default. Before
a "bigger update," make a backup first (a local tag/branch snapshot of
`main`) rather than relying on a PR as the safety net.

**Why**: Solo project; the user explicitly said so after a PR-based
refactor felt like unwanted overhead ("wolę pushować na maina" — prefer
pushing to main).

**Rules out**: Opening a PR by default for sizeable refactors or features.
Only fall back to branch+PR if explicitly asked for a specific change.

---

### `rooms/{roomId}/members` renamed to `roomMembers`

**Decision**: Renamed rather than trying to make the original name work
with a smarter Firestore rule.

**Why**: `RoomService.watchMyCommunities()` and
`ClubService.watchMyClubInvites()` were broken in production — `
collectionGroup()` queries need a **top-level**
`match /{path=**}/collection/{doc}` rule; a nested
`match /parent/{id}/collection/{doc}` rule only authorizes reads scoped to
one specific parent and does *not* make the collection queryable via
`collectionGroup()`. `clubs/{clubId}/members` legitimately needs a more
permissive, `exists()`-based rule for its own roster-browsing use case —
sharing the collection name `members` with `rooms/{roomId}/members` meant
any top-level wildcard rule added for one would have to also satisfy (or
accidentally widen) the other. Two collections that only shared a name by
coincidence, not by design, got distinct names instead.

**Also learned**: combining an `exists()`-based clause with a provable one
via `||` does **not** satisfy Firestore's collection-group provability
check, despite docs suggesting an OR'd provable clause should work — verified
directly against the emulator. A prior fix attempt relying on that
assumption never actually worked.

**Rules out**: Reusing generic subcollection names (`members`, `items`,
etc.) across different parent collections without checking whether either
side will ever need a `collectionGroup()` query. Check that before naming a
new subcollection.

---

### Top-level `collectionGroup` wildcard rules are read-only, narrowly scoped

**Decision**: The two wildcard rules added for `roomMembers` and `invites`
only allow reading your own record (`resource.data.userId ==
request.auth.uid` / `resource.data.inviteeId == request.auth.uid`). Writes
still only ever go through the nested, parent-scoped rules.

**Why**: The wildcard rules exist purely to unblock the two specific
`collectionGroup()` queries the app actually runs — not as general-purpose
access widening. Keep new wildcard rules this narrow by default.

---

### Firestore rules are always emulator-tested before deploy — and the test must actually exercise `collectionGroup()`

**Decision**: Never deploy a rules change on the strength of a test suite
that only calls `getDoc()`/`getDocs()` on a fully-specified path.

**Why**: That's exactly what let the `roomMembers`/`invites` bug ship
silently — a green 40-check suite, a completely broken real-world query.
`firestore-tests/rules.test.js` now includes real `collectionGroup()`
regression tests (43 checks total).

---

### `NEXT_PUBLIC_APP_URL` as an env var, not a hardcoded domain (website)

**Decision**: The website's redirect-to-app target is an env var, currently
`https://yovoice-ec54a.web.app`, meant to become `https://app.yovoice.app`.

**Why**: The `app.yovoice.app` DNS record is blocked on Cloudflare access
this session doesn't have. An env var means flipping it later is a one-line
config change, not a code change or a redeploy-and-hope.

---

### Resend SMTP instead of Firebase's default email sender

**Decision**: Firebase Auth's action emails (verification, password reset)
go through Resend's SMTP, not Firebase's built-in default sender.

**Why**: The default sender never reliably delivered — a real, confirmed
deliverability problem, not a preference. Resend SMTP is confirmed working
end-to-end.

**Watch out for**: the SMTP username must stay literally the string
`"resend"` — not the account email, not an API-key-looking value.
`handleCodeInApp` is intentionally **not** used for verify/reset codes —
Firebase's own hosted action page handles those, by design, not by
oversight.

---

### Firebase App Check: client integrated, enforcement deliberately off

**Decision**: `firebase_app_check` is active client-side
(`AndroidDebugProvider`/`AppleDebugProvider` debug,
`AndroidPlayIntegrityProvider`/`AppleAppAttestWithDeviceCheckFallbackProvider`
release). `enforceAppCheck` on Cloud Functions stays `false` for now.

**Why**: Flipping enforcement is a one-line change but a real risk — it
would start rejecting requests without a valid token. Needs a monitoring
period on real token delivery (Firebase Console → App Check has the
metrics) before flipping it, ideally function-by-function rather than all
at once.
