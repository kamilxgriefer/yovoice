# Architecture

Ground truth as of the "Turn Settings, Awards and Creator Studio into real
screens" milestone (commit `6cfd208`). If this drifts from the code, trust
the code and fix this file.

## Two repos, one Firebase project

```
yovoice              → this repo: the Flutter app (mobile + web + desktop)
yovoice-website       → /Users/kamiljaguszewski/yovoice-website, Next.js 16 +
                        React 19 + Tailwind, deployed on Vercel — marketing
                        site, auth, and account pages. Separate deployable,
                        not embedded in this app.
```

Both share Firebase project **`yovoice-ec54a`** — one account, one Auth
domain (`auth.yovoice.app`), one Firestore database, one set of Cloud
Functions. Domain layout:

```
yovoice.app            → Vercel (yovoice-website) — public marketing site
auth.yovoice.app        → Firebase Hosting — shared Auth domain
app.yovoice.app          → Firebase Hosting — the Flutter web build
```

`yovoice-website`'s `NEXT_PUBLIC_APP_URL` env var is the toggle between the
Flutter web app's current URL and `app.yovoice.app` once DNS for that
subdomain is live — see that repo's own docs for current status.

## Flutter app

- **Language/framework**: Dart, Flutter, Material 3.
- **State management**: `flutter_riverpod` + `riverpod_generator` are
  dependencies, but most existing screens use plain `StatefulWidget` +
  `StreamBuilder` over Firestore streams rather than Riverpod providers —
  Riverpod is available, not yet the dominant pattern everywhere.
- **Structure**: feature-based, under `lib/features/<feature>/`, each
  typically split into `data/` (models + services) and
  `presentation/screens|widgets/`. Current feature modules:
  `achievements`, `auth`, `calls`, `chats`, `clubs`, `creator`, `discover`,
  `friends`, `home`, `messages`, `moments`, `notifications`, `profile`,
  `rooms`, `settings`.
- **Theme system**: `lib/core/theme/` (`AppColors`, `AppTypography`,
  `AppSpacing`, `AppRadius`, `AppGradients`, `AppTheme`) and
  `lib/shared/widgets/` (`YoButton`, `YoCard`, `YoTextField`, `YoAvatar`,
  `YoBadge`, plus `lib/shared/widgets/states/` — `YoLoadingIndicator`,
  `YoEmptyState`, `YoErrorState`) exist as the intended shared design
  system. **Most screens don't use it yet** — they use consistent-but-inline
  hex color constants (background `0xFF080711`/`0xFF09050F`, accent purple
  `0xFFB348FF`/`0xFF9D20FF` family, etc.) established by convention rather
  than by importing the theme files. Migrating screens onto the shared
  system is tracked, not yet done — see `Roadmap.md`.
- **Voice**: `livekit_client`, connecting to
  `wss://yovoice-3f7j9fb7.livekit.cloud`. Token minting goes through the
  `createLiveKitToken` Cloud Function, never client-side.
- **Real device permissions**: `permission_handler` — used for real
  microphone/camera/notification permission status (Settings screen,
  voice call setup), not simulated.
- **Firebase App Check**: integrated client-side
  (`AndroidDebugProvider`/`AppleDebugProvider` in debug,
  `AndroidPlayIntegrityProvider`/`AppleAppAttestWithDeviceCheckFallbackProvider`
  in release). `enforceAppCheck` on Cloud Functions is deliberately still
  `false` — see `Decisions.md`.

## Firebase backend

- **Project**: `yovoice-ec54a`. Firestore region `europe-west4`. Cloud
  Functions region `europe-west1`.
- **Auth**: Firebase Authentication (email/password + Google Sign-In),
  shared across the Flutter app and the website via `auth.yovoice.app`.
  `email_verified` is used as a real Firestore-rules/Cloud-Functions gate
  for outbound/content-creation actions, not just a UI banner.
- **Firestore collections** (top-level, from `firestore.rules`):
  `users/{userId}` (with subcollections `friendRequests`,
  `sentFriendRequests`, `friends`, `blocked`, `following`, `followers`,
  `clubs`, `notifications`, `fcmTokens`), `conversations/{id}` (+
  `messages`), `clubs/{clubId}` (+ `members`, `invites`, `channels` →
  `messages`), `rooms/{roomId}` (+ `participants`, `roomMembers`,
  `messages`, `handRequests`), `voiceMoments/{momentId}` (+ `likes`,
  `comments`).
- **Why `roomMembers` and not `members` under `rooms/`**: see
  `Decisions.md` — a real bug, not a style choice.
- **`unlockedTitleTimestamps`** on `users/{userId}`: a map of achievement
  id → server timestamp, written by `AchievementService` whenever a title
  is newly unlocked. Exists specifically so the Awards screen's "recent
  unlocks" feed is real data, not inferred/guessed — see `Decisions.md`.
- **Cloud Functions** (`functions/index.js`, Node, region
  `europe-west1`), grouped:
  - Admin: `bootstrapSuperAdmin`, `assignUserRole`, `getUserRole`,
    `listAdminUsers`, `setUserBan`, `getAdminDashboard`,
    `listAdminRooms`/`getAdminRoom`/`setRoomModerationStatus`/
    `forceEndRoom`/`removeRoomParticipant`/`setParticipantMute`/
    `adminDeleteRoom`, `listAdminClubs`/`getAdminClub`/
    `setClubModerationStatus`/`removeClubMember`/`setClubMemberBan`/
    `transferClubOwnership`/`adminDeleteClub`,
    `listAdminAuditLogs`/`getAdminAuditLog`/`getAuditLogFilters`.
  - LiveKit: `createLiveKitToken`.
  - Friends: `getMutualFriends`, `getFriendSuggestions`.
  - Clubs: `transferClubOwnershipSelf`.
  - Notifications: `onNotificationCreated` (Firestore trigger → push via
    FCM, respects per-type user preferences).
- **Email delivery**: Resend SMTP (not Firebase's default sender — the
  default never reliably delivered). SMTP username must stay literally
  `"resend"`. `ActionCodeSettings` used for verify/reset links; Firebase's
  hosted action page is intentionally still used for both flows (not a
  custom `handleCodeInApp` deep-link flow).
- **CI/CD**: `.github/workflows/firebase-hosting-merge.yml` deploys
  **Hosting only** on push to `main`. Firestore rules/indexes and Cloud
  Functions are deployed manually (`firebase deploy --only
  firestore:rules,firestore:indexes` / `--only functions`) — no automatic
  race between the two deploy paths.

## Third-party services

- **LiveKit Cloud** — voice room infrastructure.
- **Resend** — transactional email (verification, password reset), via
  Firebase Auth's custom SMTP settings.
- **Vercel** — hosts `yovoice-website`.

## Testing

- `firestore-tests/` — a Node test suite against the Firestore emulator,
  covering security rules. Always run against a real, freshly-started
  emulator before trusting it — see `Decisions.md` for why a passing suite
  once still shipped a broken `collectionGroup()` query.
- `flutter analyze` — the baseline gate for all Dart changes. Should be
  zero issues before calling Flutter work done.
