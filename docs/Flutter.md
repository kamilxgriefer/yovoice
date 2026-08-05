# Flutter App

## Stack

Dart, Flutter, Material 3. Firebase Authentication, Cloud Firestore,
Firebase Storage, Cloud Functions, Firebase Cloud Messaging, Firebase App
Check, Google Sign-In, LiveKit (`livekit_client`), `permission_handler`,
`url_launcher`, `package_info_plus`.

## State management

`flutter_riverpod` + `riverpod_generator` are dependencies, but most
existing screens use plain `StatefulWidget` + `StreamBuilder` directly over
Firestore streams rather than Riverpod providers. Riverpod is available,
not yet the dominant pattern — don't assume a new screen should use it just
because it's in `pubspec.yaml`; match what similar existing screens do
unless there's a specific reason to introduce a provider.

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
`lib/shared/` (widgets) — see [UI.md](UI.md).

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

See [Firebase.md](Firebase.md#firestore-rules-testing) for the emulator
test workflow.

## Verification checklist before calling Dart work done

1. `flutter analyze` — zero issues.
2. For UI-facing changes, run it — in the iOS Simulator when possible,
   verifying the actual golden path plus loading/empty/error states, not
   just that it compiles.
3. If a screen can't be visually verified (e.g. no test credentials
   available), say so explicitly rather than claiming it was checked.
