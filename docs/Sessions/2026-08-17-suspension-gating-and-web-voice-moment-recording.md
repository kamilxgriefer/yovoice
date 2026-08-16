# 2026-08-17 — A suspension that suspends, and a recorder that records

**Scope:** two rounds, both deployed. The first closed the last account-status
hole in the room write paths (`c75720a`, `c7cea3e`). The second made Voice
Moment recording work on the web at all (`6ef4380`, `cefa81a`) — which,
web being the only published client, means it made the creator content loop
exist.

Four decision records came out of it:
[ADR-057](../Decisions.md#adr-057-voice-moment-recording-splits-only-at-byte-acquisition-and-byte-upload-and-the-server-pins-the-audio-container)
(the recording platform seam and why the server owns the audio format),
[ADR-058](../Decisions.md#adr-058-one-polite-live-region-per-screen-and-errors-go-out-on-the-assertive-channel)
(Flutter web's shared live region),
[ADR-059](../Decisions.md#adr-059-a-ui-change-is-reviewed-before-it-is-deployed-on-the-same-terms-as-a-rules-change)
(review precedes deploy for UI, written about a mistake made this session),
and
[ADR-060](../Decisions.md#adr-060-an-explanatory-comment-is-a-claim-measure-it-or-delete-it)
(the third stale-confident-claim incident in two days).

## 1. The selector was doing authorization the helper was careful about

The room-root update rule chose its host branch on `hostId` alone, with no
account-status check. `isRoomHost()` — used elsewhere — did check. So the
rule read as status-aware to anyone who followed the helper, and was not on
the path that mattered: **a banned or disabled host could still edit room
metadata and start voice.**

Four conditions now require `isActiveAccount()`: the host room-update
branch, `isHostAdmittedRoomParticipant()`, `roomMembers` create, and
message reaction updates.

`roomMembers` create is the one worth remembering. It was **already gated**
— on `isRestrictedAccount()`, which reads `banned` only and returns
**false when the account document is absent**. Disabled accounts passed a
check whose name implies it covers them. A test exercising only a banned
account passes against that rule; the hole is in the state the test never
tried.

Both properties are now
[SECURITY.md principle 9](../SECURITY.md#firestore-security-rules--design-principles).

Rules suite **310 passed / 8 failed → 318 passed / 0 failed**. The eight
failures against the then-live ruleset are the evidence; the green run
afterwards is only the confirmation.

## 2. The deployed ruleset can be read back, so "deployed" now means diffed

With ADC configured, `GET
https://firebaserules.googleapis.com/v1/projects/yovoice-ec54a/releases/cloud.firestore`
returns the released ruleset's name and `GET /v1/{rulesetName}` returns its
full source. `c75720a` was verified by fetching it and diffing against
`firestore.rules` at HEAD: **byte-identical**.

This closes two standing problems at once. There is now a **rollback
artifact** — snapshot the live source before any rules deploy, and that
file is what a rollback restores, independent of whether the repository
ever matched production (it did not on 2026-08-16, when production served
`9fdd8a9`). And a **post-deploy diff is now the verification standard**: a
Console version-history timestamp proves *a* deploy happened; a diff proves
which bytes are enforcing. For an authorization layer only the second is
evidence.

Commands in
[DEPLOYMENT.md](../DEPLOYMENT.md#reading-the-deployed-ruleset-the-verification-standard).
Both this file's predecessor and SECURITY.md had said there was no
read-only command. There is.

## 3. Three findings left open, none blocking

- **"Every write behind `canAccessRoom()` is now gated" is false.**
  `roomMembers` update lets a banned account rewrite `displayName` /
  `photoUrl` on its roster row — including a blind write into a private
  room it can no longer read, with no type or length check — and
  `participants` update lets it un-mute itself and raise its hand. Neither
  escalates privilege; neither bypasses audio, since LiveKit will not issue
  a token to a suspended account. Worth closing mostly because **no client
  issues either write**, so gating them carries zero trap risk — the exact
  opposite of the eviction rule `952d8e4` had to remove.
  [Roadmap 0k](../Roadmap.md#0k-gate-the-last-two-writes-behind-canaccessroom).
- **A pre-existing live bug, unrelated to this change.**
  `sendRoomMessage()` bumps `updatedAt` on the room root after every
  message, and the non-host branch has no transition accepting a bare
  `updatedAt`. Every non-host message send raises an unhandled
  permission-denied *after* the message has landed, and **room ordering in
  the Home feeds never advances from non-host conversation** — an active
  room looks stale.
  [Roadmap 0l](../Roadmap.md#0l-non-host-room-messages-always-throw-after-the-message-lands).
- **Dead rule code** from the `952d8e4` eviction removal:
  `roomParticipantLeaveRootExists()` has no callers, and
  `roomParticipantLeaveTransitionAllowed()` is unreachable because
  `participants` delete is `if false`. Flagged, not removed in a security
  commit. **The hazard is the reading**: the ternary calling the second
  helper looks like members can leave a voice room through rules, and they
  cannot.

## 4. A memberCount sweep found the trap was real and had landed on nobody

50 rooms, **28** whose stored `memberCount` disagrees with their true row
count, **0 trapped** — every mismatched room has zero membership rows, so
there was never anyone in them to trap. **24 rooms carry no `memberCount`
field at all**, which is exactly the legacy shape that would have trapped
members had any of those rooms had one.

The trap removed in `952d8e4` was not hypothetical. It simply had not been
reached yet. No repair migration is needed.

## 5. Nobody could record a Voice Moment, and the error said otherwise

The recorder called `getTemporaryDirectory()`, which `path_provider` does
not implement on web. A broad catch turned the `MissingPluginException`
into "Could not start recording". Web is the only published client. So the
whole creator content loop was closed, and **the message named nothing that
would lead anyone to the platform** — a catch broad enough to swallow
`MissingPluginException` converts "this platform is not implemented" into
"your action failed", which is the one distinction the user needed.

The fix splits at exactly two points — byte acquisition and byte upload —
behind one conditional export. Native keeps file → `putFile`; web uses a
MediaRecorder blob → `fetch` → `arrayBuffer` → `putData`. State, service,
reservation, metadata and UI stay single-implementation.

**The format was measured, not assumed, and the result is
counter-intuitive.** The backend pins `audio/mp4|m4a|x-m4a` in
`AUDIO_TYPES` and `isAllowedAudioType()`, and `momentStoragePath()` bakes
in `.m4a` — so web must produce MP4/AAC; the client has no free choice. In
Chromium 148, `MediaRecorder.isTypeSupported('audio/mp4;codecs=mp4a')` is
**false** while `'audio/mp4;codecs=mp4a.40.2'` is **true**. Normalizing the
codec parameter away before comparing is load-bearing, because the rules
compare against a bare set.

**The waveform had been fabricated data** — `(index * 17) % 48`, a fixed
pattern that moved identically whether the microphone heard anything or
not, in direct violation of this project's own no-fake-data rule, and
nobody had caught it. It now draws the real amplitude stream.

## 6. Both reviews returned FAIL, and the deploy had already gone out

`cefa81a` closed them. Two findings carry well beyond this screen:

- **Flutter web has no per-node `aria-live`.** `LiveRegion` writes into a
  single shared announcement element and clears it after 300 ms, so two
  live regions changing in the same frame overwrite each other. Here a
  failed publish announced a success-sounding line — reassurance during a
  failure, the worst possible direction for a user who cannot see the
  screen. **The reusable rule: one polite live region per screen, and
  errors go out on the assertive channel, which is a separate element.**
  [ADR-058](../Decisions.md#adr-058-one-polite-live-region-per-screen-and-errors-go-out-on-the-assertive-channel),
  and a pointer in [UI.md](../UI.md#announcing-status-to-assistive-technology)
  where a future engineer will actually meet it.
- **`record_web` collapses every `getUserMedia` rejection to `false`**, so
  "no microphone connected", "microphone held by another app" and a merely
  dismissed prompt all surfaced as "your browser blocked access" — blaming
  the user for a hardware condition, and pointing at a setting already
  reading Allow. Fixed by calling `getUserMedia` directly and mapping
  `DOMException.name`.

Also fixed: the timer could render `0:60 / 1:00`, because the minute was
hard-coded while the seconds clamped to 60 — and the 60-second auto-stop
landed users on exactly that frame, so the impossible value was what the
last moment of every full-length recording showed. The preview harness
rendered under `ThemeData.dark` rather than `AppTheme.darkTheme`, so
earlier screenshots showed neither production typography nor the real input
field. And the screen migrated wholesale off raw hex onto `AppColors`, so
its primary purple finally matches `moments_screen.dart` beside it.

Suites: **521 tests across 55 files** (486/54 after `6ef4380`, 438/52
before this work). `flutter analyze` clean; `flutter build web` and
`flutter build ios --simulator` both pass.

## 7. A process failure, recorded plainly

The web client was deployed from `6ef4380` **before** the accessibility and
visual reviews returned, on the reasoning that recording was totally broken
and a working screen with defects beats no screen.

That reasoning holds, and the deploy was not reverted. But **both reviews
came back FAIL**, and waiting would have put the fixed version in users'
hands directly instead of shipping a screen that told screen-reader users a
failed publish had succeeded, then shipping again. The reviews were already
in flight; the error was about timing, not about the tradeoff.

**The rule going forward: for a UI change, review precedes deploy, exactly
as it does for rules.** This is not a suggestion and should not be restated
as one —
[ADR-059](../Decisions.md#adr-059-a-ui-change-is-reviewed-before-it-is-deployed-on-the-same-terms-as-a-rules-change).

## 8. The third stale-confident-claim in two days

`c7cea3e` corrected a rules comment that justified a broad ternary selector
by asserting the tighter variant would be **looser**. An audit built the
tighter variant and measured it: **identical, denial for denial.** The
fall-through the comment described was real only against the previous
`roomMembers` create rule — which the same commit had already closed. The
comment was justifying a shape with a mechanism its own commit had removed.

That is the third incident in two days, after ADR-005's collectionGroup
paragraph (which claimed fail-closed for a mechanism that fails **open**)
and PROJECT_STRUCTURE's description of a deploy script that did something
else. All three share a shape: true when written, the system moved, the
prose stayed confident. Confident prose is worse than none, because it
stops the next reader from checking — ADR-005's wrong paragraph produced
two spurious defect reports against a rule that was never the problem.

Named as a pattern rather than logged as an instance:
[ADR-060](../Decisions.md#adr-060-an-explanatory-comment-is-a-claim-measure-it-or-delete-it).

## What is still unverified

Stated because this project's rule is that unverified means unverified:

- **No screen reader has been run** — not VoiceOver, not NVDA, not
  TalkBack, on any screen in this project. ADR-058's fix is reasoned from
  Flutter's web `LiveRegion` implementation and covered by widget tests.
- **Keyboard tabbing is widget-tested only.**
- **The `DOMException` mapping has never met a real browser refusal** — no
  actual denial, unplugged device or device-in-use condition has been
  reproduced. The mapping is unit-tested against synthetic exception names.
- **Safari, Firefox, real microphone capture and end-to-end publish against
  Firebase are all unverified.** Chromium 148's MIME negotiation was
  checked directly; the rest of the web path is seam-tested.
Not on that list, because it *was* established: **production serves
`cefa81a`.** Verified the same way `6ef4380` was — the served
`main.dart.js` is 5,159,938 bytes, matching the local build exactly, and
contains `No sound detected`, `No microphone was found` and
`Discard this take`, three strings that exist only in that commit. Both
deploys are confirmed by reading served bytes, never by trusting deploy
output.
