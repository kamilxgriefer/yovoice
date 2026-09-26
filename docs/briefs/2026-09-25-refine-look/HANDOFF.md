# refine/look: handoff to continue on another computer

Written 2026-09-26 12:40 CEST by the Mac session "YO Voice testowa aktualizacja". Kamil asked to move this work to the computer he is using: "przenieś pracę tutaj na ten komputer". The Mac rollout is **stopped**, so nothing else writes to this branch.

## What this is

Kamil's instruction is to polish the existing 3.0.0 look without redesigning it: "simple, but super wow", using the real glossy logo.

- The spec is [`spec.md`](spec.md). It is the source of truth for every value. Its sections cover the recipes (R1–R17), the logo plan, the four signature moments (W1–W4), tokens, primitives, per-screen changes, batches and the verification matrix.
- The four files that the other session released to this work are in [`handoff-notes.md`](handoff-notes.md). It lists the tests and behaviour pinned in them.
- The partial Servers diff from before the rebase is [`b4-wip.patch`](b4-wip.patch). Use it as a reference only, because main changed the servers files since.
- The Mac orchestration script is [`rollout-workflow.js`](rollout-workflow.js). It is a Claude Code Workflow script with Mac paths; adapt the paths before reusing it.

## Kamil's decisions (verbatim where it matters)

1. **Direction.** "ja bym po prostu ulepszył to co już istnieje, i pamiętaj aby używać też obecnego logo". Later: "afterglow … fajnie wygląda jeśli chodzi o delikatny design klocków i ich wykończenia ale ogólnie zrobiłbym coś jednocześnie prostego ale z drugiej strony super wow".
2. **Samples first.** "pamiętaj aby pokazać mi próbki zanim cokolwiek zaczniesz zmieniać". This was done: he saw the primitives sheet and Start before and after.
3. **Waveform variant B.** The played sweep is the logo's violet → magenta, implemented as `AppGradients.voicePlayed` with Dark `waveUnplayed` at .22.
4. **Approval.** "widzę, że dobrze to będzie wyglądać, wprowadź wszystko gdy skończysz i gdy zakończy się praca w redesign yovoice aplikacji, **pamiętaj aby nie ruszać graficznie paska nawigacyjnego**". The navigation dock and the desktop rail must stay pixel-identical. Verify that after every batch with `test/dock_visual_qa_screenshot.dart` and `test/desktop_sidebar_screenshot.dart`: the dock PNGs must match byte for byte, and in the rail frames columns 0..263 must be identical.

## Branch state

`refine/look` is rebased onto origin/main `3445a1ae` (build 36, 3.1.0+36, plus the keep-warm fix). `flutter analyze` is clean on it.

| Commit | Content |
|---|---|
| afda4d62 | B1 foundations (tokens, `AppFinish`, primitives, the real logo `YoBrandMark`, `logo-bloom.png`) + B2 Start pilot |
| b63ae6f8 | Review round for Start and the sample sheet |
| 5e218c91 | Waveform variant B keeps the logo violet → magenta in Dark |
| 869c14e9 | B3 shared controls (chip/card hairlines, gradient `YoButton`, search pill, badge borders, high-contrast theme twins) |
| (next) | WIP: `test/refine_controls_capture.dart` repair for B3 real-screen evidence |

## Remaining work, in order

1. **B3 evidence.** Render real screens that use the new controls (Settings, Friends filter chips, search and "Dodaj", notification preferences, one `YoButton` primary). Use 390 and 1440 px, Dark and Pearl, 100 % and 200 % text, plus one high-contrast frame. The harness `test/refine_controls_capture.dart` was being repaired; check it first.
2. **B4 Servers** (spec §8.2). Re-implement it on the current code.
3. **B5 Voice bead and Głos** (W3).
4. **B6 Capture and Yeels** (W4).
5. **B7 Chats.**
6. **B8 Profile.**
7. **B9 More, Settings, Friends and Notifications.**
8. **B10 Auth and Startup** (W1 rest).
9. **B12 Handoff files:** `profile_header.dart`, the `AuthPrimaryButton` in `responsive_auth_screen.dart`, `yo_segmented_pill.dart` and `yo_channel_row.dart`. Follow `handoff-notes.md`. `yo_server_rail_item.dart` stays **untouched**.
10. **B11 Docs.** Write ADR-211, superseding ADR-209's card, bubble and type rules, and update Roadmap, Bugs and UI.md. Add a `docs/Sessions/` entry.

**Per batch:**
1. Implement the code, then run targeted tests and `flutter analyze`.
2. Capture the after-frames with the area's `test/slim_*_capture.dart` harness (see the §10 table) and compare them with before-frames taken from build 36.
3. Run a visual review and an accessibility review, fix what they find, and re-check.
4. Check dock/rail parity.
5. Commit.

Subagents never commit (AGENTS.md); the main session commits.

## Hard rules for this work

- Never edit the dock, `desktop_sidebar.dart` or `yo_server_rail_item.dart`.
- Do not edit `responsive_content_frame.dart`, `profile_banner.dart`, `profile_hero_backdrop.dart`, `profile_media_image.dart`, `profile_photo_viewer.dart`, `profile_preview_sheet.dart`, `accessible_tap_region.dart`, `yo_modal_sheet_chrome.dart` or `yo_recording_countdown.dart`. Callers may pass arguments to them.
- Keep every feature, key, semantics label and Polish string. No fake data. Material 3 and Inter only. Colours come only from `app_colors`, `app_palette` and `app_finish` tokens.
- Never weaken a test.
- No deploys: this work is client-only.

## Landing (Kamil's condition is met: build 36 is done)

1. Fetch, then rebase `refine/look` onto the current `origin/main`. **main requires linear history**, so rebase or squash; a merge commit is refused with GH013.
2. Run `flutter analyze`, the **full** `flutter test` suite and dock/rail parity, then push to main and watch GitHub Actions.
3. Tell the Mac session "Redesign yovoice aplikacji" (the nb session) that refine/look is on main, so it can cut its `nb3/*` build-37 branches. If it cannot be messaged from this computer, ask Kamil to tell it.
4. The polish reaches testers with the next build (build 37), together with the nb3 work.

## Evidence

Frames so far live only on the Mac, in `~/Documents/GitHub/yovoice-evidence/2026-09-25/refine-look/frames/`: before, before-b36, after, sheet and parity. They are regenerable with the harnesses. On this computer, capture a fresh build-36 baseline first, from a detached worktree at `origin/main` (or `3445a1ae`), for both parity and before-frames.

Kamil's comparison page is https://claude.ai/artifact/UcbzkoyLRsAbbRBCseLKsa. Republish it by URL: read it first, then add each area's before/after as batches land.
