# Build 22 round — tester fixes, availability, Reel engagement — 2026-09-06/07

## Status

**SOURCE COMPLETE AND BACKEND DEPLOYED; NO CLIENT PUBLISHED.** Seventeen
commits from `c3cc9d7d` to `5f78efb6` are on `main` (the three commits before
them in `1bb823c6..HEAD` are the Build 21 release records, which this round
did not change). `firestore.rules` and
every Cloud Function were deployed to `yovoice-ec54a` / `europe-west1` on
2026-09-07 from `591b8840`. **No mobile or web build carrying any of this
work has reached a tester**: the published artifact on both invited channels
is still 1.0.0 (21) from `1bb823c6`. Where this record says an item is
verified, it means static analysis, unit and widget tests, emulator suites and
rendered review captures — plus one iPhone 17 Pro simulator run named
explicitly below. No physical device, no two-device call, no production-traffic
observation.

The round spans ADR-147 through ADR-162, already written in
[Decisions.md](../Decisions.md).

## What the round covered

Four tester rounds reported against Build 21, one product ask, and one
feature that had been half-shipped by the server for weeks.

### Tester-reported defects fixed in source

- **Torn screen switching to Home** (`c3cc9d7d`, ADR-147). The 12 px
  horizontal slide over a still-opaque page was the tear; the transition is
  now a Material fade-through with no offset, and Home keeps its last feed
  page as `initialData` across the one-shot v2 refresh so it no longer blanks
  on every tab return.
- **The More tab lit the wrong dock item** (`c3cc9d7d`). `MoreDestinationHost`
  keeps the More capsule lit while a More destination covers the shell.
- **The Friends chat bubble needed several taps, sometimes never opened**
  (`c3cc9d7d`). Repeat taps were being silently dropped for up to 60 s during
  a cold start. Each row now carries a busy state and
  `openDirectConversation` is bounded to 15 s with timeout copy. The
  underlying cold start is a server matter and is unchanged.
- **Rooms, Reels, Voice Moments, moderation and admin panels loaded slowly**
  (`c3cc9d7d`). One shared cause: every hot-path callable outside five warm
  ones runs at `minInstances: 0` and each cold start loads the whole
  48-module `functions/index.js`. Only the client share was fixed —
  `MomentsFeedView` refreshes in place and keeps content on error, Moderation
  Center resolves staff, role and counts concurrently, Staff Center paints
  from cached capabilities and then confirms. **The server share was not
  done**; see "Not done" below.
- **Mute lagged several seconds** (`c8aa3cad`, ADR-149). `RoomMuteSync`
  releases the control as soon as the local track is off and keeps roster
  writes ordered through a chained tail. Unmute stays server-first by design,
  so its wait is unchanged until `setOwnRoomParticipantMute` is warmed.
- **A call died when both parties minimised the app** (`1c7d6cd5`, ADR-154).
  The app declared no foreground service of any type, so a backgrounded
  process had its microphone silenced and was frozen once cached; with both
  sides minimised, no audio flowed either way and both LiveKit participants
  timed out. A Kotlin `VoiceSessionService` now runs an ongoing
  low-importance notification while a session is connected, typed from the
  session's own rights — microphone when the participant may publish and
  `RECORD_AUDIO` is granted, mediaPlayback for a listener, because asking for
  microphone without the permission is a `SecurityException`. A refused
  foreground start is logged, never fatal. `LiveKitClient.initialize()` moved
  before `runApp` so the iOS audio-session policy is seeded before WebRTC
  builds its audio device module; iOS keeps `UIBackgroundModes: audio` and
  deliberately does not gain `voip`, which would oblige CallKit reporting
  this app does not implement.
- **Home showed one friend instead of all of them** (`f6967a6e`). Both Home
  variants already accepted a `FriendService` and never called it, so the
  only people on screen came from the follow graph — capped at two rows on
  mobile and four on desktop. `HomePeopleStrip` renders the real friends list
  from `watchFriends()`, and renders nothing when there are no friends, when
  the read fails, or when there is no session.
