# Documentation Audit

Full audit of every Markdown file in the repository, performed
autonomously. Every `.md` file found is listed below with the action
taken, why, and its new location if it moved.

**Headline finding, unrelated to documentation organization itself**:
`docs/SECURITY_AUDIT.md` (now archived) documented 13 issues, 3 of them
critical (room takeover, club ownership takeover, LiveKit voice-moderation
bypass). While verifying whether that document was still current before
archiving it, all 13 were checked directly against today's
`firestore.rules`, `storage.rules`, and `functions/` — **12 of 13 are
already fixed**. Only App Check enforcement (`enforceAppCheck: false`,
item #12) remains open, and that's a deliberate, tracked decision, not an
oversight. Full current status in [Bugs.md](Bugs.md).

## Final structure

```
/
├── CLAUDE.md
├── README.md
└── docs/
    ├── Vision.md
    ├── Architecture.md
    ├── Features.md
    ├── Roadmap.md
    ├── Firebase.md
    ├── Backend.md
    ├── Flutter.md
    ├── UI.md
    ├── Decisions.md
    ├── Bugs.md
    ├── DOCUMENTATION_AUDIT.md      (this file)
    ├── Sessions/
    │   └── 2026-08-04-app-check-collectiongroup-fixes-website-authbuildout.md
    └── Archive/
        ├── SECURITY_AUDIT.md
        └── ROOMS_REBUILD_PLAN.md
```

`firestore-tests/README.md` and `ios/Runner/.../LaunchImage.imageset/README.md`
stay exactly where they are — see their entries below for why.

---

## Every file found, and what happened to it

| # | File (original path) | Category | Action | New location | Why |
|---|---|---|---|---|---|
| 1 | `README.md` | Essential | **KEEP** (rewritten) | `README.md` | Landing page. Trimmed to remove duplication now living in `docs/` (vision, feature list, dev-setup detail); replaced with cross-links. |
| 2 | `CLAUDE.md` | Essential | **KEEP** (edited) | `CLAUDE.md` | Working rules for this repo. Internal links updated to the new `docs/` paths; repo map updated to mention `docs/Sessions/` and `docs/Archive/`. |
| 3 | `Architecture.md` (root) | Essential | **MOVE + MERGE** | `docs/Architecture.md` | Moved into `docs/` per target structure. Trimmed: Firestore-schema detail moved out to the new `Firebase.md`, Cloud Functions detail moved out to the new `Backend.md`, Flutter-app detail moved out to the new `Flutter.md`. Now a short top-level map that links to all of them. |
| 4 | `Vision.md` (root) | Essential | **MOVE + MERGE** | `docs/Vision.md` | Moved into `docs/`. The detailed "Product pillars" section (one paragraph per feature) was duplicate content with the new `Features.md` — trimmed to a one-line pointer there instead. |
| 5 | `Roadmap.md` (root) | Essential | **MOVE** | `docs/Roadmap.md` | Moved into `docs/`, content unchanged (already accurate, no duplication found). |
| 6 | `Decisions.md` (root) | Essential | **MOVE + MERGE** | `docs/Decisions.md` | Moved into `docs/`. Added two new entries during this audit: the security-audit remediation (server-side permission checks over client-trusted flags) and the `experience: 'podcast'` compatibility rule — both were previously only documented in the now-archived `ROOMS_REBUILD_PLAN.md`/`SECURITY_AUDIT.md` and are still live, active constraints that belong in the main docs, not only in `Archive/`. |
| 7 | `CHANGES_STAGE_5_4.md` (root) | Completed change log | **DELETE** | — | A narrow, mechanical file-diff summary for one already-shipped change (achievement tracking wired into chat). No unique rationale or architectural knowledge beyond what current code already shows; git history preserves the actual diff. Matches the explicit instruction to remove completed stage reports/implementation logs with no long-term value. |
| 8 | `INSTALL_FIX.md` (root) | Installation/debug notes | **DELETE** | — | One-time instructions for manually applying a specific historical patch package ("replace your `lib` folder with the one from this package"). That workflow doesn't apply to how this repo is version-controlled today; no durable knowledge lost. |
| 9 | `STAGE_2_MANIFEST.md` (root) | Migration/implementation notes | **DELETE** | — | Pure file-manifest for one historical patch delivery (which files changed, what to validate). No rationale, fully superseded by git history and current code. |
| 10 | `docs/SECURITY_AUDIT.md` | Essential (historical) | **ARCHIVE** (banner added) | `docs/Archive/SECURITY_AUDIT.md` | Real, valuable security analysis — never delete. But presenting it unchanged in the main docs tree would mislead readers into thinking 13 critical/high vulnerabilities are still open, when 12 of 13 are fixed (verified against current code during this audit). Archived with a status banner explaining what's fixed and pointing to `Bugs.md` for current status. Its still-relevant finding (server-side-checks-over-client-trust pattern) was also written forward into `Decisions.md`. |
| 11 | `docs/ROOMS_REBUILD_PLAN.md` | Completed stage report + one live constraint | **ARCHIVE + MERGE** | `docs/Archive/ROOMS_REBUILD_PLAN.md` | Stages 1–3 are complete historical narrative (kept — real design rationale for why Community/Broadcast rooms look and behave differently). Before archiving, merged in `STAGE_2_COMMUNITY_ROOM.md`'s two implementation details not present here (participant-doc-removal disconnect behavior, moderator-mute synced to local mic). The one still-active rule (don't remove `podcast` compatibility until data is migrated) was copied forward into `Decisions.md` and `Firebase.md` so it's visible without opening the archive. |
| 12 | `docs/STAGE_2_COMMUNITY_ROOM.md` | Duplicated documentation | **DELETE** (merged first) | — | Described the same feature as `ROOMS_REBUILD_PLAN.md`'s "Stage 2" section — the two documents were a near-complete duplicate. Its two unique implementation details were merged into `Archive/ROOMS_REBUILD_PLAN.md` before deletion, per "if two documents describe the same feature, consolidate them." |
| 13 | `PROJECT_STATUS.md` (root) | Completed session log | **MOVE** (banner added) | `docs/Sessions/2026-08-04-app-check-collectiongroup-fixes-website-authbuildout.md` | A genuine point-in-time session handoff doc (App Check integration, two `collectionGroup()` bug fixes, website auth build-out) — real value as a historical record, but written in the present tense in a way that would mislead a reader today (a lot has shipped since). Moved into the new `docs/Sessions/` log, renamed with its actual date, with a banner clarifying it's historical and pointing to current docs. |
| 14 | `firestore-tests/README.md` | Essential (subproject doc) | **KEEP in place** | `firestore-tests/README.md` | Accurate, actively relevant, correctly scoped to its subproject — moving it would only add indirection. One internal link updated (`../docs/SECURITY_AUDIT.md` → `../docs/Archive/SECURITY_AUDIT.md`) to follow the file it points to. |
| 15 | `ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md` | Xcode boilerplate | **KEEP in place, out of scope** | *(unchanged)* | Flutter/Xcode-generated template text describing the asset catalog folder it lives in. Not project documentation in the sense of this audit — moving or deleting it could confuse Xcode's asset catalog tooling for no benefit. |

