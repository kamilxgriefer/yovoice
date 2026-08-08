# 2026-08-08 — P0 bugfix pass + profile media crop editors

One session, four user-reported defects fixed and verified, plus the
avatar/banner crop editor shipped. Web deployed. Details of each fix in
[Bugs.md](../Bugs.md#ui), [ADR-025](../Decisions.md#adr-025-profile-media-crop-editor-ships-the-final-cropped-jpeg-not-crop-metadata)
and [ADR-026](../Decisions.md#adr-026-more-destinations-re-host-the-shells-bottom-navigation-amends-adr-019).

## What shipped

1. **P0 — raw exception text in the UI.** Root cause was a Firestore
   rule evaluation error (null `resource` dereference on first-chat
   `transaction.get()`), surfaced on Flutter Web as "Dart exception
   thrown from converted Future…". Rules fixed (get/list split,
   deterministic-id check for non-existent conversations) and deployed;
   every `error.toString()` render replaced with
   `intentionalOrFriendly()` / `friendlyErrorMessage()`; `auth_provider`
   stores mapped copy.
2. **P0 — friend acceptance never notified the sender.** `notify()`'s
   dedupe query hit permission-denied and silently aborted. Rewritten to
   deterministic dedupe doc IDs; acceptance also retires the original
   `friendRequest` notification (`markMatchingRead`), logs failures,
   decline/cancel intentionally silent.
3. **P0 — bottom navigation disappearing.** `MoreDestinationHost` now
   re-hosts the shell's own `_BottomNavigation` on every More
   destination (one source of truth); bar taps pop to the shell first.
   Deep flows (chat, room, edit profile, subpages) still cover the bar
   by design.
4. **P1 — avatar/banner crop editors.** `ImageCrop` pipeline +
   `ImageCropScreen` (pinch/drag/reset, circular avatar mask, real 16:9
   banner frame), wired into Edit Profile; final cropped JPEG is what
   uploads (1024², 1920×1080, q85). Picker requests 2× output edge for
   zoom headroom. New dep: `package:image` (encode only).

## Verification

- `flutter analyze` clean; `flutter test` 78/78 (5 new/updated test
  files); Firestore rules emulator suite 91/0 (now deterministic —
  `clearFirestore()` added).
- **iOS Simulator (CeoGriefer, production Firebase)**: first-chat
  bootstrap opens cleanly; More → Settings/Friends keep the bar and bar
  taps land on the live shell; avatar cropped/positioned/saved; banner
  cropped/saved; media survives app restart; friend request sent to
  testGriefer through the real UI (left pending on purpose).
- **Deployed web (`yovoice-ec54a.web.app`, deployed bytes
  curl-verified)**: same chat opens cleanly; More destination keeps the
  bar; avatar+banner saved on iOS render correctly (fan-out/cache
  consistency across platforms).
- **Web crop editors**: verified via `lib/dev/crop_preview.dart`
  (real `ImageCropScreen`, no sign-in needed) — render, drag, JPEG
  confirm all work in the browser.
- **UNVERIFIED live**: the acceptance notification appearing on the
  *sender's* screen needs a second signed-in session, which this
  session's tooling could not obtain (no credentials may be entered).
  Covered by emulator rules tests + `friend_accept_notification_test`;
  the pending CeoGriefer→testGriefer request is staged so a human can
  close the loop in one tap.

## Loose ends

- Storage cap for `users/{uid}/profile/*` can come back down
  (Roadmap #0).
- The deployed web console logged one generic boxed `Error` during
  navigation stress-clicking; not user-visible, not reproduced.