- **A room tile showed the host's initial instead of their avatar**
  (`4985595a`). Discover's cards and the live hero drew `room.hostPhotoUrl`
  with `Image.network`; that field is a legacy snapshot the app deliberately
  stopped dereferencing once profile media became viewer-authorized. Both now
  pass `hostId` to `UserAvatar`.
- **Reel text overlays could not be moved or scaled** (`c8aa3cad`, ADR-149).
  Text and link pills now drag on the preview, and text pinches, via an eager
  `ScaleGestureRecognizer` so the scroll view cannot steal vertical drags.
  Feed rendering is unchanged and the sliders remain.
- **No way to dismiss the keyboard on some composers** (`c8aa3cad`).
  `YoKeyboardDoneBar` above the keyboard on every multiline creation and
  settings form; scroll views dismiss on drag.
- **"Reels lose recordings past a minute"** (`fa07bc6e`, ADR-152). The
  contract limit is `MAX_DURATION_MS = 90 * 1000` and has been 90 s since
  build 19 — it was never 60. What the report was hitting is that the cap was
  invisible and the only path under it was a `RangeSlider` that froze when
  its handles came within a second of each other. There is now a Trim tool
  with handles on the video that scrub the preview through a new
  `scrub`/`beginTrimEdit`/`endTrimEdit` API, handles that clamp to one second
  instead of freezing, and the cap shown. **The cap itself is unchanged.**
- **Missing delete-chat and remove-friend options** (`c8aa3cad`). Remove
  friend is now on the Friends list row via an options button and long-press,
  using the same confirmation and callable as the profile screen; chat rows
  gained Unarchive. **A true per-user "delete chat" was not built** — it needs
  a `users/{uid}/conversationState` written by a new callable.
- **A tester was asked for an invite code.** Not an app defect: TestFlight
  shows that prompt when the Apple ID signed in on the device is not the
  invited address. No change; recorded in Bugs.md so the next report of it is
  recognised rather than re-investigated.

### Features

- **Soft Bells v4 UI sound pack** (`c3cc9d7d` + `509bbcb1`, ADR-148).
  Generated additive bells, RMS-normalised, native notification masters
  replaced, v3 no longer bundled. `509bbcb1` was a CI repair with a real
  point: the Hosting workflow proves the checked-in WAVs are the generator's
  output (`--check`), and the v4 pack had been rendered outside it, so the
  run failed. The v4 design now lives in `tool/generate_ui_sounds.py` as a
  `BellSpec` model and the assets are regenerated from it. **The owner has
  not auditioned the pack.**
- **Thinner avatar rings tied to an availability status** (`c3cc9d7d` +
  `a5f6e90d`, ADR-150). Rings were thinned first (status 1.5/1.1 px, Premium
  frame 1.6 px, softer glow) with palette colours unchanged, because the ring
  test enforces a 3:1 contrast invariant. Then optional
  `users/{uid}.availability` (available / away / busy / invisible),
  owner-written and value-gated in `firestore.rules`, with the
  `socialPresence` projection carrying a masked form — offline whenever the
  account is offline or invisible. `PeopleStatus.fromPresence` is the single
  presence→ring mapping used by the Home strip, Friends rows, the friend
  profile pill, the chat header and the profile preview;
  `AvailabilityChip` and `showAvailabilityPicker` (sheet under 900 px, dialog
  above) sit in the profile name plate, above the More sheet title and in the
  desktop sidebar card.
- **Selectable award decorations** (`fa07bc6e`, ADR-151). A "Your title" hero
  with live preview, Change and Clear; track progress tiles;
  Selected/Unlocked/In progress/Locked sections over the existing category
  filter. The selection colours the account's own avatar ring and name
  through `achievementStyleFor` + `DecoratedUserAvatar` + `IdentityName`,
  contrast-adjusted. Selecting no longer pops the screen and failures are
  surfaced. **Other people see the decoration only after a follow-up server
  projection that has not been built.**
