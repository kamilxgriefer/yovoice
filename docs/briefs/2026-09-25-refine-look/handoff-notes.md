# Handoff batch (B12) — files released by the nb session on 2026-09-26

After build 36 (origin/main 3fb4e3e4), the "Redesign yovoice aplikacji" session released four files for the spec §10 handoff items. They have no pending build-37 changes on them until refine/look is on main.

`yo_server_rail_item.dart` stays untouched, because it is part of the desktop rail. Kamil wants the rail and the dock to stay visually unchanged.

## Pinned behaviour that the finish must not break

### `lib/features/profile/presentation/widgets/profile_header.dart`
- The header photo stands behind the avatar, name and handle (ADR-219, Kamil's explicit choice).
- Readability depends on the veil in `lib/shared/widgets/profile/profile_hero_backdrop.dart`. It also depends on the avatar ring outline using `palette.borderStrong`, which gives 3:1 against the ring cut-out.
- `test/profile_hero_backdrop_test.dart` measures contrast per row over a white and a black photo, in Dark and Pearl. It must stay green.
- `profile_header_layout_test` pins the avatar centre in the lower half of the header at 320x568. The name keeps its line.
- A name-plate hairline and the avatar brand finish are allowed, as long as those tests stay green.

### `lib/features/auth/presentation/screens/responsive_auth_screen.dart`
- After a Google or Apple sign-in, the screen calls the account-takeover remediation (ADR-222). Keep that call path.
- `AuthPrimaryButton` becomes `YoGradientFilledButton`. Keep its keys, semantics, 52 px height and radius 12.

### `lib/shared/widgets/inputs/yo_segmented_pill.dart` and `lib/shared/widgets/rows/yo_channel_row.dart`
- Both carry the podcast host "waiting" dot (ADR-220, ADR-221), used for raised hands and unseen listener questions.
- The additive `thumbDecoration` and `selectedDecoration` are fine. The dot must stay visible on the new selected and thumb finishes in both themes.
- `server_podcast_questions_dot_test.dart` and the stage request tests pin the dot.
