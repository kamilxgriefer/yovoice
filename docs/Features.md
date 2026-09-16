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
`adminSetPremiumEntitlements` admin path can issue a working grant.

## Settings

`lib/features/settings/` — Profile, Account, Privacy, Security,
Notifications, Appearance, Language, Blocked users, Devices, Storage,
Permissions, Help, About, Legal, and a Danger Zone. Real, working pieces:
password reset, email-verification resend/refresh, real
microphone/camera/push-notification permission status
(`permission_handler`), real image-cache stats and clearing, real About
(app version via `package_info_plus`) and Legal/Help links (`url_launcher`
→ `yovoice.app`). Account deletion routes to a real pre-filled support
email rather than a self-service delete, since that needs a dedicated
Cloud Function to clean up Auth + Firestore + Storage together — not
built yet. Profile visibility, recipient-controlled direct-message privacy
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
