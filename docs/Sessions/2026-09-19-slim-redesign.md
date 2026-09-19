# Slim redesign — phase log — 2026-09-19

Brief: `yovoice-evidence/2026-09-18/slim-redesign-brief.md`. Decision record:
ADR-209 (`docs/Decisions.md`). One flat file for every phase; each phase
appends its own section with the frames directory, the variant matrix, which
frames were looked at, and what is UNVERIFIED and why.

## Phase 0 — foundation, family "waveform"

**What changed.** `lib/shared/widgets/waveform/` (empty, untracked until now)
holds `YoWaveform` + its `StoryWaveform` subclass. Migrated: the Start hero's
motif (`home_here_now_hero.dart`; `home_static_waveform.dart` removed), the
legacy Home Moment row (`home_screen.dart`, unmounted), `MomentCard`'s play
row, the story stage / Moment detail / feed transport / voice reply players
(`StoryWaveform` moved out of `moment_story_viewer.dart`, re-exported), the
podcast stage's speaking mark (`server_podcast_stage.dart`, key and
`isSpeaking` gate kept) and the voice message bubble's bars
(`message_bubble.dart`; the duration-seeded per-message shape is retired).
Not migrated on purpose: `_WaveformBadge` / `_ContentBadge` (glyph badges),
`RoomEnergyWave`, `_LevelMeter`, `VoiceCore` (real amplitude). Details and
every visible normalisation: ADR-209, "waveform family".

**Code verification (finisher, after the implementation commit).** `flutter
analyze` clean. One bounded `flutter test --concurrency=2` over the family's
44 targeted files plus `yo_waveform_test.dart`,
`direct_media_fullscreen_viewer_test.dart`,
`direct_video_audio_playback_test.dart`, `home_record_moment_card_test.dart`
and `room_link_message_card_test.dart` (49 files): 791 passed, 4 failed, all
four in the new `test/yo_waveform_test.dart` and all four harness bugs in that
new file, not widget defects: three whole-tree finders also matched the
harness `MaterialApp`'s debug `Banner` (a `CustomPaint`) and the route's
`ModalBarrier` (an `ExcludeSemantics`), and `find.byType(YoWaveform)` can
never match the `StoryWaveform` subclass (`byType` is exact `runtimeType`).
Fix: the finders are scoped to the `YoWaveform` subtree and the subclass
assertion uses `find.bySubtype<YoWaveform>()`; no expected value changed. The
file then passes 7/7; no `lib/` change was needed.

**Frames.** `yovoice-evidence/2026-09-19/slim-0-waveform-frames/{before,after}/`.
`before/` holds the Build 33 run of the existing harnesses
(`test/desktop_screenshot.dart`, `test/moments_discovery_screenshot.dart`,
`test/home_light_theme_screenshot.dart`). `after/` is EMPTY at the time of the
implementation commit: the implementation step does not capture screenshots;
the visual verification step produces them. What that step must produce and
look at, same matrix as `before/`:

- Primitive-level (after only; the private copies could not be mounted alone):
  `waveform-{dark,pearl}-{ltr,rtl}-600.png` from
  `flutter test test/waveform_screenshot.dart` — every host configuration in
  one column (hero ramp 13, Home row ramp 24, MomentCard 30 bars, bubble 24
  pill bars, podcast five-bar mark, story flex at 0 / .4 / 1, Moment detail
  tiled 4/4 at 0 / .4 / 1, feed transport 3/3, voice reply 2/3), Dark and
  Pearl, LTR and RTL. PENDING: not yet rendered or looked at.
- Host-level before/after from the three harnesses above:
  `moment-detail-390*.png` (Moment detail, tiled `StoryWaveform` with the
  audio-progress gradient) is the frame that shows a migrated host; the rest
  of both sets are regression context (Start, Chats, sidebar) and must be
  diffed against `before/` for unintended change. PENDING.

**UNVERIFIED (host-level), with reason.**

- Start hero portrait cluster (its waveform motif): `desktop_screenshot.dart`
  `roster-*` cases fail on the clean tree before any frame
  (`Bad state: Stream has already been listened to`, `HomePeopleStrip`,
  `docs/Bugs.md`). The motif is verified at primitive level only; its exact
  58 % / 42 % proportions are preserved by construction (`barGap:
  waveWidth / 13 * .42`) and `test/home_here_now_hero_test.dart` still holds.
- Story stage: `moments_discovery_screenshot.dart` story-viewer cases fail on
  the clean tree before any frame (same class of fixture failure). Verified at
  primitive level (flex layout at 0 / .4 / 1) and by
  `test/moment_position_single_source_test.dart`.
- Chats voice bubble, `MomentCard` in the Moment sheet, the podcast stage's
  speaking mark: no screenshot harness mounts them. Verified at primitive
  level and by `test/message_bubble_media_state_test.dart`,
  `test/creator_pinned_posts_test.dart`, `test/server_podcast_test.dart`.
- Text scale 2.0, pl/en: the primitive draws no text; not applicable.

## Phase 0 — review round (all families)

**What changed.** The confirmed findings of the phase-0 review, most severe
first. `YoVoiceChannelRow`: the name keeps at least `minLabelWidth` (96 px at
1.0 text) — below 288 px of row (scaled) the `NA ŻYWO` marker moves under the
name beside the clock, and the join control rides beside a live marker only
from 340 px (before: a live name was 3.4 px wide in the 240 px desktop panel).
The connected roster fits the faces to the width and folds the rest into
`+n` (before: 10–48 px overflow in the 216 / 240 px columns), and the ring is
always 2 px so a speaking tick no longer resizes a face. `YoChannelRow` and
`VoicePlayerRow` draw a 2 px focus edge. Every channel glyph in the panel and
the management sheet voices its kind. `docs/Decisions.md`: the voice-player
"consciously not built" list moved out of ADR-001 into ADR-209, the ring's
ADR cited as ADR-155, the stale Consequences bullet rewritten.

**Code verification.** `flutter analyze` clean. One bounded `flutter test
--concurrency=2` over 14 files (`yo_channel_row`, `voice_player_row`,
`server_workspace`, `server_shell`, `server_review_fixes`,
`server_creation_gate`, `server_creation`, `voice_reply_mini_player`,
`message_bubble_media_state`, `message_bubble_overflow`,
`accessibility_context_action`, `localization_source_guard`,
`shared_media_screen`, `moments_semantics_activation`): 230 passed, 1 failed —
a test-harness bug in the new focus test (focus carried over between the two
theme iterations of one test); the test now resets focus between iterations,
no expected value changed, and the two primitive files then pass 76/76.

**Frames.** NONE captured in this round: implementation steps do not run
screenshot harnesses. **UNVERIFIED, all nine families** — live badge, presence
dot, waveform (its `after/` is still empty), section header, story ring,
`VoicePlayerRow`, `YoChannelRow`, `YoMetricPill`, `YoServerRailItem` — have no
after-frames. The phase-0 gate of the brief (after-frames at 320–2560, Dark
and Pearl, 1.0 and 2.0 text, pl and en, per family in
`yovoice-evidence/2026-09-19/slim-0-<family>-frames/`) is **not met**, and
phase 1 must not start until a visual verification step produces and looks
at them. The channel-row frames should be taken on this round's tree, since
they are the ones the review predicted would show the measure and overflow
defects.
