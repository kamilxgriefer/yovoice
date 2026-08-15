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

**Legacy note**: room documents may still contain `experience: 'podcast'`
from before the room-type rename; the client maps that to `broadcast` for
backward compatibility. Do not remove that mapping until production data
is confirmed migrated — see
[ADR-001](Decisions.md#adr-001-legacy-podcast-room-experience-stays-supported).

## Clubs

Persistent communities (`lib/features/clubs/`): channels (chat + voice),
member roles (`owner`/`coOwner`/regular member, ranked by
`clubRolePower()`), invites, self-service ownership transfer
(`transferClubOwnershipSelf` Cloud Function). Club rosters are readable by
members; role changes are power-ranked so a `coOwner` can't promote someone
above their own level or touch the `owner` role directly.

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
**Analytics, monetization, and audience-growth charts are intentionally
not built** — shown as visible, disabled "Coming soon" cards rather than
hidden or faked.

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
built yet. Not real yet, shown disabled: two-factor auth, profile
visibility/message-privacy controls, multi-device session management, app
UI language switching.

## Notifications

`lib/features/notifications/` — an in-app notification center with
deep-link tap routing, a preferences screen (per-type push toggles), and
real push delivery via the `onNotificationCreated` Cloud Function trigger
(see [Backend.md](Backend.md)). Triggered from real friend/follow/club/
room/message events, not simulated.
