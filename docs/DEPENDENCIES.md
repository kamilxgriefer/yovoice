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
  audio recording pipeline.

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
