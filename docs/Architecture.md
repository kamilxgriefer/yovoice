# Architecture

High-level map of how the system fits together. For detail, follow the
links — this file stays deliberately short so it doesn't drift as fast as
the specifics do.

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

## Layers, and where to read about each one

```
┌─────────────────────────────┐   ┌─────────────────────────────┐
│   yovoice (this repo)        │   │   yovoice-website             │
│   Flutter — mobile/web/desk. │   │   Next.js — marketing/auth   │
│   see Flutter.md, UI.md      │   │   see that repo's own docs   │
└───────────────┬───────────────┘   └───────────────┬───────────────┘
                │                                     │
                └───────────────┬─────────────────────┘
                                 ▼
                  ┌───────────────────────────────┐
                  │   Firebase (yovoice-ec54a)     │
                  │   Auth, Firestore, Storage,     │
                  │   Hosting, App Check, FCM       │
                  │   see Firebase.md                │
                  └───────────────┬───────────────┘
                                 │
                                 ▼
                  ┌───────────────────────────────┐
                  │   Cloud Functions (Node)         │
                  │   admin/friends/clubs/livekit/    │
                  │   notifications                  │
                  │   see Backend.md                 │
                  └───────────────┬───────────────┘
                                 │
                                 ▼
                       LiveKit Cloud (voice)
```

- **[Flutter.md](Flutter.md)** — app structure, state management, feature
  modules, dev setup and commands.
- **[UI.md](UI.md)** — design system status: Material 3, the theme/shared
  widget system, the inline-hex convention most screens still use, and the
  "Coming soon" pattern.
- **[Firebase.md](Firebase.md)** — Firestore schema/collections, Storage
  rules, Auth setup, App Check, email delivery.
- **[Backend.md](Backend.md)** — the Cloud Functions codebase: what each
  function does, LiveKit token minting, notification triggers.
- **[Features.md](Features.md)** — what's actually built, feature by
  feature.
- **[Decisions.md](Decisions.md)** — why things are the way they are.
- **[Bugs.md](Bugs.md)** — current known issues.

## Third-party services

- **LiveKit Cloud** — voice room infrastructure. See `Backend.md` for how
  tokens are minted.
- **Resend** — transactional email (verification, password reset), via
  Firebase Auth's custom SMTP settings. See `Firebase.md`.
- **Vercel** — hosts `yovoice-website`.

## CI/CD

`.github/workflows/firebase-hosting-merge.yml` deploys **Hosting only** on
push to `main`. Firestore rules/indexes and Cloud Functions are deployed
manually (`firebase deploy --only firestore:rules,firestore:indexes` /
`--only functions`) — no automatic race between the two deploy paths.

## Testing

- `firestore-tests/` — a Node test suite against the Firestore emulator,
  covering security rules. Always run against a real, freshly-started
  emulator before trusting it — see `Decisions.md` for why a passing suite
  once still shipped a broken `collectionGroup()` query.
- `flutter analyze` — the baseline gate for all Dart changes. Should be
  zero issues before calling Flutter work done.
