# YO Voice 🎙️

> **Be You. Connect. Speak.**

YO Voice is a modern cross-platform voice communication platform built with **Flutter** and **Firebase**, designed to create engaging communities where conversations feel natural, immersive, and interactive.

Unlike traditional voice chat applications, YO Voice focuses on creating unique social experiences through beautiful UI, real-time communication, and community-driven features.

---

## ✨ Features

### 🎤 Voice Rooms
- Community Voice Rooms
- Broadcast Rooms
- Real-time voice communication
- Live participant management
- Speaker & listener roles

### 👥 Communities & Clubs
- Create and manage Clubs
- Private community chats
- Member roles and permissions
- Club-exclusive voice rooms

### 💬 Social
- Friends system
- Follow creators
- Private messaging
- User profiles
- Search users and rooms

### 🏆 Gamification
- Achievements
- Titles
- XP progression
- Community milestones
- Activity rewards

### 🎨 Modern Experience
- Beautiful dark UI
- Smooth animations
- Responsive layouts
- Custom branding
- Premium visual design

---

## 🛠️ Tech Stack

- Flutter
- Dart
- Firebase Authentication
- Cloud Firestore
- Firebase Storage
- Firebase Cloud Messaging
- Google Sign-In
- Material 3

---

## 🚀 Vision

YO Voice isn't just another voice chat application.

The goal is to build a platform where people can:

- create communities,
- discover new creators,
- join live conversations,
- build clubs,
- make friends,
- and simply **be themselves**.

Everything is designed around one simple idea:

> **Be You.**

---

## 📱 Current Development

The project is actively under development.

Planned features include:

- Voice effects
- Room moderation tools
- Creator profiles
- Live events
- Push notifications
- Rich user achievements
- Premium subscriptions
- Cross-platform optimization

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

### Firebase App Check

Debug builds activate `AndroidDebugProvider`/`AppleDebugProvider`, which
print a debug token to the device log on first launch (see
`lib/main.dart`). That token must be registered once in **Firebase
Console → App Check → Apps → Manage debug tokens** before Firestore/Auth
calls will succeed from a simulator/emulator — otherwise every request
fails with a 403 App Check error. `enforceAppCheck` on Cloud Functions is
still `false`; flipping it to `true` is a deliberate, separate step that
needs token-delivery monitoring first, not something to do casually.

### Firestore rules

```bash
brew install openjdk           # one-time, needed for the emulator's JVM
export PATH="/usr/local/opt/openjdk/bin:$PATH"
firebase emulators:start --only firestore --project yovoice-ec54a
cd firestore-tests && npm install && npm test
```

See [`firestore-tests/README.md`](firestore-tests/README.md) for what the
suite actually covers and two non-obvious rules-semantics gotchas it
leans on. One worth calling out here too: a nested
`match /parent/{id}/collection/{doc}` rule does **not** authorize a
`collectionGroup()` query — that needs a separate, top-level
`match /{path=**}/collection/{doc}` rule. Direct `getDoc()`/`getDocs()`
calls on a fully-specified path don't exercise this at all, so it's easy
to ship a broken collection-group query with a fully green test suite —
`watchMyCommunities()` and `watchMyClubInvites()` both did, for a while.

Deploy with:

```bash
firebase deploy --only firestore:rules,firestore:indexes --project yovoice-ec54a
```

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
