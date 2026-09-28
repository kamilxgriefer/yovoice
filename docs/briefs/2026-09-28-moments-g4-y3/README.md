# YO Moments — G4 (Głos) and Y3 (Yeels) — brief, 2026-09-28

Decision: [ADR-228](../../Decisions.md#adr-228-yo-moments--głos-as-a-compact-list-under-author-circles-g4-yeels-with-a-one-row-chrome-y3).

## The ask

Kamil, 2026-09-28: redesign Yeels and Voice Moments so they really look like
Instagram. Yeels are "almost perfect", but the top section (the "Odkrywaj",
"Twoje" tabs) still isn't liked. Voice Moments: the per-user blocks are too
big — something slim and easier to take in; the whole section's design can
change. "Give me proposals for both tabs."

## The proposal canvas

A Design canvas (private to Kamil's account, "Yeels i Voice Moments —
propozycje") held, at 390 × 844 unless noted:

| Board | What it showed |
| --- | --- |
| Yeels · dziś / Głos · dziś | build 37 as rendered by `slim_moments_capture.dart` |
| Y1 | one row; the pool filter in a menu under "Yeels ⌄" (with Odśwież) |
| Y2 | two rows; plain text tabs "Odkrywaj \| Twoje Yeels", no plates |
| **Y3** | one row; your avatar opens "Twoje Yeels"; re-tap Yeels refreshes — **built** |
| G1 | thread rows (Threads-like), a slim voice capsule per Moment |
| G2 | compact 76 px list rows; the playing row opens in place |
| G3 | author circles (Instagram-like) above thread rows; a 1440 board |
| **G4** | G3's circles above G2's compact list — **chosen ("g2 i g3 mi się podoba") and built** |

Only data that exists was drawn: a Voice Moment has no waveform (the bars are
the fixed silhouette), no transcript and no listen count; Yeels has no
following scope. The canvas proposed three changes that shipped with G4:
Najnowsze folded into Odkrywaj (identical lists), no "Voice Moment" heading
for an uncaptioned Moment, and circles instead of the capsule strip.

## What was built

See ADR-228 §Decision and `docs/UI.md` ("Głos list (G4)", "YO Moments
chrome"). Frames: `test/slim_moments_capture.dart`
(`--dart-define=YO_CAPTURE_MATRIX=g4`) and `test/refine_b6_capture.dart`
(`--plain-name y3`).
