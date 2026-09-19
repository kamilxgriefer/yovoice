# Build 32: account deletion, public-Server invites, and a gate that caught the copy — 2026-09-18

## Status

**Source-only. Nothing was deployed, and nothing in this round ran against
production data.** Read each claim at the level of proof it carries.

- **Landed in source, both repos, green.** `yovoice` (the app, Cloud Functions,
  `firestore.rules`, `storage.rules`) and `yovoice-website`. Two decisions:
  ADR-206 (account deletion) and ADR-207 (invite widening).
- **Proven by emulator and widget tests.** The account-deletion pipeline, the
  rules, the widened inviter predicate at all three server-side sites, the
  Flutter screens, and the website's published claims. Two of the new backend
  cases were verified **red-before-green by reverting the fix**, not asserted on
  trust.
- **Verified visually by a rendered-frame harness, and by nothing else. There
  was no simulator or device run of the deletion flow.** The deletion screen's
  proof is `test/delete_account_screenshot.dart`: **112 frames** at
  320/402/834/1400 × EN/PL × 100/200 %, seven states per combination —
  consequences list, retained set expanded, bottom of the column,
  re-authentication, the confirmation dialog inert and armed, and the pending
  panel. Re-rendered from the final tree on **2026-09-19 02:16**
  (`b32/fix-3-flutter-screenshots.log`, frames in `b32/visual/app-delete-*.png`;
  byte-identical to the 2026-09-18 22:30 set, which is kept beside them under
  `visual/superseded-round2-2026-09-18T2230/`). The invite affordance is
  `test/server_invite_affordance_screenshot.dart` at 360/420/834/1400, with the
  two member cases also at 200 % text and in English (2026-09-18 21:27). These
  are `flutter test` renders: real layout, real fonts, real localized strings,
  off-screen canvas. Nothing more.

  **The `dev-*` simulator frames in the evidence directory do not corroborate
  this, and must not be cited as if they did.** An iOS Simulator session
  between 20:29 and 20:48 on 2026-09-18 captured a throwaway developer harness
  with a scenario picker; it was never committed and is not in the tree. Every
  one of those frames predates the copy corrections that landed at 21:13 and
  22:28, so they render sentences this build no longer ships. Their pending and
  failure states cannot have come from the real callable either —
  `deleteAccountSelfV1` is undeployed and fail-closed — so the deletion client
  behind them was a stub. They are superseded, not evidence.

  **Nobody ran a real deletion, and no part of this flow has run on hardware.**
  Re-authentication is the sharpest gap. `ReauthenticationService` chooses
  Google, then Apple, then password, and the two federated branches
  (`reauthenticateWithPopup` / `reauthenticateWithProvider`) are exercised only
  by widget tests with injected doubles. **Both federated re-authentication
  providers are UNVERIFIED on a real device or simulator**, and so is the
  password branch's real Firebase Auth round trip.
- **Not deployed, not enabled, not published.** `deleteAccountSelfV1` is
  fail-closed, `appConfig/accountDeletion.enabled` is unwritten, the digest salt
  is unset, and the website ships with `SELF_SERVICE_DELETION_LIVE = false`.
- **Known to be incomplete, in writing.** Four categories of personal data
  survive a completed deletion, two-factor accounts cannot use the in-app route,
  and the ban digest is inert until an operator sets a salt. All six are in
  Bugs.md with owners, and **none of them is claimed by any user-facing copy.**

## What the round was for

Two owner instructions.

1. Google Play requires an app with account creation to offer in-app account
   deletion and a web URL for deletion requests. YO Voice had neither, and the
   deployed Auth `onDelete` trigger deliberately RETAINED `users/{uid}`
   including the e-mail address.
2. "Powinny być opcje zaproszenia na serwery dla każdego użytkownika który
   dołączy do publicznego serwera znajomego bądź kogokolwiek, a w prywatnym taką
   opcję może mieć tylko admin i moderator serwera." — every member of a public
   Server may invite; on a private Server only an admin or moderator may.

## The finding that mattered most

The implementation was substantially correct. **The copy was not.** An
independent gate found that the app and the website both promised things the
pipeline does not do:

- "Servers you own are closed, and you leave every server you joined." The
  pipeline anonymizes membership and leaves ownership bound; its own emulator
  test asserts `ownerId === SUBJECT` and `role === "owner"`.
