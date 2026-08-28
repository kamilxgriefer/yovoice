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

## Verification and release

- Flutter VM: **1407/1407**.
- Firestore Rules: **512/512** against a fresh emulator.
- Cloud Functions: **892/892** against Auth and Firestore emulators.
- Storage Rules: **60/60**; combined Family media: **11/11**.
- Real Chrome audio lifecycle: **1/1**.
- Focused create-room/Podcast/model regression pass: **49/49**.
- `flutter analyze`: clean.
- `flutter build web --release`: successful.
- Visual harness: **55** room frames, including the populated producer queue.

## Production evidence

- Firestore Rules deployed as ruleset
  `projects/yovoice-ec54a/rulesets/c6736f68-dfd8-4489-b3dd-00dd0d3a9f20`;
  the live source is byte-identical to the repository with SHA-256
  `09b5bace9c1522ad5e47a274041184e73f95d84d5ca0901d35b262733198428b`.
- Hosting workflow
  [33188999220](https://github.com/kamilxgriefer/yovoice/actions/runs/33188999220)
  deployed commit `39b320727a450358a5b41a27fe353e2e41b0058e`.
  Its 6,348,593-byte `main.dart.js` is byte-identical on both live origins,
  SHA-256
  `973ad8d8dfdd5870afcbbc4be0bf3cabd62e3b6af13a278ff33058a9b485345c`.
- Build-9 Hosting workflow
  [33192629289](https://github.com/kamilxgriefer/yovoice/actions/runs/33192629289)
  completed successfully from `e2fd878c403466c9bbdd78fff6ab146a8958ad3a`.
  Both live origins remain byte-identical to its `main.dart.js`; their exact
  `version.json` reports `1.0.0 (9)`, SHA-256
  `ea6c149682a1728980b1956fd3a2d582a90a7dff617adc4b20d2683f2aec1fc8`.
- Native release revision `e2fd878c403466c9bbdd78fff6ab146a8958ad3a`
  increments the shared build number to 9 because App Store Connect and Google
  Play had already accepted build 8 before Podcast Studio was archived.
- TestFlight `1.0.0 (9)` passed package analysis, has status **Testing**, and
  is assigned to `YO Voice Internal Testers` with a 90-day testing window. Its
  signed 54,481,227-byte IPA SHA-256 is
  `3702a6c272bcc4570e3f52e5e2ce2bc2c3e9a4a27f5eea2c19488d31ad94a492`.
- Google Play `1.0.0 (9)` is **Available to internal testers**, published on
  2026-08-28 at 18:57 CEST to the selected 11-account list. Its signed
  104,300,235-byte AAB SHA-256 is
  `3168978aeccc856baeda0686b39ba868fc727f98db94da993c51bfeac227944e`.