- **Room invites by direct message** (`fa07bc6e`, ADR-153).
  `InviteToRoomPanel` opens from the Community header and roster for any
  participant and from the Broadcast header for the host, and sends a real
  direct message carrying the canonical `https://yovoice.app/?room=<id>` link
  — the broadcast share link had been using an unopenable `/rooms/<id>` form.
  The chat bubble renders that link as a room card that fails closed. Offered
  only for public rooms; an invite grants no access.
- **Friend suggestions** (`ca8e0faf`, ADR-157). "People you may know" on the
  Friends list and inside its empty state, through the card extracted from
  Add Friend so the two surfaces cannot drift. The screen owns the
  quota-limited future (2 calls/minute) and reloads only after a successful
  send.
- **Voice Moments story tiles, comment previews and mentions** (`ca8e0faf`,
  ADR-155/156). One shared `MomentStoryTile` across the feed and both Home
  rails, where the ring means "you have not heard this" everywhere — brand
  gradient while a chain has an unheard link, flat line and dimmed avatar
  once heard, disc down from 66 to 60 pt (56 under 360 pt). One views
  listener per rail; unknown state renders as unheard; heard/unheard is
  spoken in the semantic label. Up to three comments render inline from what
  the view already returns, with "See all {n} comments" into the existing
  thread. The composer suggests the caller's own friends after `@` and
  inserts plain text; on read, a mention resolves per viewer against thread
  participants plus that viewer's friends. **Mentions deliberately do not
  notify** — that needs a server sender.
- **A full emoji picker in every message composer** (`23a3739c`, ADR-159).
  `YoEmojiPicker` is one widget shared by direct chats, club chat and the
  in-room chat sheet: about 840 emoji in the standard categories, search over
  names and keywords, and recents backed by the existing
  `AppPreferencesStore` pattern. It swaps for the system keyboard rather than
  stacking on it, and insertion goes through the caret so the selection
  survives. Before this there was no emoji entry point at all — on desktop
  and web the system keyboard offers nothing. **Arbitrary-emoji reactions are
  unchanged**: `ALLOWED_DIRECT_REACTIONS` and the pinned five-key rules map
  still bound those.
- **Voice Discover rebuilt** (`301eebc4`, ADR-160). The owner's report was
  "wielkie klocki": every entry rendered as a full-width card of identical
  weight, so a screen showed three items and no sense of what was worth
  opening. `moment_discover_tiles.dart` gives density by role — featured in a
  two-column grid, recent in a tight list, the seen-aware story strip above.
  Layout only: the same audience and block rules still decide what reaches
  the list.
- **The Your Moments Voice/Reels switch restyled** (`4985595a`). It was a
  bordered Material `SegmentedButton`, the one switch in the app not using
  the pill language of Reels Discover, the Friends filters and the Awards
  categories. Now a rounded pill track keeping the icons, the
  `yo-moments-format-tabs` key, selected-state semantics and a 40 px minimum
  target.
- **The More panel rebuilt** (`ca8e0faf`, ADR-158). A floating card with
  rounded corners that ends above the dock instead of covering it — the old
  sheet hid the dock including the More control itself. No subtitle, 62 pt
  single-line tiles, hugs its content so it scrolls only when it genuinely
  cannot fit.
- **Reel likes and comments, server-owned, plus a moderation path**
  (`33c5f3e5` + `591b8840`, ADR-161/162). Covered separately below, because
  it is the only part of the round with a live backend and an incomplete
  client.

## Reel engagement and its moderation half

The counts were already on the wire — `getReelViewV2` had been returning
`likeCount`, `commentCount` and `callerLiked` and the client parsed them and
threw them away, so a Reel could not be liked or commented on at all.

`33c5f3e5` adds `setReelLike`, `createReelComment` and `deleteReelComment`.
Each moves the child document and the root counter in a single Admin SDK
transaction, so a counter cannot drift from the rows behind it, and each
carries an idempotency ledger entry and a rate budget. `reels/{id}/likes` and
`reels/{id}/comments` are stated `read, write: if false` rather than left to
the parent match, so nothing is granted by inheritance.