## New files created

Per the requested structure, several docs didn't exist as dedicated files
before — content was scattered across the files above, README.md, or
simply not written down. Created fresh, grounded in the current codebase
(not invented):

| File | Covers |
|---|---|
| `docs/Features.md` | Consolidated feature-by-feature reference — merged from `Vision.md`'s old "Product pillars" section, `README.md`'s old feature list, and the Rooms feature detail from the two archived stage documents. |
| `docs/Firebase.md` | Firestore schema/collections, Storage rules, Auth, App Check, email delivery, rules testing — split out of `Architecture.md`. |
| `docs/Backend.md` | Cloud Functions inventory and what each one does (LiveKit token minting, notification triggers, admin, friends, clubs) — split out of `Architecture.md`. |
| `docs/Flutter.md` | App structure, state management, feature modules, navigation pattern, dev setup — split out of `Architecture.md` and `README.md`. |
| `docs/UI.md` | Design system status (the shared theme system vs. the inline-hex convention most screens actually use), the "Coming soon" pattern, quality bar. |
| `docs/Bugs.md` | Current known issues — verified-current status of every item from the archived security audit, plus data-integrity, code-quality, and infrastructure gaps pulled from `Roadmap.md`/`Decisions.md` context. |

## Explicitly excluded from this audit

- **`docs/.obsidian/`** — an Obsidian vault config folder, untracked by
  git. Not project documentation; left completely untouched.
- **`docs/00 Project/`** — was present at the start of this audit as a set
  of empty (0-byte), untracked Markdown files with the same names as some
  of the docs above (`Vision.md`, `Architecture.md`, etc.), evidently an
  in-progress personal Obsidian vault scaffold. It disappeared from disk
  partway through this session (not removed by this audit — never staged,
  moved, or deleted by any command run here). Flagging in case its absence
  is unexpected.

## Link maintenance

Every cross-reference between the moved/created files was written (or
rewritten) to match the final structure: files that ended up together in
`docs/` link to each other with bare filenames (`Decisions.md`); links from
the repository root (`README.md`, `CLAUDE.md`) use the `docs/...` prefix;
links into `docs/Archive/` and `docs/Sessions/` use that subfolder prefix.
`firestore-tests/README.md`'s one outbound link was updated to match
`SECURITY_AUDIT.md`'s new path.
