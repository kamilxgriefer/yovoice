# Dependencies

Why the key third-party pieces were chosen — not an exhaustive mirror of
`pubspec.yaml`/`functions/package.json` (those files are the actual source
of truth for versions; duplicating the full list here would just rot).
This is the reasoning behind the choices that matter, so the next person
evaluating "should we swap X for Y" has the original context instead of
re-deriving it.

## Platform

**Firebase** (Auth, Firestore, Storage, Cloud Functions, Cloud Messaging,
App Check, Hosting) — the entire backend. Chosen because it lets clients
read/write the database directly with Security Rules as the authorization
layer, which is the foundational architectural choice this whole project
is built around — see
[ADR-013](Decisions.md#adr-013-clients-write-firestore-directly-cloud-functions-are-reserved-for-privileged-work).
A custom backend is explicitly not planned (see
[Roadmap.md](Roadmap.md#explicitly-not-planned-right-now)) — that would
mean rebuilding, by hand, most of what Firebase already provides
(real-time sync, offline support, per-document authorization) without a
concrete problem Firebase can't solve.

## Voice

**LiveKit** (`livekit_client` in Flutter, `livekit-server-sdk` in
`functions/`) — WebRTC-based real-time audio infrastructure. The
alternative in this space is usually Agora or building directly on raw
WebRTC. LiveKit was chosen for its open-source server option (not a
requirement for this project's current LiveKit Cloud usage, but a real
exit ramp if ever needed) and a server SDK that made the
permission-scoped-token model in
[Backend.md](Backend.md#livekit-token-minting) straightforward to
implement correctly.

## GIFs

**YO Voice Originals** is the active catalog behind the composer's GIF tab.
Sixteen original 320×200, G-rated animations are generated deterministically
by `tool/generate_yovoice_gifs.py`, committed under
`assets/gifs/yovoice/`, and decoded by Flutter's built-in image support. It
adds no Dart or npm package, no API credential and no third-party request.
See [ADR-172](Decisions.md#adr-172-gifs-are-a-server-proxied-hotlinked-g-only-surface-and-the-composer-grows-one-panel-with-two-tabs).

The provider abstraction still includes **GIPHY** as an optional HTTP adapter
(`functions/media/gif/giphy_provider.js`, Node 22 global `fetch`). It is not
selected by the current production source. Moving to it requires a reviewed
source change, the `GIPHY_API_KEY` secret, a live provider smoke test and the
privacy/attribution rollout below.

The dormant GIPHY adapter was originally chosen over KLIPY (the
Tenor-compatible alternative) because YO Voice is a
consumer social product with a real moderation queue and plausible minor users:
GIPHY's `g` rating is an editorially assigned, per-asset value with a decade of
operational history and a staffed moderation team behind it, its non-English
search relevance matters for a bilingual EN/PL product, and its API is a
contractual product line rather than a free-tier growth channel that can be
withdrawn the way Tenor's was. **KLIPY was not written as a second adapter**,
deliberately: its endpoint and response shapes could not be verified from here,
and a guessed adapter for an unverified API is fabrication, not a fallback. The
seam is what makes it cheap to add — `createGifProvider` in
`functions/media/gif/provider.js` plus one `GIF_PROVIDER` value.

**Dormant external-provider constraints and activation checks.** The bullets
below do not apply to the bundled YO Voice Originals catalog and are not a
claim that all current provider terms are enforced by code.
Account approval, current quotas, attribution and any pingback obligation
must be checked with the provider before activation; the live smoke remains
unrun without an owner-configured key.

- **Attribution is mandatory.** "Powered by GIPHY" is rendered in the picker
  footer wherever results are shown; there is no code path that hides it, and
  it stacks above the rating line rather than truncating on a narrow screen.
  Upgrading to the official logo needs no `pubspec.yaml` change —
  `assets/images/` is already declared.
- **Hotlinking is required and rehosting is forbidden.** We proxy metadata and
  search; the device fetches image bytes from `media.giphy.com` directly. This
  is why there is no Storage object and no egress line for GIFs — and why every
  viewer's IP reaches GIPHY (see [SECURITY.md](SECURITY.md)).
- **The content rating must be set.** `rating=g` is pinned inside the adapter
  and is not a parameter of any callable.
- **Rate limits.** A beta key is heavily capped per hour and per day; a
  production key needs GIPHY app review. **Read the current numbers off the
  developer portal at signup and record them here** — nothing in this repo
  knows them. `DEFAULT_HOURLY_PROVIDER_BUDGET` in
  `functions/media/gif/rate_limit.js` is a deliberately conservative 400/hour
  until somebody does; the shared query cache is what makes a beta key viable
  at all, with a target hit ratio above 80%.
- **Check at signup:** whether an analytics/pingback obligation applies to
  raw-API (non-SDK) integrations. If it does, it is issued **server-side from
  the proxy**, never from the device, so the privacy property survives.

If enabled, the API key lives only in Google Secret Manager
(`GIPHY_API_KEY`, via `defineSecret`) and is read inside a request. It is never
in the client, never in Firestore, never logged.

## State management

**`flutter_riverpod` / `riverpod_generator`** are dependencies, but most
screens use plain `StatefulWidget` + `StreamBuilder` directly over
Firestore streams instead. This isn't an abandoned migration — it reflects
that Firestore's own `Stream` API already provides most of what a state
management library would otherwise be responsible for (reactive updates,
no manual cache invalidation), so Riverpod's marginal value for a typical
CRUD screen in this app is smaller than it would be in an app without a
reactive database underneath it. See [Flutter.md](Flutter.md#state-management)
for when reaching for Riverpod is actually warranted in this codebase
(cross-screen shared state that doesn't map cleanly onto a Firestore
stream — the honest justification, not "it's already a dependency").

## Email

**Resend** (via Firebase Auth's SMTP settings, not a Dart/Node package) —
replaced Firebase's default email sender after confirmed delivery
failures. See [ADR-008](Decisions.md#adr-008-resend-smtp-instead-of-firebases-default-email-sender)
for the full story; the short version is that a general-purpose
transactional-email provider with real deliverability monitoring beat a
platform's bundled default sender that was never built to be a serious
delivery channel.

## Device capabilities

- **`permission_handler`** — real OS-level permission status/requests
  (microphone, camera, notifications), rather than the app guessing or
  assuming a permission state. See
  [ADR-011](Decisions.md#adr-011-permission_handler-for-real-device-permission-status).
- **`url_launcher`** and **`package_info_plus`** — added specifically so
  Settings' About/Legal/Help sections could show a real app version and
  open real external links, instead of static text pretending to be
  interactive. Small, single-purpose additions justified by the
  ["Coming soon" over fabricated data](Decisions.md#adr-012-coming-soon-instead-of-fabricated-data-or-dead-buttons)
  principle — the alternative was either faking these sections or leaving
  them blank, and both were worse than one new dependency each.
- **`image_picker`, `record`, `audioplayers`, `path_provider`** — media
  capture/playback for profile photos, room images, and Voice Moments'
  audio recording pipeline. `path_provider` also supplies the native
  application-support directory for account-isolated offline Voice Moment
  files; `audioplayers` receives the local file path directly so ordinary
  playback does not duplicate the whole file in Dart memory. The same package
  also plays the tiny bundled YO Voice event cues through three lazy channels;
  no player is allocated until a cue is actually requested.
  Web uses the browser's Cache Storage API instead of adding another
  persistence package.

## Local preferences and localization

- **`shared_preferences`** — persists the non-sensitive Appearance and app
  language enum on the current browser/device. These are presentation
  preferences, not account authority, so a Firestore document and cross-device
  synchronization would add latency, privacy surface and schema without a
  product benefit. Unknown or unreadable values fall back to System.
- **`flutter_localizations`** (Flutter SDK) — installs the Material, Widgets
  and Cupertino localization delegates used by framework controls. YO Voice's
  own small delegate currently covers English and a bounded Polish Beta across
  navigation, authentication and Settings. It is infrastructure for gradual
  migration, not a claim that every legacy English literal has been translated.

## Firebase Cloud Messaging / local notifications

**`firebase_messaging` + `flutter_local_notifications`** — push delivery
and in-app notification presentation, backing the notification system
described in [Backend.md](Backend.md#notifications) and
[Features.md](Features.md#notifications).

## Auth

**`google_sign_in`** alongside Firebase's built-in email/password —
Google Sign-In as the low-friction alternative to a new password, using
Firebase Auth's native support rather than a custom OAuth implementation.

## Dev dependencies worth knowing about

- **`firebase_auth_mocks`, `fake_cloud_firestore`, `mock_exceptions`** —
  what makes `test/auth_service_verification_test.dart`'s real unit
  coverage possible without touching live Firebase infrastructure in
  tests. See [TESTING.md](TESTING.md). Any new service-level test should
  reach for these first rather than inventing a different mocking
  approach.
- **`flutter_lints`** — the baseline for `flutter analyze`; see
  `analysis_options.yaml` for the actual configured rule set.

## `dependency_overrides`

`pubspec.yaml` currently pins `device_info_plus` and `connectivity_plus`
to specific versions via `dependency_overrides` — these aren't direct
dependencies of this app but are pulled in transitively by something else
in the tree; the overrides exist to resolve a version conflict between
transitive requirements. If a `flutter pub get` ever starts failing with a
version-solving error after adding a new package, check whether it
involves either of these two first.

## Evaluating a new dependency

Before adding one: does an existing dependency already solve this (check
this file first), and does it fit the architecture described in
[Architecture.md](Architecture.md) — specifically, does it respect the
client-direct-Firestore-writes model (ADR-013) rather than fighting it?
When you do add one, add a short entry here explaining *why this one*,
the same way the entries above do — a `pubspec.yaml` diff on its own never
answers that question for the next person.