`591b8840` gives the feed ownership of engagement for every card rather than
each card owning its own: a tap applies a ±1 change immediately, the
callable's returned aggregate replaces it verbatim, and a refusal restores
the exact pre-tap values with copy naming which limit was hit. A comment read
landing while a like is in flight adopts only the comment count, so the heart
cannot flicker. One `ReelCommentsView` serves both hosts — a modal sheet
below 1100 px, an inline panel above — so the sheet and the panel cannot
disagree about a count. An unverified account keeps a live control explaining
the email gate instead of a dead button. Three review findings were fixed in
the same change: a wide Pearl footer sitting on the light card margin instead
of the artwork (which made white overlay text invisible), a panel composer
floating mid-panel over dead space, and a like control that replaced its
heart with a spinner while the call was in flight, taking back the optimistic
feedback it existed to give.

User-generated comments were not shipped without somewhere to send them, so
the moderation half landed in the same commit: `createReelCommentReport`
files a report carrying a verbatim snapshot of the reported words — staff
cannot read the comments collection at all, so the snapshot is both the
moderator's only view and the only evidence that survives a removal;
`removeReelComment` gives the Reel's author authority over their own thread
as its own callable with its own ledger kind and budget; `moderateReport`
gains a `reelComment` branch whose audit entry records when the author had
already removed the content. Moderation Center gained the filter, the row,
the quoted-text evidence block and the remove action, with reported text
`Directionality`-isolated rather than stripped.

**What is not there.** The in-app *reporter* control and the author-removal
control do not exist on `main`. `ReelCommentsView` says so in its own doc
comment, and `ReelService` carries no call to either callable. So the
deployed report path has no entry point in the app: a viewer cannot file, a
Reel's author cannot clear someone else's words from their thread, and the
moderator queue can receive nothing from the product. That client half is
written but uncommitted in the working tree
(`lib/features/reels/presentation/widgets/reel_comment_report_sheet.dart` and
`test/reel_comment_moderation_test.dart` untracked; `reel_service.dart`,
`reel_engagement_copy.dart` and `reel_comments_view.dart` modified) and is
not claimed as landed here.

## Deployment

