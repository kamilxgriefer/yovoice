# Slim redesign — phase log — 2026-09-19

Brief: `yovoice-evidence/2026-09-18/slim-redesign-brief.md`. Decision record:
ADR-209 (`docs/Decisions.md`). One flat file for every phase; each phase
appends its own section with the frames directory, the variant matrix, which
frames were looked at, and what is UNVERIFIED and why.

## Phase 0 — summary (consolidated)

**Outcome.** Phase 0 (Fundament) is **done in source** and verified at code
level only. Its **visual gate is open**: no restyled primitive has rendered
after-frames. Nothing was pushed, deployed or published. `pubspec.yaml` is
untouched (`2.0.0+33`); the redesign ships later as `3.0.0+34`. Decision
record: ADR-209, consolidated in this phase's documentation commit, which
also carries this summary.

**Commits on local `main` over Build 33 (`46d6b330`).**

| Commit | Family | What landed |
| --- | --- | --- |
| `f5713426` | live badge | `YoBadge.live` restyled to the brief's spec; 11 ad-hoc pills and `_LiveDot` migrated; `ServerLivePill` became a keyed alias |
| `89c3d2be` | presence dot | `AvailabilityDot` moved to its own file with halo parameters; 10 sites in 8 files migrated |
| `d3552e3d` | waveform | wip commit (verification pending) at the end of the step's budget |
| `2c18fb02` | waveform | finisher: harness fixes in the new test, session log |
| `1c5722a0` | section header | `HomeSectionHeader` moved to `lib/shared/widgets/layout/`, grew slots, and replaced 5 private headings |
| `1d9d85c2` | story tile | one `ringGradient` behind every story shape; the Chats rail lost its fake story ring |
| `f8b8d382` | voice player | `VoicePlayerRow` shared by the chat bubble and the voice-reply mini player |
| `9b639ffb` | channel rows | `YoChannelRow` / `YoVoiceChannelRow` for the panel, the home board and the management sheet |
| `1aad9b47` | new primitives | `YoMetricPill` (2 count pills migrated), `YoServerRailItem` + `YoServerTile` (not yet mounted) |
| `620807ca` | review round | channel-row measure / roster / ring fixes, spoken channel kinds, 2 px focus edges, ADR corrections |

**Tests run.** Every run was bounded (`--concurrency=2`, targeted files). No
test assertion, finder or rhythm number was edited. Where a count was not
retained, the table says so rather than inventing one. The per-family logs
named here were kept in the orchestrating session's scratchpad
(`/private/tmp/…/scratchpad/`), not in git.

| Step | Result |
| --- | --- |
| Baseline (Build 33, live-badge list) | `+605`, all passed |
| live badge | first run `+607 −2`: `content_zoom_responsive_test`, `staff_capabilities_test`. A perpetual pulse kept `pumpAndSettle` from settling. After bounding the pulse: `+609`, all passed |
| presence dot | `+615`, all passed |
| waveform | first run cut off (see below). Finisher: `+791 −4` over 49 files, all four in the new `yo_waveform_test.dart` (harness finders). After the fix, that file passed 7/7 |
| section header | retained run `+646 −3`, all three in the new `home_section_header_slots_test.dart`. The family committed two minutes later, and no log of its green rerun was retained. The committed file passes in the consolidation run below |
| story tile | `+715`, all passed |
| voice player | the commit records the family's 17 pinning files plus `voice_player_row_test.dart` as green; no count retained |
| channel rows | the family reported green; neither the commit nor a retained log records a count |
| new primitives | first run failed two expectations in one of the family's new test files (`hasRunningAnimations`, a focus-action matcher). Those tests were fixed, that file rerun, then the full list rerun green (family report; no count retained) |
| review round | `230 passed, 1 failed` over 14 files: a focus carry-over between theme iterations in the new focus test. After resetting focus, the two primitive files passed 76/76 |
| Consolidation (documentation step, on `620807ca`) | `flutter analyze`: no issues. `flutter test` over the nine primitive contract files (`availability_dot`, `home_section_header_slots`, `moment_seen_avatar`, `voice_player_row`, `yo_badge_live`, `yo_channel_row`, `yo_metric_pill`, `yo_server_rail_item`, `yo_waveform`): **124 passed, 0 failed** |

