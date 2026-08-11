# 2026-08-11 — Global Chat, and the rail's Voice Moment action back

Two corrections to the previous session, both from the same annotated
desktop screenshot.

## 1. `Create Voice Moment` restored in the rail

Read as obsolete last time and removed; it was intentional. It is back
as a **secondary** action directly under the gradient `Create Room` —
outlined, 44px, mic icon, violet-on-rail — above the pinned profile
card.

It is not a second recorder. `MainShell` now has one
`_openCreateMoment()` and every entry point calls it: the rail button,
the Moments strip's "Your Moment" tile, and mobile Home. Same
`RecordVoiceMomentScreen`, same permissions, same 60s limit, same
`MomentService` upload path, same navigation. The Moments strip tile
stayed exactly where it was.

## 2. `All` → a real Global Chat

The old `All` tab merged this account's club and direct conversations
into one list. That is a per-user aggregation of private material, not a
community chat, so it is gone. Tabs are now **Global** (first, default),
Friends, Clubs, Private.

### The channel

`globalChat/main/messages` — one canonical conversation for the whole
authenticated community, a separate top-level collection from
`conversations` (private DMs) and `clubs/*/channels/*` (member-only).
The channel id is pinned to `main` **by the rules**, so nobody can stand
up a parallel "global" channel.

### Why direct writes, not a callable

ADR-013 reserves Cloud Functions for what rules structurally cannot do,
and names "typing a chat message" as the case where a cold start is felt
by a person waiting. None of its four conditions apply: no secret, no
uncomputable capability, no fan-out, no cross-document choreography. The
usual reason to reach for a callable is rate limiting — and rules can do
that here:

- each send is a batch of the message **plus**
  `globalChat/main/senders/{uid}` = `{lastMessageAt: request.time,
  lastMessageId: <this message's id>}`;
- the message rule verifies that document *after the same commit* with
  `getAfter()`;
- the sender-document rule refuses to advance until 3 s have elapsed;
- deleting it, or touching anyone else's, is denied.

Binding it to a **specific message id** is the part that matters: with
only a timestamp, one batch of 500 messages plus one cooldown update
would satisfy the check for all 500. There is a test for exactly that.

### Everything else rules enforce

`senderId == request.auth.uid`; `sentAt == request.time`;
`senderName`/`senderIsCreator` validated against the sender's own
`users/{uid}` document (a public feed is an impersonation surface in a
way a DM is not); `senderIsStaff` compared to the ID token's `role`
claim, so it cannot be self-awarded; content non-blank after `trim()`
and ≤ 500 chars; an exact key allowlist; nothing arrives pre-deleted.
Soft delete only — author or role-claim moderator — with content and
authorship frozen; hard delete is `if false` for everyone.

### What had to be built because it did not exist

- **Reporting.** The product had blocking but no reporting anywhere.
  A public channel cannot ship with block-only tooling, so `reports` is
  new: create-only for verified members with their own uid, a server
  timestamp and `status: 'open'`; members can never read, edit or
  withdraw one; staff read and triage via the `role` claim.
- **A moderation audit trail.** Every other moderator action in this
  project writes `adminAuditLogs` from the Admin SDK. Rules can't log,
  so `onGlobalMessageModerated` (Firestore trigger) records who removed
  whose message, with the removed text, whenever the remover is not the
  author.

Blocking, bans and roles were **reused, not reinvented**: blocking is
the existing `users/{uid}/blocked` list, bans already disable the
Firebase Auth account outright, and moderator status is the existing
custom claim set by the admin-gated, audited `assignUserRole`.

## Limits, stated rather than hidden

- **Blocking is one-directional here.** You never see a blocked
  account's messages; an account that blocked you still sees yours.
  Rules cannot filter one shared query per reader, and another user's
  blocked list is deliberately unreadable. Symmetry would need a
  mirrored `blockedBy` edge — a blocking-schema change, not made.
- **No unread badge for Global.** No per-user last-seen marker exists,
  and one was not invented. Global lives in its own collection and is
  never summed into the DM unread count the rail badge shows.
- **The cooldown is a spam floor, not abuse prevention.** 20 messages a
  minute per account, no content filtering, and ADR-004's App Check gap
  still applies.