Maintainer-authorized on 2026-09-07. Three client features were otherwise
inert — availability, Reel likes and comments, and Reel comment moderation
all call server code that did not exist in production. Deployed from
`591b8840` with a clean tracked tree, project `yovoice-ec54a`, region
`europe-west1`, in three steps: `firestore:rules`, then the moderation
callables (`moderateReport`, `createReelCommentReport`, `removeReelComment`),
then all remaining functions. **Moderation went out before engagement on
purpose**, so no window exists in which a Reel comment can be created without
a removal path. Indexes needed no deploy —
`status+targetType+createdAt` and `status+targetType+reason+createdAt`
already exist and match the `reelComment` queue query. No Hosting, Storage
rules or index deploy. Full record, including the post-deploy read-back of
the deployed function list, in
[DEPLOYMENT.md](../DEPLOYMENT.md#backend-deploy-for-the-build-22-round--2026-09-07).

## Evidence

Recorded pre-deploy gates at `591b8840`: `flutter analyze --no-pub` clean;
`flutter test` **2768/2768**; `firestore-tests` **534 passed / 0 failed**;
the Functions emulator suite **712 passing with one failure** —
`simultaneous reciprocal requests converge on one friendship` in
`functions/test/social_graph_security.test.js`, a pre-existing timing flake
last touched in build 16, untouched by this work and passing in isolation
(3.4 s against 8.6 s under full-suite contention).

Per-commit evidence as the commits themselves record it: 2532/2534 then ring
theme 6/6 at `c3cc9d7d`; composer 12/12, mute 18/18, friends and messages
64/64, Done bar 3/3, recorder/room/create-room 92/92 at `c8aa3cad`; full
suite 2546/2546 plus functions projection 3/3 and the Firestore emulator
rules suite 525/525 including the new availability check at `a5f6e90d`; full
suite 2592/2592 at `fa07bc6e`; full suite 2602/2602 plus new manifest, plist
and channel tests and an Android debug APK build with the Kotlin service at
`1c7d6cd5`; 68/68 in a clean worktree at `f6967a6e`; 35 tests in a clean
worktree and 457 room and discover tests in the working tree at `4985595a`;
full suite 2659/2659 at `ca8e0faf`.

Visual evidence is **review captures and rendered widget states**, plus one
iPhone 17 Pro simulator run at `fa07bc6e` through the Firebase-free
`lib/dev/tester_round_preview.dart` gallery, which covered the awards hero
and sections, the trimmer scrubbing while dragging, and the invite sheet
sending. Everything else visual — the transition frames, the hosted More
dock, the ring sheet, the story tiles, the comment preview and mention
picker, the friend suggestions, the More sheet over the dock — is a rendered
capture, not a device.

**Not covered by any of this:** physical devices, a two-device call, native
screen readers, and production traffic. The Android foreground service in
particular has no two-device acceptance run, which is exactly the scenario it
was built for.

## Not done, deliberately or otherwise

Recorded as open in [Roadmap.md](../Roadmap.md) items 0r–0w and in
[Bugs.md](../Bugs.md); listed here so this session's boundary is explicit.

1. **Music for Reels from a licensed catalogue.** Blocked on a product and
   licensing decision, not on engineering. It must not be approximated by
   ingesting another provider's catalogue.
2. **Reel length above 90 s.** Needs `MAX_DURATION_MS`, the 100 MB video cap
   and a streamed upload, then a deploy.
3. **"Stay open" Community rooms still end when the host leaves.** Traced on
   2026-09-07 (`1a58ce14`) and then deferred by the maintainer the same day.
   The analysis is in
   [DEPLOYMENT.md](../DEPLOYMENT.md#stay-open-community-rooms-cannot-actually-stay-open--server-proposal-2026-09-07);
   the interim honest fix — copy saying what actually happens — was not
   applied either.
4. **`createReelCommentReport` performs no visibility check**, diverging from
   ADR-086 rule 2. The trade is reasoned at the call site: with the check and
   no receipt, a harasser could immunise their own comment by blocking the
   victim afterwards. The remedy is a report receipt issued by
   `getReelViewV2`.
5. **Reported Reel comment text is retained in `reports` with no TTL and no
   account-deletion scrub.** It is the first third-party content stored
   there, and it is live in production.
6. **The new Reels engagement copy is EN/PL only**; the other 41 locale
   variants fall back to English. The localization source guard does not
   demand catalog entries on this path, so nothing failed in CI. The same
   round did add ADR-152's two trim strings to the catalog properly, so this
   is an inconsistency rather than a policy.
7. **The server share of the latency work was not done.** The 2026-09-07
   deploy updated Function *code* and changed no `minInstances`; the warm set
   is still `createLiveKitToken`, `startDirectCall`, `createDirectCallToken`,
   `sendDirectMessage` and `sendRoomMessage`. The proposal in DEPLOYMENT.md
   is still a proposal, and mute's unmute wait, the chat-open cold start and
   the staff panels are unchanged on the server side.
8. **A true per-user "delete chat"** still needs a new callable and a deploy.
9. **Reconnect-on-resume in the room screens** remains open after ADR-154.
10. **Play Console foreground-service-type declaration** must be made by the
    owner before a release carrying the Android service.
11. **Award decorations are visible only to their own account** until a
    server projection is built.

## Release status

As of `5f78efb6`: no store build, no Hosting deploy, no tester email, no
promotion, and [DEPLOYMENT.md](../DEPLOYMENT.md) records no Build 22 release.
The invited channels still carry 1.0.0 (21). Every client item above becomes
observable only when a Build 22 artifact is produced and assigned, which this
session did not do. Confirm the current release state with the DevOps and
Release Engineer before repeating any of this as present tense.
