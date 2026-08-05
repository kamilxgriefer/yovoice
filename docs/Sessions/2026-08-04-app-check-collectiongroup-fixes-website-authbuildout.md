> **Session log — dated 2026-08-04, kept for historical context.** Written
> in the moment as a handoff doc; treat every "current status" claim below
> as true *as of that date*, not now. A lot has shipped since (email
> verification, the notification system, the Settings/Awards/Creator
> Studio rebuild, most of the security-audit fixes). For current state, use
> [docs/Architecture.md](../Architecture.md), [docs/Roadmap.md](../Roadmap.md),
> and [docs/Bugs.md](../Bugs.md) instead — moved here during the
> documentation audit, content otherwise unchanged.

# YoVoice — Project Status

Rewritten from scratch at the end of a long autonomous session covering three
things back-to-back: (1) finishing Firebase App Check client integration,
(2) finding and fixing two real, previously-unnoticed `collectionGroup()`
query bugs, and (3) building out `yovoice-website` (the Next.js marketing
site, separate repo at `/Users/kamiljaguszewski/yovoice-website`) into a
working Firebase-Auth-backed site with an account section, connected to this
Flutter app. The previous version of this file (covering an earlier security
audit pass) is superseded — everything it described is still true and still
deployed, just no longer the frontier of what's happening.

**Nothing is currently broken.** One real blocker exists and is explicitly
called out in section 9 — it needs a DNS change only the user can make.

---

## 1. What has been completed this session

### A. Firebase App Check — client integration (audit item #12)

- `firebase_app_check: ^0.4.6` added to `pubspec.yaml`; `lib/main.dart`
  activates it with `AndroidDebugProvider`/`AppleDebugProvider` in debug
  builds, `AndroidPlayIntegrityProvider`/`AppleAppAttestWithDeviceCheckFallbackProvider`
  in release.
- Fixed an iOS build blocker hit along the way: `firebase_core` (bumped to
  4.13.0 by adding App Check) needed `firebase-ios-sdk` 12.17.0, but the
  locked `firebase_storage` 13.4.5 needed 12.15.0. `flutter pub upgrade`
  moved `firebase_storage` to 13.4.6, resolving both.
- The **Firebase App Check API itself was disabled** in Google Cloud Console
  for this project — not just unconfigured client-side. Enabled it.
- Captured the debug token from a live simulator run
  (`3868E14D-C821-437F-93AE-D27A8C504AA4`) via `xcrun simctl spawn ... log
  stream`, registered it in Firebase Console → App Check → Manage debug
  tokens, then **verified live** by relaunching the app and confirming the
  token-exchange 403 error was gone.
- `enforceAppCheck` on Cloud Functions is **still `false`** — deliberately.
  This only starts attaching tokens to requests. See section 9 for what
  flipping it actually requires.

### B. Two real `collectionGroup()` query bugs, found and fixed

Both `RoomService.watchMyCommunities()` and `ClubService.watchMyClubInvites()`
have been broken since they were written — "My Communities" and club invite
notifications never worked, for anyone, ever. Found while double-checking a
previous session's claimed fix for the first one (it hadn't actually worked —
see below).

**Root cause** (confirmed against the Firestore emulator, not assumed): a
nested `match /parent/{id}/collection/{doc}` rule only ever authorizes
reads/writes scoped to one specific parent document. It does **not**
authorize an actual `collectionGroup()` query, which scans that collection
name across every parent at once — Firestore rejects those outright as
`permission-denied` unless a separate, **top-level**
`match /{path=**}/collection/{doc}` rule also exists. Neither query had one.
This is easy to miss because direct `getDoc()`/`getDocs()` calls on a
fully-specified path don't exercise this code path at all — a test suite that
only ever does that (which is exactly what `firestore-tests/` did before this
session) will stay green while the real feature is completely broken.

