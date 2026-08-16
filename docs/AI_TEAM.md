# YO Voice AI Team

YO Voice has a persistent, project-scoped team of 20 specialist agents. Their
source of truth is `.codex/agents/*.toml`; Codex discovers those files whenever
this trusted project is opened. `AGENTS.md` defines how the primary agent routes
work and which independent reviews are mandatory.

The same 20 roles exist for Claude Code as `.claude/agents/*.md` — one Markdown
file per role, with YAML frontmatter (`name`, `description`, optional `tools`)
and the role instructions as the body. The two rosters are mirrors of each
other: same roles, same remits, same safety boundary. Keep them in sync — when a
role's remit changes, update both files. Claude Code's `name` is a kebab-case
slug (for example `senior-firebase-backend-engineer`), so it is the professional
role name in lowercase with hyphens, except `Senior Product Designer UX UI` →
`senior-product-designer-ux-ui` and `Localization Specialist` →
`localization-specialist`. The four read-only reviewers that run under Codex's
`sandbox_mode = "read-only"` are constrained in Claude Code by a restricted
`tools` list and/or an explicit no-edit instruction instead.

Claude Code discovers agents in `.claude/agents/` of the directory the session
was opened in. Sessions opened at `~/Documents/GitHub` (the parent of `yovoice`,
`yovoice-website` and `yovoice-marketing`) see the roster through the symlink
`~/Documents/GitHub/.claude/agents` → `yovoice/.claude/agents`, so there is only
one copy to maintain. A newly added or edited agent file is picked up by the
next session, not the running one.

## Identity and badge convention

Each role has a professional `name`, a narrow remit, and a unique visual badge
at the start of its `description`. Role names stay ASCII for compatibility
across Codex clients. Codex does not document an `icon` or `avatar` field, so
emoji badges live in the supported `description` plus this roster instead of an
unsupported setting. See the official
[Codex custom-agent documentation](https://developers.openai.com/codex/multi-agent/)
for the supported project-scoped file format.

The Subagents panel is a run history, not the team editor. Existing Active and
Done rows keep the task labels used when those runs were spawned. The persistent
roles below apply to new assignments after the project configuration reloads.

## Permanent roster

| Badge | Professional role | Ownership | Operating mode |
|---|---|---|---|
| 🧭 | Principal Product Manager | Product framing, prioritization, acceptance criteria, rollout intent | Product owner; no application implementation |
| 🏛️ | Staff Software Architect | Cross-system boundaries, compatibility, migrations, ADR-quality decisions | Architecture owner |
| 📱 | Senior Flutter Product Engineer | Flutter features, state integration, Material 3, responsive UI | Implementation |
| 🔥 | Senior Firebase Backend Engineer | Firestore, Storage, Functions, indexes, rules, schema-safe transactions | Backend implementation |
| 🎙️ | Senior Realtime Voice and Audio Engineer | Room media lifecycle, microphones, devices, reconnects, audio quality | Realtime implementation |
| 🎨 | Senior Product Designer UX UI | Journeys, hierarchy, interaction states, responsive specifications | Design and handoff |
| ♿ | Accessibility and Inclusive Design Specialist | WCAG, semantics, focus, contrast, motion, text scaling, inclusive voice UX | Independent read-only audit |
| 🧪 | Senior QA Automation Engineer | Flutter, emulator and integration regression coverage | Test implementation |
| 👁️ | Senior Visual Quality Specialist | Real rendered phone, tablet and desktop checks with screenshots | Independent visual verification |
| ⚡ | Senior Performance and Reliability Engineer | Startup, jank, network efficiency, resilience, resources, observability | Measured reliability work |
| 💳 | Mobile Store and Monetization Specialist | App Store, Google Play, subscriptions, restore, expiry and store compliance | Store and billing owner |
| 📊 | Senior Product Analytics Specialist | Metrics, event taxonomy, funnels, experiments and data quality | Privacy-aware analytics |
| 🧯 | Trust and Safety Moderation Specialist | Reporting, blocking, abuse prevention, appeals and moderator workflows | Safety-policy owner |
| ⚖️ | Privacy and GDPR Compliance Specialist | Data minimization, retention, deletion, export and GDPR engineering risk | Independent read-only review |
| 🛡️ | Cybersecurity Senior Specialist | Threat models and minimal security remediation across trust boundaries | Security implementation |
| 🕵️ | Adversarial Security Auditor | Attacker-minded authorization, payment, abuse and privilege-escalation review | Independent read-only audit |
| 🚀 | DevOps and Release Engineer | Reproducible builds, CI/CD, signing, rollout, rollback and runbooks | Release readiness; no deployment |
| 📚 | Technical Documentation Manager | Product, architecture, testing, security and operational documentation | Evidence-based documentation |
| 🌍 | Localization Specialist | Externalized copy, pluralization, formatting, RTL and linguistic QA | Localization owner |
| ✅ | Principal Code and Release Reviewer | Final correctness, regressions, maintainability and release evidence | Independent read-only final review |

## Delivery workflow

1. The Principal Product Manager defines the user outcome and acceptance
   criteria when scope is not already explicit.
2. The Staff Software Architect is added only for cross-cutting boundaries,
   schema evolution, migrations, or a new architectural pattern.
3. The narrowest engineering owner implements the change. Independent owners
   may work in parallel only when their files and decisions do not overlap.
4. The Senior QA Automation Engineer proves behavior through focused tests and
   the broader repository gates required by `CLAUDE.md`.
5. UI work receives real-device or real-render visual verification and an
   accessibility audit. Static code inspection is not visual proof.
6. Sensitive work receives two distinct security passes: the Cybersecurity
   Senior Specialist owns remediation, then the read-only Adversarial Security
   Auditor attempts to break it independently.
7. The Technical Documentation Manager records only behavior supported by code
   and evidence. The DevOps and Release Engineer distinguishes build readiness
   from deployment state.
8. The read-only Principal Code and Release Reviewer performs the final pass.
   The primary agent resolves findings and alone performs any explicitly
   authorized commit, push, deploy, publish, or store action.

## Mandatory review routing

| Change type | Required team cell |
|---|---|
| Flutter UI | Product Designer + Flutter Engineer + QA + Visual Quality + Accessibility |
| Firebase or schema | Firebase Engineer + QA + Cybersecurity + Adversarial Auditor |
| Auth, roles, ownership or permissions | Firebase Engineer + Cybersecurity + QA + Adversarial Auditor |
| Premium, entitlements or payments | Monetization + Firebase + Cybersecurity + Privacy + QA + Adversarial Auditor |
| Realtime voice | Voice and Audio + Performance and Reliability + QA |
| Moderation or abuse | Trust and Safety + Firebase + Cybersecurity + Privacy + Adversarial Auditor |
| Analytics or experiments | Product Analytics + Privacy + QA |
| Localization | Localization + Product Design + Accessibility + Visual Quality |
| Release preparation | DevOps and Release + Documentation + Principal Reviewer |

Every implementation also ends with the Principal Code and Release Reviewer.
The primary agent may add specialists when risk crosses domains, but must not
skip a required independent reviewer.

## Safety and authority boundary

All specialist files explicitly forbid commit, push, and deployment; their
domain instructions also restrict publishing, store submission, pull-request
creation, destructive actions, and production-data access where applicable.
Review agents do not implement their own findings. This keeps implementation,
adversarial review, release authorization, and user-facing communication
separate.

Project files preserve the team across sessions and, once committed, across
clones. They do not rename historical subagent runs that already exist in the
read-only Active or Done lists.
