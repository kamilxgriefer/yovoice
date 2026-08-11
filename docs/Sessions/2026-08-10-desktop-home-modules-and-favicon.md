# 2026-08-10 — Desktop Home modules + the app favicon

Two related desktop-web tasks from an annotated screenshot
(`assets/images/Zrzut ekranu 2026-08-10 o 22.11.05.png`) and a tab
comparison (`…22.24.31.png`): make the app's browser tab match the
landing page's, and finish the desktop Home redesign started in
`6a8944e`.

## 1. Favicon

The app tab showed the mark inside a black square; the landing tab
showed it clean. Measured rather than guessed: every icon in `web/` was
**100% opaque** at every size, while the website's `src/app/icon.png` is
512×512 with the symbol at 417×432 and ~8% transparent padding. The old
set was RealFaviconGenerator output built from artwork with the square
baked in — the same artwork the website's `public/logos/README.md`
already records as retired.

Fix: regenerate every app icon as a straight LANCZOS downscale of the
website's canonical icon, so scale and padding match by construction and
the logo is never redrawn.

- **New/replaced**: `favicon.ico` (16/32/48/64/128/256, mirroring the
  website's own ICO), `favicon-96x96.png`, `favicon-32x32.png` and
  `favicon-16x16.png` (new sizes), `apple-touch-icon.png`,
  `web-app-manifest-192x192.png`, `web-app-manifest-512x512.png` (also
  the committed master).
- **Deleted**: `favicon.svg` (1.6 MB traced raster, old artwork),
  `favicon.zip` (generator bundle), `favicon.png`, and the
  `flutter create` leftovers `manifest.json` + `icons/Icon-*.png` — a
  second manifest nothing linked, still branded "A new Flutter project"
  with Flutter's `#0175C2`.
- **Cache safety**: `?v=2` on every link in `index.html` and in
  `site.webmanifest`, plus a `firebase.json` Hosting header sending
  `no-cache` for exactly those filenames. Without it a deploy keeps
  serving the black square from cache.
- `purpose` dropped from `any maskable` to `any`: the artwork is
  transparent with ~8% padding, so maskable would let the platform crop
  into the mark.
- `<title>YoVoice</title>` untouched, and pinned by a test.

`web/README.md` is new and documents the source of truth, the file
table, and the regeneration snippet.

## 2. Desktop Home

Structure, before → after (centre column):

```
greeting                        greeting
                                Moments from your circle   ← new
Live around you                 Live around you
Featured Live | Your circle     Featured Live | Your circle
For you (2 gradient slabs)      For you (2 editorial cards) ← rebuilt
                                Conversations              ← new
```

Right column: Voice Trending → Premium (unchanged) → **Top creators you
follow** (new).

Where each module's data comes from — all existing services, nothing new
on the backend:

| Module | Source |
| --- | --- |
| Moments strip | `HomeFeedService.watchSocialMoments` (self + friends + following), newest Moment per person |
| Conversations | `MessageService.watchConversations`, `ClubService.watchMyClubs` + new `ClubChatService.watchLatestMessage`, `FriendService.watchFriends` |
| Top creators | `FollowService.watchFollowing`, `RoomService.watchLivePublicRooms` (`hostId` match), `watchSocialMoments` |
| For you / Live / Featured / circle | unchanged: `watchLivePublicRooms`, `watchParticipants`, `watchFriends` |

Four states the schema cannot prove, and what is shown instead (full
reasoning in ADR-036):

- no per-viewer "seen" on Moments → ring/"New" mean "posted in the last
  24 h"; older tiles show real duration. Never "Live" — a Moment is
  recorded audio.
- no per-member unread on club channels → club rows have no badge.
  Direct rows do, from `unreadCounts`.
- no third "private" conversation type → `Private` is every direct
  conversation, `Friends` the subset with a confirmed friend.
- creator presence only via `rooms.hostId` → "speaking in someone else's
  room" is not surfaced.

Two duplicate actions removed: the sidebar Moment action (already gone
in `5f02271`; the shell test pins it) and "Start a room" from Your
circle — whose width now goes to a real online count and a sixth face.

Responsive: near the 1100px breakpoint the centre column is ~490px, and
three equal live cards there were ~140px each — every room name an
ellipsis. The row now scrolls at a 194px floor. "For you" stacks below
620px; Featured/Your circle already stacked below 720px.

## Verification

- `flutter analyze` clean; 159 tests pass (139 before).
- New coverage: desktop Home structure and both obsolete actions,
  Moments strip data + viewer/create/see-all callbacks + empty state,
  For you card content + Join, all four conversation filters + row
  callbacks + per-filter empty states, followed-creators real data +
  live signal + empty state + callbacks, overflow at 1440×820, 1440×620,
  492×900 (the centre column at the 1100 breakpoint) and 1920×1080, and
  `test/web_favicon_test.dart` for the icon set, links and manifest.
- Looked at, not just tested: `test/desktop_home_preview.dart` renders
  the production widgets against `fake_cloud_firestore`. Checked at
  1440×820, 1440×1650 (full page), 1100, 1920×1080, 1440×620, and
  `?empty=1` for the new-account view where every module holds its own
  compact empty state.

## Not done / notes

- The favicon fix only reaches production on the next Flutter web
  deploy. Deploys stay manual on purpose.
- `assets/images/logo.png` (the sidebar wordmark) is still 1024×1024
  RGB with no alpha — same retired artwork family, but out of scope
  here and invisible on the near-black rail.
