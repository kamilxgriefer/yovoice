# 2026-08-15 — Staff Center redesign & the user directory

**Trigger:** the owner searched an existing user's name in Staff Center
and got "no result"; the screen itself was one card above an empty page.
[ADR-046](../Decisions.md#adr-046-user-search-lives-in-a-server-only-directory-behind-an-owner-callable-staff-center-becomes-seven-capability-gated-sections)
holds the decision record. Builds directly on the identity-badge
milestone (ADR-045) from earlier the same day.

## Root cause of the lookup failure (reproduced, not assumed)

`users.username` is stored AS TYPED — `ProfileService` seeds it verbatim
from the display name (`Sieeema`) and `updateProfile` preserves casing —
while `StaffUserLookup` lowercased the input into
`where('username', isEqualTo: 'sieeema')`, a case-sensitive equality.
Emulator repro with the exact query: stored `Sieeema` → input under any
casing → 0 rows. Display-name search did not exist; `@` was never
stripped; resolution ran client-side.

## Backend

- `functions/staff/directory.js` — `userDirectory/{uid}`: normalized
  search fields (NFKC/trim/collapse/lowercase) beside the stored forms,
  public effective role via `derivePublicRole`, VIP/banned/restricted
  flags, Auth `createdAt`. Auth is authoritative for existence (accounts
  without a profile document stay discoverable). Three triggers (users,
  vipGrants, restrictions) converge it; `searchUserDirectory` is
  PROTECTED-OWNER-ONLY (requireProtectedOwner — forged superAdmin
  audited), modes uid/email/name/browse, ≤20 rows/page, name mode over
  a bounded two-branch prefix fetch with a deterministic offset cursor.
- `functions/staff/overview.js` — `getStaffOverview` (owner-only):
  count() aggregates (users, active rooms, open reports, restricted,
  staff, VIP, security alerts) + five real lists. Summaries carry ids
  and roles, never emails.
- `functions/admin/audit.js` — `mapAuditLog` and its filters remapped to
  the FLAT schema `writeAuditLog` actually stores (`actorId`,
  `targetId`, …); the nested mapping it shipped with matched nothing.
- `scripts/backfill_directory.js` — dry-run default, `--apply` gated,
  owner-guard env required, Auth-paged with batched Firestore joins,
  orphan sweep, aggregate-only output.
- `firestore.rules` — `userDirectory` denied to every client (get, list
  and write). `firestore.indexes.json` — 4 userDirectory composites
  (flags × createdAt) + 3 adminAuditLogs composites (action / actorId /
  targetId × createdAt).

## Client

- `StaffCenterScreen` rewritten: internal left rail ≥980px, tab chips
  below; sections rendered only where the server-derived capability
  exists — owner: all seven; moderation tiers: Reports, Rooms & Spaces,
  Sanctions; everyone else: the refusal message.
- Users section: debounced (350ms) search submitting on Enter, ≥2-char
  guard as a hint (not an error), six filters, paged rows (avatar, name,
  badges, @username, copyable uid, ACTIVE/MUTED/BANNED, join date),
  distinct loading / no-results / permission / network / server states
  with Retry + Clear — an error is never dressed as "not found".
- User detail drawer: identity + badges, authoritative status
  (getUserRole), active restriction, hosted public rooms, moderation &
  role history (audit browser by targetId), the shared ••• sanctions
  menu, owner role-change (assignUserRole with `expectedRole` guard) and
  ban/unban (setUserBan) — all confirm-with-reason, double-submit
  guarded, server-confirmed before UI updates, row refreshed in place.
- Overview/Reports/Rooms/Sanctions/Staff&Roles/Audit sections all read
  real services; overview cards navigate into filtered sections.
- `UserManagementScreen` kept intact (untouched screen + tests); the
  new Users section supersedes it in navigation.

## Verification

- Functions: 218/218 (21 directory + 2 overview new). Rules: 210/210
  (userDirectory denial new). Flutter: full suite + 15 new Staff Center
  widget tests; `flutter analyze` clean; release web build.
- Gating test updated: mod tiers now SEE their sections (the redesign's
  requirement) — refusal stays for accounts with no backing capability.

## Deploy

Functions + rules + indexes first, then the directory backfill (dry-run
→ verify aggregates → apply), then the client push (Hosting
auto-deploys on push). Separate backend and client commits.
