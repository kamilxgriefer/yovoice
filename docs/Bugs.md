# Known Issues

Current, living list of known bugs and tracked gaps — not a changelog.
Update this whenever a bug is found or fixed. For "features not built
yet," see [Roadmap.md](Roadmap.md) instead; this file is specifically
about things that are broken, risky, or need verification.

## Security

**No known critical open vulnerabilities.** For the full security model
(not just this status snapshot), see [SECURITY.md](SECURITY.md). A full
audit ([Archive/SECURITY_AUDIT.md](Archive/SECURITY_AUDIT.md)) found 3
critical, 3 high, and 6 medium-priority issues plus one client/server
contract bug. Verified during the documentation audit, directly against
current `firestore.rules`, `storage.rules`, and `functions/`: **all 13
items are fixed except one:**

- **`enforceAppCheck: false` on every Cloud Function** (audit item #12) —
  still open, but deliberately: flipping it needs a token-delivery
  monitoring period first (Firebase Console → App Check has the metrics).
  See [ADR-004](Decisions.md#adr-004-firebase-app-check-integrated-client-side-enforcement-deliberately-off).
  Not urgent on its own — it removes a layer that raises the cost of
  abusing the backend, it isn't itself an open exploit — but shouldn't be
  forgotten either. Tracked as a Roadmap item too:
  [Roadmap.md](Roadmap.md#2-firebase-app-check-enforcement).

If you're about to change `firestore.rules`, `storage.rules`, or anything
in `functions/`, read [SECURITY.md](SECURITY.md#firestore-security-rules--design-principles)'s
design principles and checklist first — each one maps to a specific
failure mode this codebase has actually hit before (self-role assignment,
missing field validation, `collectionGroup()` rule gaps, client-trusted
permission flags).

## Data integrity

- **Possible orphaned `rooms/{roomId}/members` documents.** When that
  subcollection was renamed to `roomMembers` (see
  [ADR-005](Decisions.md#adr-005-roomsroomidmembers-renamed-to-roommembers)),
  any pre-existing production documents under the old name became
  invisible to the app. Never verified whether any existed at rename
  time — no `gcloud`/Application Default Credentials were available in
  the session that made the change. **Action**: check the Firestore
  Console's `rooms/*/members` collections directly, or query via
  `firebase-admin` with a real service account key. If any exist, write a
  one-time copy migration. Tracked in
  [Roadmap.md](Roadmap.md#1-verify-no-orphaned-roomsroomidmembers-documents).
- **`experience: podcast` legacy compatibility.** Still actively read by
  `lib/features/rooms/data/models/room_experience.dart` — do not remove
  until production room documents are confirmed migrated to `broadcast`.
  See [ADR-001](Decisions.md#adr-001-legacy-podcast-room-experience-stays-supported).

## UI

- **Fixed: white panel flashing behind sheet transitions (e.g. New Chat)
  on devices with the OS set to Light mode.** Root cause was native
  Android/iOS window chrome following the *system* light/dark setting
  instead of the app's own dark-only theme — not a bug in the Dart-side
  sheet code. See
  [ADR-016](Decisions.md#adr-016-native-android-and-ios-window-chrome-is-pinned-dark-not-os-controlled)
  for the full root cause and fix.

## Code quality / consolidation

- **Two parallel hand-raise implementations exist**, unconsolidated. Not
  actively broken, but a maintenance risk — a fix applied to one may be
  missed in the other. See
  [Roadmap.md](Roadmap.md#12-consolidate-the-two-parallel-hand-raise-implementations).
- **Most screens don't use the shared theme system** (`lib/core/theme/`,
  `lib/shared/widgets/`) yet — they use a consistent-but-inline hex-color
  convention instead. Not a bug, but tracked as a migration in progress —
  see [UI.md](UI.md) and
  [Roadmap.md](Roadmap.md#app-wide-theme-migration).
- **Zero automated test coverage for Cloud Functions**, and near-zero for
  Flutter services/widgets beyond one file. Not a regression — coverage
  was never broad to begin with — but worth knowing before assuming a
  change is safe because "the tests pass." See [TESTING.md](TESTING.md)
  for exactly what is and isn't covered.

## Infrastructure

- **`app.yovoice.app` DNS record not added yet** — blocks the website from
  pointing at its final app URL. Needs Cloudflare access only the domain
  owner has. See [Roadmap.md](Roadmap.md).
