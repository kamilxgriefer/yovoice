# Known Issues

Current, living list of known bugs and tracked gaps — not a changelog.
Update this whenever a bug is found or fixed. For "features not built
yet," see [Roadmap.md](Roadmap.md) instead; this file is specifically
about things that are broken, risky, or need verification.

## Security

**No known critical open vulnerabilities.** For the full security model
(not just this status snapshot), see [SECURITY.md](SECURITY.md). A full
audit ([Archive/SECURITY_AUDIT.md](Archive/SECURITY_AUDIT.md)) found 3
critical, 3 high, and 6 medium-priority issues plus one client/server
contract bug. Verified during the documentation audit, directly against
current `firestore.rules`, `storage.rules`, and `functions/`: **all 13
items are fixed except one:**

- **`enforceAppCheck: false` on every Cloud Function** (audit item #12) —
  still open, but deliberately: flipping it needs a token-delivery
  monitoring period first (Firebase Console → App Check has the metrics).
  See [ADR-004](Decisions.md#adr-004-firebase-app-check-integrated-client-side-enforcement-deliberately-off).
  Not urgent on its own — it removes a layer that raises the cost of
  abusing the backend, it isn't itself an open exploit — but shouldn't be
  forgotten either. Tracked as a Roadmap item too:
  [Roadmap.md](Roadmap.md#2-firebase-app-check-enforcement).

If you're about to change `firestore.rules`, `storage.rules`, or anything
in `functions/`, read [SECURITY.md](SECURITY.md#firestore-security-rules--design-principles)'s
design principles and checklist first — each one maps to a specific
failure mode this codebase has actually hit before (self-role assignment,
missing field validation, `collectionGroup()` rule gaps, client-trusted
permission flags).

## Data integrity

- **Possible orphaned `rooms/{roomId}/members` documents.** When that
  subcollection was renamed to `roomMembers` (see
  [ADR-005](Decisions.md#adr-005-roomsroomidmembers-renamed-to-roommembers)),
  any pre-existing production documents under the old name became
  invisible to the app. Never verified whether any existed at rename
  time — no `gcloud`/Application Default Credentials were available in
  the session that made the change. **Action**: check the Firestore
  Console's `rooms/*/members` collections directly, or query via
  `firebase-admin` with a real service account key. If any exist, write a
  one-time copy migration. Tracked in
  [Roadmap.md](Roadmap.md#1-verify-no-orphaned-roomsroomidmembers-documents).
- **`experience: podcast` legacy compatibility.** Still actively read by
  `lib/features/rooms/data/models/room_experience.dart` — do not remove
  until production room documents are confirmed migrated to `broadcast`.
  See [ADR-001](Decisions.md#adr-001-legacy-podcast-room-experience-stays-supported).

## UI

- **Fixed: Settings screen was a blank grey panel on Flutter Web.**
  `settings_screen.dart` imported `dart:io`'s `Platform` and called
  `Platform.isIOS` unconditionally inside `_deviceLabel()`, which is
  called directly from `build()`. On web, `dart:io`'s `Platform` is a
  stub that throws `Unsupported operation: Platform._operatingSystem` on
  any access — crashing the whole screen's build and leaving Flutter's
  default grey `ErrorWidget` background with no visible error text (the
  "large white/grey empty area" report). Fixed by returning a `kIsWeb`
  branch before ever touching `Platform`. Verified server-side: the
  deployed `main.dart.js` was confirmed via direct `curl` (bypassing any
  browser cache) to contain the fix and no longer reference the crashing
  path. **Not re-verified as a live screenshot** — every standard
  cache-bypass technique (`Cache-Control: no-cache`, `Clear-Site-Data`,
  full browser-process restart, brand-new tabs, query-string busting on
  both `main.dart.js` and `flutter_bootstrap.js`, an isolated iframe
  loaded entirely from `no-store` fetches) still rendered stale,
  pre-fix content in this session's sandboxed browser tool — strong
  evidence of a caching layer in that tool's own network path, not an
  app defect, but it means the fix is server-verified, not yet
  eyes-verified. Needs a real end-user browser (or a future session with
  working tooling) to close the loop.
- **Fixed (root cause): Firebase Hosting served `main.dart.js` (and other
  build output) with `Cache-Control: max-age=3600`, and Flutter's default
  web build doesn't content-hash that filename.** This meant any browser
  that had visited before a deploy could keep running the *previous*
  build's JS for up to an hour after a fix shipped — exactly the kind of
  gap that made the Settings fix above hard to verify live. Added
  explicit `Cache-Control: no-cache` header rules for `**/*.@(js|json|wasm)`
  and `/index.html` in `firebase.json`, forcing browsers to revalidate
  (via ETag) on every load instead of trusting a stale copy.
- **Fixed: profile avatar (and, incidentally, display name) silently
  reverted to blank/placeholder minutes after being set correctly.**
  `PresenceService.setOnline()` (`lib/core/presence/presence_service.dart`)
  runs unconditionally every 45 seconds and on every app foreground, and
  was writing `photoUrl: user.photoURL` (FirebaseAuth's own, separate,
  often-null `currentUser.photoURL`) into the *same* Firestore
  `users/{uid}.photoUrl` field that `ProfileService` treats as the
  authoritative profile photo. Any time those two diverged, the next
  heartbeat clobbered the real value. Reproduced directly: set
  `photoUrl` via the Storage/Firestore REST API on the shared diagnostic
  account, confirmed it read back correctly, then watched it revert to
  `null` on its own within one heartbeat interval while a session was
  open. Fixed by stripping `displayName`/`email`/`photoUrl` out of the
  presence write entirely — presence now only ever touches
  `isOnline`/`lastSeen`/`presenceUpdatedAt`. The one legitimate reason
  those fields were being seeded there (bootstrapping a brand-new user's
  profile doc before they ever open Profile) is now handled once, at
  sign-in, by `ProfileService.ensureProfile()` called from
  `AuthGate`'s `_AuthenticatedEntryState.initState()` — already
  idempotent (no-ops if the doc exists), so this is a straight move, not
  new behavior. Also fixed the *display* side of the same class of bug in
  `home_screen.dart`: its header read `FirebaseAuth.instance.currentUser`
  directly (a non-reactive snapshot, and the same wrong source of truth)
  instead of the Firestore profile stream every other screen
  (Settings, Creator Studio) already uses correctly — now wired to
  `ProfileService.watchCurrentProfile()` like the rest. **Verified**:
  root cause reproduced live via REST before the fix; the fix itself is
  a small, mechanical, `flutter analyze`-clean change reviewed against
  the same reactive pattern already proven correct elsewhere in the
  app. **Not yet re-confirmed with a live client running the patched
  build** — blocked by the same Web caching-tool issue above, and by the
  iOS Simulator being unresponsive to input in this session (reboot,
  relaunch, and home+relaunch recovery attempts were all tried and all
  failed identically).
- **Not a bug, confirmed by direct check: profile banner (`bannerUrl`)
  was never affected by the avatar issue above.** `PresenceService`
  never touched `bannerUrl`, and `profile_screen.dart` already reads
  `profile.bannerUrl` correctly from the same reactive stream. Confirmed
  directly: set both `photoUrl` and `bannerUrl` via REST on the
  diagnostic account at the same time — after the same wait,
  `bannerUrl` was untouched while `photoUrl` had been wiped again (by a
  still-open browser tab running the *old*, pre-fix code) — a clean,
  direct confirmation that the two fields' behavior genuinely differs
  for the reason described above, not a shared/systemic Firestore issue.
- **Fixed: white panel flashing behind sheet transitions (e.g. New Chat)
  on devices with the OS set to Light mode.** Root cause was native
  Android/iOS window chrome following the *system* light/dark setting
  instead of the app's own dark-only theme — not a bug in the Dart-side
  sheet code. See
  [ADR-016](Decisions.md#adr-016-native-android-and-ios-window-chrome-is-pinned-dark-not-os-controlled)
  for the full root cause and fix.
- **Fixed: the New message sheet showed a large light-grey panel filling
  everything below the search field (Flutter Web).** A *separate* bug from
  the native window-chrome one above, which stays valid — this one is
  pure Dart and reproduces on every platform.
  `FriendService.watchFriends()` returned a plain
  `StreamController<List<FriendUser>>()`, i.e. a **single-subscription**
  stream. `MessagesScreen` builds that stream once in `initState` and
  hands the same instance to two widgets: `_FriendsRow` (always mounted,
  subscribes first) and `NewMessageSheet`. Opening the sheet therefore
  made a second `listen()` call, which throws
  `Bad state: Stream has already been listened to.` inside the sheet's
  `StreamBuilder`. Flutter replaced that subtree with the default
  `ErrorWidget` — red with text in debug, an **unlabelled light-grey
  rectangle in release** — occupying exactly the `Expanded` region below
  the search field, which is why the handle/title/search stayed correctly
  dark. Same failure signature as the Settings grey-panel bug above: an
  exception during build, rendered as a blank grey box in a release web
  build. Fixed by making `watchFriends()` return a broadcast stream that
  also replays its last value to late subscribers (via `Stream.multi`) —
  replay matters because the sheet subscribes *after* the first emission
  and would otherwise sit on a spinner. **Verified**: reproduced live in
  Flutter Web with a debug build via `lib/dev/new_message_preview.dart`
  (screenshot showed the panel and the "already been listened to"
  message), then re-checked after the fix with the sheet rendering fully
  dark end to end. Regression covered by `test/new_message_sheet_test.dart`.
- **Fixed: the New message sheet painted its surface with a bare
  `Container`.** `showModalBottomSheet` is invoked with
  `backgroundColor: Colors.transparent`, so that `Container` *was* the
  sheet's surface — but it sat between the tiles and the nearest
  `Material`, so every `ListTile` background and ink splash was painted
  behind it and never seen. Flutter's own assertion ("ListTile background
  color or ink splashes may be invisible") fired in debug. The sheet now
  owns a `Material`.
- **Fixed: a failed friends/conversations query in the New message sheet
  rendered as "You're all caught up".** The sheet read `snapshot.data`
  but never checked `hasError`, so a permission failure was
  indistinguishable from having no friends. There is now a distinct dark
  error state.
- **Fixed: a newly chosen avatar/banner appeared to do nothing in Edit
  profile.** Not a caching bug: `ProfileService` already uploads to a
  timestamped path (`avatar_<millis>.jpg`), so every upload produces a
  genuinely new download URL and neither the browser HTTP cache nor
  Flutter's `ImageCache` can serve a stale image. The real causes were
  in the UI: (1) `EditProfileScreen` rendered **no avatar or banner
  preview at all** — just two "Change avatar/Change banner" buttons — so
  after a successful upload nothing on screen could change; and (2) it
  received a `UserProfile` as a plain constructor argument and threw away
  the URL returned by `pickAndUploadImage`, so its own copy of the
  profile was stale the moment the upload finished. Edit profile now
  shows a live preview of both images, and a freshly picked file renders
  instantly from memory (`MemoryImage`) with no upload or network round
  trip. `ProfileScreen` was already correct — it reads
  `watchCurrentProfile()` — so it updates as soon as Firestore does.
- **Changed: avatar/banner now commit on Save instead of uploading
  immediately.** Previously images were written to Storage and Firestore
  the instant they were picked, while every text field waited for Save —
  so pressing Back after choosing an avatar still changed it remotely,
  and a discarded pick left an orphaned Storage object behind. Picks are
  now held in memory as pending changes and uploaded by `_save()`, which
  gives the screen one consistent rule and means nothing reaches Storage
  unless the user commits.
- **Known, not yet fixed: other people still see your old avatar.** The
  photo URL is denormalised into `conversations.participantPhotoUrls`,
  `users/{uid}/friends/*`, room participants and club members, each
  written from `FirebaseAuth.currentUser.photoURL` at the time that
  document was created. Changing your profile photo updates
  `users/{uid}.photoUrl` but nothing back-fills those copies, so your
  avatar stays stale in other users' Chats/Friends/Rooms lists (and in
  your own conversation list). Needs a fan-out — realistically a Cloud
  Function on `users/{uid}` write — plus a one-off backfill. Also
  `home_screen.dart:568` still reads `FirebaseAuth.instance.currentUser
  ?.photoURL` directly, which is a non-reactive snapshot and will not
  rebuild when the avatar changes.
- **Fixed: Broadcast Room listeners were left stranded in a dead room.**
  When a host ended or deleted a Broadcast Room, every participant doc
  (including every listener's own) was deleted server-side, but the
  screen only watched the participants list, not the room's own status —
  so listeners just saw the stage go empty with no explanation and no
  way back except manually tapping back. Now detected and the listener is
  shown "This room has ended." and navigated out automatically. See
  `broadcast_room_screen.dart`'s `_handleParticipantsUpdate`.
  `community_voice_room_screen.dart` already had equivalent handling
  (`_handleParticipantState`) before this pass; `podcast_room_screen.dart`
  didn't get this fix — see the dead-code note below.
- **Fixed: "Sign up" / "Log in" cross-links on the auth screens had a
  near-zero tap target.** Both `login_screen.dart` and
  `register_screen.dart` explicitly shrank the `TextButton`'s hit box to
  the bare text glyphs (`padding: EdgeInsets.zero` +
  `minimumSize: Size.zero` + `tapTargetSize: MaterialTapTargetSize.shrinkWrap`),
  well under Apple/Material's 44/48pt minimum touch target — a tap that
  looked like it landed on the text would frequently miss. Removed the
  override so the theme's default `TextButton` sizing applies (the shared
  `textButtonTheme` doesn't set its own padding/minimumSize, so this falls
  through to Flutter's own default, already comfortably tappable).
  Regression-guarded by `test/auth_link_tap_target_test.dart`, which taps
  each link via `find.text(...)` (real hit-testing, not a coordinate
  guess) and asserts the resulting navigation.
- **Fixed: every "More" menu destination had doubled or broken chrome.**
  Reported as "Settings is broken — white background, content missing";
  the actual cause was every one of the seven More destinations being
  wrapped in a second, redundant `Scaffold`+`AppBar` on top of each
  screen's own. Settings only doubled its title text; Achievements showed
  two full stacked Material app bars. See
  [ADR-019](Decisions.md#adr-019-more-menu-destinations-own-their-full-chrome-no-wrapper-scaffold).

## Code quality / consolidation

- **`RoomScreen` (`lib/features/rooms/presentation/screens/room_screen.dart`,
  ~1,164 lines) and `PodcastRoomScreen`
  (`.../screens/podcast_room_screen.dart`, ~987 lines) are dead code.**
  Confirmed by tracing actual navigation, not by filename: `RoomEntryScreen`
  only routes to `BroadcastRoomScreen` or `CommunityRoomLobbyScreen`, and
  legacy `experience: podcast` Firestore values are mapped to `broadcast`
  before that routing decision happens (see
  [ADR-001](Decisions.md#adr-001-legacy-podcast-room-experience-stays-supported)) —
  so neither screen class is reachable from anywhere in the app. Not
  deleted per this project's rule against removing functionality without
  being explicitly asked (see [CLAUDE.md](../CLAUDE.md)) — flagging for a
  deliberate decision instead. See
  [ADR-018](Decisions.md#adr-018-per-screen-firestore-streams-are-created-once-in-initstate-never-inline-in-build)
  for how this was found.
- **Several screens create a fresh `Stream` inline inside `build()`**
  instead of once in `initState()`, causing `StreamBuilder` to tear down
  and re-subscribe its Firestore listener on every rebuild. Fixed in the
  four highest-traffic instances
  (`broadcast_room_screen.dart`, `community_voice_room_screen.dart`,
  `podcast_room_screen.dart`, `club_overview_screen.dart`) — see
  [ADR-018](Decisions.md#adr-018-per-screen-firestore-streams-are-created-once-in-initstate-never-inline-in-build).
  A handful of lower-traffic instances remain
  (`friends_screen.dart`, `friend_profile_screen.dart`, an invite sheet in
  `club_overview_screen.dart`) — lower severity since they don't sit
  behind a frequently-rebuilding `build()`, but worth a future pass.
- **Two parallel hand-raise implementations exist**, unconsolidated. Not
  actively broken, but a maintenance risk — a fix applied to one may be
  missed in the other. See
  [Roadmap.md](Roadmap.md#12-consolidate-the-two-parallel-hand-raise-implementations).
- **Most screens don't use the shared theme system** (`lib/core/theme/`,
  `lib/shared/widgets/`) yet — they use a consistent-but-inline hex-color
  convention instead. Not a bug, but tracked as a migration in progress —
  see [UI.md](UI.md) and
  [Roadmap.md](Roadmap.md#app-wide-theme-migration).
- **Zero automated test coverage for Cloud Functions**, and near-zero for
  Flutter services/widgets beyond a couple of files. Not a regression —
  coverage was never broad to begin with — but worth knowing before
  assuming a change is safe because "the tests pass." See
  [TESTING.md](TESTING.md) for exactly what is and isn't covered.

## Infrastructure

- **`app.yovoice.app` DNS record not added yet** — blocks the website from
  pointing at its final app URL. Needs Cloudflare access only the domain
  owner has. See [Roadmap.md](Roadmap.md).
- **Fixed: `flutter build apk` failed outright** (missing core library
  desugaring for `flutter_local_notifications`, then a follow-on AAPT2
  drawable-resource error). See
  [ADR-017](Decisions.md#adr-017-android-build-fixes-core-library-desugaring-and-drawable-resource-references).
  Nothing in CI builds Android (only the Flutter web target does — see
  [DEPLOYMENT.md](DEPLOYMENT.md)), so a regression like this has no way
  to surface on its own; worth keeping in mind next time something in
  `android/` changes.
- **Android build is verified; Android runtime is not.** No emulator
  (AVD) or physical device was available in the session that fixed the
  above — `flutter build apk --debug` succeeds and produces a real APK,
  but nobody has actually run this build and watched it boot. Needs a
  session with an Android emulator/device attached to close the loop.
- **Fixed (root cause, demonstrated): a saved avatar was wiped seconds
  later by the friends stream.** `FriendService.ensureUserDocument()`
  merged `'photoUrl': user.photoURL` — FirebaseAuth's own, separate,
  frequently-null value — into `users/{uid}.photoUrl`, the exact field
  `ProfileService` owns. It runs from `watchFriends()`'s `onListen`, so
  every Home mount, every Messages mount and every browser refresh
  overwrote the freshly uploaded avatar with whatever Auth happened to
  hold: `null` for email/password accounts (→ the purple placeholder with
  the person icon on Home) or a stale Google avatar for Google accounts.
  This is the third instance of the same defect — `PresenceService` had
  it, `home_screen` read the same wrong source — and it explains why the
  earlier "Edit profile has no preview" fix, though real, did not make
  the avatar appear. Proven, not inferred: `test/profile_photo_source_of_
  truth_test.dart` fails with `Actual: https://i.stack.imgur.com/34AD2.jpg`
  when the old line is restored and passes with it removed.
  `ensureUserDocument()` now writes only `uid`/`isOnline`/`lastSeen`.
- **Fixed: removing that write exposed an ordering hazard in
  `ProfileService.ensureProfile()`.** It bailed out on
  `if (existing.exists) return;`, but `ensureUserDocument()` (and
  presence) legitimately *create* `users/{uid}` with presence-only
  fields — so a friends stream that started before AuthGate's
  `ensureProfile()` left a brand-new account permanently without a
  displayName. It now keys off whether `displayName` is actually present,
  seeds the Auth avatar only when the profile has none, and writes the
  zeroed counters only on true first creation so it can never reset
  progress.
- **Fixed: Home mixed two profile-image sources.** The header read
  `profile?.photoUrl ?? FirebaseAuth.currentUser?.photoURL` and the "Your
  Moment" bubble read `currentUser?.photoURL` directly — a non-reactive
  store that never updates after an avatar change. Both now read the
  shared profile stream, so Home, Profile, Settings and Creator Studio
  cannot disagree.
- **Added: `ProfileService.watchCurrentProfile()` is now one shared,
  replayed broadcast stream cached per uid**, so every screen observes the
  same value from one Firestore listener, and a screen opened after the
  first emission renders immediately instead of flashing a placeholder.
  Cleared on sign-out via `resetCurrentProfileCache()`.
