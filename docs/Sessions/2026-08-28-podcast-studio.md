# 2026-08-28 — Podcast Studio

The Podcast Room is now its own product surface rather than a recoloured
Community Room. The live screen is organised around an episode hero, the real
stage, an explicit audience state and a host-only producer desk. On desktop the
producer can keep chat or the stage-request queue beside the show; on compact
screens the same controls remain reachable without compressing the stage.

## Product changes

- The episode hero presents the episode topic, show identity, host, format,
  visibility and real on-stage/audience/request counts.
- Hosts get a producer desk and a real request queue with accept and decline
  actions. Listeners see a clear listening, requested or on-stage state.
- Podcast settings now edit the show name, episode topic and description,
  format, guest guidelines, visibility and whether listener stage requests are
  open. Existing advanced room controls remain available.
- Header and dock terminology now says **On stage**, **Audience** and
  **Requests** instead of exposing Community Room language.
- Responsive compositions were inspected at 320, 390, 768, 1100 and 1440 px;
  the producer queue received its own populated desktop frame.

## Data and authority

`VoiceRoom` now reads and preserves the existing Podcast production contract:
`topic`, `audienceCanSpeak`, `handRaisingEnabled` and `stageLimit`. Legacy
documents default safely, including the historical `experience=podcast` value.
Episode metadata has explicit type and length bounds in Firestore Rules.

Stage requests now have one source of truth:
`rooms/{roomId}/participants/{uid}.isHandRaised`. The current client no longer
creates or watches a parallel `handRequests` row. The legacy collection rule is
retained only for already-installed clients until the minimum supported build
can retire it. A listener may lower an old request after the producer closes
the queue; raising is restricted to a live Podcast/Broadcast listener while
requests are enabled. Promotion remains callable-only.

The participant stream remains the authority for all counts. LiveKit speaking
state supplies the speaking indicator; no independent counter or placeholder
identity is fabricated.

## Verification before release

- Flutter VM: **1407/1407**.
- Firestore Rules: **512/512** against a fresh emulator.
- Cloud Functions: **892/892** against Auth and Firestore emulators.
- Storage Rules: **60/60**; combined Family media: **11/11**.
- Real Chrome audio lifecycle: **1/1**.
- Focused create-room/Podcast/model regression pass: **49/49**.
- `flutter analyze`: clean.
- `flutter build web --release`: successful.
- Visual harness: **55** room frames, including the populated producer queue.

Deployment evidence is appended only after Rules readback, the pinned Hosting
workflow and served-artifact fingerprint have completed.
