> **Archived — historical design/implementation plan.** Stages 1–3 below are
> complete and describe how the two current room types (`community`,
> `broadcast`) came to look and behave the way they do. The one item that's
> still a **live, active constraint** — the `podcast` compatibility rule at
> the bottom — is also carried forward into
> [Decisions.md](../Decisions.md) and [Firebase.md](../Firebase.md) so it
> stays visible without anyone needing to open this file. A feature summary
> lives in [Features.md](../Features.md). Originally two documents
> (`ROOMS_REBUILD_PLAN.md` + `STAGE_2_COMMUNITY_ROOM.md`); merged here
> during the documentation audit since both described the same feature.

# YoVoice Rooms rebuild

## Stage 1 — completed

- Canonical room experiences are now `community` and `broadcast`.
- Existing Firestore documents containing `experience: podcast` remain supported.
- New and updated rooms write `experience: broadcast`.
- A dedicated `BroadcastRoomScreen` entry point was introduced.
- User-facing creation and selection labels now say Broadcast Room.

## Stage 2 — Community Room

- dedicated Community voice screen, with an animated cosmic background and
  orbit rings
- "Heart of the Community" core, reacting live to the LiveKit room's energy
- orbiting participants with a speaking glow
- no raise-hand action
- clickable Speaking/Listeners counters, opening a participant list
- owner moderation: mute/unmute and remove — removed users are
  disconnected the moment their participant document disappears, and a
  moderator's mute is synchronized to the target's local microphone (not
  just a Firestore flag with no client-side effect)

## Stage 3 — Broadcast Room

- red stage-and-audience visual system
- raise-hand queue
- host speaker invitations
- clickable participant counters and participant sheet
- owner moderation: mute, move to audience and remove

## Compatibility rule

Do not delete support for the legacy Firestore value `podcast` until all
production room documents have been migrated to `broadcast`.
