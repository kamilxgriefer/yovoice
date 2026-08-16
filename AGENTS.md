# YO Voice agent orchestration

`CLAUDE.md` is the authoritative project policy. Every primary agent and
subagent must read it before working, then follow the domain documents it
routes to. The persistent specialist roster lives in `.codex/agents/` (Codex,
TOML) and `.claude/agents/` (Claude Code, Markdown with YAML frontmatter). Both
hold the same 20 roles and must stay in sync; the roster is documented in
`docs/AI_TEAM.md`.

## Assignment rules

- Delegate only concrete, bounded work to the narrowest matching specialist.
- Give each agent one clear owner area, acceptance criteria, relevant paths,
  and required evidence. Do not use multiple implementation agents on the same
  files concurrently.
- Parallelize independent discovery, implementation, test, visual, security,
  and documentation streams. The primary agent integrates their output and
  resolves conflicts.
- Use the professional role name from `.codex/agents/` when assigning work.
  Existing Active or Done entries in the Subagents panel retain the task labels
  with which they were originally spawned; new runs should use professional,
  role-identifying task labels.
- Subagents must never commit, push, deploy, publish, submit to an app store,
  open a pull request, discard unrelated work, or mutate production data. The
  primary agent alone may perform an explicitly authorized Git or release
  action after all required reviews pass.

## Domain routing

- Product scope, priorities, acceptance criteria: `Principal Product Manager`.
- Cross-system design, migrations, boundaries, ADRs: `Staff Software Architect`.
- Flutter features and responsive Material 3 UI: `Senior Flutter Product Engineer`.
- Firebase, Cloud Functions, rules, indexes, transactions: `Senior Firebase Backend Engineer`.
- Realtime room media and microphone lifecycle: `Senior Realtime Voice and Audio Engineer`.
- User journeys and implementation-ready UX/UI: `Senior Product Designer UX UI`.
- Accessibility and inclusive UX audit: `Accessibility and Inclusive Design Specialist`.
- Automated regression coverage: `Senior QA Automation Engineer`.
- Actual rendered phone, tablet, and desktop verification: `Senior Visual Quality Specialist`.
- Startup, latency, resilience, resources, observability: `Senior Performance and Reliability Engineer`.
- App Store, Google Play, purchases, subscriptions: `Mobile Store and Monetization Specialist`.
- Metrics, funnels, experiments, instrumentation: `Senior Product Analytics Specialist`.
- Reporting, blocking, abuse and moderation policy: `Trust and Safety Moderation Specialist`.
- Personal-data flows and GDPR engineering risk: `Privacy and GDPR Compliance Specialist`.
- Security threat modelling and remediation: `Cybersecurity Senior Specialist`.
- Independent attacker-minded security review: `Adversarial Security Auditor`.
- Builds, CI/CD, signing, rollback and release readiness: `DevOps and Release Engineer`.
- Project documentation and evidence accuracy: `Technical Documentation Manager`.
- Localization, RTL, formatting and linguistic QA: `Localization Specialist`.
- Independent final correctness and release review: `Principal Code and Release Reviewer`.

## Mandatory review cells

- Every implementation: owning engineer -> `Senior QA Automation Engineer` ->
  read-only `Principal Code and Release Reviewer`.
- Every user-facing UI change: `Senior Product Designer UX UI` and
  `Senior Flutter Product Engineer` -> `Senior Visual Quality Specialist` plus
  `Accessibility and Inclusive Design Specialist`.
- Authentication, Firestore or Storage rules, payments, entitlements,
  staff/moderation roles, ownership, uploads, or permissions:
  `Senior Firebase Backend Engineer` plus `Cybersecurity Senior Specialist` ->
  separate read-only `Adversarial Security Auditor` ->
  `Principal Code and Release Reviewer`.
- Realtime voice or room lifecycle: `Senior Realtime Voice and Audio Engineer`
  plus `Senior Performance and Reliability Engineer` ->
  `Senior QA Automation Engineer`.
- Store billing or Premium lifecycle: `Mobile Store and Monetization Specialist`
  plus `Senior Firebase Backend Engineer`, `Cybersecurity Senior Specialist`,
  `Privacy and GDPR Compliance Specialist`, and `Senior QA Automation Engineer`
  -> read-only `Adversarial Security Auditor`.
- Moderation or abuse controls: `Trust and Safety Moderation Specialist` plus
  `Senior Firebase Backend Engineer`, `Cybersecurity Senior Specialist`, and
  `Privacy and GDPR Compliance Specialist` -> read-only
  `Adversarial Security Auditor`.
- Release preparation: `DevOps and Release Engineer` plus
  `Technical Documentation Manager` -> read-only
  `Principal Code and Release Reviewer`.

## Completion gate

The primary agent must wait for all required specialists, address actionable
findings, rerun the checks required by `CLAUDE.md`, and distinguish automated,
visual, emulator, build, and production-deployment evidence. A task is not done
while a required review is outstanding or a known blocker is being presented as
working behavior.
