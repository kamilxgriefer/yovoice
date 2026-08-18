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

Both: host/speaker/listener roles, live participant management, real-time
audio via LiveKit (see [Backend.md](Backend.md) for token minting).
Publish permission (`canPublish`) is computed server-side from the
caller's actual participant role — never trusted from the client.
Meaningful voice actions have original, short YO Voice cues: room creation,
the local join/leave transition, remote participant join/leave, and confirmed
microphone mute/unmute. The cues are throttled during bursts and can be turned
off with the device-local **Sound effects** setting.

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

Home surfaces the three most recently updated non-archived direct
conversations as `Your recent chats`. Global Chat is retired from the app
UI; its existing backend data remains compatibility-only for older clients
and historical moderation records.

## Voice Moments

Short (≤60s) recorded audio posts (`lib/features/moments/`): likes,
comments including voice replies, a public feed
(`MomentService.watchPublishedMoments`) and a per-user feed
(`MomentService.watchMyMoments`, published + drafts) used by Creator
Studio. Like/comment counters are transactionally validated against the
actual `likes` subcollection — not client-settable to an arbitrary value.

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
- **Pinned post** lets an eligible Premium Creator select exactly one of
  their canonical published Voice Moments. The server-owned pointer is shown
  on both the Creator's own and public profile and is removed when the Moment,
  Creator identity or Premium entitlement stops being eligible.

Monetization remains unbuilt and is intentionally absent from the Studio UI.

## Premium entitlements

`entitlements/{uid}` is the only paid-access source. A capability requires an
active/trialing/grace subscription whose period has not ended, the common
`premiumIdentityEnabled` flag and its feature flag (`creatorEnabled` or
`canCreateClubs`). `users/{uid}.premiumIdentity` and the visible VIP badge are
public presentation data only; neither authorizes Creator, Creator Studio or
Clubs. Client gates fail closed and Firestore Rules enforce protected writes.

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
Appearance offers System, Dark and Light Beta; Language offers System, English
and Polish Beta. Both persist through `shared_preferences`, update the root
`MaterialApp`, and fall back to Dark/English when stored state is missing,
malformed or unavailable so legacy installs do not enter a Beta implicitly.
The Beta labels are material: the shared
theme, navigation, authentication, Settings and framework controls participate,
while legacy screens with inline dark colors or English literals are still
being migrated. These preferences do not create Firestore data and do not sync
between devices. See
[ADR-072](Decisions.md#adr-072-appearance-and-ui-language-are-device-local-preferences-with-explicit-beta-boundaries).

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