- **Report triage has no UI** — Firestore Console until one exists.
- **No expanded Global Chat screen.** The brief asked for one "if an
  appropriate desktop chat content slot exists"; none does (the Chats
  slot is the DM inbox), so the module is the whole surface.

## Verification

- `flutter analyze` clean; **174 Flutter tests** pass (162 before this
  session's additions).
- **128 Firestore rules tests** pass against the emulator, 28 of them
  new: cross-account shared visibility, unauthenticated read/send
  denial, sender/name/staff/timestamp spoofing, empty/blank/oversized/
  pre-deleted content, skipping the cooldown, posting inside the
  cooldown, batch-burst spam, deleting the cooldown doc, reading
  another member's cooldown doc, rewriting a posted message, deleting
  someone else's, moderator re-attribution, moderator soft delete,
  author soft delete, hard delete, paging, second-channel creation, and
  six report cases. The 99 pre-existing cases still pass — DM and Club
  rules are unchanged.
- New Dart coverage in `test/global_chat_test.dart`: canonical path,
  profile-sourced identity, client-side validation, soft delete, the
  growing pagination window (no duplicates, no reordering), badges,
  removed-message state, empty state, composer, reader-side blocking,
  and "load earlier".
- Looked at, not just tested, via `test/desktop_home_preview.dart` at
  1440×1550, 1100×1900 and 1440×620: the rail's two actions in order
  above the pinned profile card, and the Global feed with badges,
  timestamps, a removed message and the composer, with no overflow.

## Not done

Not deployed. Going live needs
`firebase deploy --only firestore:rules,functions`. (This section
originally also claimed a manually created `globalChat/main` document was
required — that was wrong, and the hardening pass below removes it.)

---

# Production-hardening pass (same day)

A review found the first cut was not safe to enable. Seven corrections,
all inside the existing architecture — see
[ADR-038](../Decisions.md#adr-038-global-chat-hardening--account-status-in-rules-no-manual-channel-structural-report-uniqueness-two-tier-rate-limits).

- **Bans now bite immediately.** Gating on `isSignedIn()` assumed a
  disabled account holds no token; an already-issued ID token stays
  valid for up to an hour. Rules read `users/{uid}.banned` — the field
  `setUserBan` already wrote, not self-writable — so a ban applies on
  the next request. `setUserBan` also revokes refresh tokens now.
- **Email verification, confirmed and documented.** Sending was already
  gated on `isVerified()`; the first report simply never said so, and it
  had no test. Reading stays open to unverified accounts, and reporting
  was *ungated* to match the existing policy, which puts safety actions
  beside blocking rather than beside publishing.
- **The manual `globalChat/main` step was never real.** Firestore
  addresses a subcollection independently of its parent. Dependency
  removed, proven by a test that asserts the parent is absent while the
  whole suite reads and writes the channel.
- **Reports hardened**: deterministic id (uniqueness with no counter and
  nothing to race), target-must-exist, owner-must-match, reason enum,
  bounded note, no workflow fields on create, 30s / 20-per-window
  limits — and a real reason picker in the UI, which previously sent
  `other` for everything.
- **Two-tier send limit**: the 3s floor plus 200 per fixed one-hour
  window. Named *fixed*, not rolling, because that is what it is —
  straddling a boundary allows 400 across two adjacent hours.
- **The audit trigger is idempotent** (entry id from the CloudEvent id)
  and now has seven tests plus a separate emulator smoke test proving
  the binding delivers.
- **Blocking is described accurately** — a UI filter over public
  content, not a read boundary — and the panel holds its first paint
  until the block list resolves so nothing flashes.

## A real bug the new tests caught

The Global message menu is hover-revealed. Opening its popup moves the
pointer onto the overlay, which fired the row's `MouseRegion.onExit`,
unmounted the `PopupMenuButton` — and `PopupMenuButton` silently drops
`onSelected` when its State is gone. **Report and Delete did nothing at
all in the running app.** The row now tracks the open menu and keeps the
button mounted.

## Final verification

`flutter analyze` clean · **187 Flutter tests** · **159 Firestore rules
tests** · **7 Functions tests** + the binding smoke test (real emulator,
one deterministic audit document) · Functions syntax clean ·
`flutter build web --release` succeeded.
