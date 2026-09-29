# Features

What's actually built, feature by feature — not aspirational. "Coming
soon" markers below match what the app itself shows the user; see
[Roadmap.md](Roadmap.md) for planned work and priority order.

## Servers

The current source is built around persistent **Servers**, with one responsive
workspace for phone, tablet and desktop. The creation flow starts with the
full-screen five-card selector, in this fixed order:

- **Friends** — compact text, voice, events and rules channels.
- **Community** — text and voice plus a moderated LIVE video stage, events,
  questions, announcements and rules.
- **Podcast** — LIVE studio, persistent episode recording/archive, programme,
  listener questions, discussion, announcements and rules.
- **Family** — private family conversation, lounge, calendar, shared shopping
  list, check-ins and a private photo-and-voice Memories album.
- **Company** — team and project channels, restricted HR and Management
  channels, meetings with screen sharing, a collaborative whiteboard with live
  ink, and controlled company files.

The selector preserves the approved typography, color identity and responsive
breakpoints. Choosing a card opens actual configuration; changing the template
keeps the entered name and description. The shell keeps its established global
navigation layout and behavior. Its former Rooms destination now shows the
Servers hub with a server-hub icon and Server label. The standalone Rooms,
Discover and Clubs destinations are no longer exposed in the product UI.

Servers use a versioned facade over the existing `clubs` and `rooms` Firebase
graph so existing identities, membership, moderation and media history remain
compatible. Those collection names and legacy model types are implementation
details, not separate user-facing products. Current `?server=` links and
historic `?club=` links open the corresponding Server workspace. A historic
`?room=` link whose room has a related `clubId` also opens that workspace; a
standalone legacy room without `clubId` lands in the Servers catalog instead of
reviving the removed Rooms screen. Server invitations resolve through the same
Server surface. New V1 invitations are generation-bound, expire, can be
accepted or declined idempotently and notify only the intended recipient. See
[Servers.md](Servers.md) for the complete schema and rollout contract.

Voice and video participation still use LiveKit. Roles and publish sources are
derived from current server membership and channel policy on the backend.
Community stages can grant camera publishing. Screen sharing is granted only to
the session host, in a Company meeting or a Community broadcast stage. The host
can start a share from the web client, from Android (after the system screen
capture consent) and from iOS, where only the YO Voice app itself is captured.
The native macOS, Windows and Linux clients can join and view but cannot yet
start a share. Android and iOS sharing are **UNVERIFIED on a device**. Podcast stages can record into their persistent
episode archive. Removing membership or ending a session revokes the
corresponding provider-room access. The retained legacy `RoomExperience`
mapping remains a compatibility layer, including old persisted `podcast`
values.

The host of a live Community broadcast stage can also stream from OBS
(ADR-192, source only): **OBS** beside **Share screen** opens a setup guide
and returns an RTMP server URL and a Stream Key, masked until revealed, with
copy buttons. One broadcast per account is allowed, and the feature stays off
until an operator enables it. No real OBS stream has been tested. In a Company
meeting, other members' strokes appear on the whiteboard while they are still
drawing (ADR-193); only completed strokes are saved.

This section describes the coordinated local source change. Production
activation, migration and Firebase deployment remain separate release actions.

## Profile

`lib/features/profile/` — editable identity/media, account type and real
activity counters. `Your YO Voice journey` presents Servers joined, Messages,
Voice time and Servers created as one compact four-row list with intrinsic
height, so desktop width no longer turns four short metrics into oversized
cards. Changing a Personal profile into Creator requires the trusted Creator
capability and is checked again on Save; an existing Creator profile and its
content are not erased when Premium expires.

Follower and following controls are absent for an ordinary Personal account.
They appear only when a user has a verified Creator identity, active Premium
access, completed eligibility checks and explicitly enables the audience
feature. That decision is projected by the server and fails closed when the
projection is missing or Premium expires.

## Home

Home is server-first. It keeps the compact strip of friends and their current
Voice activity at the top, then presents the signed-in user's Servers, a direct
create-server action and recent chats. The former general Followers panel and
ordinary-user follow discovery are removed. Creator audience discovery remains
available through YO Moments and the Find creators destination in More; both
surfaces expose only eligible, opted-in Creators.

## Friends & Social

`lib/features/friends/`: friend requests (must exist before a friendship
record can be created — no forcing a friendship via direct write), blocking,
mutual-friend discovery and friend suggestions. Friendship remains available
to every active user. Creator following is a separate, server-gated audience
relationship and is never treated as friendship or Server membership.

## Messages

