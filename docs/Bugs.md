# Known Issues

Current, living list of known bugs and tracked gaps — not a changelog.
Update this whenever a bug is found or fixed. For "features not built
yet," see [Roadmap.md](Roadmap.md) instead; this file is specifically
about things that are broken, risky, or need verification.

## Security

**No known critical open vulnerabilities.** A full audit
([Archive/SECURITY_AUDIT.md](Archive/SECURITY_AUDIT.md)) found 3 critical,
3 high, and 6 medium-priority issues plus one client/server contract bug.
Verified during this documentation pass, directly against current
`firestore.rules`, `storage.rules`, and `functions/`: **all 13 items are
fixed except one:**

- **`enforceAppCheck: false` on every Cloud Function** (audit item #12) —
  still open, but deliberately: flipping it needs a token-delivery
  monitoring period first (Firebase Console → App Check has the metrics).
  See [Decisions.md](Decisions.md). Not urgent on its own — it removes a
  layer that raises the cost of abusing the backend, it isn't itself an
  open exploit — but shouldn't be forgotten either.

If you're about to change `firestore.rules`, `storage.rules`, or anything
in `functions/`, skim the archived audit first — it's a good checklist of
the failure modes this codebase has actually hit before (self-role
assignment, missing field validation, `collectionGroup()` rule gaps,
client-trusted permission flags).

## Data integrity

- **Possible orphaned `rooms/{roomId}/members` documents.** When that
  subcollection was renamed to `roomMembers` (see Decisions.md), any
  pre-existing production documents under the old name became invisible to
  the app. Never verified whether any existed at rename time — no
  `gcloud`/Application Default Credentials were available in the session
  that made the change. **Action**: check the Firestore Console's
  `rooms/*/members` collections directly, or query via `firebase-admin`
  with a real service account key. If any exist, write a one-time copy
  migration.
- **`experience: podcast` legacy compatibility.** Still actively read by
  `lib/features/rooms/data/models/room_experience.dart` — do not remove
  until production room documents are confirmed migrated to `broadcast`.
  See [Decisions.md](Decisions.md).

## Code quality / consolidation

- **Two parallel hand-raise implementations exist**, unconsolidated. Not
  actively broken, but a maintenance risk — a fix applied to one may be
  missed in the other. See [Roadmap.md](Roadmap.md) item 12.
- **Most screens don't use the shared theme system** (`lib/core/theme/`,
  `lib/shared/widgets/`) yet — they use a consistent-but-inline hex-color
  convention instead. Not a bug, but tracked as a migration in progress —
  see [UI.md](UI.md) and [Roadmap.md](Roadmap.md).

## Infrastructure

- **`app.yovoice.app` DNS record not added yet** — blocks the website from
  pointing at its final app URL. Needs Cloudflare access only the domain
  owner has. See [Roadmap.md](Roadmap.md).
