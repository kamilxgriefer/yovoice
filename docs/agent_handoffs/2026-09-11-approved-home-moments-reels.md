# Approved Home / Voice Moments / Reels implementation handoff

Owner accepted all three directions on 2026-09-10. This handoff makes that
description implementation-ready; it is not a new visual-approval request or
a claim that the approved screens are already implemented. Use real existing
data/services, not the illustrative people, counts or content in the mockups.

## Shared design and interaction contract

- Material 3, Inter and the current theme remain authoritative. Use
  `AppPalette.surface`, `surfaceRaised`, `border`, `textPrimary`,
  `textSecondary`, `interactiveForeground`, `focus` and paired status colors.
  `AppColors.primary` is the invariant brand accent, not body-copy color.
- Follow `ResponsiveContentFrame`: below 600 use 16 px horizontal gutters;
  600–1099 use 24; 1100+ use 32 within the bounded dashboard/feed slot.
  Root desktop content does not add a second shell-owned app bar.
- Keep the six `AppRhythm` steps (4/8/12/16/24/32), `AppRadius`,
  existing typography and button tokens. Do not add arbitrary large spacers
  or a competing theme. Artwork is subordinate to legible surface layers.
- Retain global bottom navigation and its safe area. Never let actionable
  content sit underneath its raised selection or the active-call capsule.
- All actions have at least 44×44 hit regions, visible focus, meaningful
  labels and keyboard activation. Focus order follows visual reading order.
  Badge/status color alone cannot convey meaning. Respect reduced motion.
- Retain current localization. Reuse existing accurate strings; any new
  strings must be added across the supported catalog before integration.
  Don't solve long translations by clipping a primary action or hiding text.
- Use existing short UI transition tokens. No decorative continuous motion,
  hover rotation, blanket animated layout, or expensive feed-wide blur.
- Rendering and real functionality are separate acceptance gates.

## Home — first implementation slice

### Layout and hierarchy

1. Compact identity header: greeting as secondary copy, current display name
   as the heading, notifications and profile as trailing circular controls.
   Preserve unread count and the availability picker. At narrow width/200%
   text the header may wrap without truncating the user's primary identity.
2. Friends / people: one compact horizontal strip with actual avatars,
   readable names and current availability. Keep the route to all friends and
   a clear add/find-friends entry when empty. Avoid repeating the account's
   identity/status in several large consecutive blocks; preserve its existing
   actions through the header or compact own tile.
3. One clear conversation entry: a genuine featured live room with title,
   actual participant state and an explicit join/open action. It goes through
   the existing prejoin flow; merely displaying or opening Home never joins
   audio or requests microphone permission. With no room, show a purposeful
   compact empty card with Create room and a secondary Friends/Discover route,
   not a blank hero or fabricated activity. Denied/error differs from empty.
4. New content: a concise followed-Moments preview with the existing real
   play/chain action, a record entry and View all. Avoid multiple competing
   previews of the same content on the same first viewport.
5. Preserve recent chats, owned-room management and full room discovery lower
   in the page or in the intentional desktop secondary column. Do not delete
   existing callbacks/features or hide owned rooms during stream remounts.

Phone uses a single vertical reading order. Medium widths stay single-column
until cards retain useful readable widths; wide Home uses a main conversation/
content column and a bounded people/recent-chat secondary column rather than
stretching phone cards. Gaps remain token-based at all widths. Lists/rails keep
stable keys and subscriptions across section growth, refresh and navigation.

### States and edge cases

| State | Required behavior |
| --- | --- |
| Loading | Bounded progress/skeleton in the affected section, no fake names/counts or whole-page spinner |
| Empty | Short actionable invitation to create/find; no dead button or misleading online state |
| Partial failure | Local retry with safe localized message; usable sections stay interactive |
| Permission loss | Remove denied cached content; don't relabel authorization failure as empty |
| Long content | Names/titles wrap where primary; preview ellipses have a reachable full destination |
| Refresh | Preserve stable identity and route state; discard stale async results |
| 200% text | Reflow rows and CTAs, keep primary content and every action reachable |

Reuse current single-flight navigation, privacy-bound avatars and presence
services. No new eager listeners, permission dialogs or network fan-out just
to decorate the redesigned layout. Measure/assert stable listener ownership
and don't attribute perceived latency improvement to spacing changes.

## Voice Moments — following slice

Replace redundant featured/recent presentations with one clear feed of
readable cards. Each has actual author/avatar/time, caption, play/pause,
waveform/progress and duration, likes/comments plus overflow for existing
report/management actions. Discovery/following remains easy to reach without
three stacked rows of large chips. Recording is an obvious distinct action.
This is not a full-screen video feed.

Preserve expiry, author chains, pagination, reactions, existing text/voice
comments, moderation and authenticated grants. Stop/release playback on expiry,
loss of visibility, account change and route exit. Never treat an illustrative
waveform as recording-derived data. Loading/playback error needs a local retry,
and one source should own audible playback. Phone is one-column; wide layout
uses a bounded reading list, not a dense grid of tiny players.

## Reels — following slice

Video fills the available feed width/height above the retained navigation;
remove the large nested header/filter/card stack from that viewport. Keep a
compact overlay with current feed selection and create action. On desktop,
use a centered immersive player with sensible width rather than stretching
portrait media across the workspace; preserve the asset's aspect/crop intent.

Right-side actions are Like, Comments, Share and overflow. Reporting belongs
inside overflow along with only authorized owner actions. Author/caption/audio
information stays above the navigation inset and is not covered by the action
rail. Long captions have a readable expansion. Comments use an adaptive sheet/
panel with usable keyboard space; the underlying video lifecycle is explicit.

Reuse and test the real feed/author scope, pagination, active+neighbor decoder
budget, silent autoplay, feed sound preference, grant expiry and genuine-watch
logic already integrated. Swipe advances one item; background/hidden cards do
not play. Like/comment/share/report must call their real existing authorities,
with appropriate optimistic rollback and single-flight/idempotent behavior.
No duplicated player per sheet, uncontrolled prefetch, fake counters or replay
of stale media after access revocation. Layout alone cannot fix stuttering.

## Verification and handoff

Each slice: author tests and clean analysis, independent QA, real rendered
Dark/Pearl captures, accessibility review and read-only final code review.
Inspect 320/390/430/768/1100/1440 and large desktop where relevant, plus 200%
text, long Polish/English strings, populated/empty/error/loading/denied states,
keyboard and safe areas. Record actual captures and what was inspected.

Keep physical iOS/Android two-account playback, camera/microphone, audio
routing, comments/likes and provider/network checks separate from widget and
emulator evidence. Do not claim a tester release from a passing layout suite.