Direct messages (`conversations/{id}/messages`) and Server channel chat
(`clubs/{serverId}/channels/{channelId}/messages`, retaining the collection
name for compatibility) — `lib/features/messages/` and
`lib/features/chats/`.

Direct conversations support text, private photos and private voice messages
(1–60 seconds). Photo and voice uploads use a server-issued, expiring
reservation; the resulting message stores a private `gs://` object reference,
not a public download-token URL. Only active participants can read the object
through the authenticated Firebase Storage SDK. Upload and finalization are
idempotent, so a lost network response reuses the same reservation and object
instead of creating a duplicate message.

A photo or video picked from the library is reviewed before anything is
queued (next build after 3.0.0, ADR-212): the review shows the photo, or a
paused and muted local video with play, scrub and mute, with its size and
length, and names the recipient. Send queues it; Cancel sends nothing. A video
over 60 seconds or 64 MB, or a photo over 8 MB, is blocked in the review with
the reason and a "Choose another" that reopens the library. Taking a photo or
recording a video with the camera keeps the camera's own Use/Retake step.
Company team files use the same review before an upload.

Confirmed friends can also place a real-time 1:1 voice call from the phone
action in a DM. The callee sees an app-level incoming-call screen and can answer
or decline; the caller can cancel while ringing, either participant can mute or
end after connection, and a 60-second timeout becomes a missed-call entry that
opens the conversation. Calls use a separate server-authoritative lifecycle and
dedicated LiveKit room rather than pretending a two-person call is a Community
Room. Only one ringing/active call per account is allowed.

In source from 2026-09-16 (ADR-194), an active video call continues in system
Picture in Picture when the app goes to the background (Android 8+ and
iOS 15+), and the window stays open through a brief reconnect. A video sent in
a direct chat now plays with sound after a call or a voice recording. Both are
**UNVERIFIED on a device**, and the local camera currently pauses while in
Picture in Picture.

Home surfaces the three most recently updated non-archived direct
conversations as `Your recent chats`. Global Chat is retired from the app
UI; its existing backend data remains compatibility-only for older clients
and historical moderation records.

