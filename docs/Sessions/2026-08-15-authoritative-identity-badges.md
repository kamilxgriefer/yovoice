# 2026-08-15 — Authoritative identity badges on every surface

**Scope:** one identity-badge system across the whole app — official
role (server-authoritative, permission-linked), VIP (independent
entitlement), and a reserved-but-unbuilt achievement-cosmetics slot —
rendered by one shared widget family and resolved through one batched
repository over the existing `publicBadges` projection.
[ADR-045](../Decisions.md#adr-045-one-authoritative-identity-badge-system--owner-guarded-derivation-a-batched-client-repository-and-a-single-family-of-badge-widgets)
holds the full decision record.

## Backend (functions/, deployed before the client)

- `derivePublicRole(uid, user)` in `badges/public_badges.js`: the mirror
  publishes `superAdmin` only for the confirmed protected-owner uid.
  A forged/stale non-owner `superAdmin` publishes as `superModerator`
  (the tier the capability matrix actually grants it) and raises
  `security_alert_non_owner_super_admin` with
  `attempted: badgeDerivation`. Owner confirmation requires the secret
  present AND matched — with the secret unavailable, nobody gets the
  owner badge, the real owner included.
- `getPublicBadges` applies the same demotion to STORED rows (defense in
  depth for rows written before the guard) and, like both badge
  triggers, now binds `YOVOICE_PROTECTED_OWNER_UID`.
- `scripts/backfill_badges.js`: refuses to run without the owner guard
  (`assertOwnerGuard`), counts `unconfirmedSuperAdmins` in the aggregate
  report, and deliberately does NOT block apply on them — the fail-safe
  badge is the write that heals a forged row.
- Tests: 21 badge tests (owner vs forged vs unguarded-secret derivation,
  sync alerts, stale-row demotion in the callable, backfill refusal),
  195 Functions tests green overall.

## Client (lib/)

- New `shared/identity/`: `OfficialRole` enum (exact labels, colors from
  `AppColors` — the palette's single source), `PublicIdentity`,
  `AchievementStyle` (reserved cosmetic slot, contract documented, no
  construction), and `PublicIdentityRepository` — flush-window batching
  over `getPublicBadges` (≤50 uids/request, chunked), in-memory cache,
  in-flight dedup, cache cleared on account switch, `revision` notifier
  for post-role-change refresh, USER fallback on failure. Transient
  failures are answered but not cached; ABSENCE (ordinary account) is
  cached as USER by design.
- New `shared/widgets/identity/`: `OfficialRoleBadge`, `VipBadge`
  (always after the role badge, never instead), `UserIdentityBadges`
  (resolves by uid; renders USER immediately, upgrades when resolution
  lands), `DecoratedUserAvatar`. Variants `full` / `compact` / `icon`
  (tooltip carries the label); `Wrap` + a `Flexible` pill label keep
  narrow surfaces overflow-free without hiding the role.
- Surfaces wired (all through the shared components, none defining
  their own role colors/labels): desktop sidebar profile card, mobile
  profile header (`ProfileHeader`), `FriendProfileScreen`,
  `ProfilePreviewSheet`, Global Chat (`GlobalChatPanel`, desktop +
  mobile host), DM header (`ChatScreen`), room chat sheet, Club/Family
  chat, broadcast participants sheet, community room People drawer,
  community stage tiles, broadcast host tile and guest roster tiles,
  Moments cards and comment cards, People & Moments rail, friends list,
  follow lists, Add-Friend search (suggestions + results), Discover
  room/creator cards (both card kinds), Top creators (desktop card +
  mobile rows), notifications (friend-request card + activity rows),
  Staff Center (lookup now resolves VIP through the repository and
  invalidates it after `assignUserRole`), Moderation Center
  reported-account header.
- Removed as a trust source: Global Chat's message-embedded
  `senderIsStaff` "Team" chip (field still written/validated; renders
  nothing). "Creator" chip retained — account type, not a role.
- `RoleIdentity` reduced to the string-keyed Staff-Center adapter,
  aliasing `AppColors` so the palette cannot fork.

## Verification

- `flutter analyze` clean; Functions suite 195/195; rules suite 209/209
  (existing publicBadges client-write/list denials); new
  `identity_badges_test.dart` (exact labels + hexes, role×VIP order,
  owner mapping, USER fallback, batching = 1 request per window,
  50-uid chunking, dedup, cache/account-switch/invalidate, 120px
  overflow, cosmetics-cannot-replace-badges); `global_chat_test.dart`
  updated to assert projection-driven badges (`MODERATOR` + `VIP` from
  the repository, `USER` for an ordinary sender, `Team` gone).
- The overflow test caught a real bug pre-ship (pill label not
  `Flexible` → RenderFlex overflow at 120px) — fixed in the component.

## Deploy

- Functions deploy (badge module + secret bindings), backfill dry-run →
  apply with `YOVOICE_PROTECTED_OWNER_UID` exported, then the client
  push — separate backend and client commits, straight to `main` per
  repo convention.
