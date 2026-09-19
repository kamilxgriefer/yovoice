# Known Issues

Current, living list of known bugs and tracked gaps — not a changelog.
Update this whenever a bug is found or fixed. For "features not built
yet," see [Roadmap.md](Roadmap.md) instead; this file is specifically
about things that are broken, risky, or need verification.

## OPEN — build 32's tester notes promise a deletion the server refuses (2026-09-19)

Not a code defect: the binary, the server and the rollout order are all doing
what they were designed to do. It is a copy-versus-state mismatch that will
generate tester reports, and it needs a human decision rather than a fix.

The "What to Test" text stored for TestFlight build 32
(`betaBuildLocalizations/a13858b1-ca22-4a58-b643-192c4d8c4276`, 542 chars,
`en-US`) tells testers "you can now delete your account from Settings (the
request is processed within a few minutes)" and asks them to exercise
`Settings → Delete account`. But `appConfig/accountDeletion` does not exist —
re-read live on 2026-09-19, HTTP 404 — and `accountDeletionEnabled()`
(`functions/account/deletion.js:127`) is fail-closed on a missing document by
design. A tester who follows the instruction reaches the screen, reads the
retained-data copy and is routed to `privacy@yovoice.app` by
`AccountDeletionFailureKind.unavailable`. Nothing crashes and no data is
touched; the promise is simply false while the switch is off.

The other three claims in the same notes are genuinely testable — their server
halves (`createServerInviteV1`, `getProfileMediaAccess`) were deployed in the
same round, and the empty-chat-threads fix is client-only.

Two ways out, both cheap: leave it and triage the reports, or `PATCH` the same
localization to drop the deletion instruction — `whatsNew` is rewritable after
release and needs no rebuild. Flipping the kill switch instead is **not** an
option: it is gated on iOS *and* Android being live in the stores, and on the
ban-digest salt below. Owner: product.

## OPEN — account deletion leaves four named categories behind (2026-09-18)

Found while gating Build 32's account-deletion slice. Each of these is a place
where personal data outlives a completed deletion. None of them is claimed by
any user-facing copy any more — the app's consequence list, `/delete-account`
§2/§5 and privacy §9 were rewritten to match the pipeline
([ADR-206](Decisions.md#adr-206-a-deletion-promise-is-a-list-of-stages-and-the-copy-may-not-exceed-it))
— so the product is honest, but the gaps are real and each needs its own stage
plus an emulator test before the matching claim may come back.

- **Comments and reactions on OTHER people's posts.** `functions/account/stages.js`
  `runContent` deletes `voiceMoments`/`reels` where `authorId == uid` and
  `recursiveDelete` takes their own comments and likes with them. There is no
  `collectionGroup` query for `comments.authorId` and no index for one. The rows
  carry `authorId`, `authorName`, `text` and a voice-comment `storagePath`.
  Closing this needs the composite index **and** an ADR-007 test that runs the
  real query, not a direct-path one. Owner: backend.
- **Storage objects outside a uid-keyed prefix.** `uidStoragePrefixes` is a
  fixed seven-element list and `runStorage` sweeps only it. `storage.rules`
  declares eleven prefixes, so **four** are never deleted by the pipeline — the
  first disclosure of this named only the first two:
  1. `family_moments/{clubId}/{uid}/` (`storage.rules:321`) — Family memories.
  2. `server_company_files/{serverId}/{channelId}/{uid}/` (`storage.rules:434`)
     — Company channel files. Both are uid-keyed but nested under somebody
     else's container, so closing them needs the club/server-id enumeration the
     social stage already walks.
  3. `room_images/{roomId}/{fileName}` (`storage.rules:165`) — voice-room cover
     images. The uploader is identifiable (`{uid}_{32 hex}.jpg|png`, plus an
     `ownerId` in custom metadata) but the uid is nowhere in the path, so
     closing this needs an enumeration of the rooms the account hosted or a
     per-object metadata scan.
  4. `server_podcast_episodes/{serverId}/{channelId}/{fileName}`
     (`storage.rules:506`) — backend-written (`allow read, write: if false`),
     with no uid in the path or the object name at all.

  All four are disclosed in `/delete-account` §5 and none is claimed as deleted
  by any copy. Owner: backend.
- **`directCalls/{callId}`.** Carries `callerId`/`calleeId` and is never
  deleted; only `directCallLocks/{uid}` and `users/{uid}/incomingCalls` are.
  Owner: backend.
- **Server ownership succession.** A deleted owner's Server keeps running with
  the deleted person's pseudonymous uid bound as `ownerId`; only `ownerName`,
  the member `displayName` and `photoUrl` are anonymized. Tearing a membership
  down correctly needs the Servers operations layer. This is an open **owner**
  decision (transfer, or close), not a bug to fix silently. Owner: product.

Residual, lower-severity and unclaimed by any copy: `achievementVoiceSessions` /
`achievementVoiceEvents`, `integrityPreflightLedgers`, `userWarnings`,
`reelAvailability`/reservations, `directReactionEvents`,
`privateRateLimits.ownerId` and legacy room participation are not swept either.
They are pseudonymous or short-lived, which is why the retained-set copy speaks
of "short-lived records that stop an in-flight operation from being replayed"
rather than naming each.

## OPEN — two-factor accounts cannot delete their account in-app (2026-09-18)

TOTP two-factor is a shipped feature (`lib/features/auth/data/totp_mfa_service.dart`,
enrolment in `two_factor_authentication_screen.dart`). For an enrolled account
`reauthenticateWithCredential` throws, and `DeleteAccountScreen` has no
second-factor step to drive, so the in-app deletion cannot complete — the users
who followed the app's own security advice are the ones locked out of the
affordance Google Play requires.

Mitigated, not fixed: `_runReauth` now detects the refusal (the typed
`FirebaseAuthMultiFactorException`, and the platform codes
`second-factor-required` / `multi-factor-auth-required`, because the typed
exception's only constructor is private to the plugin) and renders an EN+PL
sentence naming the e-mail route by the exact words on the button below it,
instead of a generic auth error and a dead end. Covered by
`test/delete_account_screen_test.dart` for both codes.

The real fix is to drive the existing resolver: `AuthService.createTotpSignInChallenge`
plus `TotpChallengeScreen`, the same path `responsive_auth_screen.dart` already
uses for sign-in. It was not taken in this round because it cannot be verified
end to end here — no deployed callable and no enrolled test account — and
shipping an unverified resolver into the Play-compliance path is worse than
shipping the honest fallback. Owner: Flutter.

## OPEN — the ban digest is inert until an operator sets its salt (2026-09-18)

`functions/account/stages.js` writes `deletedAccountDigests/{digest}` only when
the profile is `banned === true` **and** a salt is configured;
`functions/account/retention.js` requires
`YOVOICE_DELETED_ACCOUNT_DIGEST_SALT` of at least 16 characters and otherwise
returns null. An unsalted digest of an e-mail address is trivially reversible,
so skipping is the correct behaviour — but if the variable is never set,
deleting a banned account silently resets the ban.

Closed on the documentation and observability side in this round: the variable
is documented in [DEPLOYMENT.md](DEPLOYMENT.md) as a **precondition** for
writing `appConfig/accountDeletion.enabled = true`, and the skip is now written
to the outbox row as `banDigestSkipped: true` rather than being only a log line,
as `retention.js` already claimed. Still open: nothing verifies the salt at
deploy time, and no TTL removes a digest — the retention is indefinite for a
permanent ban, which the website now states plainly instead of promising
expiry. Owner: ops.

**Re-verified 2026-09-19, after the Build 32 backend deploy: the variable is
still not set anywhere.** It is absent from `functions/.env`, and absent from
the `environmentVariables` of all three deployed account-deletion exports
(`deleteAccountSelfV1`, `onAccountDeletionOutboxCreated`,
`processAccountDeletionOutboxSchedule` — read back in
`yovoice-evidence/2026-09-18/b32/deploy-readback-*.json`). Because a
`functions/.env` value is materialized into the function environment **at deploy
time**, setting it is not a live configuration change: it needs an edit *and* a
redeploy of at least those three exports, and both must happen before anyone
writes `appConfig/accountDeletion.enabled = true`
([DEPLOYMENT.md](DEPLOYMENT.md), enablement step 4). Nothing is at risk while
the kill switch is off, because no deletion can run at all.
## FIXED — four source-guard tests failed on every Windows checkout (2026-09-19)

Found while setting the project up on a Windows workstation; macOS and CI
(Linux) never saw it. `flutter test` reported 4 failures there that had nothing
to do with the product:

- `localization_source_guard_test.dart` — *literal catalog keys without
  interpolation*: every budgeted file reported as new, e.g.
  `lib/features\clubs/presentation\screens\clubs_screen.dart: 5, // allowed: 0`.
- `semantic_color_source_guard_test.dart` — *do not import the immersive
  palette* and *reject copied semantic and immersive surface values*: every
  documented immersive atom (`auth_gate.dart`, `image_crop_screen.dart`, the
  room mini-player, …) reported as a violation.
- `voice_session_keep_alive_test.dart` — *manifest components resolve to the
  one active application package*: found zero `MainActivity.kt` files.

- **Root cause.** `Directory.listSync` joins the entries below its root with
  the platform separator, so on Windows it yields
  `lib/features/moments/presentation\screens\record_voice_moment_screen.dart`.
  The guards compared those paths against POSIX keys (the localization
  budgets, `_excludedFiles`, the `lib/app/` prefix, `/MainActivity.kt`), so no
  key ever matched.
- **Fix (tests only).** Each enumeration normalises `\` to `/` where it lists
  files, the same pattern `sign_out_cleanup_test.dart` already uses. On Windows
  all 20 cases in the three files pass. A mutation probe still bites: a
  throwaway `lib/features/home/presentation/*.dart` importing
  `app_immersive_colors.dart` fails the import guard and is reported with a
  `/` path.
- **Related environment trap, not a code change.** The same Windows run
  failed two more tests (`ios_export_compliance_test.dart`,
  `localization_platform_configuration_test.dart`) because Git for Windows
  defaults to `core.autocrlf=true`. With that setting the checkout gets CRLF,
  and tests that match multi-line source fragments containing `\n` fail. On a
  Windows clone, set `git config --global core.autocrlf false` before cloning,
  or re-checkout afterwards. The repository has no `.gitattributes`, so it
  does not enforce LF itself.

## FIXED — people you never wrote to hoisted to the top of Chats (2026-09-18)

Tester report via the owner, verbatim: "pokazuje się historia na samej górze
w czatach ludzi z którymi nie pisał nawet jeszcze, dziwnie ich 'winduje' do
góry bez sensu". Opened and fixed in source on 2026-09-18, with tests that were
RED before the fix and GREEN after it; not yet verified on a device.

**Shipped in Build 32 as `bffa8db6`** (`fix(chats): hide message-less threads
other people opened, order by last message`), which is in the binary iOS testers
received on 2026-09-19. An earlier revision of this entry cited
`78beb43d6312` and called it a Build 33 candidate; that object has the identical
patch-id but is not reachable from any ref, so `bffa8db6` on `main` is the
commit to cite.

- **Root cause — a conversation root exists for BOTH people from the moment
  either one looks at the other, and the list sorted every root by
  `updatedAt`.** `openDirectConversation`
  (`functions/messaging/direct_integrity.js:1024-1046`) creates the root the
  first time A opens B from B's profile, the Friends rail or the new-message
  sheet, with `lastMessage: ""`, `lastMessageSenderId: ""`,
  `lastMessageSequence: 0`, `createdAt: now`, `updatedAt: now` and no field
  naming the opener. `MessageService.watchConversations`
  (`lib/features/messages/data/services/message_service.dart`) streamed every
  root with the account in `participantIds` and sorted by `updatedAt`, so B
  got a "Start a conversation" row for A above every real thread — on the
  Chats list and on Home's recent-chats rail, which takes the first three of
  the same stream. Each further person who looked (or each friend the tester
  tapped and backed out of) landed at the top the same way. The server bumps
  `updatedAt` only on message events — sending text or media
  (`direct_integrity.js:1245-1251`, `:1786-1792`), editing or deleting the
  newest message (`:1936-1939`, `:1958-1961`) and an admin deletion
  (`functions/admin/messages.js:181-186`); typing (`:2824`), read cursors
  (`:2594`), archive/mute (`:2091`), delete-for-me (`:2329`), reactions and
  calls never touch it — so the promotion came from creation, not from later
  heartbeats.
- **Fix (client only, no schema change).** `Conversation.hasMessages`
  (any of `lastMessage`, `lastMessageSenderId`, `lastMessageSequence`) and
  `Conversation.lastActivityAt` (`updatedAt` with messages, `createdAt`
  without) in `lib/features/messages/data/models/conversation.dart`;
  `watchConversations` hides message-less roots and sorts with
  `Conversation.compareByRecentActivity`. The one exception is the empty
  thread THIS account opened from THIS device: the root records no opener,
  so `DirectConversationOpenIntents.markOpenedHere` keeps an in-memory,
  account-scoped set of ids that `openOrCreateConversation` fills on success
  (callable and legacy paths), and the stream combines with it so the thread
  appears the moment the open completes. The set is deliberately in-memory:
  after a restart an own empty thread drops out of the list until someone
  writes; it is reachable again from the person's profile. Chats tiles and
  the new-message sheet's Recent section order by the same key; unread
  badges, mute, archive, search and empty states are untouched, and Home's
  rail inherits the behaviour through the shared stream. Tests:
  `test/conversation_visibility_ordering_test.dart` (service order and
  exclusion, both open paths, deleted/archived filters unchanged, the
  locally-opened stream, sort-key unit cases, Firestore parsing) and
  `test/messages_screen_empty_thread_visibility_test.dart` (Chats at phone,
  tablet and desktop widths, Home rail, empty state). Mutation proof: with
  the visibility filter removed 9 of the 14 tests fail; with the old
  `updatedAt` sort restored the 5 ordering assertions fail; both restored
  and the suites are 14/14 on the fixed tree.
- **Backend follow-up (recommendation, not done here):**
  `openDirectConversation` should not have to create a root the non-opener
  can see — either write `lastMessageAt` only when a message lands and let
  the list query on it, or record `openedBy` on the root so clients need no
  local memory of who opened what. Until then the client rule above holds.
## FIXED IN SOURCE — a nameless profile announced "Zdjęcie w tle:" and opened a differently-named frame (2026-09-18 sweep, fixed 2026-09-19)

Found during the "banner" slice's verification pass over S-02 / S-19 (the
banner viewer and the friend-profile banner band, both already landed by the
"profile" and "other" slices — see the entries further down). Fixed in source
on branch `polish/build-33`; commit `polish/build-33 (pending)`. Full report:
`yovoice-evidence/2026-09-18/polish-33/fix-banner.md`.

- **The launcher and the frame it opens disagreed about the member's name.**
  `showProfilePhotoViewer` has always resolved an empty `displayName` to
  "YO Voice member" / "Użytkownik YO Voice", but `ProfilePhotoButton` and
  `ProfileBannerButton` interpolated the raw value into their own semantic
  label and tooltip. `UserProfile.fromFirestore` only substitutes a name when
  the field is *missing*, so a document carrying `displayName: ''` reaches the
  UI with an empty name: the avatar and the banner then announced
  "Zdjęcie profilowe:" and "Zdjęcie w tle:" — a bare colon with nothing after
  it for a screen reader — and the dialog that opened on tap was titled
  "…: Użytkownik YO Voice". Two names for one photo, on the exact surface the
  owner asked to have working everywhere. Fix: one private `_viewerName`
  helper in `lib/shared/widgets/profile/profile_photo_viewer.dart`, used by
  the dialog and by both launchers, so the fallback (and the trim, which also
  stops a padded name being announced with its whitespace) is applied in one
  place. No new copy key — the existing EN/PL pair moved into the helper. No
  palette, layout, geometry or schema change; every other call site is
  unaffected.
- Regression coverage: `test/profile_banner_viewer_test.dart`, "a nameless
  profile is named the same way by the launcher and by the frame it opens"
  (banner) and "the avatar launcher resolves a missing name the same way".
  Mutation-proved: restoring the raw interpolation fails exactly those two and
  leaves the other four cases green.
- **Rendered, but not on a device.** The viewer and the friend-profile band
  were captured from a real render pass (`polish-33/visual/`,
  `viewer-banner-*`, `friend-profile-photo-*`): the banner frame is 16:9 and
  the avatar frame 1:1, the PL title reads "Zdjęcie w tle: …", and the
  no-photo state is the cosmic gradient with "Brak zdjęcia w tle" — not the
  initial-letter block. Those captures use a stub image, so **a real uploaded
  background photo has still never been seen in the new viewer**; no APK was
  built from this worktree while several agents were editing `lib/`
  concurrently. Production `getProfileMediaAccess` logged zero ERROR-severity
  entries in the 24 h to 2026-09-19 07:28 CEST and answers 200, so the grant
  path the viewer depends on is healthy; the function does not log `kind`, so
  that check does not single out banner grants.

## FIXED IN SOURCE — the Settings title ran off the right edge at 200 % text (2026-09-18)

Audit ID S-11 from the Build 33 pre-redesign polish sweep
(`yovoice-evidence/2026-09-18/polish-33/audit-small-things.md`, report
`yovoice-evidence/2026-09-18/polish-33/fix-overflow.md`). Fixed in source on
branch `polish/build-33`; commit `polish/build-33 (pending)`.

- **S-11 (P3) — the Settings header title overflowed at large text scale.**
  The header `Row` in `settings_screen.dart` was
  `[YoIconButton(40 → 48 pt touch target), SizedBox(6), Text(fontSize: 26)]`
  and the title was the last child with **no** `Expanded`/`Flexible`, no
  `maxLines` and no `overflow`. At 200 % text the 26 px title renders at ~52 px,
  so on a narrow phone "Ustawienia" (and "Settings" behind a Back button) ran
  past the right edge and `RenderFlex` reported an overflow instead of
  ellipsizing. Fix: the title is now
  `Expanded(child: Text(…, maxLines: 1, overflow: TextOverflow.ellipsis))` —
  the same shape `creator_studio_screen.dart:402` already uses for its own
  header. **No copy, style, colour, padding or size changed**, and no catalog
  key was added: the existing `copy.text('Settings', 'Ustawienia')` pair moved
  verbatim, so `find.text('Settings')` in `test/mobile_staff_parity_test.dart`
  and `'Ustawienia'` in `test/shared_polish_localization_test.dart` still match.
  The row was lifted into a new `SettingsHeaderBar` widget in the same file for
  one reason: `SettingsScreen` builds its own `ProfileService`/`AuthService` and
  `watchCurrentProfile()` throws `Bad state: User is not signed in` the moment
  `build()` runs under `flutter test` (measured — the screen renders nothing at
  all, `find.text('Ustawienia')` is 0 widgets), so the overflow was otherwise
  untestable. Test: `test/settings_header_text_scale_test.dart`, 22 cases across
  320 / 390 / 834 / 1440 px × EN/PL × root-tab/pushed-route, asserting the title
  stays inside the row and no `RenderFlex` overflow is raised, plus a
  default-text-size case per width pinning that the title still starts flush
  after the Back button (layout unchanged) and a case that the Back button still
  fires. Mutation-proved: with the `Expanded` reverted, **8 of 22 fail** — all
  four 200 % cases at 320 px and all four at 390 px, with
  "A RenderFlex overflowed by 166 pixels on the right" and
  "the title ends at 468.0 but the header row ends at 302.0"; the tablet,
  desktop and default-size cases stay green, which is exactly the blast radius
  the fix claims. `flutter analyze --no-pub`: clean.
  **Not visually confirmed on a device** — the audit asked for before/after
  photographs of S-11 and this fix has only geometry-level proof; the
  Senior Visual Quality Specialist still owns the rendered check.

## FIXED IN SOURCE — "Show more replies" on a Moment could spin forever (2026-09-18 sweep, fixed 2026-09-19)

Audit ID S-09 (P2) from the Build 33 pre-redesign polish sweep, "futures"
slice. Fixed in source on branch `polish/build-33`; commit
`polish/build-33 (pending)`.
Full report: `yovoice-evidence/2026-09-18/polish-33/fix-futures.md`.

**Symptom.** On the expanded Moment (`MomentDetailScreen`), tapping *Show more
replies* / *Pokaż więcej odpowiedzi* and then leaving and re-entering the app —
or returning from a pushed route, or hitting Retry — left the control as a
permanently disabled spinner. Every later tap on it was silently rejected for
the rest of the screen's life, so the rest of the conversation became
unreachable without backing out of the Moment entirely. The window is small but
entirely ordinary: it is any app-resume or route-return that lands while a
replies page is still on the wire, which on a slow connection is most of them.

**Cause.** `_loadMoreComments` owned `_loadingMore` on exactly two paths — the
success `setState` and the `catch` — and both of them sit *behind* the
staleness guard `if (!mounted || generation != _viewLoadGeneration) return;`.
A canonical refresh (`_loadView`, fired by resume, route return or retry)
increments `_viewLoadGeneration`, so a page that comes back afterwards returns
early and never clears the flag. The flag is also the method's own re-entry
guard (`if (service == null || cursor == null || _loadingMore) return;`), which
is what turns a stuck spinner into a dead button.

**Fix.** One `finally` in
`lib/features/moments/presentation/screens/moment_detail_screen.dart`:

```dart
} finally {
  if (mounted && _loadingMore) {
    setState(() => _loadingMore = false);
  }
}
```

Dart runs `finally` on the early `return`s too, so the stale page is still
correctly discarded — only the control is released. This cannot stomp a newer
request, because the re-entry guard keeps `_loadMoreComments` single-flight:
the sole writer of `_loadingMore = true` is the very call whose `finally` this
is. It is the same shape `MomentCommentsScreen._loadComments`
(`moment_comments_screen.dart:227-231`) has carried since it was written — the
detail screen simply never got it.

The audit's optional second half — also resetting `_loadingMore` inside
`_openNeighbour`'s `setState` — was **deliberately not taken**. It would break
the single-flight invariant the `finally` relies on (a swap could clear the
flag, a tap on the new Moment could start a second page, and the first page's
`finally` would then release a request that is still running). With the
`finally` alone, a neighbour swap mid-page self-heals as soon as the stale page
settles, and `onLoadMore` is null in the meantime anyway, because
`_openNeighbour` clears `_nextCommentCursor`.

No copy was added or changed (the button and its failure snackbar already exist
in EN and PL), no layout, no colour token, no schema, no Functions change.

**Regression test.** `test/moment_canonical_refresh_test.dart` — "a canonical
refresh landing mid-page never strands the load-more control", run at both
layouts that host the conversation: stacked under the player (390×844) and in
the wide thread panel (1440×1000). It taps the control, fires a resume while
the page is in flight, completes the superseded page, and then asserts that the
superseded rows are still discarded, that the spinner is gone, that
`onPressed` is non-null, and that a further tap really does issue a new
request. Mutation-proved: with the `finally` body disabled, both variants fail
on the surviving `CircularProgressIndicator`.

## FIXED IN SOURCE — a like left the NEXT Moment unlikeable (2026-09-18 sweep, fixed 2026-09-19)

Audit ID S-09b (P2), found while fixing S-09 in the same file — the identical
in-flight-flag defect one method away. Fixed in source on branch
`polish/build-33`; commit `polish/build-33 (pending)`.
Full report: `yovoice-evidence/2026-09-18/polish-33/fix-futures.md`.

**Symptom.** On the expanded Moment, tapping the heart and then handing off to
the next Moment from the queue *before the like round trip answers* left the
new Moment's like chip dead — permanently, for the life of the screen. Nothing
told the viewer; the heart simply stopped responding to taps.

**Cause.** Exactly S-09's shape in `_toggleLike`
(`lib/features/moments/presentation/screens/moment_detail_screen.dart`). Both
paths that clear `_liking` sit behind an identity guard — the success path
returns on `if (!mounted || _moment.id != previous.id) return;` and the `catch`
only rolls back `if (mounted && _moment.id == previous.id)`. `_openNeighbour`
replaces `_moment`, and its reset `setState` does not list `_liking`, so a
hand-off during the round trip strands the flag. `_liking` is also what
disables the control (`onTap: _liking ? null : () => ...`), so a stranded flag
is a dead heart.

**Fix.** The same guarded `finally`:

```dart
} finally {
  if (mounted && _liking) {
    setState(() => _liking = false);
  }
}
```

Safe for the same reason: `if (_liking) return;` at the top keeps `_toggleLike`
single-flight, so the only writer of `_liking = true` is the call whose
`finally` this is, and its request has already settled by the time it runs. The
stale answer is still correctly prevented from writing into the Moment the
viewer moved to — only the control is released. No copy, no layout, no colour
token, no schema, no Functions change.

**Regression test.** `test/moment_playback_currency_test.dart` — "a like answer
that lands after the hand-off leaves the next Moment likeable", using that
file's existing hand-off harness with a `HomeFeedService` double whose
`setLike` is held open by a `Completer`. It likes the current Moment, hands off
to the neighbour while the call is in flight, completes it, then asserts both
halves: the stale answer wrote nothing for the new Moment, and a fresh tap on
the heart really does issue `setLike('m-next')`. Mutation-proved: with the
`finally` body disabled the case fails on that second `setLike` never arriving.

## FIXED IN SOURCE — in Pearl the avatar initial was invisible, and a screen reader read every row's identity twice (2026-09-18 sweep, fixed 2026-09-19)

Audit IDs A-26 (P2) and A-23 (P3) from the Build 33 pre-redesign polish sweep,
"accessibility" slice. Fixed in source on branch `polish/build-33`; commit
`polish/build-33 (pending)`.
Full report: `yovoice-evidence/2026-09-18/polish-33/fix-accessibility.md`.

Both defects live in `lib/shared/widgets/profile/user_avatar.dart` — the one
widget every avatar in the app is drawn by (98 call sites in `lib/`, plus
`DecoratedUserAvatar`, which delegates to it). One behaviour-only change each
therefore fixes every list, sheet, header and preview at once, without touching
a caller. No copy, no layout, no colour token, no schema, no Functions change;
nothing new is shown to the user, so **no localization key was added** — the
fixes change how existing content is announced and painted, not what it says.

- **A-26 (P2) — in Pearl the fallback initial was white on a near-white
  disc.** Eleven avatar call sites pass `palette.surfaceSunken` as the fill
  (Chats ×2, Friends ×2, Add friend, Blocked users, friend suggestions ×2, the
  friend profile ×2, Edit profile); in Pearl that token is `#E9E1EF` and the
  initial was hard-coded `Colors.white` — a measured **1.27:1**, i.e. nothing
  to see. Pearl is user-reachable, not theoretical: Settings → Appearance
  offers System / Dark / Light. The fallback foreground is now derived from the
  fill it is painted on, with the same estimate Material uses for its own
  foregrounds — `ThemeData.estimateBrightnessForColor(backgroundColor) ==
  Brightness.light ? AppColors.contrastInk : Colors.white` — following the
  pattern already established at `room_control_dock.dart:113-118`.
  `AppColors.contrastInk` (`#211629`) on `#E9E1EF` measures **13.6:1**. Every
  fill used anywhere in the app today is dark, so **Dark output is
  byte-identical** (white on `#0C0814` = 19.8:1, white on the widget's default
  `#64258E` = 9.56:1). Using the named token rather than the hex the audit
  suggested also keeps `test/semantic_color_source_guard_test.dart` green — it
  rejects a raw semantic-token literal anywhere under `lib/shared/widgets`.
  Deliberately left alone, because they are contrast-safe and changing them
  would be restyling: the default `backgroundColor` at `user_avatar.dart:22`,
  the gradient rings, and the identity fills in `chat_screen.dart:3963`,
  `podcast_studio.dart:176` and `broadcast_roster.dart:39`.
- **A-23 (P3) — a screen reader read every list row's identity twice.** The
  fallback initial is a `Text`, so it contributed a label of its own and
  TalkBack/VoiceOver announced "K, Kamil, online" on rows whose adjacent title
  already says "Kamil". The whole fallback — the initial *and* the placeholder
  icon — is now wrapped in `ExcludeSemantics`: the letter is still painted, it
  simply stops being announced, and the name beside it carries the identity.
  Harmless where an ancestor already excludes. The audit's other half was
  **rejected on purpose**: a `semanticLabel` in `profile_media_image.dart`
  would put the name back into the merged row a second time, which is the same
  defect in a new place.
- **Audit-ID mapping, so nothing looks fixed twice.** A-24 ("an emoji display
  name renders a broken initial") is the same defect as **A-13**, already fixed
  and documented by the "avatars" slice further down. This slice re-verified it
  and mutation-proved it rather than re-applying it. Its second file —
  `profile_photo_viewer.dart:181` — is **obsolete**, not skipped: A-02 replaced
  that viewer's initial-letter fallback with resolution-aware states, so the
  `displayName[0]` line no longer exists (`git show fe98e651:` still has it at
  line 182). `name[0].toUpperCase()` does survive at 14 occurrences in 12 other
  files, including `profile_screen.dart:716` — every one of them another
  slice's file; worth a follow-up.

Regression coverage, mutation-proved: `test/user_avatar_fill_test.dart`, groups
"the fallback foreground follows the fill" (3 cases; 2 fail with the ternary
collapsed back to `Colors.white`) and "the fallback mark is decoration, not an
announced label" (2 cases; the row case fails without the wrapper — the
compiled row label is then literally `K\nKamil\nonline`). The semantics case
reads the **compiled** semantics tree via `test/semantics_probe.dart`, not the
`Semantics` widgets, because the initial's node is not a boundary: it merges
into the row rather than sitting beside it, which a widget-level assertion
cannot see.

**UNVERIFIED on a device, twice over.** No screen has been opened in Light
appearance to look at the fixed initial, and no TalkBack/VoiceOver pass has
been run on the Friends/Followers lists. The contrast numbers are computed from
the palette source and the painted `TextStyle.color` is asserted in a widget
test; that proves the value, not the pixels. The device proof owed by the
"avatars" and "profile" slices covers these changes too.

Optional follow-up, deliberately not done because it is another slice's file:
`messages_screen.dart:1520-1523` still works around this very bug by swapping
the *fill* in light mode; it can now go back to plain `palette.surfaceSunken`
like the other ten lists.

## FIXED IN SOURCE — you could not look at the person you were about to accept, invite or promote (2026-09-18 sweep, fixed 2026-09-19)

Audit IDs A-18 (P2), A-19 (P2) and A-20 (P3) from the Build 33 pre-redesign
polish sweep, "missing" slice. Fixed in source on branch `polish/build-33`;
commit `polish/build-33 (pending)`.
Full report: `yovoice-evidence/2026-09-18/polish-33/fix-missing.md`.

The app's one answer to "who is this?" is the profile preview sheet, reached by
tapping an avatar. Three surfaces had the avatar and not the tap, and all three
are exactly the places where the viewer is being asked to make a decision about
a stranger.

- **A-18 (P2) — a friend request showed a name, an avatar and Accept/Decline,
  and nothing opened the sender's profile.** Both inboxes were affected: the
  Friends screen's Requests tab (`FriendRequestCard`, used by the coordinated
  scroll and the tablet/desktop two-pane list) and the Activity inbox's own
  request card. **The fix** promotes the sender's avatar — and only the avatar
  — to a named profile action. `FriendRequestCard` gained an *optional*
  `onOpenProfile`, so the layout-only harness at
  `test/content_zoom_responsive_test.dart` keeps compiling and renders an inert
  avatar rather than tapping into unresolvable Firebase singletons. Both
  `FriendsScreen` call sites pass a `_previewRequester` that runs through the
  screen's existing `_runNavigation` guard and hands the preview the screen's
  already-injected `firestore`/`auth`/`FriendService`/`MessageService`/
  `ProfileMediaService` — never the global singletons — exactly as
  `ChatScreen` does for its header avatar. `NotificationsScreen` gained the
  same wiring plus optional test-only `firestore`/`auth` seams, matching the
  `currentUserId` seam already documented on that widget.
- **Why the avatar and not the row.** The name shares its column with the
  request line and, on the Friends card, with Accept/Decline; the inbox card
  keeps its trailing accept/decline icon buttons. Wrapping the identity row
  would have swallowed taps aimed at those. The discs are already 54 px
  (Friends) and 50 px (Activity), so each target was created at its existing
  size and nothing reflowed.
- **A-19 (P2) — inside one screen the Moment author's avatar opened a profile
  and the commenters' avatars did nothing.** Only an `@mention` inside a reply
  body was tappable, so a person who commented without being mentioned was
  unreachable. **The fix** wraps `MomentCommentRow`'s avatar in the
  established `AccessibleTapRegion` pattern and routes it through the row's
  existing `onMentionTap` seam, whose documented default is already the
  app-wide preview sheet — no new plumbing, and the same "open this person"
  contract for a tapped name and a tapped face. A comment with an empty
  `authorId` stays inert, mirroring the guard the identity badges in the same
  row already apply: `ProfilePreviewSheet` does `.doc(userId)` and would
  assert on an empty id.
- **A-20 (P3) — the server invite sheet and the member management list showed
  people you could invite or promote without letting you look at them first.**
  **The fix** makes each leading avatar a profile action in both sheets, and
  leaves every other control alone: the invite tile still has no tile-level
  `onTap` (the trailing Invite button stays the single primary action) and the
  member row keeps its role/ban/remove menu. The preview is read-only, so it
  stays live while a row is sending. Both sheets gained optional test-only
  `firestore`/`auth` seams for the same reason `NotificationsScreen` did.
- **What deliberately did NOT change.** No restyle, no palette or type change,
  no schema or Cloud Functions change, and no new localization catalog keys —
  the labels reuse phrasings the app already ships (`Open profile` /
  `Otwórz profil`, `Open profile for {name}` / `Otwórz profil: {name}`). Two
  further comment-avatar surfaces named in the audit,
  `moment_comment_preview.dart` and `MomentCommentsInline` in
  `moments_feed_view.dart`, were left alone on purpose: nothing in production
  constructs either (`MomentCard.commentPreview` has no caller and
  `MomentDetailPanel` is never instantiated), their avatars are 22–28 px, and
  giving them a 44 px target would reflow compact rows — a restyle this slice
  forbids.
- **Known cosmetic consequence, pending a rendered look.** Three of the five
  avatars were already ≥ 44 px and are pixel-identical. The two `radius: 20`
  avatars — a Moments comment row and the two server list rows — grow their
  leading box from 40 px to the 44 px minimum target, shifting the adjacent
  text about 4 px. That is an accessibility floor, not a redesign, but it has
  not yet been looked at on a device: see the OPEN item below.
- **Coverage.** `test/friends_workflow_test.dart` (the requester avatar opens
  the preview, dispatches no accept/decline, and an unwired card exposes no
  target at all), `test/notifications_inbox_test.dart` (the same for the
  Activity inbox), `test/accessible_tap_region_test.dart` (a commenter avatar
  is a named 44 px action that opens that commenter; an authorless row stays
  inert) and `test/server_shell_test.dart` (invite and member rows open the
  preview and dispatch no callable). Each case asserts the sheet is absent
  before the tap and present after.

## OPEN — the "missing" slice's three surfaces still need a look on a device

Audit IDs A-18, A-19, A-20, Build 33 polish sweep. Code fixed and covered by
widget tests (above). **Updated 2026-09-19 07:30: rendered frames now exist**
— 21 real rasterised captures of the shipping widgets (real Inter face, real
theme, PL+EN, 360/834/1440 and 200 % text) plus 20 matching pre-fix frames, in
`yovoice-evidence/2026-09-18/polish-33/missing/`. They settle the layout
question by measurement: the Friends and Activity request rows are **pixel-
identical** before and after the fix at every width and text scale, and the
Moments comment column moves by **exactly 4.0 logical px**, as predicted. They
also contain the frame of the preview sheet actually opening from a request
card. A headless tester is still not a phone, so a **device pass remains
outstanding**: all three screens need a signed-in account with real data — a
genuine pending friend request, a Moment with comments, a server with members —
and the only signed-in device in the fleet is the Redmi Note 8 Pro, which runs
Build 31. Both iPad simulators and the iPhone 17 Pro simulator are signed out,
and credentials must not be entered. What still needs a real look, at narrow,
medium and wide:

- Friends › Zaproszenia and the Activity inbox with a pending request: the
  avatar's focus ring and pressed state, and that Accept/Decline are still
  comfortably hittable beside it.
- A Moments comment thread: the 4 px leading-column growth per row, at 100 %
  and 200 % text.
- The server invite sheet and the member management list: the same 4 px growth
  inside `ListTile`, and that the trailing Invite button and role menu are
  unaffected.
- VoiceOver/TalkBack on any one of them: each avatar must read as one button
  named for the person, with no duplicate announcement of the fallback initial.

## FIXED IN SOURCE — the localization catalog threw on first read in every locale, and three more polish blockers (2026-09-19)

Found by the Build 33 verification sweep on `polish/build-33`; closed in fix
round 2. Full write-up and logs in
`yovoice-evidence/2026-09-18/polish-33/fix-round-2.md`.

- **B1 (P0) — every translated string threw, English included.** The new
  `translations_profile_media_viewer.dart` defined 40 locales and omitted
  `fil`, while `app_translation_catalog.dart:285` merges it with
  `...profileMediaViewerTranslations[entry.key]!` over a driver union that
  includes `fil`. `appTranslations` is a lazily-initialised top-level `final`,
  so the null-check throw happened *inside the initializer*: the first catalog
  read in ANY locale failed and every later read re-ran it and failed again.
  The navigation dock's Chats destination, the unread badge and the chat
  header presence line rendered a Flutter error box; the other 39 non-EN/PL
  locales lost every catalog string. Before/after, same frame:
  `visual/r2-dock-moments-en-dark-402-200.png` (error box) vs
  `visual/r3-dock-moments-en-dark-402-200.png` (real glyph + "99+" badge).
  Fix: one `fil` block, wording aligned with the Filipino copy the catalog
  already ships. `test/profile_media_viewer_localization_test.dart` states the
  requirement as a set comparison that never touches `appTranslations`, so a
  future omission names the missing locale instead of crashing 28 suites.
- **B2 — a catalog key built by runtime interpolation.**
  `server_text_channel_scene.dart` passed `'Open profile for ${senderName}'`
  as the *key*, which can never be looked up outside EN/PL, so every message
  row in a server text channel fell back to raw English in 41 locales.
- **B3 — a new user-facing key that existed in no translation module.**
  `'Open profile for {name}'` was introduced on three surfaces (Moments
  comment thread, Friends requests, Activity inbox) and appeared nowhere in
  `lib/core/localization/`. Fix for both: the catalog already carried a
  reviewed `'Open profile of {name}'` in all 41 locales
  (`translations_moments_overview.dart`), with the identical Polish string
  already in use at `moments_follow_panel.dart:325`. All four sites now share
  that one key — no new copy was minted, and the tooltip that used to be a
  second, differently-worded key (`"Open {name}'s profile"`) folds into it.
- **B4** — see the entry below (translucent avatar fill).
- **B5 (a11y P1, WCAG 1.4.3 / 1.4.11) — the banner viewer's non-photo states
  were unreadable in the Pearl theme.** `profile_photo_viewer.dart` paints
  `kProfileBannerFallbackGradient` (fixed dark, `#53108C → #21102E → #09050F`)
  as the banner backdrop in BOTH themes, but took the message copy from
  `palette.textSecondary`, the icon from `palette.textTertiary` and the retry
  label from `palette.interactiveForeground` — all dark inks in Pearl, at
  1.54:1, 2.00:1 and 1.51:1 against the brightest stop. The loading spinner
  (`palette.focus`) failed the same way at 1.51:1. Fix: the banner flavour now
  takes its foreground from `AppImmersiveColors`, the token set this app
  already uses for fixed-dark routes — 11.5:1 for the copy, the retry label
  and the spinner, 5.4:1 for the icon, on the *brightest* stop. The avatar
  flavour is untouched: its backdrop is `palette.surfaceSunken`, which does
  follow the theme. Pinned in `test/profile_banner_viewer_test.dart`, which
  recomputes the ratio against all three gradient stops in both themes.
- **B6 (P1 layout) — the banner viewer overflowed and clipped its own retry
  button at 320 dp / 200 % text.** The fallback sat in a non-scrolling
  `Center` inside the `AspectRatio(16/9)` frame. Measured at 320 dp: a 288x162
  dp viewport holding a 387 dp column, with the retry button ~150 dp below the
  fold — so a RenderFlex hazard stripe was painted over the user's content and
  the viewer's only recovery affordance became unreachable, making a transient
  grant failure a dead end. Before/after:
  `visual/viewer-banner-failed-pl-dark-320-200.png` vs
  `visual/r3-viewer-banner-failed-pl-dark-320-200.png`. Fix: the message layer
  is a `SingleChildScrollView` whose `ConstrainedBox` keeps it centred
  whenever it fits and scrollable when it does not. Residual, accepted: at
  320 dp / 200 % the retry control is reachable but requires a scroll gesture
  inside the banner frame.

## FIXED IN SOURCE — a translucent avatar fill paints the initial in invisible ink (found 2026-09-19, REGRESSION on `polish/build-33`)

Found by the "missing" slice while capturing rendered evidence for A-20;
proof in `yovoice-evidence/2026-09-18/polish-33/missing/` and
`fix-missing.md`. Fixed in fix round 2 (blocker B1-B6 sweep,
`fix-round-2.md`) — the avatars slice had finished editing the file by then.
Rendered proof of the fix:
`yovoice-evidence/2026-09-18/polish-33/visual/r3-server-member-avatar-dark-720.png`
shows a legible white initial on all five server templates, and
`r3-server-member-avatar-pearl-720.png` shows Pearl unchanged.

- **What it looks like.** In the server member management list the person's
  fallback initial is invisible: disc `rgb(18,33,43)`, glyph `rgb(33,22,41)`,
  a contrast ratio of roughly 1.1:1, and the brightest pixel anywhere inside
  the disc is `rgb(19,33,43)` — there is no light glyph at all. Compare
  `missing/a20-server-members-pl-900.png` with
  `missing/before/a20-server-members-pl-900.png`, the same row at base
  `fe98e651`, where a `CircleAvatar` drew a white initial on violet.
- **Why it is a regression.** The member row's `CircleAvatar` → `UserAvatar`
  replacement (S-06 / A-11, avatars slice — correct in itself: the old widget
  dereferenced a denormalized `photoUrl`) also passes
  `backgroundColor: ServerIdentity…iconSurface`. The same defect is
  **pre-existing** in the sibling invite sheet, which has always passed
  `colors.iconSurface` (`missing/a20-server-invite-pl-390.png`).
- **Root cause, one line.** `iconSurface` is `primary.withValues(alpha: .12)`
  in dark mode (`server_identity.dart:99`) — a *light* colour at 12 % alpha.
  `UserAvatar` chooses its foreground with
  `ThemeData.estimateBrightnessForColor(backgroundColor)`
  (`user_avatar.dart:72`), which reads RGB and ignores alpha: it sees a light
  fill, picks `AppColors.contrastInk` (`#211629`), and paints dark ink on a
  disc that composites to near-black. Every caller passing a translucent fill
  is affected.
- **Blast radius: 9 `UserAvatar` call sites**, all in Servers, all passing
  `colors.iconSurface` — `server_invite_sheet.dart`,
  `server_management_sheet.dart`, `server_text_channel_scene.dart`,
  `server_voice_stage.dart`, `server_community_stage.dart`,
  `server_podcast_stage.dart` (×2), `server_company_meeting.dart` (×2).
- **Proposed fix**, a no-op for every opaque caller (`Color.alphaBlend` is the
  identity when the top colour is opaque, so the eleven `surfaceSunken` callers
  and every constant-colour caller are untouched; only the translucent server
  fills change, and only in their foreground):

  ```dart
  final resolvedFill = Color.alphaBlend(
    backgroundColor,
    Theme.of(context).colorScheme.surface,
  );
  final onFill =
      ThemeData.estimateBrightnessForColor(resolvedFill) == Brightness.light
      ? AppColors.contrastInk
      : Colors.white;
  ```

  Applied verbatim in `user_avatar.dart`. `test/user_avatar_fill_test.dart`
  gained a "a translucent fill is judged after it composites" group that walks
  every `ServerType`, asserts the Dark fill is still translucent (otherwise the
  case proves nothing), and pins white ink in Dark / `contrastInk` in Pearl,
  plus an opaque-fill case proving the eleven `surfaceSunken` callers are
  byte-identical.

## FIXED IN SOURCE — your own profile photo and your banner could never be opened, and the banner crop was not WYSIWYG (2026-09-18)

Owner report, verbatim: "wszystko ma działać, nawet takie drobiazgi jak podgląd
zdjęcia profilowego w każdej sekcji, i zdjęcia w tle tak samo". Audit IDs A-01,
A-02 and A-03 from the Build 33 pre-redesign polish sweep
(`yovoice-evidence/2026-09-18/polish-33/audit-avatars-code.md`). Fixed in source
on branch `polish/build-33`; commit `polish/build-33 (pending)`.

- **A-01 (P2) — tapping your own avatar on the Profile screen did nothing.**
  Evidence: `redmi/02-profile-avatar-tap.png` (Build 31). Every *other* person's
  avatar opens the profile preview, and a friend's photo opens the fullscreen
  viewer, but the owner's own avatar in `profile_header.dart` was a bare
  `Container` + `UserAvatar` with no gesture — there was no way anywhere in the
  app to enlarge your own profile photo. Fix: wrap that Container (key
  `profile-header-avatar` deliberately left where it is — two layout tests hang
  off it) in the existing `ProfilePhotoButton`, mirroring
  `profile_preview_sheet.dart`. `minimumSize` is the *ring*, not the disc
  (`(avatarRadius + ringPadding) * 2`), so the ripple is not clipped inside the
  gradient border and the target is >= 66 pt at every breakpoint. EN+PL copy
  comes from `ProfilePhotoButton`'s existing template pair — no catalog key
  added. Test: `test/profile_photo_viewer_test.dart`, "the owner can open their
  own profile photo from the header". RED with the wrapper removed
  ("Found 0 widgets with key [<'profile-photo-viewer-close'>]"), GREEN with it.
- **A-02 (P2) — the banner ("zdjęcie w tle") had no viewer anywhere in the
  app.** `ProfileBanner` painted it and nothing could open it, on any screen.
  Fix, three parts: (1) `showProfilePhotoViewer` takes a `ProfileMediaKind`
  and `showProfileBannerViewer` forwards `banner`; the dialog's frame is now
  `16/9` for banners (`ProfileImageRules.banner`) instead of a hard-coded 1,
  the grant it requests carries `kind: banner`, and the banner's no-photo
  fallback is `kProfileBannerFallbackGradient` — never the initial-letter
  block, which is wrong in a 16:9 frame. Copy is banner-specific in both
  languages (`Background photo of {name}` / `Zdjęcie w tle: {name}`,
  `Close background photo` / `Zamknij zdjęcie w tle`), because reusing the
  avatar wording would mislabel it in the title *and* in the Semantics route
  name. (2) A new `ProfileBannerButton` (rectangular, 22px radius, the
  header's own) wraps the header's banner card. (3) The viewer no longer
  guesses why there is no picture: `ProfileMediaImage` reports
  `pending / available / absent / failed` through a new optional
  `onResolution` callback (null at every existing call site, so nothing else
  changes), and the dialog shows a spinner, "No background photo yet" /
  "Brak zdjęcia w tle", or "Photo unavailable" + **Try again** accordingly.
  Tests: `test/profile_banner_viewer_test.dart` (4) and the new cases in
  `test/profile_photo_viewer_test.dart`. RED with either wrapper reverted.
  **Correction to the audit's own advice, measured not assumed:** the audit
  predicted that wrapping the whole banner card would make taps on the user's
  name plate open the banner, because "a decorated `Container` does not answer
  hit tests". It does — `RenderDecoratedBox.hitTestSelf` delegates to
  `BoxDecoration.hitTest`, which returns true inside the plate's rounded rect.
  A hit-test dump at a point on the plate that is *inside* the banner's
  rectangle shows `RenderDecoratedBox` as the deepest target, so no separate
  tap strip was needed. `test/profile_banner_viewer_test.dart`, "the name plate
  never falls through to the banner viewer", pins that: it asserts the probe
  point really is over the banner *and* that nothing opens.
- **A-03 (P3) — the banner crop editor was not WYSIWYG.** The upload stores
  16:9 (`ProfileImageRules.banner`) but `ProfileHeader` paints a fixed-height
  band at content width — about 3.3:1 on a phone and 7.6:1 at the 1040dp feed
  cap — with `BoxFit.cover`, so only the centre ~52% (phone) to ~23% (wide) of
  the crop the user deliberately composed ever appears. The crop editor showed
  no guide, and `profile_image_rules.dart` still described a `SizedBox(height:
  320)` full-bleed header that no longer exists. Fix, behaviour only: the band
  geometry stops being two magic numbers (`ProfileHeader.gutter`,
  `bannerHeightCompact`, `bannerHeightWide`, and `bannerSafeBandFraction`
  *derived* from the stored ratio, `ResponsiveContentWidth.feed` and the wide
  band height, so it cannot drift); `ImageCropScreen` draws a horizontal
  safe-band guide for `ProfileImageKind.banner` only — the mirror image of the
  shipped room-cover `COMPACT SAFE` overlay — dimming what will be trimmed and
  labelling the surviving strip `ALWAYS VISIBLE` / `ZAWSZE WIDOCZNE`. The band
  is a fraction of the frame, so on a short band at large text sizes the pill
  steps aside instead of being clipped; the same sentence is carried for
  screen-reader users on the preview's Semantics label, where it costs no
  vertical space (an explanatory footer line pushed Cancel/Use photo off a
  390x844 phone at 200% text, which the existing test correctly caught). 16:9
  stays the stored format on purpose — it is the superset, so a redesign can
  change the band without asking anyone to re-upload. Tests: four cases in
  `test/image_crop_screen_test.dart`, including one that re-derives the
  surviving fraction from `ResponsiveContentWidth.feed` and the header
  constants and asserts the drawn guide matches it, one PL case, one avatar
  case proving the guide is banner-only, and one 320px/200%-text case. RED
  with the overlay removed.
- **Not verified on a device.** None of this is in an installed build (the
  Redmi Note 8 Pro runs Build 31); the proof is widget tests plus rendered
  pixels (`RepaintBoundary.toImage`, real Inter + MaterialIcons) at 320, 390,
  834, 1280 and 1440 px in `yovoice-evidence/2026-09-18/polish-33/fix-own/`.
  The gestures on a real phone are UNVERIFIED until Build 33 is installed.

## FIXED IN SOURCE — one network blip during cold start left a screenful of initials for the whole session (2026-09-18 sweep, fixed 2026-09-19)

Audit ID A-22 (P2) from the Build 33 pre-redesign polish sweep, "pipeline" slice.
Fixed in source on branch `polish/build-33`; commit `polish/build-33 (pending)`.
Full report: `yovoice-evidence/2026-09-18/polish-33/fix-pipeline.md`.

- **A-22 (P2) — a failed profile-media grant was never retried.**
  `ProfileMediaImage` asked `getProfileMediaAccess` once per resolution and, on
  failure, deliberately kept the last image (or the initial) and waited. The
  only things that ever re-resolved were a new identity, a new
  `publicProfiles` revision, an access boundary, or the fullscreen viewer's
  manual Retry (T-6/A-06/A-07 below). So a single `unavailable` during app
  bootstrap — exactly when every avatar and banner on Home, Chats, Friends and
  the profile surfaces resolves at once — painted initials that stayed until
  the user restarted the app. Avatars in a list have no Retry affordance at
  all, so there was no way back.
- **The fix.** One production file,
  `lib/shared/widgets/profile/profile_media_image.dart`: a `_retryTimer` plus
  an attempt counter, and `_resolve({bool isRetry = false})` which resets the
  counter for every *fresh* resolution. A failed grant now schedules at most
  two automatic re-resolutions, ~2 s and ~8 s later. No UI, copy, colour or
  layout change — the widget renders exactly what it rendered before, it just
  stops giving up after one try.
- **What is deliberately *not* retried, and why.** `permission-denied` is the
  normal, permanent answer for friends-only visibility and for blocks
  (`functions/profile/media.js`), and retrying it would triple callable traffic
  against the 180-per-minute per-caller budget (`PROFILE_MEDIA_ACCESS_LIMIT`)
  to hear the same "no" — so it, `resource-exhausted` and every other decided
  Firebase code fail closed. `FormatException` (the client rejected the
  response shape) and every `Error` — notably the `StateError` raised when the
  cache is cleared mid-flight, i.e. logout — also fail closed. Retried:
  `unavailable`, `internal`, `deadline-exceeded`, `aborted`, `unauthenticated`,
  `cancelled` and raw transport failures (socket/TLS/timeout).
- **Logout stays fail-closed.** The queued retry is cancelled in `dispose()`
  and on any access boundary, and the timer callback re-checks the resolution
  generation before firing, so a retry queued before a logout resolves into a
  no-op rather than a second callable. Without both, a global boundary produced
  two extra grant calls after sign-out (proved by mutation).
- **Coverage** in `test/profile_media_access_test.dart`: a transient
  `FirebaseFunctionsException` followed by a good grant recovers the photo on
  its own (calls 1 → 2 after 2 s); `permission-denied` stays at one call after
  10 s; a logout boundary during a pending retry leaves it at one call with no
  pending timers; and a table test pins the full retryable/permanent code
  split. All three fail without the fix.

## FIXED IN SOURCE — an emoji display name drew a tofu box where the avatar initial belongs (2026-09-18 sweep, fixed 2026-09-19)

Audit ID A-13 (P3) from the Build 33 pre-redesign polish sweep, "avatars" slice.
Fixed in source on branch `polish/build-33`; commit `polish/build-33 (pending)`.
Full report: `yovoice-evidence/2026-09-18/polish-33/fix-avatars.md`.

- **A-13 (P3) — `UserAvatar._initial` took the first UTF-16 *code unit*, not
  the first grapheme cluster.** For any display name not starting with a BMP
  character, `name[0]` is half a surrogate pair — an unpaired high surrogate,
  which every renderer draws as a tofu/replacement box where the initial
  belongs. A decomposed accent was silently dropped the same way — `Źaneta` fell back to a bare `Z`. This is a reachable
  production state, not a theoretical one: `resolveAuthProfileName` deliberately
  **accepts** a display name that is a single emoji, which
  `test/auth_profile_identity_test.dart` pins. The rule now reads
  `name.characters.first.toUpperCase()`. No copy, colour, size or layout change
  — the same glyph box, a complete glyph inside it.
- **How it got in, and why it was app-wide.** The in-app incoming-message
  banner used to build its own `_IncomingMessageAvatar`, which took the initial
  with `characters.first`. When that banner moved to the canonical `UserAvatar`
  (S-08 below) the widget was deleted and its grapheme-safe rule went with it.
  Because `UserAvatar` is *the* avatar in this app, the weaker rule it already
  carried then applied to every fallback initial on every surface — Chats,
  Friends, server member lists, the notification banner, Settings and Creator
  Studio — not just to the banner that triggered the move.
- **Audit-ID mapping, so nothing looks fixed twice.** A-09, A-10, A-11 and the
  first half of A-13 — the four surfaces that could never render a photo at all
  — are the same four defects as S-03 / S-04 / S-06 / S-08, already fixed in
  this same pass by the "profile" slice; see that entry further down. The
  "avatars" slice re-verified them against its own findings and changed nothing
  there. One deliberate difference between the two sibling heroes was left
  standing and is **not** a bug: Creator Studio passes
  `premium: profile.premiumIdentity` (matching `profile_header.dart`) while the
  Settings hero does not. Both sit inside their own gradient ring, so this is a
  presentation choice for the redesign to settle, not behaviour.

Regression coverage, mutation-proved against the unfixed rule:
`test/user_avatar_fill_test.dart` (+4 cases — emoji, regional-indicator flag,
decomposed accent, and a control case pinning that plain, accented-precomposed
and blank names are unchanged; 3 of the 4 fail before the fix) and
`test/active_conversation_notification_test.dart` (+2 cases, which pump the real
`YoTopNotificationHost` rather than a bare avatar: the sender resolves by uid
through `ProfileMediaImage`, the avatar measures exactly 38x38 in the host's
fixed leading slot, and an emoji sender name yields a readable initial — the
last one fails before the fix).

**UNVERIFIED on a device.** `flutter analyze` and the widget tests prove the
string the app renders, not how a screen looks. No build carrying this change
has been installed on `6tq4g6f6ijrwxwzx` (still Build 31) or on a signed-in
simulator — deliberately, because several agents were editing `lib/`
concurrently and a build from that worktree would not be a build of any
coherent revision. The device proof owed for S-03/S-04/S-06/S-08 covers this
change too.

## FIXED IN SOURCE — the friend-profile banner band could never grow past its phone size (2026-09-18 sweep, fixed 2026-09-19)

Audit ID A-04 (P2) from the Build 33 pre-redesign polish sweep, "other" slice —
the verification pass over the banner band the "profile" slice had just added to
`friend_profile_screen.dart` (see R-03 / T-5 further down). Fixed in source on
branch `polish/build-33`; commit `polish/build-33 (pending)`. Full report:
`yovoice-evidence/2026-09-18/polish-33/fix-other.md`.

- **A-04 (P2) — the band's wide branch was unreachable, so every tablet and
  desktop drew the phone band.** `_banner()` chose 168 px over 116 px at
  `constraints.maxWidth >= 900`, but this screen's content lives inside
  `ResponsiveContentFrame(width: ResponsiveContentWidth.list)` — 880 px — and
  pays a 20 px gutter on each side, so the widest band the builder can ever be
  handed is 840 px. The 168 px branch was dead code at every window size,
  2560 px included. The breakpoint is now 700 px, the first step above a 768 pt
  tablet's 728 px band, and the comment now states the measure so the next edit
  does not reintroduce a window-sized threshold. Palette, corner radius, copy,
  semantics and the tap target are untouched — behaviour only, no restyle.
- **Regression coverage for the band itself.**
  `test/friend_profile_responsive_test.dart` now pins, at 390 / 768 / 1440:
  the band exists and carries the friend's uid; it resolves through the
  screen's injected `ProfileMediaService` rather than the one
  `ProfileMediaImage._resolve()` would otherwise build for itself (without the
  injection the widget's `mediaService` is null and any test fake is bypassed);
  the grant request carries `userId` and `kind: banner` and nothing else — no
  durable or bearer URL; the band stays above the avatar and spans the content
  measure; and the 390 band is shorter than the 768 one, which equals the 1440
  one, because the 880 px measure and not the window is what caps it. All three
  were mutation-proved: breakpoint back to 900, injected service removed, band
  removed from the sliver — each makes the test fail.

**Rendered, not device-verified.** The band was rendered and captured from the
real `FriendProfileScreen` widget tree at 390 / 768 / 1440 px. It has **not**
been opened on the Redmi Note 8 Pro (still Build 31) or on a signed-in
simulator in this run, so how a *real uploaded* banner photo looks inside the
band on a device stays UNVERIFIED.

## FIXED IN SOURCE — Home mixed both heading arrangements on one page (2026-09-18)

Audit ID T-2 (P3) from the Build 33 pre-redesign polish sweep. Fixed in source
on branch `polish/build-33`; commit `polish/build-33 (pending)`.

- **T-2 (P3) — at a 1032 pt window with 200 % text, "Twoi znajomi" pushed
  "Zobacz wszystkich ›" onto a second, right-aligned row while "W Twoich
  serwerach" and "Ostatnie czaty" kept "Zobacz wszystkie ›" on the heading
  line.** One page, both arrangements — the thing `docs/UI.md` says never
  happens. `_RenderSectionHeader._stacksAt`
  (`lib/features/home/presentation/widgets/shared/home_section_header.dart`)
  answered the third-of-the-row width test against the action's OWN rendered
  width, and the doc justified that with "every heading on a page carries the
  same label". That stopped being true when the Polish animate declension
  landed: the friends rail says "Zobacz wszystkich", servers and chats say
  "Zobacz wszystkie". Measured with real Inter at 200 % text, the two buttons
  are 275.70 pt and 260.11 pt wide (compact ramp), so they stack below content
  widths of 851.10 pt and 804.34 pt respectively — and MobileHome clamps its
  content to `ResponsiveContentWidth.list` (880) minus the medium gutter
  (24 x 2) = **832 pt for every window >= 880 pt**, which sits inside that
  gap. So the mix was not a 1032-only curiosity: it was every MobileHome
  window from ~852 pt upwards at >= 160 % text. Fix: the header now measures
  the whole "View all" vocabulary the page can carry (`copy.homeSeeAll`,
  `copy.homeSeeAllPeople` and the neutral default) with a `TextPainter` at the
  button's own resolved style and the ambient `TextScaler`, adds the button's
  fixed chrome (2 px gap + chevron + 2 x 8 px padding, floored at the 44 px
  target), and passes that page constant to the layout as
  `arrangementActionWidth`. The verdict is answered against the constant; the
  action's REAL size still drives `reserve` and placement, so the
  24 / titleInk / 16 rhythm is untouched and the box height is unchanged in
  the inline case. Consequence, accepted and intended: inside the straddle
  band every Home heading now stacks, because the widest label decides — "the
  page answers the test once". No copy changed (the declensions are correct
  and stay); no catalog key added. Tests: two cases in
  `test/home_rhythm_test.dart` sweep 320 → 1456 pt in 16 pt steps (plus 430,
  834, 1032) at 200 % text in Polish, for both type ramps, and assert that the
  people, servers and neutral headings pick the SAME arrangement — never which
  one, so the assertion is font-independent and holds under the stub test font
  and real Inter alike. RED with the verdict reverted to `actionSize.width`
  ("arranged differently at 1344 pt" compact, "1408 pt" expanded — the stub
  font's straddle band), GREEN with the fix. Rendered proof (real painted
  pixels in real Inter, `RepaintBoundary.toImage`) before and after, both for
  the three headings at the production 832 pt content box and for a populated
  `MobileHome` at 1032 pt in Polish at 200 % text, in
  `yovoice-evidence/2026-09-18/polish-33/fix-home/`. The stale rule is
  corrected in `docs/UI.md` and in the widget's own doc comment. **Not
  verified on a device or a simulator**: the fix is not in any installed build
  (Redmi runs Build 31), and DesktopHome's own columns were checked by
  arithmetic and widget test rather than by screenshot — at 280-344 pt both
  declensions stack, so no desktop column falls in the mixing band.

## FIXED IN SOURCE — the floating dock mislabelled itself and left a dead band at 200 % text (2026-09-18 sweep, fixed 2026-09-19)

Audit ID T-1 (P3 as filed, P1 in the tablet audit table) from the Build 33
pre-redesign polish sweep,
`yovoice-evidence/2026-09-18/polish-33/audit-ipad.md`. Fixed in source on
branch `polish/build-33`; commit `polish/build-33 (pending)`. Evidence,
including before/after renders at the reported geometry:
`yovoice-evidence/2026-09-18/polish-33/fix-navigation.md`.

- **T-1a — the expanded caption named whichever destination sat in the
  middle.** Above the large-text threshold the dock replaces the five compact
  labels with one caption band under the icon row
  (`lib/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart`).
  The band is laid out full width, and its single `Text` was wrapped in a
  `Center`, so a short caption was drawn in the middle of the bar no matter
  which destination it named. On iPad Pro 13" portrait, Dark, Polish, 200 %
  text with Home selected, the caption `Start` sat directly under the Chats
  icon — 182 pt away from the Home bead it belonged to, and under the one icon
  that also carries the unread badge. Fix: the caption keeps its full-width
  band (`expandedLabelHeight` reserves the bar's height against that width, so
  narrowing the band would clip long Polish and Vietnamese captions) but is
  now positioned with an `Align` whose x is derived from the shown slot's own
  centre. A caption that fills the band still resolves to centre, a short one
  slides under its destination, and the clamp to [-1, 1] keeps the existing
  in-bounds assertions true.
- **T-1b — a tab with no dock destination left a tall empty box.** Friends and
  every other tab outside the five visual slots resolve to no accepted slot, so
  the painter draws neither bead nor socket (`center: null`). The five 92 pt
  destination tiles were still pinned to `top: 0`, which is correct while a
  bead anchors the row to the top edge of the bar — but at 200 % text the bar
  grows to 154 pt, so the icons hung under the top outline with ~45 pt of empty
  bar below them, and the Chats unread badge rode the top edge. Fix: only when
  the dock is expanded **and** nothing is selected, the tile row is offset so
  the resting icons are centred in the bar body; the offset is clamped so the
  tiles — icon, `InkWell` hit area and focus ring together — stay inside the
  bar. The dock's height, its reserved height for the host, and the compact
  (100 % text) dock are untouched: the 100 % renders are byte-identical before
  and after the fix.

Behaviour only — no restyle, no new widget, no copy and no new localisation
key (the caption already uses the shipped `home`/`chats`/`more` strings, EN and
PL). Tests: `test/yo_floating_navigation_dock_test.dart` gains six cases —
icon-row centring at 1032 pt / 200 % in EN and PL, a compact-dock guard, and
caption ownership in EN, PL and Arabic (RTL). Each was mutation-proved:
reverting the tile offset fails the two centring cases by exactly 28 pt,
reverting the `Align` fails all three caption cases by exactly 182 pt, and in
both mutations every other case in the file still passes. `flutter analyze`
is clean for both changed files.

**Not closed by this fix:** the same 200 % bar is still top-weighted *while a
destination is selected* — the bead must stay in its socket on the top edge, so
the icons cannot move and the caption band fills the lower half. That is a
layout question for the Slim redesign, not a correctness defect. The device
re-render of iPad Pro 13" portrait (replacements for evidence `05`, `07`, `09`)
was **not** run: YO Voice is not installed on any booted simulator and the
preview-harness build measured ~50 min under this machine's load. The proof
here is a real-engine render of the production widget at the reported geometry,
not a device capture.

## FIXED IN SOURCE — profile photos and banners: no grant survived a slow device clock, and nothing opened a banner (2026-09-18)

Audit IDs R-01, R-02/S-01, R-03/T-5, R-07, T-3, T-6/A-06/A-07, S-03, S-04, S-06,
S-08 (P1–P3) from the Build 33 pre-redesign polish sweep, "profile" slice. Fixed
in source on branch `polish/build-33`; commit `polish/build-33 (pending)`. Full
report: `yovoice-evidence/2026-09-18/polish-33/fix-profile.md`. **Not yet
verified on a device — see the UNVERIFIED note at the end of this entry.**

- **R-01 (P1) — a device clock running a couple of seconds behind Google's
  blanked every avatar and banner in the app.** `functions/profile/media_contract.js`
  mints every grant with `PROFILE_MEDIA_ACCESS_TTL_MS = 90_000` measured on the
  *server* clock, while `ProfileMediaService.resolveAccess` rejected any expiry
  more than 91 s ahead of the *device* clock — a 1 s skew budget. The Redmi Note
  8 Pro (adb `6tq4g6f6ijrwxwzx`, `auto_time=1`) trailed server time by ~1.9 s, so
  every HTTP 200 grant with a valid signed URL was discarded as
  `FormatException('Unsafe profile-media grant expiry.')` and every surface fell
  back to the initial letter with no spinner, error or toast. The ceiling is now
  a symmetric ±5 min plausibility window, and the lifetime that is *cached* is
  derived from the device clock and clamped to the 90 s contract
  (`ProfileMediaService.grantTtl`), so a fast clock cannot stretch a grant
  either. A device running *ahead* of the server previously computed a negative
  remaining lifetime; it now falls back to the contract TTL, because the signed
  URL is judged by Google's clock, not the phone's, and an already-expired cache
  entry would evict and re-request itself in a loop. No Functions, schema or
  rules change: the server contract was correct.
- **R-02 / S-01 (P2) — the owner's own profile photo was a dead tap.** Tapping a
  friend's avatar opened the fullscreen viewer; tapping your own on Profile did
  nothing. `profile_header.dart` now wraps the gradient ring (not the disc — the
  ring is part of the avatar and a smaller target would clip the ripple) in
  `ProfilePhotoButton` with `minimumSize` equal to the ring's natural diameter,
  so the layout is unchanged at all six tested widths and
  `Key('profile-header-avatar')` still measures the same rect.
- **R-03 / T-5 (P2) — the banner ("zdjęcie w tle") had no fullscreen viewer
  anywhere in the app, and a friend's profile drew no banner at all.**
  `profile_photo_viewer.dart` is now parameterized by `ProfileMediaKind`: the
  banner opens in a 16:9 frame matching `ProfileImageRules.banner` (the shape
  the upload pipeline actually stores), falls back to
  `kProfileBannerFallbackGradient` instead of a 96pt initial, and carries its own
  EN+PL copy. `showProfileBannerViewer` and `ProfileBannerButton` (rectangular,
  22px radius) are the launchers. The Profile header's banner band and a new
  banner band on `friend_profile_screen.dart` both open it, so the same identity
  now reads the same way whichever profile you open. The uid + revision contract
  is unchanged — no durable or signed URL crosses the boundary. The edit-profile
  WYSIWYG preview was deliberately left non-tappable: it can show a locally
  picked image the server grant would contradict.
- **Name plate hit-test, found while wiring R-03.** The header's identity plate
  rides over the banner's lower edge, and a `Container` with a `decoration`
  does not answer hit tests, so tapping your own name fell through and opened
  the banner viewer. The plate is now wrapped in
  `MetaData(behavior: HitTestBehavior.opaque)` — no visual change, and the
  availability chip inside still wins the hit test.
- **T-6 / A-06 / A-07 (P3) — the viewer promised a photo it could not show.**
  For an account with no photo it opened a 640x760 panel containing one giant
  letter, and a failed grant left that letter forever with no retry.
  `ProfileMediaImage` gained one optional, non-breaking seam —
  `onResolution: ValueChanged<ProfileMediaResolution>` over
  `{pending, available, absent, failed}` — emitted from the branches it already
  computed, deferred past the build phase where it fires during `initState` or
  an `errorBuilder`. Every other call site is byte-for-byte unchanged. The
  viewer now shows a progress indicator while pending, a localized "No profile
  photo yet" / "Brak zdjęcia profilowego" (and the banner wording) only for a
  genuinely absent photo, and a neutral "Photo unavailable" with a Retry that
  goes through `ProfileMediaService.evictUser` for a failure — a blocked or
  private profile is never mislabelled as an empty one.
- **R-07 (P2) — the preview sheet printed English "Offline" and contradicted the
  rest of the app.** The same user read "Aktywny 6 min temu" in the chat header
  and "Nieobecny" on the Home rail. The sheet was reading `profile.isOnline`
  from the public projection for *everyone*; it now subscribes to
  `MessageService.watchUserPresence` — the same `socialPresence` stream
  `chat_screen.dart` uses — and renders through the shared `PeopleStatus`
  mapping (`Dostępny` / `Nieobecny` / `Zaraz wracam` / `Nie przeszkadzać`), so
  the two surfaces can no longer disagree. A viewer the rules deny gets **no
  dot at all** rather than a guess, and the pushed full profile inherits the
  resolved presence instead of a hardcoded `isOnline: false`. The hardcoded
  `Color(0xFF35D07F)` is gone in favour of `status.foreground(palette)`.
  `friend_profile_screen.dart` lost its own `'Offline', 'Offline'` special case
  the same way. No schema, rules or Functions change — `socialPresence/{uid}`
  and its canonical-friend read already existed.
- **T-3 (P2) — the preview sheet rendered built-in error copy in English inside
  a Polish UI.** `friendlyErrorMessage` already carried
  `'Nie masz uprawnień, aby to zrobić.'`; three call sites in the sheet simply
  never passed the localizations, so a permission-denied profile read showed the
  bare English sentence as the sheet's entire body. All three now pass `copy:`,
  and `test/shared_localization_source_guard_test.dart` pins every
  `intentionalOrFriendly` call in that file against regression. Making `copy`
  required on the helper was deliberately **not** done here: 58 of 95 call sites
  omit it and some have no `BuildContext` at all — that is its own sweep.
- **S-03 / S-04 / S-06 / S-08 (P2–P3) — four avatars that could never render a
  photo, whatever the user uploaded.** The Settings hero, the Creator Studio
  header, server management member rows and the incoming-DM top notification all
  dereferenced a denormalized `photoUrl` that the server no longer projects (and
  which must not be dereferenced anyway — it bypasses the live visibility and
  block recheck), so each painted the display-name initial unconditionally and
  the member row painted an *empty* disc when a legacy URL failed to load. All
  four now use the canonical `UserAvatar`, resolving from the uid, keeping their
  existing disc colours so nothing is restyled. `ServerMember.fromFirestore`
  additionally stops parsing `photoUrl` at all (client-side only; the Firestore
  field, rules and migration allowlist are untouched), so no future call site
  can dereference it.

All eight new viewer strings were added to the translation catalog as a new
append-only pack,
`lib/core/localization/translations/translations_profile_media_viewer.dart`
(8 keys x 40 locales, wired into `app_translation_catalog.dart`), because the
viewer is a current-release surface and
`test/localization_source_guard_test.dart` will not let one fall back to
English outside EN/PL.

Tests, all failing before the fix and passing after (mutation-proved by running
them against the base sources: 14 failures):
`test/profile_media_clock_skew_test.dart` (7 cases, both skew directions plus
the clamp), `test/profile_banner_viewer_test.dart` (4),
`test/profile_photo_viewer_test.dart` (+5), `test/profile_preview_sheet_test.dart`
(+4), `test/profile_avatar_surfaces_test.dart` (5),
`test/friend_profile_responsive_test.dart` (banner asserted at all 7 widths),
`test/shared_localization_source_guard_test.dart` (+1).
`test/profile_media_access_test.dart` now exercises the shipped 90 s TTL instead
of 80 s.

**UNVERIFIED — device proof is still owed.** `flutter analyze` and the widget
tests prove code health, not that a screen renders. Nobody has yet installed a
build carrying R-01 on `6tq4g6f6ijrwxwzx` to confirm the owner's own avatar and
banner actually appear and that no `[IMAGE] profile media grant failed` line
remains in logcat. A build was deliberately not made from this worktree while
several agents were editing `lib/` concurrently — it would not have been a
build of any coherent revision. If initials persist after R-01 lands, the fix
is necessary but not sufficient and the signed-URL GET must be instrumented
next.

**Not covered by this slice:** S-05 (server stage/text-channel avatars opening
the profile preview) was already being implemented by another agent in
`server_text_channel_scene.dart` during this pass and was left to them to avoid
clobbering in-flight work.

## FIXED IN SOURCE — the More sheet clipped three of its six tile labels (2026-09-18)

Audit ID R-10 (P3) from the Build 33 pre-redesign polish sweep,
`yovoice-evidence/2026-09-18/polish-33/redmi/13-more-menu.png`. Fixed in source
on branch `polish/build-33`; commit `polish/build-33 (pending)`. Full report:
`yovoice-evidence/2026-09-18/polish-33/fix-more.md`.

- **R-10 (P3) — half the More sheet's launcher tiles showed a truncated
  label on a 392.7dp phone**: `Znajdź twór…`, `Osoby warte obs…` and
  `Powiadomie…`. `more_sheet.dart` drew the six product destinations in a
  `GridView.count` with a fixed `mainAxisExtent: 62` and `maxLines: 1` on both
  the title and the subtitle, so one line was all a label could ever get. The
  tile's text column measures 107.35dp there, and the real Inter face needs
  114.86dp for `Znajdź twórców` and 109.06dp for `Powiadomienia` on one line.
  Fix, behaviour only — no colour, padding, icon size or type changed: the
  fixed-extent grid became a `Column` of `IntrinsicHeight(Row(stretch))` with
  the same column count and spacing, so each row takes the height its own
  tallest tile needs; `_MoreTile` keeps 62dp as a *minimum* (unchanged density
  for short labels, unchanged 44px+ target) and both texts moved to
  `maxLines: 2`. Raising the fixed extent instead was rejected: a cell tall
  enough for two lines of each at 1.3x text is ~86dp, which would have made
  every tile 39% taller at 1.0x and risked the owner sheet no longer fitting
  390x844. The branch that picks the compact grid is also width-aware now
  (`textScale > 1.3 || labelWidth < scaler.scale(14) * 5`), so a 320dp phone at
  1.3x text drops to the full-width rows that already existed instead of a
  74dp column nothing fits in; 360dp and up keep the grid at 1.0x and 1.3x.
  One Polish string was shortened in the tile only — `People to follow` maps to
  `Warto obserwować` there, while the roomier desktop popover keeps `Osoby
  warte obserwowania`; the English catalog key is unchanged, so no other
  locale moved. Tests: 14 cases appended to
  `test/more_sheet_accessibility_test.dart`, which load the shipped
  `InterVariable.ttf` first (the default test font is a 1em-per-glyph box far
  wider than Inter and would measure the wrong thing) and assert
  `didExceedMaxLines == false` for all twelve Polish titles and subtitles at
  320/360/375/390/392.7/430/834/1280dp across 1.0x and 1.3x, plus the 320dp
  1.3x row fallback. RED on each part of the fix independently: title back to
  `maxLines: 1` fails 8 cases; a fixed 62dp cell fails every grid case with
  `RenderFlex overflowed by 23 pixels`; the old text-scale-only branch fails
  the 320dp case. Rendered proof (real painted pixels) at six widths in
  `yovoice-evidence/2026-09-18/polish-33/fix-more/`, including the 3-column
  tablet branch the audit could not check. **Not re-verified on a device** —
  the fix is in no installed build (the Redmi runs Build 31), so the on-device
  result is UNVERIFIED until Build 33 is installed. Known cosmetic residual,
  left for the redesign: `Powiadomienia` still wraps on a phone, and at exactly
  392.7dp the break leaves a single `a` on the second line — the word needs
  109.06dp and the column gives 107.35dp, a 1.71dp shortfall that only a
  spacing/icon change or a shorter label can close.

## FIXED IN SOURCE — the Chats slice: an English tombstone in a Polish list, and a conversation photo that could not be looked at (2026-09-18)

Audit IDs R-08 (P3) and T-4 (P3) from the Build 33 pre-redesign polish sweep.
Both fixed in source on branch `polish/build-33`; commit
`polish/build-33 (pending)`.

- **R-08 (P3) — the Chats list printed `Ty: Message deleted` while the
  thread it opened printed `Wiadomość usunięta`.** `Message deleted` is the
  wire value `functions/messaging/direct_integrity.js` writes onto the
  conversation root when a message is deleted; it is the storage format and
  it stays English. Two client helpers rendered it: the localized
  `_localizedConversationPreview` in `messages_screen.dart`, which fell
  through to the raw field for text/GIF, and an English-only duplicate,
  `Conversation.previewFor`, which Home's recent chats
  (`recent_chats.dart:273,367`) and the shell's incoming-message overlay
  (`main_shell.dart:1087`) used — so those two surfaces were English in every
  locale, tombstone or not. Fix, client-only, no schema or Functions change:
  one shared `conversationPreview(Conversation, currentUserId,
  AppLocalizations)` plus `localizedMessageTombstone(...)` in
  `lib/features/messages/data/models/conversation.dart`, mapping the exact
  trimmed literal `Message deleted` and returning every other body verbatim
  (a message whose text merely contains those words is user content and is
  never translated). `messages_screen.dart` (list, search filter and the New
  message sheet's recent rows), `recent_chats.dart` (both card styles, text
  and semantic label), `main_shell.dart` (overlay body) and
  `notifications_screen.dart:881` (unread card) all call it;
  `Conversation.previewFor` and the provably dead `Message.previewText()` are
  deleted so the English literals cannot come back through a new caller. No
  catalog key added — `Message deleted` already has all 41 non-EN/PL
  translations in `translations_gif_messages.dart`. Test:
  `test/conversation_preview_localization_test.dart`, 7 cases — the Chats row
  and the Home card under `Locale('pl')` and `Locale('en')`, the empty-thread
  call to action, and a unit check that `Message deleted?` is left alone. RED
  on two independent mutations (tombstone mapping neutered: 3 failures;
  `recent_chats.dart` reverted to the old English-only duplicate: 2
  failures), GREEN on the fix.

- **T-4 (P3) — tapping a person's photo in the Chats list opened the
  conversation instead of the photo.** The avatar sat inside the row's single
  `InkWell`, so the 58 px the face occupies was just more of the row. This is
  the owner's complaint that the profile-photo preview is missing in some
  sections, and Chats had no other route to that person's profile. Fix:
  `_ConversationAvatar` takes an `onOpenProfile` callback and wraps its
  `Stack` in the canonical `AccessibleTapRegion` (58x58 circular target, so no
  layout shift at any width), which contributes one enabled *button* node —
  `Open {name} profile, {status}` / `Otwórz profil użytkownika {name},
  {status}` — replacing the old `Semantics(image: true)` wrapper, and the
  callback opens `showProfilePreview(...)`, the same sheet every other avatar
  in the app opens. Wrapping inside `_ConversationAvatar` covers both the
  ordinary row and the enlarged-text column branch with one edit. The
  existing catalog key `Open {name} profile` is reused; no key added.
  **Regression found while fixing, and fixed here**: the naive wrapper cost
  the row its long-press mute/archive/delete sheet on exactly those 58 px —
  not the nested `InkWell` but `Tooltip`, whose default
  `TooltipTriggerMode.longPress` registers a `LongPressGestureRecognizer`
  below the row's own and wins the arena. The hover hint is therefore mounted
  as an explicit `Tooltip(triggerMode: TooltipTriggerMode.manual)` around the
  tap region, which registers no recognizer while pointer hover is
  unaffected. A `firestore` injection seam was added to `MessagesScreen`
  (null in production, exactly as `ChatScreen` does) so the preview is
  assertable without a live Firebase app. Test:
  `test/messages_row_profile_preview_test.dart`, 9 cases — avatar tap opens
  `ProfilePreviewSheet` and pushes no `ChatScreen`, row body still opens the
  conversation, avatar long-press still opens the actions sheet, each at 1.0x
  and 1.6x text; the avatar stays its own target at 600 px and 1280 px; and
  the semantics node is one enabled button >= 48 pt. RED on both mutations
  (`onTap: null`: 2 failures; tooltip back to `longPress`: 2 failures), GREEN
  on the fix. **Not verified on a device in this round** — see the evidence
  file `yovoice-evidence/2026-09-18/polish-33/fix-chats.md` for what was and
  was not rendered.
  Home's recent-chat cards (`recent_chats.dart:106,113`) have the same
  avatar-inside-one-tap-target pattern and were deliberately left alone in
  this slice.

## FIXED IN SOURCE — a server text channel's message avatars were not tappable (2026-09-18)

Audit ID R-04 (P2) from the Build 33 pre-redesign polish sweep,
`yovoice-evidence/2026-09-18/polish-33/audit-avatars-code.md`. Fixed in source
on branch `polish/build-33`; commit `polish/build-33 (pending)`.

- **R-04 (P2) — tapping a sender's avatar in a server text channel did
  nothing.** The same tap opens the shared profile preview in Moments
  (`moment_card.dart`), in direct chats, in the room chat panel and in the
  Home people strip, so the gesture is learned everywhere else in the app; the
  server thread was the one populated message surface where the avatar was an
  inert picture, and it carries no other route to a member's profile.
  `_MessageTile` in
  `lib/features/servers/presentation/widgets/server_text_channel_scene.dart`
  built a bare `UserAvatar` with no gesture, no semantics and no tooltip.
  Fix: wrap it in the canonical `AccessibleTapRegion` — the same wrapper
  `moment_card.dart` uses — which contributes a real *button* node to the
  semantics tree, answers Enter/Space, keeps a 44x44 target and draws the
  focus ring; `onTap` opens `showProfilePreview(userId: message.senderId,
  displayName: message.senderName)`. The avatar's own initial is wrapped in
  `ExcludeSemantics` so the button announces the sender's name once instead of
  the name plus a stray "A". Copy is inline EN+PL (`Open profile for {name}` /
  `Otwórz profil: {name}`, tooltip `Open {name}'s profile` /
  `Otwórz profil {name}`) — no catalog key added. A self-tap needs no special
  case: `profile_preview_sheet.dart`'s `_isSelf` already suppresses the
  friend/follow actions and shows the self variant. A narrow test seam
  (`ServerTextChannelScene.onOpenProfile`, null in production) follows the
  pattern `moment_comment_preview.dart` already uses for the same sheet, so
  the wiring is assertable without a live Firebase app. Test: two cases in
  `test/gif_chat_surfaces_test.dart` (EN and PL) pump the real scene at 320,
  768 and 1440 px, assert the avatar has an `AccessibleTapRegion` ancestor
  whose rendered target is >= 44 pt, assert the semantics node is an enabled
  button labelled with the sender's name and carrying a tap action, assert the
  tooltip, and assert the tap reports `other/A member`. RED with the wrapper
  reverted to the bare `UserAvatar` ("Found 0 widgets with type
  AccessibleTapRegion"), GREEN with it. Rendered proof (real painted pixels,
  `RepaintBoundary.toImage`) at all three widths in EN and PL in
  `yovoice-evidence/2026-09-18/polish-33/fix-cross-section/`. Known visual
  consequence, accepted: the 44 pt target makes the row's leading column 44 pt
  instead of 36 pt, so the bubble starts 8 px further right — the same
  geometry Moments already has. **Not re-verified on a device**: the fix is
  not in any installed build (Redmi runs Build 31), so the on-device gesture is
  UNVERIFIED until Build 33 is installed.
  `server_management_sheet.dart:491` and `server_invite_sheet.dart:185` have
  the same gap and are tracked separately as A-20; they are untouched here.

## FIXED IN SOURCE — Settings polish slice: invisible switch thumb and an untranslated account type (2026-09-18)

Two defects from the Build 33 pre-redesign polish sweep (audit IDs R-06 and
R-09, `yovoice-evidence/2026-09-18/polish-33/redmi/audit-redmi.md`). Both are
fixed in source on branch `polish/build-33`; commit `polish/build-33 (pending)`.

- **R-06 (P2) — every ON notification switch rendered as a solid purple
  lozenge with no thumb.** Evidence: `redmi/18-notifications.png` (Build 31).
  `_PreferenceRow` in
  `lib/features/notifications/presentation/screens/notification_preferences_screen.dart`
  passed `activeThumbColor: colors.primary` — the exact colour
  `AppTheme._buildTheme`'s `switchTheme` already resolves the *selected track*
  to (`app_theme.dart`, `trackColor` → `primary`), so the thumb was painted
  the same purple as the track it sits on and disappeared into it. The theme
  on its own resolves the selected thumb to `colorScheme.onPrimary`. Fix:
  delete the widget-level override, leaving
  `Switch.adaptive(value: value, onChanged: onChanged)` so the Material 3
  switch theme applies. No theme file was touched, and the four other
  `activeColor` switch overrides elsewhere in `lib/` are a different colour
  from their track and were left alone. Test:
  `test/notification_preferences_switch_thumb_test.dart` pumps the real screen
  under both `AppTheme.darkTheme` and `AppTheme.lightTheme` and asserts, for
  every rendered toggle, that the resolved selected *thumb* colour differs
  from the resolved selected *track* colour — a behavioural assertion rather
  than a hard-coded hex, so it survives a palette change. RED with the
  override restored (both themes), GREEN without it. Rendered proof (real
  painted pixels, `RepaintBoundary.toImage`) in
  `yovoice-evidence/2026-09-18/polish-33/fix-settings/`:
  `notification-prefs-BEFORE-{dark,light}.png` show the thumbless lozenge,
  `notification-prefs-{dark,light}.png` show the white thumb, with the one OFF
  toggle unchanged in both.
- **R-09 (P3) — "Typ konta: Personal" in the Polish UI.** Evidence:
  `redmi/14-settings.png` (Build 31, owner's account, `accountType: personal`).
  The Account row in
  `lib/features/settings/presentation/screens/settings_screen.dart` rendered
  `copy.text(profile.accountType.label, _polishAccountType(...))`, and
  `_polishAccountType` matched on the lowercased English label with cases for
  `creator`, `business` and `user`/`member` before falling through to
  `_ => label`. `personal` and `official` had no case, so both leaked the raw
  English enum label; `business`, `user` and `member` were dead branches — no
  such `AccountType` exists. Fix: a new `settingsAccountTypeLabel(copy, type)`
  helper whose switch is exhaustive over `AccountType`, worded exactly like the
  account-type badge in `profile_header.dart` (Personal/Osobiste,
  Creator/Twórca, Official/Oficjalne), and `_polishAccountType` deleted. The
  exhaustive switch makes a future fourth `AccountType` a compile error here
  instead of a silent English leak. Test:
  `test/settings_account_type_localization_test.dart` covers all three values
  in EN and PL, asserts no value renders its English enum label in Polish, and
  pins the wording to the profile badge's. RED when any branch regresses.
  **Not visually re-verified on a device**: the fix is not in any installed
  build, and `SettingsScreen` builds its own `ProfileService`/`AuthService`,
  so it cannot be pumped in a widget test without a real Firebase app — the
  rendered Polish row is UNVERIFIED until Build 33 is installed.
- **Still open, deliberately out of this slice.** `Personal`, `Creator` and
  `Official` have no entries in any `lib/core/localization/translations/`
  catalog, so the other 28 selectable locales still fall back to English for
  this row — exactly as `profile_header.dart`'s badge already does. That is an
  app-wide catalog gap for the Localization Specialist, not an EN+PL defect.

## FIXED — reactions on photo, video and GIF bubbles in direct chats (2026-09-18)

Owner report, verbatim: "w czatach znajomych, na wiadomość możesz dodać
reakcję a na zdjęcie i filmy nie można". Fixed in source on 2026-09-18, with
tests that were RED before the fix and are GREEN after it.

- **Root cause — a Tooltip inside the bubble won the long-press arena; not a
  type gate and not the server.** `setDirectMessageReaction`
  (`functions/messaging/direct_integrity.js`) accepts every canonical,
  non-deleted message type, and `_MessageActionsSheet` gates only *Edit* by
  type. The gesture was the defect: `MessageBubble` opens its actions from
  `AccessibleContextAction`, a `GestureDetector.onLongPress` around the whole
  bubble. A text bubble is plain content, so the long-press reached it. A
  photo bubble wraps its tap target in `AccessibleTapRegion(tooltip: 'View
  photo')`, the video bubble's full-screen `IconButton` carries a tooltip,
  and a GIF that failed to load carries a "Retry" tooltip — and Flutter's
  `Tooltip` (`widgets/raw_tooltip.dart`, `_handlePointerDown`) registers its
  own `LongPressGestureRecognizer` on every touch, stylus and trackpad
  pointer-down. It sits deeper in the hit-test path, so its deadline timer
  starts first, fires first and wins the arena; the bubble's recognizer was
  rejected and the person saw a "View photo" hint instead of the reaction
  row. A mouse never triggers that path (the tooltip hovers instead), which is
  why desktop right-click kept working while the phone did not. Fix
  ([ADR-199](Decisions.md#adr-199-a-long-press-context-action-makes-every-tooltip-inside-it-hover-only)):
  `AccessibleContextAction` wraps its child in a `TooltipTheme` with
  `triggerMode: TooltipTriggerMode.manual`, so every tooltip nested inside a
  long-press context action is hover-only — the hint still shows on hover,
  the semantics tooltip stays, and the touch long-press goes back to the
  action that owns it. Nothing outside a context action changes. Tests:
  `test/chat_media_reactions_test.dart` (photo; video full-screen and play
  controls; voice; a failed GIF; the tap still opens the photo full screen;
  mouse hover still shows the hint and right-click still opens the sheet) and
  the tooltip case in `test/accessibility_context_action_test.dart`. With the
  wrapper removed, four of the eight fail by finding the tooltip text where
  the sheet should be. UNVERIFIED on a device: the build machine was busy
  with the Build 31 release, so the proof is the gesture arena in widget
  tests, not a phone.
- **Not reachable, by design and unchanged:** the full-screen viewer
  (`direct_media_fullscreen_viewer.dart`) offers no reaction control — a
  person closes it and long-presses the bubble. The queued card of a photo or
  video still uploading has no actions either; it is not a message yet.
## FIXED IN SOURCE — the chat keyboard could not be put away, or came back on its own (2026-09-18)

Owner report (Redmi Note 8 Pro, Android 11/MIUI, Build 30, and iOS): "nie
można 'zniżać' klawiatury podczas pisania czasami". Reproduced in widget tests
against the direct-chat composer; the channel composers (the server text
channel scene and the club chat facade) shared three of the five defects.
`TestTextInput.isVisible` is the oracle in every test below: it follows the
`TextInput.show` / `TextInput.hide` / `TextInput.clearClient` traffic the
framework sends, which is exactly what a phone acts on.

- **KB-01 (P1) — every send cycled the keyboard.** `_Composer` in
  `chat_screen.dart` set `readOnly: sending`. On Android and iOS a read-only
  `EditableText` cannot hold an input connection
  (`_shouldCreateInputConnection = kIsWeb || macOS || !readOnly`), so
  `_sending = true` closed it (`TextInput.clearClient`, then a scheduled
  `TextInput.hide`) and `_sending = false` re-opened it a frame later with
  `TextInput.show`. Every send dipped the keyboard; a keyboard put away during
  a slow local enqueue climbed back when it ended; and a Back pressed while it
  was down left the chat. The pause is now a `TextInputFormatter` that
  rejects edits while sending — same contract ("no keystroke lands between
  send and the durable enqueue", still pinned in
  `messages_silent_failure_test.dart`), no connection churn.
  `chat_composer_keyboard_test.dart: a send never puts the keyboard away` is
  red with the flag restored (2026-09-18: 10 pass / 1 fail) and green without.
- **KB-02 (P1) — no way to dismiss on touch.** Flutter's tap-outside default
  is a no-op for touch on Android and iOS, the thread had no
  `keyboardDismissBehavior`, and nothing on the screen unfocused the composer.
  On iOS, which has no Back button, the keyboard could not be dismissed inside
  a chat at all. The field now passes `onTapOutside`, scoped by a
  `TextFieldTapRegion` around the whole composer cluster (reply preview, GIF
  status, field, buttons, panel — so send, camera, mic, emoji and GIF taps are
  "inside"), and the thread lists use
  `ScrollViewKeyboardDismissBehavior.onDrag`. Direct chat, server text
  channels and club chat.
- **KB-03 (P2) — sheets handed the keyboard back.** `_pickAttachment` and
  `_recordVoiceMessage` opened their sheets with the composer still the
  route's remembered focus, so Flutter refocused it on pop and the keyboard
  reopened over the returning native picker, or right after a voice note.
  Both `unfocus()` first now.
- **KB-04 (P2) — the panel and the keyboard.** (a) Opening the emoji/GIF
  panel from an idle composer sent `TextInput.hide` *before* the
  `TextInput.show` that `requestFocus()` triggers a microtask later, so the
  keyboard rose under the panel; `yoFocusComposerBehindPanel` flushes the
  focus change first. (b) Closing the panel from its own button called
  `requestFocus()` on a node that already had focus — a no-op — so the
  keyboard never came back; `yoShowSystemKeyboard` asks the platform
  directly. (c) Android Back with the panel open left the screen instead of
  closing the panel; a `PopScope` on the composer cluster — Android only,
  since `canPop: false` on iOS would merely disable swipe-back — closes the
  panel first. Direct chat and club chat take the `PopScope`; the server
  scene is embedded inside the shell's own `PopScope` and cannot take one
  without both firing on the same Back (see "remaining").
- **KB-05 (P2) — a completed send re-requested focus.** Server and club
  `_send` called `requestFocus()` after the *network* send, which would
  resurrect a keyboard the person had put away during a slow send. Removed;
  focus stays where the person left it (the send button is inside the tap
  region, so tapping it never dropped focus in the first place).

Tests: `test/chat_composer_keyboard_test.dart` (11) and
`test/composer_keyboard_dismissal_surfaces_test.dart` (12; club and server),
plus `test/messages_silent_failure_test.dart`, which now pins the pause
contract behaviourally rather than through `readOnly`.

Device behaviour is **UNVERIFIED**: no Redmi Note 8 Pro / MIUI run and no iOS
run. Remaining: Back with the panel open inside the server scene still pops
the server screen (the scene lives inside the shell's `PopScope`); the room
chat sheet (a retired surface) was left untouched; the reel comment composer
toggles `enabled` while posting, which drops focus during the post but never
brings the keyboard back on its own — not the reported symptom, left as is.

## FIXED — publishing, the Voice Moments feed and new chats were 100 % dead for two days (2026-09-14 → 2026-09-16)

**P0, production; repaired by the four waves that ran 2026-09-16
21:56–22:05 UTC** (publishing at 21:58, the feed and new chats at 22:00). Every
account, on every platform, for 2.6 days. The three tester reports ("nie mogę opublikować Yeela",
Voice Moments, "czaty nie działają") were one defect with three faces.

**Root cause — deploy skew, not a bad commit.** The 2026-09-14 round deployed
115 of 241 functions from `22cc2313` and left 126 on the 2026-09-08 tree
`585740dc`. One of the 115, the `users/{uid}` trigger
`onUserPrivacySourceChanged`, rewrites every `publicProfiles/{uid}` document
with a 22nd field, `creatorAudienceVisible`. The shared guard
`canonicalPublicProfile()` in `functions/integrity/guards.js` validates that
document against an exact key set, and the 2026-09-08 copy accepts only the
21-key shape, answering `data-loss` — HTTP 500 — for everything else. All 32
production profiles carried the new field by ~08:54 UTC on 2026-09-14 (the
08:22:01Z read cited below was still healthy), so every
stale function refused every profile, 100 % of the time. The publish handlers
themselves are byte-identical across the two revisions.

Measured in production before the repair: `reserveReelDraftV2` 0 × 200 / 5 × 500;
`reserveMomentDraft` 0 × 200 / 6 × 500; `finalizeReelDraftV2` and
`finalizeMomentDraft` 0 requests (nobody got that far); `openDirectConversation`
9 × 200 (existing threads, which short-circuit before the guard) versus
25 × 500 (the create branch) plus 2 × 429; `reelUploadReservations`,
`voiceMomentUploadReservations` and `directMessageUploadReservations` all 0, so
no server state was ever created and there was nothing to repair in data.

**The feed was the silent one, and it is why nobody noticed.**
`voiceMomentProjection` calls the guard inside a loop that swallows per-item
failures, so every item was dropped and the caller received **HTTP 200 with an
empty page**: last populated page `2026-09-14T08:22:01Z` (1,459–1,509 bytes),
first empty page `08:53:56Z`, then 343 responses of a constant **245 bytes**
through `2026-09-16T21:27:57Z`, with **zero** errors, while production held 24
Voice Moments. Client-side there was nothing either: these are caught
`HttpsError`s, Crashlytics is wired for uncaught errors only, and neither
`_friendly()` in the composer nor `friendlyErrorMessage` has a `data-loss`
branch, so users saw "Try again" and no signal reached anyone.

**Fix:** the 16 named-target wave deploy from `22cc2313` on 2026-09-16
(21:56–22:05 UTC), recorded in
[DEPLOYMENT.md](DEPLOYMENT.md#tester-outage-repair--named-target-waves-ad-and-the-serverinviterefs-index--2026-09-16).
All 16 targets are ACTIVE on the fixed guard, and all 32 live profiles satisfy
the key set the redeployed guard accepts. Process rules so it cannot recur:
[ADR-195](Decisions.md#adr-195-a-shared-integrity-guard-is-a-deployment-unit--a-projection-writer-never-ships-ahead-of-its-readers).

**Not yet observed end to end.** No signed-in client has touched any of the 16
targets since the deploy, so the tester-facing metrics — a `200` on
`reserveReelDraftV2` / `reserveMomentDraft`, and a `getVoiceMomentsFeedV2`
response over 500 bytes — are **UNOBSERVED, not passed**. The hand-off check is
in the DEPLOYMENT entry. Run it the moment a tester is on a device.

**Update 2026-09-17 (observed, passed).** A signed-in owner client on the iPhone
17 Pro simulator exercised the repaired paths. Chats: `sendDirectMessage`,
`setDirectMessageReaction`, `editDirectMessage`, `deleteDirectMessage`, and a
GIF sent then deleted — 19 authenticated callables, all HTTP 200 (23:15–23:28
UTC, 2026-09-16). Publishing: `reserveMomentDraft`/`finalizeMomentDraft` 200 at
01:17 UTC and `reserveReelDraftV2`/`finalizeReelDraftV2` 200 at 01:20 UTC on
2026-09-17; both test items appeared in their feeds and were deleted in-app
(`deleteMoment`/`deleteReel` 200). Zero non-2xx responses in the window.
Evidence: `yovoice-evidence/2026-09-17/repair-device/` (`publish-report.md`,
`publish-logs.json`, `session-full.json`). Still unobserved:
`openDirectConversation` for a brand-new pair (existing threads resolve client-
side), the comment callables, and any Android client (the Redmi is signed out).
The empty Voice Moments feed before publishing was correct — all 24 stored
moments are `status: expired`, none published.

## FIXED IN BUILD 31 — what the outage repair did **not** fix (RC-5 … RC-17; found 2026-09-16, fixed 2026-09-17/18)

Ranked in `yovoice-evidence/2026-09-16/testers-root-cause.md`, designed in
`b31-design.md`, implemented in `b31-backend.md` / `b31-client.md`, repaired in
`b31-fix-1.md` and cleared by an independent read-only review in
`b31-gate-2.md` (analyze clean, 4965/4965 Flutter, 2282/2282 Functions, rules
and indexes unmodified). Ten of the thirteen are closed. **RC-6 and RC-7 are
not**, and one sub-item of RC-15 was deliberately left out of scope — they keep
their full entries in the OPEN section below.

**Read the proof level before repeating a claim.** Every "fixed" here is proven
by a test that was observed to fail with the fix reverted and pass with it in
place (the mutation convention in [TESTING.md](TESTING.md)). Nothing in this
group was verified on a physical device.

| Id | What it was | Fixed in | Reaches users through |
| --- | --- | --- | --- |
| RC-3(d) | `getVoiceMomentsFeedV2` swallowed every per-item drop, so a feed that lost its whole page logged nothing | `e714c251` (backend), `2b4e31b7` (client) | deployed 2026-09-18; client in build 31 |
| RC-5 | the first failed publish locked the Yeel draft forever — `_draftContractLocked` was set before the network call and the `finally` cleared only `_publishing`, gating 27 call sites with Back → "Discard this draft?" as the only exit | `3fddac7e` | build 31 binaries |
| RC-8 | `canonicalPublicProfile` returned `displayName.slice(0, 80)` **without re-trimming** while `validateReservation` asserts `authorName === authorName.trim()`, so an account whose 80th character is a space could reserve and then fail `finalize` permanently | `41bbe057` | deployed 2026-09-18 for the 7 targets |
| RC-9 | every failed "open chat" minted a fresh `requestId`, leaking an `integrityPreflightLedgers` row per failure and spending `direct.attempt.open` (12/60 s) in a preflight transaction that commits even when the main one rolls back — 12 taps manufactured a 429 | `d70cf055` | build 31 binaries; `openDirectConversation` deployed 2026-09-18 |
| RC-10 | a thrown `HttpsError` logged nothing server-side and every client failure was caught into a snackbar, so 34 production 500s produced zero signal for 2.2 days | `41bbe057` (backend `fail()`), `7137b015` (client non-fatal + `data-loss` copy) | deployed 2026-09-18 **for the 7 targets only**; client in build 31 |
| RC-11 | friend discovery was capped at 2 calls/minute, so ordinary browsing of the "make finding friends easier" surface produced 429s | `b710fd34` (10/min, 120/hour, plus a 5-per-10 s burst window) | deployed 2026-09-18 |
| RC-14 | the Yeel progress bar stopped at 95 % with no stage label — `ReelService.publish` exposed `onStage` and no caller in `lib/` passed it | `3fddac7e` | build 31 binaries |
| RC-15 a–d | MSG-01 an already-muted thread still offered "Mute"; MSG-02 Edit was offered on photo/video/voice the server refuses (2 × 400 in production); MSG-03 the outbox burned its 6/8 attempt budget while offline and parked at "Not sent" forever; MSG-05 `markDirectConversationRead` retried a permanent refusal every 30 s | `316cee33` (MSG-01, MSG-02, MSG-05), `6b3cd783` (MSG-03) | build 31 binaries |
| RC-16 | `onDirectMessageCreated` was registered **without** `retry: true`, so one contention, timeout or cold start silently and permanently dropped a message's bell row and push | `f383dd64` | deployed 2026-09-18 — `RETRY_POLICY_RETRY`, 512 Mi, 120 s, maxInstances 50, all read back |
| RC-17 | the probe refused fragmented MP4 (`readIsoBmffDecodeTimeline` required a populated `stts`, which a browser `MediaRecorder` never writes), so a web Yeel was rejected and mistranslated into "Check your media and audio rights" | `bdea661f` | deployed 2026-09-18 — **partially; see F-1 below** |
| RC-12 | four comment/voice-reply callables failed on the same guard | wave C, 2026-09-16 | already deployed |
| RC-13 | `sweepExpiredServerInvitesSchedule` failed every run for 62 hours | `58853fb0`, 2026-09-16 | already deployed |

Two corrections worth keeping, because both were nearly shipped wrong:

- **RC-8's first fix created the defect it was meant to remove.** Making the
  reader *refuse* an untrimmed stored name would have turned every legacy row
  into a permanent `data-loss`. The shipped rule repairs at the reader and
  projects at the writer — [ADR-202](Decisions.md#adr-202-a-canonical-display-name-is-repaired-at-the-reader-and-projected-at-the-writer-never-refused-at-either).
- **RC-17's first fix took the uploader's word for the duration.** The
  fragmented branch initially trusted a `tfdt` the uploader controls; six attack
  fixtures proved it. The shipped rule measures from bytes that a `trun` claims
  *and* an `mdat` actually contains — [ADR-203](Decisions.md#adr-203-a-fragmented-mp4-is-measured-from-bytes-a-trun-claims-and-an-mdat-actually-contains).

## OPEN — what Build 31 did not close (RC-6, RC-7, MSG-04 and the fragmented-MP4 over-count)

- **F-1 — P2, backend source, found by the principal gate on 2026-09-18, still
  present at HEAD and in production.** `functions/reels/probe.js:1572`
  `fragmentDuration += run.duration + run.maxCompositionOffset` adds one
  composition-offset maximum **per run, per fragment**, and `measuredTrackTotals`
  then sums those across every fragment. A composition offset is a presentation
  shift, not extra duration; the correct bound adds it once. Measured on
  synthetic fMP4 with one `cts` of 1001 ticks at a 30 000 timescale: 10 fragments
  → 10 334 ms (true ≤ 10 033); **60 fragments → 62 002 ms** (true ≤ 60 033); at
  two frames of offset, 64 004 ms. `reels/service.js` sets
  `MEDIA_DURATION_TOLERANCE_MS = 2000`, so a 60 s B-frame web recording at a 1 s
  timeslice lands exactly on the tolerance and a slightly heavier one is refused
  with "The uploaded Reel tracks are invalid" — **the RC-17 symptom, back for
  B-frame content.** It fails closed (over-reports, never under-reports) and the
  pre-fix code refused every fragmented file, so it is not a regression against
  production — but it caps how much of RC-17 actually shipped, and the fix is
  deployed. Do not tell anyone the web recorder is fixed without this caveat.
  Smallest fix: track the maximum composition offset per track across fragments
  and add it once to the final candidate. Prove it with a `trun` carrying flag
  `0x000800` over ≥ 10 fragments. Both Chromium fixtures are avc1 baseline, carry
  no `cts`, and therefore cannot see this.
- **F-2 — P3, backend source, accepted knowingly.** The ISO-BMFF read ceiling
  went 160 → 900 and is shared with the **progressive** path, where
  `listIsoBmffAtoms` spends 16 bytes per read — so `MAX_ISO_BMFF_DURATION_RANGE_BYTES
  = 2 MB` does not bound the read count for tiny atoms. A crafted progressive
  file can force ~900 GCS range requests per probe instead of ~160, a 5.6×
  amplification bounded downstream only by the `reels` reserve limiter
  (12/hour/user). Fix: a separate, smaller ceiling for the non-fragmented branch,
  or a minimum-bytes-per-read charge.
- **F-3 — P3, latent only.** `functions/messaging/direct_integrity.js:1748-1752`
  passes a `content` argument the preview helper never reads, and for a
  `reservation.type` outside image/video/voice the preview would silently become
  `""` where the old ternary produced `"Voice message"`. Identical behaviour for
  the three types the reservation validator allows, so nothing is broken today.
- **RC-6 — P1, needs data repair, not a deploy. Unchanged by Build 31 except
  that the tooling is now trustworthy.** Three of 20 conversation roots in
  production are non-canonical (`conversations` 20, `schemaVersion == 2` 17,
  `directConversationPairs` 17): the legacy client-written 12-key shape, which
  both trees reject (`validateConversation` → `permission-denied`,
  `validatePairGuard` → `data-loss`). A real user hit this — `sendDirectMessage`
  2 × 403 and `setDirectTyping` 2 × 403 from an Android client within 15 seconds
  on 2026-09-05, with generic copy and no diagnosis. `71078013` repaired the
  drifted migration tool (it treated `gif` and `video` as invalid types) and
  added `functions/scripts/identify_noncanonical_direct_conversations.js`, a
  read-only identification script with no apply path. **Neither has been run
  against production, and the migration callables were not deployed.** Read the
  script's output before anything else runs, and note N-2/N-3 below first.
  - **N-2 / N-3 — P2, in the repaired tool.** The canonicality probe is
    one-sided (`participants[0]` only) and `rootIsCanonical` short-circuits the
    apply to `alreadyMigrated` before the message pass, so a root canonical for
    one participant and broken for the other is reported healthy and refused
    repair. The three known roots are non-canonical *roots*, so the tool still
    serves them — but `alreadyMigrated` must not be trusted as an all-clear.
  - **N-10 — P3.** The script header claims "no participant uid ever reaches
    stdout". That is false for its own output: legacy roots use the `uidA_uidB`
    id shape (`firestore.rules:2876-2885`) while canonical ones use
    `dm_<digest>`, so the divergent ids it prints embed both uids.
- **RC-7 — P1 switch, disarmed 2026-09-16, keep it in mind.** One GIF message
  would have disabled open/attach/edit/delete/react for that thread, because
  `sendDirectMessage` on the new tree could write `lastMessageType: "gif"` that
  the old readers rejected, and the message would have been undeletable by
  anyone. Production never had one only because RC-4 kept testers out of new
  chats. Wave D removed the cause. The free runtime mitigation if it reappears is
  `appConfig/gif.enabled = false` — a document change, no deploy.
- **RC-15 e (MSG-04) — P3, client, deliberately out of scope.** Message history
  is `.limit(250)` with no older-page loader. `b31-design.md` excluded it
  explicitly ("not one of the owner's five"); it was never implemented and is not
  in build 31.
- **N-1 — P2, brand-new copy, wrong plural in both languages.**
  `lib/features/moments/presentation/widgets/moments_feed_view.dart:2056-2062`
  renders EN "The server returned **1 Moments**" and PL "Serwer zwrócił **4
  Momentów**". `AppLocalizations._pluralized` and the hand-written Polish rules
  already exist and are not used here. Shipped in build 31.
- **N-9 — P2, and the gate confirmed it is reachable.** The same new state can
  accuse the server falsely. `scannedCount = pageDocuments.length` is counted
  **before** the per-item privacy swallow (`functions/moments/integrity.js`), so
  a page whose candidates are all legitimately withheld for privacy yields
  `fetchedCount > 0, moments empty, drops empty` — which now draws "These Moments
  could not be loaded … This is a problem on our side" **and** fires a
  `getVoiceMomentsFeedV2 / server-dropped-all` Crashlytics non-fatal. A false
  fault claim to the user and a false signal in the very channel RC-10 built.
  Still better than the pre-round copy, which asserted expiry — so not a
  regression, but it must be fixed before the signal is alerted on.
- **N-5 — P2, observability noise from day one.** The central `fail()` now emits
  one WARNING per `data-loss`/`internal` at ~300 sites. A feed skew emits up to
  10 identical `integrity refusal` lines per call per viewer, and the RC-6 script
  plus `migrateDirectIntegrityConversation` emit `data-loss` WARNINGs as ordinary
  control flow. Any alert built on `integrity refusal` will be noisy until those
  paths are separated. See [ADR-201](Decisions.md#adr-201-the-single-refusal-primitive-is-the-single-refusal-signal--and-it-may-log-only-author-written-constants).
- **N-4 — P3, narrower than first reported.** No `.timeout()` wraps the send
  callable, so a slow server surfaces as `deadline-exceeded` (→ `markRetry`,
  budget charged), not a bare `TimeoutException`, and indefinite `retrying`
  requires `_offlineObserved == true`, which is intended. Residual: if the
  connectivity stream never reports the return to online, `_offlineObserved`
  stays stuck true.

### UNVERIFIED in this round — say so rather than implying otherwise

- **No device or simulator verification exists for any Build 31 fix.** RC-14's
  on-screen stage label and RC-15's "Edit is not offered on media" are proven by
  **rendered-widget tests** (`find.text(...)` in EN and PL, 320 px at 200 % text
  with `takeException()` null) and by nothing else. The device frames in
  `b31-device.md` (`h20`/`h22`) predate the fix and are byte-identical to each
  other, which is why the widget-test proof was demanded in the first place.
- **No browser measurement of RC-17 outside Chromium.** The only browser bytes in
  evidence are two Playwright-Chromium captures (1.47 s single-`moof`, 15 s
  five-`moof`). The exact-`mdat`-coverage rule and F-1 are both unproven against
  WebKit, which is the recorder most likely to differ — and RC-17 is a *web*
  recorder defect.
- **Deploy coverage is partial by design.** `functions/integrity/guards.js` is in
  every export's require graph, but only 7 functions were deployed. The remaining
  ~238 exports still run the pre-`41bbe057` `fail()` and the pre-fix reader, so
  RC-10's backend signal and RC-8's reader repair exist in production **only for
  those 7**. The cross-revision posture was checked and is safe: the reader change
  is a relaxation and the writer now emits values the old guard also accepts.
- **RC-8 is still unquantified in production.** Counting affected accounts means
  reading display-name values. The one known bound is that the longest live
  display name was 26 characters on 2026-09-16, so it could not fire on that data.
- **`98f9413c` (the Premium injected-clock fix) is not deployed.** Every Stripe
  export is outside the selector and in the must-not-deploy list. The change is
  test-clock correctness with `Date.now()` defaults preserved, so production
  Premium behaviour is unchanged — but the source and production do differ here.

## The 2026-09-16 RC diagnosis, frozen at `58853fb0` — reference only, not current state

**Every status word below describes the tree at `58853fb0`, before the Build 31
round.** It is kept because the file:line references, the production counts and
the reasoning are what a future investigation needs; read the two sections above
for the current state. Only RC-6, RC-7 and MSG-04 are still live.

- **RC-5 — was P1, client. FIXED in `3fddac7e`.** The first failed publish locks
  the Yeel draft forever. `reel_composer_screen.dart:187`
  `bool get _draftContractLocked => _session != null || _publishing;` assigns
  `_session` before the network call and the `finally` clears only
  `_publishing`, so from the first refusal the lock is permanent and gates 27
  call sites — media picker, backing-audio picker, every composition tool, the
  caption field, the availability selector. The only exit is Back → "Discard
  this draft?". The lock is correct once a server reservation exists; during the
  outage no reservation ever existed. Fix:
  [ADR-196](Decisions.md#adr-196-a-composer-draft-is-locked-by-a-server-reservation-never-by-an-attempt).
- **RC-6 — P1, needs data repair, not a deploy. STILL OPEN; the tool was repaired in `71078013` but never run.** Three of 20 conversation roots
  in production are non-canonical: `conversations` 20, those with
  `schemaVersion == 2` 17, `directConversationPairs` 17. They are the legacy
  client-written 12-key shape, and both the old and the new tree reject them
  (`validateConversation` → `permission-denied`, `validatePairGuard` →
  `data-loss`), so the wave deploy changed nothing for them. A real user hit
  this: `sendDirectMessage` 2 × 403 and `setDirectTyping` 2 × 403 from an
  Android client within 15 seconds on 2026-09-05, with generic copy and no
  diagnosis. `migrateDirectIntegrityConversation` exists but is itself drifted —
  it treats `gif` and `video` as invalid types — so **do not run its apply
  path**; reconcile `conversations` against `directConversationPairs` first.
  Which three roots they are is unknown: identifying them needs participant ids
  nobody read.
- **RC-7 — P1, disarmed on 2026-09-16, STILL a switch to keep in mind.** One GIF
  message would have disabled open/attach/edit/delete/react for that thread,
  because `sendDirectMessage` (on the new tree) could write
  `lastMessageType: "gif"` that the old readers rejected, and the message would
  have been undeletable by anyone. Production never had one
  (`lastMessageType == "gif"` was 0) only because RC-4 kept testers out of new
  chats. Wave D removed the cause. The free runtime mitigation if it ever
  reappears is `appConfig/gif.enabled = false` — a document change, no deploy.
- **RC-8 — was P1, backend source, the next publish failure in line. FIXED in
  `41bbe057`; deployed 2026-09-18 for the 7 named targets only.**
  `canonicalPublicProfile` returned
  `publicProfile.displayName.slice(0, 80)` **without re-trimming**
  (`functions/integrity/guards.js:258`), identical at `585740dc`, `22cc2313` and
  HEAD, while `validateReservation` asserts `authorName === authorName.trim()`.
  For an account whose 80th character is a space, reserve succeeds and finalize
  fails permanently on every retry — and RC-5 then locks the composer. Not
  quantified against production, because counting it means reading display-name
  values; the one bound that is known is that the longest live display name was
  26 characters on 2026-09-16, so it cannot fire on today's data. Same defect as
  the 2026-09-13 entry further down.
- **RC-9 — was P2. FIXED in `d70cf055`.** Every failed "open chat" burns quota and leaks a
  ledger row. `openDirectConversation` runs `beginAttemptPreflight` in its own
  transaction *before* the main one: it consumes `direct.attempt.open`
  (12 events per 60 s) and commits an `integrityPreflightLedgers` document,
  then the main transaction rolls back. So a deterministic refusal still charges
  the budget, and after ~12 taps the copy silently changes to "We're a little
  overloaded right now" — production shows exactly that, 2 × 429 after an
  11-failure burst. The client mints a new `requestId` per attempt, so nothing
  replays and each attempt leaks a row (`integrityPreflightLedgers` is at 1,075
  documents with no TTL). The Yeel and Voice Moment reserve paths consume their
  limiter *inside* the failing transaction and cost nothing, which is the shape
  to copy.
- **RC-10 — was P2, and it is why two days passed with no report. FIXED in
  `41bbe057` (backend) and `7137b015` (client).**
  The callable framework logs nothing for an explicitly thrown `HttpsError`, so
  all 34 production 500s carry zero application log lines. Crashlytics records
  uncaught errors only (`lib/main.dart`), and every one of these failures is
  caught and turned into a snackbar, so no non-fatal was ever recorded. Neither
  the composer's `_friendly()` nor `friendlyErrorMessage`
  (`lib/core/helpers/error_messages.dart`) has a `data-loss` branch — confirmed
  absent at HEAD. Fix: a Crashlytics non-fatal carrying `{callable, code}` on any
  terminal refusal, and copy that says the server refused and the draft is kept.
- **RC-11 — was P2. FIXED in `b710fd34`; deployed 2026-09-18.** "Find friends"
  from Chats is rate-limited at **2 calls per minute**
  (`FRIEND_DISCOVERY_MINUTE_LIMIT = 2`, hour limit 20,
  `functions/friends/social_graph.js`) — identical at every revision.
  Production: `getMutualFriends` 6 of 12 calls 429, `getFriendSuggestions`
  5 × 429. The "make finding friends easier" surface calls it more than twice a
  minute in ordinary browsing, so this is a separate, genuine "chats are broken"
  complaint waiting to be filed.
- **RC-12 — FIXED by wave C.** `createReelComment`, `createMomentComment`,
  `reserveVoiceCommentDraft` and `finalizeVoiceCommentDraft` failed on the same
  guard. Worth recording because an upstream report had called them D12-blocked:
  they are **Voice Moment** exports, deployed since 2026-09-08 and not covered
  by the Reel voice-comment block, which applies to
  `reserveReelVoiceCommentDraft`, `finalizeReelVoiceCommentDraft` and
  `expireAbandonedReelVoiceCommentDraftsSchedule` (absent from production).
- **RC-13 — FIXED 2026-09-16.** `sweepExpiredServerInvitesSchedule` had failed
  every run for 62 hours; see the entry below.
- **RC-14 — was P2, client. FIXED in `3fddac7e`; UNVERIFIED on a device.** The Yeel progress bar stops at 95 % with
  no stage label. `ReelService.publish` exposes `onStage`/`ReelPublishStage`
  (`uploadShare = .95`) and **no caller in `lib/` passes `onStage`** — verified
  at HEAD; the composer passes only `onProgress`. During `finalizeReelDraftV2`,
  up to a 60 s timeout, the label sits at "Publishing 95 %".
- **RC-15 — was P2, client, five chat defects. FOUR FIXED (`316cee33`,
  `6b3cd783`); MSG-04 remains open by decision.**
  `chat_screen.dart` never reads `Conversation.mutedBy`, so an already-muted
  thread still offers "Mute" (MSG-01); Edit is offered on photo/video/voice
  messages the server refuses — production shows `editDirectMessage` 2 × 400
  (MSG-02); `message_outbox.dart` `maxAttempts = 6` and
  `direct_attachment_outbox.dart` `maxAttempts = 8` burn the retry budget while
  offline and the connectivity listener only calls `due()`, so a message parks
  at "Not sent" and never revives (MSG-03); `markDirectConversationRead` retries
  every 30 s forever on a permanent refusal (MSG-05); message history is
  `.limit(250)` with no older-page loader (MSG-04). One Flutter change with
  widget tests, before the next tester round.
- **RC-16 — was P2, backend source. FIXED in `f383dd64`; deployed and read back
  2026-09-18.** A DM bell row and its
  push can be lost permanently: `onDirectMessageCreated` is registered **without
  `retry: true`** (`functions/notifications/activity.js`), while
  `onNotificationCreated` and `onRoomLiveChanged` in the same file set it.
  `createNotificationForEvent` is idempotent through
  `notificationDeliveryEvents`, so retry would be safe. One contention, timeout
  or cold start silently and permanently drops that message's notification.
- **RC-17 — was P3, backend source. FIXED in `bdea661f`; deployed 2026-09-18 —
  but see F-1, which caps how much of it actually works.** The media probe still
  refuses fragmented MP4: `readIsoBmffDecodeTimeline` requires a populated
  `stts`, which a browser `MediaRecorder` does not produce, so a web Yeel is
  rejected as `failed-precondition` and the client mistranslates it into "Check
  your media and audio rights". Android `MediaRecorder` and the iOS camera write
  non-fragmented MP4, so phones do not hit this — if a device publish fails now,
  suspect RC-8 first. It becomes the next *web* Yeel failure.

## FIXED — `sweepExpiredServerInvitesSchedule` failed every run for 62 hours (2026-09-14 → 2026-09-16)

**P2, production, fixed 2026-09-16; source landed in `58853fb0`.**
`collectionGroup("serverInviteRefs").where("expiresAt", "<=", now)`
(`functions/notifications/invites.js:465`) needs a hand-declared
`COLLECTION_GROUP` single-field exemption, and `firestore.indexes.json` had
never contained one at any revision. Every run since `2026-09-14T06:13Z` — 250
consecutive, roughly four an hour, 87 × HTTP 500 on 2026-09-16 alone — failed
with `9 FAILED_PRECONDITION: The query requires a COLLECTION_GROUP_ASC index for
collection serverInviteRefs and field expiresAt`. It was about 93 % of all
error-level log volume in the project, which would have masked the next real
scheduler alert. Impact: expired Server invite pointers and their notifications
were never cleaned up — growing and user-visible over time, not data-destructive.
Redeploying the function on 2026-09-16 did not help (it failed again identically
3½ minutes later), which is the empirical proof that the defect was the missing
index.

Fixed by the preserve-then-extend override (`COLLECTION` ASC/DESC/CONTAINS plus
`COLLECTION_GROUP` ASC, no `ttl`), deployed 22:14 UTC and READY at 22:18:55Z;
the next two scheduled runs returned 200. The emulator does not enforce index
requirements, so an existing suite that drove the real sweep stayed green
through all 250 failures — the new
`functions/test/server_invite_sweep_index.test.js` therefore asserts the
declaration *as data* and runs the real cross-parent query, with the declaration
test demonstrated red against the pre-fix file. Rule:
[ADR-198](Decisions.md#adr-198-a-collection-group-query-is-an-index-declaration-plus-a-test-that-runs-it-adr-007-reaffirmed).

## OPEN — `rooms.expiresAt` is the same missing collection-group index, one caller away from an outage (2026-09-16)

**P2, latent, not currently failing.** `fetchFreshVoiceSessions`
(`functions/stats/public_stats.js`) runs
`collectionGroup("rooms").where("expiresAt", ">", …)` and no `fieldOverrides`
entry declares `rooms.expiresAt` at `COLLECTION_GROUP` scope. It is harmless
**today** only because the function is exported and tested but deliberately not
called by `publishPublicStatsSchedule` (the file says so in capitals), and that
schedule was returning 150 × 200 with 0 errors when it was last read. The moment
anyone reconnects it, it fails in production exactly as the invite sweep did and
passes in every emulator run. Fix before that happens: the same preserve-then-
extend override and the same two-test shape as
`functions/test/server_invite_sweep_index.test.js`. Every other production
`collectionGroup()` query was cross-checked against the live index set on
2026-09-16 and is covered.

## FIXED IN SOURCE — Community OBS broadcasting defects found before commit (2026-09-16)

These defects existed only in the uncommitted media-collaboration work
(ADR-192) and were never committed or deployed. Fixed in `99b5916b`.
Every fix has a test that fails when its key line is reverted. Evidence is in
`yovoice-evidence/2026-09-16/` (`wip-inspect-servers.md` found them;
`wip-slice-A.md` and the `fix-A-mutation-*.log` files prove the fixes).

- **P1 — OBS authority expired with the 300 s join token.**
  `readAuthorizedCommunityBroadcastAccess` required the host's last JWT to be
  unexpired. As a result, a connected host could not set up OBS after five
  minutes, and any later host reconcile deleted a healthy live ingress. Token
  expiry is no longer part of the predicate; losing real host authority still
  deletes the ingress. Four emulator tests; reverting the line gives 2 failures
  in 31.
- **P2 — a provisioning lease refused every session end for up to 180 s.**
  Owner end, archive, delete, transfer, the staleness sweep, staff suspension
  and staff delete all failed with `failed-precondition` while a host's OBS
  setup was in flight. A host could re-arm that window after a deterministic
  provider failure. Ends are now always staged, and only the terminal worker's
  provider delete waits for the lease. Emulator tests cover host end, staff
  suspension and staff delete. Reverting the stager gives 3 failures in 37;
  reverting the host end gives 1 in 31; disabling the worker deferral gives 2
  in 37.
- **P3 — a missing capacity document meant "enabled".** The first OBS call
  created `serverRuntimeCapacity/communityBroadcastV1` as enabled with a limit
  of 25, so deploying the callable was not inert. A missing document now fails
  `failed-precondition` before any provider call.
- **P3 — every new Server session was written with source policy v2.** A
  not-yet-redeployed or rolled-back function would have denied every new
  generation. Policy v2 is now written only for Community broadcast
  generations.
- **P1 release blocker — the Servers activation package tool rejected the new
  manifest.** `tool/servers_activation_package.js` pinned 60/54/7/53 and 47
  non-creation callables, and it read the frozen callable table, so it could not
  include the new callable. Its test was 2 pass / 10 fail. CI does not run
  `tool/test`, so CI would have stayed green. It now pins 61 total / 55
  callables / 7 Podcast / 54 base with phases 42 / 7 / 48 / 1 (12/12).
- **P1 commit hazard — tracked modules required untracked files.** Six tracked
  Functions modules and one test `require` the three new
  `community_broadcast*.js` files. A commit without them makes
  `functions/index.js` throw `MODULE_NOT_FOUND` for every function. The
  Functions commit carries the complete set.
- **Test gap — the two new deny-all collections had no rules test.** The Server
  rules suite now proves every client role is denied get, set, update, delete
  and list on both (70/70; a scratch rule that allowed reads made exactly this
  check fail).

## OPEN — deleting a streaming host's account leaves the OBS ingress live (found 2026-09-16)

**P2, source only; OBS is not released.** `onAuthUserDeleted` retires the
profile but triggers no Servers voice cleanup. When the deleted account is a
Community host streaming through OBS, nothing deletes the RTMP ingress or ends
the generation. The OBS participant keeps the room occupied, so the staleness
sweep never stages the end. It ends only when a moderator ends the session, the
channel or server is archived, deleted or suspended, or a later reconcile of
that host runs. An account **ban** is handled: global voice enforcement deletes
the ingress (emulator test). Workaround: a moderator ends the session. Fix
direction: enqueue the existing voice-enforcement cleanup, or a host reconcile,
from the account-deletion lifecycle. Traced by Slice A, `wip-slice-A.md`
section 3. Emulator-confirmed by the adversarial review (SEC-1 in
`wip-security.md`, probe SEC-C): the session stayed `live`, the slot stayed
`active`, and no provider delete, outbox job or enforcement event was created.

## OPEN — Community OBS and call PiP hardening gaps from the adversarial review (P3, found 2026-09-16)

Source only; OBS is not released and PiP has no tester build. Found by the
read-only adversarial review of the uncommitted media work
(`yovoice-evidence/2026-09-16/wip-security.md`, emulator probe
`wip-security-probe.test.js`, 6/6). None is a P0 or P1, and none discloses a
Stream Key to a non-host. Not fixed in this round.

- **SEC-2 (CONFIRMED on the emulator) — the capacity document is a single
  point of failure for session ends.** If
  `serverRuntimeCapacity/communityBroadcastV1` is deleted while an input is
  live, or `limit` is set below `activeCount`, the terminal worker fails with
  "The media cleanup state needs reconciliation." (or `data-loss`) after the
  provider room is already gone. The session stays `ending`, the channel cannot
  go LIVE again, and a hand-edited counter also refuses every other host's
  setup. Repro: provision an input, delete the document, end the session, run
  the worker twice. Workaround: recreate the document with the true
  `activeCount`; the next worker pass finishes. Operators must change only
  `enabled` ([DEPLOYMENT.md](DEPLOYMENT.md)). Fix direction: always release the
  matching slot and decrement only a valid document.
- **SEC-3 (HYPOTHESIS; code path confirmed, no device capture) — a screen
  share can broadcast a revealed Stream Key, and the key cannot be rotated.**
  The host row shows Share screen and OBS together. Android and iOS screen
  share now capture the YO Voice UI, "Show key" renders the key as selectable
  text, and nothing sets `FLAG_SECURE` or pauses capture. A same-generation
  replay returns the same key, so a leaked key stays valid until the session
  ends or host authority changes; any viewer who saw it could publish into the
  LIVE. Workaround: end the session. Fix direction: hide reveal and copy while
  sharing, add a rate-limited key reset, mark the Android clip sensitive.
- **SEC-4 (CONFIRMED on the emulator) — OBS has no presence or duration
  bound, and the kill switch does not stop existing inputs.** A host admitted
  once can provision 6 h later without rejoining. After `enabled: false`, a
  host reconcile with unchanged authority deleted nothing. The OBS participant
  counts as occupancy (`session_staleness.js`), so an unattended, billed stream
  can run indefinitely. Workaround: end the live session. Fix direction: a
  maximum broadcast duration or periodic host presence, exclude `obs_`
  identities from occupancy, and an operator sweep for `enabled: false`.
  Hypothesis, not probed: 25 moderator accounts on 25 stage channels could hold
  the global cap; bounded today by the 100-UID `appConfig/serversV1` gate.
- **SEC-5 (CONFIRMED in a unit probe; not reachable in production) —
  fail-open ingress adapter seam.** When a RoomService `client` is injected,
  `getIngressClient` returns null, so ingress cleanup reports
  `{cleanupPending: false, deleted: 0}` and the room is still deleted while the
  key stays valid. Production construction never passes `client`. Fix
  direction: fail closed unless an explicit test-only flag is set.
- **SEC-6 (CONFIRMED in a unit probe; provider behaviour UNVERIFIED) —
  plaintext `rtmp://` is accepted.** `session_livekit.js` and
  `server_broadcast_ingress_service.dart` accept `rtmp:` as well as `rtmps:`.
  If the provider ever returned `rtmp://`, OBS would send the bearer key in
  cleartext. Fix direction: require `rtmps:` on both sides once the canary
  confirms what LiveKit Cloud returns.
- **SEC-7** is the `canPublishData` item in the residual-gaps entry below.
- **SEC-8 (HYPOTHESIS; no device) — Android PiP auto-enter is not gated on the
  call route being on top.** `_syncPictureInPicture` in
  `direct_call_screen.dart` arms `setAutoEnterEnabled` whenever the call screen
  is mounted and eligible. If another route, such as a chat opened from a
  notification, is pushed over the call, pressing Home may turn that route into
  a floating PiP window. iOS is not affected. No lock-screen exposure was found.
  Fix direction: also require `ModalRoute.of(context)?.isCurrent == true`.

## FIXED IN SOURCE — direct-call Picture in Picture closed on a network handover (2026-09-16)

Found in the uncommitted PiP work (ADR-194), reproduced with a scratch widget
test, and fixed in `1eed1626` before it was ever committed.

- **CM-02 (P2).** `_syncPictureInPicture` required `_voice.isConnected`, so a
  transient `reconnecting` state disarmed PiP. On Android that also moved the
  task to the background. PiP now stays armed through `reconnecting` and is
  disarmed only on terminal states. Reverting the line fails the new widget
  test with `[{active:true}, {active:false}]` (71 pass / 2 fail).
- **CM-09 (P2).** Every PiP controller installed its own handler on the shared
  `app.yovoice/direct_call_pip` channel and cleared it on dispose. It also
  disarmed natively even if it had never armed. Disposing an old call screen
  could therefore close a newer call's PiP or deafen it to
  `pictureInPictureChanged`. One native owner per channel now arms, disarms and
  receives events. Reverting the ownership check gives 5 pass / 2 fail;
  clearing the handler on every dispose gives 6 pass / 1 fail.

Device behaviour is **UNVERIFIED**: no physical Android or iOS device, no
two-device call and no real network handover were used.

## FIXED IN SOURCE — a direct message video after a call could play silently (2026-09-16)

LiveKit and the voice recorder leave a process-wide communication audio
session behind. On iOS that can route a chat video through the receiver or keep
it in a category the silent switch mutes; on Android it can leave
`AudioManager` in communication mode. A video controller cannot repair either
by changing its own volume. Before a user-started DM video, a native bridge now
restores the normal media route, but only while no call or Server session holds
the `RealtimeAudioSessionRegistry` (ADR-194). Fixed in `1eed1626`.

Two defects in the first version of this fix were corrected before commit:

- **MF-4 (P2).** The three DM video sites passed
  `VideoPlayerOptions(mixWithOthers: true)`. On Android that disabled audio
  focus, so a DM video no longer paused other apps' music and a phone call no
  longer paused the video. On iOS it could make a live call's audio session
  mixable. The option is removed at all three sites; Reels keep theirs.
  Restoring it in `direct_video_playback_source_io.dart` or in
  `message_bubble.dart` fails that site's test; the web site was not
  mutation-tested.
- **R-5 (P3).** On Android 8-11 the audio mode is process-global. The route
  reset now skips `MODE_IN_CALL`, so a chat video cannot reset another party's
  phone call (source-contract test).

**UNVERIFIED on device:** audibility after a real call with the silent switch
on, behaviour with Spotify playing, and a GSM call during playback.

## FIXED IN SOURCE — a refused screen-share type update could stop the Android voice keep-alive (2026-09-16)

**MF-5 / S-9 (P2), found in the uncommitted screen-share work.** Starting a
Server screen share sent a second `startForegroundService` intent and replied
to Dart before the service had applied the `mediaProjection` type, so LiveKit
capture could race it on targetSdk 34+. If `startForeground` refused the
update, the service called `stopSelf()` and ended the microphone and media
keep-alive for the whole call. Type changes are now applied in-process on the
running `VoiceSessionService`. The reply comes only after `startForeground`
returns, a failed update never stops an already-foreground service, and a share
without a running service is refused so Dart rolls the publication back. Fixed
in `1eed1626`. Source-contract tests fail when either key line is reverted;
the Kotlin compile passes.

The audit's suspicion that the service type was added **before**
MediaProjection consent is refuted by code: the type is added only after
`requestCapturePermission()` succeeds. Android 14, 15 and 16 behaviour remains
**UNVERIFIED** on a device.

## FIXED IN SOURCE — Activity kept the bell lit and Mark all read stopped at 400 rows (2026-09-16)

Opening Activity acknowledged nothing. The bell count stayed until each
notification was opened through its route or **Mark all read** was pressed,
and a foreground banner for Activity stayed on screen. **Mark all read**
updated at most 400 unread rows per press. The
screen now acknowledges unread rows while it is visible (including when a
retained tab becomes visible again) and clears the covering banner.
`markAllAsRead` drains bounded 400-row batches and throws if the signed-in
account changes between batches. Fixed in `63507816`. `test/notifications_inbox_test.dart`
passes 17/17. No revert run was recorded for this fix.

## FIXED IN SOURCE — Servers client gate failures in the media work (2026-09-16)

Found by the 2026-09-15 audit in the uncommitted work and fixed before commit:

- `flutter analyze` reported 2 `invalid_use_of_visible_for_testing_member`
  warnings. `isValidOpaqueServerParticipantIdentity` is a production
  validator used by the live whiteboard transport, so the annotation was
  removed (`50522b2d`).
- The localization source guard failed on `const Text('OBS')` in the Community
  stage. The label now goes through `AppLocalizations` (`50522b2d`).
- `test/voice_session_keep_alive_test.dart` still pinned the old
  `microphone|mediaPlayback` manifest. It now pins
  `microphone|mediaPlayback|mediaProjection` and the in-process type contract
  (`1eed1626`).
- The OBS setup sheet's refusal states (`not-found`, `unimplemented`,
  `failed-precondition`) had no tests. Seven widget tests now cover English and
  Polish copy, no raw backend message and retry (`50522b2d`).

## FIXED IN SOURCE — the phone whiteboard toolbar hid tools behind its edge (F1, F6; found 2026-09-16)

Found by the iOS Simulator smoke of the uncommitted whiteboard work
(`yovoice-evidence/2026-09-16/wip-verify-device.md`, frames 08-11 and
`crops/08-tools-row.png`, `crops/10-tools-row-drag.png`). HEAD had one
wrapping toolbar; the compact strips were new. Fixed in `50522b2d`.

- **F1 (P2).** On a phone the tools strip was a horizontal scroll view in an
  `Expanded` next to pinned Undo and Clear buttons. At 402 pt the six 48 pt
  tools (318 pt with gaps) had about 244 pt, so the Arrow tool was cut in half
  and the Grid toggle was hidden, with no fade, chevron or other scroll
  affordance. The Ink color strip cut its seventh swatch in half the same way.
  Repro on the old code: open a Company server on a phone-width device, then
  Channels, then the whiteboard channel. Every toolbar strip now wraps onto
  another run at every width, as the wide layout already did, and all targets
  stay 48 pt.
- **F6 (P3).** The zoom pill over the canvas was 94% opaque, so strokes
  under the top-right corner showed through its buttons and the percentage
  label. It is now fully opaque.

Tests: `test/server_whiteboard_test.dart` checks at 320x760 with 200% text,
390x844 and 402x874 that every tool, swatch and width button lies fully
inside the toolbar and overlaps no other control, and that the zoom controls
are opaque in both themes. Restoring the scroll strip fails all 3 layout
cases (at 402x874 Arrow overlaps Undo); restoring the 94% fill fails both
opacity cases. Capture-harness frames of the fix at 402x874 (light and dark),
390x844 and 320x760 at 200% text are in `wip-fix-1-frames/`. **On-device
rendering of the fix is UNVERIFIED**: the simulator smoke was not repeated,
because that app build runs signed in to production data.

## PENDING DEVICE VALIDATION — call PiP, Android screen-share service, mobile screen share and the OBS canary (2026-09-16)

**Still pending after the 2026-09-16 release.** The backend of this work is now
deployed (`createServerBroadcastIngressV1` is ACTIVE) and a 2.0.0 (30) client
was built, but nothing below moved: the OBS surface is inert because
`serverRuntimeCapacity/communityBroadcastV1` does not exist (owner decision,
[ADR-197](Decisions.md#adr-197-the-2026-09-16-owner-decisions-on-servers-exposure-warm-instances-and-the-obs-canary)),
no OBS/RTMP stream or LiveKit Cloud Ingress call has ever run, the two-device
call test was **waived by the owner** rather than performed, and build 30's
TestFlight delivery is itself unconfirmed. The authenticated non-host
`permission-denied` probe on the ingress callable, and the cross-account,
cross-server and malformed-grant negative probes, were **not produced** in
either 2026-09-16 round — they need real signed-in accounts. Nothing here may be
described as working.

Known risks in the ADR-194 work. None has been observed on a device, because
no device run has happened yet. The 2026-09-16 iOS Simulator smoke could not
reach a call, PiP or a screen share without ringing a real user or starting a
production session:

- **R-1.** iOS PiP may render black or frozen. `RTCMTLVideoView` is Metal, and a
  backgrounded app may not submit GPU work. An `AVSampleBufferDisplayLayer`
  renderer may be needed. Check on a physical iPhone with a Release/TestFlight
  build.
- **R-3.** flutter_webrtc ignores `MediaProjection.Callback.onStop`. Stopping a
  share from the Android 14+ status-bar chip, or the Android 15 lock-screen
  auto-stop, may leave a frozen LiveKit publication and a stale
  `mediaProjection` type. This needs a plugin or native change.
- **R-4.** The Server media reconcile removes the `mediaProjection` type when
  the publication is briefly absent (for example during a full reconnect) and
  never re-adds it.
- **R-6.** The realtime audio registry barrier has no timeout, so a hung native
  route call would block every call and Server join.
- **R-7.** If the Activity is recreated outside `configChanges`, native PiP state
  resets while Dart still believes it is armed, and PiP silently stops arming.
- **R-8 (pre-existing).** A Server listener promoted to speaker keeps a voice
  service without the `microphone` type.
- iOS screen share captures only the YO Voice app surface, because there is no
  Broadcast Upload Extension.

## OPEN — Servers media collaboration residual gaps (P3, 2026-09-16)

- `canPublishData` is `true` for every Server role, including Community
  listeners. Only Company meetings consume data, and no per-participant data
  rate limit is configured. Tightening it needs source policy v3 (ADR-192;
  SEC-7).
- A server-muted or host-muted participant can still send whiteboard previews,
  and `boardChannelId` is not bound to the meeting (ADR-193; SEC-9).
- A worst-case whiteboard packet is about 1.7 KB, which can exceed one lossy
  MTU-sized packet.
- The OBS sheet copies the Stream Key to the clipboard on request, and some
  platforms let other apps read the clipboard.
- Every `failed-precondition` from the OBS callable (kill switch off, missing
  capacity document, not the host, no live generation) shows the same
  "temporarily unavailable, try again" copy, even when a retry cannot succeed.
- Host broadcast cleanup can write a 120 s lease on an ending session while its
  own ingress delete is retried, so repeated server-side cleanup failures can
  re-arm that window. A host cannot trigger it.
- Community stage live chat on a phone (`server_text_channel_scene.dart`,
  unchanged committed code): the capture harness at 390x844 showed the chat
  empty-state subtitle clipped at its baseline. The iOS Simulator smoke on
  2026-09-16 (iPhone 17 Pro, 402 pt; `wip-verify-device.md` F2, frames 15-16)
  confirmed it and found it worse: the pane is about 95 pt tall, so at rest
  only the empty-state icon shows, and "No messages yet" and its subtitle
  appear only after scrolling the pane. The host's Share screen and OBS row
  shortens the pane further in a live session (harness frame only; the
  simulator smoke did not go live). At 1440x900 the Community stage's secondary
  action row starts under the fixed session dock at the initial scroll offset;
  the simulator smoke covered phone width only, so that one stays UNVERIFIED.

## OPEN — pre-existing visual defects seen in the 2026-09-16 simulator smoke (P3)

Found by the iOS Simulator smoke (iPhone 17 Pro, 402 pt, light theme, English;
`yovoice-evidence/2026-09-16/wip-verify-device.md`). All are in code the
uncommitted media work does not change. Not fixed in this round.

- **F3.** A clipped rounded container edge with a gradient shows above the
  Live chat / Channels segmented control on the phone Community stage (frame
  15; also in harness frames).
- **F4 (accessibility).** In a Server text channel, the enabled send button
  draws a #211629 icon on #6f1fd1, a 2.31:1 contrast (below the 3:1 non-text
  minimum). Its right edge sits about 8-10 pt from the screen edge instead of
  the 16 pt narrow gutter (`crops/05-composer-crop.png`).
- **F5.** The direct message composer draws a nested double outline, the
  header's name and "Active" rows are misaligned, and the call icons take a
  third header row (`crops/18-dm-composer.png`, `crops/18-dm-header.png`).
- **F7.** Activity shows a prominent filled "0" count chip, and system
  achievement notifications carry a "USER" role chip. Rendering them logged
  three `profile media grant failed: [firebase_functions/not-found] The
  selected profile does not exist.` messages; the avatars fall back to an
  initial (frame 20).

## OPEN — a direct call can stay "connected" for hours after the other side disappears (confirmed 2026-09-16)

**P1, pre-existing in committed code.** For a direct call,
`ParticipantDisconnectedEvent` does nothing, and the call screen has no "the
other person left" logic. If one side kills the app, crashes or loses the
network, the other side stays on a "connected" timer with no audio, video or
message until they press End or Back. The side that dropped gets "you already
have a call in progress" on every retry and has no UI to end it. Anyone calling
either person hears that they are in another call. If both sides leave without
End, the call document and both `directCallLocks` stay active for up to 8 hours
(`ACTIVE_CALL_TTL_MS`), until `expireDirectCallsSchedule` removes them. There is
no heartbeat or TTL refresh. The LiveKit webhook handles `participant_left` only
for achievements. Fix direction: end the call server-side when a `call_*` room
has fewer than two participants for N seconds, or use a short TTL renewed by a
heartbeat. On the client, end on a remote disconnect after a grace period, and
offer "End previous call" on `already-exists`. Not fixed in this round.

## OPEN — ordinary Server members cannot leave a Server in the app (confirmed 2026-09-16)

**P1, pre-existing in committed code.** The only **Leave server** control is in
the management sheet. The workspace opens that sheet only for roles that can
moderate, on both desktop and phone. A `member` or `guest` therefore has no way
to leave, although `leaveServerV1` accepts every non-owner. The only ways out
are account deletion or removal by a moderator, and the member stays visible in
the roster. `test/server_management_test.dart` ("ordinary member has no server
management entry") pins the missing entry and no test covers a member leaving.
Fix direction: a separate Leave action for non-owner roles, or the sheet with
management sections hidden below moderator. Not fixed in this round.

## OPEN — the full friend profile shows actions that do not match the relationship (confirmed 2026-09-16)

**P2, UX only, pre-existing.** `FriendProfileScreen` always renders **Remove
friend** and **Block user**, and **View full profile** in the preview sheet is
shown even for yourself. For a stranger with a public profile, Remove friend
changes nothing but closes the screen as if it had. On your own profile, both
actions end in a generic error. A friend opened from the preview always shows
"Offline" because the preview passes `isOnline: false`. Firestore Rules still
keep a profile unreadable when its owner has blocked the viewer. Fix direction:
read the relationship status and show only the matching actions, hide View full
profile for yourself, and hide unknown presence instead of showing Offline. Not
fixed in this round.

## OPEN — `firestore-tests/rules.test.js` ignores the emulator address the Firebase CLI injects (found 2026-09-16)

**P3, test harness only.** `rules.test.js` reads `FIRESTORE_EMULATOR_ADDRESS`
and `FIRESTORE_EMULATOR_PORT`. `firebase emulators:exec` (firebase-tools
15.29.0) sets `FIRESTORE_EMULATOR_HOST` and
`FIREBASE_FIRESTORE_EMULATOR_ADDRESS` instead. The suite therefore always
targets port 8080 unless `FIRESTORE_EMULATOR_PORT` is set. CI is unaffected
because it uses the default ports. An alternate-port run, such as
`--config firebase.qa-gate.json`, would miss its emulator or reach a different
one. The workaround is documented in `firestore-tests/README.md`. The Storage,
Family Memory and Servers suites already read the injected variables.

## FIXED IN SOURCE — committed docs linked to four uncommitted records (2026-09-16)

`Bugs.md` (twice) and ADR-173 linked to `Sessions/2026-09-10-claude-integration.md`,
and the 2026-09-11 Servers session linked to
`agent_handoffs/claude-continuation-at-codex-limit.md`. Neither file had ever
been committed. Both are now committed with dated outcome banners
(`244f2dbe`), and the relative-link check over `docs/` went from 4 broken
links (HEAD `e8f0e0ce`) to 0. In the same round, this checkout's canonical
docs turned out to be stale copies from before `d02cef5a`. Committing them would
have deleted the Build 27 runbook and reintroduced a false claim that the
Functions package `deploy` script deploys a single function (it runs
`firebase deploy --only functions`). They were restored from HEAD before the
media-collaboration documentation was added, in the same docs commit as this
entry.

## PENDING VALIDATION — Yeels double-tap/autoplay and custom-audio synchronization (Build 27)

Build 27 contains the current double-tap-like and feed-autoplay corrections,
but their final regression result and release review are still outstanding.
The video-plus-selected-audio path is under the same hold: its final playback
synchronization check has not yet closed. Keep both items labelled **pending
validation** in release notes and tester guidance until the owning engineer
reports the exact focused gate and principal review. Source presence alone is
not evidence that either playback path is fixed.

## FIXED IN SOURCE — the desktop redesign preview drifted from the current app (Build 27)

The local redesign preview now uses the same current Home, Servers, Chats,
Friends and YO Moments destinations as the app at desktop widths. Its Servers
destination uses production content slot 13, `ServersScreen` and the current
repository wiring; the preview controls link directly to Servers, Chats and
Friends. Responsive coverage includes 1280 and 1440 px, plus the 1100 px / 200%
text Server workspace regression. The shared Hub bar/dock, its geometry,
behavior and animation were not changed; its only retained cutover is the
previously approved Rooms-to-Servers destination replacement.

## FIXED IN SOURCE — Build 27 feed and chat state was visually ambiguous

YO Moments now names its text selector **Głos** and **Yeels** across the shared
responsive chrome. Photo Yeels omit the meaningless elapsed-time label, while
video Yeels retain their time indicator. **Add friend** state is shared per
author, so repeated cards for one creator converge together, and a refused
request exposes retry instead of leaving a false success. In Chats, an unread
conversation marks the complete row rather than relying on one small sublabel.

## FIXED IN SOURCE — archive could duplicate intent after a lost acknowledgement

Archive and unarchive now retry one ambiguous lost acknowledgement with the
same `requestId`, allowing the server ledger to replay the original operation
instead of creating a second intent. The Chats row keeps a visible busy state
and disables the conflicting archive action while that bounded request is in
flight, including a cold Function start. Permanent refusals are surfaced and
are not retried.

## FIXED IN SOURCE — startup art could disappear before it was readable (Build 27)

The integrated startup flow keeps Voice Glass visible for at least 1.4 seconds.
Authentication and profile provisioning may keep it on screen longer; the
minimum does not replace either readiness gate. This supersedes the original
startup-slice note that deliberately added no minimum display time.

## FIXED IN SOURCE — call and semantic notification cues lacked one current sound language

Build 27 carries the generated **Prism Halo v5** sound family for outgoing,
incoming and terminal call states plus the mapped semantic notification cues.
The deterministic generator and checked-in assets remain the source of truth.
This source record does not claim a physical-device loudness or focus-mode
acceptance run, and the pending Yeels custom-audio check above is a separate
media-playback boundary.

> **A pattern, named once here rather than four times below.** Between
> 2026-08-19 and 2026-08-20, four features were found to exist in source,
> pass their tests, and — where a backend was involved — be deployed and
> ACTIVE, while being unusable by any user: room voice, club chat
> moderation, message reporting, and Home's club-discovery rail. The
> unifying mechanism is that the emulator does not enforce composite
> indexes, rules tests exercise fixtures the test author wrote rather than
> what the client actually sends, and `fake_cloud_firestore` does not
> evaluate rules at all — so **a green suite can coexist with a feature
> that cannot work.** When triaging anything below, check reachability
> before believing the code.
> [ADR-082](Decisions.md#adr-082-a-feature-is-not-shipped-until-a-user-can-reach-it--reachability-is-part-of-done-and-a-green-suite-cannot-prove-it).

## FIXED IN SOURCE — Yeels chrome masked too much of the footage (2026-09-13)

The immersive phone layout now gives the footage the full available stage and
keeps reactions in one narrow trailing rail. Sound remains a separate top-edge
target; author, follow and one-line caption stay in the lower safe zone; and the
progress bar sits at the media edge. Large counts cannot widen the rail, authored
links avoid every chrome zone, short landscape screens use a shallow fallback,
and desktop keeps its responsive card presentation. The revised legacy
contracts and the focused geometry, accessibility, playback and composer matrix
pass **177/177**, including touch-drag placement for text and link overlays.
The 319 x 723 dark phone render was inspected in the live browser preview. The
shared Hub dock was not changed.

## FIXED IN SOURCE — private chat media lacked a full-screen viewer and queued slowly (2026-09-13)

Received photos and videos now open in a full-screen viewer with close, retry,
scrub and rotation handling. The viewer reuses the authenticated bytes or
controller already owned by the message instead of downloading the same private
object again. Sending streams the selected file into a persistent outbox, returns
the conversation UI before network completion, and drains independent text and
media work concurrently. Account changes, late playback and upload generations
are fenced so one session cannot adopt another account's result. Focused private
media, outbox and account-lifecycle verification passes **97/97**. Incoming
private video still buffers a bounded file of up to 64 MB before local playback;
real-device weak-network startup remains an acceptance check.

## FIXED IN SOURCE — Chats and Friends hid the path to adding a friend (2026-09-13)

Chats now shows separate, visible actions for **Add friend** and **New message**.
Add friend opens the existing retained Friends destination without changing the
Hub dock. Friends has a clearer search-first flow, simpler invitation states and
filters for existing connections, backed by lazy responsive lists. The combined
Chats/Friends widget and navigation slice passes **72/72** focused cases.

## FIXED IN SOURCE — direct calls raced setup, teardown and retry (2026-09-13)

Direct voice and video calls now serialize join lifecycle changes, bound provider
and Firestore waits, recover from canonical snapshot timeouts, and reconcile
manual microphone and camera commands with the current session. The client slice
passes **150/150** focused cases; the callable configuration passes **8/8** and
the Firestore-emulator direct-call slice passes **47/47**. A proposed warm
`acceptDirectCall` instance takes effect only if Functions is deployed and may
add roughly USD 8/month. No physical two-device call was available in this
source round, so device-to-device media quality remains an explicit release
acceptance check.

## FIXED IN SOURCE — Podcast and Community stage moderation had no Flutter path (2026-09-13)

The backend already enforced generation-bound participant role changes and
separate host/server mute authority, including hierarchy and token revocation,
but the Flutter repository exposed neither callable and both stage surfaces had
no moderator controls. Joined Podcast and Community hosts/moderators can now
move reported participants between stage and audience and explicitly apply or
release their own mute dimension. The client validates the receipt binding,
does not infer the two mute flags from provider audio state, and leaves the
backend to re-prove target hierarchy. Focused repository and widget tests cover
the exact callable payloads, unauthorized UI absence, both explicit mute
commands and success receipts.

## FIXED IN SOURCE — the Reels details caption was empty to screen readers (2026-09-13)

At 200% text the immersive Reel stage intentionally moves the full caption to
the **More** sheet. Flutter Web exposed its raw `SelectableText` there as an
unnamed, disabled text box with no value, so a screen-reader user could open the
only visible route to the caption and still hear none of it. The details sheet
now publishes one explicit static semantic label and excludes the broken inner
textbox semantics. The focused accessibility matrix passes for dark and light
themes at 320x568 and 390x844 with 200% text (`42/42`), and a live browser
retest reads the complete caption at both 100% and 200%.

## OPEN — Flutter Web keyboard skips the unchanged mobile dock (confirmed 2026-09-13)

The five dock cells retain correct accessible names and 78x64 targets, but
browser `Tab` traversal moves past the page without visiting them. Pointer and
semantics activation still work. This predates the Servers/Home/Moments visual
cutover and remains outside that cutover's frozen navigation component. A
future isolated fix must preserve the dock's current geometry and ordering
while making Start, Servers, Chats, Moments and More focusable with `Tab`,
Enter and Space. Modal bottom sheets also emit a lower-priority Flutter Web
warning because their route semantics have no label; their content, close
button and Escape behavior remain usable.

## FIXED IN SOURCE — three Reel voice-comment defects the principal gate found (2026-09-13)

This unreleased source-only slice (ADR-187, ADR-191) was never deployed with
these defects. Evidence:
`yovoice-evidence/2026-09-12/voice-comments-principal-1.md` (found) and
`voice-comments-fix-1.md` (fixed).

- **A result-shape break against every installed client.** The backend draft
  added `audioQueued` to `deleteReelComment` and `removeReelComment`. Installed
  builds parse those results with an exact-key reader, so a committed deletion
  would have been reported as a failure. Removed from both results and their
  ledger replays; the rule is now in ADR-187.
- **The Reel thread's mic had no semantics tap action.**
  `excludeSemantics: true` dropped the IconButton's action and nothing replaced
  it, so Switch Control and semantics-driven activation found a button that did
  nothing. `onTap` now mirrors `onPressed`.
- **The Moderation Center could not tell a voice report from an empty text
  one.** Nothing read `targetCommentType` or `targetDurationSeconds`; an
  uncaptioned voice comment reached staff as a text report whose snapshot "was
  not retained". The report model now parses both, and the queue and detail
  panel name the target "Voice comment · m:ss" with the caption as its own
  field.

## FIXED — a legal 81–120 character display name could make Reel and Voice comments fail (found 2026-09-13, fixed 2026-09-18)

`updateMyDisplayName` and `canonicalPublicProfile` accept up to 120 characters,
but `canonicalPublicProfile` truncates to 80 without re-trimming
(`functions/integrity/guards.js`), and every comment validator caps
`authorName` at 80 with trim equality (`validateReelComment`,
`validateReelVoiceCommentReservation`, `validateVoiceReservation`, the Reel
reservation and root validators). A name whose 80th character is a space
therefore yields an `authorName` no reader accepts. **Deployed today on the
text path:** `createReelComment` writes the comment and increments
`commentCount`, but the comment is invisible, and neither its author, the
Reel's author nor a moderator can delete or remove it. In the undeployed voice
path, finalize refuses after the upload, on every retry. Found independently
by the principal gate (F5) and the adversarial audit (F2, P2). Suggested repair
from both: re-trim inside `canonicalPublicProfile` and assert the reader's
bound at every write that stores the canonical name. Not fixed in this round.

**Re-confirmed 2026-09-16 (RC-8), still present at `58853fb0`.**
`guards.js:258` was byte-identical at `585740dc`, `22cc2313` and that HEAD, so
the tester repair deploy did not touch it: it was the next publish failure in
line behind the outage above, and RC-5 then locked the composer on top of it. It
could not fire on that data — the longest live display name was 26 characters
when all 32 production profiles were checked on 2026-09-16.

**FIXED 2026-09-18 in `41bbe057`, and the fix is the opposite of the repair both
reviews suggested.** Asserting the reader's bound at the *writer alone* would
have turned every legacy row into a permanent `data-loss` refusal — the
principal gate caught exactly that in the first attempt (`b31-gate-2.md`, G-1).
The shipped rule is reader-repairs / writer-projects:
`canonicalStoredDisplayName` trims before **and** after a cut that
`truncateToWholeCodePoints` takes back to the last whole code point (a naive
80-unit slice can split a surrogate pair, and the lone high surrogate that
leaves is not encodable as UTF-8), and `public_profiles.js` applies the same
projection at the writer through `safeDisplayString`. Only a projection with no
visible character is refused. See
[ADR-202](Decisions.md#adr-202-a-canonical-display-name-is-repaired-at-the-reader-and-projected-at-the-writer-never-refused-at-either).
**Deployed 2026-09-18 for the seven named targets only** — the ~238 other
exports still carry the pre-fix reader, which is safe because the change is a
relaxation and the writer now emits values the old guard also accepts. The
comment callables (`createReelComment` and friends) are **not** among the seven,
so the text-comment symptom above is still live in production until they move.

## OPEN — two localization defects on Home found by a catalog audit (2026-09-12)

Found by the Localization Specialist while verifying the Home "Tu i teraz"
catalog. Both predate the Home redesign work, both are in committed code, and
neither is caused by the new Home strings. Recorded here because Home is about
to put each of them in front of a user.

- **Bulgarian and Greek Home mix the polite and familiar registers on one
  screen.** `home.*` addresses the user informally in bg, el, hr, lt, lv, sr and
  uk (`На живо за теб`, `Ζωντανά για σένα`, `Tvoj krug`, `Tavo ratas`) while the
  rest of those catalogs — Settings, auth, the language picker — addresses them
  formally. That split is a product decision and is listed as such. The *defect*
  is narrower: in bg and el one `home.*` string is on the wrong side of it, so
  the same Home screen shows both registers.
  `lib/core/localization/translations/translations_home.dart`,
  key `home.fromPeopleYouFollow` (the followed-Moments rail heading):
  bg `От хора, които следвате` and el `Από άτομα που ακολουθείτε` are polite
  second-person plural, next to `Твоите хора` / `Οι δικοί σου` on the same
  screen. The fix is one verb form each — bg `…които следваш`, el `…που
  ακολουθείς` — and is held for a qualified native review rather than applied by
  the agent that found it. Everything else in the 41-locale Home set was audited
  key by key and is register-consistent with its own catalog.
- **Durations render in ASCII digits while dates in the same view render in the
  locale's digits.** `VoiceMoment.durationLabel`
  (`lib/features/moments/data/models/voice_moment.dart:201-205`) builds `"1:05"`
  from `int.toString()` unconditionally, whereas dates go through
  `DateFormat.yMd(localeKey)`
  (`lib/core/localization/app_localizations.dart:516`), which emits Arabic-Indic
  digits for ar and fa. Any surface that shows both — the Home friend tile's
  "Voice {m:ss}" next to a relative time, the Moments strip, the Reel player —
  shows two numeral systems side by side in ar, fa, and wherever else the locale
  data asks for non-ASCII digits. Not a crash and not a data problem; it reads as
  unfinished localization. The screen-reader path is already correct: Home speaks
  the duration through `AppLocalizations.secondsCount(n)`, never "0:45".

## FIXED IN SOURCE — two defects the first Simulator run found (2026-09-11)

The approved Home/Voice/Reels redesign had widget tests and rendered captures
but had never been run on a device frame. The first iOS Simulator run (iPhone
17 Pro, iOS 26.5, fixture-fed `lib/dev/redesign_preview.dart`, Polish, dark)
showed two defects no widget test had caught, both now fixed:

- **A status broke inside a word.** Home's people rail rendered "Nie
  przeszkadzać" as "Nie przesz / kadzać": Flutter breaks a word wider than its
  line, and "przeszkadzać" is wider than the 62 px label column. The column is
  now at least as wide as the status's longest word, measured in the rendered
  style and text scale (`lib/shared/widgets/profile/people_status_ring.dart`).
  `test/people_status_word_wrap_test.dart` covers four statuses at 1x/1.3x/2x
  text with and without the availability caret, and was proven to fail against
  the old width. The default test font draws every glyph as a square, so the
  test loads Inter — measuring text in the test font would have hidden this.
- **Scrolled content collided with the clock.** Home pads itself below the
  status bar instead of sitting in a `SafeArea`, so scrolled section headings
  slid under the system glyphs. `StatusBarScrim`
  (`lib/shared/widgets/layout/status_bar_scrim.dart`) paints a non-interactive
  band in the page background over exactly the top inset, and nothing when
  there is no inset. `test/status_bar_scrim_test.dart` covers both themes,
  hit-testing and the no-inset case.

Both were verified on the Simulator after the fix. The 290 Home, rhythm,
status-ring and localization cases pass. Lesson: the redesign's captures were
generated at fixed logical widths with the test font, which cannot show either
defect; a device frame with the shipped font and a real status bar can.

## FIXED IN SOURCE — Home error announcement competition (2026-09-11)

Several failing Home sections created competing polite live regions. A shared
visible-surface announcement scope now batches assertive errors, deduplicates
active episodes and withdraws recovered/unmounted errors. Seven author
regressions and independent QA cover the corrected behavior; the frozen Home
scope passed 326/326 focused tests and final read-only review. Not deployed;
physical VoiceOver/TalkBack remains a separate acceptance gate.

## FIXED IN SOURCE — Voice playback ownership and stale discovery (2026-09-11)

Two clean pre-fix regressions reproduced a viewed event before successful
playback and a stale A media-grant failure replacing B's current playback
state. The single-player/generation redesign now passes independent 132/132
focused tests and final review. Later adversarial tests also closed recovery
intent adopting a new account epoch and a late read resurrecting a confirmed
deletion. Opaque continuation cursors and failed-delete behavior are preserved.
The subsequent complete Flutter run passes 3686/3686 after explicitly reviewed
old-layout fixture adaptations and bounded localization. These are controlled
local transport/widget results, not deployed or real-device playback proof.

## FIXED IN SOURCE — immersive Reel overlay collisions and translated controls (2026-09-11)

Independent geometry tests reproduced opposite-edge authored links colliding
at 1440 px/200% text. Removing unused top spacing and refining short-height
layout closes the tested collision without dropping controls. Hidden source
replacement cannot start playback, and stale link/private-sheet callbacks
retire on account, expiry and host changes. The frozen Reels/Share slice passed
76/76, with all twenty independent captures and four white-footage captures
inspected. This does not establish actual provider or native sharing behavior.

The final feed audit also found newly visible English fallback controls and
numeric time/footer strings being used as dynamic lookup keys. Twenty-four
stable keys across 41 additional catalogs now cover that bounded surface;
existing relative-time keys are reused. Independent review passed 748/748,
preserved EN/PL timing/count behavior and inspected twelve locale renders.
This is not a claim that every older application string is translated or has
received qualified native-language review.

## FIXED IN HELD SOURCE — Servers review findings (2026-09-11)

- Concurrent participant revocations could allow a fresh token after the
  first ACK while another RemoveParticipant still ran. A durable single-owner
  attempt, no timeout reclaim/retry and a confirmed cutoff close the race.
- Ended/revoked historical recipients still reported pending recovery after
  an authorized generation end. Validated terminal reconciliation is now a
  read-only completed result, without touching the new session.
- The offline mapping report treated partial V1 markers as legacy and failed
  to report a bound-room host/server-owner conflict. Both now block mapping
  instead of proposing a normal legacy conversion.
- Final-page deletion happened before revocation receipts were durable. If
  DeleteRoom succeeded remotely but its ACK was lost, retrying removals against
  the absent room could remain pending indefinitely. Durable receipt/checkpoint
  commits now precede one generation-bound DeleteRoom; terminal retry is
  delete-only. At most twenty actual SDK calls/four concurrent removals run per
  invocation, and failed batches await all started requests before release.

The earlier findings were reproduced independently before correction. Session
QA **83/83** and mapping QA **33/33** passed on Node22. The terminal defect had
two explicit RED cases; the expanded runtime/bridge union now passes **128/128**
and a new independent terminal set **11/11** twice. Final independent review
accepted the held adapter, and the complete fresh Functions run passes
**1772/1772** with unchanged hashes. These
are unexported runtime/offline tooling changes, not deployed fixes for current
tester calls. Integration and physical/provider acceptance remain open; see
[the checkpoint](Sessions/2026-09-11-servers-runtime-and-mapping.md).

## FIXED IN SOURCE — integration/review regressions in the Claude round (2026-09-10)

The completed integration and independent reviews found and closed:

- GIF search could remain loading after a one-character edit; repeated
  near-bottom events duplicated paging requests; slow catalog startup and
  tab remounts could desynchronize the visible query/results. Controlled
  futures now cover cancellation, paging ownership and query restoration.
- GIF preview retry intercepted picker selection/report gestures. Received
  bubbles retain retry, while picker cells own their selection/report input.
- Narrow moderation detail unmounted its search field while retaining a
  hidden active filter. The parent now owns the controller; detail/back/clear
  tests preserve visible text and actual filtering together.
- At 200% text, Chat lost primary identity, moderation hid the focused note,
  Club media cards overflowed, and Podcast dropdowns exceeded their width.
  Strict real-widget captures verified the corrected visible bounds rather
  than draining rendering exceptions and declaring a green harness.
- GIF block/report/audit and canonical DM tombstone/audit were not atomic;
  Club removal retained a media snapshot. Current transactions preserve
  authorization, exact DM schema, conditional previews and durable audit.
- Initial Reel seen-rule hardening exceeded Firestore's document-call budget,
  then mishandled absent restriction resources. The final resource-null
  checks fit nine worst-case calls; real allow/deny and expired-mute cases
  pass in the emulator.

Final evidence: Flutter 3289/3289, Functions 1580/1580, Rules 564/564,
strict visual gate 142/142 and independent reviews with no actionable
findings. **Not deployed or native-device-certified**; external gates remain
in [the integration record](Sessions/2026-09-10-claude-integration.md).

## FIXED — a host's "Your active rooms" disappeared from Home as soon as the board had more than one room (found and fixed 2026-09-09)

Both Homes render the owned-rooms section from a `StreamBuilder` placed
AFTER a variable-length block ("Rooms for you", 0 or 2 children on mobile,
0 or 2 on desktop). The child carried no key, so `SliverChildListDelegate`
matched it by index: the moment the live board grew, the section shifted
position, its element was rebuilt from scratch, and the new `StreamBuilder`
re-subscribed to `watchOwnedRooms()` — a broadcast stream that had already
emitted. It never emitted again, so `hasData` stayed false forever and the
section silently rendered `SizedBox.shrink()`. No error, no empty state: a
host simply could not see or enter their own rooms from Home.

Reproduced with three live rooms, one of them hosted by the signed-in
account: the stream logged `[Morning Coffee]` while the heading count was 0.
Existing coverage missed it because the fixture seeded the owned room as
NOT live, which leaves the board at one room and the section at a stable
index.

Fixed by keying the child (`ValueKey('home-owned-rooms')`) on both platforms
so its element survives the shift. Pinned by "a host keeps 'Your active
rooms' when the board also fills 'Rooms for you'" in
`test/mobile_home_test.dart`.

## FIXED — the empty recent-chats note overflowed a 320 px Polish Home by 33 px (found and fixed 2026-09-09)

`_RecentChatsMessage` stacked its action under the note only at a text scale
of 1.6 or more. At ordinary scale on a 320 px phone, "Znajdź znajomych" plus
the icon and the note is wider than the 254 px the card leaves, and a `Row`
cannot shrink a button — so the row overflowed. English fitted, which is why
it survived; the failure was locale-shaped, not scale-shaped.

Fixed by stacking on WIDTH as well as scale (`< 300 px` of card interior),
which is the rule `HomeQuickActions` already applied. Caught by
`test/home_rhythm_test.dart`, which pumps Home in Polish at 320.

## FIXED — the Reel overlay footer swallowed every tap in the lower 40 % of the frame (found and fixed 2026-09-09)

`_OverlayFooter` wrapped its content in a `DecoratedBox` carrying the footer
scrim gradient. `RenderDecoratedBox.hitTestSelf` returns
`BoxDecoration.hitTest(...)`, which is **true over the whole box** for a
rectangular shape — so the scrim, not the empty space it looks like,
absorbed pointers across its entire area. Anywhere below roughly the 60 %
line of a Reel, a tap reached nothing at all: not the playback surface, not
the author row, nothing. The comment above the footer in `reel_card.dart`
asserted the opposite ("The empty area of this layer takes no hits"), and the
earlier hit-geometry measurement missed it because it measured the rectangles
of the *controls*, which really do cover only ~12 % of the card.

Found while writing autoplay coverage: `tester.tap` on the playback surface
reported "derived an Offset that would not hit test on the specified widget"
and the hit result ended at the footer's `RenderDecoratedBox`.

Fixed by making the scrim a sibling behind the controls —
`Stack[Positioned.fill(IgnorePointer(DecoratedBox)), Padding(content)]` —
which is the same shape `_LegibilityScrim` already used. `Padding` and
`Row`/`Column` do not hit-test themselves, so empty footer space now falls
through to the playback surface. Covered by
`test/reel_autoplay_test.dart` ("a tap still pauses, and autoplay does not
fight it"), which taps the centre of the card.

## OPEN — `users/{uid}/muted` is dead surface, so a muted author still fills the feed (found 2026-09-09)

`firestore.rules` declares `users/{uid}/muted/{mutedId}` as "the personal
mute list: hides that user's content for THIS account only", owner
read/write. It has **zero readers and zero writers** anywhere in `lib/` or
`functions/`. Nothing writes a mute, nothing consults one.

Found while wiring feed ranking (ADR-167), which deliberately did **not**
consume it: building an ordering on a list nothing writes would be
fabricating a feature. So a "muted" author's Reels appear in the ranked feed
exactly as anyone else's would. Pre-existing, but the ranking work makes the
omission more visible — either wire the mute list up end to end, or delete
the rule rather than leave a permission granting access to a collection with
no purpose.

## FIXED IN SOURCE — Reel feed ranking lacked its client integration (2026-09-10)

**Resolved in source 2026-09-10, not deployed.** The screen now wires own-feed
scope, genuine decoder-progress watches, cursor recovery and caught-up/replay
states. The text below records the original defect, not current behavior.
Current proof and remaining external gates are in
[the integration record](Sessions/2026-09-10-claude-integration.md).

The server side of ADR-167 is on `main` and tested; none of it is deployed,
and three client pieces it depends on do not exist:

- **Nothing writes `users/{uid}/reelViews`.** The seen ledger the ranker
  reads is empty, so seen suppression and the `W_SEEN` penalty are inert.
  The write must fire on a *genuine watch* — the card is active, has been
  active ≥2000 ms, and for video playback advanced ≥1500 ms. Marking on
  mount would be actively harmful: with autoplay, one fast scroll would mark
  the whole corpus seen and empty the viewer's own Discover feed for six
  hours. That threshold is load-bearing and needs its own widget test.
- **Nothing sends `scope: "own"`.** Your Reels is still a client-side filter
  over the global feed, which is why one toggle can fire four serial
  `listReelsV2` calls.
- **`ReelService.fetchFeed` does not clear the cursor on `invalid-argument`.**
  Without that, a client holding a cursor the backend rejects retries the
  same rejected value indefinitely, because `_load(reset: _cursor == null)`
  keeps the bad value. This protects a whole class of failure, not just this
  change, and it is not optional polish given the codec is a one-way door.

## FIXED IN SOURCE — Reel inline grants lacked backend and player integration (2026-09-10)

**Resolved in source 2026-09-10, not deployed.** Both halves are connected.
Inline minting is capped at four attempts per list call and 1500 ms total,
then fresh audience authorization is checked. Failure omits the hint, not
the item; the existing dedicated media callable remains the fallback.
The following description is the original discovery context.

ADR-168 shipped the client half of the inline media grant: `Reel` accepts an
optional `mediaGrant`, `ReelService` seeds its cache from it, and the
`mediaGrants` request flag is probed safely against a backend that does not
know it. Nothing about it is user-visible yet, because two halves are
missing.

- **`listReelsV2` neither accepts `mediaGrants` nor returns `mediaGrant`.**
  The allow-list at `functions/reels/service.js` is
  `["cursor", "limit", "scope", "includeSeen"]`. Until it also allows
  `mediaGrants`, every process pays one extra `listReelsV2` on its first feed
  load (the probe) and no grant is ever inlined. The refusal costs no rate
  budget — `requireExactInput` throws before `consumeReadLimit` — but it is
  a wasted round trip. **When that key is added, the mint must also assert
  the CALLER's own `users/{uid}` and `restrictions/{uid}`**: `visibleFeedItem`
  checks the *author's* account and restriction and both block directions,
  not the viewer's, while `authorizeMediaAccess` does check the viewer's. A
  grant minted off the feed's checks alone would hand media to a viewer whose
  own account is disabled or restricted. Those two documents belong in the
  first batch `getAll`, and the minted grants must consume the `mediaAccess`
  budget, not the `list` one.
- **No screen calls the new seams.** `ReelService.cachedMediaUri` (a
  synchronous first-frame read), `prefetchMediaUri` (one neighbour) and
  `resolveMediaUri(forceRefresh: true)` (recovery when a player fails on an
  expired signature) all exist and are tested, and none of them is called
  from `reel_card.dart`, `reels_feed_screen.dart` or `moments_screen.dart`.
  Until they are, an expired grant mid-session still ends at
  "This Reel is unavailable right now." with a manual Retry, and the first
  card still waits a frame on a `FutureBuilder` whose future is already
  complete.

## OPEN — feed weights are unvalidated guesses and the seed is deliberately unlogged (2026-09-09)

Two consciously accepted gaps in ADR-167, recorded so they are not
rediscovered later as surprises.

The five ranking weights have no offline evaluation behind them — this
project has no evaluation data and none can be produced honestly — so "is
this ordering good" is unanswerable until it ships. Mitigation is
containment, not confidence: one frozen `FEED_RANKING` object, emitted in
the new per-request log line, flippable by environment variable.

Separately, the per-request log deliberately omits the session seed, the uid
and every Reel id, because a (viewer, reel) pair is viewing history. The
cost is that "why did I see this Reel first" cannot be reconstructed after
the fact for a support request. That is a privacy trade taken on purpose.

Also unverified: `users/{uid}/reelViews` is new personal data, and no
account-deletion or data-export fanout over user subcollections exists
anywhere in `functions/` (`deleteAccount` appears only as a sanction name in
tests). The 90-day TTL bounds exposure but does not satisfy an erasure
request, and the TTL itself is a manual `gcloud` step that is easy to forget
on deploy. Like `momentViews` and the other owner-writable subcollections,
`reelViews` now requires an active account and an existing, currently viewable
published Reel, bounds each row's shape/retention, and pins its `viewedAt`.
It is no longer an arbitrary-ID storage namespace. There is still no
per-account frequency quota on best-effort seen writes; privacy/export and
erasure obligations remain a separate unresolved lifecycle concern.

## OPEN — a Reel comment can be reported by nobody, and its author cannot remove one (2026-09-07)

This is the ADR-082 pattern again, in the direction the box above warns
about: the server half exists, is tested, and is **deployed**, while no user
can reach it.

`createReelCommentReport` and `removeReelComment` went live on 2026-09-07
(`33c5f3e5`, deploy recorded in
[DEPLOYMENT.md](DEPLOYMENT.md#backend-deploy-for-the-build-22-round--2026-09-07)),
and the Moderation Center on `main` already renders the `reelComment` filter,
the row, the quoted-text evidence block and the remove action. But
`ReelCommentsView` at `main` states in its own doc comment that it offers no
report control and no author removal — "Reel comments have neither yet" — and
`ReelService` carries no `createReelCommentReport` or `removeReelComment`
call. So a viewer who sees an abusive Reel comment has no way to file, and a
Reel's author has no way to clear it from their own thread; the only remedy
is still deleting the whole Reel. The moderator queue is real and can receive
nothing from the app.

The client half is written but **uncommitted** in the working tree
(`lib/features/reels/presentation/widgets/reel_comment_report_sheet.dart`
untracked, `reel_service.dart`/`reel_comments_view.dart` modified,
`test/reel_comment_moderation_test.dart` untracked). Nothing here claims it
works until it is committed and verified. Until then the honest reading is
that Reel comments shipped to `main` with creation and own-comment deletion
only.

## Room tiles showed the host's initial instead of their avatar (2026-09-07; fixed in source)

Discover's room cards and the live hero drew `room.hostPhotoUrl` with
`Image.network`. That field is a denormalized snapshot the app deliberately
stopped dereferencing when profile media became viewer-authorized: avatars
resolve from the uid through `ProfileMediaService`. With the field empty the
widgets fell back to the first letter of the host's name, so a host with an
avatar set still rendered as a circle with a letter. Both now pass `hostId`
to `UserAvatar`; the room-cover widget is unchanged.

## The More sheet covered the navigation dock (2026-09-07; fixed in source)

Opening More produced a full-width sheet that hid the dock, including the
More control itself. It is now a bounded floating card above the dock
(ADR-158).

## A Reel could not be liked or commented on at all (2026-09-07; fixed in source, backend deployed)

`getReelViewV2` had been returning `likeCount`, `commentCount` and
`callerLiked` on every v2 Reel and the client parsed them and discarded them —
nothing referenced the fields, and no engagement callable existed. `33c5f3e5`
adds `setReelLike`, `createReelComment` and `deleteReelComment`, each moving
the child document and the root counter in one Admin SDK transaction with an
idempotency ledger entry and a rate budget, and `591b8840` wires the feed to
them: an optimistic ±1 that the callable's aggregate replaces verbatim, a
refusal that restores the exact pre-tap values, and one `ReelCommentsView`
serving both the modal sheet (<1100 px) and the inline panel so the two
cannot disagree about a count. `reels/{id}/likes` and `reels/{id}/comments`
are stated `read, write: if false` rather than inherited from the parent
match. ADR-161.

Three defects the review caught in the same change: the wide Pearl footer sat
on the light card margin instead of the artwork, so white overlay text was
invisible; the panel composer floated mid-panel over dead space; and the like
control swapped its heart for a spinner while the call was in flight, which
took back the optimistic feedback it existed to give.

Backend live since the 2026-09-07 deploy. The client is source- and
widget-test-verified only, and is not in any published build. See the OPEN
entry at the top of this file for what the moderation half is still missing.

## No way to send an emoji on desktop or web (2026-09-07; fixed in source)

Direct chats, club chat and the in-room chat sheet had no emoji entry point:
the only emoji a person could send were whatever their system keyboard
offered, which on desktop and web is nothing at all. The fixed reaction sets
(six for direct messages, five in rooms) were the only emoji surfaces in the
product. `YoEmojiPicker` (`23a3739c`, ADR-159) is one widget shared by all
three composers — roughly 840 emoji in the standard categories, name and
keyword search, per-device recents through the existing `AppPreferencesStore`
pattern, insertion at the caret rather than the end of the string, and it
swaps for the system keyboard instead of stacking on top of it.

Still true afterwards: **reacting** with an arbitrary emoji remains
impossible. `ALLOWED_DIRECT_REACTIONS` in the messaging Functions and the
pinned five-key map in `firestore.rules` still bound the reaction sets, so
widening those is a deploy and a moderation question, not a client change.

## The keyboard Done bar was never visible on any screen (2026-09-09; fixed in source)

Reported from a phone against the Voice Moment caption: Return only added a
line break, there was no visible way to stop typing, and Publish had gone
under the keyboard. ADR-149 had shipped `YoKeyboardDoneBar` for this and
this file recorded it as fixed. Two separate defects sat underneath.

1. On Record Voice Moment (and the Reel composer) the bar was placed inside
   `Scaffold.body`. `Scaffold` strips the bottom view inset from that slot,
   so the bar's only render gate — `viewInsets.bottom > 0` — was never true
   and it rendered nothing at all.
2. On every other screen the bar was in `bottomNavigationBar`, and
   **`Scaffold` does not lift that slot above the keyboard**: it shrinks the
   body and leaves the bottom chrome pinned to the bottom of the window. On
   390x844 with a 336 px keyboard the bar sat at y 796–844 — behind the
   keyboard, on Create room, Create club, Club settings, Room settings and
   Edit profile alike. The widget test and the tester preview both passed
   because they only checked that the bar was in the tree.

Fixed by ADR-169: `YoKeyboardSafeBottomBar` lifts bottom chrome by the
keyboard inset (same surface: y 460–508), the Done bar can carry the
screen's primary action, the caption's Return confirms, and the regression
tests now measure rendered rectangles against the top of the keyboard rather
than asserting presence in the tree.

**Still to check:** the Reel composer's in-body bar (`reel_composer_screen`)
starts rendering as a side effect of the view-inset fallback. That path was
locked to another workstream during this change, so it has had no visual
check — and the composer's own primary action has not been reviewed against
this rule. Two chat composers (`chat_screen.dart:2696`,
`club_chat_screen.dart:757`) still declare `onSubmitted` with no
`textInputAction`, so those callbacks are dead code; both screens dock a
send button, so they are not keyboard traps, but the callbacks should either
get `TextInputAction.send` or be deleted.

## Voice Discover rendered every entry as a full-width slab (2026-09-07; fixed in source)

Reported by the owner as "wielkie klocki": the Discover pool laid every
engagement-ranked pick out as a full-width audio card of identical weight, so
two or three filled a phone screen and nothing signalled what was worth
opening. `moment_discover_tiles.dart` (`301eebc4`, ADR-160) gives density by
role instead — featured entries in a two-column grid, recent ones in a tight
row per Moment, the seen-aware story strip above them. Every action the slab
carried (play, open, delete your own, report, expiry countdown) is still
reachable, the rare ones behind the row's overflow menu. What Discover
*shows* is unchanged: the same audience and block rules still decide what
reaches the list. Captions now truncate to one line in the grid.

## OPEN, deferred by decision — a "Stay open" Community room still ends when the host leaves (2026-09-07)

Reported by the owner: a Community room created with the **Stay open**
option — copy that promises "People can keep talking after you leave" — is
gone from every live list once the host goes. The report was traced on
2026-09-07 and the room turns out not to be deleted; the cause is a chain of
three server facts, and the two changes that would make the promise true both
widen who can trigger global fanout. **The full analysis, with file and line
references and the two proposed changes, is in
[DEPLOYMENT.md](DEPLOYMENT.md#stay-open-community-rooms-cannot-actually-stay-open--server-proposal-2026-09-07)
and is not restated here.**

**The maintainer decided on 2026-09-07 to leave this for a later round.** It
is deferred deliberately, not forgotten, and nothing in the app was changed
for it — so the option still promises more than it delivers today. The
smallest honest interim fix named in that analysis is client copy saying what
actually happens (the room stays, voice sleeps when it empties, the host
reopens it); that has **not** been applied either.

Adjacent but distinct: Roadmap item 0p is the *opposite* failure — a
member-started room staying live with nobody in it — and is separately
landed-in-source, not deployed. Do not conflate the two.

## Home showed one person instead of the friends list (2026-09-06; fixed in source)

The live-first Home replaced the old "Your people" row and never brought it
back: `MobileHome` and `DesktopHome` both accept a `FriendService` and never
called it, so the only people on the screen came from the follow graph —
`MobileVoiceTrending` caps that at two rows and the desktop creators card at
four. An account with a dozen friends therefore saw one person, and the
count never matched the Friends tab.

Fixed by `HomePeopleStrip`
(lib/features/home/presentation/widgets/shared/home_people_strip.dart): the
account's real friends from `FriendService.watchFriends()`, online first then
alphabetical, with the shared availability ring language (green available,
yellow be right back, red do not disturb, grey offline) and a See all that
opens the Friends tab. It renders nothing when there are no friends, when the
read fails, or when there is no session — never a fabricated row. The strip
takes its height from the measured text so 200 % text at 320 px does not clip
the status label. Covered by test/home_people_strip_test.dart; the Moments
rail assertion in test/mobile_home_test.dart was scoped to the rail, since a
friend without a Moment is now legitimately visible elsewhere on Home.

## Build 21 tester round — navigation, latency and creation gaps (2026-09-06; partly fixed in source, no client published)

Reported by the owner after the 1.0.0 (21) tester wave. Every fix below is
source- and test-verified only: **no build carrying any of them has reached a
tester.** Rules and Functions were deployed on 2026-09-07, so the backend
halves are live while the client halves are not. Status per item:

- **Torn screen on tab switch** — fixed in source (ADR-147): fade-through
  without offset, Home keeps its last feed page while refreshing.
- **Dock lit Home inside a More destination** — fixed in source: hosted
  destinations keep the More capsule lit.
- **Friends chat bubble "does nothing" / needs several taps** — fixed in
  source: per-row busy state, 15 s bound on `openDirectConversation`, timeout
  copy. The remaining wait is the callable's cold start (server, see below).
- **Room entry, Reel publish, Voice Moment publish and staff panels slow** —
  root cause is shared: every hot-path callable except five is deployed with
  `minInstances: 0`, each cold start loads the whole 48-module
  `functions/index.js`, and the flows chain two callables plus an upload.
  Client share fixed in source (Moments refresh in place; Moderation reads in
  parallel; Staff Center paints from cache). Server share **needs an owner
  cost decision and a Functions deploy** — proposal in DEPLOYMENT.md.
- **Own music in the Reel composer never opens on iOS** — fixed in source:
  `XTypeGroup` now carries `uniformTypeIdentifiers`, which `file_selector_ios`
  requires before it will show a picker.
- **Avatar rings look heavy** — thinned in source (status rings 1.5/1.1 px,
  Premium frame 1.6 px, softer glow); colours stay the palette's semantic
  tokens because the ring test enforces 3:1 contrast on the surface.
- **UI sounds** — replaced by the v4 pack (ADR-148); not yet auditioned by
  the owner.
- **Draggable text/link overlays on the Reel canvas** — fixed in source
  (ADR-149): drag and pinch in the Text tool; sliders remain.
- **No "Done" over multiline keyboards** — the shared `YoKeyboardDoneBar`
  landed on every creation/settings form (ADR-149), but it was **not
  actually visible on any of them**; see the entry below for what was wrong
  and what fixed it (ADR-169).
- **"Delete friend" / "delete chat" missing** — Remove friend is now on the
  Friends list row (options button and long-press); chat rows offer
  Unarchive for archived threads. A true per-user "delete chat" still needs
  a server capability (`users/{uid}/conversationState` written by a new
  callable) — owner decision + deploy.
- **Mute lag of several seconds** — client share fixed in source: the
  control is released as soon as the local track is off (ADR-149). The
  server callable `setOwnRoomParticipantMute` still cold-starts at
  `minInstances: 0`; unmute remains server-first by design, so its wait is
  unchanged until that callable is warmed (DEPLOYMENT.md proposal).
- **Reel trimming on the video, and "a recording past a minute is lost"** —
  partly fixed in source (ADR-152). The publish contract's limit is
  `MAX_DURATION_MS = 90 * 1000` in `functions/reels/contract.js` and has been
  90 s since build 19 (`2529acc7`) — it was never 60 s. What the report was
  actually hitting is that the cap was **invisible** and the only way to get
  under it was a `RangeSlider` that froze whenever the two handles came
  within a second of each other, so long footage had no usable path to a
  publishable selection. There is now a Trim tool with draggable handles
  that scrub the preview, handles that clamp to a one-second minimum instead
  of freezing, and `Maks. 90 s` shown on the strip; the slider stays as the
  keyboard and screen-reader fallback. **Longer than 90 s is still refused**
  — raising it is a server change and a deploy (Roadmap item 0u).
- **Awards could not really be "used"** — fixed in source (ADR-151):
  selection has a hero, Clear, error feedback, no stray pop, and it colours
  the owner's avatar ring and name. Other people see it only after the
  follow-up server projection.
- **No way to invite a friend into a room** — fixed in source (ADR-153) for
  public rooms: Community (any participant) and Broadcast (host) open an
  invite sheet that sends a direct message with a room link, rendered as a
  room card in chat. The broadcast share link form was wrong and is fixed.
- **A call ended when both parties minimised the app** — fixed in source
  (ADR-154): the app declared no foreground service of any type, so a
  backgrounded process had its microphone silenced and was then frozen once
  cached; with both sides minimised no audio flowed either way and both
  LiveKit participants timed out. A foreground service now runs while a
  session is connected, typed from the session's own rights (microphone when
  the participant may publish and `RECORD_AUDIO` is granted, mediaPlayback
  for a listener), and `LiveKitClient.initialize()` runs before `runApp` so
  the iOS audio-session policy is seeded before WebRTC builds its audio
  device module. **Still required before release:** the owner must declare
  both foreground-service types in Play Console, and no two-device
  acceptance run has happened. **Reconnect-on-resume in the room screens
  remains open.**
- **A tester was asked for an invite code** — not an app defect. TestFlight
  shows that prompt when the Apple ID signed in on the device is not the
  address the invitation was sent to. No code change; kept here so the next
  report of it is recognised rather than re-investigated.
- **User-set availability (green/yellow/red/grey rings + picker)** — built
  in source (ADR-150) and **no longer blocked**: `firestore.rules` and the
  `onUserPrivacySourceChanged` projection carrying `deriveVisibleAvailability`
  were deployed on 2026-09-07
  ([DEPLOYMENT.md](DEPLOYMENT.md#backend-deploy-for-the-build-22-round--2026-09-07)).
  The picker's write is accepted by the deployed rules; no client build
  carrying the picker has been published to testers, so this is deployed
  backend plus unpublished client, not an end-to-end observation.
- **Open, not yet fixed:** a music library for Reels (needs a licensed
  catalogue and a backend — product decision, Roadmap item 0v); Reel length
  above 90 s (server `MAX_DURATION_MS`, the 100 MB video cap and a streamed
  upload, then a deploy — Roadmap item 0u); a true per-user "delete chat"
  (`users/{uid}/conversationState` written by a new callable — owner decision
  and deploy); and the cold-start latency on every hot-path callable outside
  the five warm ones. The 2026-09-07 deploy updated Function *code* and did
  not change `minInstances` for anything — the warm set is still
  `createLiveKitToken`, `startDirectCall`, `createDirectCallToken`,
  `sendDirectMessage` and `sendRoomMessage` — so the latency proposal in
  DEPLOYMENT.md is still a proposal.

## Direct-call latency and Android connection acceptance (2026-09-06; fixed in source, physical acceptance pending)

Testers reported that private audio and video calls took an exceptionally long
time to connect and that Android participants could not connect at all. The
source audit confirmed several independent client-side failure amplifiers: the
previous 60-second callable/retry windows could accumulate to roughly two
minutes, pending call actions made the UI effectively non-interruptible, a
microphone publication failure could still surface as connected, and late
connect, cleanup or camera futures could race teardown and revive stale media.

The direct-call operation is now bounded to 20 seconds, each callable attempt to
8 seconds and reconciliation to 3 seconds. The public LiveKit connect and
cleanup waits are bounded to 20 and 3 seconds respectively, while the underlying
audio cleanup barrier deliberately remains fail-closed: a timed-out stale native
session cannot authorize a replacement Room. Connected is exposed only after
initial media readiness. Late validated acknowledgements are retained solely
for cleanup, camera candidates are stopped across teardown races, and Close,
Back and End can cancel a pending presentation immediately. See ADR-146.

The source gate passes 2,534/2,534 Flutter tests, 47/47 emulator-backed
direct-call backend tests, `flutter analyze`, an Android debug APK build and an
Android release AAB build.
This does **not** prove the tester report resolved on real devices: no physical
Android device or current production Firebase logs were available during the
repair. Android↔Android and Android↔iOS tests on real devices, including a
poor-network run, remain a release condition. The repair changes no schema,
backend contract, Security Rules or TURN configuration.

## Build 20 fixes and remaining acceptance gaps (2026-09-05; invited testing)

### Reels authorship and creation report — local remediation, live acceptance pending

The reported cross-user authorship/creation failure is not reproduced in the
server contract: two authors can publish independently (including identical
request IDs and repeat publication), and three viewers receive unchanged
canonical author identities. Foreign finalize/delete and forged ownership are
denied. A screenshot/error from the affected installed account is still needed
to distinguish a live failure from the misleading personal-sounding entry.

Local changes separate Discover/Your Reels and keep Create visible, bind client
publication/retry to account identity, discard stale feed results, and redesign
Reels and Voice capture/review. QA additionally found auth-listener cleanup
blocking widget-zone completion, tablet caption focus loss, and inaccessible
creation controls in enlarged/short layouts; all have passing regressions.
Error copy now describes supported media and recoverable states instead of raw
backend messages. Native Simulator inspection also caught browser-only wording
on a native microphone timeout; the presentation now selects the correct
platform copy in all locales. Actual microphone acquisition timed out in the
Simulator, so successful device capture is not claimed. See ADR-145 and the
[creation-flow session](Sessions/2026-09-06-reels-moments-creation.md).

Remaining boundaries: own filtering uses bounded pagination rather than a new
server author query; imported backing audio still accepts 1–90-second licensed
or own files, not a commercial song catalogue. Reels publication retains its
existing authenticated-public audience and block checks, not Voice Moments'
private-profile audience behavior. New source is not yet a tester deployment;
physical separate-account upload/playback and installed-version acceptance
remain separate gates.

The later top-notification/mobile-Back work is source-only. Local review resolved
competing arrival surfaces, tooltip/root-overlay interception, insufficient
keyboard-space acceptance, unreachable notification keyboard controls, inherited
long-content scroll offset and stale foreground fallback after an identity change.
Retained mobile roots now have bounded Back history with canceled/stale gesture
guards and a landscape-safe indicator. Existing native protected exits are not
relaxed. Full evidence and remaining physical-device/push/assistive-technology
limits are recorded in
[the notification/Back session](Sessions/2026-09-05-top-notifications-mobile-back.md);
these changes are not claimed as part of the already-distributed Build 20.

Post-Build-20 Meniscus development found two local interaction regressions:
recognized pointer cancellation could commit a drag destination, and the
unread badge remained right-aligned in RTL. Raw pointer cancellation now
clears preview before recognizer end routing; the badge uses logical `end`.
Focused tests cover cancellation, rapid initial movement, denied navigation,
external selection and RTL. These changes are local/source-only, not part of
the already-distributed Build 20 runtime described below.

The Home/atmosphere review also exposed short-screen Chats header overflow and
truncated primary names at 200% text. Local presentation now uses coordinated
header/list scrolling and full-width enlarged-text identities. Rooms' idle
hero pulse respects Reduced Motion and offstage TickerMode. Home expiry now
recovers visible, actionable keyboard focus, including a horizontally scrolled
avatar rail. Featured copy and owner/staff controls have guaranteed contrast
backings over bright uploaded covers. Full regression passes 2364 tests and
independent source/visual review approved the changes; these remain source-only,
not claimed as shipped fixes.

Runtime `941376e` is deployed on Firebase Hosting and available to the existing
Google Play internal cohort of 15 testers. Both signed Build 20 artifacts were
uploaded once; iOS completed processing, has its internal cohort of one
assigned and is `Testing` for its existing external cohort of six. Five
non-owner TestFlight testers show `Installed 20` (observed at 12:07/12:11/12:13
CEST), and the user separately confirmed availability. The older P1 cleanup
defect found during post-deploy log review is now repaired and independently
verified recovered; external TestFlight advanced only after that hold was
lifted. Twenty separate tester emails have verified sender-side `SENT` evidence,
but tester email deliverability is blocked, not complete. One authorized-domain
probe reached the owner's Inbox with SPF/DKIM/DMARC PASS; this does not resolve
the cohort's bounces/spam. Marketing commit `975e5c6` is published with a
successful Vercel deployment and live read-back. This is not a public store release
or complete physical acceptance.

- **OPEN — separate tester-email deliverability is blocked.** Twenty unique
  recipients were each sent one plain-text email; Gmail `SENT` records and a
  separate sent-mail search verify twenty submissions, not deliveries. The
  user reports blocked Apple-cohort messages and Android spam placement.
  Mailbox inspection confirms four Apple-cohort hard bounces with status
  `5.7.1`, `Message rejected` and a reference to Gmail help 69585. Android spam
  is user-reported, not independently recipient-mailbox verified; the other
  sixteen emails are not assumed delivered. Manual resends were paused
  immediately while Gmail policy rejection is investigated. Native automatic
  TestFlight notification stays enabled; no tester-wide deliverability fix or
  completed email rollout is claimed. A separate owner-only probe from the
  existing authorized `hello@yovoice.app` Workspace alias was sent at
  13:05:51 CEST and received in Inbox at 13:06:03 on 2026-09-05 (twelve seconds),
  with original SPF PASS, DKIM PASS for `yovoice.app` and DMARC PASS. No DNS,
  sender, account or security settings changed and no tester resend occurred.
  Independent recipient-side Gmail read confirms Inbox placement, actual
  From `hello@yovoice.app` and the same authentication results.
  This proves one domain-sender inbox delivery, not the cause of the earlier
  `5.7.1` rejection. Future tester email is intended to use that authorized
  domain mailbox; a personal Gmail connector cannot assume company-alias
  authority. On 2026-09-05 the maintainer declined current resends and confirmed
  that future updates must use the domain sender and delivery-test procedure
  in DEPLOYMENT.md. No retry occurred; the four bounces/Android spam report
  remain unresolved. No recipient addresses are recorded here.
- **FIXED AND PRODUCTION RECOVERY VERIFIED — shared cleanup rejected
  valid expired direct-message video reservations.** One pending canonical
  `.mov` reservation exposed an allowlist limited to `jpg|png|webp|m4a` in the
  shared cleanup validator. The five-minute scheduled errors predate Build 20
  and persisted on its new worker revision; the exact read-only outbox query
  succeeds, so this case is not an index failure. Backend-only commit
  `06e94c6` adds the already-supported `mp4|mov|webm` formats while preserving
  canonical root, owner, conversation, message and path checks. Focused
  regression 2/2, independent Moment 76/76 and the fresh full Functions suite
  1279/1279 across 118 suites pass, with required independent reviews APPROVE.
  Scoped deployment of `processPendingContentCleanupSchedule` and
  `onContentCleanupOutboxCreated` succeeded by 09:39:39 UTC on 2026-09-05.
  Independent review APPROVED recovery at 09:59:13 UTC: latest ready revisions
  at 100% traffic, the old reservation completed automatically at 09:41:05.343
  on attempt one, pending aggregate zero, four scheduler HTTP 200 results and
  zero ERROR entries in either worker over more than 19 minutes. The cleanup
  hold is lifted. Follow-up full CI `33958465563`, browser CI `33958465500`
  and CodeQL `33958465503` passed; Hosting correctly skipped. No manual
  outbox/media mutation or mobile rebuild was needed.
- **FIXED IN RELEASED RUNTIME — Build 20 Voice Moment reads no longer treat
  foreign published Firestore documents as an audience-safe feed.** Feed and
  detail use bounded, server-owned v2 projections, recheck viewer/author visibility,
  restrictions, blocks, expiry and exact friendship authority, and omit
  durable media/avatar bearer data. Like/report mutations are server-owned;
  lifecycle refresh discards stale auth generations and inaccessible content
  fails closed. The legacy v1 direct-read path remains a documented Build 19
  compatibility residual until adoption telemetry and a separately reviewed
  minimum-version/rules cutover permit its removal; this source fix does not
  claim that residual is closed in production.
- **FIXED IN RELEASED RUNTIME — Reels expiry cleanup and Voice Moment report
  receipts lacked the complete Build 20 production retention boundary.** Reels
  now use bounded availability plus retry/lease cleanup, while canonical moderation
  validates server-known content rather than a client-supplied object path.
  The required source configuration includes four new composite indexes and
  both managed TTL overrides: `reelCleanupOutbox.deleteAfter` and
  `voiceMomentReportReceipts.expiresAt`.
- **PRODUCTION PREREQUISITES VERIFIED, AUTHENTICATED SMOKE STILL OPEN.** All
  four required composite indexes are `READY`, both TTL overrides are
  `ACTIVE`, additive Functions and Firestore Rules are deployed/read back,
  the explicit one-pair friendship repair completed with a no-op repeat, and
  unchanged Storage Rules were correctly skipped. Hosting `33954305037`
  succeeded and both domains match its artifact bytes/security headers.
  Anonymous callable `401` and server-owned collection `403` probes are not
  authenticated allow-path or cross-account acceptance; dedicated production
  QA credentials are still unavailable. ACTIVE worker status likewise did
  not prove the shared cleanup path healthy, as the finding above demonstrates.
- **OUTSTANDING PHYSICAL/DISTRIBUTION GATE — automated success is not device
  acceptance.** The bounded YO Moments 50/50 and dock Dark/Pearl 8/8
  screenshot harnesses pass; inspected Frame Echo Clean PNGs have no internal
  lines/skew or observed overlap. Remaining app-wide keyboard/RTL and physical
  visual QA and two-account iOS/Android and mixed-version Voice/DM/Reels/call
  testing remain unverified. Signed artifact inspection, store-number
  uniqueness and both uploads/processing are complete. Play internal
  availability and the user's separate confirmation do not establish
  non-owner Android installation. External TestFlight `Testing` and five
  non-owner `Installed 20` observations establish bounded distribution, not
  functional two-device acceptance. The seven unavailable vendored iOS dSYMs
  limit third-party crash symbolication but did
  not block upload/processing. Automatic TestFlight notification was enabled/
  triggered with submission, but recipient inbox delivery is unverified.
  The twenty separate email submissions and four confirmed hard bounces are
  tracked above; manual resends are paused. Marketing commit `975e5c6` is
  published: Vercel deployment succeeded and live home/updates/download/features
  HTTP 200 read-backs passed, including Build 20 content/anchors and preserved
  Build 19 updates history.

The authoritative operational checklist is the
[Build 20 release-candidate session](Sessions/2026-09-05-build-20-release-candidate.md).

## Build 19 tester-acceptance gaps (2026-09-03)

Build `1.0.0 (19)` is now available to the bounded TestFlight and Google Play
Internal Testing cohorts. These entries distinguish completed automated and
production rollout evidence from the physical acceptance still needed before
any public store release:

- **DM media and Shared Media**: photo, video and voice, camera/library
  acquisition, media playback, Shared Media tabs and the durable outbox are
  implemented in source. Server hardening now sniffs JPEG/PNG/WebP,
  ISO-BMFF/WebM and MP3/WAV bytes, requires an audio-only voice container or a
  real video track, and rechecks object metadata plus the reservation in the
  canonical transaction. Its shared contract passes 9/9 and fresh-emulator
  direct integrity passes 38/38. Complete Flutter 2123/2123 and browser
  media/crop/Reels 39/39 are green; the production migration, IAM and Rules
  read-back completed. Physical upload/playback/restart evidence is pending.
- **Avatars and profile routes**: canonical refresh and a single-flight route
  guard address stale initials and stacked profiles after rapid taps. The
  final two-account cache-invalidation and native route-transition/visual
  matrix is pending.
- **Direct audio/video**: the server-authoritative call lifecycle retains
  missing-`mediaType` = audio compatibility and offers audio fallback when a
  recipient cannot accept video. Two physical devices, mixed installed
  versions, camera/microphone/Bluetooth, backgrounding and APNs/FCM remain
  tester gates; no FaceTime-equivalent application E2EE claim is made.
- **Voice Moments**: generation grants and publish/play retry recovery are in
  source. The production legacy migration itself is complete: 5 objects, 0
  remaining download tokens, 0 legacy `audioUrl` fields and no deleted media
  bytes. Final iOS/Android record → publish → play → expiry testing is pending.
- **Reels MVP**: callable-owned publish/list/read/delete/report and a
  non-destructive editor recipe are integrated. Only user-owned or licensed
  backing audio is accepted; Spotify/Apple Music ingestion is absent by
  design. Final visual/editor and physical codec/upload evidence is pending.
- **Presentation/localization**: compact achievement/More treatment and the
  production Polish + 41-additional-locale guarded catalog have targeted
  coverage. Full visual, RTL, 200% text and native permission-string review is
  pending.
- **Moderation**: the content action, report resolution and append-only audit
  commit atomically; its focused 31/31 subset sits inside the 64/64
  Reels/moderation security gate. The intended Reels Functions are deployed
  and ACTIVE; a tester-device report/moderation journey remains acceptance
  evidence.
- **Website Updates**: tester-availability copy deployed from separate website
  commit `9cc6d72550ce6e0b603136f7bb71e7e11891ab47` through successful Vercel
  deployment `6248731984`. The live Updates entry reports the bounded Android
  15 / TestFlight external 7 + internal 1 cohorts and clearly says this is not
  a public store release; the production route/header smoke passed 43/43.

The consolidated checklist is in
[DEPLOYMENT.md](DEPLOYMENT.md#build-19-coordinated-tester-release--2026-09-03),
and measured evidence is in
[TESTING.md](TESTING.md#build-19-tester-release-evidence-2026-09-03).

## Security

- **OPEN, accepted knowingly 2026-09-07 — `createReelCommentReport` checks no
  visibility, diverging from ADR-086 rule 2.** Every other moderation
  endpoint checks access before existence, so a caller who cannot reach the
  container learns nothing from the refusal. This one does not: it will file
  a report against a Reel comment the caller may no longer be able to see.
  The divergence is deliberate and reasoned at the call site — with the check
  and no receipt, a harasser could immunise their own comment by blocking the
  victim afterwards, and the victim could then never file. The cost is that
  the callable is a weak existence oracle for comment ids on the shared
  `reel.report` budget (charged before the target is read, so a refusal costs
  the same as a report, which bounds but does not remove it). **The remedy is
  a report receipt issued by `getReelViewV2`**, so the report can be
  authorized by the receipt instead of by a live read — Roadmap item 0r.
  Live in production since the 2026-09-07 deploy; today reachable only by a
  direct callable invocation, since no client control exists (see the OPEN
  entry at the top of this file).
  [ADR-162](Decisions.md#adr-162-reel-comment-moderation-is-three-server-paths-not-one),
  [ADR-086](Decisions.md#adr-086-a-safety-action-is-never-gated-on-email-verification-and-every-moderation-endpoint-checks-access-before-existence).

- **OPEN, found 2026-09-07 — reported Reel comment text is retained in
  `reports` indefinitely.** `createReelCommentReport` writes
  `targetTextSnapshot`, a verbatim copy of the reported comment, because
  `reels/{id}/comments/{id}` is `read, write: if false` for every client
  including staff — the snapshot is both the moderator's only view of the
  words and the only evidence that survives the removal. It is the **first
  third-party content stored in `reports`**, and it has no TTL field and no
  account-deletion scrub: deleting the author's account does not remove their
  words from the reports collection, and nothing expires them. Confirmed in
  source — `targetTextSnapshot` is written at `functions/reels/service.js`
  and validated in `functions/moderation/reports.js`, and neither path nor
  the account-deletion workers touch a retention deadline. Needs a privacy
  pass deciding a retention period and a deletion path — Roadmap item 0s.
  Live in production since the 2026-09-07 deploy.

- **OPEN, found 2026-09-07 — author removals of other people's Reel comments
  are recorded where no moderator can see them.** `removeReelComment` writes
  its trace only to `integrityOperationLedgers`, which no moderator tool
  reads, and removal is a hard delete on every path — so an author who
  removes a comment before anyone reports it leaves no copy anywhere. This
  was a deliberate trade in ADR-162 (a distinguishable ledger kind exists
  precisely so Trust and Safety *can* count these separately), but the
  counting surface does not exist yet.

- **FIXED IN SOURCE 2026-08-29 — logout changed AuthGate but left private
  routes, banners and live-room audio attached to the previous session.**
  Profile and Settings are pushed above the first Navigator route, so replacing
  MainShell with LoginScreen underneath them left the pushed screen visible;
  its Firestore listener then rendered “You don't have permission to do that.”
  The app now treats every signed-in principal as an auth epoch: logout,
  direct account replacement and auth-stream failure replace the complete root
  route stack with a zero-duration auth boundary, ignoring route pop vetoes.
  Logout paints the real Login screen on that first replacement frame and
  clears app-level notification SnackBars so account A cannot leave UI on
  account B. The same central sign-out path now disconnects local LiveKit audio
  immediately, best-effort leaves an active room roster and ends an active
  direct-call record while Auth is still valid; bounded network failure can
  never trap the account in-session. Remote Auth loss and direct A→B also force
  the local audio disconnect even when roster/call authority is already gone.
  Registration's intentional signed-out → signed-in Verify Email flow is
  preserved. Route-stack, PopScope, direct A→B, real-Login, presence/FCM and
  active-room/direct-call cleanup regressions cover the boundary.

- **FIXED AND PARTIALLY DEPLOYED 2026-08-27 — the product sound was a retro synth-jingle
  system and one foreground notification could play two different cues.** All
  eight effects used notes, pentatonic rise/fall pairs, glass-bell partials,
  detune or a two-note chime. Worse, native push still packaged the much louder
  original mono WAV while the focused app used a later stereo file; native FCM
  and the Firestore banner could sound together. Velvet Prism replaces the
  entire pack with short, non-musical material cues, removes the conflicting
  Dart generator, derives all native copies from one deterministic 48 kHz
  master, serializes channel playback, dedupes foreground ownership and makes
  room creation one confirmation rather than create+join. Android uses a new
  immutable `yovoice_activity_v3` channel consistently in source. Hosting now
  serves all eight v3 cues; native stores remain on build `+3`, and production
  `onNotificationCreated` deliberately remains on channel v2. Mobile clients
  must create v3 before the Functions payload cutover; physical-device
  listening is still required. See ADR-116.

- **FIXED AND DEPLOYED 2026-08-27 — Voice Moment root lifecycle and the active
  cap could be bypassed by a modified or legacy client.** Before this rollout,
  production rules permitted a direct root create with no `expiresAt`, broad
  author updates that could forge publish/media/status state, and direct root
  deletion that skipped the cleanup outbox. The old cap scanned only the
  newest 100 authored documents and had no shared write on which two
  finalizations of different drafts could conflict. ADR-115 makes
  root and engagement mutation server authority, queries the complete
  published set and serializes
  finalize/delete/expiry through a server-only per-author revision document.
  Draft and retired roots plus their audio become author-private, and all root
  and reply audio becomes client-immutable so deletion cannot race a publish
  transaction. Bounded server workers remove abandoned uploads. Every
  unfinished finalize retry is rate-charged before Storage reads, exact client
  timers stop open playback at the deadline, announce visible transitions
  once, restore focus and preserve the first surviving Story successor;
  engagement callables refuse the same deadline before the sweeper runs.
  Emulator coverage includes direct
  lifecycle/counter/comment attacks, more than 100 newer drafts, concurrent
  publication into the tenth slot, retry-budget attacks and deadline edges.
  The ordered index, Functions, Firestore Rules, Storage Rules and Hosting
  rollout completed with byte read-back and controlled production smokes.

- **FIXED IN SOURCE 2026-08-28 — the conversation root and message documents
  still admitted client-side authority despite a server-owned contract.** The
  old root rule pinned only `participantIds`, allowing a participant to forge
  `lastMessage`, identity snapshots and either party's unread/read state; old
  message rules also kept edit/delete/reaction/read fallback writes alive.
  Current Rules make both surfaces server-write-only while preserving
  participant reads. Text, media, typing, read, mute, archive, edit, delete and
  reactions use their owning callables. The 519-case emulator gate includes
  direct attacks on both participants' state and every retired message write.
  Production Rules remain a separate rollout gate until build 11 is available
  to the permanent tester cohorts.

- **FIXED IN SOURCE 2026-08-27 — the message outbox existed but the chat waited
  for the network and rendered none of its states.** A text send now clears the
  composer after durable local enqueue, renders an optimistic outgoing bubble,
  and drains oldest-first under the original idempotent `requestId`. Pending,
  offline/retrying, server-accepted and terminal failure states remain visible;
  a terminal bubble preserves the words and exposes 44 px Retry/Remove actions
  without showing raw backend errors. The callable response and Firestore
  snapshot are reconciled by the backend's deterministic SHA-256 message id, so
  their arrival order cannot flash or duplicate a bubble. Typing presence is a
  transition/heartbeat instead of one callable transaction per keystroke, and
  expires locally after eight seconds even without another snapshot. One live
  `MessageService` owns one serialized, UID-scoped queue
  (`messages.outbox.v2.<uid>`); the ownerless v1 value is retired rather than
  attributed to whichever account opens the upgrade. MainShell resumes it on a
  cold start, backoff preserves FIFO inside a conversation without blocking a
  different chat, and closing Chat cancels its shared Firestore listener. An
  enqueue refusal restores every draft word, while a local bubble can no longer
  hide a failed server-history stream. FIFO, restart/account-switch,
  cold-callable, 320 px/200% and recovery paths are regression-tested.
  **DEPLOYED TO WEB 2026-08-27; NATIVE STORE BUILD PENDING.** See ADR-105.

- **FIXED IN SOURCE 2026-08-27 — the avatar cropper could shrink a picked
  photo into the upper-left corner on the first pinch.** The initial cover
  transform scaled X/Y below 1 for a large source image but left Z at 1.
  `InteractiveViewer.getMaxScaleOnAxis()` therefore reported 1 instead of the
  real cover scale; the first zoom gesture applied that cover factor again,
  producing the quarter-sized image and empty circular frame visible on iOS.
  The editor now uses one uniform XYZ scale, so reset, pinch and drag preserve
  full cover and the exported JPEG matches the visible crop. Named 44 px
  Zoom −/+ and directional controls provide the same operation without a
  multi-pointer gesture and work from the keyboard; the crop preview exposes
  its current zoom to assistive technology. Gesture- and control-level
  regressions cover portrait and landscape inputs on phone layouts, including
  200% text. **DEPLOYED TO WEB 2026-08-27; NATIVE STORE BUILD PENDING.** This
  is a corrective amendment to ADR-025.

- **FIXED IN SOURCE 2026-08-29 — room covers bypassed the crop editor and
  could not be positioned by their owner.** Create Room and Room Settings sent
  the picked source straight to a fixed `BoxFit.cover` presentation, so a host
  could replace an image but could not choose which faces, logo or text would
  survive the wide room card. Both flows now use one 21:9 editor, upload only
  its final 1600×686 JPEG and retain the previous crop when Replace is
  cancelled. The fix also closes the adjacent lifecycle defects: system Back
  cannot dispose the decoded image during encoding, native codecs are
  released, double taps cannot stack editors, leaving Settings cannot skip
  superseded-object cleanup, and status/delete cannot race an upload. A lost
  Firestore acknowledgement deletes new media only after an authoritative
  server read proves the pointer did not commit; an unavailable read preserves
  it for recovery. Closed/archived rooms explain the active-room Storage rule
  and offer a nearby confirmed Reopen action; a moderation-suspended room has
  no host-controlled status escape hatch. Firestore Rules now also reject
  non-string, oversized, external and cross-room cover pointers, while keeping
  a Club Lounge bound to the exact managed avatar on its live Club root. The
  client parser ignores hostile legacy/Admin data and the decoder bounds both
  encoded dimensions and decoded memory. See ADR-122.

- **FIXED AND DEPLOYED TO WEB 2026-08-29 — the new room-cover crop flow rejected every
  valid image on Web before the editor could open.** Its safety preflight read
  `ImageDescriptor.width/height` from an encoded descriptor, getters that the
  Flutter Web engine deliberately does not support. The resulting
  `UnsupportedError` was flattened into the red “We couldn't process this
  image” state visible in both Community and Podcast creation; Room Settings
  and profile media shared the same latent decoder defect. The decoder now
  reads bounded JPEG/PNG/WebP header metadata and JPEG EXIF orientation first,
  then sends one oriented-axis target to the cross-platform codec. An iPhone
  portrait therefore cannot constrain the wrong axis or decode beyond the
  3200 px memory ceiling. The route launcher retains ownership of the native
  frame until the reverse transition or forced auth reset has fully removed
  the crop overlay. CI now runs decode, EXIF rotation, forced-reset and
  picker-bytes → crop → 1600×686 export regressions in Chrome. Native tester
  build remains part of the coordinated queue.

- **FIXED IN SOURCE 2026-08-27 — Message in Profile Preview appeared to do
  nothing when the preview was opened above another sheet.** The callback
  popped Profile Preview and immediately looked up a navigator through that
  closing route; an `openDirectConversation` refusal was even less visible,
  because its snackbar painted in the root Scaffold underneath both modal
  barriers. Profile Preview now returns a typed destination to the navigator
  captured by its launcher, waits for dismissal, and only then pushes Chat or
  the full profile. The same resolved Auth identity and MessageService follow
  the route so optimistic reconciliation cannot switch users; an internally
  constructed test/preview service is disposed after Chat returns. A failed
  open stays in the preview as a friendly inline
  live-region message; while the request is pending, the button and a concise
  live status both say that the chat is opening. The real two-sheet route,
  delayed/double tap, Back behavior and 320 px/200% failure state are
  regression-tested. **DEPLOYED TO WEB 2026-08-27; NATIVE STORE BUILD
  PENDING.**

- **OPEN, noted not fixed — `enforceAppCheck: false` on the Stage B callables,
  including `sendDirectMessage`.** App Check is supported but not enforced
  (`stage_b_functions.js:24`, default `enforceUserAppCheck = false`; asserted
  by `stage_b_bindings.test.js:138`). Pre-existing posture, unchanged by any
  pending work, and a deliberate separate decision rather than an oversight to
  fix in passing.

- **FIXED AND DEPLOYED 2026-08-25 — the desktop rail could still be
  deliberately scrolled, making primary navigation look displaced.** ADR-107
  correctly separated the rail from the page and fixed controller ownership,
  but kept the nav `SingleChildScrollView` as a short-height safety valve:
  measured `maxScrollExtent` was 40 px at 720 and 82 px at 620. That prevented
  overflow while preserving the exact layout, but a wheel gesture could still
  leave the menu visibly shifted — the visual behavior reported again on
  2026-08-24. The new contract removes the scrollable entirely: Home is a
  pinned 44×44 header action beside Notifications, the creation actions share
  one row below 700 px, and the content-only verification banner/RoomMiniBar
  no longer shorten the rail. At 200% text the informational timezone card
  yields; below 620 logical px the shell uses mobile navigation. The earlier
  diagnosis and measurements remain valid history in
  [ADR-107](Decisions.md#adr-107-the-desktop-rail-owns-its-scroll-position-and-sizes-its-decoration-from-the-rail-not-the-window);
  the superseding layout decision is
  [ADR-109](Decisions.md#adr-109-the-desktop-rail-has-no-scroll-position--home-is-a-pinned-header-destination).

- **FIXED IN SOURCE 2026-08-22 — the desktop rail hard-coded a 24-hour
  clock.** The same defect `message_bubble.dart`, `edit_profile_screen.dart`
  and `club_chat_screen.dart` each had to fix: a 12-hour-clock locale was
  shown "13:04". The timezone card now reads
  `MediaQuery.alwaysUse24HourFormatOf(context)`. Confirmed live — an `en-GB`
  browser rendered "1:37 PM".

- **FIXED BEFORE IT SHIPPED 2026-08-22 — the new web timezone reader returned
  null in every browser.** `external factory` on a bare extension type names
  no global constructor, so `Intl.DateTimeFormat()` resolved to nothing and
  the card silently fell back to the platform abbreviation. Found by looking
  at the running app, in a browser whose own console answered
  `Europe/Amsterdam`. `@JS('Intl.DateTimeFormat')` is the binding that makes
  it work and is load-bearing.

- **FIXED IN SOURCE 2026-08-19, NOT DEPLOYED — room chat was the largest
  unguarded client write surface in the product.** The rule checked
  `senderId` and membership and nothing else about the document, so an
  ordinary member could write another member's `senderName` and photo, a
  60,000-character body, arbitrary extra fields, and a `sentAt` in 2099 that
  pinned the message to the top of every member's list **permanently**.
  Every other client-authored identity snapshot in `firestore.rules` was
  already pinned; room chat was the exception, and the client compensating is
  why it never surfaced. `01c0ab2` adds a six-key allowlist, pins
  `senderName` to the canonical `users` document and `createdAt` to
  `request.time`, caps content at 500 and bounds reactions updates at 32
  keys. **Still open, stated rather than hidden**: `senderPhotoUrl` is
  deliberately NOT pinned, because the client falls back to the Firebase Auth
  mirror when the profile field is empty and a pin would refuse a legitimate
  send — so **an avatar can still point at another member's image**. With the
  name pinned that is much weaker impersonation, but it is a real remaining
  gap, and closing it needs the client to drop the fallback first. Also
  bounded but not closed: the uid list under each reaction key is still
  caller-authored and unbounded, because rules cannot iterate map values —
  the real fix is a `reactions/{uid}` subcollection, which is a schema
  change. See
  [ADR-084](Decisions.md#adr-084-client-authored-writes-carry-an-exact-key-allowlist-and-identity-and-time-are-pinned-to-canonical-server-values-or-the-remaining-gap-is-stated).

- **FIXED IN SOURCE 2026-08-19, NOT DEPLOYED — a plain club member could
  write an unrepairable forged tombstone.** Found by the adversarial review
  of the club-moderation change, and it is the mirror image of that fix: the
  club message create rule had no field allowlist, so a member could write a
  message that was **already** a removal record — reading as "removed by the
  club owner", carrying `deletedByRole: superAdmin` and a `senderName` of
  "YO Voice Support", with `sentAt` in 2099 so it pinned to the top of every
  member's list forever. And it was **unrepairable by any client path**: the
  new update rule refuses already-deleted documents, `delete` is `if false`,
  and `adminDeleteMessage` short-circuits on `isDeleted`, so only a raw Admin
  SDK script could have cleared it. `clubMessageCreateShapeAllowed` closes
  it, with a test that seeds the forged tombstone and proves owner, moderator
  and author are all refused. This is the standing reason the rules and
  client halves of club moderation could not ship apart.

- **FIXED IN SOURCE 2026-08-20, NOT DEPLOYED — `createContentReport` was an
  existence oracle.** The callable answered `not-found` *before* checking
  access, so a caller could learn whether a private room, club, channel or
  message id was real by watching which refusal came back. `2c086c7` runs the
  access check first for every target type; a caller who cannot read the
  container now gets `permission-denied` and nothing else. One live behaviour
  changes with it: a non-participant reporting a DM could previously
  distinguish a missing message from a real one. See
  [ADR-086](Decisions.md#adr-086-a-safety-action-is-never-gated-on-email-verification-and-every-moderation-endpoint-checks-access-before-existence).

- **FIXED IN SOURCE 2026-08-20, NOT DEPLOYED — a first-day victim could not
  report harassment.** `createContentReport` required a verified email:
  `requireActor` defaults to `{verified: true}` and the inner call at
  `functions/moments/integrity.js` overrode an outer binding that already
  passed `{verified: false}`. `firestore.rules` states the opposite policy in
  writing on the client-direct path — reporting is a SAFETY action and sits
  with blocking, which that policy explicitly leaves available to a
  freshly-registered account. A neighbour audit of **every** `requireActor`
  call site found this was the ONLY tightened safety path: `setUserBlock`,
  `unfollow`, conversation mute/archive, mark-read and both delete paths were
  already correct, and every remaining `verified: true` site is genuinely
  outbound.

- **FIXED IN SOURCE 2026-08-19, NOT DEPLOYED — a signed-out account showed as
  online to its friends indefinitely, and two of five sign-out paths left the
  previous account receiving push.** The offline presence write lived in the
  `authStateChanges()` **null branch** — after `FirebaseAuth.signOut()` had
  already cleared the session — so the rule's `isSignedIn()` gate denied it
  and `presence_service` swallowed the denial to a `debugPrint`. `isOnline`
  stayed true and `onUserPrivacySourceChanged` mirrored it into
  `socialPresence`, which is exactly what the DM header dot and the
  conversation list read. The comment above that code claimed it fixed this;
  it did not. A second such write, in the account-switch branch, wrote a
  previous uid under a new identity and failed `isOwner()` just as
  structurally — both removed rather than relocated, because keeping a write
  the ruleset always rejects is the mistake. The FCM token had the same shape
  across five sign-out entry points with five different amounts of cleanup;
  cleanup converged into `AuthService.signOut()` immediately before
  `_firebaseAuth.signOut()`. Both cleanups start while Auth is live, are
  independently time-bounded, and push revokes its identity epoch plus starts
  durable-marker/platform-token rotation before any offline Future can stall
  sign-out. **UNVERIFIED**: presence actually flipping in production needs two
  real accounts. **Half of this is not fixable from the
  client at all** — see the process-death entry under Data integrity. See
  [ADR-090](Decisions.md#adr-090-session-cleanup-converges-on-authservicesignout-because-a-write-the-rules-authorize-by-session-cannot-live-after-the-session-ends).
- **FIXED IN SOURCE 2026-08-19 — a banned or communication-muted account
  could still send direct messages through the client fallback.**
  `conversations/{id}/messages/{id}` create checked `isVerified()` — a token
  claim that says an email was confirmed once, and nothing about account
  standing — but never the sender's `users/{uid}.banned|disabled` or
  `restrictions/{uid}` communicationMute. The server's `activeProfile()` and
  `assertNotRestricted()` run *inside* `sendDirectMessage`, while
  `_sendTextMessageDirectly` wrote the message document straight from the
  client whenever the callable was unreachable, so on that path the rule was
  the only backstop and it did not enforce the sanction. The same bypass
  skipped the per-sender rate limit and the idempotency ledger.

  Adding the missing check to the rule was implemented and then abandoned on
  measurement: it exceeds Firestore's per-request document access-call
  budget (the friends-privacy path had exactly one call of headroom; a
  complete sender-status check needs four), and an exhausted rule errors
  rather than skipping — which denies, breaking legitimate sends. The rule
  is now `allow create: if false`; `sendDirectMessage` is the sole writer.
  A bounded local outbox with Pending / Retrying / Failed states retries
  unsent messages under their original `requestId` when connectivity
  returns, so removing the fallback does not lose a message. See ADR-082.

  Verified: rules **446/446**, Flutter **881/881**, `flutter analyze` clean.
  Not yet deployed — rules deploys are manual, and the app should ship
  before the rule so installs older than this release are not left writing
  into a denial with no queue to catch them.

- **FIXED IN SOURCE 2026-08-18 — live rooms wasted desktop space and left a
  detached chat bubble behind after chat closed.** Community, Podcast, Club
  and Family rooms now use one bounded responsive workspace: desktop keeps a
  readable stage on the left and a permanent chat rail on the right, while
  phones and compact tablets switch between full-width Stage and Chat views.
  The floating latest-message overlay and the synthetic “room is quiet”
  prompt were removed. Responsive tests cover the four room identities,
  desktop split geometry, 320/390/768 compact widths and 200% text. Pending
  the Flutter Hosting deploy for live verification.

- **FIXED LIVE 2026-08-18 — every Firestore-backed Storage upload was denied
  despite green emulator tests.** Production was missing the
  `roles/firebaserules.firestoreServiceAgent` binding on
  `service-80235878542@gcp-sa-firebasestorage.iam.gserviceaccount.com`.
  Consequently `firestore.get()`/`firestore.exists()` inside `storage.rules`
  failed closed before a Voice Moment object could be created; the UI retained
  the recording and reported only that publishing failed. The same missing
  prerequisite affected profile/room/Club/message uploads whose rules read
  Firestore authority. The minimal Google-managed service-agent binding was
  restored in production, then an authenticated resumable upload using the
  exact Voice Moment path, MIME, metadata, size and unpublished-draft contract
  returned HTTP 200 and created a generation; the temporary Auth user,
  Firestore documents and object were deleted. Deployment documentation now
  requires an IAM-policy check plus a real cross-service upload smoke test.
  Emulator coverage remains necessary for rule semantics but cannot model
  production IAM. See ADR-077.

- **FIXED AND DEPLOYED 2026-08-18 (`e524497`) — mobile Home hid both
  legitimate room-deletion paths.** The phone Home never loaded the shared
  staff-capability response, so an administrator or super moderator could not
  see the audited room menu that desktop already rendered. Owners could reach
  deletion only when a room happened to appear under `Your active rooms`, with
  no explicit management affordance on the room card. Home room cards now
  expose a separate owner-only overflow menu backed by `deleteRoomSelf`, while
  the shield menu is backed by `adminDeleteRoom`. Server authorization is
  intentionally asymmetric: exact `hostId` ownership is sufficient only for
  the caller's own room; deleting any room requires `superAdmin` or
  `superModerator`; ordinary `moderator` is denied. Phone navigation now loads
  the same capability object as desktop. See ADR-075.

**Rules status, 2026-08-16: the pending fixes are now DEPLOYED.** Every
"FIXED IN SOURCE, PENDING RULES DEPLOY" marker in this file was cleared on
this date. `firestore.rules` was deployed twice — 20:40 by the operator and
21:06 covering `952d8e4` — and `storage.rules` was deployed the same day,
per Console → Firestore → Rules version history. First-user-document
creation and Club invitation acceptance are no longer open production
risks.

**Rules status, 2026-08-17: the banned-host gap is CLOSED and deployed.**
The room-update host branch, `isHostAdmittedRoomParticipant()`,
`roomMembers` create and message reaction updates all require
`isActiveAccount()` as of `c75720a`. Deployed, and verified by reading the
live ruleset source back through the Firebase Rules API and diffing it
against `firestore.rules` at HEAD — **byte-identical**. That verification
is now the project's standard for a rules deploy; the commands are in
[DEPLOYMENT.md](DEPLOYMENT.md#reading-the-deployed-ruleset-the-verification-standard).

**Two writes behind `canAccessRoom()` are still ungated**, and the claim
that all of them are is false — see
[SECURITY.md](SECURITY.md#still-open-pre-existing-live-in-production) and
[Roadmap 0k](Roadmap.md#0k-gate-the-last-two-writes-behind-canaccessroom).
Neither escalates privilege.

For the full security model (not just this status snapshot), see
[SECURITY.md](SECURITY.md). An earlier full audit
([Archive/SECURITY_AUDIT.md](Archive/SECURITY_AUDIT.md)) found 3 critical, 3
high, and 6 medium-priority issues plus one client/server contract bug. Within
that audit's original 13 items, all are fixed except one:

- **`enforceAppCheck: false` on every Cloud Function** (audit item #12) —
  still open, and as of 2026-09-18 it has a **measured hard blocker** in
  front of it, not just a waiting period: **no platform is known to be
  delivering a valid App Check token.** The Play-distributed Android
  client sends one the backend cannot decode, on every single call; iOS
  and web are unproven either way, because an *absent* token is logged as
  nothing at all; and `playintegrity.googleapis.com` is not enabled on
  `yovoice-ec54a`. Flipping enforcement today would reject real users, so
  the earlier framing — "needs a token-delivery monitoring period first
  (Firebase Console → App Check has the metrics)" — was too soft, and the
  monitoring source it named is the only one that can answer the question
  (Cloud Functions logs cannot). Measurement, and what it does and does
  not prove: **App Check token delivery is broken on Android and unproven
  everywhere else**, the dated entry at the end of this file. See also
  [ADR-004](Decisions.md#adr-004-firebase-app-check-integrated-client-side-enforcement-deliberately-off)
  for why the integration shipped with enforcement off.
  Not urgent on its own — it removes a layer that raises the cost of
  abusing the backend, it isn't itself an open exploit — but shouldn't be
  forgotten either. Tracked as a Roadmap item too:
  [Roadmap.md](Roadmap.md#2-firebase-app-check-enforcement).

- **FIXED AND DEPLOYED 2026-08-16 — first `users/{uid}` create
  bypassed every protected-field update check.** The update rule prevented
  self-assigned Creator/Premium/staff state, but a document that did not exist
  yet could be created with arbitrary fields. The create rule now accepts only
  the non-privileged bootstrap/profile/presence field set, requires any `uid`
  to match the path and permits only `personal` as an initial `accountType`;
  legitimate partial presence-first documents still work. Forged Creator,
  `premiumIdentity` and role creates are rejected in the emulator suite.
  ([ADR-053](Decisions.md#adr-053-paid-capabilities-come-only-from-the-trusted-entitlement-and-every-entry-boundary-fails-closed)).

- **FIXED AND DEPLOYED 2026-08-16 — a Club invitee could self-promote
  while accepting an invitation.** The membership-create branch previously
  verified the pending invite but did not pin the new membership role or shape,
  allowing a modified client to join as owner/co-owner/admin and then inherit
  Club management rights. Rules now allow exactly the seven production fields,
  require the invite's sender in `invitedBy`, and force invite acceptance to
  `role: member`; owner membership creation remains a separate `getAfter()`
  path. The Club-root counter update must also atomically create that membership
  and delete the invite, may change only both counters plus `updatedAt`, and
  pins their deltas and server time. Emulator attack cases cover every
  privileged role, extra permission fields, repeated counter bumps and Club
  metadata mutation.

### Found and fixed 2026-08-17 — live in production, and deployed

- **FIXED (`c75720a`) — a banned or disabled host could still edit room
  metadata and start voice.** The room-root update rule selected its host
  branch on `hostId` alone with no account-status check, while
  `isRoomHost()` did check — so the selector was doing authorization work
  the branch's own helper was careful about. Four conditions now require
  `isActiveAccount()`: the host room-update branch,
  `isHostAdmittedRoomParticipant()`, `roomMembers` create, and message
  reaction updates. **`roomMembers` create mattered independently**: it
  gated on `isRestrictedAccount()`, which reads `banned` only and returns
  false when the account document is *absent*, so disabled accounts passed
  a check that looked like it covered them. Rules suite 310 passed / 8
  failed → **318 passed / 0 failed**. Generalized as
  [SECURITY.md principle 9](SECURITY.md#firestore-security-rules--design-principles).

- **OPEN, pre-existing, live — every non-host room message throws after
  the message lands, and Home never reorders from non-host talk.**
  `sendRoomMessage()` bumps `updatedAt` on the room root after each
  message, and the non-host branch of the room-update rule has no
  transition that accepts a bare `updatedAt`. The message itself is
  written, so nothing is lost; what follows is an **unhandled
  permission-denied** and a room whose ordering in the Home feeds never
  advances no matter how active the conversation is. Found during the
  2026-08-17 rules work, not caused by it. Tracked as
  [Roadmap 0l](Roadmap.md#0l-non-host-room-messages-always-throw-after-the-message-lands).

### Found and fixed 2026-08-16 — all were live in production

Each was proven by a case that failed first, and all are now deployed.

- **FIXED (`56e7ea7`) — every club promotion and demotion was denied.**
  `clubs/{clubId}/members` manager updates allowlisted only
  `['role','updatedAt']`, while both the deployed client and this tree
  write `role`, `roleUpdatedAt` and `roleUpdatedBy`. Club role management
  was entirely non-functional. `clubRoleChangeFieldsAllowed()` widens the
  field set without widening privilege: `roleUpdatedBy` is pinned to the
  acting uid and both timestamps to `request.time`. Also closes an
  unknown-role string falling through `clubRolePower`'s else branch.
- **FIXED (`56e7ea7`) — a private Community room became unreadable to its
  own members, and took the whole Communities list with it.**
  `canAccessRoom()` had no `isRoomMember` branch. The blast radius came
  from the client: `watchMyCommunities()` hydrates every id in a single
  `Future.wait`, so **one** unreadable room emptied the entire list. Worth
  remembering as a pattern — an unbounded `Future.wait` turns a
  single-document permission error into a whole-screen outage.
- **FIXED (`56e7ea7`) — club avatar and banner uploads were denied.**
  `storage.rules` `validClubImageUpload()` accepted only the bare
  `avatar`/`banner` object name; the deployed client uploads
  `{kind}_{millis}.{ext}`. Both shapes are now accepted, with the
  timestamped form validated like the profile path including
  MIME/extension agreement.
- **FIXED (`2fc05e5`) — banned and disabled accounts gained private-room
  access.** `isRoomMember()` required only `isSignedIn()`, so widening
  `canAccessRoom()` handed private rooms, their rosters and their
  participant lists to suspended accounts. Now requires
  `isActiveAccount()`, which also withdraws room chat and voice-start from
  them.
- **FIXED (`2fc05e5`) — club role attribution was forgeable.** Omit
  `roleUpdatedBy`, or resend the value already stored, and the guard never
  fired — because `diff().affectedKeys()` reports only fields whose
  *value* changed and the guards were gated on `hasAny()`. Attribution is
  now required unconditionally whenever `role` changes, checked against
  the post-write document. This is now
  [SECURITY.md principle 6](SECURITY.md#firestore-security-rules--design-principles).
- **FIXED (`2fc05e5`) — a host could permanently and remotely empty a
  victim's Communities tab.** `roomMembers` update had no field allowlist
  on either branch, so a host could repoint their own membership row at a
  victim's uid. The victim's `collectionGroup` query then returned a row
  whose room they cannot read, and `Future.wait` in
  `watchMyCommunities()` emptied their entire Communities tab — with **no
  action available to the victim**. Writes are now limited to
  `displayName`, `photoUrl` and `updatedAt`, with `userId`, `role` and
  `joinedAt` pinned.
- **FIXED (`952d8e4`) — a production trap: rooms nobody could leave.**
  `2fc05e5` made `memberCount` the gate on removing a membership row while
  leaving hosts able to write that counter, so a host — including a banned
  one, since the room-update host branch checks no account status — could
  starve it to zero in three plain writes and make membership unremovable
  for everyone. It also fired **with no attacker at all**, on any room
  whose counter had drifted below its true row count, legacy rooms
  carrying no `memberCount` field being the clearest case. Fixed by
  removing rules-level eviction entirely rather than guarding it. See
  [ADR-056](Decisions.md#adr-056-a-moderation-action-belongs-in-a-callable-that-completes-the-whole-removal-not-in-a-rule-that-deletes-one-row).

If you're about to change `firestore.rules`, `storage.rules`, or anything
in `functions/`, read [SECURITY.md](SECURITY.md#firestore-security-rules--design-principles)'s
design principles and checklist first — each one maps to a specific
failure mode this codebase has actually hit before (self-role assignment,
missing field validation, `collectionGroup()` rule gaps, client-trusted
permission flags).

## Data integrity

- **FIXED IN SOURCE 2026-08-20, NOT DEPLOYED — the two staff surfaces that
  report live rooms both under-reported them, and by the majority shape.**
  `getAdminDashboard`'s `liveRooms` figure and `getStaffOverview`'s live-room
  count *and* list all ran
  `where("status","==","active").where("isLive","==",true)`. That form matches
  only documents where `status` is PRESENT and equal, and **25 of the 45
  production rooms carry no `status` field at all** — so every legacy room was
  invisible to the only people who can act on it. This is the same defect
  `b7c6d99` fixed on the callable side by introducing `roomIsActive()`
  ([ADR-093](Decisions.md#adr-093-an-absent-status-means-active--one-reading-of-the-field-shared-by-the-rules-and-every-callable));
  the aggregates were not part of that change, and
  [DEPLOYMENT.md](DEPLOYMENT.md) recorded them as a known, untouched gap when
  the liveness sweeper shipped. Both now go through one shared
  `listLiveActiveRoomDocs()` (`functions/rooms/live_rooms.js`) that queries
  `isLive` alone and applies `roomIsActive()` in memory, exactly as
  `liveness_sweeper.js` already did
  ([ADR-097](Decisions.md#adr-097-a-live-room-count-that-must-honour-an-absent-status-is-a-bounded-read-not-a-count-aggregate)).
  The staff overview issued that query **twice** — once to count, once to
  list — and now issues it once. **Index impact, checked because dropping a
  clause changes which index serves the query**: the two-equality form needed
  a zigzag merge of two automatic single-field indexes (there is no
  `(status, isLive)` composite in `firestore.indexes.json`); a single equality
  on `isLive` is served by the automatic single-field index alone, so this
  **removes** an index dependency and needs no deploy of
  `firestore.indexes.json`. It is also the identical query the deployed
  sweeper has run every five minutes since `b7c6d99`. Verified: 754 Functions
  tests, 0 failures, on a clean emulator; the three new no-status cases were
  each confirmed to FAIL against the reinstated query. **Not deployed** — this
  is a Cloud Functions change only, no rules, index, client or Storage change.
- **FIXED IN SOURCE 2026-08-20, NOT DEPLOYED — `adminDeleteClub` left
  `activeVoiceSessions/{uid}/rooms/{roomId}` mirrors behind forever.** The
  per-room teardown loop in `functions/admin/clubs.js` called
  `liveKitControl.endRoom`, `cleanupRoomMedia` and
  `deleteDocumentRecursively` for each of the club's rooms but never
  `deleteActiveVoiceSessionsForRoom(roomDocument.id)` — unlike
  `setClubModerationStatus` in the same file, which has always cleared the
  mirrors right after `endRoom`. The mirrors live in a separate top-level
  collection, so recursive room deletion never touches them, and nothing
  else expires them: every voice session active at admin-deletion time
  became a permanent orphan. Fixed by adding the call after `endRoom` in
  the loop; the "admin Club deletion lifecycle" test in
  `functions/test/club_membership_security.test.js` now seeds two session
  mirrors — one with a participant row and one without (the
  collection-group sweep path) — and proves both are gone, and fails
  without the fix (verified by reverting it).

- **FIXED IN SOURCE 2026-08-19, NOT DEPLOYED — extra fields on a room message
  silently dropped the sender's achievement credit.**
  `functions/achievements/sources.js` treats an exact six-key room message as
  canonical; any extra field made the adapter return `null` and the event was
  skipped, with nothing logged and nothing visible to the sender. The
  pre-`01c0ab2` rule allowed arbitrary extra fields, so the two halves of the
  same contract disagreed. The rules allowlist is now that same six-key set,
  so **rules and adapter agree**. Consequence to carry: any new field on a
  room message needs a rules change *and* an `achievements/sources.js` change
  in the same commit, or this recurs.

- **OPEN, and not fixable from the client — presence is never cleared on
  process death.** `AuthService.signOut()` now clears presence inside the live
  session, but a force-quit or a server-revoked refresh token never reaches
  client code, and no client can write for a session that no longer exists.
  `functions/` has no presence sweeper — `public_profiles.js` clears
  `isOnline` only on account deletion — so those accounts stay online to
  their friends indefinitely. Closing it needs a scheduled function expiring
  `users/{uid}` on a stale `presenceUpdatedAt`, or a staleness cutoff when
  reading `socialPresence`. Flagged in the code's doc comment rather than
  approximated. Tracked as Roadmap item 0q.

- **OPEN, reported while writing the club-discovery list rule — a family
  room's owner can still set privacy `public` from the settings screen.** It
  grants nothing today (the new `clubs` list rule excludes family clubs by
  `type`, and the room's own reads are governed separately), but a family
  surface offering a public setting is a contradiction the UI should not
  present. Communication-muted accounts can also still react to messages.

- **[OPEN — needs a product decision] Three direct-conversation threads and
  ~30 rooms belong to dead Auth accounts.** `SqEQ493FrDUnD8l7j0egaoNCHnk2`
  ("Griefer") and `hMwXnWimPQOYhk50TPPw62towbc2` ("testGriefer") no longer
  exist in Firebase Auth, but their `users` docs, empty `publicProfiles`,
  three legacy DM threads (33 messages) and dozens of test rooms remain.
  The 2026-08-18 migration correctly refused those threads
  (`invalidPublicProfile`); the living-party UX is a chat row that cannot
  be operated on. Decide: retire/delete dead-party threads and orphan
  rooms, or keep them frozen. 25 of 43 `users` docs are Auth orphans in
  total. A pre-decision snapshot exists in
  `~/Documents/YO Voice Backups/2026-08-18-pre-dm-migration.json`.

- **[FIXED 2026-08-18] The "beyb" zombie room** (`mwrohOrlGAHQQBfCX2sn`,
  `status: closed`, `deletionInProgress: true`): a `deleteRoomSelf` crash
  (ADR-078) committed the closing transaction and died before teardown.
  The callable fix is deployed; the host's next Delete retry completes the
  removal (verified retryable: `closed` ∈ ROOM_STATUSES and
  `deletionInProgress` does not block deletion). Home no longer renders
  mid-deletion rooms as startable.


- **FIXED IN SOURCE 2026-08-17, NOT YET DEPLOYED — a `not-found` from any
  messaging callable disabled the entire server-side guard set, and a
  failed conversation open wrote a thread the backend can never touch
  again.** `MessageService._isCallableUnavailable` counted `not-found` as
  "the callable is not deployed". The server throws `not-found` itself as
  an ordinary refusal — `functions/integrity/guards.js:157` when
  `users/{uid}` is missing, `functions/messaging/direct_integrity.js:83`
  and `:223`. So a user with no `users` document received `not-found` from
  **every** messaging callable and the client read each as an absent
  deployment, silently bypassing `assertNotBlocked`,
  `assertNotRestricted` and the rate limits across send, edit, delete,
  react, mark-read and typing. The ambiguity is irreducible — an
  undeployed callable is HTTP 404 too — so `not-found` now propagates and
  only `unimplemented` signals absence.

  **The conversation-open path made it a data-integrity bug, not just an
  authorization one.** On that swallowed error, `openOrCreateConversation`
  created the conversation root itself. The client cannot write
  `directConversationPairs/{pairKey}` — no rules match block, by design —
  so the root has no pair guard, and `validateConversation` refuses it
  with `data-loss`, "The canonical conversation is missing.", on every
  later server call, permanently. It also carried 12 keys against the
  required 18. **This is the same class of defect as the
  `_publishRecordedMomentLegacy` entry below** — a client fallback writing
  a document an exact-key server validator will reject forever — with one
  difference that makes it worse: that one is latent because nothing
  reaches the path, while this one had a live trigger in production, and
  the 32 accounts with no public profile
  ([Roadmap 0a](Roadmap.md#0a-run-the-public-profile-backfill-verified-consistent-2026-08-18))
  are the population most likely to have hit it.

  `openDirectConversation` is now the only production path and its answer
  stands, success or failure; `conversations` create is `if false` in
  `firestore.rules` so the invariant holds for installs that will never
  update; `directConversationPairs` keeps no match block, now a recorded
  decision
  ([ADR-062](Decisions.md#adr-062-the-client-never-creates-a-direct-conversation--canonical-binding-is-server-only-and-a-legacy-thread-is-adopted-in-place-not-forked)).
  Covered by `test/direct_conversation_open_test.dart` (18 cases, all
  Firestore-level), an inverted case in
  `test/direct_message_send_test.dart` that previously asserted the
  defective behaviour outright, and three new checks in
  `firestore-tests/rules.test.js`.

  **Roots already written this way are stranded and their count is
  unmeasured.** They are identifiable by a missing `pairKey`/`schemaVersion`
  on the conversation document, or by the absence of a
  `directConversationPairs` entry for the pair. They are repairable —
  unlike the duplicate messages below — because
  `migrateDirectIntegrityConversation` adopts a legacy root **in place** at
  its existing id, preserving history. That migration has never been run
  against production; it is
  [Roadmap 0m](Roadmap.md#0m-run-the-direct-conversation-migration-there-are-stranded-legacy-roots-in-production).
  Until it is, `openDirectConversation` **forks**: it derives a fresh
  `dm_<hash>` id, binds the pair to that, and leaves the legacy thread and
  its history behind. That fork is pinned by a test in
  `functions/test/direct_integrity.test.js` so the cost of not running the
  migration is visible in the suite.

- **FIXED IN SOURCE 2026-08-17 (`8f7aa03`), NOT YET DEPLOYED — every direct
  message was written to Firestore twice.**
  `MessageService.sendTextMessage` called the `sendDirectMessage` callable,
  which creates the canonical message document and updates the conversation
  summary server-side inside one transaction, and then ran its own client
  batch write **unconditionally** — the early return existed only on the
  fallback path. Every send in production therefore produced a second
  message document under a Firestore auto-id and incremented
  `unreadCounts.<recipientId>` twice. Both copies render: `watchMessages`
  orders by `sentAt` with no filter. `sendTextMessage` now returns as soon
  as the callable answers, and the client write is reached only when it
  does not
  ([ADR-061](Decisions.md#adr-061-a-callable-that-answers-is-the-whole-write-and-its-client-fallback-must-write-the-same-document)).

  **It went unnoticed because no test had ever executed that branch.**
  Every Flutter test injected a `NotificationService`, which sets
  `_preferLegacyBehaviour` and short-circuits `_tryCallable` to `false`, so
  the callable-success path was unreachable from the entire suite — a green
  suite covering exactly one side of the fork that mattered.
  `test/direct_message_send_test.dart` now asserts at Firestore level on
  both paths, "exactly one message document" included; against the pre-fix
  service it fails 10 of its cases, the probe reading being
  `messages=2 unread[recipient]=2` where 1 and 1 were expected.

  **The duplicates already in production are permanent, and their volume is
  unmeasured.** They carry 14 keys, not the canonical 16, so `validateMessage`
  refuses them and the server can never edit, delete, react to, or accept
  them as a reply target. Identifying them by their missing `schemaVersion`
  over-selects on its own — it also matches every pre-fix *fallback* write —
  so a cleanup pass needs that paired with a deploy-date cutoff or a
  same-sender-and-content twin. Three things reasoned from code and **not
  yet verified against production data**: read-marking was never poisoned
  (`markDirectConversationRead` filters on `sequence > N`, and a range
  filter excludes documents missing the field), inflated `unreadCounts`
  self-heal on the recipient's next open, and the canonical chain is intact
  because only the server ever advanced `lastMessageSequence`. Duplicates
  keep accruing until a client carrying `8f7aa03` ships — no client release
  is recorded after that commit.

  The same commit closed three messaging failures that were invisible to
  the user, found while in the file: `toggleReaction`, `setTyping` and the
  un-archive inside an unawaited handler all swallowed their errors. They
  initially used the shared error mapping. The 2026-08-29 incident refined
  that boundary: reaction and un-archive failures remain actionable, while
  ephemeral typing failures are logged but silent because the sender cannot
  repair them from the composer. Covered by
  `test/messages_silent_failure_test.dart`.

- **FIXED 2026-08-16 — accounts with no public profile were invisible to
  everyone else.** After the ADR-054 rules cutover, `users` became
  owner-`get` only and non-listable, so an account with no
  `publicProfiles` projection could not be seen by any other user in
  either client. The backfill closed it: 14 projections created, 28 writes
  applied, and a verification re-run planned zero writes with all 33
  accounts unchanged — idempotent against real production data.

  **Worth remembering how the headline number was wrong.** A console count
  of 33 `users` against 1 `publicProfiles` reads as 32 missing. The
  backfill's own dry run showed the truth: **18 of the 33 are Auth
  orphans**, which correctly get no projection. The real gap was 14.
  Counting two collections against each other is not a measurement when one
  of them is derived with conditions.

- **OPEN — 18 `users` documents have no Firebase Auth account.** Surfaced
  by the backfill's `authOrphans: 18` on 2026-08-16. Origin unknown; most
  are likely deleted test accounts from before `onAuthUserDeleted` existed,
  since that trigger only covers deletions occurring after it was deployed
  the same day. They hold no projection and are invisible, so nothing is
  user-facing — but they are stale personal data with no owner, which makes
  this a retention question as much as a tidiness one. Decide deliberately
  whether to delete them; do not fold it into an unrelated migration.

- **FIXED 2026-08-16 — the ADR-054 legacy identity scrub has run.** All
  four phases applied, `conflicts: 0`, 21 documents (conversations 5,
  friendRequests 6, following 5, followers 5), verified by a re-run
  planning zero further scrubs. Note it was run *after* the rules deploy,
  which was the wrong order and briefly a live defect rather than
  housekeeping — the ADR-054 deployed rules required follow edges to carry
  exactly `['uid','followedAt']`, Firestore denies a list query if any single
  document fails the rule, so one legacy five-key edge emptied a user's
  entire followers/following list. ADR-114 source later preserves that legacy
  shape while allowing one optional bounded server-owned generation pointer.
  See
  [DEPLOYMENT.md](DEPLOYMENT.md#private-profile-projection-cutover-strict-order--executed-2026-08-16).

- **FIXED AND DEPLOYED 2026-08-16 — the real Club creation batch was
  rejected even for an entitled owner.** `ClubService` atomically creates the
  Club, owner member, user's Club projection, three default channels and the
  lounge room. Owner-member/channel rules used pre-write `get()`, so they could
  not see the new Club root inside that same commit; the batch also included a
  dead root-user `clubCount` update outside the self-write allowlist. Those
  rules now use `getAfter()`, the unused counter write is removed, and the
  emulator suite exercises the full seven-document batch.

- **KNOWN AND ACCEPTED — `rooms/{roomId}.memberCount` can overcount.** A
  client that deletes its `roomMembers` row without pairing the room write
  leaves the counter high. It can never undercount below a real departure,
  which is the property that matters: an undercount was what trapped
  members in rooms they could not leave. Treat the field as an upper
  bound. Deliberate trade, `952d8e4`,
  [ADR-056](Decisions.md#adr-056-a-moderation-action-belongs-in-a-callable-that-completes-the-whole-removal-not-in-a-rule-that-deletes-one-row).

  **Swept in production 2026-08-17: no victims exist.** 50 rooms examined,
  **28** whose stored count disagrees with their true row count, **0
  trapped** — every mismatched room has zero membership rows, so there was
  never anyone to trap. **24 rooms carry no `memberCount` field at all**,
  which is precisely the legacy shape that *would* have trapped members had
  any of those rooms had one. The trap was real; it simply did not land
  before `952d8e4` removed it. No repair migration is needed, and none
  should be written for the overcount — it is the accepted direction.

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

## Branding

- **FIXED IN SOURCE 2026-08-28 — Android adaptive launcher icon overfilled
  OEM masks.** The transparent foreground occupied about 84.5% of its source
  layer and was inset by only 8%, leaving the rendered mark up to roughly
  77dp tall against Android's 66dp adaptive safe area. The Android-only inset
  is now 16%, matching the generator default and keeping the symbol within the
  safe area on circle, squircle and rounded-square masks. The canonical PNG,
  legacy Android icon and every iOS/App Store asset are unchanged. Android
  build 7 is available to the existing 10 internal testers; an update and
  fresh-install launcher check remain release evidence.
- **FIXED — native launcher/store icons still contained the retired black
  square.** Web favicons had already moved to the transparent canonical mark,
  but `flutter_launcher_icons` continued reading the old opaque `logo.png`.
  Android adaptive, Android legacy, iOS/App Store, macOS, Windows and the
  in-app compact logo now derive from the favicon artwork. Opaque platforms
  receive only the required full-bleed product background, without a second
  black tile around the symbol.
- **FIXED — opening the app could show two sequential, time-based loading
  screens.** The landing site's `/app` route imposed a 2.8-second animation
  before navigation, then authenticated Flutter sessions imposed another
  four-second welcome timer. `/app` now redirects immediately, the fixed
  Flutter timer is gone, and the app origin owns one matching sound-wave
  startup surface that exists only while the engine/Auth state genuinely
  resolves. Its shared responsive layout uses a larger, lowered logo with the
  title layered across the mark's lower edge instead of floating too high.
- **FIXED IN SOURCE 2026-08-27 — the remaining native-to-Flutter launch handoff
  visibly jumped.** iOS launch images were 1×1 transparent, Android's mark was
  commented out (and Android 12 had no matching system-splash theme), the ring
  opacity reset at its modulo boundary, and Auth replaced the loading surface
  without a transition. Native iOS/Android and Flutter now share the same
  #0D0618 surface, centred 170 logical-pixel mark and Android light/dark API-31 themes;
  the ring envelope reaches zero on both sides of its wrap and Auth crossfades
  for 220 ms (or instantly under Reduce Motion). The mark is positioned in its
  own centred layer, so text metrics and 200% scaling cannot move it. **WEB
  DEPLOYED 2026-08-27; native iOS and Android 12+ handoff remains pending and
  still needs device verification.** See ADR-052.

## Notifications

- **FIXED — notification activity could stop at the numeric bell badge.**
  Android referenced `yovoice_default` but never created the channel, the
  server payload did not select a channel or default sound/vibration, and a
  focused browser tab did not present foreground FCM messages. The app now
  creates a high-importance audible channel, explicitly presents native
  foreground alerts with sound, shows a compact actionable web banner, and
  sends platform-specific audible/visible payload options. Device/browser
  notification permission, Focus/Do Not Disturb and mute settings remain OS
  controls and cannot be overridden by an app.

- **SUPERSEDED — friend requests, acceptances and follows could silently
  produce no notification.** All three were a second client write issued
  after the authoritative write, inside `try { ... } catch (_) {}`. Any
  interruption between the two writes lost the notification permanently
  and reported nothing. ADR-041 first moved them to derived triggers.
  ADR-114 supersedes that implementation with the social callable as the
  single transactional writer, because the trigger and callable later
  overlapped.
  **Deployed 2026-08-16, retired 2026-08-25** — those three historical
  triggers were explicitly deleted when ADR-114 became the production
  single-writer contract.
- **FIXED AND DEPLOYED 2026-08-25 — resolved/cancelled friend requests could leave or
  resurrect an unread alert.** Cancel omitted the notification cleanup and
  legacy source triggers could overwrite the callable's resolved state. The
  callable now retires actionable rows atomically on accept/decline/cancel,
  repairs stale rows on replay, and retires the active lifecycle rows on
  unfriend/unfollow so later lifecycles receive fresh generation ids.
  Friend-request taps open Requests with Accept/Decline, the mobile bell shows
  the unread count, and new lifecycles use generation-specific ids. Push
  delivery re-checks both document generation and the canonical graph source;
  retired compatibility ids were removed during rollout (ADR-114). The
  production journey passed before and after trigger deletion, and the final
  source-aware sweep planned zero further deletions.
- **FIXED — clients could forge these three notification types.** A
  client could write "X accepted your friend request" with no friendship
  existing; rules cannot check that. The three types were removed from
  the client-creatable list, and the server authority validates the
  friendship itself. ADR-114 now keeps that authority inside the deployed
  graph transaction.
- **FIXED — web push configuration.** The service worker
  (`web/firebase-messaging-sw.js`) now exists and ships in the build, and
  `getToken()` passes a `vapidKey` from
  `--dart-define=YOVOICE_WEB_PUSH_VAPID_KEY`. The production public key is
  generated in Firebase and supplied by the Hosting workflow. Without a key,
  local builds still skip web push setup entirely — no permission prompt
  spent, no `getToken()` call, no empty token written, one clear log line.
  End-to-end delivery still needs a signed-in real-browser smoke test.
- **FIXED — the Notifications screen collapsed on an unrelated failure.**
  It returned one "Could not load notifications" state if ANY of three
  streams errored, including the unrelated conversations stream, and
  spun while any one was still loading. Loading and fatal errors now
  depend on the activity feed alone; an auxiliary failure degrades to a
  small notice above the feed, which keeps rendering.
- **OPEN — `mention` has no authoritative writer.** Firestore Rules deny every
  client notification create. Club/room invites, direct messages and replies
  use server paths; mention remains an enum/rendering contract without a
  production writer and must not be described as a client best-effort path.

## Achievements

- **FIXED LIVE 2026-08-19 — three infinite trigger retry loops: the second
  qualifying action of a user-day was an unresolvable ledger collision.**
  `activeDay` events key their dedup identity on (uid, UTC day) but carried
  the triggering event's exact time inside the content fingerprint, so the
  first action of a day wrote the ledger entry and every later action that
  same day derived the same eventId with a different fingerprint. The engine
  threw `AchievementEventIntegrityError` (fail closed) and, with `retry:
  true`, Eventarc redelivered forever — the primary event's transaction had
  already committed, so each loop burned invocations every 1–3 minutes.
  Latent since the 2026-08-16 launch; first tripped 2026-08-18 17:34Z.
  Production had three loops across `onAchievementRoomMessageCreated` and
  `onAchievementDirectMessageCreated` (ledger ids `v1_29153e…`, `v1_96d81c…`
  — hit by both a room message and a DM — and the unreported `v1_3c2af0…`).
  Fixed by ADR-081: mismatches are terminal (quiet replay for
  same-content-different-time recurrences, logged collision otherwise),
  `activeDay` content is now a pure function of (uid, day), and the four
  pre-fix ledger entries were rewritten canonically by
  `functions/scripts/repair_achievement_canonical_ledger.js`. Regression
  tests fail 10/10 against the pre-fix code.

- **FIXED LIVE 2026-08-19 — `reconcileAchievementsV1` was wedged on the
  first user in the collection since its first run (2026-08-16 18:40Z).**
  That user's document is a legacy presence-only skeleton;
  `legacyProgressFromUser` returned `undefined` for two fields, Firestore
  rejected the bootstrap write, and `failUser` then merge-created a partial
  record ({status, failureCode, updatedAt} only) that `beginUser` rejected
  as "Stored user migration state is malformed" on every 15-minute run —
  ~96 failures/day for three days, with the global cursor never advancing
  past user one. Distinct root cause from the retry loops, same
  fail-closed-forever pattern, surfaced in the same incident review. Fixed:
  the bootstrap shape is undefined-safe, `failUser` always writes a
  self-describing record with an attempt counter, `beginUser`
  re-initializes pre-bootstrap failures (terminal after 5 attempts) and
  marks contradictory records failed while the run advances. The production
  poison record was rewritten by the ADR-081 repair script.

- **FIXED IN SOURCE 2026-08-19 (preventive) — the reconciler bootstrap
  would have erased live verified progress.** `beginUser` unconditionally
  overwrote `achievementProgress/{uid}` with a legacy bootstrap. Three
  production users already hold live trigger-accrued verified progress the
  dedup ledger can never replay; once the unwedged reconciler reached them,
  their verified counters would have been reset and the legacy floors
  re-derived from user-document counters the projection had already
  replaced with verified values. `beginUser` now adopts existing progress
  untouched and derives audit floors from it. Caught by review during the
  ADR-081 incident work, before the reconciler ever reached those users.

- **FIXED — every achievement progress transaction was denied by Firestore.**
  `AchievementService` atomically writes the metric counter, unlocked ids,
  unlock timestamps, selected title and reconciliation timestamp, but the
  self-update allowlist omitted `unlockedTitleTimestamps`. Firestore rejected
  the whole transaction, while best-effort callers intentionally swallowed
  the tracking failure so the source action could still succeed. The field is
  now allowed and emulator-covered; Awards also reconciles counters on open.

- **OPEN — `voiceMinutes` is written by nothing, so the entire voice
  achievement category and Creator Studio's "Voice time" tile are
  permanently zero for every account.** Traced end to end on 2026-08-16:
  `ProfileService` seeds the field to `0`;
  `functions/achievements/model.js` only ever *derives* it from
  `voiceSeconds`; and the sole producer of `voiceSeconds` is
  `receiveLiveKitAchievementWebhook` in
  `functions/achievements/livekit_http.js`, which is **never exported from
  `functions/index.js`** and therefore has never been deployed. Nothing is
  broken in the sense of erroring — the number is simply always zero, and
  both surfaces present it as a real measurement. Wiring the webhook also
  fixes the `publishPublicStatsSchedule` data-source problem, since
  LiveKit emits `participant_left` / `participant_connection_aborted` even
  on a crash. Until then, do not read `voiceMinutes` as a metric.

## Moderation & safety

- **FIXED IN SOURCE 2026-08-21, INDEX NOT DEPLOYED — the Admin Center's
  room-status filter did not work for any value, and its "active" value
  asked the wrong question.** `listAdminRooms` built
  `where("status", "==", status).orderBy("updatedAt", "desc")`, and **no
  `status`+`updatedAt` composite index exists in the live project** — so
  every status filter returned `9 FAILED_PRECONDITION`, not a truncated
  list. Underneath that, the "active" value contradicted ADR-093: a
  production census (2026-08-21) finds 45 rooms carrying **9 explicit
  `"active"`, 11 `"closed"`, and 25 no `status` at all**, so the literal
  clause recognised 9 of the 34 rooms the rules call active — while
  `mapRoom`, in the same callable, already reported those 25 as
  `status: "active"` to the browser. "Active" now means active as the rules
  read it (`roomIsActive()`, in memory, for that value only); other values
  keep the indexed equality. Eight cases in
  `functions/test/admin_room_listing.test.js` pin it, three of which fail
  against the unfixed callable. **Still open**: `closed` and `suspended`
  stay broken until `firebase deploy --only firestore:indexes` runs — and
  that deploy must NOT be run from this branch alone, which lacks the live
  `clubs.clubId` exemption and would offer to delete it. Note this callable
  has no caller in `lib/` — the browser it serves is in the website or
  unbuilt — so the user-visible impact is confined to whoever calls it.
  [ADR-101](Decisions.md#adr-101-the-admin-centers-active-room-filter-reads-status-the-way-the-rules-do--and-the-filter-it-replaced-never-ran-at-all).

- **OPEN, found 2026-08-21 — three layers disagree about what an absent club
  `status` means, and one of them invents a value.** Unlike rooms, the club
  rules read the field BARE (`get(clubPath).data.status == 'active'`, three
  sites in `firestore.rules`), so a club with no `status` is not active to
  the ruleset — while `functions/clubs/deletion.js:128` defaults it the
  other way (`String(club.status ?? "active")`), treating the same club as
  deletable-because-active. Separately, `mapClub`
  (`functions/admin/clubs.js`) defaults an absent status to **`"open"`**, a
  value nothing in the codebase ever writes: production clubs carry
  `"active"` or `"closed"`. 1 of 3 production clubs has no `status`, so all
  three disagreements are live, just small. Not fixed with the room filter
  on purpose — picking a direction here is a product call about club
  lifecycle, not a mechanical copy of ADR-093, and the wrong pick changes
  who can delete a club. See ADR-101's Consequences.

- **FIXED IN SOURCE 2026-08-19, NOT DEPLOYED, AND NOT VISUALLY VERIFIED —
  club chat moderation had never worked.** A club owner could not remove an
  abusive message from their own club. Three layers held three different
  beliefs: `ClubChatService.deleteMessage` authorised moderator, admin and
  owner; the rule was **author-only**; and the UI never offered the action at
  all, wiring `onLongPress` solely to the viewer's own messages. `b3c27fd`
  ships all three halves together — rules alone are invisible and the client
  alone is denied. The rule carries two **disjoint** branches (author
  retracts, moderator removes), separated on `senderId == uid` vs `!=`
  **before any document read**, because CEL absorbs errors through `||`
  (`<error> || true` ALLOWS). Both branches pin `content` to the empty
  string, so editing is not expressible by anyone. An early version of the
  moderator branch restated only account status, so a **communication-muted
  or unverified-email moderator kept full reach** over every non-owner
  message in every club where they held a role — both sanctions are now
  required on that branch. `f817b41` then fixed an accessibility and visual
  FAIL: the confirmation dialog **silently truncated at large text sizes**
  (no exception, no overflow stripe — the sentence naming the action simply
  vanished, so a user with bigger type confirmed a removal without being told
  what it did), the message header overflowed and **erased the sender name at
  DEFAULT text size** whenever the staff badge was wide, and long-pressing
  the club owner's message did nothing at all so the local refusal copy
  reached nobody. **UNVERIFIED**: nothing was rendered after the reworked
  header and dialog — both review agents died on a session limit — so this
  must not deploy on a UI claim until it has been looked at. See
  [ADR-085](Decisions.md#adr-085-authorization-branches-in-a-rule-are-disjoint-by-construction-because-cels--absorbs-errors).

- **OPEN — a club moderator's removal is recorded nowhere.** Named in the
  rule's own comment as an accepted gap rather than left for a reader to
  discover. The only trigger on that collection is
  `onAchievementClubMessageCreated`, an `onDocumentCreated`, so a moderator
  removal leaves **no `adminAuditLogs` entry**. The client writes
  `deletedBy`/`deletedAt` from day one so an audit trigger has what it needs
  when one exists. Three siblings in the same comment: **no rate limit**, **no
  restore path**, and **no rank ordering** — a moderator can clear an admin's
  or a co-owner's messages.

- **FIXED IN SOURCE 2026-08-19 → 2026-08-20, NOT DEPLOYED — no message
  anywhere in the product could be reported.** Not a DM, not a room message,
  not a club message. `createContentReport` was **deployed and ACTIVE** and
  already accepted `directMessage`, `voiceMoment` and `voiceMomentComment`;
  **no Dart file called it.** The only report action in the product was on a
  profile, with `reason` hardcoded to `harassment`, a fabricated note reading
  "Reported from profile", and no reach into club chat at all. Reporting the
  same person twice showed the raw string
  `[cloud_firestore/permission-denied] The caller does not have permission`,
  because the client was reading back its own report to tell "already filed"
  from a refusal — but `reports` is staff-read by design, so
  `ReportAlreadyFiledException` was **unreachable in production** and one raw
  string covered both the 30-second cooldown and the 20-per-day cap. `9f3ce7f`
  wires every target the callable supports to every surface where that
  content appears, replaces the read-back with the owner-readable
  `reportLimits` document checked before the write, maps nine callable status
  codes to nine distinct sentences, and replaces the hardcoded reason with a
  picker. `2c086c7` adds `roomMessage` and `clubMessage` server-side. Visual
  verification caught what widget tests could not: **both snackbars rendered
  as dim grey on near-black**, because the Material 3 dark snackbar theme
  paints its own colour.

- **OPEN, and actively misleading — the Moderation Center renders a v2 report
  badly.** Two report schemas now coexist in `reports/` after `2c086c7`.
  `targetType` parses to null so **the queue title is blank**, and
  `reportedUserId` defaults to empty so the detail pane says **"This account
  no longer exists"** about a live account. That is worse than blank: a
  moderator reading it will make the wrong call. The fix spans Dart and
  Functions together. Tracked as Roadmap item 0o.

- **OPEN — moderators can triage room and club message reports but cannot
  action them.** `removeAndResolve` is still globalChat-only, so the queue
  now accepts reports it has no removal path for. The vocabulary is already
  aligned (`roomMessage`/`clubMessage` are exactly the target names
  `admin/messages.js` uses for the removal callable), so this is a branch to
  add, not a design to invent.

- **OPEN — `reason` has no server-side enum on the callable path.** The
  client-direct v1 rule in `firestore.rules` constrains `reason` to eight
  values; `createContentReport` does not. So a report whose reason is
  off-list is **invisible to the Moderation Center's equality filter** — it
  exists in the collection and never appears in the filtered queue.

- **OPEN, inherited and restated rather than discovered later — a report
  cannot be re-filed after a moderator dismisses it.** Deduplication rides
  the server's operation ledger with the idempotency key derived from the
  **target** rather than the attempt, so a second report of the same content
  replays the first outcome. The previous deterministic-id path had the same
  limitation. See
  [ADR-087](Decisions.md#adr-087-an-idempotency-key-derived-from-a-request-payload-is-a-compatibility-surface--new-fields-fold-in-only-when-the-target-carries-them).

- **BY DESIGN, not a gap to fill by re-adding a rule — host eviction does
  not exist anywhere in the product.** Removed deliberately in `952d8e4`.
  A rules-level delete removed a roster row and nothing else: the evicted
  account stayed connected to the live audio, kept chat through
  `isRoomParticipant`, and could rejoin a public room immediately. It also
  created a starvation primitive, because the delete was gated on a
  counter the host could write. If the product wants eviction, it needs a
  **callable** that completes the whole removal — roster row, live-audio
  disconnect, chat withdrawal — in the shape of
  `removeRoomParticipantSelf`. Do not restore the rule. Full reasoning:
  [ADR-056](Decisions.md#adr-056-a-moderation-action-belongs-in-a-callable-that-completes-the-whole-removal-not-in-a-rule-that-deletes-one-row).


- **FIXED — Staff Center user lookup could not find existing users.**
  `users.username` is stored AS TYPED (seeded verbatim from the display
  name, e.g. `Sieeema`) while the lookup lowercased the input into a
  case-sensitive Firestore equality — so every casing the owner could
  type missed, and display-name search did not exist at all. Reproduced
  against the emulator with the exact client query, fixed 2026-08-15
  ([ADR-046](Decisions.md#adr-046-user-search-lives-in-a-server-only-directory-behind-an-owner-callable-staff-center-becomes-seven-capability-gated-sections)):
  search now runs server-side over the normalized `userDirectory` index
  (owner-only callable), and `listAdminAuditLogs` was remapped to the
  flat audit schema its queries never actually matched.

- **FIXED — a forged non-owner `superAdmin` role would have been
  mirrored, and rendered, as the owner badge.** `deriveBadge()` never
  saw the uid, so a stale or planted `superAdmin` value in a user
  document reached `publicBadges` verbatim. Fixed 2026-08-15
  ([ADR-045](Decisions.md#adr-045-one-authoritative-identity-badge-system--owner-guarded-derivation-a-batched-client-repository-and-a-single-family-of-badge-widgets)):
  derivation is owner-guarded (publishes `superModerator` + writes the
  `security_alert_non_owner_super_admin` audit event), the batch
  callable demotes stale stored rows, and the backfill refuses to run
  without the owner secret. Global Chat also no longer renders identity
  from the message-embedded `senderIsStaff` flag — badges resolve by
  sender uid from the projection.

- **RESOLVED 2026-08-16, and the premise inverted.** This entry read
  "Production is running a client that is ahead of its backend. Pushing to
  `main` auto-deploys Hosting…" — describing the Global Chat and
  Moderation Center clients shipping ahead of their Functions, indexes and
  rules. `moderateReport`, `listReportAuditTrail` and the `reports` indexes
  are all now deployed (`firebase functions:list`,
  `firebase firestore:indexes`, 2026-08-16).

  Two corrections worth keeping, because both were load-bearing beliefs:
  **(1)** pushing to `main` has not auto-deployed Hosting since `409c7ee`
  — releases are a manual `workflow_dispatch`. **(2)** The drift therefore
  reversed direction: production sat on commit `9fdd8a9` while ~60 Cloud
  Functions were deployed and *inert* because no client called them.
  Backend-ahead-of-client is harder to spot than client-ahead-of-backend,
  because nothing visibly fails. See
  [ADR-055](Decisions.md#adr-055-the-2026-08-16-production-cutover--order-the-deploy-by-what-fails-closed-and-verify-by-fingerprinting-served-bytes).
- **FIXED — the audit timeline's status arrow rendered as a tofu box.**
  `'open → resolved'` used U+2192, and Roboto — the font CanvasKit falls
  back to on web — has no glyph for it. Caught by actually looking at a
  rendered screenshot, not by any test. Now `'open › resolved'`
  (U+203A, which Roboto has). A sweep of every UI string literal found
  no other missing glyph; the remaining non-ASCII characters are emoji,
  which resolve through CanvasKit's emoji fallback.
- **FIXED — a failed audit page took the loaded history with it.** A
  pagination failure in the timeline replaced the whole list with an
  error box, so a moderator lost the history they already had. The error
  is now inline beneath the events, and Retry resumes from the same
  cursor.

- **FIXED — Mobile More could hide Moderation behind Staff Center.** The
  capability mapping returned only one staff destination, so owners and
  super moderators saw Staff Center but lost the separate Moderation entry
  available on desktop. Mobile now lists every destination their server
  capabilities grant; ordinary accounts remain unchanged.
- **FIXED IN SOURCE 2026-08-27 — Mobile More used four rows of oversized
  160–176 px destination cards and forced a normal expanded sheet to scroll.**
  At ordinary text scale destinations are now compact 78 px two-/three-column
  tiles and staff/settings are 58 px rows; a 320×568 ordinary sheet and
  390×844/430×932 owner sheets fit without scrolling. At enlarged text the
  sheet deliberately reflows to full-width rows and keeps scrolling as the
  accessible safety valve. Every action and capability gate remains intact,
  with named ≥44 px targets. **DEPLOYED TO WEB 2026-08-27; NATIVE STORE BUILD
  PENDING.**
- **`adminAuditLogs` has no BROAD staff-facing view.** Entries are
  written deterministically and stay unreadable by every client, staff
  included. A moderator can now see one report's own history through the
  scoped `listReportAuditTrail` callable (ADR-040), which is the only
  client-reachable path into the collection and cannot be pointed
  anywhere else. Reviewing the whole log still means the Firestore
  Console or the admin-only `listAdminAuditLogs` callable.
- **A newly promoted moderator must refresh their token.** Staff access
  requires the signed claim as well as the server record, so promotion
  takes effect when the ID token refreshes (up to an hour, or instantly
  on sign-out/in). Revocation is immediate. This asymmetry is deliberate:
  it fails closed.
- **Global Chat had no report-triage UI** — now addressed by the
  Moderation Center; the note below covers what is still missing. Reports land in `reports`
  and are readable only by accounts holding a `moderator`/`admin`/
  `superAdmin` role claim — through the Firestore Console, because no
  Admin Center screen lists them yet. Filing one records it; nothing is
  automated, and the reporter gets no follow-up. Tracked as the first
  gap to close if Global Chat sees real use
  ([ADR-037](Decisions.md#adr-037-global-chat-is-one-canonical-public-channel-written-directly-under-security-rules-with-a-rules-enforced-rate-limit)).
- **Blocking on Global Chat is a UI filter, not a read boundary.**
  Firestore delivers every channel message to every active account,
  including ones from senders the reader blocked; the panel drops them
  from the rendered list (and waits for the block list before its first
  paint, so nothing flashes). Anyone reading the collection through the
  SDK sees everything. It is also one-directional: an account that
  blocked *you* still sees your public messages. Symmetry, or a real
  per-recipient boundary, would need a mirrored `blockedBy` edge or
  per-user fan-out — deliberately not built here.
- **A ban reaches Firebase Auth slightly after it reaches Firestore.**
  `setUserBan` disables the account, revokes refresh tokens, and writes
  `users/{uid}.banned`. Firestore rules read that field, so database
  access stops on the **next request**. The ID token itself stays
  cryptographically valid until it expires — at most one hour — so any
  surface that trusts the token alone (currently none in this app, but
  worth knowing before adding one) has that window.
- **Global Chat rate limiting is a floor, not a shield.** Rules cap a
  sender at one message every 3 seconds AND 200 per FIXED one-hour
  window, and a reporter at one report every 30 seconds AND 20 per fixed
  24-hour window. The windows tumble rather than slide, so an account can
  send up to 400 messages across two adjacent hours by straddling a
  boundary — still a 3x reduction on the floor's 1,200/h. That
  stops flooding from one account; it does not stop a distributed
  abuser, and there is no content filtering of any kind. Combined with
  [ADR-004](Decisions.md#adr-004-firebase-app-check-integrated-client-side-enforcement-deliberately-off)'s
  open App Check gap, a script holding a valid ID token can post at that
  rate.

## UI

- **OPEN, known at merge 2026-09-07 — the new Reel engagement copy is English
  and Polish only.** `reel_engagement_copy.dart` builds every like/comment
  message through inline `copy.text('English', 'Polski')` pairs rather than
  the canonical translation catalog, so the other **41 locale variants fall
  back to English** for the whole engagement surface: the refusal messages,
  the rate-limit and unverified-email notices, and the comment thread's
  states. The localization source guard does not demand catalog entries on
  this path, so nothing failed — this is a known gap, not a regression that
  slipped through. Contrast with ADR-152's Reel trim strings, which did enter
  the catalog for all 41 variants in the same round. A catalog pass is
  Roadmap item 0t; until it runs, the round violates
  [DEVELOPMENT_WORKFLOW.md](DEVELOPMENT_WORKFLOW.md)'s "language is part of
  the feature" step for this surface, and that is stated rather than papered
  over. Recorded as a consequence in
  [ADR-161](Decisions.md#adr-161-reel-engagement-is-optimistic-in-the-feed-and-authoritative-on-the-server).

- **FIXED AND RELEASED TO WEB 2026-08-29 — collapsing a live-room chat exposed a large
  multi-row control panel that obscured the Home feed.** Phone and compact-
  tablet layouts now use one 82 px YO Live Capsule with a separate room-return
  zone and circular 48 px Chat, Mic and More controls; low-frequency Return and
  Leave/End actions live in a compact modal. The redesign also closes two
  lifecycle hazards found during review: remote session replacement dismisses
  only the exact controls route (never the underlying screen during the
  sheet's reverse transition), and a stale host confirmation cannot disconnect
  the next room. Busy Mute consumes input without advertising an accessibility
  action; mobile honors the full system text scale. Twenty-six focused widget
  regressions and Dark/Pearl production-dock renders cover these boundaries.
  Workflow 33257269683 deployed commit `838bddb`; the verified artifact and
  both Hosting domains are byte-identical at SHA-256 `1835920f7c1c5505`
  (6,476,304 bytes). The coordinated native tester build remains held.

- **Fixed in source 2026-08-29 — Home Moments rendered a large filler card,
  friend-only identities and profile suggestions without audio.** Mobile and
  desktop Home now render a story-style avatar rail: the signed-in avatar
  first, followed authors only, and only when an active Voice Moment has a
  playable audio URL. Multiple Moments from one author become one ordered
  chain. The empty card, duplicate Find creators/Record actions, desktop
  profile shortcuts and divider are gone; a quiet rail ends after the user's
  avatar. Following-load failure fails closed. See ADR-123. The source change
  awaits the next coordinated tester build.

- **FIXED AND RELEASED TO WEB/MOBILE BETA 2026-08-28 — Vibe saved successfully but disappeared on
  full profiles.** The editor wrote `statusMessage`, the model read it back,
  and compact profile previews already used it; both the signed-in member's
  older Voice identity card and the full friend-profile route omitted it.
  Both routes now share one labeled, full-width Vibe headline, treat Vibe alone
  as a populated identity, and wrap the full 80-character value at narrow
  widths and enlarged text. The signed-in card's stale identity predicate also
  omitted `website`, so a website-only profile falsely showed the empty state;
  that branch is fixed too. One regression drives Save through Firestore and
  the shared profile stream; production-widget coverage pins both full-profile
  routes, including 320 px/200% accessibility layouts. Browser inspection
  covered the shared card at 390, 768 and 1180 px plus the actual friend route
  at 1280 px with no visible overflow. The pinned Hosting artifact is live,
  TestFlight build 10 is Testing in both permanent tester groups, and Google
  Play Internal Testing exposes version code 10 to the selected cohort.
  **FOLLOW-UP FIXED IN SOURCE 2026-08-29 — HTTPS links inside the now-visible
  Vibe were still inert text.** Own profile, another member's profile and the
  compact Profile Preview now share one actionable renderer. It removes each
  URL from the prose and presents a separate 48 px link row with the real host,
  a provider label for boundary-verified YouTube, Spotify, Apple Music and
  other known music domains, keyboard focus/Enter, link semantics and an
  external universal-link handoff so the installed music app can claim it and
  the browser remains the fallback. Unknown public HTTPS destinations stay
  honestly labeled External link. User-generated non-HTTPS, credentialed,
  local/private-style, IP, custom-port and non-ASCII-authority URLs remain
  plain text; false/throwing launch attempts stay visible inline without
  exposing platform errors. Parser, double-fire/cooldown, disposal,
  accessibility, preview-bio fallback and 320 px/200% regressions cover the
  path. See ADR-126. **FOLLOW-UP FIXED AND RELEASED TO WEB 2026-08-29 — the Dark Vibe
  surface and identity chips used primary purple beneath primary-purple
  icons, collapsing the visual hierarchy and dropping informative icon
  contrast as low as 1.46:1.** Vibe now uses a calm opaque semantic surface
  with a separate focus accent, music-link actions use the tertiary
  cyan/teal role, errors use the paired `errorContainer/onErrorContainer`
  roles, and identity metadata sits on neutral surfaces with distinct
  external/voice/learning accents. Dark and Pearl contrast regressions pin
  text at 4.5:1 and informative icons at 3:1; exact production-card renders
  cover 320/390/768/1440 px plus 320 px at 200% text without clipping. The
  served `main.dart.js` on both Hosting domains is byte-identical to the
  verified release (SHA-256 `1a23f11d8e816a0d`, 6,445,943 bytes). The native
  change still waits for the next coordinated tester build.

- **FIXED AND RELEASED TO WEB/MOBILE BETA 2026-08-28 — Podcast Room behaved like a recolored
  Community Room and ignored parts of its own creation contract.** The screen
  showed description/category where the episode topic belonged, counted every
  stage member as “Speaking,” did not expose show format, guidelines or the
  host's `handRaisingEnabled` choice, and required producers to manage requests
  through the generic People sheet. A role-row event also disconnected audio
  immediately even though the moderation callable already updates LiveKit
  permissions in place. Podcast Studio now has an editorial episode hero,
  accurate On stage / speaking now / Audience metrics, producer desk, desktop
  request queue, listener state, and podcast-specific settings. The current
  request path is the participant row only; Rules refuse a new request when
  the producer closes the queue but always permit the listener to lower an
  existing one. Reconnect is a delayed permission-recovery fallback rather
  than the normal promotion path. Responsive frames were rendered at
  320/390/768/1100/1440 px; inspection caught and fixed a short-desktop stage
  overlap before release. Production Firestore Rules and Hosting were verified
  after deployment; the same client is available as TestFlight build 9 and
  Android Internal Testing build 9. See ADR-120.

- **FIXED IN SOURCE 2026-08-27 — a rapid double tap on More could stack
  sheets or pop two different routes.** The shell previously started a new
  modal for every callback, while a More destination's persistent dock
  unconditionally popped and acted on every tap before the first reverse
  transition had removed its overlay. A burst could therefore leave one More
  sheet hidden under another destination, close the newly opened sheet with a
  stale second callback, or pop the shell itself. More presentation is now
  single-flight through the complete modal transition. Destination dock/rail
  actions commit once, pop once, wait for `Route.completed`, and only then
  invoke the shell action. Regressions cover a same-frame double callback,
  launcher-position retap during entry and the closing-animation boundary.
  **DEPLOYED TO WEB 2026-08-27; NATIVE STORE BUILD PENDING.**

- **FIXED IN SOURCE 2026-08-27 — a Voice Moment could not be heard before it
  was published, and availability was limited to fixed presets.** Review now
  plays, pauses and seeks the temporary native file or browser Blob locally,
  before Firestore reservation or Storage upload. The author chooses any whole
  24–720 hours, 1–30 days, or Until deleted; the 24-hour wire default remains
  compatible. Playback is stopped and disposed before publish, record-again,
  Back or discard, and caption/lifetime lock after a first publish attempt so
  an idempotent retry cannot silently change its contract. Voice replies gain
  preview without their own lifetime selector. **DEPLOYED TO WEB 2026-08-27;
  NATIVE STORE BUILD PENDING.**

- **FIXED IN SOURCE 2026-08-27 — desktop Recent Chats could show a ghost
  initial or turn a real portrait into an unrecognizable color stripe.** The
  desktop card trusted only `conversations.participantPhotoUrls`, so an older
  empty/stale denormalized value disagreed with profile surfaces already
  reading the current public projection. A loaded image was then enlarged
  1.14×, blurred at sigma 12 with low-quality filtering and covered by a scrim
  reaching 98%, erasing identity. Desktop Home now keeps at most three active
  public-profile point listeners for visible chat partners and falls back to
  conversation metadata on load/error. Artwork uses a sharp, face-biased
  full-bleed cover, medium filtering and a lower text scrim; missing/broken
  photos get a deliberate branded accent/monogram. Mobile remains unchanged.
  Widget/integration coverage pins the live-photo repair, image treatment,
  fallback, semantics, keyboard path and 200% layout; a production-theme frame
  was rendered and inspected. **DEPLOYED TO WEB 2026-08-27; NATIVE STORE BUILD
  PENDING.** See ADR-111.

- **FIXED AND DEPLOYED 2026-08-25 — modal sheets drew two detached
  drag handles and offered no obvious universal way to close them.** The app
  theme enabled Material's automatic bottom-sheet handle globally while many
  custom sheets also painted their own bar. On transparent draggable routes,
  notably New Message, the framework bar belonged to the full route at the
  top of the viewport and the custom bar belonged to the visible panel, so one
  sheet looked like two stacked layers. Every production modal route now owns
  exactly one shared chrome contract: one attached cue on phones/tablets, no
  drag cue on pointer-first desktop, and an explicit named Close target of at
  least 44 px everywhere. Scrim, swipe, Back and Escape remain available.
  New Message uses `DraggableScrollableSheet(expand: false)`, and Profile
  Preview now scrolls and stacks its actions when enlarged text or narrow
  geometry makes a fixed row unsafe. See
  [ADR-113](Decisions.md#adr-113-modal-sheets-own-one-chrome-contract-instead-of-inheriting-a-global-drag-handle).

- **FIXED AND DEPLOYED 2026-08-22 — the bottom-nav center logo lost its
  circle.** Per the operator's before/after spec: the 58pt gradient disc,
  border ring and circular BoxShadow are gone; the standalone transparent
  mark renders at the spec's responsive sizes (56/62/66 for 320-/360-/400+),
  floats 12px above the row inside an invisible 72pt tap target, and glows
  along its own silhouette (a blurred tinted copy of the same asset —
  logo-glow.png was rejected: no alpha channel, baked background). The
  live-in-a-room state warms the glow to the live red instead of drawing a
  ring. Pinned by tests that fail on ANY circular ancestor of the mark.

- **FIXED PRE-DEPLOY 2026-08-22 (ADR-103 review) — deleting your own Moment
  failed on any Moment somebody else had engaged with.** The client swept
  the comments/likes subcollections directly, but rules only let each
  engager delete their own docs — permission-denied mid-batch, and under
  the availability amendment deletion is the ONLY exit for a permanent
  Moment. Now routed through the deployed deleteMoment callable (wiring
  pinned by test). Also closed from the same review: own uploading drafts
  offered a Details page that claimed the Moment "reached the end of its
  availability"; the detail header could show "Comments (1)" directly above
  "Be the first to comment." on counter drift; stale 24h-era rules
  comments. OPEN, deferred by the brief: availability cannot be changed
  after publishing; dock "Moments" label ellipsizes at the 320pt floor and
  the feed error state prints a raw exception line (both pre-existing).

- **FIXED AND DEPLOYED 2026-08-22 (ADR-102) — Mute on the live-room bar
  could navigate into the room.** Root cause: the whole bar was one parent
  InkWell(onTap: return-to-room); Flutter forwards taps THROUGH a disabled
  child, and Mute disables briefly on every toggle — so a tap in that
  window (or in inter-icon padding) navigated. Rebuilt as isolated targets;
  a disabled Mute now consumes the tap. Also fixed pre-release from review:
  the mobile expanded-chat sheet outlived a remotely-ended room with a live
  composer; "End room" overclaimed for persistent-room hosts (the server
  ends those on empty roster — label now follows the tap's real effect);
  Expand chat measured 26px tall (now a 44pt floor); tile labels announced
  twice to screen readers; preview overline contrast 4.41:1.

- **OPEN (Voice Moments stories, 2026-08-22)** — known edges shipped with
  ADR-101, deliberately: (1) playback through the row sheet / MomentCard
  does not write the viewed-mark, so a chain fully heard there keeps its
  gradient "unviewed" ring (the story viewer marks correctly); (2) the
  website's `yovoice.app/?moment=` share links outlive the chosen finite
  availability and land on an `isPublished:false/status:'expired'` doc — the
  website's rendering of that shape is unverified; (3)
  `users/{uid}/momentViews` accepts unbounded
  self-writes (same accepted class as the sibling owner-writable
  subcollections).

- **OPEN — Voice Moment expiry is feed visibility, not bearer-media
  revocation.** Published Moments store a Firebase download-token URL. After
  the exact deadline the client hides the Moment and the server refuses new
  engagement; only after the scheduled sweeper retires it do the root and
  authenticated Storage path become private again. A previously copied token
  URL remains usable until explicit deletion/cleanup or token rotation.
  Product copy therefore says how long a Moment stays visible in the feed; it
  does not promise that expiry destroys the bytes.

- **FIXED AND DEPLOYED 2026-08-21 — the redesign's three post-release reviews
  returned FIX_FIRST; every high and medium is closed.** Highlights: the
  podcast HOST's filled column overflowed at 720-850px heights (gate is now
  role-aware: 880 host / 780 guest, pinned by a 1100x800 harness frame whose
  takeException assertion is the regression net); a dormant podcast showed
  "1 Speaking" beside NOT LIVE YET with an unmuted accent mic chip (dormant
  now reports 0 and defaults the placeholder host muted; the dormant host
  dock also no longer offers a red End for a session that does not exist);
  the chat send button and the participants-sheet close had no accessible
  name; the white mic glyph failed non-text contrast on the emerald and gold
  accents (2.0-2.25:1 — glyphs now follow the fill's brightness in the dock
  and the stage chip); '+N' overflow/audience counts and the own-name chat
  color sat under the 4.5:1 small-text bar; dock labels truncated to "Sta…"
  at 200% text (two lines + a caption-only scale cap, full label always in
  Semantics); sidebar nav rows never exposed `selected` to assistive tech
  and sat at 40px (now 44); the bell's "unread" was the rail's one
  unlocalized word; the 768 tablet kept the dead band (fill gate now 700);
  the family hero's lone ↗ became the labeled "Open family space" button;
  chat messages gained real per-message timestamps; the sidebar harness
  rendered under a generic theme (now AppTheme.darkTheme), which immediately
  exposed a real 1px overflow of the Home room card under Inter metrics.

- **OPEN, accessibility (from the 2026-08-21 review) — recorded, not yet
  fixed.** (1) Compact room chat is widget state, not a route: system Back
  exits the whole room instead of closing the chat. (2) Room lifecycle
  transitions (connecting/reconnecting/live/ended) make no polite
  screen-reader announcement; ADR-058's single-LiveRegion constraint applies.
  (3) Sub-44px targets remain: counter pills 34px (informational, but
  tappable in places), reaction chips ~22px. (4) The speaking pulse and
  waveform have no rendered-frame proof (animation; stills cannot show it).

- **FIXED AND DEPLOYED 2026-08-21 (`84ab319`) — three rendering defects found
  only by opening the redesign's PNGs.** (1) The hero's "View club" drew as
  solid blocks: `styleFrom(textStyle:)` replaces a button's text style, so an
  omitted `fontFamily` dropped the control off Inter. (2) The room screenshot
  harness rendered under `ThemeData.dark()` instead of `AppTheme.darkTheme` —
  its PNGs proved nothing about the shipped screens until corrected. (3)
  Letter-fallback avatars stayed app-purple inside emerald/gold/coral rooms
  (stage, header, audience strip, podcast hero credit) — fallback colour now
  derives from the room identity.

- **FIXED AND DEPLOYED 2026-08-20 — family and club rooms were permanently
  undeletable.** The room delete dialog opened for a lounge and its Delete
  button could only display the server refusal "A Club Lounge is deleted
  through the Club lifecycle" — a lifecycle that did not exist anywhere.
  Closed by ADR-096: `deleteClubSelf` plus dialog routing on both delete
  surfaces. Review caught two ship-blockers first: the missing
  `clubs.clubId` COLLECTION_GROUP exemption (production-verified absent;
  emulator-invisible) and a recycled Home menu state that could delete a
  DIFFERENT club than the tile tapped (unkeyed stateful widget in a
  reordering list; regression test fails against the unfixed widget).

- **FIXED AND DEPLOYED 2026-08-20 (`eb51e96`) — muting yourself removed the
  microphone and could never be undone.** `deriveVoiceGrant` and both
  permission-recompute callables folded the participant's OWN `isMuted` into
  LiveKit `canPublish`; the client reads a missing grant as "you are
  audience", hides the mute toggle, and the persisted flag reproduced the trap
  on every re-entry. Same root: self-service joins are rules-pinned to
  `role: 'listener'` while the grant required host-or-speaker, so every
  non-host in a Community/Family room was permanently voiceless. Both fixed —
  see [ADR-094](Decisions.md#adr-094-a-self-mute-is-a-track-state-not-a-permission--and-outside-a-broadcast-everyone-present-may-speak).
  The permission had NO test before this; 7 cases now pin it, 3 failing
  against the old code.

- **FIXED AND DEPLOYED 2026-08-20 (`7938c88`) — Moments counts froze until a
  full page reload.** The feed was a deliberate one-shot `get()`. Counts now
  stream via `watchEngagement()` and patch in place while the board order
  stays frozen per load ([ADR-095](Decisions.md#adr-095-the-moments-board-ranks-deterministically-and-freezes-its-order-while-counts-update-live-in-place)).
  Limitation, stated: live counters cover the 60 most recent published
  Moments.

- **FIXED AND DEPLOYED 2026-08-20 (`7938c88`) — tapping "Your Moment" on Home
  did nothing, and the working part opened the wrong screen.** Only the 66pt
  disc was wrapped in an InkWell — the label and status line under it were
  dead — and the callback pushed the COMMENTS screen, which owns no player,
  so Home was the one surface where a Moment could not be heard. The whole
  tile is now the target and both rails open the playing sheet; mobile's own
  bubble opened the recorder even when a Moment existed and the strip was
  hidden entirely when nobody else had posted.


- **FIXED IN SOURCE 2026-08-20, NOT DEPLOYED AND NOT ROUND-TRIPPED — voice
  had never worked in ANY Community room or lounge.** Reported as "opening a
  Family Room you created yourself and pressing unmute returns *This room is
  not currently live*"; it was not a Family Room bug.
  `createLiveKitToken` refuses a token unless the room says status active and
  `isLive` true. Performing that transition is the **caller's** job, and only
  `enterClubLounge` ever did it — reachable in practice from the Club
  overview alone, because `HomeScreen` is not mounted in the running app (see
  the next entry). `RoomService.startCommunityVoice` had **zero callers**.
  Nine call sites push `RoomEntryScreen`, whose own comment says callers
  joined the room beforehand, and the room screen then asks for a token
  immediately. **Production agreed: 45 rooms, 3 live.** `b0f1062` makes
  entering a room perform the liveness transition for anyone the deployed
  rules would accept, through one coordinator running liveness → roster →
  token. Legacy documents are tolerated deliberately because most production
  rooms are legacy — **25 of 45 carry no `membersCanStartVoice` and 24 have
  neither `roomType` nor `experience`** — so every read defaults rather than
  raising. All 3 club-lounge documents carry `clubId` and `roomKind`, read
  from production, so the operator's own room is genuinely covered. Fixed in
  passing: `CommunityVoiceRoomScreen.dispose` never removed its listener from
  the process-wide `RoomMuteCoordinator` singleton. **UNVERIFIED**: no
  production or emulator round trip, no real LiveKit, no device run — rules
  were read, not executed, and `fake_cloud_firestore` does not evaluate
  rules, so every "the client may start voice" test proves the mirror, not
  the server. Audio quality, reconnect, device routing and the web permission
  path are untouched and unretested. See
  [ADR-088](Decisions.md#adr-088-entering-a-room-performs-the-liveness-transition-through-one-ordered-coordinator-that-mirrors-the-deployed-rule).

- **FIXED AND DEPLOYED 2026-08-20 — a member-started room could stay live
  with nobody in it.** The server dropped `isLive` at zero
  participants **only for lounges**, which was survivable only while nothing
  could set `isLive: true` on an ordinary room. `b0f1062` removed that
  protection: a Community room whose host opted into `membersCanStartVoice`,
  started by a member who then left last, had no exit — `endRoomVoiceSelf` is
  host-only and there was no scheduled sweeper — so it stayed
  `isLive: true, participantCount: 0` and kept advertising itself on
  `watchLivePublicRooms` (Home, Discover) as a live room nobody is in.
  `3ff80e6` fixes it: the last participant out ends the session in **any**
  room, and emptiness is proved from the roster inside the transaction rather
  than from the denormalised `participantCount`
  ([ADR-091](Decisions.md#adr-091-the-roster-not-participantcount-decides-that-a-room-is-empty--and-the-leave-path-asks-the-server-to-prove-it)).
  `executeEndRoomVoice` gained the matching `onlyIfEmpty` re-check.
  **Still open from this cluster**: an ended room still offers Start voice to
  someone who never held a participant row. Tracked as Roadmap item 0p.

- **FIXED AND DEPLOYED 2026-08-20 — a failed join stranded a room live with
  an empty roster, and no client could ever close it.**
  `RoomVoiceEntryCoordinator.enter()` writes liveness first and calls
  `joinRoom` second (it must — `joinRoom` refuses a dormant room and
  `createLiveKitToken` refuses both a dormant room and a caller with no
  participant row). When the join failed the coordinator returned
  `RoomVoiceEntryOutcome.failed` and did **not** call `leaveRoomSelf`: there
  was nothing to leave, the roster row was never written. The room sat
  `isLive: true, participantCount: 0` with an empty `participants`
  subcollection, advertising itself on Home and Discover. A process death
  between the two calls produced the identical document. The state was
  self-healing only if somebody else happened to enter and leave; a room
  nobody revisited stayed a ghost forever, and — because
  `roomVoiceStartAllowed()` requires `isLive == false` — could never be
  *started* again either, only joined. `executeLeaveRoom` deliberately does
  **not** repair it: it returns early without a participant row, and
  extending the repair there would let any signed-in account drop `isLive` on
  a live room during somebody else's start→join window. Closed instead by the
  scheduled `sweepStrandedLiveRoomsSchedule`, which has no caller to
  impersonate
  ([ADR-092](Decisions.md#adr-092-a-scheduled-sweep-closes-the-room-no-client-can-close-and-the-roster-is-still-the-only-thing-that-proves-it-empty)).
  **Still open, and not the same bug**: a client that crashes *while in a
  room* leaves its participant row behind, so the roster is not empty and the
  sweeper correctly skips it — that needs the unexported LiveKit webhook
  (Roadmap item 0h).

- **OPEN, and it is the root cause of two other entries — `HomeScreen` is not
  mounted anywhere in the running app.** `main_shell` holds it at
  `_screens[0]`, but `_slotChildren` special-cases index 0 to
  `MobileHome`/`DesktopHome` and **never reads `_screens[0]`**. So
  `DiscoverClubsRail`, `FromYourClubs` and `LiveNowHero` are finished,
  tested, rendered at three widths and two text scales, and **unreachable by
  any user**. "Discover clubs" exists in exactly one file and that file is
  dead. Placing them into the live compositions is a Home
  information-architecture decision nobody has taken — deliberately not taken
  unilaterally by the implementing session — and the widget APIs make it
  about ten lines per composition. Tracked as Roadmap item 0n.

- **FIXED IN SOURCE 2026-08-19, NOT DEPLOYED — Home's "Discover clubs" rail
  was denied for everyone, and the denial was invisible.** `clubs` carried
  `allow list: if false`, so even a club owner listing their own club was
  refused; the rule's comment claimed no legitimate listing remained, which
  was wrong — the caller had simply been missed. The denial was then
  swallowed by `snapshot.data ?? []` with **no `hasError`**, and the heading
  vanished along with the rail, which is the exact mechanism that hid this
  for the product's life. `01c0ab2` writes the rule entirely in bare field
  accesses so the caller's query must carry three equalities, `155ad61` sends
  them and gives the rail visibly distinct loading, error, empty and
  populated states with `hasError` checked **before** any read of `data`
  (`StreamBuilder` retains data alongside an error) and a Try again that
  re-subscribes (a Firestore subscription is terminated by its first error).
  The same swallowing was fixed where it was actively lying: **"Rooms for
  you" printed "No rooms to show yet, start one and your community will see
  it here" over a permission denial**, and "From your clubs" vanished
  entirely. **The user-visible defect is still not closed** — the rail lives
  in the unmounted `HomeScreen`, so it was broken twice over, independently.
  Several remaining `snapshot.data ?? []` instances are listed in that
  change's report rather than fixed, because each needs a widget's public API
  to grow an error channel.

- **FIXED IN SOURCE 2026-08-19, NOT RENDERED — the Moments screen showed
  engagement it would not let you create, and reported every failure as
  "No Moments yet".** `MomentsScreen` rendered a heart and a like count with
  **no tap target**, while the same feature worked fine on Home; both of its
  `StreamBuilder`s used `snapshot.data ?? []` with no `hasError`, so a
  permission error, a missing index and a still-connecting stream all
  rendered identically; and the screen imported `AppColors` and then
  hardcoded six off-palette colours anyway. All three are addressed in
  `cef05e6`. **UNVERIFIED, and it gates the deploy rather than the commit**:
  nothing has been rendered at any width, the stack interaction has never
  been seen, and the empty state — the state most users on a pre-launch
  product will actually hit — is unconfirmed.

- **A Firestore trap worth carrying forward, found while building the Moments
  feed:** `orderBy('likeCount')` **silently omits every document missing that
  field**. A popularity ordering would therefore have hidden exactly the
  Moments that had never been liked — most of them, on a pre-launch product —
  and the omission would have looked like an empty feed rather than a bug.
  Recorded here because it is the same failure shape as the swallowed
  permission error above: an absence that renders as an empty state.

- **FIXED IN SOURCE 2026-08-18 — the full Profile screen opened on a huge,
  mostly-empty gradient banner with the Back arrow floating alone in the far
  corner.** `ProfileHeader` was a fixed 300–320px banner Stack (38–56% of a
  phone viewport, worse on desktop where the empty gradient stretched across
  the window). It is now a compact, content-sized header: a toolbar row
  (Back when the route can pop — min 44px target, safe-area aware — the
  title, and Edit) aligned with the 18px content gutter inside the same
  bounded frame as the page panels, a slim 104/132px banner accent card
  that keeps the cosmic gradient and any user-uploaded banner, and one
  readable identity block (avatar overlapping the card, name, @username,
  badges, title). The Premium/account-type chips also gained
  Flexible+ellipsis labels, which previously overflowed at 320px width with
  2.0 text scale. Pinned by test/profile_header_compact_test.dart
  (320/390/768/1100/1440, 2.0 text scale at 320 and 1440, header ≤ 30% of a
  390x844 viewport, Back pops) alongside the existing
  test/profile_header_layout_test.dart matrix, and rendered for visual
  proof via test/profile_header_screenshot.dart. A 2026-08-29 density
  follow-up fixes the remaining owner-profile failure visible in production:
  OWNER/VIP/Creator/Premium/title no longer form a four-floor staircase beside
  the avatar. The pseudonym now sits on a compact theme-safe name plate and a
  full-width two-level identity rail separates authority from product and
  achievement labels. Dark/Pearl real-font frames, 320 px/200% text, heading
  semantics, exact two-row owner geometry, Pearl AA contrast and repository
  listener replacement are regression-tested. The follow-up is live on both
  Hosting domains: served `main.dart.js` is byte-identical to the verified
  production build (SHA-256 `a9024e2e02fe0cb3`, 6,444,765 bytes); see ADR-131.

- **FIXED IN SOURCE 2026-08-29 — Light mode painted white-on-white headings,
  stale dark cards and the wrong system-bar icons.** The setting previously
  changed only the root Material theme while Home, dock, modals and most
  journeys still owned dark literals. Pearl now has one semantic palette,
  brightness-aware native chrome, migrated normal-product surfaces and
  explicit immersive-dark voice/media islands. Automated contrast,
  responsive/200% text and real light/dark render checks cover the release;
  see ADR-127.

- **FIXED IN SOURCE 2026-09-01 — Polish no longer stops at a mixed-language
  Beta boundary.** User-facing product copy, errors, loading/empty states,
  tooltips and accessibility labels now pass through `AppLocalizations`, and
  migrated feature roots are protected by a raw-copy source guard. Polish is
  presented as a production language. System plus 43 explicit locale variants
  are available; the additional variants own a strict core catalog and retain
  an honest English fallback outside that boundary. Catalog completeness,
  placeholders, plural/date smoke tests, RTL direction and platform locale
  bundles are automated. Coordinated tester release and physical-device visual
  verification are still pending; see ADR-136.

- **Known platform limitation in the not-yet-deployed source implementation —
  downloaded audio is durable only for as long as this device keeps app/site
  data.** Native files live in the application
  support directory; web copies live in browser Cache Storage, which a browser
  may evict or a user may clear. YO Voice filters a missing object from its
  manifest-backed list and asks for a fresh download; it cannot promise
  permanent browser storage. Server deletion or unpublishing also cannot
  recall a public audio file already downloaded to a user's device. Limits are
  12 MB per item and 250 MB per account/device to bound storage and download
  memory.

- **Not a bug — Devices & sessions does not enumerate or individually revoke
  Firebase logins.** Firebase Auth's Admin SDK supports account-wide refresh-
  token revocation, not a trustworthy device/session list or one-token revoke.
  FCM registrations are push endpoints, not login sessions. The implemented
  control therefore shows the current token session and signs out everywhere;
  it explicitly warns that already-issued stateless ID tokens can continue for
  up to about one hour. See ADR-073 and
  [ACCOUNT_SESSIONS.md](ACCOUNT_SESSIONS.md).

- **Fixed in source (deployment pending): room creation failures and four
  unrelated-looking room interiors.** Podcast creation was denied because
  `showFormat` arrived before its `experience`; Family creation could fail on
  a missing deterministic-root pre-read against the deployed rules; Club
  artwork was uploaded before a canonical Club existed and surfaced a false
  "deploy rules" instruction. Podcast now writes its immutable type
  atomically, Family lets the create batch remain authoritative, and ordinary
  Club media is root-first with a generation-pinned server finalizer. All
  four interiors use the shared stage with purple Community, coral Podcast,
  gold Club and emerald Family identity. Family artwork is intentionally
  disabled: the previous public/token URL model could not revoke access when
  a member left. The fix is verified locally but does not affect production
  until Hosting, Functions and both rulesets are released.

- **Fixed (2026-08-17, this revision): photo and microphone actions in a
  direct chat were placeholders.** Both buttons only displayed “prepared in
  the interface” notices. They now run a real private-media flow: gallery
  selection or a 1–60 second recorder, server reservation, immutable Storage
  upload, canonical message finalization, authenticated image loading and
  voice play/pause/resume. Lost upload/finalize responses reuse the same
  reservation and request id. Independent review also caught and fixed two
  pre-release UI defects: resume restarted audio from zero, and recycled list
  state could briefly show/play the previous message's media.

- **Fixed in code (2026-08-17, this revision; post-deploy iPhone verification
  still required): Safari Voice Moment publish stopped after draft
  reservation but before Storage upload.** Production evidence showed two
  canonical one-second drafts, zero finalizations and zero bucket objects.
  The web path converted a native `MediaRecorder` Blob through
  Blob→ArrayBuffer→Dart bytes→JS bytes. It now gives the native Blob directly
  to Firebase Storage `putBlob`, recovers object generation after an ambiguous
  commit and never deletes a valid object merely because finalization failed.
  The investigation also found a backend bootstrap bug that could replace the
  configured `.firebasestorage.app` bucket with a guessed `.appspot.com`
  bucket; the Admin SDK now respects `FIREBASE_CONFIG` unless an explicit
  bucket override is supplied.

- **Fixed (2026-08-17, `6ef4380`): no production user could record a Voice
  Moment at all.** The recorder called `getTemporaryDirectory()`, which
  `path_provider` does not implement on web, and a broad catch turned the
  `MissingPluginException` into "Could not start recording". Web is the
  only published client, so the entire creator content loop was closed —
  and the error text named nothing that would lead anyone to the platform.
  Fixed by a conditional-export platform seam
  ([ADR-057](Decisions.md#adr-057-voice-moment-recording-splits-only-at-byte-acquisition-and-byte-upload-and-the-server-pins-the-audio-container)).
  **The generalizable part: a catch broad enough to swallow
  `MissingPluginException` converts "this platform is not implemented"
  into "your action failed", which is the one distinction the user needs.**

- **Fixed (2026-08-17, `6ef4380`): the recording waveform was fabricated
  data.** It drew `(index * 17) % 48` — a fixed pattern that moved
  identically whether the microphone heard anything or not — in direct
  violation of this project's no-fake-data rule, and nobody had caught it.
  It now draws the real amplitude stream from the recorder backend.

- **Fixed (2026-08-17, `cefa81a`): a failed publish announced a
  success-sounding line to screen readers.** Flutter web has **no
  per-node `aria-live`** — `LiveRegion` writes into a single shared
  announcement element and clears it after 300 ms, so two live regions
  changing in the same frame overwrite each other. The rule that came out
  of it, and which applies to every screen:
  [ADR-058](Decisions.md#adr-058-one-polite-live-region-per-screen-and-errors-go-out-on-the-assertive-channel).
  **UNVERIFIED with a real screen reader** — no VoiceOver, NVDA or
  TalkBack run has been performed; keyboard tabbing is widget-tested only.

- **Fixed (2026-08-17, `cefa81a`): missing and busy microphones were
  reported as a browser block.** `record_web` collapses every
  `getUserMedia` rejection to a bare `false`, so "no microphone
  connected", "microphone held by another app" and a merely dismissed
  prompt all surfaced as "your browser blocked access" — blaming the user
  for a hardware condition and pointing them at a setting already reading
  Allow. The flow now calls `getUserMedia` directly and maps
  `DOMException.name` onto distinct outcomes with distinct copy
  (`lib/features/moments/data/services/audio_capture/web_microphone_errors.dart`).
  **UNVERIFIED against a real browser refusal** — the mapping is unit-
  tested against synthetic exception names; no real denial, unplugged
  device or device-in-use condition has been reproduced in a browser.

- **Fixed (2026-08-17, `cefa81a`): the recording timer could read
  `0:60 / 1:00`.** The minute component was hard-coded while the seconds
  clamped to 60, and the 60-second auto-stop landed users on exactly that
  frame — so the impossible value was what the last moment of every
  full-length recording showed, not a rare edge.

- **Fixed (2026-08-17, `cefa81a`): the preview harness rendered under
  `ThemeData.dark`, not `AppTheme.darkTheme`.** Screenshots taken through
  it showed neither production typography nor the real input field, so
  earlier visual sign-off on this screen was evidence about the harness.
  The screen also migrated wholesale off raw hex onto `AppColors`, so its
  primary purple finally matches `moments_screen.dart` beside it.
  **Worth remembering: a preview harness that does not install the
  production theme produces screenshots that look like proof and are not.**

- **OPEN release verification (2026-08-17): a real post-deploy iPhone Safari
  publish is still required.** The native-Blob browser seam, native-file seam,
  reservation/finalization retries and Firestore+Storage contracts are now
  automated, but no physical iPhone has exercised the new build against
  production yet. The format decision is described in
  [ADR-057](Decisions.md#adr-057-voice-moment-recording-splits-only-at-byte-acquisition-and-byte-upload-and-the-server-pins-the-audio-container).
  Firefox is
  **known unsupported** and shows an honest unavailable panel — see
  [Roadmap 0i](Roadmap.md#0i-voice-moment-recording-on-firefox-needs-a-coordinated-backend-change).

- **Fixed (2026-08-16): Profile journey metrics expanded into four enormous
  desktop panels.** Their grid height followed the available width, so four
  short values occupied most of a wide screen. `Your YO Voice journey` is now
  one intrinsic-height, four-row list with an icon, label and trailing real
  value. The same production widget is regression-tested at 320, 390, 768,
  1024 and 1440 px without overflow or width-derived height growth.

- **Fixed (2026-08-16): Creator and paid More destinations could look
  available to free accounts.** Creator in Edit profile, Creator Studio and
  More → Clubs now show a lock and contextual Premium explanation unless the
  trusted entitlement grants the matching capability. Navigation preflight,
  a reactive destination guard and the Edit-profile Save recheck all fail
  closed. A visible VIP/Premium badge never authorizes access; existing club
  memberships/invites and Family Rooms remain free.

- **Fixed (2026-08-17): Family Room creation could fail before its batch or
  strand the one deterministic id.** `createFamilyRoom()` probes
  `clubs/family_{uid}` before creating it, but the missing-document rules path
  dereferenced `resource.data`; a first create could therefore stop at its
  initial read. Conversely, a modified client could create only the root and
  consume the account's one canonical id without its membership, channels or
  lounge. The missing self probe is now explicitly allowed, while create is
  accepted only as the complete seven-write graph. Reopen and concurrent
  create attempts converge on the canonical winner before upload cleanup, the
  selected banner is retained, and the success screen opens the actual Family
  Room with Family-specific copy. Emulator, lifecycle and responsive tests
  pin all of these paths.

- **Fixed (2026-08-10): the web app's browser tab showed the YO Voice
  mark inside a solid black square** while the landing page's tab showed
  the clean transparent one. Not a CSS or padding problem — the icon
  files themselves were RealFaviconGenerator output built from a version
  of the artwork with the square baked in, 100% opaque at every size
  (`web/favicon.ico`, `favicon-96x96.png`, `apple-touch-icon.png`,
  `web-app-manifest-*.png`). All of them are now straight downscales of
  the marketing site's canonical transparent icon
  (`yovoice-website/src/app/icon.png`), so both tabs render the same
  mark at the same scale and padding. `favicon.svg` (a 1.6 MB traced
  raster), `favicon.zip`, `favicon.png` and the unreferenced
  `flutter create` `manifest.json` + `icons/Icon-*.png` were deleted with
  them. `test/web_favicon_test.dart` decodes each PNG's corner pixel and
  fails if an opaque one ever comes back; `web/README.md` documents how
  to regenerate. **Needs a Flutter web deploy to reach production** —
  the `?v=2` links and the Hosting `no-cache` header on the icon
  filenames are what stop the cached black-square version from surviving
  it.

- **Fixed (P1, 2026-08-09): room rosters, members and chat messages
  wrote STALE identity (FirebaseAuth displayName/photoURL) instead of
  the canonical profile.** FirebaseAuth's cached identity is not updated
  by profile edits, so a member who changed their name/avatar kept
  appearing with the old one on stage tiles, roster previews and chat
  rows (observed live: CeoGriefer's messages carried a long-replaced
  avatar). Every identity write in `RoomService` (create, join,
  community join, sendRoomMessage) now goes through `_identity()`, which
  reads `users/{uid}` — the avatar system's source of truth — with
  FirebaseAuth only as the unseeded-profile fallback. Verified live in a
  production two-user room: consecutive messages show the stale-then-
  correct avatar (old docs are immutable by design; the server-side
  fan-out repairs rosters on the NEXT profile change, and new writes are
  correct from the start).
- **Fixed (2026-08-09): club lounges stayed `isLive` forever after the
  last member left.** The lounge flow opened the legacy `VoiceCallScreen`,
  whose leave path calls plain `leaveRoom` — `leaveClubLounge` (which
  drops `isLive` at zero participants) had NO callers. Club lounges now
  route through `RoomEntryScreen` into the shared room shell, whose
  leave is lounge-aware. (Part of the board-screen-6 club room rebuild,
  ADR-032.)
- **Fixed (2026-08-09): false "This room has ended" ejection from a
  still-live room.** Observed once: ~80s after creating a community
  room, the host's screen flipped to the ended state with no
  leave/moderation action, while the room stayed live. Root cause:
  both room screens treated "my participant doc is missing from the
  roster snapshot" as proof of removal, but `watchParticipants` is a
  `snapshots()` stream that ALSO emits cache-sourced snapshots (listener
  re-establishment after a network blip, cold-cache re-targeting) — a
  transient snapshot without the own document is indistinguishable at
  the stream level from a moderator removal. The ended state is now
  gated on `RoomService.isParticipantRemovedOnServer()`, an explicit
  `Source.server` read that fails CLOSED (any error ⇒ "still present",
  never an ejection); both screens guard against re-entry while the
  check is in flight. Applies to Community AND Podcast rooms.
  Regression tests: `test/room_removal_confirmation_test.dart`.
  NOTE: the original sighting was never reproduced on demand, so this
  is a root-cause fix for a mechanism that can produce exactly the
  observed symptom, not a confirmed reproduction of that one event.

- **Fixed (P0, 2026-08-08): raw Dart exception text shown to users when
  opening a chat.** Tapping the message icon on a friend could render
  "Dart exception thrown from converted Future…" directly in the UI. Two
  stacked root causes: (1) `openOrCreateConversation`'s
  `transaction.get()` on a not-yet-existing conversation hit a Firestore
  rule that dereferenced `resource.data` on a null resource — a rule
  *evaluation error*, not a permission denial — which Flutter Web boxes
  into that exception text (rules fixed: `get` and `list` split, null
  resource handled by checking the caller's uid inside the deterministic
  conversation id; deployed); (2) 15+ screens rendered `error.toString()`
  directly — all now route through `intentionalOrFriendly()` /
  `friendlyErrorMessage()` (`lib/core/helpers/error_messages.dart`), and
  `auth_provider` stores mapped messages instead of raw exceptions.
  Verified live on iOS Simulator and the deployed web app (first-chat
  bootstrap opens cleanly). Regression tests: `test/error_messages_test.dart`,
  rules suite conversation-bootstrap cases.
- **Superseded by ADR-114 (DEPLOYED 2026-08-25). Fixed (P0,
  2026-08-08): friend-request acceptance never notified the
  original sender.** `notify()`'s dedupe path queried the *recipient's*
  notification subcollection, which rules forbid — the permission-denied
  silently aborted every deduped notify, so the `friendAccepted`
  notification was never written. Rewritten to use deterministic doc IDs
  (the dedupe key IS the doc id; a duplicate becomes a forbidden
  cross-user update, caught and treated as already-sent — zero extra
  reads). Acceptance also retires the acceptor's own `friendRequest`
  notification via `markMatchingRead()`, failures are logged instead of
  swallowed, and decline/cancel stay intentionally silent. Verified by
  emulator rules tests and `test/friend_accept_notification_test.dart`;
  a live two-account UI check needs a second signed-in session
  (UNVERIFIED live — no second test-account session was available to
  this session's tooling). This paragraph records the historical repair; the
  current source no longer uses client `notify()`/`markMatchingRead()` for the
  social lifecycle and instead binds each event to a server-owned generation.
- **Fixed (P0, 2026-08-08): bottom navigation disappeared on More
  destinations.** Deterministic, not random: `_openMoreDestination`
  pushed full-screen routes that covered the shell. Main More
  destinations now keep the persistent bar via `MoreDestinationHost`
  (single source of truth re-hosting the shell's own `_BottomNavigation`;
  bar taps pop back to the shell first). Deep detail flows still cover
  the bar by design. See
  [ADR-026](Decisions.md#adr-026-more-destinations-re-host-the-shells-bottom-navigation-amends-adr-019).
  Verified live on iOS (Settings, Friends) and deployed web
  (Notification preferences). Regression tests:
  `test/more_destination_nav_test.dart`.
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

## Test reliability

- **FIXED (2026-08-19) — `firestore-tests/storage.test.js` was green only
  on a brand-new emulator; a second run against the same instance reported
  five failures that were not rules regressions.** `active owner can create a
  JPEG profile image`, `unverified active owner can upload during onboarding`,
  `legacy exact M4A MIME remains compatible for replies`, `reserved direct
  image uploads with exact identity` and `reserved direct voice media is
  private and enforces the 12 MB cap` all came back `storage/unauthorized` on
  re-run. (It was three failures when first reported; the direct-media cases
  added two more leaking create-only paths, so this was getting worse, not
  settling.)

  Root cause: **`clearStorage()` from `@firebase/rules-unit-testing` removed
  nothing at all here.** It deletes only the `items` a single `listAll()`
  returns at the bucket root, and `listAll()` does not recurse — every object
  this suite writes lives under a prefix (`users/`, `clubs/`,
  `message_attachments/`, `voice_replies/`, …), so every leftover survived it,
  confirmed by listing the bucket immediately after the call. The failing
  cases are the ones whose objects the suite never deletes and whose paths are
  create-only (`allow create: if resource == null`), so the rules correctly
  denied the re-upload. Leftovers on the Club path did not fail, because that
  path permits a replacement — which is why only some of them went red.

  Fixed by walking the prefix tree and deleting every object, then asserting
  the bucket is actually empty so a future unreachable path fails loudly up
  front instead of posing as an authorization regression. No assertion was
  weakened and `storage.rules` was not touched; proven with **three
  consecutive 52/0 runs against one emulator**, immediately after the same
  emulator had produced 47/5 from the unfixed suite. This mattered because red
  lines on an ordinary re-run train people to discount failures in the one
  suite that gates a `storage.rules` deploy.

  `family-media.test.js` calls the same no-op `clearStorage()` but is not
  affected: it seeds its objects through `withSecurityRulesDisabled`, which
  overwrites regardless, and its rules deny all client writes.

  A further failure (`Voice Moment requires exact filename, audio MIME and
  size bounds`, reported as `storage/unknown` rather than a denial) was
  observed once before the fix and is **not explained by leftover state** —
  that object is deleted by the suite itself, and `assertFails` rejects any
  non-permission error, so a transient transport/emulator error surfaces as a
  failure. It did not reproduce in 55 targeted attempts of that exact oversize
  upload (25 sequential, 30 at 6-way concurrency, all clean
  `storage/unauthorized`) nor in any full run. Treat a lone `storage/unknown`
  as transient and re-run; if it becomes frequent, suspect emulator contention
  (e.g. another suite sharing the hub) rather than a rule.

- **Open (2026-08-09): `profile_save_e2e_test.dart`'s "full save
  pipeline" case is FLAKY under full-suite parallelism.** It passes
  reliably in isolation (`flutter test test/profile_save_e2e_test.dart`)
  and passes on most full-suite runs, but failed twice in a row during
  the 2026-08-09 session and then passed again with the identical tree —
  so it is timing/scheduling sensitive, not a real regression, and NOT
  caused by the room-eviction change it appeared alongside (verified by
  running the same tree both ways). Worth stabilizing before it erodes
  trust in a red CI run: the likely culprit is the test's real-async
  Storage/Firestore fakes racing the shared-profile stream assertion.

- **FIXED (2026-08-16, `38b29f7`) — CI was red on three consecutive
  pushes, including a docs-only commit.** `legacy_identity_scrub.test.js`
  asserted an absolute document count (`scanned === 1`) while
  `scrubIdentitySnapshots` scans the whole `conversations` collection and
  takes no uid or prefix scope, so it could not isolate itself the way its
  own `wipe()` isolates its fixtures. `node --test test/*.test.js` runs
  files **concurrently against one emulator**, so a conversation seeded by
  any other file was counted here too, and the assertion held or broke
  purely on interleaving — green locally, red on the runner. 509 of 510
  passed every time, which is what gave it away. Fixed by measuring the
  **delta** around this test's own write: exactly as strong an assertion
  (one document scanned, one scrub planned, nothing written), independent
  of what else exists. **Generalizable rule**: in the Functions suite,
  never assert an absolute count over a collection your file does not
  exclusively own.

## Code quality / consolidation

- **Dead rule code in `firestore.rules`, left over from the `952d8e4`
  eviction removal — and it reads as though a capability exists that does
  not.** `roomParticipantLeaveRootExists()` has no callers, and
  `roomParticipantLeaveTransitionAllowed()` is unreachable because
  `participants` delete is `if false`. Flagged 2026-08-17, deliberately
  not removed in a security commit. **The hazard is the reading, not the
  bytes**: the ternary that calls the second helper looks like members can
  leave a voice room through rules, and they cannot — so anyone reasoning
  about the leave path from these lines reasons about a path that is off.
  Remove them in a change of their own, with the emulator suite re-run.

- **`_publishRecordedMomentLegacy` writes a 14-key document where
  `validateMoment()` requires exactly 20.** The callable fails `data-loss`
  on a mismatch, so any moment created through this fallback would break
  every later callable operating on it. Latent only because Stage B is
  deployed and nothing reaches the path today. It needs a deliberate
  decision — delete it, or write the canonical shape — not continued
  coexistence. Tracked as
  [Roadmap 0j](Roadmap.md#0j-decide-the-fate-of-_publishrecordedmomentlegacy).

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
- **RESOLVED IN CURRENT SOURCE 2026-08-28 — two parallel hand-raise APIs no
  longer write two schemas.** Podcast Studio, Participants and the deprecated
  `RoomExperienceService` compatibility methods all read/write
  `rooms/{roomId}/participants/{uid}.isHandRaised`. The separate
  `handRequests` Rules contract remains temporarily readable/writable only so
  an already-installed older client is not broken without a minimum-version
  migration; current source neither creates nor watches those documents. See
  ADR-120.
- **RESOLVED IN CURRENT SOURCE 2026-08-29 — normal product journeys now use
  the semantic theme system.** Remaining inline dark colour systems belong to
  documented immersive voice/media surfaces or specialized workbenches; new
  brightness-dependent UI must use `AppPalette`/`ColorScheme` (ADR-127).
- **CORRECTED 2026-08-16 — this entry said "Cloud Functions still have
  zero automated test coverage."** That was false, and had been for some
  time: `functions/test/` holds **510 tests across 82 suites** in 45
  files, running against the Auth + Firestore emulators and gating the
  Hosting release in CI. Current counts live in one place now —
  [TESTING.md](TESTING.md#current-counts) — so this file should
  reference them rather than restate them.

  What remains true, and is the useful part of the original entry:
  coverage is uneven, not absent. Many older functions have no focused
  tests. **No suite anywhere proves anything about production** — they all
  run against emulators or fakes, and the emulator does not require
  composite indexes, which is precisely how a broken `expirePremiumIdentity`
  survived 510 green tests for the entire life of the Premium feature.
  Broad cross-service integration and real store billing still have no
  executable path. A green suite is strong evidence for the cases it
  names, not blanket proof for every feature — and never evidence about
  what is deployed.

## Infrastructure

- **RESOLVED 2026-08-20 — `firestore.indexes.json` had drifted BEHIND
  production: the deployed `clubs.clubId` single-field exemption was never
  backported, so the next index deploy would have deleted it and bricked
  club deletion.** `adminDeleteClub` sweeps the `users/{uid}/clubs`
  projections with `db.collectionGroup("clubs").where("clubId", "==",
  clubId)` (`functions/admin/clubs.js:1005`), which requires a
  COLLECTION_GROUP-scope exemption on `clubs.clubId`. The repo file listed
  overrides for `rooms.roomId`, `participants.userId`, `roomMembers.userId`
  and `invites.inviteeId` but not this one; production (checked via
  `firebase firestore:indexes`, 2026-08-20) already HAS it — evidently
  console-created and never committed. Club deletion therefore works today,
  but `firebase deploy --only firestore:indexes` offers to delete live
  indexes the file omits (`--force` deletes silently), after which the
  sweep's `.get()` would throw `FAILED_PRECONDITION` after
  `deletionInProgress: true` is set — a retryable state no retry could ever
  complete. Exemption backported; the full live config was diffed against
  the file and now matches exactly. The emulator does not enforce
  single-field exemptions, so no test could see any of this. See
  [ADR-096](Decisions.md#adr-096-firestoreindexesjson-mirrors-the-deployed-index-state-exactly--a-console-created-exemption-is-backported-to-the-repo-the-day-it-is-found).
- **OPEN — App Store/Google Play Premium checkout is not operational.** The
  entitlement model, admin grant and access gates exist, but no IAP client or
  store receipt-verification adapter is configured; `verifyPurchase`
  deliberately declines rather than trusting the device. Only the guarded
  protected-owner-only `adminSetPremiumEntitlements` callable can grant working
  Premium today. See
  [Roadmap.md](Roadmap.md#0e-premium-billing-adapters).
- **RESOLVED 2026-08-16 — `app.yovoice.app` is LIVE.** This entry said
  "DNS record not added yet … needs Cloudflare access only the domain
  owner has" and had been stale. The CNAME resolves to
  `yovoice-ec54a.web.app` and HTTPS returns 200; the Flutter web client
  was fetched from that host and fingerprinted (5,139,256 bytes,
  containing `publicProfiles`, `searchPublicProfiles`,
  `selectMyAchievementTitle`).

  **Remaining, and UNVERIFIED**: `NEXT_PUBLIC_APP_URL` must be flipped to
  `https://app.yovoice.app` in all three of the website repo's Vercel
  environments (production, preview, development) and the redirect
  verified end-to-end. That lives in the other repo and could not be
  checked from here — assume the website still points at the default
  `web.app` domain until someone confirms otherwise.
- **FIXED AND DEPLOYED 2026-08-16 — Premium never expired for anyone.**
  The deployed scheduled `expirePremiumIdentity` sweep queries
  `entitlements where isPremium == true and currentPeriodEnd < now`
  (`functions/premium/entitlements.js:163`), which requires a composite
  index on `entitlements(isPremium, currentPeriodEnd)`. The index was
  committed but had never been deployed, so every run threw
  `FAILED_PRECONDITION` and expired entitlements were never revoked. The
  function looked healthy in `functions:list` and the Functions suite was
  green throughout, because the emulator does not require composite
  indexes — the failure existed only in the scheduler logs. Index deployed
  2026-08-16. **UNVERIFIED**: no successful run has yet been observed in
  Console → Functions → Logs; check that before calling Premium expiry
  proven.
- **OPEN, deliberate — `publishPublicStatsSchedule` is committed
  (`cb4651a`) but NOT deployed.** Three preconditions first: `publicStats/live`
  needs the project's first `allow read: if true` rule (with its own ADR and
  emulator coverage), the live count needs a `COLLECTION_GROUP` index on
  `rooms.expiresAt`, and the data source is known to be wrong —
  `activeVoiceSessions.expiresAt` is a token-issuance TTL that is never
  renewed and never cleaned up on a crash, so counting by freshness
  reports zero for a full room while counting without it reports ghosts
  forever. Do not sweep it into a blanket `--only functions` deploy. See
  [DEPLOYMENT.md](DEPLOYMENT.md#deliberately-held-back-publishpublicstatsschedule).
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
- **PARTIALLY RELEASED 2026-08-27 — password reset / email verification links still
  dump production users on Firebase's generic white `__/auth/action` page.**
  Not a bug in
  ActionCodeSettings — its `url` only ever becomes the post-action
  continueUrl (established empirically in a prior session). The user-facing
  handler simply didn't exist for reset (`/reset-password` on the website
  was an empty directory) and the console's action URL was never
  customized. Source now provides a tested `yovoice.app/auth/action`
  dispatcher → branded `/reset-password`, `/verify-email`, `/recover-email`
  and `/revert-second-factor` pages; full reset
  lifecycle verified against the Firebase Auth emulator (old password
  rejected, new accepted, code replay rejected, reused link shows a
  branded error, hostile continueUrl stripped by allowlist). Token routes are
  private/no-store, no-referrer and noindex; the MFA recovery path validates
  the exact operation and requires a deliberate click so a mail scanner cannot
  remove an authenticator. Website commit `ce11602` is live and all five token
  routes pass production probes. The narrow Identity Toolkit callback/template
  request was rejected with HTTP 400 `EMAIL_TEMPLATE_UPDATE_NOT_ALLOWED`, and
  immediate read-back confirmed no targeted field changed; production
  `callbackUri` therefore remains the Firebase handler. Do not broaden the
  update mask. The retained leaf scope, read-back and rollback gates are
  documented in docs/email-templates/README.md. See ADR-022.
- **Fixed: login's "Forgot password?" required the login form's email and
  only answered with a SnackBar.** It now opens a dedicated responsive
  reset-password route with its own email form, then a neutral "Check your
  inbox" result. `user-not-found` deliberately takes the same path as success
  so the form cannot probe which emails have accounts.
- **Fixed: user-facing copy wrote the brand as "YoVoice" in ~30 strings**
  (share messages, fallback display names, settings copy). All user-facing
  occurrences are now "YO Voice"; code identifiers (`YoVoiceApp`) and
  URLs/package ids unchanged.
- **Fixed (fourth and final clobber writer): registration merged
  `photoUrl: null` into `users/{uid}`.**
  `FirestoreService.createUserProfile()` — called from email/password
  registration and first-time Google sign-in — wrote the avatar field as
  a literal null with merge:true. Mostly invisible at account creation,
  but it made the field's ownership ambiguous and could null a Google
  avatar seeded in the same sign-in flow. It no longer touches photoUrl
  (regression-pinned in test/profile_photo_source_of_truth_test.dart);
  its dead updatePhotoUrl/updateDisplayName siblings were deleted.
- **Fixed: other people finally see profile changes.** New Cloud
  Function `onProfileIdentityChanged` fans photoUrl/displayName changes
  out to conversations, club member docs and voice_moments (see
  ADR-023). NOT yet deployed — requires `firebase deploy --only
  functions`, and until then other users' Chats lists keep showing the
  avatar from when the conversation was created.
- **Fixed: Edit profile was enormous on desktop.** The screen was an
  unconstrained full-width ListView, so its AspectRatio(16:9) banner
  preview scaled with the window — ~810px tall at 1440px wide. The form
  is now centered and capped at 640px (preview ≤ ~275px tall at 21:9),
  and the Profile header renders the banner as a centered rounded cover
  card above 900px instead of a full-bleed stretch. Verified visually
  via lib/dev/profile_preview.dart at 390 and 1024/1440-class widths;
  mobile keeps the previous full-bleed composition.
- **Fixed: broken image URLs were indistinguishable from "no image".**
  CircleAvatar(backgroundImage:) and DecorationImage swallow load errors
  silently. Shared UserAvatar/ProfileBanner widgets now render explicit
  fallbacks (initials / brand gradient) via errorBuilder, and replaced
  Storage objects are cleaned up after a successful save instead of
  orphaning forever.
- **Fixed (regression from 82c1746, mine): Profile avatar clipped at the
  top of the page on mobile.** The header refactor returned the inner
  Stack (title row + identity row) as a NON-positioned child of the
  header's outer Stack on <900px widths. A non-positioned Stack child
  sizes to its own children, so the inner Stack collapsed to the title
  row's height and the identity row's `bottom: 20` anchored to that
  collapsed ~70px box at the top — avatar drawn above the viewport, name
  at the top, dead space below. The width-matrix test written for the fix
  then caught the SAME collapse on ≥900px widths (avatar 76px above the
  header): ConstrainedBox capped width but left height loose. Both
  branches now wrap the content in Positioned.fill (+SizedBox.expand on
  the wide branch). The header was also extracted to a public
  ProfileHeader widget rendered by the screen, the dev harness AND
  test/profile_header_layout_test.dart (8 sizes: 320/375/390/393/430/
  768/1024/1440 — avatar-fully-inside asserted at each), because the
  regression shipped precisely while the harness mirrored the layout
  instead of importing it.
- **Proven end to end (not merely reviewed): the profile media save
  pipeline.** test/profile_save_e2e_test.dart drives the real
  EditProfileScreen with generated "YO TEST AVATAR"/"YO TEST BANNER"
  images through real pick→validate→pending→Save code against
  firebase_storage_mocks/fake_cloud_firestore, and asserts: Storage
  object exists at users/{uid}/profile/<kind>_<ts>.png with byte-exact
  content; Firestore photoUrl/bannerUrl/bio updated; Auth photoURL
  mirrored; the shared watchCurrentProfile stream emits the new values;
  replacement mints a new URL and deletes the old object; an oversized
  file is rejected with the product's exact copy. Structured [PROFILE]
  stage logging (deliberately present in release web) traces
  SELECTED→VALIDATED→UPLOAD_STARTED/COMPLETE→URL_RECEIVED→
  FIRESTORE_UPDATE→STATE_REFRESHED in the browser console for field
  debugging.
- **Fixed: silent no-op Save.** Edit profile's Save returned without ANY
  feedback when form validation failed — indistinguishable from success.
  It now says so, and a real success ("Profile saved.") is announced only
  after every stage completes.
- **Fixed and deployed 2026-08-27: direct Voice call button in chat did
  nothing.** This was not a tap-target bug: the product had no 1:1 signaling
  subsystem. Friends can now start a server-authoritative call from a DM,
  receive an immediate ringing surface, accept/decline/cancel/end it, mute
  locally and reconnect through a short-lived LiveKit token. Per-user locks prevent overlapping calls; block,
  restriction, account and bilateral-friendship state are rechecked before
  answer and token minting. A 60-second timeout becomes a useful missed-call
  notification that returns to the conversation. See ADR-117.
- **Fixed: reciprocal friend requests could invalidate their Firestore
  transaction under contention.** The request path opened two transaction
  query streams concurrently; the emulator repeatedly closed one while two
  users requested each other at the same moment. The bounded quota reads are
  now ordered, preserving the same caps while the reciprocal-request
  convergence test and the full Functions suite remain stable.
- **Fixed (THE root cause of "saved but no avatar/banner", found with
  production evidence): the default Storage bucket had no CORS
  configuration.** Full diagnostic chain: fan-out logs proved Firestore
  photoUrl updates on Save (uid + object path captured); the stored
  objects fetched publicly as valid images (curl 200, correct
  content-type, real photo bytes); THEN the in-browser test from the
  app's own origin showed the asymmetry — fetching a MISSING object
  returned a clean JSON 404 (the Storage API front-end adds
  Access-Control-Allow-Origin to error responses), while fetching the
  REAL object threw `TypeError: Failed to fetch`, because successful
  alt=media downloads are served with the BUCKET's CORS config, which
  was empty. Browsers therefore blocked every real image byte; the
  errorBuilder fallbacks rendered initials/gradient, indistinguishable
  from "no image set". This also explains why NO Storage-hosted image
  (avatars, banners, club avatars, room images) has ever rendered in
  the web app, and why the earlier CORS probe — run against an error
  response — was misleading. Fix: bucket CORS set to allow GET/HEAD
  from any origin (media on this bucket is public-read by rules design
  anyway) via a one-shot admin function, executed once and deleted;
  functions/admin/apply-storage-cors.js is kept unexported as the
  documented reapply path. Verified after: the same fetch+decode from
  the app origin succeeds (200, 1024x1819, 352,362 bytes) with
  access-control-allow-origin present on the real object. No client
  change was needed — stored URLs were always correct.
- **Known minor issue: replaced profile images may not be cleaned up.**
  The user's superseded avatar (avatar_1786204059179.png) was still
  fetchable after being replaced — `_deleteReplacedImage`'s best-effort
  delete is failing silently, most likely refFromURL vs the
  `.firebasestorage.app` bucket URL format. Cosmetic storage cost only;
  needs a debugPrint in the catch and a look at refFromURL handling.
- **Fixed: mobile Home's "Create Room" empty state opened the Moment
  recorder.** `MobileHome` had no `onCreateRoom` callback, so
  `HomeActiveRooms`'s empty-state button was wired to `onCreateMoment`.
  Starting a room and recording a Moment are different flows; the shell
  now passes `_openCreateRoom`.
- **Not a bug: the "DesktopHome renders one banner of two" report.** The
  stream and `rankRoomsForHome` were always correct — instrumentation
  showed `board=[r1, r2]` and two `HomeRoomBanner` widgets in the tree.
  The failing test simply never set a viewport, so the 800x600 default
  clipped the second banner out of the lazily-built `ListView` and the
  finder saw one. Every other test in that file called `useDesktop`;
  that one did not. Fixed by giving it a viewport, not by changing
  production code.
- **Fixed: room identity snapshots trusted the Firebase Auth display name.**
  Broadcast `handRequests` and Family `checkIns` pinned the uid but accepted a
  client-supplied `displayName`, while the app sourced that value from the Auth
  mirror. A stale mirror could regress a recent canonical rename and a modified
  client could forge any label. Both services now read `users/{uid}` and both
  create rules require byte-for-byte equality with its `displayName`, exact
  schemas and server-time timestamps; focused Flutter tests and Rules emulator
  cases cover canonical, stale, forged and missing-profile paths.
- **PARTIALLY DEPLOYED 2026-08-28 — revised Stripe Premium catalog is live,
  but provider rollout and checkout remain disabled.** The secret-free
  production callable now returns the truthful catalog with checkout and
  Portal unavailable; no Stripe mutation handler was deployed. ADR-118
  replaces ADR-067's old PLN
  19.99/199.99 recurring catalog with card/PayPal at EUR 6 monthly or EUR 60
  annually, plus non-renewing BLIK at PLN 26/30 days or PLN 260/365 days. The
  source owns hosted Checkout/Portal, signed webhook authority, idempotent
  billing-to-entitlement projection and production live/test separation. No
  live Product/Prices, PayPal/BLIK activation, secrets, webhook, Portal or
  four-method production smoke is recorded here, so source readiness must not
  be presented as a working purchase path. Launch also remains blocked on
  approved seller/business, applicable tax, B2B and customer-facing
  refund/dispute handling. Do not publish legal, tax or refund claims until
  those decisions exist, and never use Stripe test mode in production
  `yovoice-ec54a`.
- **Fixed in source — Google Sign-In on Flutter Web returned Google error 400
  `redirect_uri_mismatch`.** The deployed bundle used
  `auth.yovoice.app/__/auth/handler`, but that redirect was not registered on
  the Google OAuth client. Flutter Web now uses Firebase's registered
  `yovoice-ec54a.firebaseapp.com` Auth handler. The Android Firebase app also
  has both debug and release/upload SHA-1 and SHA-256 fingerprints, and the
  checked-in SDK config contains the release OAuth client. The registered
  Firebase handler is now live; each auth release still requires a real popup
  smoke rather than relying on static configuration alone.
- **Fixed and deployed to web/Android internal build 6 — Google/Apple authentication could succeed and
  then return the user to Login, while Registration did not expose either
  provider.** Firebase publishes the authenticated user before the provider
  future completes; if concurrent first-profile provisioning then failed, the
  old rollback signed out a valid provider session. Provider names outside the
  Firestore 2–120 UTF-16-unit contract could fail the same boundary. Federated
  auth now preserves the Firebase Auth session, normalizes provider identity
  without splitting graphemes, aborts an in-flight cross-account bootstrap,
  and blocks `MainShell` behind bounded, idempotent profile-bootstrap retries
  with an explicit retry/sign-out state. Registration reuses the Google/Apple
  actions from Login, transient Apple availability failures can be retried,
  and iOS declares `GIDClientID`. Automated tests/config checks are not a real
  provider login: new-account and returning-account smokes on production web
  and store-installed builds remain release evidence. The signed iOS build 7
  artifact passed entitlement/configuration inspection and App Store Connect
  accepted it for TestFlight processing; tester-group availability and a
  real-account smoke remain pending. Android build 7 remains active on
  Internal Testing; testers must opt in with an address registered as a Google
  account rather than searching for the still-draft app in Play Store.
- **Fixed in source and provider configuration — Sign in with Apple was a
  placeholder.** Apple App ID `app.yovoice` now has the capability, Service ID
  `app.yovoice.web` owns the three verified web domains and Firebase callback,
  a dedicated Sign in with Apple key configures the enabled Firebase
  `apple.com` provider, and the regenerated `YO Voice App Store` profile
  carries the entitlement. The client has a real Firebase Apple flow, shared
  profile provisioning and a runtime provider probe. Every configured shipped
  target enables Apple by default; an explicitly disabled build still fails
  closed. Deployment and real-account web/Android/iOS smoke tests remain the
  release evidence, not the existence of source code.
- **Fixed in source — Profile visibility was a disabled placeholder.** The
  reusable Settings surface now persists `public`/`friends`/`private` through a
  server-authoritative callable. Rules, search and website publication enforce
  it; invalid state fails closed. A backend-only generation also closes the race
  where a scheduled showcase build could otherwise reinsert a profile just
  after it became private. Source and production still differ until Functions,
  Rules and clients are deliberately deployed.
- **Fixed in source, not deployed — “Who can message you” was a disabled
  placeholder with no delivery policy.** A recipient now selects Everyone,
  People you follow, Friends only, or Nobody. The server rechecks the setting
  on canonical conversation open, every text send, media reservation, and
  media finalization; existing threads and a pre-change upload reservation are
  not bypasses. Firestore Rules also protect the legacy direct-write path.
  Directional-follow, one-sided-friendship, malformed-value, existing-thread,
  and preference-change-during-upload attacks are covered by the Functions and
  Rules emulator suites; responsive Flutter widget/service tests cover 320 px
  and desktop widths.
- **Fixed in source — mobile Staff Center left too little room for its
  content.** The pushed Staff Center kept both a seven-item horizontal section
  strip and the application dock visible while every section scrolled inside
  the remaining viewport. The section strip now collapses when content moves
  toward the bottom and returns when the user scrolls back; an always-visible
  app-bar menu keeps every capability-gated section reachable. Phone headers
  also keep their action beside the title instead of wasting a separate row.
  Geometry and interaction regressions cover 320/390/430 px at 200% text, and
  the real-font screenshot harness includes the scrolled state.
- **Fixed in source 2026-08-28 — direct chats could nag, duplicate alerts,
  strand media and lose call setup.** The visible “Unread counts may not update right now.”
  banner came from background read-receipt bookkeeping, which ran even for the
  sender's own messages and surfaced an unactionable failure inside the chat.
  Read work is now incoming-only, silent, single-flight and paged past the
  server's 100-message boundary. An active conversation suppresses only its
  foreground native alert, app banner and shell overlay; background delivery
  remains enabled. Activity-trigger replay can no longer reset a notification
  to unread or resurrect a deleted row, and each Firestore notification
  generation uses a source-revalidated terminal FCM dispatch claim, platform
  collapse ids and a managed 30-day event-ledger TTL. Text outbox delivery
  remains FIFO per conversation without allowing one failed conversation to
  block another. Photo and voice payloads now survive process restarts in an
  account-scoped, bounded outbox; expired reservations rotate safely even when
  the device clock is wrong, and Retry/Discard cannot race an active finalize.
  Direct-call start persists one account/peer-scoped request id before the
  network write and recovers the canonical call after restart or lost response,
  instead of leaving the callee ringing while the caller cannot open or cancel
  the call. Firestore Rules also enforce the documented
  server-only conversation root, preventing a participant from forging either
  member's unread/read cursor, typing state or last-message summary. See
  ADR-121. Physical two-device background push, APNs/FCM, LiveKit audio and
  weak-network media smoke remain release evidence rather than automated-test
  claims.
- **Fixed in source 2026-08-29 — the mobile bottom navigation did not match the
  approved compact floating-dock interaction.** The old private shell widget
  mixed layout, routing and its centre action, used a standalone logo treatment
  and transitioned whole pages vertically. One reusable floating dock now owns
  the five responsive visual slots, one shared animated selection capsule,
  the contained circular YO action, transient More selection, safe-area
  reservation and reduced-motion behavior. `MainShell` remains the sole owner
  of domain tab indexes and keeps its existing lazy page instances; a keyed
  Offstage/TickerMode stack adds the 12 px directional fade-through without
  dropping scroll, form or loaded state. The real centre room/Moment action,
  More transition guard, unread badge and pop-before-action behavior are
  preserved. Widget regressions cover 320 px, 1.3 text scale, gesture inset,
  keyboard inset, rapid retargeting, actionable semantics, active-animation
  disposal, Android system Back, final-row
  visibility and retained page state. A physical iOS/Android visual and haptic
  pass remains release evidence for the next native tester build. The first
  visual pass still painted YO over a complete rounded rectangle, so the
  approved central cradle read as an overlap instead of a deliberate cut-out.
  The shipping surface now uses one tangent notched path for fill, border,
  shadow and child clipping, with the 64/68 px YO control centred inside a
  five-pixel `surfaceSunken` socket. Dark/Pearl real-font renders and
  path-level widget assertions guard the corrected silhouette. The follow-up
  accessibility pass also gives the whole painted ring one circular hitbox,
  orders keyboard focus Home → Chats → YO → Moments → More, paints a visible
  YO focus boundary and switches 160%+ text to a taller two-by-two destination
  layout instead of truncating labels. Firebase Hosting workflow
  `33238217610` deployed the pinned `17b386b` artifact on 2026-08-29; the live
  `main.dart.js` matches that artifact byte-for-byte.
- **Fixed in source 2026-08-29 — iOS silently disabled System/Pearl at the
  native application boundary.** ADR-016 correctly pinned a formerly
  dark-only product to `UIUserInterfaceStyle=Dark`, but that override survived
  the complete Pearl migration and forced iOS to keep reporting Dark even
  when Flutter selected `ThemeMode.system`. The application-wide override is
  removed for build 12. The launch storyboard and native window background
  remain branded dark while device-local preferences load; Flutter then owns
  the live surface and status-bar brightness. A source regression asserts the
  global pin stays absent.
- **Fixed in source 2026-08-29 — profile photos could update in the Chats
  people strip but remain stale in conversation rows and Home.** Direct
  conversations and Voice Moments keep denormalized identity for offline
  rendering. Their profile trigger used the triggering event's `after` image,
  so an older at-least-once Firestore event finishing last could permanently
  restore an obsolete avatar. The fan-out now re-reads the canonical user in
  the same retryable transaction as each bounded target chunk. Chats overlays
  its reactive friend identity immediately, open chat routes watch the
  privacy-safe `publicProfiles` projection through `ProfileService`, and mobile
  Home resolves that same projection for recent-chat cards just like desktop.
  A production-pinned, dry-run-first repair converges already-stale snapshots
  but fails closed for missing/disabled Auth accounts and retired profiles.
  Emulator regressions cover out-of-order delivery, avatar removal, retired
  identities and a conversation-membership race; widget regressions cover the
  Chats row, open route and standard Home card. Coordinated native tester build
  13 remains the physical-device release evidence.
- **FIXED 2026-08-29 — one active direct
  conversation was rejected by every guarded operation after an old profile
  fan-out stringified a `FieldPath` into a literal backtick-wrapped map key.**
  The root still had both real participant photo entries, but the third key
  made the exact-map validator return `data-loss`; text became terminal
  `Not sent` and typing showed an unrelated warning from the same rejection.
  The recipient's installed build was never consulted and was not causal.
  Profile fan-out now rebuilds both exact two-key identity maps atomically,
  preserves validated peer values, removes extras, and is transaction-safe
  when both users update concurrently. Dry-run/apply/idempotency and concurrent
  emulator regressions cover the repair. Typing failures are diagnostic-only,
  and an absent callable no longer attempts the Firestore-root write that
  deployed Rules always deny. A bounded production dry-run found exactly one
  matching conversation; a private `0600` backup was written before a single
  transaction removed the poison key. The post-write scan found zero matching
  records, and the full identity dry-run then reported 48 users, zero affected
  users and zero planned writes. No application, Hosting, Functions or store
  build was published as part of this data repair.
- **Fixed in source 2026-08-31 — a newly created password account could race
  profile bootstrap and permanently receive the email local-part instead of
  the pseudonym selected during registration.** Firebase Auth emits the new
  principal before `updateDisplayName` and `users/{uid}` finish. AuthGate could
  therefore call the legacy/social fallback, write a non-empty guessed name,
  and correctly be prevented by Rules from replacing it later. A UI-only
  Riverpod flag was insufficient because a second browser tab does not share
  process state. The shipped responsive form now drives the local AuthGate
  interlock, while ProfileService independently fails closed for an
  unverified password user with no usable Auth name: it reloads Auth, checks
  the uid, re-reads the profile, and either observes the registration owner's
  exact name or throws a retryable provisioning-pending error without writing
  identity. Three deterministic cross-tab/poison regressions plus the
  disposed-form navigation test pin the boundary. No Rules relaxation or
  arbitrary overwrite path was added.
- **Fixed in source 2026-08-31 — direct video capability and its privacy races
  were missing from the audio-only friend-call path.** Direct calls now carry a
  server-authored immutable media type, mint declared-source-scoped LiveKit
  grants and render remote video plus a local mirrored preview with camera,
  microphone, speaker and camera-flip controls. Screen-share labels are not
  granted, but LiveKit source labels are client-declared and therefore not
  capture-origin proof against a modified client. A session
  epoch prevents a late token/permission result from reconnecting after
  logout, account switch or hang-up; separate microphone and camera epochs
  prevent late capture changes. Teardown retains and re-stops the original
  local track objects after delayed SDK work, even when Room publications were
  already removed. Active calls now expire and queue room teardown. The UI
  deliberately makes no E2EE promise: LiveKit/WebRTC transport encryption is
  present, app-level E2EE is not. Native two-device, background-call and
  mixed-client-version testing remain release gates.
- **Fixed in source 2026-08-31 — `?room=` links could join a live room without
  an informed mic boundary.** Room IDs are now bounded to a strict safe
  character set, the destination is fetched before a named confirmation is
  shown, cancellation performs no join, and confirmed external entry connects
  muted until the user explicitly unmutes. Regression coverage pins ID
  validation and muted propagation through both Community and Podcast rooms.
- **Fixed in source 2026-09-01 — auth-stream failures could expose raw backend
  exception text on the session-isolation screen.** Both the in-place
  `StreamProvider` error state and the root-route reset stringified the original
  exception directly into a widget. The route boundary now preserves the typed
  error only for diagnostics and sends it through the shared authentication
  error localizer before rendering. English and Polish widget regressions pin
  the actionable fallback and assert that backend codes, messages and secret-
  shaped test values never reach the UI.
- **Fixed in source 2026-09-03 — shared friends/request streams and profile
  route guards had lifecycle gaps at tab and auth boundaries.** The Friends
  screen retained a fanout after its final listener retired, so a
  Requests→All round trip could leave the friend list permanently closed; the
  request cache reused a non-replaying production Firestore broadcast, so a
  late Requests view could wait forever after its badges consumed the initial
  snapshot. Both reads now use/reacquire ref-counted replay fanouts, validate
  the synchronous Firebase Auth identity at final delivery, and drop queued
  values after retirement. Fatal source/setup errors also evict their dead
  generation so a later view can retry instead of joining a poisoned cache.
  Successful sign-out clears both generations before returning, while a failed
  sign-out leaves the still-authenticated session's streams live. The
  profile-preview single-flight guard now releases on every setup failure, and
  its nullable route result is promoted before dispatch. Injected Auth,
  Firestore and service instances are preserved across Friends, Chat, preview
  and full-profile routes instead of silently switching to the process-wide
  Firebase account. Focused service, auth-cleanup, Friends workflow and preview
  widget regressions cover the failure paths.
- **Fixed in source 2026-09-04 — Build 19 rejected valid iOS direct-message
  videos when picker metadata and immutable ISO-BMFF branding disagreed, or
  when the generic parser omitted a valid QuickTime duration.** The client now
  sniffs the actual selected bytes before reservation. The server permits only
  the narrow MP4/QuickTime video-container equivalence after a generation-bound
  probe. Every ISO-BMFF result is now corroborated against all playable tracks,
  including `audi` and `soun`: movie, track, media, decode, composition and edit
  timelines plus sample counts must agree conservatively. The parser is capped
  at eight tracks, 160 generation-bound reads and 2 MiB of timing bytes;
  fragmented, ambiguous, overflowing or over-budget media fails closed. Track,
  generation, size, kind and duration checks remain strict, and unrelated MIME
  mismatches still fail closed. Direct integrity passes 39/39, the focused probe
  passes 29/29 and the full Functions suite passes 1215/1215.
  The repaired Functions revision is not yet deployed and physical Apple
  camera/library codec smoke remains pending.
- **Fixed in source 2026-09-04 — legitimate pre-cutover friends could not
  start direct calls or fetch friends-only avatars because their canonical
  server-owned guards did not exist.** This was not caused by the recipient
  running an older application build. The call endpoint now returns localized,
  actionable reason codes instead of a generic failure, while the security
  boundary continues to reject client-writable mirrors. A bounded operator-only
  reconciliation can create both guards atomically for independently reviewed
  pairs after exact Auth/profile/mirror/timestamp/block/restriction checks, a
  mandatory dry-run and matching digest. It never scans or auto-promotes old
  rows. Its schema-v2 manifest binds the complete reviewed Firestore timestamp
  as `{seconds, nanoseconds}` (including microsecond differences) into the plan
  digest and writes that exact value to both guards. No production reconciliation
  has been applied yet, so affected
  production pairs remain blocked until the controlled deployment and data
  step are completed.
- **Fixed in source 2026-09-04 — direct-call capability detection and
  multi-device UI could reject a valid no-push recipient, auto-open media on a
  second device, lose a terminal disconnect during a pending `Answer`, or let
  passive-route dismissal end the call on the answering device.** FCM token
  inventory is no longer a video-capability authority. The caller offers v1;
  the installation performing `Answer` retains video only when it explicitly
  acknowledges v1, otherwise the call atomically downgrades to audio. New
  clients use call-scoped SHA-256 installation bindings, never a raw stored
  identifier, while legacy audio remains compatible. Other devices require an
  explicit continue gesture and cannot auto-join; disconnect exposes Retry;
  Close/system back only dismiss a passive route. Focused Flutter is 45/45,
  direct-call emulator is 44/44, complete Flutter is 2161/2161 and complete
  Functions is 1215/1215. Physical mixed-version two-device verification is
  still pending.
- **Fixed in the final unreleased 2026-09-04 source candidate — DM media could
  mishandle a lost acknowledgement or orphan private payload bytes during local
  cleanup.** Production-shaped authoritative reservation expiry/change errors
  now rotate reservation and `messageId` before generic ambiguity handling;
  ambiguous transport results retain the durable retry identity. Canonical
  reconciliation requires the exact sender, conversation, `messageId` and
  media type. Completion deletes payload before manifest removal, so deletion
  failure remains queued across retry/restart; wrong sender, type or
  conversation never suppresses the failed item or cleans its bytes, and
  concurrent delivery/reconciliation converges once. The focused aggregate is
  68/68 and independent cleanup re-review is 41/41 with no P0/P1/P2 finding.
  This is source evidence only; physical/deployed success is not claimed.
- **Fixed in the final unreleased 2026-09-04 source candidate — private avatars
  could outlive a grant boundary in mounted/cache state and repeated profile
  taps could queue duplicate routes.** Expiring/auth-bound profile media now
  clears both the mounted provider and Flutter `ImageCache`, with grants kept in
  a 256-entry LRU. Mutual-friend rows render through `UserAvatar` and the current
  viewer grant; preview, full-profile and social-stat routes are single-flight.
  Avatar/profile review passes 91/91 with no P0/P1. One non-blocking P2 remains:
  the target epoch map may grow in an exceptionally long session with many
  unique evictions, but is cleared globally/on logout and is not a privacy or
  correctness blocker. The complete final candidate is Flutter 2192/2192,
  analysis-clean and formatted across 615 Dart files with zero changes; it has
  not been deployed or physically accepted.

## OPEN — two Home "Tu i teraz" defects found by independent QA (2026-09-12)

Found by the Senior QA Automation Engineer reviewing the Home redesign
independently of the four implementation slices. Both are in uncommitted
source, both have a red regression test in the tree that goes green when the
fix lands, and neither is a security or data issue. Evidence and exact
commands: `/Users/kamil/Documents/GitHub/yovoice-evidence/2026-09-12/home-qa.md`.

- **A failed live-rooms read takes the create-room pill off the phone Home.**
  `lib/features/home/presentation/widgets/mobile/mobile_home.dart:707` renders
  `HomeQuickActions` only when a featured room exists, so a `permission-denied`
  or offline `watchLivePublicRooms()` — and the cold-start loading frame —
  leaves "Stwórz pokój" and "Znajomi" off the screen entirely. The empty state
  is unaffected (the invitation card embeds the actions). Three consequences:
  the desktop composition already does the opposite and explains why
  (`desktop_home.dart:687`, "a failed room read must not also cost the reader
  the way to start a room of their own"), so the two Homes disagree about one
  state; `home-quick-create-room` is the guided tour's mobile Create anchor
  (`main_shell.dart:434`, `:878-887`), so that step falls back to a centred
  tooltip pointing at a control that is not on screen; and the pre-redesign
  Home did render them in both states (`if (!roomsEmpty)`). One-line fix:
  mirror the desktop condition. Red test:
  `test/home_independent_qa_states_test.dart`, "live rooms denied: the
  create-room pill survives the denial".
- **The phone tells a screen reader "0 osób" about a place the listener
  belongs to.** `home_places_section.dart:484-490` always puts
  `copy.peopleCount(club.memberCount)` in the place tile's spoken label, so a
  club whose counter was never written announces zero members. The desktop
  list refuses exactly this ("a count only where a count actually exists",
  `home_places_card.dart:22-26`, `:134-137`). Fix: the same
  `memberCount > 0` guard, dropping the clause when there is no count. Red
  test: `test/home_independent_qa_states_test.dart`, "a place whose member
  counter was never written says nothing about its size — on the phone too".

Separately, and not a product defect: `test/home_rhythm_test.dart` ("desktop
Home reports the same steps at the expanded scale") is RED in the working tree
because the Wide slice gave the 300 px context column the compact heading ramp
(`desktop_home.dart:771-773`) without updating that older blanket assertion.
Two tests in the tree now contradict each other; the owner decides which
behaviour is correct before the gate can be called clean.

## FIXED — three servers-shell defects the round-2 release gate blocked on (2026-09-12)

All three were found by the Principal Code and Release Reviewer's second pass
over the servers shell and are fixed in the working tree, each with a test that
was RED before the fix and is GREEN after it. Evidence, with the pre-fix
failure output and real timings:
`/Users/kamil/Documents/GitHub/yovoice-evidence/2026-09-12/servers-gate-closure.md`.

- **A joined server conversation survived a rail or dock switch with the
  microphone still open (P1, privacy/lifecycle — the gate's B3 / F-1).** The
  client half shipped in the previous pass: `ServersScreen` and
  `ServerWorkspaceScreen` take a `ValueListenable<bool> isVisible` and leave
  the conversation when it goes false. The HOST half did not exist. The shell
  keeps its built content slots alive inside an `IndexedStack`, so selecting
  Home or Chats hid the Servers slot — and with it the conversation dock —
  while the slot stayed mounted, the microphone stayed open, the Android
  keep-alive service kept running, and nothing anywhere said a conversation
  was live (the legacy rooms path has `ActiveRoomMiniPlayer`; a server session
  has nothing). Fix: `main_shell.dart` now owns a `_serversVisible` notifier
  beside `_momentsVisible`, sets it in `_onDestinationSelected` (the only
  place `_selectedIndex` changes, so no rail item, dock cell, More entry,
  mobile Back or responsive reset can bypass it), disposes it, and threads it
  to the slot through a new `serversVisible:` argument on
  `moreDestinationScreen`. `TickerMode.of(context)` was explicitly rejected as
  the signal: `Overlay` builds every entry below the topmost opaque one with
  `tickerEnabled: false`, so any full-screen route pushed over the shell — a
  profile, Settings, a moment detail — would have ended a conversation the
  person never left. Tests: `test/server_shell_visibility_test.dart` and the
  new slot-seam case in `test/main_shell_servers_slot_test.dart`.
- **An inline-hosted server workspace had no way out of its error, loading or
  "server unavailable" states (P2 — the gate's F-2).** The panel's `Serwery`
  control and the phone header's Back both live inside the workspace body,
  which those three states replace; hosted inline over the directory there is
  no app bar and no rail affordance that clears the screen's own
  `_inlineServerId`, and switching the rail away and back rebuilt the same
  retained state with the same server still open. A deleted server, a revoked
  membership or a root read that errored or never answered therefore made the
  directory unreachable for the rest of the app session. (Pre-existing above
  768 px; the B2 fix removed the accidental escape that narrowing the window
  used to provide.) Fix: `server_workspace_screen.dart` wraps every
  pre-workspace state in a back row (`server-state-back`), drawn only when
  `onBack` is present, so a pushed route still has exactly one Back.
- **The podcast recording marker dropped its `Wkrótce` at 1100 x 200 % in both
  themes (P3 — the gate's F-3).** It rendered as `Nagrywanie audycji ·` — a
  dangling middle dot, no `Wkrótce`, not even an ellipsis — so the marker that
  exists to say a feature is unavailable read as a live one. Mechanism:
  `Chip` takes its label's intrinsic width and keeps a box sized for one line,
  so the two-line label was laid out inside a one-line box and its second line
  was painted outside it and clipped. Fix: the marker is now the slice's own
  pill (a `Container` whose label wraps and is never truncated), keyed
  `server-podcast-recording-pill`. Pinned by a test that checks the label's
  rendered rectangle against the pill's at exactly 1100 x 200 %, in both
  themes.

Also hardened in the same pass, from the gate's F-5: a microphone or
headphones press the provider refuses is no longer swallowed. Those two
controls stay reachable through a reconnect on purpose, and the production
link really does raise there — the rejected future escaped into the zone and
the control reverted in silence, which is the "looks live, does nothing" shape
the contract forbids. `ServerSessionController` now stores the failure
(`privacyError`) the way it already stores `screenShareError`, and the
conversation dock renders it in place of the phase line, inside its existing
`liveRegion`, until the next press or leaving clears it.

Still OPEN from the same gate, and NOT fixed here:

- **B6, the device audio lifecycle, is code-complete but device-unverified.**
  It needs two-device evidence or the owner's written acceptance as a named
  limitation; it cannot be closed from a widget test.
- **F-4, board 02's community phone at 320 x 568 / 1x**, where the `Wkrótce`
  chip and `Udostępnij` are cut by the details pane's bottom edge. The
  mechanism is now understood — `ServerScrollingDetails` fades only its last
  14 %, which is shorter than a 48-px control, so the cut reads hard rather
  than faded, and the pair is reachable by scrolling — but every candidate fix
  either changes board 02's phone anatomy or changes how two boards look, and
  neither can be judged without rendered frames. It stays the owner call the
  gate already called it.

## OPEN — App Check token delivery is broken on Android, and unproven everywhere else (2026-09-18)

Found while reading production logs for the profile avatar/banner pipeline:
**every** `getProfileMediaAccess` call from the Android client logs an App
Check rejection. It is harmless today — `enforceAppCheck: false`
(`functions/profile/media_runtime.js:68` and `:76`) is exactly the control
that keeps it harmless, and it must stay false — but it means the App Check
integration is not actually working, and the log noise had been reading as
routine rather than as a broken client. Documentation status: **open → fixed**
for the *documentation* defect (three documents implied client token delivery
was working and that only a waiting period stood between the project and
enforcement); `polish/build-33 (pending)`. The **App Check gap itself stays
OPEN** and is now a named blocker on
[Roadmap item 2](Roadmap.md#2-firebase-app-check-enforcement).

### What was measured

Production logs, project `yovoice-ec54a`, service `getprofilemediaaccess`,
window `2026-09-18T20:30:00Z` – `2026-09-18T21:15:00Z`:

- **662 requests**, split by user agent: **360 `okhttp/4.12.0`** (Android, all
  `POST` → 200), **298 `app.yovoice/2.0.0 iPhone/…`** (240 on `hw/iPhone18_1`,
  of which one returned 404, and 58 on `hw/iPhone14_2`), and **2 `POST` + 2
  `OPTIONS`** from desktop Safari (web).
- **360 `Failed to validate AppCheck token. FirebaseAppCheckError: Decoding
  App Check token failed.`**, followed by **359 `Allowing request with invalid
  AppCheck token because enforcement is disabled`** — exactly the Android
  request count. Not "most Android calls": **all** of them.
- Across every Cloud Run service in that window, only three logged App Check
  messages at all: `getprofilemediaaccess` (719 lines),
  `getmystaffcapabilities` (2) and `getmutualfriends` (2). The volume is a
  property of which function the client calls most, not of that function.

Client side, Redmi Note 8 Pro (`6tq4g6f6ijrwxwzx`), `app.yovoice`
`versionCode=31`, `versionName=2.0.0`,
`installerPackageName=com.android.vending` (a real Play-distributed release
build, so `AndroidPlayIntegrityProvider` is the active provider), logcat from
the running app (pid 24601):

```
W FirebaseContextProvider: Error getting App Check token. Error: wo0: Too many attempts.
```

repeating every ~13–18 s, continuously, across the sampled window (device
clock `02:24:06`–`02:31:02`). The exchange fails on the device *before* a
token is ever produced; the SDK then backs off, and firebase-functions
receives an undecodable placeholder rather than a JWT. A re-capture ten
minutes later produced no lines at all — consistent with the backoff the
message itself names, and a reminder that an empty logcat here is not a
recovered client. `playintegrity.googleapis.com` is
**not enabled** on `yovoice-ec54a` (58 services were enabled when checked;
none of them was Play Integrity, App Attest or DeviceCheck —
`firebaseappcheck.googleapis.com` alone is on), which is a sufficient
explanation for a Play Integrity exchange that never succeeds.

### What it costs today: nothing user-facing, measured

Worth stating plainly, because "App Check rejection" reads alarming in a log:
**no avatar or banner fails because of this.** `firebase-functions` treats an
invalid token as `INVALID`, and with `enforceAppCheck: false` that path warns
and continues — the grant is still issued. Nor does the failed validation cost
server time: over the same window the request latency on
`getprofilemediaaccess` was p50 111 ms / p90 1300 ms for the 360 Android calls
against p50 229 ms / p90 1537 ms for the 298 iOS calls, so the platform that
fails App Check is, if anything, the faster one. Decoding a malformed token
fails locally and immediately.

What it does cost: a dead security layer, ~360 warning pairs per 45 minutes of
log noise that trains readers to ignore this function's logs, and a client-side
Play Integrity retry loop that ends in `Too many attempts` backoff. Whether
that loop delays the *first* callable of an app session before the backoff
widens is **not measured here** — it would need client-side instrumentation,
not server logs — and is the one open user-impact question this entry does not
close.

### The part that matters most — silence is not health

`firebase-functions`
(`functions/node_modules/firebase-functions/lib/common/providers/https.js`)
warns **only** when a token is present and *invalid*. When the token is
**missing**, `tokenStatus.app === "MISSING"` and with `enforceAppCheck: false`
**nothing is logged at all**. So iOS's and web's clean logs prove nothing:
"delivering valid tokens" and "delivering no tokens" are byte-identical in
Cloud Run logs. Under enforcement the two are also treated alike — `MISSING`
throws `unauthenticated` exactly as `INVALID` does — so a platform that is
quietly sending nothing today goes dark the moment the flag flips. Cloud
Monitoring cannot settle it either: the Monitoring API returns `404
NOT_FOUND` for `firebaseappcheck.googleapis.com/request_count` on this
project. Only **Firebase Console → App Check** separates verified from
unverified requests per platform.

Release **web** is a third case and is not in doubt: `lib/main.dart` activates
no provider at all in a release web build unless
`--dart-define=YOVOICE_WEB_RECAPTCHA_SITE_KEY=…` is supplied, and logs the
line `Web App Check is not configured for this release build.` instead. That
branch is deliberate and correct — it is what keeps a missing key from
crashing startup — but it means web would fail enforcement by construction.

### What was changed here, and what was not

Changed: this entry, the App Check bullet under
[Security](#security), [Roadmap item 2](Roadmap.md#2-firebase-app-check-enforcement)
(dependency → blocker) and the App Check section of
[Firebase.md](Firebase.md#firebase-app-check). **Documentation only.**

Not changed, on purpose: `functions/profile/media_runtime.js`. The two
`enforceAppCheck: false` options are the control that makes this survivable;
turning them on is precisely the thing this entry says not to do. No Functions
source, schema or deploy change was made, and none is needed to stop the
*harm* — there is none today, only noise and a dead security layer.

### Owner / ops action, outside this build's authority

1. Enable `playintegrity.googleapis.com` on `yovoice-ec54a`.
2. Confirm the Play Console app is linked to that Cloud project.
3. Re-read the logs and confirm the `Decoding App Check token failed`
   warnings stop.
4. Read Firebase Console → App Check per platform and confirm iOS and web
   are producing *verified* requests — not merely silent ones — before
   anyone considers flipping enforcement anywhere.

Until step 4 reports real verified traffic on a platform, `enforceAppCheck`
stays `false` for that platform's traffic.

### Known-stale, deliberately left alone

`functions/index.js:555`, `:573` and `:588` each comment that clients "attach
App Check tokens already". Android provably does not, and iOS/web are
unproven. The comments are behaviourally inert — the four flags they
annotate are read through `strictBooleanEnvironment`, `functions/.env` sets
only `YOVOICE_ENFORCE_GIF_APP_CHECK=false` and an unset variable resolves to
`false`, so all four are off — and correcting them is a
Functions-source edit, which was out of scope for this documentation pass.
Worth a one-line correction the next time `functions/` is opened for any
other reason.