This also means a previous session's fix attempt for `watchMyCommunities()`
— adding `|| resource.data.userId == request.auth.uid` to
`clubs/{clubId}/members`'s read rule, reasoning that Firestore's docs suggest
an OR'd provable clause satisfies collection-group provability — **never
actually worked**. Verified directly: combining an `exists()`-based clause
with a provable one via `||` does not satisfy Firestore's real provability
check, at least not as implemented by the emulator. That workaround has been
removed/simplified; the comment explaining why is in `firestore.rules`.

**Fixes:**
- Renamed `rooms/{roomId}/members` → `rooms/{roomId}/roomMembers` so it no
  longer shares a collection-group name with `clubs/{clubId}/members` (which
  legitimately needs `exists()` for its own non-collectionGroup roster
  browsing, and would otherwise poison the whole group for any query).
  Updated all 5 call sites in `room_service.dart` and the `isRoomMember()`
  rules function accordingly. `clubs/{clubId}/members` itself was **not**
  renamed — it's never queried via `collectionGroup()`, and one of the 6
  `collection('members')` call sites in `room_service.dart` (the club-lounge
  entry check, line ~470) is correctly a `clubs/{clubId}/members` read and
  was left alone.
- Added two top-level wildcard rules, scoped to exactly what the two real
  queries need (read your own record, nothing more):
  ```
  match /{path=**}/roomMembers/{memberId} {
    allow read: if isSignedIn() && resource.data.userId == request.auth.uid;
  }
  match /{path=**}/invites/{inviteId} {
    allow read: if isSignedIn() && resource.data.inviteeId == request.auth.uid;
  }
  ```
- Added `firestore.indexes.json` (**didn't exist before this session at
  all** — no collection-group index configuration had ever been deployed)
  with a collection-group field override for `roomMembers.userId`.
  `firebase.json` now points `firestore.indexes` at it.
- Added two real `collectionGroup()` regression tests (plus one attack-case
  test) to `firestore-tests/rules.test.js` — suite is now 43 checks, up from
  40, all passing on a freshly-started emulator.
- Deployed to production: `firebase deploy --only firestore:rules,firestore:indexes`.

**Known gap, explicitly not resolved:** if any real `rooms/{roomId}/members`
documents already existed in production before this rename, they are now
invisible to the app (the client reads/writes `roomMembers` now). No reliable
way to check production document counts was available in this session (no
`gcloud`, Application Default Credentials weren't set up for `firebase-admin`,
and the Firebase Console's Firestore data browser was too unreliable via
browser automation to check manually — see section 10). **Worth verifying
before assuming this is a non-issue** — check the Firestore Console's
`rooms/*/members` collections directly, or query the same via
`firebase-admin` with a real service account key.

### C. `yovoice-website` — full auth + account section + SEO build-out

Separate repo, `/Users/kamiljaguszewski/yovoice-website`, Next.js 16 +
React 19 + Tailwind, deployed on Vercel (`yo-voice/yovoice-website`, linked
via `vercel link` this session; auto-deploys on push to `main`). This repo
had a lot of scaffolding (empty files with the right names) but almost
nothing was actually implemented before this session.

**Firebase Authentication** (shares the `yovoice-ec54a` project and the
`auth.yovoice.app` custom auth domain with this Flutter app — one account
works everywhere):
- `src/lib/firebase/config.ts`, `src/providers/auth-provider.tsx`,
  `src/hooks/use-auth.ts`, `src/hooks/use-require-auth.ts` — real
  implementations, were empty stubs before.
- Login, Register, Forgot Password, Verify Email — all functional pages
  backed by real Firebase Auth calls (`signInWithEmailAndPassword`,
  `createUserWithEmailAndPassword` + `sendEmailVerification`,
  `sendPasswordResetEmail`, `resendVerificationEmail`).
- Security page: change password and change email, both requiring
  re-authentication first (`reauthenticateWithCredential`).
- `resolveAuthRedirect()` sends signed-in users to `NEXT_PUBLIC_APP_URL`
  (defaults to `https://yovoice-ec54a.web.app`, meant to become
  `https://app.yovoice.app` once DNS exists) by default, or to an internal
  path via `?redirect=/some/path` — used by the download flow.