The full `flutter test` suite was **not** run in phase 0. The brief requires
it at each phase gate, so it remains part of the open gate.

**Aborted and interrupted runs.**

- **Waveform cut-off.** The implementation step's budget ended mid-run. It
  committed `d3552e3d` as `wip(ui): waveform (verification pending)` with the
  run at 223 passed / 0 failed. The retained log shows that the run continued
  to `+734 −5`: the four `yo_waveform_test` harness failures, plus a load
  error in `record_voice_moment_accessibility_test.dart`. It then stopped
  with a shutdown error (`Bad state: Cannot add event while adding stream`).
  The finisher (`2c18fb02`) reran the full 49-file list. Only the four
  harness failures remained, and those were fixed.
- **Usage-limit stop.** The weekly Fable usage limit stopped a step during
  the phase. The run records do not show which step it interrupted.
  Apart from the waveform wip commit, which has its finisher `2c18fb02`, no
  family commit is partial.
- **Model switch to Opus.** From the voice-player step (`f8b8d382`) onward,
  steps ran on Opus 5 (1M context), per the owner's instruction to change
  models when Fable hits its limit. `f8b8d382` and `9b639ffb` still carry the
  `Claude Fable 5.1` trailer that their step text required. They were left
  alone because history may not be rewritten. `1aad9b47`, `620807ca` and
  this documentation commit carry the Opus 5 trailer.

**UNVERIFIED, and why.**

- **All nine primitives have no rendered after-frames**, on any host, at any
  width, in either theme. These are the live badge, presence dot, waveform,
  section header, story ring, `VoicePlayerRow`, `YoChannelRow`, `YoMetricPill`
  and `YoServerRailItem`. This follows from the step rules: implementation
  steps ran no screenshot harnesses, and the machine is shared, so a step
  never ran two Flutter processes at once. Every visible normalisation listed
  in ADR-209 is therefore a specification, not an observation.
- **The only frames are "before" frames.**
  `yovoice-evidence/2026-09-19/slim-0-waveform-frames/before/` holds 92
  Build 33 PNGs from `test/desktop_screenshot.dart`,
  `test/moments_discovery_screenshot.dart` and
  `test/home_light_theme_screenshot.dart`. `after/` is empty, and
  `test/waveform_screenshot.dart` has not been run.
- **Two harnesses cannot render some host frames at all**, even on the clean
  Build 33 tree: the `desktop_screenshot` `roster-*` cases and the
  `moments_discovery_screenshot` story-viewer and loading cases
  (`docs/Bugs.md`).
- **The channel-row frames matter most.** The review predicted the measure,
  overflow and jitter defects from the code, and `620807ca` fixed them in the
  code only. They should be the first frames taken.
- **Gate matrix, an open question for the owner.** The brief's lighter
  verification mode (390 / 768 / 1440, pl, one en control frame) is written
  for phases 1–7. The brief does not say whether phase 0's after-frames may
  use it, or need the original 320–2560 × pl/en matrix.

**Integration note.** Local `main` is 11 commits ahead of `origin/main`,
counting the documentation commit. `origin/main` carries `b6dbc516` ("docs:
record the Build 33 polish release"), which local `main` does not have. That
commit touches `docs/Roadmap.md` at the top of the file and adds
`docs/DEPLOYMENT.md` and `docs/Sessions/2026-09-19-build-33-release.md`,
while phase 0 edits the Roadmap's In Progress section. Pushing therefore
needs a merge first, done by the release or integration step, not by a
phase-0 step.

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
