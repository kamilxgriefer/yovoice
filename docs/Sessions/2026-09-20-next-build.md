# The next build after 3.0.0 — eight branches, one integration — 2026-09-20

Base: `main` `f71a2ae2` (YO Voice 3.0.0+34, the Slim redesign, already with
testers on both stores). Integration branch: `nb/integrate`, in the worktree
`/Users/kamil/Documents/GitHub/tmp/nb-integrate`.

**Outcome: done in source. Nothing is on `main`, nothing is deployed, nothing
is with testers, nothing was run on a real device or a simulator.** The single
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
| Server channels should do what DMs do (next-build Task 2a) | Emoji in the channel composer; one reaction per person in the DM vocabulary, toggled from the actions sheet, in announcements and rules channels too, never for guests; photos and videos through a server-issued reservation, a byte-probing finalize, 90-second V4 read grants and durable deletion jobs; authors can retract their own messages. io uploads stream from disk; a library pick goes through the ADR-212 review first. | `nb/server-messaging` | ADR-216 |

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
way, as `docs/briefs/2026-09-19-nb-server-messaging-docs.md`; its deploy
order (section 7 of that brief) is folded into DEPLOYMENT.md — with Storage
Rules moved *before* the Functions that issue reservations, as ADR-216
requires, where the brief had them second.

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
- **Nothing is deployed.** Production still runs the 3.0.0+34 backend: the
  old sweep, no reminder scheduler, no comment notifications, no
  `releaseServerChannelSessionIfEmptyV1`. Every defect fixed here is still
  live for every user.
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
> **React, and share photos and videos, in server channels.** Tap and hold a
> message in a server text channel to react with an emoji — announcements
> too. You can send photos and short videos (up to a minute) there, see them
> before they go, and delete your own messages.
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
> **Reakcje, zdjęcia i filmy na kanałach serwera.** Przytrzymaj wiadomość na
> kanale tekstowym serwera, żeby zareagować emoji — także w ogłoszeniach.
> Możesz tam też wysyłać zdjęcia i krótkie filmy (do minuty), zobaczyć je
> przed wysłaniem i usuwać własne wiadomości.
>
> **Plakietka NA ŻYWO mówi prawdę.** Kanał głosowy przestaje pokazywać NA
> ŻYWO mniej więcej minutę po wyjściu ostatniej osoby, zamiast trzymać ją
> nawet przez kwadrans.

**Both sets describe behaviour that is in source only.** Do not send either
until the build is actually deployed and installed — the LIVE-badge line in
particular is a backend change and is false until the Cloud Functions deploy
and the LiveKit webhook confirmation are both done.