- "Your Voice Moments, Yeels, comments and reactions are deleted." Comments and
  reactions left on **other people's** posts are never touched.
- "Family memories, Company channel files" — uploads in somebody else's Storage
  container are never swept.
- "Your call records in Chats" — `directCalls` is never deleted.
- "This is everything we hold that is about you" — a categorical claim on the
  page filed in Play's Data safety form.
- A source comment claiming an enumeration of cross-container Storage prefixes
  that does not exist anywhere in the module.

Every one of these was a truthful-disclosure defect, not a code defect, and the
fix was to make the copy match the code rather than the other way round. Where a
claim is worth keeping, it is now an entry in Bugs.md with the stage and the
test it would need.

## What else the gate caught

- **Two workers could run the same deletion.** The attempt budget equalled the
  lease exactly, so the final stage step routinely started at the lease boundary
  and finished after it — and the mid-attempt `stage: "auth"` write was the one
  unguarded write in the pipeline, letting an expired worker stamp `auth` onto a
  row another worker held earlier. Fixed: budget lowered under the lease, and
  the write is now lease-guarded like every other.
- **`attemptCount` conflated progress with failure.** Any account needing eight
  or more leases dead-lettered on its first transient error with none of the
  eight retries the design promises. Fixed by splitting out `failureCount`.
- **The in-app deletion would have failed for every user.** The Flutter client
  re-authenticated and then sent the **cached** ID token, which on the native
  SDKs is not guaranteed to carry the new `auth_time`; the server refuses
  anything older than 300 s. The website implementer had hit exactly this and
  fixed it; the app had no equivalent. The forced refresh now lives in
  `AccountDeletionService`, immediately before the callable, so it holds for
  every route in — password, Google, Apple, and any second factor.
- **Twelve ADR citations pointed at the wrong decisions.** ADR-199 and ADR-200
  were already taken by Build 31. Re-derived against `docs/Decisions.md` and
  rewritten to ADR-206 and ADR-207 — fourteen citations in the end, because two
  were invisible to `grep`.

## An incidental find worth remembering

`functions/account/deletion.js`, `outbox.js` and `retention.js` contained
**literal NUL bytes**, used as hash-domain separators inside template literals.
Valid JavaScript, and the technique is sound — but `file` classified those
sources as binary, so `grep` skipped them silently. That is how two of the
fourteen wrong ADR citations stayed hidden through a review that grepped for
them. Replaced with `\0` escapes, which produce byte-identical strings; the
three hash outputs were captured before and after and compared.

The lesson generalises: a source file that tooling cannot read as text is a
review hazard regardless of whether it compiles.

## What must happen before any of this reaches a user

In this order, and the order is load-bearing for store review:

1. Deploy the account-deletion exports.
2. Deploy `firestore.rules`. It carries the two liveness narrowings the sweep
   depends on — `users/{uid}/muted` write and `users/{uid}/momentViews`
   create/update now also require `isActiveAccount()` — so a frozen client
   cannot keep appending rows behind the sweep. `momentViews` is the
   irreparable case: no TTL, `allow delete: if false`, so a row written after
   the sweep passed is one nobody can ever remove. It is **not** what makes the
   two new deny blocks work: the pipeline reaches `accountDeletionOutbox` and
   `deletedAccountDigests` through the Admin SDK, which bypasses Rules, so a
   missed rules deploy breaks nothing visibly and silently drops a guarantee.
3. Deploy the two sweep composites (`firestore.indexes.json`).
4. Set `YOVOICE_DELETED_ACCOUNT_DIGEST_SALT` (≥16 chars). Until it is set,
   deleting a banned account resets the ban.
5. Write `appConfig/accountDeletion.enabled = true`. Steps 2 and 3 go before
   this one: after it, the first person to tap Delete already relies on them.
6. Release the app carrying `Settings → Account → Delete account` to the
   stores. A store binary is reviewed and rolled out on its own clock and
   cannot be reverted from Firestore, which is why it goes after the backend
   and before the website.
7. Only then land the website with `SELF_SERVICE_DELETION_LIVE = true`.

Publishing the site first promises a deletion the servers cannot perform.
Submitting the app first sends a Play reviewer down an in-app route that
answers `not-found` / `failed-precondition` and offers only the e-mail
fallback — graceful for the user, but a data-deletion policy failure for the
listing. See [DEPLOYMENT.md](../DEPLOYMENT.md).
