# The next build after 3.0.0 — eight branches, one integration — 2026-09-20

Base: `main` `f71a2ae2` (YO Voice 3.0.0+34, the Slim redesign, already with
testers on both stores). Integration branch: `nb/integrate`, in the worktree
`/Users/kamil/Documents/GitHub/tmp/nb-integrate`.

**Outcome: done in source. Nothing is on `main`, nothing is deployed, nothing
is with testers, nothing was run on a real device or a simulator.** Built on
2026-09-19/20; the branch then waited while `main` shipped 3.0.0+35 and was
merged with it on 2026-09-25 (see "Waiting for 3.0.0+35" below). The single
deploy order and the owner-only steps live in
[DEPLOYMENT.md](../DEPLOYMENT.md#next-build-after-300--one-deploy-order-for-the-whole-build-source-only-nothing-deployed);
the product account is in [Roadmap.md](../Roadmap.md); the defects are in
[Bugs.md](../Bugs.md).

## What Kamil asked for, and what each request became

| What was asked | What it became | Branch | Decision |
| --- | --- | --- | --- |
| "Yeels can't be scrubbed" | A finger on the Yeel timeline is a scrub session: a translucent drag-only band over the hairline on both Yeel stages, an adjustable slider node (±5 s, arrow keys, mouse click) so keyboard and screen-reader users can move through a Yeel at all, and finger-seek on the Voice story player waveform. A childless fill that had always laid out `200 × 0` was fixed on the way. | `nb/yeels-scrub` | ADR-211 |
| "I can't call someone from their profile" | Quick actions under the bio at every width (Zadzwoń, Wideo, Wiadomość, Więcej), the call launch flow extracted so the chat header and the profile run one implementation, a relationship gate that disables calls for non-friends with a visible reason, and a Więcej sheet with voice message, invite-to-server and report. | `nb/friend-actions` | none — no new architectural rule |
| "I want to see what I'm sending before it uploads" | One confirm-before-send review for everything picked from a library: DM Photo library, DM Video library and Company team files show the file with its size and length before anything is queued, and an over-limit video is blocked *in* the review instead of being refused by a snackbar after the enqueue. Camera paths untouched. | `nb/confirm-upload` | ADR-212 |
| "brakuje opcji usuwania serwerów" | Delete or leave a server from the list itself: a `...` button, long press and secondary click; a labelled settings entry on wide; a separate danger zone in the sheet; a typed-name confirmation; legacy schema-less roots routed to `deleteClubSelf`; and a live channel turning the confirmation into "Zakończ rozmowy i usuń". | `nb/server-delete` | none — client-only use of deployed authority |
| "zatwierdzam wszystko, opcja b" (GIFs) | GIPHY searched by the client with `rating=g` pinned, resolved by the server at send time by id, the official Powered By GIPHY mark, Action Register pingbacks gated on "Load GIFs automatically", and a dual-provider allow-set on every send path so Originals can never be stranded by a provider flip. **The whole server half is source-gated off.** | `nb/giphy` | ADR-214 |
| "a channel still says LIVE with nobody in it" | A session now ends one 60 s backend-observed reconnect grace after the last person leaves, through three paths into the one existing end writer: the leaving client's new `releaseServerChannelSessionIfEmptyV1`, the provider's signed `room_finished`, and the tightened five-minute sweep, which also repairs projections no live generation backs. Plus a dry-run-first repair script for the badges already stuck in production. | `nb/server-live` (Windows PC) | **an amendment to ADR-180, deliberately not a new number** |
| "notifications are missing" | Comments on your Voice Moment and your Yeel notify you; `@mentions` inside them notify the mentioned person, validated against *their* audience; Server event reminders are finally delivered; a role promotion and an ownership transfer tell the member. Deny-by-default at the push boundary, a "Moments & Yeels" preference group, and copy in 41 locales. | `nb/notifications` | ADR-213, and ADR-215 for the hardening round |
| Server channels should do what DMs do (next-build Task 2a) | The emoji input stays in the channel composer while membership loads (it used to vanish); one reaction per person in the DM vocabulary, toggled from the actions sheet, in announcements and rules channels too, never for guests; photos and videos through a server-issued reservation, a byte-probing finalize, 90-second V4 read grants and durable deletion jobs; authors can retract their own messages. io uploads stream from disk; a library pick goes through the ADR-212 review first. | `nb/server-messaging` | ADR-216 |

The decisions as they finally stand: **ADR-211** Yeels drag-to-seek,
**ADR-212** confirm before upload, **ADR-213** the notification slice,
**ADR-214** GIPHY option B, **ADR-215** the notification hardening round,
**ADR-216** server channel reactions and media, plus the **ADR-180
amendment** for empty server channel sessions. When `main` took ADR-210 for
the Velvet Mallet sound pack (3.0.0+35), `2d1bfdef` moved every record this
branch introduced up by one, and `985dceee` merged 3.0.0+35 in. Three branches
had each independently written "ADR-211"; `9b941f14` renumbered them and moved
every anchor, deployment heading and code comment with them. The GIPHY entry's
own note about that collision has been settled in this session — nothing cites
210 for GIPHY any more.

## How the work actually ran

Two machines. Six branches were built on this Mac, one at a time under a
machine-wide lock (`tmp/lk.sh`) because the Mac has 8 GB of RAM and other
sessions run heavy jobs on it; the Flutter suite is therefore always run as
two halves, and the Functions suite in batches. `nb/server-live` was built on
the Windows PC in parallel, which is why its evidence arrived as a written
brief (`docs/briefs/2026-09-19-nb-server-live-docs.md`) holding every line the
protected documents needed rather than as edits to those documents — the two
machines cannot merge prose safely at the same time. This session folded that
brief into `Decisions.md`, `SECURITY.md`, `Servers.md`, `DEPLOYMENT.md`,
`Firebase.md`, `Bugs.md` and `Roadmap.md` and deleted it. The eighth branch,
`nb/server-messaging`, was also built on the Windows PC and arrived the same
way, as `docs/briefs/2026-09-19-nb-server-messaging-docs.md`. Its deploy
order (section 7 of that brief) is folded into DEPLOYMENT.md — with Storage
Rules moved *before* the Functions that issue reservations, as ADR-216
requires, where the brief had them second — and the rest of it into
`Decisions.md` (ADR-216), `SECURITY.md`, `Servers.md`, `Firebase.md`,
`Bugs.md` and `Roadmap.md`; the brief was then deleted (2026-09-25). It is in
git history at `afa9dc03` for anyone who needs the branch-time evidence.

The Windows machine also produced the only cross-platform noise worth
recording: seven Functions cases fail there on *any* tree, `origin/main`
included — four compare `require.cache` keys and paths written with `/`
against Windows `\`, two assert POSIX file modes (`0600`), and one spawns a
CLI whose `status` came back `null` under load. Those are the environment, not
the branch.

Merge order was `nb/yeels-scrub`, `nb/friend-actions`, `nb/confirm-upload`,
`nb/server-delete`, `nb/giphy`, `nb/server-live`, `nb/notifications`, then
`nb/server-messaging` (`0fbe42d0`) and its upload platform split
(`e69b1013`). Two
integration commits followed the merges rather than the branches:

- `bd549032` — `tool/servers_activation_package.js` hard-pins the reviewed
  Servers V1 manifest and is **not run by CI**, so nothing before integration
  noticed that adding one callable moved it. The numbers were **recomputed
  from the merged `functions/servers/registration.js`**, never relaxed to make
  a suite pass: 61 → 62 total exports, 55 → 56 callables, 54 → 55 base,
  48 → 49 non-creation. A stale header comment in
  `functions/test/cold_start_module_graph.test.js` that still said 54 three
  lines above its own recomputed assertion of 55 was corrected in the same
  commit.
- `f0ea2867` — the ADR-215 hardening round, which is a real behaviour change
  and has its own entries in Bugs.md and TESTING.md.

## What the final passes found and fixed

Three changes landed after the eight branches were merged, each found by a
review of the integrated tree rather than of a single branch. All three are
on the server channel media path (ADR-216); none touches a rule, an index or
a pinned number.

- **`e69b1013` — uploads stream from disk.** The channel photo/video path read
  the whole pick into the Dart heap to measure it and then `putData` copied
  it again: ~128 MiB transient for a 64 MiB video, an out-of-memory kill on a
  mid-range Android phone. Now platform-split like the DM store
  (`club_media_upload_source_io.dart` uses `putFile`, web keeps `putData`),
  measured with `XFile.length()`. The one new failure mode — the OS evicted
  the picker's temp file — is refused locally with the existing copy and
  leaves the reservation unused. ADR-216 decision 5.
- **`6a473b27` — the review sheet on server channels.** A photo or video picked
  from the library in a server text channel now opens ADR-212's
  `YoMediaSendReview` ("Send this photo?") before anything uploads; a camera
  capture deliberately goes straight through. The review's bounds are the
  DM constants because `storage.rules` declares exactly those for
  `server_message_media`. ADR-212 amendment, ADR-216 decision 6.
- **`77264f18` — a failed send can be retried.** The review keeps Send armed
  after a failure, but every press minted a fresh `reserveRequestId`, so the
  retry was read as a second upload and refused `resource-exhausted` —
  "We're a little overloaded right now" — for up to fifteen minutes, in every
  channel of every server. Fixed on the client: one `ServerMediaSendAttempt`
  per pick replays its reservation and committed generation. The backend's
  one-lease rule was not relaxed. ADR-216 decision 7, [Bugs.md](../Bugs.md).

Documentation corrections from the same passes: `afa9dc03` put the Storage
Rules deploy (step 2b) before the Functions that issue reservations — the
branch brief had it second, which would refuse every upload after a
reservation was granted — and corrected the `firestore.rules` and
`storage.rules` rows below; this pass corrected ADR-216's export-surface line,
which had counted the broadcast and last-leave callables twice, and folded
the branch brief into SECURITY.md, Servers.md, Firebase.md and Bugs.md.

## Waiting for 3.0.0+35

The branch was finished on 2026-09-20 and not merged to `main`. While it
waited, `main` shipped the Velvet Mallet v6 sound pack: `32c9dd9b` (ADR-210),
served on the web since Hosting run 36038221140 on 2026-09-24, and `738ecc4a`
setting `3.0.0+35` on 2026-09-25. Its store upload is the owner's step and is
not recorded as done. 3.0.0+35 changed no rule, index or deployed Function
(the only file under `functions/` it touched is one test), so production's
backend is still 3.0.0+34's and every backend change of this build is still
outstanding.

On 2026-09-25 the branch took it in:

- `2d1bfdef` moved every record this branch had introduced up by one, because
  `main` had used ADR-210: Yeels scrub 211, confirm before upload 212,
  notifications 213, GIPHY option B 214, the notification hardening round
  215, server channel reactions and media 216. 72 files, 153 references,
  anchors included.
- `985dceee` merged `main`. The only code overlap was
  `lib/features/notifications/data/services/push_notification_service.dart`
  and `test/notification_sound_profile_test.dart`. The sound resource names
  did not change, so the new notification types still point at existing
  files.
- `pubspec.yaml` therefore reads `3.0.0+35` here. It is not changed on this
  branch; a store build of it needs the next free build number (DEPLOYMENT.md,
  owner step 14).

## What this session verified, on this tree

| Check | Result |
| --- | --- |
| `flutter analyze` | **clean** — "No issues found! (ran in 7.0s)" |
| Flutter suite, odd half (`ls test/*_test.dart \| sort \| awk 'NR%2==1'`, `--concurrency=3`) | **2701 / 2701 pass** |
| Flutter suite, even half (`NR%2==0`, `--concurrency=3`) | **2766 / 2766 pass** |
| Flutter suite total | **5467 tests across 435 test files, 0 failures** |
| Servers V1 registration counts, recomputed with Node against the merged `registration.js` | 62 total exports, 56 callables, 6 non-callable exports, 7 Podcast-recording names → **55 base exports / 50 base callables**, which is exactly what `tool/servers_activation_package.js` pins |
| `firestore.indexes.json` vs. the base | **one** addition: the COLLECTION_GROUP composite on `events (reminderOptInEnabled, status, startsAt)`. 48 composites, 13 field overrides, TTL on `notificationDeliveryEvents.expiresAt` still declared |
| `firestore.rules` vs. the base | **six** additions, each `allow read, write: if false;`: `commentMentions/{mentionId}` and the five server channel media collections (`serverMessageMediaUploadReservations`, `…UploadLeases`, `…UploadBudgets`, `serverMessageMediaDeletionJobs`, `serverMessageMediaObjects`). Corrected on 2026-09-25: this row first said "one", written before `nb/server-messaging` was counted |
| `storage.rules` vs. the base | **one** addition: `match /server_message_media/{serverId}/{channelId}/{userId}/{fileName}` (+104 lines, ADR-216), so this build has a Storage Rules deploy step. Corrected on 2026-09-25: this row first said "byte-identical", which was false once `nb/server-messaging` merged |
| Every markdown anchor link in the repository | re-resolved after the ADR renumbering; the ones that did not resolve were fixed in this commit |

The merged Functions suite is **2480 / 2480 across 182 test files, 140 suites,
0 failures**, observed on `6a473b27` in four slices of
`ls functions/test/*.test.js | sort | awk 'NR%4==n%4'` (599 + 497 + 600 + 784),
each slice under its own fresh Auth + Firestore emulators. It moved from the
2442 / 179 that an earlier pass inherited because the server channel messaging
merge added `server_message_media`, `server_message_media_admin_delete` and
`server_message_reactions`; no existing test changed. Every slice is one
command, because the whole suite takes about fifteen minutes and no single
command in this session may run longer than eight. The Functions suite also
needs the storage bucket in the environment — without
`FIREBASE_CONFIG='{"projectId":"yovoice-ec54a","storageBucket":"yovoice-ec54a.firebasestorage.app"}'`,
`social_graph_security`, `report_audit`, `server_legacy_boundary` and
`servers_legacy_club_anchor_guard` fail with "Bucket name not specified or
invalid" on *any* tree, including the untouched base.

The hand-resolved export map in
`functions/test/cold_start_module_graph.test.js` was re-derived independently:
requiring the merged `functions/index.js` in a fresh child process with the
deployed environment yields **261** names, and they are identical to the pinned
list name for name, with no additions or omissions on either side.
`tool/servers_activation_package.js` still pins the reviewed
**62-total / 56-callable / 7-Podcast / 55-base** manifest, recomputed from the
merged `functions/servers/registration.js` and confirmed by its own
`node --test tool/test/servers_activation_package.test.js` at **12 / 12**. The
seven server channel messaging exports are deliberately outside
`SERVERS_V1_EXPORT_NAMES`, which is why none of those four numbers moved for
them.

**The last fully verified state is `cd30afea`** (2026-09-20): Flutter 5505,
Functions 2480, rules 781, all green, as reported by the integrating session
(the Flutter and rules counts are not otherwise recorded in this repository).
The table above is from an earlier point in the same session (5467 Flutter
tests). After `cd30afea` came `77264f18` (the retry fix), the documentation
commits `b75d19df`, `2d1bfdef` and `afa9dc03`, and the merge `985dceee`; the
full suites on the merged tree are recorded by the session that runs them,
not by this documentation pass.

No test assertion, finder or pinned number was edited to make anything go
green in this session. The only numbers that moved are the Servers V1 export
counts, and they moved because one callable was genuinely added; they were
recomputed from the merged code.

## What was NOT verified — read this before believing anything ships

- **Nothing was run on a real device or a simulator.** Not iOS, not Android,
  not a real browser. Every visual claim in this build rests on rendered test
  frames under `yovoice-evidence/2026-09-19/next-build/…`, and the Yeels
  seek latency, the arena feel of a diagonal flick, the media review on a real
  phone, the server delete/leave flow against the deployed backend and the
  friend-profile quick actions are all **UNVERIFIED on hardware**.
- **Nothing is deployed.** Production is on 3.0.0+35 on the web (sounds
  only), and its backend is still 3.0.0+34's: the old sweep, no reminder
  scheduler, no comment notifications, no
  `releaseServerChannelSessionIfEmptyV1`, no server channel reactions or
  media, no `server_message_media` Storage rule. Every defect fixed here is
  still live for every user.
- **No server-side video thumbnails.** A server channel video shows a
  placeholder poster with its duration (DMs have none either). Hover-revealed
  reactions and a side-sheet actions menu on wide screens were not built.
- **No production data was read** and **no provider console was touched** —
  not LiveKit, not Firebase, not GIPHY. No secret was written.
- **The LiveKit webhook is the biggest open question.** The URL was
  registered in LiveKit Cloud on 2026-09-19, but `firebase functions:log`
  returned only deployment audit entries, so **no delivery has ever been read
  back and acceptance of its HMAC signature is UNVERIFIED**. Until a real
  voice session proves one delivery after the deploy, `voiceMinutes` stays
  zero and the provider-driven end of an empty channel session does not
  actually run.
- **The provider drill is not done** (Servers activation precondition 4). The
  release path and `room_finished` act sooner than the old token-expiry rule,
  so three provider facts now have to be observed against real LiveKit Cloud:
  how long `ListParticipants` keeps listing a cleanly disconnected
  participant, when `room_finished` arrives after the last departure, and
  whether an OBS ingress participant and an Egress recorder are listed. Every
  local suite proves these paths against a stub adapter.
- **GIPHY is off and must stay off.** `resolveGif` is source-gated
  (`GIPHY_SEND_RESOLVE_ENABLED = false`), no key exists, and `getGifCatalog`
  answers `resolvableProviders: []`, so the picker behaves exactly like
  today's Originals-only picker in every build. No GIPHY request has been
  made from anywhere in this work.
- **App Check stays telemetry-only.** Attestation is unhealthy on all three
  platforms; enforcing now would refuse most real traffic.
- **Stale LIVE badges already in production are untouched.** The repair script
  has never been run against production, not even as a dry run.
- The **`yovoice-website` branch `privacy/giphy`** is written and must not be
  published until GIPHY is actually live.

## Owner steps, in short

The full list, with commands, is
[DEPLOYMENT.md, "Steps only Kamil can do"](../DEPLOYMENT.md#steps-only-kamil-can-do);
the deploy order itself is steps 1 → 2 → 2b → 3a → 3b → 4 there. In short:
read back (or grant) the Functions runtime `signBlob` permission before 3b;
confirm one LiveKit webhook delivery after 3b; dry-run, apply and re-check
the stale-LIVE repair script; run the provider drill; confirm the
`notificationDeliveryEvents` TTL after the index deploy; change the website's
`/delete-account` copy only after 3b; keep GIPHY off (production key, the
official mark, the secret, the privacy disclosure and a separate deploy wave
all still pending) and App Check telemetry-only; pick the next free build
number before a store build; then the store and web release. The smoke after
the release now includes the two checks the final passes added: a library
pick opens the review first, and a failed send goes through on the retry.

## Release notes

Short, user-facing, and describing only what a tester will actually see once
this build is installed. **No links and no domain names**, because the tester
e-mails carry none.

### English

> **What's new in YO Voice**
>
> **Scrub through a Yeel.** Drag along the timeline to move through a Yeel,
> or use the arrow keys. The Voice story player takes a finger too.
>
> **Call a friend from their profile.** Call, video, message and more now sit
> right under the bio — no hunting for the chat first. From "More" you can
> send a voice message, invite someone to one of your servers, or report them.
>
> **See it before you send it.** Photos and videos you pick from your library,
> and files you add to a Company server, now show you exactly what you chose —
> with its size and length — before anything is uploaded. A video that is too
> long is caught here, not after.
>
> **Delete or leave a server without hunting for the button.** It is on the
> server row itself now, and on the settings entry in the panel. Deleting asks
> you to type the server's name first, and tells you plainly when a
> conversation is still live.
>
> **New notifications.** You are told when somebody comments on your Voice
> Moment or your Yeel, and when somebody mentions you in one of those
> comments. Server event reminders finally arrive. Being promoted in a server,
> or handed ownership of one, now tells you. You can turn all of this on or
> off under "Moments & Yeels" and "Servers" in your notification settings.
>
> **Emoji, reactions, photos and videos in server channels.** The emoji
> button no longer disappears from a server channel's message box while the
> channel is still loading. Tap and hold a message in a
> server text channel to react with an emoji — announcements too. You can
> send photos and short videos (up to a minute) there; anything you pick from
> your library shows up for a look before it goes, and you can delete your
> own messages.
>
> **The LIVE badge tells the truth.** A voice channel stops showing LIVE about
> a minute after the last person leaves, instead of hanging on for up to
> a quarter of an hour.

### Polski

> **Co nowego w YO Voice**
>
> **Przewijanie Yeela.** Przeciągnij palcem po pasku czasu, żeby przewinąć
> Yeela, albo użyj strzałek. Odtwarzacz relacji głosowej też reaguje na palec.
>
> **Zadzwoń do znajomego z jego profilu.** Zadzwoń, Wideo, Wiadomość i Więcej
> są teraz tuż pod opisem — nie trzeba najpierw szukać czatu. W "Więcej"
> wyślesz wiadomość głosową, zaprosisz kogoś na swój serwer albo zgłosisz
> użytkownika.
>
> **Zobacz, zanim wyślesz.** Zdjęcia i filmy wybrane z galerii, a także pliki
> dodawane na serwerze firmowym, pokazują się teraz przed wysłaniem — razem z
> rozmiarem i długością. Za długi film zostaje zatrzymany tutaj, a nie dopiero
> po dodaniu do kolejki.
>
> **Usuń lub opuść serwer bez szukania przycisku.** Jest teraz na samym
> wierszu serwera i w ustawieniach panelu. Usunięcie prosi najpierw o wpisanie
> nazwy serwera i wprost mówi, kiedy rozmowa jeszcze trwa.
>
> **Nowe powiadomienia.** Dowiesz się, kiedy ktoś skomentuje Twój Moment
> głosowy albo Twojego Yeela i kiedy oznaczy Cię w takim komentarzu.
> Przypomnienia o wydarzeniach na serwerze wreszcie przychodzą. Awans na
> serwerze i przekazanie własności też dają znać. Wszystko to włączysz i
> wyłączysz w ustawieniach powiadomień, w sekcjach "Momenty i Yeels" oraz
> "Serwery" (przełączniki "Komentarze i oznaczenia", "Wydarzenia na
> serwerach" i "Twoja rola na serwerze").
>
> **Emoji, reakcje, zdjęcia i filmy na kanałach serwera.** Przycisk emoji
> nie znika już z pola wiadomości na kanale serwera, gdy kanał jeszcze się
> wczytuje. Przytrzymaj wiadomość na kanale
> tekstowym serwera, żeby zareagować emoji — także w ogłoszeniach. Możesz tam
> też wysyłać zdjęcia i krótkie filmy (do minuty); to, co wybierzesz z
> galerii, zobaczysz przed wysłaniem, a własne wiadomości możesz usuwać.
>
> **Plakietka NA ŻYWO mówi prawdę.** Kanał głosowy przestaje pokazywać NA
> ŻYWO mniej więcej minutę po wyjściu ostatniej osoby, zamiast trzymać ją
> nawet przez kwadrans.

**Both sets describe behaviour that is in source only.** Do not send either
until the build is actually deployed and installed — the LIVE-badge line in
particular is a backend change and is false until the Cloud Functions deploy
and the LiveKit webhook confirmation are both done.
