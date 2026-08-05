# Flutter App

## Stack

Dart, Flutter, Material 3. Firebase Authentication, Cloud Firestore,
Firebase Storage, Cloud Functions, Firebase Cloud Messaging, Firebase App
Check, Google Sign-In, LiveKit (`livekit_client`), `permission_handler`,
`url_launcher`, `package_info_plus`. See [DEPENDENCIES.md](DEPENDENCIES.md)
for why each of these was chosen over the obvious alternative.

## State management

`flutter_riverpod` + `riverpod_generator` are dependencies, but most
existing screens use plain `StatefulWidget` + `StreamBuilder` directly over
Firestore streams rather than Riverpod providers. Riverpod is available,
not yet the dominant pattern — don't assume a new screen should use it just
because it's in `pubspec.yaml`; match what similar existing screens do
unless there's a specific reason to introduce a provider. See
[DEPENDENCIES.md](DEPENDENCIES.md#state-management) for why this isn't
considered an abandoned migration — Firestore's own `Stream` API already
covers most of what a state management library would otherwise be for.

## Structure

Feature-based, under `lib/features/<feature>/`, each typically split into:

```
lib/features/<feature>/
  data/
    models/          # plain Dart classes, usually with a fromFirestore()
    services/         # Firestore/Storage/Functions calls
  presentation/
    screens/
    widgets/
```

Current feature modules: `achievements`, `auth`, `calls`, `chats`, `clubs`,
`creator`, `discover`, `friends`, `home`, `messages`, `moments`,
`notifications`, `profile`, `rooms`, `settings`.

Shared, cross-feature code lives in `lib/core/` (theme, helpers) and
`lib/shared/` (widgets) — see [UI.md](UI.md). For *why* this is
feature-based rather than layer-based (one global `models/`, `services/`,
`screens/`), see
[ADR-015](Decisions.md#adr-015-feature-based-folder-structure-over-layer-based).
For where this fits in the repo as a whole, see
[PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md).

## Navigation

The "More" sheet (`lib/features/home/presentation/widgets/more_sheet.dart`)
is a `MoreDestination` enum + a `moreDestinationScreen()` switch — the
pattern for adding a new destination screen without adding new top-level
navigation: add the enum case once, then only ever change what
`moreDestinationScreen()` returns for it.

## Voice

`livekit_client`, connecting to `wss://yovoice-3f7j9fb7.livekit.cloud`.
Token minting always goes through the `createLiveKitToken` Cloud Function
— see [Backend.md](Backend.md). Never mint a LiveKit token client-side.

## Device permissions

`permission_handler` — used for real microphone/camera/notification
permission status (Settings screen, voice call setup). Query real status
via `Permission.<x>.status`, don't assume/hardcode a permission state.

## Dev setup

```bash
flutter pub get
flutter run                    # any connected device/simulator
flutter analyze                # static analysis, keep at zero issues
```

Firebase config is generated into `lib/firebase_options.dart` via
`flutterfire configure` — already committed, no per-developer setup needed
beyond having access to the `yovoice-ec54a` Firebase project.

### Firebase App Check (local dev)

Debug builds activate `AndroidDebugProvider`/`AppleDebugProvider`, which
print a debug token to the device log on first launch (`lib/main.dart`).
That token must be registered once in **Firebase Console → App Check →
Apps → Manage debug tokens** before Firestore/Auth calls will succeed from
a simulator/emulator — otherwise every request fails with a 403 App Check
error.

### Firestore rules

See [Firebase.md](Firebase.md#firestore-rules-testing) and
[TESTING.md](TESTING.md) for the emulator test workflow.

## Verification before calling Dart work done

Short version: `flutter analyze` clean, plus an actual look at UI changes
rather than trusting that it compiles. Full checklist, and how this fits
into adding a feature end-to-end, in
[DEVELOPMENT_WORKFLOW.md](DEVELOPMENT_WORKFLOW.md#verification-checklist-before-calling-something-done).