- Header shows "Log in" for anonymous visitors, "Account" + "Open App" for
  signed-in users — anonymous visitors otherwise see the unchanged marketing
  site, nothing forces them anywhere.

**Account section** (`/account/*`, all gated by `useRequireAuth()`):
Profile (display name), Security (as above), Devices & Sessions (current
session only — see limitations), Notifications (honest placeholder, no
backend schema for it yet), Downloads (reuses the same platform selector as
the public download center).

**Download center** (`/download`, gated to signed-in users): mobile shows
"coming soon" + a link to the GitHub repo; Windows/macOS show "installer not
published yet" + a link to GitHub Releases; Web links straight to the app.
Deliberately does **not** fabricate app-store/installer URLs that don't
exist.

**SEO/metadata**: `robots.ts`, `sitemap.ts` (only lists genuinely public,
non-gated routes), `manifest.ts` + real PNG icons generated from the brand
logo via `sips`, a dynamically-generated OpenGraph image
(`opengraph-image.tsx`, via `next/og`), Twitter card metadata. Fixed a
pre-existing duplicate `id="community"` between the hero section and the
product-details section that broke the "Community" nav anchor link.

Full details, env var docs, and known limitations are in
`yovoice-website/README.md` — kept up to date, don't duplicate it here.

**Verified live** end-to-end: registered a real test account through the
running dev server, confirmed the Firebase Auth network calls, confirmed the
redirect landed on the actual Flutter web app
(`https://yovoice-ec54a.web.app`) and that app initialized Firebase
correctly. Logged back in with `?redirect=/account/profile`, confirmed the
internal-path redirect stayed on-site, confirmed the profile page showed the
right data, confirmed the verify-email banner appeared (email genuinely
wasn't verified). Test account (`claude-website-test@yovoice.app`) is
**still in the production Firebase Auth user list** — attempted to delete it
via the Console UI but hit repeated script-injection timeouts on that
specific page; low priority (one obviously-fake test account), but worth a
5-second manual delete next time someone's in Authentication → Users.

### D. `app.yovoice.app` — everything possible without DNS access

- Added `app.yovoice.app` as a custom domain on the `yovoice-ec54a` Firebase
  Hosting site. Firebase's setup flow gave the exact DNS record needed:
  ```
  CNAME  app.yovoice.app  →  yovoice-ec54a.web.app
  ```
  (Same pattern already working for `auth.yovoice.app`.) This is now
  registered on the Firebase side and waiting on that DNS record — see
  section 9.
- The website's `NEXT_PUBLIC_APP_URL` env var is exactly the toggle for this:
  currently `https://yovoice-ec54a.web.app`, flip to `https://app.yovoice.app`
  once the DNS record is live and Firebase finishes domain verification (can
  take a while after the record propagates — check the same "Edit domain"
  panel in Firebase Console → Hosting).
- Confirmed via `dig` that `yovoice.app`'s DNS is managed on **Cloudflare**
  (nameservers `louis.ns.cloudflare.com` / `heidi.ns.cloudflare.com`), and
  that the root domain + `www` currently point at Vercel's IPs. No Cloudflare
  access exists in this session — this is genuinely something only the user
  (or whoever has Cloudflare access) can do.
- Also discovered: Firebase Hosting's domain list shows `yovoice.app` itself
  as a "Connected" custom domain, left over from — presumably — before the
  marketing site moved to Vercel. DNS no longer points there (confirmed via
  `dig`), so this is just stale metadata on Firebase's side, not receiving
  real traffic. Harmless, but worth knowing about if it's ever confusing in
  the Console.

---

## 2. Files created (this session, both repos)

```
# yovoice (Flutter)
firestore.indexes.json

# yovoice-website
.env.example
src/app/(auth)/layout.tsx
src/app/(auth)/register/page.tsx
src/app/(auth)/forgot-password/page.tsx
src/app/(auth)/verify-email/page.tsx
src/app/(account)/account/layout.tsx
src/app/(account)/account/profile/page.tsx
src/app/(account)/account/security/page.tsx
src/app/(account)/account/devices/page.tsx
src/app/(account)/account/notifications/page.tsx
src/app/(account)/account/downloads/page.tsx
src/app/(marketing)/download/page.tsx
src/app/manifest.ts
src/app/robots.ts
src/app/sitemap.ts
src/app/opengraph-image.tsx
src/app/icon.png
src/app/apple-icon.png
src/lib/firebase/config.ts
src/lib/auth/auth-errors.ts
src/components/auth/forgot-password-form.tsx
src/components/auth/verify-email-banner.tsx
src/components/download/platform-selector.tsx
src/hooks/use-require-auth.ts
public/icons/icon-192.png
public/icons/icon-512.png
```

## 3. Files modified (this session, both repos)

```
# yovoice (Flutter)
lib/main.dart                                        # App Check activation
pubspec.yaml, pubspec.lock                            # firebase_app_check + storage bump
ios/Podfile.lock, ios/Runner.xcodeproj/**, ios/Runner.xcworkspace/**  # SPM resolution
macos/Flutter/GeneratedPluginRegistrant.swift
windows/flutter/generated_plugin_registrant.cc, generated_plugins.cmake
firestore.rules                                       # roomMembers rename + wildcard rules
firebase.json                                          # points to firestore.indexes.json
lib/features/rooms/data/services/room_service.dart     # 5 collection('members') -> 'roomMembers'
firestore-tests/rules.test.js                           # +3 collectionGroup tests
README.md                                               # +Development Setup, +App Check, +rules testing
PROJECT_STATUS.md                                       # this file

# yovoice-website
src/app/layout.tsx                                      # AuthProvider, OG/Twitter/icons metadata
src/hooks/use-auth.ts
src/providers/auth-provider.tsx
src/lib/auth/auth-redirect.ts
src/components/auth/login-form.tsx
src/components/auth/register-form.tsx
src/components/layout/site-header.tsx                   # auth-aware Log in/Account/Open App
src/components/layout/site-footer.tsx                    # sizes= fix
src/components/hero/hero-section.tsx                      # id="community" collision fix, sizes= fix
src/components/sections/download-section.tsx              # auth-aware routing
src/types/user.ts
.gitignore                                                # !.env.example exception
README.md                                                 # +Getting Started, +env vars, +deployment
```

## 4. Git history (this session, chronological)

**`yovoice`** (`kamilxgriefer/yovoice`, all on `main`, all pushed):
```
e620582  Fix two broken collectionGroup() queries: watchMyCommunities and watchMyClubInvites
0e18d24  Integrate Firebase App Check (client side, not yet enforced)
```
(plus this doc's commit, made after — check `git log --oneline -5` to
reconfirm hashes, don't trust anything transcribed here blindly)

**`yovoice-website`** (`kamilxgriefer/yovoice-website`, all on `main`, all
pushed):
```
b016577  Wire Firebase Authentication and complete SEO foundation
```
(plus a follow-up commit for the account section / README updates — check
`git log --oneline -5` in that repo too)

Both repos' working trees should be clean after this session's final commits
— reconfirm with `git status` before starting new work.

---

## 5. Current architecture

### `yovoice` (Flutter)
Unchanged from the previous version of this doc except: App Check is now
integrated client-side (not enforced), and `rooms/{roomId}/members` is now
`rooms/{roomId}/roomMembers`. Firebase project `yovoice-ec54a`, Firestore
`europe-west4`, Functions `europe-west1`. LiveKit at
`wss://yovoice-3f7j9fb7.livekit.cloud`. CI/CD
(`.github/workflows/firebase-hosting-merge.yml`) deploys **Hosting only** on
push to `main` — confirmed again this session, still true, still no race
risk with manual rules/functions deploys.

**The two parallel hand-raise implementations noted in the previous version
of this doc still both exist**, unconsolidated — not touched this session.

### `yovoice-website` (Next.js, new territory this session)
```
yovoice.app          → Vercel (this repo) — marketing site, public
auth.yovoice.app      → Firebase Hosting (yovoice-ec54a) — shared Auth domain, already live
app.yovoice.app        → Firebase Hosting (yovoice-ec54a) — the actual Flutter web app,
                          custom domain added in Firebase, DNS not yet pointed (section 9)
```
One Firebase project (`yovoice-ec54a`) backs both apps. The website is a
*separate* deployable from the Flutter web build — it doesn't embed or
replace it, it's the marketing/auth/account layer in front of it, matching
the Discord (`discord.com` + `discord.com/app`) pattern the user described.

---

## 6. Remaining issues

### 🔴 Blocking (needs the user / DNS access — see section 9)
- `app.yovoice.app` DNS record not added yet. Everything else for this is
  ready and waiting.

### 🟡 Deliberately deferred
- **App Check enforcement** (`enforceAppCheck: true`) — client integration
  is done and verified, but flipping enforcement needs a monitoring period
  first (see section 9 for the reasoning).
- **Value-level validation for room/club counters** via a Cloud Function
  trigger — unchanged from the previous version of this doc, still not
  started, still flagged as bigger/riskier than it looks (touches many call
  sites in `room_service.dart`).
- **Consolidate the two hand-raise implementations** — unchanged, still not
  started.
- **`rooms/{roomId}/members` → `roomMembers` migration** — see section 1B's
  "known gap." Not started because production document counts couldn't be
  checked this session.
- **Website: Notifications page, multi-device session management, mobile
  store links** — all explicitly placeholder/honest-about-limitations
  rather than built out, since none have real backend support yet. Full
  reasoning in `yovoice-website/README.md`'s "Known Limitations" section.
- **Website: `npm audit`** reports 3 high-severity advisories, all
  transitive (bundled inside `next`'s own dependencies). `npm audit fix` not
  run — should be verified against a full rebuild before applying.
- **One leftover test account** in production Firebase Auth
  (`claude-website-test@yovoice.app`) — harmless, just needs a manual
  delete via Console → Authentication → Users.

---

## 7. Important design decisions

- **`rooms/{roomId}/members` renamed to `roomMembers` rather than trying to
  make the existing name work with a smarter rule.** The alternative (a
  single top-level wildcard rule covering both `rooms/*/members` and
  `clubs/*/members` under the same collection name) isn't possible without
  either making `clubs/*/members` less permissive than its real
  roster-browsing use case needs, or accepting the original bug. Distinct
  names cleanly separate two collections that only ever happened to share a
  name by coincidence, not by design — `watchMyCommunities()` never
  actually needed club data, it only ever used `roomIds` derived from the
  parent path.
- **Top-level wildcard rules are read-only and scoped to "read your own
  record."** Writes to both `roomMembers` and `invites` still only ever go
  through their nested, parent-scoped rules — the wildcard rules exist
  purely to unblock the two specific `collectionGroup()` queries the app
  actually runs, not as a general-purpose access widening.
- **Website account pages are scoped to what Firebase Auth's client SDK
  actually supports**, deliberately not extended into Firestore-backed
  preferences/session-registry features that would need new schema design
  and — given this project's Firestore rules are already intricate and
  shared with the Flutter app — real care to get right rather than bolt on
  quickly. Better to ship an honest "coming soon" than a UI that doesn't
  persist anything.
- **`NEXT_PUBLIC_APP_URL` as an env var, not a hardcoded domain**,
  specifically so the `app.yovoice.app` DNS blocker doesn't block shipping
  everything else — flipping it later is a one-line env var change, not a
  code change.
- **Git workflow**: push straight to `main`, no PRs, in both repos now —
  same standing preference as before, now applied consistently to
  `yovoice-website` too.
- **Rules changes are always emulator-tested before deploy.** This session
  specifically: don't trust a passing test suite's claim of "collectionGroup
  compatibility" without a real `collectionGroup()` query in the test, not
  just a `getDoc()` on a known path — that distinction is exactly what let
  the original bug ship silently.

---

## 8. Commands needed to continue

```bash
# yovoice (Flutter)
cd /Users/kamiljaguszewski/Documents/GitHub/yovoice
flutter analyze
export PATH="/usr/local/opt/openjdk/bin:$PATH"   # needed before any firebase emulators command
firebase emulators:start --only firestore --project yovoice-ec54a
cd firestore-tests && npm test                    # 43 checks, all should pass

# yovoice-website
cd /Users/kamiljaguszewski/yovoice-website
npm run lint && npm run build
vercel env ls                                       # confirm the 8 NEXT_PUBLIC_* vars are still set
                                                      # across production/preview/development
```

Firebase CLI logged in as `kamil.piotr.jaguszewski@gmail.com`. Vercel CLI
authenticated as `kamilxgriefer` (confirmed working this session via
`vercel whoami`, despite no prior local `.vercel` link existing at session
start). Git push works via `osxkeychain` for both repos.

---

## 9. Exact next task

**The only real blocker: add this DNS record on whatever manages
`yovoice.app`'s DNS (Cloudflare, confirmed via `dig`):**

```
Type:  CNAME
Name:  app.yovoice.app
Value: yovoice-ec54a.web.app
```

Once that's live and Firebase finishes verifying it (check Firebase Console
→ Hosting → the `app.yovoice.app` row, or re-open "Edit domain" from the
custom domains list):
1. Flip `NEXT_PUBLIC_APP_URL` to `https://app.yovoice.app` in
   `yovoice-website/.env.local` and in all three Vercel environments
   (`vercel env rm NEXT_PUBLIC_APP_URL production` then
   `vercel env add ...` again with the new value, same for preview/dev).
2. Redeploy the website (push to `main`, or `vercel --prod`).

**After that, in rough priority order:**
1. Verify whether any pre-existing `rooms/{roomId}/members` documents exist
   in production that the `roomMembers` rename orphaned (section 1B). If any
   do, write and run a one-time copy migration — the rules/code changes are
   already deployed and correct, this is purely a data-migration concern.
2. App Check enforcement (`enforceAppCheck: true`) — monitor real token
   delivery for a while first (Firebase Console → App Check has request
   metrics), then flip it function-by-function or all at once depending on
   how confident that data makes you.
3. Delete the leftover `claude-website-test@yovoice.app` test account from
   Firebase Authentication.
4. Value-level counter validation, hand-raise consolidation — unchanged
   from before, still lower priority, still bigger than they look.

If the user asks for something else entirely, that takes priority over this
list — it's a backlog, not a queue.

---

## 10. Anything else the next session should know

- **No `gcloud` CLI, no Application Default Credentials set up.**
  `firebase-admin`'s `initializeApp({projectId: ...})` fails without
  explicit credentials in this environment — needed a real service account
  key or `gcloud auth application-default login` (interactive, needs the
  user) to do direct Admin SDK reads/writes against production. Anything
  requiring that this session (checking production doc counts, deleting the
  test Auth user cleanly) had to be worked around or deferred.
- **Firebase Console via `claude-in-chrome` was flaky this session**,
  specifically the Hosting "Manage site" and Authentication "Users" pages —
  repeated `Script injection timed out` errors on clicks/scrolls that
  otherwise worked fine elsewhere in the Console. Opening a fresh tab
  (`tabs_create_mcp`) instead of reusing one that had just timed out
  reliably fixed it. If this recurs, try that first before assuming
  something's actually broken.
- **Vercel CLI works without an explicit login this session** — `vercel
  whoami` succeeded immediately as `kamilxgriefer` despite no local
  `.vercel` config existing at session start, meaning a global Vercel CLI
  session was already authenticated on this Mac from prior use.
- `docs/SECURITY_AUDIT.md` (in the `yovoice` repo) is still the
  authoritative reference for the security work described in the *previous*
  version of this doc — still true, still worth reading before further
  security work, just not the frontier of what's currently happening.
