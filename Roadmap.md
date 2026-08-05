# Roadmap

Update this file whenever a feature ships — move it into **Done**, note the
commit. This is a working backlog, not a promise to users.

## Done

- Voice Rooms — broadcast, podcast, and community rooms; host/speaker/
  listener roles; hand-raise; moderation; live participant management.
- Clubs — channels (chat + voice), member roles, invites, ownership
  transfer (`2c27c6e`).
- Friends system — requests, blocking, mutual friends, suggestions
  (`2abda0a`).
- Direct messages + club channel chat.
- Voice Moments — recorded audio posts, likes, comments, voice replies.
- Achievements/Awards — full 100-title catalog; Level/XP header, category
  filters, and a real (not fabricated) "recent unlocks" feed backed by
  per-achievement unlock timestamps (`6cfd208`).
- Creator Studio — real dashboard over owned rooms/clubs/Voice Moments with
  working quick actions (`6cfd208`).
- Settings — full account/privacy/security/notifications/permissions/
  storage/legal/danger-zone screen, backed by real Firebase Auth,
  `permission_handler`, and image-cache stats (`6cfd208`).
- Notifications — in-app center + deep-link routing (`a4c78c6`), triggered
  from real friend/follow/club/room/message events (`1760a6f`), preferences
  screen (`467b6c8`).
- Email verification flow (Flutter) — full journey, gates outbound/
  content-creation actions on `email_verified` (`a21d00d`, `04882cc`),
  `ActionCodeSettings` wired into password reset too (`14cc7f7`).
- Email deliverability fixed — moved off Firebase's default sender to
  Resend SMTP (see `Decisions.md`).
- Firebase App Check — client-side integration (not yet enforced).
- Two production-breaking `collectionGroup()` query bugs found and fixed
  (`watchMyCommunities`, `watchMyClubInvites`) — see `Decisions.md`.
- `yovoice-website` — Firebase Auth wired in (login/register/forgot-
  password/verify-email), account section, SEO/metadata foundation,
  full design-system rebuild (pill buttons, glass panels, reusable
  `src/components/ui/` library), 15 new marketing pages.

## In Progress

- **App-wide theme migration** — `AppColors`/`AppTypography`/shared
  `Yo*` widgets exist (`lib/core/theme/`, `lib/shared/widgets/`) but most
  screens still use their own consistent inline hex constants instead of
  importing them. Migration is happening screen-by-screen, tracked as
  internal tasks (foundation done; per-feature-area passes: home/friends/
  notifications/messages, discover/clubs/profile/achievements, auth
  screens, rooms feature, messages/moments/notification-prefs, final
  consistency pass). Not urgent — the inline convention is visually
  consistent even where it doesn't share code — but should finish before
  it drifts further.
- **`app.yovoice.app` DNS** — Firebase Hosting custom domain is configured
  and waiting on one CNAME record on Cloudflare (only the domain owner can
  add it). Once live: flip `NEXT_PUBLIC_APP_URL` in the website and
  redeploy.

## Planned / Backlog

Roughly in priority order — re-prioritize freely, this isn't a queue:

1. **Verify no orphaned `rooms/{roomId}/members` documents** exist in
   production from before the `roomMembers` rename (no reliable way to
   check without `gcloud`/Admin SDK credentials — see `Decisions.md`).
2. **Firebase App Check enforcement** (`enforceAppCheck: true`) — client
   integration is done and verified; flipping it needs a token-delivery
   monitoring period first.
3. **Creator analytics** — real audience/engagement insights. Currently an
   honest "Coming soon" card in Creator Studio, no backend at all yet.
4. **Monetization** — tipping/subscriptions for creators. Not started.
5. **Audience growth tracking** — needs a real time-series data model
   (follower count over time); currently there's only a point-in-time
   `followerCount`.
6. **Two-factor authentication** — Settings has a visible, honestly-
   disabled "Coming soon" entry; no backend support exists yet.
7. **Profile visibility / message-privacy controls** — same treatment:
   visible, disabled, no backend field on `UserProfile` yet.
8. **Multi-device session management** — Settings shows only "this
   device"; there's no session registry to list/revoke other devices.
9. **Self-serve account deletion** — currently routes to a support-email
   flow (real, not fake) rather than deleting anything itself, since a full
   deletion (Auth + Firestore + Storage cleanup) needs a dedicated Cloud
   Function, not a client-side stub.
10. **App language switcher** — app is English-only; no i18n system wired
    up yet, despite per-user spoken/native language fields already existing
    on the profile (those are unrelated — that's *content* language, not
    *UI* language).
11. **Value-level counter validation** via a Cloud Function trigger for
    room/club counters — flagged as bigger/riskier than it looks (touches
    many call sites in `room_service.dart`).
12. **Consolidate the two parallel hand-raise implementations** — both
    still exist, unconsolidated.
13. **App-store distribution** — no published iOS/Android builds yet; the
    website's download center is honest about this ("coming soon" +
    GitHub link) rather than linking to store pages that don't exist.
14. **Windows/macOS installers** — same situation as above.

## Explicitly not planned right now

Don't build these speculatively — revisit only if the product direction
changes:
- Text-first chat as a primary surface (voice-first is the point).
- A custom (non-Firebase) backend.