**Reporting content** (source `9f3ce7f`/`2c086c7`, **not yet released**):
a message, Voice Moment or comment can be reported from every surface where
that content appears — DM chat, both Moments feeds and the comment thread —
through `createContentReport`. Reporting is never offered on your own
content. A reason picker (spam, harassment, hate, sexual, violence,
self-harm, impersonation, other) replaces what used to be a hardcoded
`harassment` label, with self-harm drawn differently so a distressed reporter
finds it without reading eight rows; there is no free text and no
confirmation step, deliberately. Failures say why: nine callable status codes
map to nine distinct sentences, and the 30-second cooldown is told apart from
the 20-per-day cap through the reporter's own `reportLimits` document. It is
available to **any active account**, verified or not, because reporting is a
safety action. **Until this ships, no message anywhere in the product can be
reported.** Room and club message reports can be triaged but not yet actioned
by a moderator, and the Moderation Center does not yet render them correctly
— see [Bugs.md](Bugs.md#moderation--safety) and Roadmap item 0o.

## YO Moments

YO Moments is one responsive destination with a shared title, visual language
and top-level **Głos | Yeels** text selector. Internal models and source paths
retain the established Reel naming for compatibility. It uses an original
content-stage and conversation design inspired by familiar short-form
interaction patterns, without copying another product's branding, assets or
exact layout.

The Voice format contains short (≤60s) recorded audio posts
(`lib/features/moments/`): likes, text comments and recorded voice replies, a
public feed
(`MomentService.watchPublishedMoments`) and a per-user feed
(`MomentService.watchMyMoments`, published + drafts) used by Creator
Studio. Like/comment counters are transactionally validated against the
actual `likes` subcollection — not client-settable to an arbitrary value.

Yeels uses the same YO Moments chrome around an immersive video/photo stage.
Its comment thread accepts text and voice replies. Recording opens an explicit
composer and does not start the microphone before the user acts. Published
voice replies have their own compact player and share one playback arbiter with
the primary Voice Moment or Yeel, so competing audio does not overlap. Yeels
voice publishing probes backend support and fails honestly when that coordinated
backend is not yet deployed.

Yeel videos fit their frame by one rule shared by the composer and every
feed host: cover while it still shows at least 72% of the picture (every
upright phone clip), otherwise the whole video over a blurred copy of itself
(black bands on web — pending Kamil's sign-off — and on Android phones with
4 GB RAM or less). The composer's **Obróć** pill, in
the video's top corner, turns a video a quarter turn clockwise per tap; at
Publish the rotation is written into the uploaded file's track matrix, so
iOS, Android and web viewers — older builds included — play it upright
([ADR-235](Decisions.md#adr-235-yeel-videos-fit-by-one-shared-rule-and-obróć-rotates-the-files-track-matrix-not-the-recipe)).

**Moments is a primary destination** (source `cef05e6`, deployed
2026-08-20). Friends keeps its existing screen and state outside the five-item
mobile dock. Voice discovery is a bounded popular pool weighted by engagement,
shuffled under a held seed so paging stays stable, with authors spaced apart.
The Following filter combines friends with Creators whose audience feature is
currently eligible and enabled; it does not restore public follower controls
for Personal accounts. Ranking happens client-side because Firestore can
neither order by a computed sum nor randomise server-side. See
[ADR-089](Decisions.md#adr-089-moments-is-a-primary-destination-and-its-discovery-feed-ranks-client-side-because-firestore-can-neither-order-by-a-computed-sum-nor-randomise).

**Recording platform support** (2026-08-17): native and Chromium-based
browsers record; **Firefox cannot** and shows an explicit unavailable panel
naming the reason, because MP4/AAC is the only container the backend
accepts and Firefox's `MediaRecorder` does not produce it
([ADR-057](Decisions.md#adr-057-voice-moment-recording-splits-only-at-byte-acquisition-and-byte-upload-and-the-server-pins-the-audio-container)).
Until `6ef4380`, recording failed on web entirely — which, web being the
only published client, meant nobody could create a Voice Moment. A later
Safari-specific upload defect converted the native `MediaRecorder` Blob to a
Dart byte array before upload and failed before Storage created an object. Web
now preserves the native Blob and uploads it with `putBlob`; retry reuses the
same draft, request id and object generation. Browser/native seams and the
complete reservation/rules contract are automated, but a real post-deploy
iPhone Safari publish remains a release verification step.

**Review-before-publish and custom availability** (2026-08-27, **DEPLOYED TO
WEB; NATIVE STORE BUILD PENDING**): a completed take can be played, paused and sought from its
local file/Blob without reserving a Firestore draft or uploading bytes. The
author chooses any whole 24–720 hours, 1–30 days, or Until deleted; 24 hours
remains the backward-compatible default. Voice replies receive preview but no
separate lifetime. The server validates the duration and owns root publication,
expiry and deletion. A single nearest-deadline timer removes a Moment from an
already-open feed/detail/story/sheet/comments surface and stops playback at the
deadline. A visible transition is announced once to assistive technology and
keyboard focus moves to a stable surviving control or heading; Story keeps the
first surviving successor even when several links expire while the app is
suspended. Long waits are chunked below the browser timer limit, and cached
hidden tabs neither announce nor steal focus. Server callables independently
refuse new engagement at that same instant. A deadline does not delete the
stored document or audio. The mobile and desktop Home circle strips observe
the exact stream transition too, so a focused tile cannot disappear silently.
Root/reply
objects are client-immutable, and bounded server cleanup removes abandoned
uploads without racing finalization.

**Offline playback is live in the web/PWA client as of 2026-08-18; the same
source is ready for the next signed native release.** Published, non-deleted
Voice Moments can be downloaded on the current device. Offline audio is
account-isolated and local:
native clients store files in their application-support directory and play
them directly from the file path; web uses the browser's Cache Storage and
materializes bytes only for the selected playback. A compact local manifest
backs the real count, byte total, play, per-item removal and Remove all
controls. Limits are 12 MB per item and 250 MB per account on each device.
There is no Firestore collection, server database or cross-device sync for
downloads. Browser/site-data eviction, app removal or OS storage cleanup can
remove a local copy; the UI reconciles a missing object rather than pretending
it is still available. See
[ADR-074](Decisions.md#adr-074-offline-voice-moments-are-bounded-account-isolated-device-storage-not-a-server-database).

## Achievements / Awards

`lib/features/achievements/`: a 100-title catalog (`AchievementCatalog`)
across 10 retained metrics — messages, Creator followers, voice minutes,
server sessions, servers, friends, reactions, host minutes, active days and
moments — each
with 10 thresholds and a rarity tier (common → mythic). The Awards screen
adds:

- A derived **Level/XP** system (XP is a real function of unlocked
  achievements' rarity — not a stored, independently-editable number).
- **Category filters**: Creator, Community, Voice, Friends.
- A genuine **"recent unlocks" feed**, backed by a real
  `unlockedTitleTimestamps` map on the user document (see
  [Firebase.md](Firebase.md) and
  [ADR-010](Decisions.md#adr-010-real-per-achievement-unlock-timestamps))
  — achievements unlocked before that field existed simply don't appear
  there, rather than being backfilled with a guessed date.

## Creator Studio

`lib/features/creator/` — a real dashboard over the signed-in user's owned
Servers and Voice Moments, with quick actions into the existing
create-server/record-moment flows and a share-based invite flow.
Creator Studio requires the trusted Creator capability; More shows the locked
state to free users and the destination independently rechecks entitlement,
including expiry while it is open.

The audience visibility setting lives here. It is available only to an
eligible verified Creator with active Premium and requires explicit opt-in.
Ordinary accounts do not receive follower controls or a follower-notification
preference. Losing eligibility removes the public audience projection.

The Studio exposes two reachable tools:

- **Server tools** opens the Creator's existing Servers, channels and member
  tools.
- **Pinned post** lets an eligible Creator select exactly one of their
  canonical published Voice Moments. Eligibility can come from a live paid
  Creator entitlement or the derived moderator preview. The server-owned
  pointer is shown on both the Creator's own and public profile and is removed
  when the Moment or effective Creator access stops being eligible.

Monetization remains unbuilt and is intentionally absent from the Studio UI.

## Premium entitlements

`entitlements/{uid}` is the only **paid-access** source. A paid capability
requires an active/trialing/grace entitlement whose period has not ended, the
common `premiumIdentityEnabled` flag and its feature flag. The legacy
`canCreateClubs` field remains the compatibility name for paid Server tooling;
it does not expose a Clubs product surface. `users/{uid}.premiumIdentity` and
the visible VIP badge are public presentation data only; neither authorizes
Creator, Creator Studio, Creator audience visibility or protected Server
tools. Client gates fail closed and Firestore Rules enforce protected writes.

Active `moderator` and `superModerator` accounts also receive a derived,
revocable Premium-preview overlay so those roles can test identity, Creator
and Server tooling. It is kept in a separate client/model flag and server access
resolver: it does not fabricate `isPremium`, plan, period, renewal or provider
state. Acting backend operations require the signed role claim and
client-immutable mirror to match; demotion or an inactive account removes the
overlay while leaving any real paid entitlement untouched.

The subscription plumbing is ready for verified grants, but real App
Store/Google Play purchase adapters and an IAP client are not configured.
`verifyPurchase` therefore declines today; only the guarded
`adminSetPremiumEntitlements` admin path can issue a working grant (plus
one documented operator grant for the protected owner, ADR-053 amendment
2026-09-29).

**One exception (ADR-230, source only):** "See who liked" is unlocked by paid
Premium, the staff preview above, **or** a canonical owner-granted
`vipGrants/{uid}` document (exact keys, allowlisted source, `revoked:
false`, a Timestamp or null expiry). The grant authorizes this capability
only; every other paid capability still reads `entitlements/{uid}` alone.
The client's check is a UX pre-gate; the list callables decide.

### Likes and "See who liked" (ADR-230, backend, NOT deployed)

- **Comment likes.** Voice Moment and Yeel comments can be liked through
  `setMomentCommentLikeV1` / `setReelCommentLikeV1` (idempotent, everyone,
  not gated). Likes live in the server-only `commentLikes` /
  `commentLikeCounters` store; comment documents are unchanged. The views
  return per-comment `{likeCount, callerLiked}` only when asked with
  `includeCommentLikes: true`, so installed builds see identical responses.
  Deleting a comment purges its likes.
- **Lists.** `listVoiceMomentLikersV1` (a Moment or one of its comments),
  `listReelLikersV1` (a Yeel or one of its comments) and
  `listServerChannelMessageReactorsV1` (who reacted to a Server message, with
  an optional emoji filter) return pages of 20 people
  (`userId`, `displayName`, `reaction`), newest first (Server: emoji order,
  then uid), with an opaque cursor. Paid Premium, a canonical VIP grant or the
  staff preview is required (`likersAccessRequired` otherwise). Blocked
  (either way), private or friends-only (unless friends), muted, suspended
  and deleted accounts, and people with Hide my likes on, are never listed;
  you always see your own like. Counts never change. Budgets: 10 lists a
  minute, 120 an hour, 500 a day. Every existing like is listable once
  switched on.
- **Switched, not deployed.** Every list answers `likersNotEnabled` until an
  operator writes `appConfig/likersV1` (`enabled`, and `serverMessagesEnabled`
  for the Server list), which happens only after the privacy policy and the
  Hide-my-likes build are out on every platform for 7 days
  ([DEPLOYMENT.md](DEPLOYMENT.md#see-who-liked-adr-230--backend-deployed-2026-09-28-lists-switched-off)).
- **Hide my likes.** `setMyLikesHiddenV1 {hidden}` stores the private
  `users/{uid}.likesHidden`; it removes you from every YO Voice likers list
  and from Top reactions at once, and works before the lists are switched on.
  Server channel members still receive the raw reaction map of messages in
  channels they can read (recorded in ADR-230).
- **Closed:** the Build 19-era direct read of `voiceMoments/{id}/likes`.

### Likes in the app (ADR-230, client, source only)

Client source is in `lib/features/likers/` and the host screens. Nothing is deployed, and the lists stay off
until an operator enables the server-only switch `appConfig/likersV1`.

- **See who liked / See who reacted.** Premium, staff-preview and VIP viewers
  open a list of the people who liked a Voice Moment, a Yeel, a Voice Moment
  or Yeel comment, or reacted to a Server channel message. Every entry point
  opens the same flow; everyone else gets an honest Premium sheet with the
  public count and, while Premium cannot be bought, no purchase button.
  Entry points: "See who liked ›" beside Top reactions on Moment detail; the
  like count (a separate target from the heart) on Moment cards, the story
  viewer and the Yeel rail; a Yeel's panel, footer action and ⋯ sheet; the
  compact Głos row's ⋯ menu; a Server message's reaction pill and actions
  sheet; and the count beside a comment's heart.
- **The list.** Pages of 20 from the server, name with the VIP rosette,
  "You" for yourself, a small heart (Voice/Yeel) or the person's emoji
  (Server), reaction tabs on Server lists with two or more emoji, and a
  "Some people aren't shown." footer when privacy filters hid anyone. Blocked
  (either way), private or friends-only profiles you may not see, muted,
  suspended or deleted accounts and people who hide their likes are never
  listed. Counts never change.
- **Comment likes.** Voice Moment and Yeel comments get a heart and count in
  the action line ("Reply · ♡ 3"); VIP viewers also see "Who liked" there.
  The hearts appear only after the server has shown it supports them (an
  `includeCommentLikes` probe on the view calls); an older backend draws no
  heart at all.
- **Hide my likes.** Settings → Privacy → "Hide my likes" removes you from
  every likers list YO Voice shows. It is written through
  `setMyLikesHiddenV1` (never directly), is not behind the switch, and says
  plainly that Server members still receive your reactions in channels you
  share.
- **Premium section.** "See who liked" is listed in the Premium benefit card,
  checklist and included items.
- **Languages.** Every string is translated in all 43 app languages
  (`translations_vip_likers.dart`, `test/vip_likers_localization_test.dart`);
  the upsell's count line uses each language's plural forms.

## Premium Pages (ADR-231..233) — backend (B1-B5) deployed 2026-09-28 switched off; app hidden until switched on

A VIP account can turn itself into a Page of type Business or Community
(one Page per account, only the owner posts). Backend packages B1-B5 and the app
(C0-C4, below) are in source.

- **Who.** A canonical owner-granted VIP grant only; paid Premium is off in
  code until images are screened, and the staff preview does not count.
  Everything answers `pagesNotEnabled` until an operator writes
  `appConfig/pagesV1` (off / testers / everyone, separately for reading and
  writing).
- **`managePageV1`.** `create` (kind, category from a server list,
  description, public Business contact fields or Community rules + one linked
  public Server the owner runs, an 18+ birth date that is never stored),
  `update` (kind is fixed), `pause` (always works, even muted, unverified or
  with Pages switched off) and `resume`. A Page needs a public profile and a
  name that is not reserved ("YO Voice", VIP, Admin, Support, Pomoc,
  Official, Verified … and check-mark look-alikes), and cannot be created on
  an account that already has followers.
- **Existing settings.** Renaming checks the same name rules while you have a
  Page; making your profile friends-only or private pauses your Page; Creator
  audience cannot be turned on while you have a Page.
- **Badge.** `publicBadges.page` (`business` / `community`) marks a visible
  Page for other people's apps; it authorizes nothing.
- **Follow (B3).** The existing Follow button works on a running Page (the
  same edges as a Creator follow; the owner is notified). A paused,
  suspended, hidden or read-only Page (VIP lapsed) takes no new followers;
  unfollow always works, even with Pages switched off. Three follows of the
  same Page per day at most.
- **Treści feed (B3, `getPagesFeedV1`).** Newest posts of the Pages you
  follow, 20 at a time with "load more", plus up to 10 Page suggestions on
  the first page. Paused, suspended, hidden and blocked Pages never appear.
- **Page profile (B3, `getPageV1`).** Header (name, kind, category,
  description, follower count, post count, "on YO Voice since", Business
  contact fields or Community rules + one linked public Server), your
  Follow / Message options, the pinned post, then the wall or the Zdjęcia
  (photos) tab. The owner sees their own Page in every state, including
  held posts.
- **Post detail (B3, `getPagePostV1`).** One post with its comments, 20 at a
  time; comments from accounts you blocked (or that blocked you) are left
  out.
- **Find Pages (B3, `findPagesV1`).** Suggestions (newest active Pages you
  do not follow), name search (2-60 characters, prefix) and the list of
  Pages you follow (desktop panel). A Page renamed in the last 7 days is
  left out of suggestions and search.
- **Messages (B3, D13).** Following a Page never lets the Page owner message
  you when your setting is "People you follow"; a Page account can start at
  most 10 new conversations with non-friends a day. A Page host's LIVE
  notifies nobody, and a Page account's followers never count toward
  achievements.
- **Posting (B2).** The owner posts text (up to 5000 characters), 1-10
  photos (JPEG only, up to 4 MB each, re-encoded without metadata by the
  app; a photo that still carries Exif/GPS, XMP, ICC or a comment is
  refused, and so is one whose real pixel size is over 8192 a side or is
  not the width and height the app declared) or one voice clip (up to 60 s, 4 MB). Media are reserved first
  (`reservePagePostMediaV1`, 15 minutes, one upload set at a time), uploaded,
  then published (`publishPagePostV1`), which checks the real bytes and
  duration and returns the new post; there is no optimistic post. Daily
  limits per Page: 10 posts, 30 photos or clips, 200 MB; publishing 3 times
  per 10 minutes. A paused or suspended Page cannot post.
- **Managing posts (B2, `managePagePostV1`).** Pin one post to the top of the
  wall, unpin it, turn comments on or off, and delete. Delete always works
  (even muted, unverified or with Pages switched off). A post under a report,
  held or removed by a moderator is kept out of sight as evidence (its photos
  and clip stay while a report on it is open); it is removed with its likes,
  comments and files when the last report is resolved, and never later than
  90 days after the delete. Any other post is removed at once.
- **Photos and clips (B2, `getPagePostMediaAccessV1`).** 90-second links for
  the media of one post the caller may see; moderators can open held,
  removed or deleted posts that were reported, and published posts with an
  open report, and every such view is logged. At most 60 requests a minute, 600 an hour, 3000 a day.
- **Cleanup (B2, `pagesMaintenance`, every 10 minutes).** Abandoned uploads
  are removed after 15 minutes, deleted posts' files and their likes and
  comments are cleared, and once a day unreferenced files older than an hour
  are swept.
- **Likes (B4, `pagePostEngagementV1`).** Anyone who can see a published
  post may like it, also while the Page is read-only (VIP lapsed); unlike
  always works, even after a block. 60 a minute.
- **Comments (B4).** Up to 1000 characters on a published post with
  comments on, while the Page is running (not read-only, paused or
  suspended). No links: web addresses, `www.` and domain-like words
  ("bit.ly/x", "example . com") are refused. 20 a minute and 200 a day;
  accounts younger than 7 days (by their sign-up date) 3 a minute. The
  comment's author and the Page owner can delete it, always (even muted,
  unverified or with Pages switched off). No comment likes in v1.
- **Owner notification (B4).** Each comment by someone else puts "New
  comment on your Page post from {name}" (the name cut at 40 characters) in
  the owner's bell and pushes "{name} commented on your Page post"; the
  existing "Comments and mentions" switch turns the push off. Deleting the
  comment (or its post) removes the bell row. There is no notification for
  new posts in v1.
- **See who liked (B4, `listPagePostLikersV1`).** The ADR-230 VIP list on a
  Page post, behind both the likers switch and the Pages switch, with the
  same privacy rules (hidden likes, private profiles and blocks are never
  listed).
- **When VIP ends (B5).** The Page turns read-only at once (the owner is
  told): the wall and feed stay readable and likes, unlikes, unfollows and
  deletes still work, but there are no new posts, comments or follows and
  the Page leaves Find. On day 23 the owner is told the Page will be hidden
  in 7 days; on day 30 it is hidden (visible only to the owner). Nothing is
  deleted, and the Page is back the moment VIP returns. The VIP rosette
  follows the owner-granted VIP grant, checked with its expiry date.
- **Reporting (B5, `createPageReportV1`).** Anyone can report a Page, a
  Page post or a comment on one (spam, harassment, hate, sexual content,
  violence, self-harm, impersonation, restricted category, scam,
  intellectual property, other), even when the Page blocked them, while
  muted, unverified or with Pages switched off. 10 reports per 10 minutes.
  A reported post is kept as evidence if its owner deletes it, until the
  report is resolved (90 days at most). A report of a whole Page also
  records the text of its newest five posts for the moderator.
- **Moderation (B5).** Staff can remove a post (its files are kept for an
  appeal), hide it while they review it and show it again, remove a
  comment, and suspend a Page or lift the suspension. A hidden post comes
  back by itself when its last report is resolved or dismissed without
  removal; the affected person
  gets a notification that says what happened and why. Until the
  Moderation Center shows Page reports, the owner works them with an
  audited operator script.
- **Deleting your account (B5).** Your Page, your posts and their files,
  and the comments you wrote are deleted. A post with an open report is
  kept out of sight as evidence for at most 90 days, then removed.

### Premium Pages in the app ("Treści") — hidden until `appConfig/pagesV1`

`lib/features/pages/`. A YO Voice VIP can turn their account into a public
Page (Business or Community) and publish to followers. Servers stay the only
shared space; a Page is a one-to-many publishing profile. Everything is
behind the fail-closed `appConfig/pagesV1` switch (`PagesAvailability`):
until the backend enables it, no Treści tab, entry, notification route or
deep link is reachable. The spec and the owner-approved renders live in
`yovoice-evidence/2026-09-28/premium-pages/`.

- **Treści destination.** A sixth dock tab (the whole dock at 90 %) and a
  desktop rail item between Chats and Moments. The wall is a card feed of
  followed Pages with a "Follow more Pages" rail, Find Pages, a desktop
  panel of followed Pages, and a "Create your Page" entry for VIPs without
  one.
- **Page profile.** Cover, Page face, name with the VIP rosette, Follow /
  Message actions, Wall · About · Photos tabs; the owner gets New post, Edit
  Page, and Page settings (pause/resume, contact fields, follower count).
- **Create.** From the Premium screen's "Your Page" block (and the Treści
  entries). An account without VIP gets the honest "Pages" upsell instead of
  the form (`PremiumUpsellContext.pages`): it never offers a purchase while
  billing is not for sale.
- **Composer.** Text, up to 10 photos, or one voice post of up to 60 s, with
  a Comments switch. Photos are decoded, orientation-baked and re-encoded as
  a JPEG with **no metadata** (GPS, EXIF, ICC and comments are gone) in a
  background isolate before upload (`image_sanitizer.dart`); a photo that
  still carries metadata is refused locally. Upload goes reserve → upload
  (per-item progress) → publish, with one request id per attempt so a retry
  never double-posts. Recording stops by itself at 1:00. There is no
  optimistic post: the post appears once the server has accepted it.
  Budget: 10 posts per day; the last three are counted down.
- **Post detail.** The full card and its comment thread, newest first, 20 per
  page. Anyone can like, see likers (VIP, the ADR-230 flow), share, and report
  the post or a comment. Comments are hidden behind a line that says why when
  the owner turned them off or the Page is read-only. The owner can switch
  comments on or off, delete the post, and delete any comment. There are no
  comment hearts.
- **Voice playback.** A voice post is downloaded whole (at most 4 MB) through
  a short-lived grant before it plays, so an expiring link never cuts it off;
  an expired grant is re-requested once. One clip plays at a time across the
  app, and it pauses when Treści is hidden.
- **Notifications.** "{actor} commented on your Page post" opens the post;
  Page moderation and lapse notices come from YO Voice (not a person) and
  open your Page. The comment push follows the existing "Comments" switch.
- **Languages.** Every string is translated in all 43 app languages
  (`translations_pages.dart`, `test/pages_localization_test.dart`), and every
  count uses each language's plural forms.

## Settings

`lib/features/settings/` — Profile, Account, Privacy, Security,
Notifications, Appearance, Language, Blocked users, Devices, Storage,
Permissions, Help, About, Legal, and a Danger Zone. Real, working pieces:
password reset, email-verification resend/refresh, real
microphone/camera/push-notification permission status
(`permission_handler`), real image-cache stats and clearing, real About
(app version via `package_info_plus`) and Legal/Help links (`url_launcher`
→ `yovoice.app`). **Account deletion is self-service as of Build 32**
(`lib/features/settings/presentation/screens/delete_account_screen.dart`,
[ADR-206](Decisions.md#adr-206-a-deletion-promise-is-a-list-of-stages-and-the-copy-may-not-exceed-it)):
the screen states what is removed and what is kept, re-authenticates, and calls
`deleteAccountSelfV1`, which marks the account and hands a staged, leased
teardown of Auth + Firestore + Storage to an outbox worker. The callable is
deployed (2026-09-19) but the server kill switch `appConfig/accountDeletion`
does **not** exist yet, and it is fail-closed, so **what a user actually gets
today is still the pre-filled `privacy@yovoice.app` route** that the screen
keeps as its fallback. The screen ships in build 32; enablement order and
current state are in [DEPLOYMENT.md](DEPLOYMENT.md). Four named categories of
data survive a completed deletion and are disclosed rather than claimed — see
[Bugs.md](Bugs.md). Profile visibility, recipient-controlled direct-message privacy
and authenticator-app two-factor authentication are implemented in source and
covered by responsive/security tests; they require their coordinated Firebase
configuration, Functions/Rules and client rollout before being called live.

The original Settings additions were deployed to the web/PWA client on
2026-08-18 from commit `8fa0192`; the 2026-09-01 language expansion is complete
in source and still requires a coordinated tester release. Appearance and app
language have real device-local contracts. Appearance offers System, Dark and
Light (Pearl). Language offers System plus 43 selectable locale variants:
English, production Polish and 41 additional languages/region variants,
including the requested German, Spanish, Portuguese, Italian, Ukrainian,
Russian, Czech, Slovak and Bulgarian coverage. Portuguese distinguishes
Portugal/Brazil and Chinese distinguishes Simplified/Traditional. Both
preferences persist through `shared_preferences` and update the root
`MaterialApp`. A new installation defaults to System; malformed or unreadable
legacy state falls back to English.
Pearl uses the semantic `AppPalette` across the shell, Home, Chats, Friends,
Moments, Profile, Settings, Notifications and Premium; immersive server
stages, calls,
recording/review and image-led viewers remain deliberately immersive dark
surfaces instead of accidental theme leaks. Polish has graduated from Beta
after the full product-copy pass and source guard. The additional locales own
an exact, placeholder-checked core catalog covering navigation,
authentication, onboarding, Settings and system controls; specialist feature
phrases outside that contract fall back explicitly to English until they
receive editorial translation. Firebase Auth, Android/iOS locale metadata,
localized native permission prompts and the web document language follow the
same resolved locale. These preferences do not create Firestore data and do
not sync between devices. See ADR-136 and ADR-127.

Devices & sessions shows the current Firebase token session and offers one
real remote-security action: account-wide refresh-token revocation followed by
local push-token removal and sign-out. Firebase Auth exposes neither a
trustworthy per-device session list nor individual refresh-token revocation, so
the app does not fabricate one from FCM registrations. The action requires a
verified `auth_time` no older than ten minutes. Already-issued stateless ID
tokens can remain valid for at most about one hour, which the screen states
explicitly. Downloaded audio is managed locally with the Voice Moment limits
and platform behavior described above. See
[ADR-073](Decisions.md#adr-073-firebase-session-management-exposes-account-wide-revocation-never-a-fabricated-device-list).

New accounts receive one optional five-step product tour after authenticated
startup settles. It points at the real YO creation action, Moments, Chats and
More controls on the current mobile or desktop shell; users can skip it at any
time and replay **Quick app tour** from Settings. Completion and Skip are kept
locally per Firebase uid and tour version, so the guide does not add profile
data or interrupt established accounts on a new device. See ADR-132.

### Report a bug (ADR-223, source only, not deployed)

"Report a bug" / "Zgłoś błąd" in Settings > Help, the More sheet and the
desktop More popover, plus a movable "Bug" button for the testing period
(hide it with a long press or Settings > Help > Show the Bug button). The
reporter takes a description, sends the app version, platform, OS, language,
theme, screen size and screen name, and — only after the person previews it
(full size, with zoom) and confirms it — a screenshot. Reports reach only the
owner, in Staff Center > Bug reports, who can also find one account's reports
and delete a report or its screenshot on request.

## Notifications

`lib/features/notifications/` — an in-app notification center with
deep-link tap routing, a preferences screen (per-type push toggles), and
real push delivery via Cloud Function triggers (see
[Backend.md](Backend.md)). Triggered from real friend, eligible Creator
audience, Server invitation/session and message events, not simulated. Native
foreground and background pushes
use an audible high-priority system notification; a focused web tab shows a
compact floating banner with an Open action. Android, iOS and the focused web
app use the same original YO Voice notification motif rather than a generic
system beep; Android uses a versioned notification channel because installed
channel sound settings are immutable.
