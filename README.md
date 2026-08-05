# YO Voice 🎙️

> **Speak. Connect. Be you.**

YO Voice is a voice-first social platform built with **Flutter** and
**Firebase**: live voice rooms, Clubs, friends, Voice Moments, a real
achievement system, and creator tools — designed around live conversation
rather than a text feed.

Full documentation lives in [`docs/`](docs/Architecture.md) — start there
for anything beyond a quick clone-and-run:

- [docs/Vision.md](docs/Vision.md) — what this product is for
- [docs/Features.md](docs/Features.md) — what's actually built today
- [docs/Architecture.md](docs/Architecture.md) — how it all fits together
  (with links to Flutter.md, UI.md, Firebase.md, Backend.md)
- [docs/Roadmap.md](docs/Roadmap.md) — done / in progress / planned
- [docs/Decisions.md](docs/Decisions.md) — why things are the way they are
- [docs/Bugs.md](docs/Bugs.md) — current known issues
- [CLAUDE.md](CLAUDE.md) — working conventions for this repo

---

## 🛠️ Tech Stack

Flutter, Dart, Material 3, Firebase (Auth, Firestore, Storage, Cloud
Functions, Cloud Messaging, App Check), Google Sign-In, LiveKit. Full
breakdown in [docs/Architecture.md](docs/Architecture.md).

---

## 🔧 Development Setup

```bash
flutter pub get
flutter run                    # any connected device/simulator
flutter analyze                # static analysis, keep at zero issues
```

Firebase config is generated into `lib/firebase_options.dart` via
`flutterfire configure` — already committed, no per-developer setup needed
beyond having access to the `yovoice-ec54a` Firebase project.

For Firebase App Check debug-token setup and the Firestore rules
emulator/test workflow, see
[docs/Flutter.md](docs/Flutter.md#dev-setup) and
[docs/Firebase.md](docs/Firebase.md#firestore-rules-testing) —
kept there instead of duplicated here so there's one source of truth.

---

## 📷 Screenshots

Coming soon...

---

## 👨‍💻 Developer

Developed by **Kamil Jaguszewski**

GitHub: https://github.com/YOUR_GITHUB

---

## 📄 License

This project is currently proprietary.

All rights reserved.
