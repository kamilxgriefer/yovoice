# 2026-09-24/25 — Velvet Mallet sounds, 3.0.0 web release, website sign-in

Cloud session "250 dolarów kredytu" (Claude Code on the web). Work spanned
this repository and `kamilxgriefer/yovoice-website`. Everything below is
committed and pushed; nothing is left in a working tree. On 2026-09-25 the
owner moved further work to the "YO Voice testowa aktualizacja" chat; this
log is the handoff, and **Open** is where that chat starts.

## Shipped

### App (`kamilxgriefer/yovoice`, `main`)

| Commit | What |
| --- | --- |
| `32c9dd9` | Velvet Mallet v6 product-sound pack replaces Prism Halo v5 (ADR-210). |
| `36d0bf0` | Roadmap: 3.0.0 web deploy recorded. |
| `738ecc4` | Version `3.0.0+35` + release notes (en/pl) in the Roadmap. |

- **Sounds:** the owner chose pack B "Velvet Mallet" (felt-mallet tones, no
  voice layer) from three candidates. Two review rounds fixed phone-speaker
  presence, mute/unmute legibility, calls that opened with the message cue,
  a sparse incoming ring and a left-leaning stereo image.
  `tool/generate_ui_sounds.py` is still the only authoring source (assets in
  `assets/audio/ui/v6`). Native push files keep their names and Android
  channel ids; only their bytes changed. No Functions change or deploy.
- **Checks before push:** generator `--check` byte-identical on Python
  3.10–3.13, `flutter analyze` clean, full `flutter test` 5319/5319. CI on
  `32c9dd9` was green.
- **Web release:** the owner approved deploying 3.0.0 to the web. The
  `workflow_dispatch` Hosting run 36038221140 (`deploy_hosting: true`,
  `main @ 32c9dd9`) succeeded, and the owner confirmed that app.yovoice.app
  works.

### Website (`kamilxgriefer/yovoice-website`, `main`, auto-deployed by Vercel)

| Commit | What |
| --- | --- |
| `b78ba45` | `/login` and `/register` share an animated surface: a large title (one size and weight for every letter), a stylised waveform, a Log in / Create account switch, and form rows that fold without jumping. |
| `00f8148` | Continue with Google / Apple on both pages, with the Apple availability probe from the app, profile bootstrap and the TOTP step. |
| `0090580` | OAuth handler domain moved to `<projectId>.firebaseapp.com`; accessibility and `/account/security` fixes; more tests. |
| `107bb00` | Release hardening: Apple re-check, web-storage error, redirect normalisation, security notes. |

- **Why the domain moved:** `auth.yovoice.app/__/auth/handler` is not a
  registered redirect URI on the Google OAuth client. A live check got
  `redirect_uri_mismatch`, the same failure as the app's old bug in
  `docs/Bugs.md`. `yovoice-ec54a.firebaseapp.com` reaches Google's account
  chooser.
- **Checks:** lint, `tsc`, 262/262 tests and the build all pass. The owner
  confirmed that real Google and Apple sign-in work on yovoice.app.

## Open

1. **Store build 35:** the owner builds and uploads it (iOS needs a Mac with
   Xcode; the Android upload keystore is not in the repo). Proposed but not
   started: a GitHub Actions release workflow (Android on Linux, iOS on a
   macOS runner) using owner-added secrets, so later releases can be
   triggered from a session.
2. **Device checks (ADR-210, UNVERIFIED):** on a phone upgraded from build
   34, send one backgrounded push per Android channel (message, social,
   achievement, alert, call) and one iOS push. If an old sound plays, the fix
   is new resource names and channel ids in Flutter, `push_payload.js` and
   the manifest, plus a Functions deploy.
3. **Pre-registered account takeover (pre-existing on the whole platform):**
   a password pre-registrant keeps a working refresh token after the owner
   signs in with Google or Apple, and the token becomes `email_verified`.
   This was reproduced in the Auth emulator. A server-side fix is proposed
   as a separate task: a `beforeUserSignedIn` function that revokes tokens,
   or a TTL for unverified password accounts. See the website's
   `docs/security/security-notes.md`.
4. **Website input overflow (pre-existing):** at very large browser font
   sizes, auth inputs overflow on phones on every auth page. Spun off as a
   separate task.
5. **Minor website review follow-ups:** the provider-only email-change
   support runbook; a CSP reporting endpoint before the CSP goes enforcing;
   the double navigation after a password sign-in on `/login`.
6. **Flutter login screen:** unchanged. The owner considered moving the
   website's animated switch into the app, but it was not requested.

## Dropped by the owner

- Landing-page redesign concept ("tacky"). Nothing was committed.
- Generative "code music" for the login screen ("tacky"). It only ever
  existed in the session scratchpad.
- Sound pack A "Vox".

## Environment notes

- The cloud environment's egress proxy blocks yovoice.app, app.yovoice.app,
  auth.yovoice.app, yovoice-ec54a.firebaseapp.com, apis.google.com,
  www.gstatic.com and appleid.apple.com. Production pages and real OAuth
  popups cannot be opened from a session until the owner widens Network
  access in the environment settings.
- Chromium in the container distrusts the proxy's CA. Playwright needs
  `ignoreHTTPSErrors: true` for requests through the proxy.
