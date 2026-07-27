# YoVoice Rooms rebuild

## Stage 1 — completed

- Canonical room experiences are now `community` and `broadcast`.
- Existing Firestore documents containing `experience: podcast` remain supported.
- New and updated rooms write `experience: broadcast`.
- A dedicated `BroadcastRoomScreen` entry point was introduced.
- User-facing creation and selection labels now say Broadcast Room.

## Stage 2 — Community Room

- cosmic animated background
- Heart of the Community core
- orbital speakers and listeners
- no raise-hand action
- clickable participant counters and participant sheet
- owner moderation: mute and remove

## Stage 3 — Broadcast Room

- red stage-and-audience visual system
- raise-hand queue
- host speaker invitations
- clickable participant counters and participant sheet
- owner moderation: mute, move to audience and remove

## Compatibility rule

Do not delete support for the legacy Firestore value `podcast` until all
production room documents have been migrated to `broadcast`.
