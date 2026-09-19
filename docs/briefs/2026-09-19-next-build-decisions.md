# Next build after 3.0.0: tasks, decisions, split (2026-09-19)

Full read-only investigation (current state with file:line, designs, backend changes, tests, risks) for all tasks:
`docs/briefs/2026-09-19-next-build-investigation.json` on this branch. Base = origin/main (3.0.0+34).

## Decisions taken (defaults; Kamil can override)
- T1 Yeels scrub: fade the overlay chrome while scrubbing (none under reduced motion); add the same finger-seek to the Voice
  full-screen story player waveform (transparent-slider pattern); segmented bars stay previous/next navigation.
- T2a Server messaging: "reactions" = emoji reactions on channel messages, DM style (one reaction per person from the fixed
  six, map on the message). Members may react in announcement/rules channels; guests may not. Photos and videos in server
  channels with the full design from the investigation (Storage path, reservation/finalize/access callables, moderation
  and cleanup). Emoji input stays in the composer; fix its disappearance where the investigation found it.
- T2b Stuck LIVE: end the channel session when the last participant leaves, after a short reconnect grace (~60 s),
  server-authoritative (release callable on leave + room_finished webhook + tighter stale sweep); idempotent dry-run-first
  repair script for existing stale flags. LiveKit webhook registration is Kamil's action (dashboard).
- T3 Friend profile quick actions: Zadzwoń (voice), Wideo, Wiadomość, Więcej (voice message, invite to server, block,
  report). Only real backend paths enabled; relationship/privacy checks as in the investigation.
- T4 Confirm before upload: library picks only (camera flows keep their own OS confirm), one item per pick, no caption
  in this build (DM attachments have no caption field); one shared confirm sheet adopted by every immediate-send site.

## Split
- Mac: T1, T3, T4 (app only) on branches nb/yeels-scrub, nb/friend-actions, nb/confirm-upload.
- PC: T2a and T2b (Functions, rules, emulator tests, app UI for reactions/media) on branches nb/server-messaging and
  nb/server-live. Push each branch and a tag nb-<key>-ready when green. Never push main, never deploy: deploys
  (Functions, Storage rules, Firestore rules, in the order from the investigation) happen at release time with the
  release session.

## Rules (same as 3.0.0)
Never remove functionality; never edit test assertions to go green; additive schema only; rules changes need emulator
tests; no new inline hex; Material 3; no pubspec, dock or MainShell navigation edits; no localization catalog changes
without entries for all locales; commits end with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
