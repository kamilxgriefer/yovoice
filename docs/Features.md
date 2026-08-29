# Features

What's actually built, feature by feature — not aspirational. "Coming
soon" markers below match what the app itself shows the user; see
[Roadmap.md](Roadmap.md) for planned work and priority order.

## Voice Rooms

Two room types, sharing a moderation model but with distinct visual
languages and interaction patterns:

- **Community Room** (`lib/features/rooms/presentation/screens/community_voice_room_screen.dart`)
  — cosmic animated background with orbit rings, a "Heart of the
  Community" core that reacts live to the LiveKit room's energy, orbiting
  participants with a speaking glow, no raise-hand action. Clickable
  Speaking/Listeners counters open a participant list. Owner moderation:
  mute/unmute and remove — removal disconnects the user the moment their
  participant document disappears, and a moderator's mute is synced to the
  target's local microphone, not just a Firestore flag.
- **Broadcast Room** (`lib/features/rooms/presentation/screens/broadcast_room/`)
  — red stage-and-audience visual system, a raise-hand queue, host
  speaker invitations. Same clickable-counters/participant-sheet pattern.
  Owner moderation: mute, move-to-audience, and remove.

**Going live** (source `b0f1062`, **not yet released** — this is the state of
the repository, not of production): `createLiveKitToken` refuses a token
unless the room says status active and `isLive` true, and **entering a room
performs that transition** for anyone the deployed rules would accept, through
one coordinator running liveness → roster → token. There is no lobby and no
second tap: the room board labels a dormant room's button "Start", and the
screen renders a stage, a live status line and a microphone the moment it
opens. Exposure is host-opt-in — `membersCanStartVoice` defaults false, so
only the host starts an ordinary room; Club and Family lounges are private and
auto-started. Someone without authority sees a "Not live" state that explains
itself on tap, with chat and People intact. Legacy room documents are
tolerated by design (most production rooms predate these fields), so every
read defaults rather than raising. **Until this ships, voice does not work in
any Community room or lounge**, and did not for the product's life — see
[ADR-088](Decisions.md#adr-088-entering-a-room-performs-the-liveness-transition-through-one-ordered-coordinator-that-mirrors-the-deployed-rule).

Both: host/speaker/listener roles, live participant management, real-time
audio via LiveKit (see [Backend.md](Backend.md) for token minting).
Publish permission (`canPublish`) is computed server-side from the
caller's actual participant role — never trusted from the client.
Meaningful voice actions have original, short YO Voice cues: room creation,
the local join/leave transition, remote participant join/leave, and confirmed
microphone mute/unmute. The cues are throttled during bursts and can be turned
off with the device-local **Sound effects** setting. ADR-116 replaces the
melodic cues with the non-musical Velvet Prism material system;
room creation consumes its immediate join confirmation instead of producing a
two-cue jingle. The v3 pack is live on Hosting; native build `+4`, physical
listening and the FCM payload cutover remain held. User speech, Voice Moments
and voice messages are media and are deliberately outside this effects system.

**Legacy note**: room documents may still contain `experience: 'podcast'`
from before the room-type rename; the client maps that to `broadcast` for
backward compatibility. Do not remove that mapping until production data
is confirmed migrated — see
[ADR-001](Decisions.md#adr-001-legacy-podcast-room-experience-stays-supported).

## Profile

`lib/features/profile/` — editable identity/media, account type and real
activity counters. `Your YO Voice journey` presents Communities, Messages,
Voice time and Rooms created as one compact four-row list with intrinsic
height, so desktop width no longer turns four short metrics into oversized
cards. Changing a Personal profile into Creator requires the trusted Creator
capability and is checked again on Save; an existing Creator profile and its
content are not erased when Premium expires.

## Clubs

Persistent communities (`lib/features/clubs/`): channels (chat + voice),
member roles (`owner`/`coOwner`/regular member, ranked by
`clubRolePower()`), invites, self-service ownership transfer
(`transferClubOwnershipSelf` Cloud Function). Club rosters are readable by
members; role changes are power-ranked so a `coOwner` can't promote someone
above their own level or touch the `owner` role directly.

The More → Clubs hub and ordinary Club creation require the trusted Clubs
capability. This is not a membership paywall: existing club membership,
invites and direct participation remain free. Family Rooms use the same Club
primitives but keep their separate free, invite-only, deterministic-id path.
Creation is one atomic seven-document batch (Club, owner member, user
projection, three default channels and lounge room); rules validate the new
root with `getAfter()` so the dependent writes see the same commit.

**Club chat moderation** (source `b3c27fd`/`f817b41`, **not yet released**):
a club owner, admin or moderator can remove another member's message from
club chat; an author can retract their own. Removal freezes content to empty
and records `deletedBy`/`deletedAt`; **editing is not available to anyone**,
by construction rather than by convention. The action is offered only where it
would succeed — a moderator who is communication-muted or whose email is
unverified is not shown it, matching what the rules would answer, and the
club owner's own messages are refused locally with product copy rather than a
round-trip. Removals are **not** audit-logged today, there is no rate limit,
no restore path, and no rank ordering (a moderator can clear a co-owner's
messages) — all four named as accepted gaps. Not yet rendered and reviewed;
see [Bugs.md](Bugs.md#moderation--safety).

## Friends & Social

`lib/features/friends/`: friend requests (must exist before a friendship
record can be created — no forcing a friendship via direct write), a
social graph of `following`/`followers` (separate from friends), blocking,
plus two Cloud Functions for discovery: `getMutualFriends` and
`getFriendSuggestions`.

## Messages

Direct messages (`conversations/{id}/messages`) and club channel chat
(`clubs/{clubId}/channels/{channelId}/messages`) — `lib/features/messages/`
and `lib/features/chats/`.

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

## Voice Moments

Short (≤60s) recorded audio posts (`lib/features/moments/`): likes,
comments including voice replies, a public feed
(`MomentService.watchPublishedMoments`) and a per-user feed
(`MomentService.watchMyMoments`, published + drafts) used by Creator
Studio. Like/comment counters are transactionally validated against the
actual `likes` subcollection — not client-settable to an arbitrary value.

**Moments is a primary destination** (source `cef05e6`, deployed
2026-08-20): it sits directly above Discover in the desktop rail and takes a
slot in the mobile dock, which displaced Friends from the five-slot dock —
Friends keeps its desktop rail entry, its More entry, its screen and its state.
The screen behind it is a global discovery feed showing
Moments from every user rather than only people you follow: a bounded popular
pool weighted by engagement, shuffled under a held seed so paging stays
stable, with authors spaced apart. Ranking happens client-side because
Firestore can neither order by a computed sum nor randomise server-side. See
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
across 10 metrics — messages, followers, voice minutes, rooms,
communities, friends, reactions, host minutes, active days, moments — each
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
rooms, clubs, and Voice Moments, with quick actions into the existing
create-room/create-club/record-moment flows and a share-based invite flow.
Creator Studio requires the trusted Creator capability; More shows the locked
state to free users and the destination independently rechecks entitlement,
including expiry while it is open.

The Studio now includes two working tools:

- **Analytics** is an honest snapshot of already-canonical data: followers,
  owned/live rooms and current participant counters, owned clubs, and
  published Voice Moment likes/comments/audio duration. It does not claim
  historical reach, listens, growth or attendance because no such event
  model exists yet.
- **Pinned post** lets an eligible Creator select exactly one of their
  canonical published Voice Moments. Eligibility can come from a live paid
  Creator entitlement or the derived moderator preview. The server-owned
  pointer is shown on both the Creator's own and public profile and is removed
  when the Moment or effective Creator access stops being eligible.

Monetization remains unbuilt and is intentionally absent from the Studio UI.

## Premium entitlements

`entitlements/{uid}` is the only **paid-access** source. A paid capability
requires an active/trialing/grace entitlement whose period has not ended, the
common `premiumIdentityEnabled` flag and its feature flag (`creatorEnabled` or
`canCreateClubs`). `users/{uid}.premiumIdentity` and the visible VIP badge are
public presentation data only; neither authorizes Creator, Creator Studio or
Clubs. Client gates fail closed and Firestore Rules enforce protected writes.

Active `moderator` and `superModerator` accounts also receive a derived,
revocable Premium-preview overlay so those roles can test identity, Creator
and Clubs. It is kept in a separate client/model flag and server access
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

The following Settings additions were deployed to the web/PWA client on
2026-08-18 from commit `8fa0192`; native stores require their own signed
release. Appearance and app language have real device-local contracts.
Appearance offers System, Dark and Light (Pearl); Language offers System, English
and Polish Beta. Both persist through `shared_preferences`, update the root
`MaterialApp`, and fall back to Dark/English when stored state is missing,
malformed or unavailable so legacy installs do not enter a Beta implicitly.
Pearl uses the semantic `AppPalette` across the shell, Home, Chats, Friends,
Moments, Profile, Settings, Notifications and Premium; voice rooms, calls,
recording/review and image-led viewers remain deliberately immersive dark
surfaces instead of accidental theme leaks. Polish remains explicitly Beta
because product copy is not yet fully localized. These preferences do not
create Firestore data and do not sync between devices. See ADR-072 and ADR-127.

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
real push delivery via the `onNotificationCreated` Cloud Function trigger
(see [Backend.md](Backend.md)). Triggered from real friend/follow/club/
room/message events, not simulated. Native foreground and background pushes
use an audible high-priority system notification; a focused web tab shows a
compact floating banner with an Open action. Android, iOS and the focused web
app use the same original YO Voice notification motif rather than a generic
system beep; Android uses a versioned notification channel because installed
channel sound settings are immutable.
