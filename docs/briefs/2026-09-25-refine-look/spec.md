# YO Voice 3.x: "simple, but super wow" refinement spec

- **Owner:** Senior Product Designer (UX/UI). Review cell: Senior Flutter Product Engineer, Accessibility and Inclusive Design Specialist, Senior Visual Quality Specialist.
- **Date:** 2026-09-25. **Target:** 3.0.x / 3.1 on `main`. Everything here is a spec. No code was changed while writing it.
- **Inputs:** Kamil's two notes (quoted below); the per-area audits and director verdicts; the four picked wow moments; the Afterglow source (`afterglow-reference/afterglow.src.html`) and frames `part-0/1500/3000/4500/6000.png`; the "before" frames listed in §1; the current code (the file:line references are from the 2026-09-25 tree).

> 1. "szczerze to wciąż wygląda strasznie tanio […] ja bym po prostu ulepszył to co już istnieje, i pamiętaj aby używać też obecnego logo"
> 2. "afterglow itd fajnie wygląda jeśli chodzi o delikatny design klocków i ich wykończenia ale ogólnie zrobiłbym coś jednocześnie prostego ale z drugiej strony super wow"

**In one line:** 3.0.0 keeps its layout, sections, order, components and copy. Every existing block gets Afterglow's finish: a soft top-lit fill, a hairline edge and consistent radii. Light comes from only three places: the real logo, something really LIVE, and a voice being played or recorded. That light budget produces the four signature moments.

---

## 1. Diagnosis: why 3.0.0 still reads as cheap

1. **The logo is hidden.** On Start, the glossy 3D mark is shrunk to about 22 px of ink inside a grey 28 px tile, which in Pearl reads as a grey chip. `YoLogo` points at a missing SVG and has no callers. Three different PNGs are placed by hand in 7 places at 4 sizes. See `2026-09-25/refine-look/frames/before/start/start_390_{dark,pearl}_pl_100_populated.png` top-left, and `home_greeting_header.dart` ≈l.262-285.
2. **Every block is the same flat slab.** Blocks are an opaque #17121F fill with an opaque 1 px outline (#342A43 / #D6C8DF) and no light. Radii jump between 12, 14, 18 and 20 inside one screen, and ADR-209's card rule forbids any light. See `start_390_dark…-p2.png` (12 px servers list directly above the 20 px "Masz chwilę?"), `3.0.0-tester-email/frames/p5-profile-390-*.png` and `p4-moments-390-*.png`.
3. **LIVE is the dullest block on Start.** It is a muddy maroon wash in Dark, a pale pink slab in Pearl, and a 72 % still waveform. See `start_390_{dark,pearl}` y≈338-494 and `home_live_now.dart` ≈l.274-309.
4. **The voice UI has no hero.** The play button is a stock `IconButton.filled`. Bars are lilac on lilac, and there is an 88 px dead gap before the clock. The detail disc uses a different visual language, and the record button is a flat disc. See `p4-moments-390-{dark,pearl}.png`, `moments_feed_view.dart` ≈l.3101/3126, and `moment_transport_controls.dart` ≈l.325.
5. **Primary actions are flat and inconsistent.** At 1440, the rail's "Stwórz serwer" has a gradient and a glow, while Start's identical action next to it is a flat #7B2FF7 pill (`start_1440_dark…-p2.png`). The auth, profile and server CTAs are flat fills too (`p7-auth`, `p5-profile`, `slim-2-servers-frames/after/workspace-*`).
6. **Outlines everywhere make it look like a wireframe.** Chips, icon buttons, search and the hollow "Kanały"/"Zaproś" pills all carry opaque 1 px `borderStrong` (#7C6790 / #967AA9) strokes (`p6-more-390-*`, `workspace-390x844-*`).
7. **Placeholder avatars look like coins.** The initial fallbacks are flat #64258E / #6F1FD1 discs with w900 letters, and in the Dark Chats list they turn into near-black holes. Most test accounts have no photo, so these discs dominate every list (`p3-chats-390-{dark,pearl}.png`, `start_1440_dark` friends row).
8. **Too much violet and too much weight.** Unread chat rows are `primaryContainer` slabs, the selected chip is a second violet, and there are 216 × w900 and 302 × w800 literals. The result is three to five violets per screen and black-weight type everywhere (`p3`, `p6`).
9. **Pearl looks washed out and dirty.** Blocks are separated by outline only, with no lift. The lounge photo shows through as grey haze or ghost furniture (`p3-chats-390-pearl` y≈760-1050), and the More sheet casts a muddy plum band (`2026-09-25/report-bug/fix-round/more-sheet-390-pearl.png`).
10. **Edges look unfinished.** There is a hard horizontal seam above the dock (`start_390_dark` y≈738), a desktop chat tile cut mid-word (`start_1440_dark` x≈1376), a two-tone band in the "Kanały" sheet (`workspace-channels-sheet-390x844-*`), and a "NO GLYPH" box beside the greeting in every captured frame (the harness has no emoji font).

---

## 2. Principles

1. **Improve what exists.** Screens, sections, order, components, copy, keys and semantics all stay. New tokens are derived getters only, and no existing token value changes. Because the dock and desktop rail read only existing values, they stay 1:1 by construction.
2. **One recipe per block type.** Each recipe is defined once (tokens → `AppFinish` → one primitive), and screens opt in. There are no hand-rolled decorations and no new hex literals in widgets.
3. **Light has a source (the light budget).** *Emitted* light (bloom or glow) comes only from the real logo, a real LIVE block and a voice actually playing or recording. Each screen also gets at most **one** CTA *lift* (a tight coloured shadow) and at most **one** lead block with a *corner tint*. Every other surface is gradient fill plus hairline, plus a plum contact shadow in Pearl. Dark surfaces emit light; Pearl surfaces receive it.
4. **Hairlines, not outlines.** Decorative separation uses a 9-12 % hairline. Text inputs keep `borderStrong`. High contrast brings `borderStrong` back everywhere and removes every gradient, tint and glow.
5. **The real logo, always bare.** Use `assets/images/logo.png` only. Never box it, never redraw it, and never draw a flat "YO" square. `logo-glow.png` and `app-store-icon.png` are never used in-app, because both are opaque plates.
6. **Calm type, one violet.** Inter only. The weight cap is w700; w800 is allowed only for the "YO Voice" wordmark and the Głos | Yeels switch, and w900 is not used anywhere. Headings get tight tracking. A violet fill appears only on the screen's one CTA and on the voice bead; every tonal element is neutral glass.
7. **Honest motion.** Motion starts only from a real event (a press, a real playback position, real microphone amplitude, a real live start). It is bounded, never an idle loop, and zero under Reduce Motion, accessible navigation or `TickerMode` off.

---

## 3. Finish recipes (one per block type)

Values are **Dark / Pearl**. Every value maps to an existing role or a derived getter from §6. "AG" names the Afterglow class each recipe comes from.

### 3.0 Radius family (one family, no hero radius)

| Token | px | Used by |
|---|---|---|
| `AppRadius.block` (new alias, = `lg`) | 20 | every content block, the LIVE tile, Moment cards, Settings groups (bubbles keep 18 with a 6 px tail) |
| `AppRadius.tile` (new) | 16 | More tiles, conversation-row wash, vibe sticker, image actions, name plate (handoff) |
| `AppRadius.md` (unchanged) | 14 | server squircles, theme inputs |
| `AppRadius.card` (value unchanged, doc updated) | 12 | composers, auth controls, glyph boxes |
| `AppRadius.pill` | 999 | chips, search, labelled CTAs that are already stadium-shaped |
| `AppRadius.xl` | 28 | sheets, recorder panel |

Home's 6 `AppRadius.card` uses switch to `AppRadius.block`. The value of `card` itself does not change.

### R1 Canvas
- The existing Chats/Friends radial is promoted unchanged to `palette.canvasGlow(scheme.primary)`: centre (-.86,-.96), radius 1.25, stops [0,.38,1], [lerp(backgroundTop, primary, .18 / .055), backgroundTop, background]. The output is pixel-identical. Settings and own Profile adopt it. **Start adds no extra aurora**, because the logo bloom already owns that corner.
- Scenery (`YoAtmosphereArt`): add an 18 % bottom dissolve to `palette.background`, painted inside the existing RepaintBoundary (no ShaderMask). Pearl scenery opacity drops .07 → .05. Chats in Pearl uses `section: null` (the watermark path) instead of the lounge photo.
- High contrast: omitted (as today).

### R2 Block surface — AG `.idea` + `.mcard` inset line + Pearl `.mcard` shadow pair
- **Fill:** `palette.blockGradient`, topCenter→bottomCenter [`blockTop`, `surface`]. Dark #1C1626 → #17121F (blockTop = lerp(surface, surfaceRaised, .55)). Pearl #FFFFFF → #FCFAFD.
- **Edge:** 1 px `palette.hairline`. Dark is textPrimary @.09 (≈#2B2633 composited). Pearl is shadow #3D1F50 @.12 (≈#E8E4EA).
- **Radius:** `AppRadius.block` (20).
- **Shadow:** `palette.blockShadows`. Dark: none (a shadow on #080711 is invisible). Pearl: [shadow@.06 blur 2 y1] + [shadow@.16 blur 24 y10 spread -14].
- **States:**
  - Pointer hover: edge → `palette.hairlineHover` (borderStrong @.55 ≈ #4F415D Dark), and in Pearl the second shadow's y goes 10 → 14.
  - Pressed: wash textPrimary @.06 / .05, plus `YoPressFeedback` .985 on touch. No ink ripple on iOS, macOS, web or desktop; InkSparkle on Android, scoped to the primitive.
  - Focus: a 2 px `palette.focus` ring painted as foreground, so there is no 1 px layout shift.
  - Selected: 2 px `interactiveForeground`, fill lerp(surface, focus, .08) (as today).
- **High contrast:** flat `surface`, 1 px `borderStrong`, no gradient, tint or shadow.
- **Rules:** never a card inside a card, and never on dense list rows (rows stay one layer). Chip-like blocks (Moment author capsules) use `elevated: false`, which drops the Pearl shadow.

### R3 Lead-block corner tint — AG `.mcard::before`, exact geometry
- A 240 × 240 circle at `PositionedDirectional(top: -90, end: -70)` holding RadialGradient [tint @ `palette.tintAlpha`, tint @ 0], stops [0,.68]. `tintAlpha` is .16 Dark / .09 Pearl.
- It is fixed in px, so it is never a wash on wide cards. It sits inside the clip, under the ink, in `IgnorePointer`, and mirrors in RTL.
- **At most one per screen:**
  - Start "Tu i teraz" continue card: `ServerIdentity.of(type).primary`
  - Start empty-servers card: `AppColors.primary`
  - Settings profile doorway: `colorScheme.primary`
  - The Moment card that is playing: `AppColors.primary`, only while playing
- Contrast at the tint peak: textTertiary is 4.82:1 (Dark) and 5.02:1 (Pearl). Omitted under high contrast.

### R4 Live block (wow 2) — AG `.live` + `.lamp`
- **Home live tile** (16:9, 280 × 158 narrow/medium, 320 × 180 wide):
  - Base fill stays alphaBlend(`visuals.cardWash`, `surfaceRaised`), so Pearl stays light. Radius `block`.
  - **Corner light:** RadialGradient centred at `AlignmentDirectional(.9,-1)`, radius `min(1.0, 200 / shortestSide)`, [identity **accent** @ .28 / .14 → 0], stops [0,.72], inside the clip, under the content.
  - **Rim:** 1 px `AppColors.live` @ .30 / .28, replacing `palette.border` on this thumbnail only.
  - **Dark specular:** a 1 px top hairline, [`palette.specular` (white @.22) → transparent] across 70 % of the width.
  - **Under-glow:** BoxShadow(`palette.liveGlow` = live @ .34 / .18, blur 32, y 14, spread -12). Pearl adds shadow @.10 blur 16 y 6 spread -8.
  - Content unchanged: the still waveform (`visuals.foreground` @.72), the channel icon, `YoBadge.live` and the `YoMetricPill(overlay)` clock.
- **Server session card, live and not yet joined:** the same recipe at card scale (corner light radius capped at 200 px, live rim, live under-glow). The orb becomes the lit identity gem (§8.2), with **no** glow of its own.
- **Server session card, connected:** keep today's 1.5 px `audioAccent` edge, plus an audioAccent corner tint @ .12 / .08. No glow.
- The block finish never adds a second soft shadow to a live tile, because the under-glow replaces it.

### R5 Primary action, labelled — AG `.btn.pri` + `.mic` shadow idea
- **Primitive:** `YoGradientFilledButton`, which wraps a real `FilledButton` so keys, type finders and focus-ring tests still hold.
- **Fill:** `AppGradients.primaryAction(scheme)` = LinearGradient([scheme.primary, scheme.secondary]) centerLeft → centerRight. That is #7B2FF7 → #A117D8 Dark and #6F1FD1 → #A117D8 Pearl, the same gradient the desktop rail CTA and `YoButton` already paint. White label contrast is at least 5.79:1. Keep `color: null` behind the gradient (see the `yo_button.dart` comment).
- **Lift** (the rail's exact values, both themes): BoxShadow(`AppColors.primary` @ .32, blur 18, y 5). Hover .40 / blur 22. Pressed y 3 and alpha × .6.
- **Other states:**
  - Overlay: white @.10 pressed, @.06 hover.
  - Focus: the existing 2 px `onPrimary` edge.
  - Disabled: `surfaceSunken` with `textTertiary` and no lift.
  - `busy`: the gradient stays, the lift drops to × .5, and a white 18 px spinner shows.
- **Shape:** unchanged per call site (Start 44 px stadium, YoButton 58 px / `lg`, Profile 44 / 12).
- **Identity variant (server join only):** [cta, lerp(cta, #080711, .16)] when `onCta` is white; [lerp(cta, white, .14), cta] when `onCta` is ink. The lift uses cta @ .32 with the same geometry.
- **Rule:** one per screen. Never on repeated, list, retry or tonal actions.

### R6 Icon-only CTA disc — AG `.fab`
- **Primitive:** `YoGradientDisc(emphasis: lift)`.
- **Fill:** `AppGradients.primary` (#7B2FF7 → #C026FF, the logo's own gradient). White glyph at least 4.23:1 (the non-text minimum is 3:1).
- **Lift:** BoxShadow(`palette.brandGlow` × .6 alpha, blur .36d, y .14d, spread -.14d). `brandGlow` is secondary @.42 Dark / primary @.22 Pearl. No gloss.
- **Uses:** Chats compose (40 visual / 44 target), Moments "+" (48, on canvas and over media), and record idle (96, which also gets the voice gloss from R14).

### R7 Tonal action — AG `.btn.ton` / `.vreply`
- **Neutral:**
  - Fill `palette.glass` (textPrimary @.07 / .05), 1 px `palette.hairlineControl` (textPrimary @.14 / .16), label `interactiveForeground` (7.37:1 / 6.27:1) or `textPrimary`.
  - Hover glass × 1.6; pressed +.04; focus 2 px `focus`; disabled 1 px `border` with `textTertiary`.
  - Uses: Start "Znajomi", Profile "Nagrody" and the more button, "Kanały", "Zaproś", Friends "Dodaj" and the row chat action.
- **Accent** (only for the one voice-reply affordance per block): fill `interactiveForeground` @.06 (hover .10, pressed .14), 1.5 px `interactiveForeground` @.55 edge, w700 label. Uses: the feed "Odpowiedz głosem" button and the Chats rail action discs.

### R8 Chip — AG `.chips span` / `span.on` / `.ychips`
- **Single-select filter rows** (Friends `_FilterChip`, the Głos canvas chips, `find_creators`):
  - Size: 36 visual inside the unchanged 48 target, h-padding 14, label 13 w600.
  - Unselected: transparent fill, 1 px `hairlineControl`, `textSecondary` label.
  - Selected ("ink inversion"): fill `textPrimary`, label `background` w700, no edge (18.55:1 / 15.66:1).
  - Hover `glass`; pressed textPrimary @.10; focus 2 px `focus`.
  - The caller passes `selectedBorderColor: Colors.transparent` to `AccessibleTapRegion` (an argument only; that file is not edited).
- **Over media (Yeels):** selected fill white with an `AppImmersiveColors.background` label w700; unselected fill `overlayChipColor` = 0x59000000 with a white label w600.
- **Multi-select Material chips** (`chipTheme`): only the side changes, to `hairlineControl`. Selected keeps `primaryContainer` and the checkmark.

### R9 Controls
- **`YoIconButton` default:** `glass` fill, 1 px `hairlineControl`, hover → `hairlineHover`, shape `md` unchanged.
- **Search** (`YoSearchField`, Chats search): 44 px `StadiumBorder`, fill `surface` (Dark) / `surfaceRaised` (Pearl), 1 px `border`, 2 px `focus` at pill radius, `textTertiary` 20 px prefix icon, no lift.
- **Form fields** (auth, edit profile, composer): unchanged `borderStrong`. The composer field goes to radius 24.

### R10 Avatar — AG `.av` (one brand pair; the Afterglow aura hues are excluded)
- **Opt-in:** `UserAvatar(finish: UserAvatarFinish.brand)`. The default `flat` stays pixel-identical, which keeps the desktop rail's profile card and the other session's profile hero unchanged.
- **Letter fallback:** `AppGradients.letterAvatar`, topLeft → bottomRight #6542B8 → #6D1894 (lerp(voice, #080711, .30), lerp(secondary, #080711, .45)). White initial is 6.94:1 / 9.51:1.
- **Initial:** w700, fontSize = diameter × .38, letterSpacing -.3, `TextScaler.noScaling`. Shadow(black @.25, blur 2, y 1) only when diameter ≥ 40.
- **Ring:** letter avatars get 1 px white @.08 in Dark and none in Pearl. Photos get 1 px `palette.hairline` in both themes.
- **Custom fills:**
  - Neutral or brand fill passed by a caller (`surfaceSunken`, `colors.primary`, `AppColors.primary`): the caller drops it and passes `finish: brand`.
  - Opaque custom fill with `finish: brand`: top-light [lerp(fill, white, .14), fill] from Alignment(-.6,-.8) to (.6,.8).
  - Translucent identity fill: stays flat, and gets the ring.
- No per-person hues, anywhere.

### R11 Count badge and pills — AG `.conv .n` + `.bdg`
- **`YoCountBadge(count, ring)`:**
  - Fill `AppGradients.primaryAction(scheme)`; minimum 20 × 20, h-padding 5, radius pill.
  - Label white 11 w700 with tabular figures, "99+" cap, no scaling beyond the existing clamp.
  - A 2 px ring in the host colour (`background` on the canvas, white @.28 over media). No shadow.
  - Replaces the Start bell badge, `recent_chats` `_UnreadBadge` (both styles) and the Chats row badge.
- **Unchanged:** the dock's red badge, sidebar badges, `YoMetricPill`, `OfficialRoleBadge` / `IdentityBadgePill` (the rail renders them), and `YoBadge.live`.
- **`YoBadge` tonal variants:** the border goes from full foreground to foreground @.32.

### R12 Ring — AG `.cring`
- **`YoProgressRing(value, size, stroke, trackColor, arcColor)`:** round caps, starts at 12 o'clock, clockwise, `ExcludeSemantics` (the caller's text carries the value).
- **Moment expiry pill:** 14 px ring, stroke 2, track `border`, arc `interactiveForeground`. It switches to `warningForeground` only when less than 1 h remains.
- **Unchanged:** `MomentProgressRing` (the listening ring) and its `audioProgressGradient`. There is no elapsed ring around any record button (see wow 4).

### R13 Waveform — AG `.wave`
- **Played:** `palette.audioProgressGradient` (Dark #5CE1E6 → #D986FF, Pearl #007C83 → #6F1DCE). This is the documented single voice-playback accent. The gradient **spans the full waveform width** and is revealed up to the playhead, so bar colours never shimmer.
- **Unplayed, at rest and while playing:** `palette.waveUnplayed` (textPrimary @ .28 / .22), so pressing play never dims the bars. Played vs unplayed is at least 3:1 at both ends (Dark 4.64 / 3.06, Pearl 3.13 / 4.80).
- **Shape:** always the fixed silhouette (honesty rule). Feed: 36 high, bar 3, gap 2, radius 1.5. Detail: 56 / 64 high, bar 4, gap 3.
- **`continuousProgress`** (opt-in): a partial bar fill at the exact playhead. The caller tweens linearly toward each **real** position event (~200 ms), snaps on seek and never extrapolates.
- **Outgoing bubble:** unplayed white @.50, played white.
- **Unchanged:** the LIVE tile silhouette and the `StoryWaveform` default (story viewer).

### R14 Voice bead (wow 3) — AG `.bigplay` / `.pin .pb` / `.mic`
- **Primitive:** `YoGradientDisc(emphasis: rest | lit, gloss: true)`. It is draw-only; the caller keeps Semantics, tooltip, keys and callbacks.
- **Sizes (unchanged per site):** 34 bubble, 40 rows, 44 `moment_card`, 48 feed, 52 pinned, 54 detail panel, 64 / 72 transport, 96 record.
- **Fill:** `AppGradients.primary`.
- **Gloss:** RadialGradient centre (-.40,-.60), radius .60, [white @.28 → 0].
- **Rim:** a 1 px inner stroke, [white @.24 → 0] by 55 % of the height. If it looks plasticky at 44 or 48, drop the rim first.
- **Rest:** contact shadow only, `palette.contactShadow` (shadow @.28 / .12), blur 4, y 2.
- **Lit (only this clip, only while it plays):** BoxShadow(`palette.brandGlow`, blur .45d, y .18d, spread -.12d). That is 22 / 9 / -6 at 48 and 32 / 13 / -9 at 72. Fades in over 180 ms and out over 320 ms.
- **Glyph:** white, .42d (minimum 18). Play is nudged +.03d. `AnimatedIcon(play_pause)`, 200 ms easeInOut.
- **Other states:**
  - Busy: a white spinner (20; 18 at ≤ 40), stroke 2, 120 ms cross-fade.
  - Failed: the refresh glyph.
  - Disabled: `surfaceMuted`, `textTertiary` glyph, no gloss or shadow.
  - Press: `YoPressFeedback` .94. `HapticFeedback.lightImpact` on play (iOS and Android).
  - Hover: contact and glow +.06.
  - Focus: 2 px `focus` ring, 3 px outside.
- **Outgoing bubble variant:** fill white @.22 with no gloss, rim or shadow (AG `.bub.out .pb`).
- **High contrast:** the gradient stays; no glow and no gloss.

### R15 Bubbles — AG `.bub.in` / `.bub.out` / `.react` / `.sep`
- **Outgoing:** `primaryAction(scheme)` (white text 5.8:1 or better; today it is 4.7:1 on #A72DFF). Radius 18, **6 px tail**, no edge, no shadow.
- **Incoming:** `blockGradient` + 1 px `hairline` + Pearl `blockShadows`, 6 px tail.
- **Queued (sending):** the same outgoing decoration, width cap 560 and 48 px gutter as sent bubbles, so nothing jumps on acceptance. The failed state gets a 1.5 px `colorScheme.error` edge.
- **Media:** padding 4 with a concentric 14 px inner radius and 2 px on the tail corner. This applies **only** to image, video and gif bubbles that are neither deleted nor replies.
- **Reaction pill:** stadium, `surfaceRaised` fill, 1 px `hairline`, h8 v3. It stays in its own slot, with no overlap.
- **Date separator:** a centred glass pill (h10 v3, 11 w700, letterSpacing .6, displayed uppercase). Semantics read the original label.

### R16 Rows, tiles and sheets
- **Rows:** stay one layer. Hover wash textPrimary @.04 / interactiveForeground @.05, pressed interactiveForeground @.10, focus 2 px ring at radius 16. Dividers use `hairline`.
- **Tiles (More):** radius `tile`. Dark `glass` fill + `hairline`; Pearl `surfaceRaised` + `blockShadows`.
- **Glyph box (tiles, Settings, account rows):** radius 12, LinearGradient topLeft → bottomRight [scheme.primaryContainer, scheme.secondaryContainer] (existing scheme values), icon `interactiveForeground`.
- **Sheets:** `hairline` top edge.
  - The Pearl More sheet sits on `background` with a shadow pair [shadow @.10 blur 2 y1] + [shadow @.24 blur 40 y18 spread -12], replacing the @.34 band.
  - The "Kanały" sheet background is `surfaceMuted`, which removes the seam.

### R17 Empty and error states
- **Logo:** only the two first-run invitations get the real logo, the Chats inbox and the Servers directory (see §4). All other empty states keep their topic icon.
- **Moments empty/error:** a 64 px circle, primary @.14 / .08 fill with a 1 px primary @.30 edge and a 28 px `interactiveForeground` glyph. The CTA is R5.
- **Other `YoEmptyState` / `YoErrorState` discs:** unchanged. The "glossy placeholder disc" idea is dropped.

### Light budget per screen (the enforcement table)

| Screen | Emitted glow | CTA lift (max 1) | Corner tint (max 1) |
|---|---|---|---|
| Start | logo bloom (Dark), LIVE tile | "Stwórz serwer" pill | "Tu i teraz" continue card (or the empty card) |
| Servers directory | none | "Stwórz serwer" | none |
| Server workspace | live session card | join action | none (connected card gets an audioAccent tint instead of a glow) |
| Chats list / thread | the voice bead while playing | compose disc | none |
| Głos / detail | the playing bead + card | "+" / "Utwórz" / detail reply | the playing card |
| Recorder | record bead (live halo) | record bead at idle | none |
| Profile | pinned bead while playing | "Edytuj profil" | none (the vibe sticker *is* the colour block) |
| Settings, More, Friends, Notifications | none | none | Settings profile doorway only |
| Startup / Auth / TOTP | logo bloom + one glint | auth CTA (deferred, §10 handoff) | none |

---

## 4. Logo plan

Primitives live in `lib/shared/widgets/branding/yo_logo.dart`: `YoBrandMark` and `YoBrandLockup`. `YoLogo` is kept as a thin wrapper that renders `YoBrandLockup`, which fixes the missing-SVG crash path.

- **Assets:** `markAsset = 'assets/images/logo.png'` (512 px, alpha) and a new derived `bloomAsset = 'assets/images/logo-bloom.png'`.
- **How `logo-bloom.png` is made:** from logo.png, the logo is scaled to 320 px, centred on a transparent 512 canvas, then Gaussian-blurred with σ 24, keeping its own colours and alpha. For example with Pillow: `resize(320) → paste on 512 RGBA → GaussianBlur(24) → save optimize`. The script goes in the batch notes and a test pins that the result is 512 px with alpha. It is drawn at 1.6 × the mark box so that its inner footprint equals the mark.
- **Rendering:** `cacheWidth = (size × dpr).ceil().clamp(64, 512)`, `FilterQuality.high`. The errorBuilder shows `Icons.graphic_eq_rounded` at .6 × size in `interactiveForeground`. The image is `excludeFromSemantics`; the lockup is one Semantics node, "YO Voice".
- **Layout:** bloom and contact shadow are Stack siblings with `clipBehavior: none`, so the layout box is always exactly size × size.
- **`light`:** `auto` gives bloom in Dark and a contact shadow in Pearl; `bloom` is forced on immersive surfaces; `none` for lists.
- **Precache:** `precacheImage(logo, bloom)` in `MobileHome.didChangeDependencies` and in the startup screen.

| Surface | File | Size | Dark | Pearl | Motion |
|---|---|---|---|---|---|
| Start lockup (phone, tablet) | `home_greeting_header.dart` (`HomeBrandLockup`) | 32 (<600), 36 (600 to the desktop shell); at ≥1.6× text clamp(wordmark line × 1.1, 32, 48) | bare mark, **no tile**; bloom 1.6× box @ .45, static; 10 px gap to the unchanged w800 wordmark | contact shadow: bloom tinted `palette.shadow` via ColorFiltered(srcIn) @ .16, box 1.6×, offset (0,2) | none (no glint at this size) |
| Start, desktop | no lockup (the rail owns the brand) | n/a | n/a | n/a | n/a |
| Desktop rail | `desktop_sidebar.dart` | **untouched** (30 px) | n/a | n/a | n/a |
| Startup | `startup_loading_screen.dart` | 208 / 160 / 128, unchanged | bloom 1.5× (312 / 240 / 192) inside the same fly-in transform, opacity .34 + .16 × the existing 3.6 s breath; **glint** follows the existing `lightCenter` | same (immersive) | Reduce Motion: bloom .42 static, no glint |
| Auth compact header | `responsive_auth_screen.dart` ≈l.1806 (logo-only edit) | 56 / 44, unchanged | bloom 1.6× @ .45 | same (immersive) | one glint 350 ms after first paint, only if startup did not glint this launch |
| Auth wide brand panel | same file ≈l.1595 | 96, unchanged | bloom | same | shares the one glint |
| TOTP | `totp_challenge_screen.dart` ≈l.325 | 76 | bloom | same | none |
| Auth-gate error | `auth_gate.dart` | 64 | bloom | same | none |
| System notification sender | `notifications_screen.dart` `_Avatar` | 40 in the 44 slot, only when `type == system && actorId.isEmpty` | bare, `light: none` | bare | none |
| Settings › O aplikacji › Wersja | `settings_screen.dart` | 40 in the leading slot, no glyph box | bare | bare | none |
| Chats inbox empty (first-run) | `messages_screen.dart` | 88 (72 when viewport height < 560) | bloom | contact shadow | fade + scale .96 → 1, `entrance`, Reduce Motion = none |
| Servers directory empty (first-run) | `servers_screen.dart` via `YoEmptyState(leading:)` | 72 | bloom | contact shadow | existing entrance |
| Mini-player, page watermark | `active_room_mini_player.dart` ≈l.1155, `yo_page_background.dart` ≈l.82 | unchanged | asset constant swapped to `markAsset` | same | none |
| Launcher, favicon, store | platform configs | n/a | `yo-voice-favicon-512.png` / `app-store-icon.png` stay there only | n/a | n/a |

**Never:** a flat "YO" square, `logo-glow.png` or `app-store-icon.png` in-app, the logo in the dock, the logo on the Moments empty state (the studio scenery already carries the neon YO as wall art, ADR-142), a glint on the 32 px Start mark, or the logo in list or content states.

---

## 5. Signature moments

Motion predicate for all four: `AppMotion.decorative(context)` = `!disableAnimations && !accessibleNavigation && TickerMode.of(context)`. Each moment gets its own `RepaintBoundary`.

### W1. The real logo, freed and lit
- **Where:** the Start lockup, Startup, Auth (and the TOTP / auth-gate marks).
- **What:**
  - Start: the tile is removed; the mark box grows from 28 to 32 px and the visible ink from ~20 to ~26 px (logo.png carries about 9 % transparent margin per side). Dark gets a static bloom; Pearl gets a contact shadow so the glossy object sits on the paper.
  - Startup: the bloom rides the native-splash fly-in inside the same transform, and its opacity follows the existing breath (.34 + .16 × breath). No new ticker; the blur is pre-baked.
  - Glint (startup): `ShaderMask(srcATop)` on the logo's alpha only. The band goes white 0 → white (.42 × the existing brightness) → 0, is 35 % of the logo wide and tilted 20°. Its centre is driven by the existing `lightCenter`, so the backdrop light visibly crosses the logo's glass. The mask exists only while |x| ≤ 1.4.
  - Glint (auth): one pass 350 ms after first paint over the new `AppMotion.glint` (900 ms, easeInOutCubic), gated by a static "glinted this launch" flag. The controller is disposed after the run.
- **Reduce Motion / HC / TickerMode off:** bloom static at .42, no glint, `transientCallbackCount` 0. Under high contrast: no bloom, glint or shadow.
- **Acceptance:**
  - At 390, Dark and Pearl, the full-colour mark sits in a 32 px box (~26 px of ink) with no tile.
  - The startup frame 0 still matches the native splash.
  - `pumpAndSettle` settles within 1.2 s on auth.
- **Unverified until rendered on a device:** the glint. If it reads as a cheap "shine sweep", ship the bloom only.

### W2. LIVE is the one lit surface on Start
- **Where:** `HomeLiveChannelCard` (R4), plus the server session card at card scale.
- **Ignite:** once per `(channelId, startedAt)`, remembered in section state. Glow and corner light fade 0 → 1 over `AppMotion.entrance` (320 ms, easeOutCubic), in parallel with the badge dot's existing 3-cycle pulse, then rest. No translate, scale or breathing loop. Rebuilds, scrolling, tab switches and retained-root returns never replay it; a new `startedAt` does.
- **Section arrival:** the section mount point in `mobile_home` / `desktop_home` is wrapped in `AnimatedSize(AppMotion.entrance, entranceCurve, topCenter, clipBehavior: Clip.none)`. Start no longer jumps ~250 px in one frame, and the section collapses over `AppMotion.standard`. No placeholder is reserved (it would promise a live that may not exist).
- **Hover (wide):** glow alpha × 1.2 and rim @.45 over `quick`. **Press:** `YoPressFeedback` .985, shadow y 14 → 8, release 240 ms.
- **Reduce Motion:** renders directly at rest, with `AnimatedSize` at 0. **High contrast:** no glow; the rim is 1.5 px solid `AppColors.live`.
- **Acceptance:**
  - At 390, Dark and Pearl, with each of the 5 ServerTypes live, the tile is the only glowing object on Start.
  - The glow bleeds ≤ 20 px into the 24 px gap and never under the next heading's ink.
  - No glow placeholder appears when nothing is live.

### W3. The voice bead: the logo's glass, lit only while a voice plays
- **Where:** the feed transport (48), `MomentDetailPanel` (54), `_PlayDisc` (64 / 72), `moment_card` (44), `VoicePlayerRow` (40), chat bubbles (34), the profile pinned Moment (52), and the Start "Masz chwilę?" mic (48, rest only).
- **What:** the R14 bead replaces five hand-rolled discs. In any feed or thread, **exactly one** thing glows: the clip that is playing. That card's hairline goes to `AppColors.primary` @ .45 / .35 and it gains the R3 corner tint (the feed's lead block). There is no layout shift.
- **Pour:** `YoWaveform(continuousProgress: true)` with the full-width played gradient, tweened toward real position events (~200 ms) and snapped on seek. Bar heights never change.
- **Timing:** tint and glow in over 180 ms, out over 320 ms. Press .94 over 90 ms, release 240 ms easeOutBack. Haptic light impact on play (mobile).
- **Reduce Motion:** no scale, the icon snaps, glow and tint change instantly, and the pour updates only on position events. **High contrast:** no glow or tint; the playing card gets a 1.5 px `interactiveForeground` hairline instead.
- **Acceptance:**
  - Starting card 2 lights only card 2, pausing drops it to rest, and starting card 3 moves the light.
  - Position ticks never rebuild the card body (the energy notifier changes only on play, pause or switch).
  - `test/yo_waveform_test.dart` "no frame scheduled" still passes.
- **Risk:** gloss and rim at 44 / 48 must be rendered in both themes before app-wide adoption (B1 primitive sheet).

### W4. The record button listens
- **Where:** `_recordButton()` in `record_voice_moment_screen.dart` (≈l.2508). The screen is immersive dark in both themes. Only the child inside `AccessibleTapRegion` changes.
- **Idle:** bead 96 (R14 with gloss) at R6 lift strength (brandGlow at 60 %), white mic glyph 38.
- **Requesting:** 35 % disc with a white spinner (today).
- **Recording:** a solid `AppColors.live` bead with gloss and an `onLive` stop glyph (the existing 220 ms colour change stays). Mic ↔ stop swap through `AnimatedSwitcher` (scale .6 → 1 plus fade, 160 ms).
- **The halo is the button's own shadow:** BoxShadow(`AppColors.live` @ (.30 + .35L), blur 28 + 24L, spread 2 + 4L).
  - L is the same normalised sample the existing `_LevelMeter` draws (`VoiceMomentRecorder.normalizeAmplitude`, about 8 Hz).
  - It is smoothed with attack .6 / release .25, pushed through a `ValueNotifier` with a 140 ms tween, and never rebuilds the screen.
  - Silence gives L = 0, a still halo. No stroke ring: that slot belongs to the other session's `yo_recording_countdown`.
- **Haptics:** medium on start, light on stop (mobile).
- **Web / no amplitude:** L stays 0 (honest).
- **Reduce Motion:** fixed halo .42 / blur 28 while recording, instant icon swap. **High contrast:** solid disc, no glow.
- **Recorder panels** get the immersive block finish:
  - `_card` and the 20 px panels: fill [AppImmersiveColors.surfaceRaised, surface] @ .92 with a 1 px white @.10 hairline replacing #3A3151. Radii unchanged; no tint (the bead is the light).
  - Active step: primary @.14 fill, 1.5 px primary @.55 edge, and an `AppGradients.primary` number disc.
  - Inactive step: white @.03 fill with a white @.06 hairline.
- **Chats voice-message sheet (B7):** adopts the idle and recording bead **at rest only**, and the literal #FF4F78 becomes `AppColors.live`. The amplitude halo there is a later, separate step.
- **Acceptance:** tested on a real iPhone and a real Android. The halo swells with speech and settles in silence. Maximum extent is about 26 px beyond the disc, agreed with the countdown-ring owner.

---

## 6. Token and theme changes (all additive)

**`lib/core/theme/app_palette.dart`: derived getters only.** No new constructor fields, so the 27-role raw-literal guard (`test/semantic_color_source_guard_test.dart`) and `copyWith`/`lerp` stay untouched, and derived values lerp for free.
```dart
bool get isDark => background.computeLuminance() < .5;
Color get hairline => isDark ? textPrimary.withValues(alpha: .09) : shadow.withValues(alpha: .12);
Color get hairlineControl => textPrimary.withValues(alpha: isDark ? .14 : .16);
Color get hairlineHover => borderStrong.withValues(alpha: .55);
Color get glass => textPrimary.withValues(alpha: isDark ? .07 : .05);
Color get blockTop => isDark ? Color.lerp(surface, surfaceRaised, .55)! : surfaceRaised;
LinearGradient get blockGradient => LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [blockTop, surface]);
List<BoxShadow> get blockShadows => isDark ? const [] : [
  BoxShadow(color: shadow.withValues(alpha: .06), blurRadius: 2, offset: const Offset(0, 1)),
  BoxShadow(color: shadow.withValues(alpha: .16), blurRadius: 24, offset: const Offset(0, 10), spreadRadius: -14)];
double get tintAlpha => isDark ? .16 : .09;
Color get contactShadow => shadow.withValues(alpha: isDark ? .28 : .12);
Color get brandGlow => isDark ? AppColors.secondary.withValues(alpha: .42) : AppColors.primary.withValues(alpha: .22);
Color get liveGlow => AppColors.live.withValues(alpha: isDark ? .34 : .18);
Color get specular => AppColors.white.withValues(alpha: isDark ? .22 : .70);
Color get waveUnplayed => textPrimary.withValues(alpha: isDark ? .28 : .22);
RadialGradient canvasGlow(Color primary) => /* existing Chats/Friends recipe, stops [0,.38,1] */;
```
- **`app_gradients.dart`:** keep `primary`. Add `primaryAction(ColorScheme s, {begin = centerLeft, end = centerRight})` = [s.primary, s.secondary], and `static final letterAvatar` (#6542B8 → #6D1894 via `Color.lerp` from `AppColors` and `AppPalette.dark.background`).
- **`app_radius.dart`:** `block = lg` (20), `tile = 16`. Update the `card` doc comment ("inputs, composers, glyph boxes; blocks use `block`").
- **`app_motion.dart`:** `press` 90 ms, `release` 240 ms + `releaseCurve = Curves.easeOutBack`, `glint` 900 ms + `glintCurve = Curves.easeInOutCubic`, and `static bool decorative(BuildContext)`.
- **`app_typography.dart`:** new roles only; existing styles unchanged, because the rail and other screens use them.

  | Role | Size | Weight | Tracking | Line height / notes |
  |---|---|---|---|---|
  | `screenTitle` | 22 | w700 | -0.5 | 1.15 |
  | `greetingWide` | 30 | w700 | -0.8 | 1.1 |
  | `sectionTitle` | 17 compact / 19 expanded | w700 | -0.25 | |
  | `rowTitle` | 15 | w600 (unread w700) | | |
  | `rowPreview` | 13 | w400 `textSecondary` (unread w500 `textPrimary`) | | |
  | `count` | 11 | w700 | | tabular figures |
  | `overline` | 11 | w600 | .6 | |

  Verify on a device that `InterVariable.ttf` renders true w600 and w700. If not, add `fontVariations`.
- **`app_finish.dart` (new):** the recipe composer, with the light budget in its doc comment. It holds `block(p, {radius, hovered, elevated, highContrast})`, `cornerTint(color, p)`, `liveCorner(accent, p)`, `liveRim(p)`, `liveGlow(p, {hovered, pressed})`, `actionLift(color, {hovered, pressed})`, `discShadow(p, d, emphasis)`, `glass`, `chip` values and `tonal` ButtonStyles. Pinned by `test/app_finish_test.dart`.
- **`app_icons.dart` (new):** Material aliases (`compose = Icons.edit_outlined`, `addFriend = person_add_alt_outlined`, `chat = chat_bubble_outline_rounded`, `archive = archive_outlined`, `notifications = notifications_none_rounded`). Rule: outline glyphs in chrome; filled glyphs only for a selected toggle, a white glyph in a gradient disc or CTA, or a status icon. Owners swap as they touch files.
- **`app_theme.dart` (B3):** `chipTheme.side` → `hairlineControl`; `cardTheme.side` → `hairline`. Nothing else: no global `splashFactory`, no `iconButtonTheme` or `outlinedButtonTheme` change (the rail uses a themed `IconButton` and `InkWell`s).
- **`server_identity.dart` (B4):** add `liveOrbGradient` + `onLiveOrb` and `ctaGradient` to `ServerIdentityVisuals`. These are the director-verified gem stops:
  - friends #70E5E9 → #5CE1E6 with ink (11.0:1)
  - podcast #FF7D90 → #FF5474 with ink (5.6:1)
  - family #4DE89B → #2EDB84 with ink (9.6:1)
  - company #76CEFF → #58B5FF with ink (7.8:1)
  - community #A528F0 → #8A2BE2 with white (5.05 / 5.96:1)

  `iconSurface` and `iconBorder` are unchanged.

**Rule:** no token lands without an adopter by the end of the rollout. Tokens for other-session files (channel-row selected wash, tonal server tile) live only in the §10 handoff table until their owner adopts them.

---

## 7. Primitive changes

| Primitive | File | Exact change | Default pixels change? |
|---|---|---|---|
| `YoCard` | `shared/widgets/cards/yo_card.dart` | Evolve to R2. New params: `tint`, `radius` (default `block`), `minHeight`, `semanticButton` (default true), `elevated`. The shadow sits on an outer `DecoratedBox` so the clip never cuts it. Focus becomes a foreground ring. The 140 ms transition uses `AppMotion.resolve`. `YoPressFeedback` .985. No splash off Android. | Yes, but it has **0 lib callers** today |
| `YoGradientFilledButton` | new `shared/widgets/buttons/yo_gradient_filled_button.dart` | R5. Signature `(onPressed, child, style/shape, minimumSize, padding, gradient?, liftColor?, busy)`. A `FilledButton` with `backgroundBuilder` painting `Ink(ShapeDecoration(gradient))`, inside an outer `DecoratedBox` with the lift. Never set in `filledButtonTheme` (84 call sites recolour `FilledButton`s). | New |
| `YoGradientDisc` | new `shared/widgets/buttons/yo_gradient_disc.dart` | R6 / R14, draw-only. Params: `size`, `emphasis` (rest / lift / lit), `gloss`, `status` (idle / busy / failed / disabled), `glyph` (icon or `AnimatedIcon`), `tone` (brand / onBrand / live). This implements the wow-picked `YoVoiceDisc` under a neutral name, because the same bead also serves compose and create. | New |
| `YoPressFeedback` | new `shared/widgets/interactions/yo_press_feedback.dart` | A `Listener`-based scale (never joins the gesture arena). `scale` .985 block / .97 tile / .94 disc; press 90, release 240 easeOutBack; zero under Reduce Motion. `accessible_tap_region.dart` is not edited. | New |
| `YoCountBadge` | new `shared/widgets/badges/yo_count_badge.dart` | R11. | New |
| `YoProgressRing` | new `shared/widgets/badges/yo_progress_ring.dart` | R12. | New |
| `YoBrandMark` / `YoBrandLockup` / `YoLogo` | `shared/widgets/branding/yo_logo.dart` | §4. Keys pass through (`home-brand-lockup`, `home-brand-mark`, `startup-logo`, `totp-logo`), plus new keys `startup-logo-bloom` and `startup-logo-glint`. | Fixes the broken widget |
| `UserAvatar` | `shared/widgets/profile/user_avatar.dart` | Add `finish: UserAvatarFinish.flat \| brand` (R10). The #64258E literal becomes a named `static const` in the file. | No (opt-in) |
| `YoWaveform` | `shared/widgets/waveform/yo_waveform.dart` | Add `continuousProgress` (default false) and `gradientSpan: played \| full` (default `played`). Doc updated; `StoryWaveform` defaults unchanged. | No (opt-in) |
| `YoEmptyState` | `shared/widgets/states/yo_empty_state.dart` | Additive `Widget? leading` that replaces the 76 px circle when set. | No |
| `YoButton` | `shared/widgets/buttons/yo_button.dart` (B3) | Primary reads `AppGradients.primaryAction` + `AppFinish.actionLift` (rail values). Label letterSpacing .8 → .2. Press .98 on touch. | Yes, tiny |
| `YoIconButton`, `YoSearchField` / `YoTextField` (search variant), `YoBadge` (tonal border @.32) | `shared/widgets/...` (B3) | R9 / R11. | Yes |
| `VoicePlayerRow`, `VoiceCore` | `shared/widgets/voice/*` (B5) | `_control()` → `YoGradientDisc` (40 contained / 34 inline). Style gains `playedGradient`, `unplayed`, `continuousProgress`. The inline path accepts a real progress notifier. `VoiceCore` literals #B44BFF, #7A16D8 and #9D20FF become `AppGradients.primary` / `AppColors.secondary`. | Yes |
| `HomeSectionHeader` | `shared/widgets/layout/home_section_header.dart` (B2) | Title uses `sectionTitle` (w800 → w700, -0.25). Shared with More, Friends and Notifications. | Yes |
| `YoPageBackground` / `YoAtmosphereArt` | `shared/widgets/backgrounds/yo_page_background.dart` (B2) | R1 bottom dissolve; Pearl scenery .05; watermark `markAsset`. | Yes |
| `ImmersiveFeedChrome`, `ImmersiveOverlayAtoms`, `ReelProgressRow` | B5 / B6 | R8 chips, the format switch, Yeels plates, "+" and progress (§8.4). | Yes |

---

## 8. Per-screen changes (each small, no IA change)

### 8.1 Start (the pilot; mobile + desktop)
- **Header:**
  - W1 lockup (32 / 36, no tile). The greeting uses `screenTitle` on phone (22 w700 -0.5, maxLines 2) and `greetingWide` on desktop (30).
  - `HomeHeaderDisc` (bell and avatar, 46 px): `glass` fill + `hairline`, icon `textPrimary` 21. The own-avatar ring becomes `hairline`, and the bell badge becomes `YoCountBadge`.
  - Structure unchanged: brand line, then greeting, then subtitle, with the controls at the end; at ≥ 1.6 text the controls drop below.
- **Friends row:** avatars `finish: brand`; press .97 via `YoPressFeedback` around the existing ink. The ring language is unchanged.
- **Live:** W2 (R4). `cardWidth` stays 280 / 320; `AnimatedSize` arrival.
- **"Tu i teraz" continue card** (`home_server_overview.dart`):
  - `YoCard(tint: identity.primary)`, padding 16 (32 expanded), minHeight 216 expanded.
  - Server name 20 w700 -0.3 (22 expanded).
  - The trailing arrow becomes a 36 px disc (`iconSurface`, 1 px `iconBorder`, `arrow_forward_rounded` 20 in `foreground`) inside `ExcludeSemantics`, so the card stays one button.
  - At 1440 the fixed 240 px tint lights the empty right half of the 790 px card.
- **Server list:** `YoCard(padding: 0)`, dividers `hairline`, indent 64.
- **Loading / empty / error:** loading is `YoCard` without a tint (minHeight 164, spinner kept); the empty card is `YoCard(tint: AppColors.primary)` with an R5 "Stwórz serwer"; `HomeSectionError` and `_RecentChatsMessage` use `YoCard`.
- **"Masz chwilę?":** `YoCard` without a tint; the 52 px squircle mic becomes an R14 bead at 48, rest state. The card stays one button (`home-record-moment`).
- **Quick actions:** "Stwórz serwer" → `YoGradientFilledButton` (stadium, 44, shrinkWrap); "Znajomi" → R7 neutral. The measured 12 px gaps stay exact, because the lift is paint only.
- **Recent chats:**
  - Mobile cards: `YoCard`, radius 20, padding 12.
  - Desktop tiles: radius 18 → 20 (the `AccessibleTapRegion` `borderRadius` argument too), edge white @.10, fill `AppPalette.dark.surface → surfaceSunken`, Pearl `blockShadows`, ghost initial .16 → .10.
  - Desktop tile fallback accents come from the brand family (primary, secondary, voice, navigationPrimary); the random pink or blue per person goes.
  - When the rail can scroll, the peek fades out over the final 32 px + gap (ShaderMask dstIn, RTL-mirrored, removed at scroll end).
  - Badges → `YoCountBadge`.
- **Seam:** R1 bottom dissolve, plus a 24 px `IgnorePointer` / `ExcludeSemantics` bottom fade on the mobile list while `extentAfter > 0`. The dock and shell are untouched; `Scaffold.extendBody` is not proposed.
- **Section headings:** `sectionTitle`.
- **Responsive:** 390 is one column (358 px blocks). 768 is the same inside the list frame, with the expanded "Tu i teraz" at ≥ 600. 1440 keeps the 3:2 columns, has no lockup (the rail owns it), live 320 × 180 and the chats rail fade. At 200 % blocks only grow, the lockup mark follows the clamp, and the wordmark may ellipsize.

### 8.2 Servers (directory + workspace)
- **Directory rows** (`servers_screen.dart`, flagged small edit, ~60 lines):
  - Each row gets the R2 block (neutral, **no identity tint**; identity lives only in the face) via `Ink(AppFinish.block)` inside the existing `Material` (key `server-directory-<id>` unchanged). minHeight 72, `runSpacing` 12, column gap 16.
  - At two columns, rows render as `IntrinsicHeight` pairs (stretch), so pairs are equal height with the same row-major focus order.
  - Create → R5. Empty state → the logo (§4). The meta line uses a non-breaking space between count and noun.
- **Workspace:**
  - "Kanały" and "Zaproś" → R7 neutral, keeping widget types and keys; disabled keeps a 1 px `border`.
  - The "Kanały" sheet: `backgroundColor: surfaceMuted`, hairline top side, 28 radius.
  - Header, panel and centre dividers → `hairline`.
- **Session card** (`server_channel_scene.dart`):
  - Live and not joined: W2 recipe at card scale.
  - Connected: audioAccent edge + tint (R4).
  - Quiet: R2.
- **Orb:**
  - Live: `liveOrbGradient` circle with `onLiveOrb` symbol and a 1 px white @.14 rim; no glow and no pulse (the badge dot already pulses).
  - Quiet, empty or microphone: the "unlit" finish, [alphaBlend(primary @.18 / .12, surfaceRaised), alphaBlend(primary @.06 / .04, surface)], 1 px primary @.28 (Dark) or `hairline` (Pearl), plus Pearl `blockShadows`.
  - The 112 px size and the `server-voice-orb` key are unchanged.
- **Join:** `YoGradientFilledButton` identity variant. `FilledButton` is kept, `backgroundColor: colors.cta` stays for the ring test, and the test is extended to both stops. Module card primary, retry and invite-intro actions stay solid (one lit action).
- **Header live marker:** only in the channel header above a media scene, the red pill becomes a lamp (an 8 px live dot using the same bounded 3 × 1.2 s pulse, then 6 px, then the unchanged "Na żywo od 19:40"), with key `server-live-lamp` and Semantics `copy.serverLivePill`. The pill stays on the card and the rows.
- **Module card, admission, invite intro:** R2 neutral (admission `xl`). The admission and invite intro edges are identity `foreground` @.30. The icon chip becomes radius 12 with a tonal identity gradient and loses its Pearl dark outline. The duplicate "Wydarzenia" link stays; it is flagged to the PM only.
- **Conversation bar** (not the nav dock):
  - Connected fill alphaBlend(audioAccent @.10 / .04, surfaceRaised); edge audioAccent @.45 / .35.
  - Pearl gets `blockShadows`; Dark gets none.
  - `_DockControl` becomes a `CircleBorder` with a neutral `glass` fill. The live mic gets BoxShadow(audioAccent @.36 / .20, blur 12, spread -4), bound to `isMicrophoneEnabled`.
  - Geometry is 1:1. Show Kamil before shipping.
- **Voice stage:**
  - `_MicrophoneOrb` ring: a 2.5 px SweepGradient of the `audioProgressGradient` colours.
  - Speaking tile: BoxShadow(audioAccent @.40, blur 12) only while `isSpeaking`.
  - **Bug fix:** the speaking border grows from 1.5 to 3 px inside the padding, which makes tiles jiggle. It becomes a foreground ring (also goes in docs/Bugs.md).
- **Panel subtitle:** a non-breaking space keeps "12 osób" together.
- **Responsive:** 390 is the phone surface plus the sheet. 768 and 1440 use the 216 / 256 / 296 px panels unchanged. 200 %: the stacked row branch runs inside the block. Reduce Motion: hover and lamp are static.

### 8.3 Chats (list, thread, composer)
- **Rows:**
  - The unread slab goes: no fill, no border, radius 16 in both states.
  - Unread is carried by `rowTitle` w700, `rowPreview` w500 in `textPrimary`, time in `focus` w700, and `YoCountBadge`.
  - The "…" stays visible, as `more_horiz_rounded` 20 in `textTertiary` with a 48 px target.
  - Presence dot halo 3 → 2.5 px.
  - Avatars `finish: brand`.
  - Voice, image and video previews lead with a 15 px glyph: mic in `audioAccent`, the others in the preview colour. The glyph is `ExcludeSemantics`, and the preview string is unchanged.
- **Header:** compose → R6 disc (40 visual / 44 target, `edit_square` white 20). Archive stays a bare 44.
- **Search:** R9 pill.
- **Friend rail:** action tiles become R7-accent ghost discs (58 px, `interactiveForeground` icon and label). Friend avatars `finish: brand`; the band becomes `hairline`.
- **Canvas:** `canvasGlow` getter (pixel-identical). In Pearl, `section: null` removes the ghost furniture.
- **Inbox empty:** the logo (§4) with a `YoButton` primary CTA. Archived and search empty states keep a 64 px circle with block fill, hairline and a `textSecondary` glyph.
- **Thread:**
  - Bubbles per R15. The shared `outgoingDecoration` is used by sent **and** queued bubbles.
  - Run grouping: `joinsOlder` / `joinsNewer` (same sender, same day, < 2 min apart, no reactions, no date break). The sender-side top corner becomes 6, spacing 6 → 2, and the meta row is hidden **only** when the next bubble shows the identical time, edit state and read state.
  - Voice bubble: R14 at 34 (incoming lit while playing; outgoing white @.22) and R13 with real position via `onPositionChanged` (reset to null on completion or source change).
  - Chrome: `hairline` header edge; call, video and "…" icons sit in 36 px glass discs inside the existing 44 px targets; the date separator becomes a pill; the typing bubble uses the incoming finish.
- **Composer:**
  - Top edge `hairline`; the round 48 px camera is `surfaceMuted` with a hairline; the field radius is 24 with `borderStrong` and left padding 18.
  - Mic, send and saving become R14 / R6 discs at 36 / 46 with a **contained** shadow: BoxShadow(`brandGlow` × .6, blur 10, y 3, spread -3). Keys `voice` / `send` / `saving` and the switcher are unchanged. `TextField` wiring is untouched.
- **Long-press sheet:** emoji sit in 48 px glass discs (≥ 44 at 320) with `TextScaler.noScaling`, which removes the 200 % overflow. Warning literals move to `warningForeground`. Radius 28 with a hairline top.
- **Recorder sheet:** W4 at rest only; #FF4F78 → `AppColors.live`.
- **Also:** `room_link_message_card` #7821E8 → `colors.primary`.
- **Responsive:** bubbles stay capped at 560 in the 880 frame. The thread chrome keeps its reflow logic. At 200 % the sheet no longer overflows.

### 8.4 YO Moments (Głos + Yeels + capture)
- **Feed card:**
  - R2 at radius 20 (from 14). The caption is w700 -0.2; an empty caption falls back to `titleMedium` w600 `textSecondary` (same string).
  - Transport: R14 bead 48 with R13 bars (36 / 3 / 2), and the time **under** the wave, end-aligned (the 88 px box goes).
  - W3 lights the playing card.
  - Expiry becomes the neutral R12 pill (same copy and position); it turns amber only under 1 h.
  - "Odpowiedz głosem" → R7 accent.
- **Author capsules:** pill radius, block fill + hairline, `elevated: false`. The heard/unheard state moves to a 38 px `MomentSeenAvatar` ring (same `ringColors`). Bars are single-colour `waveUnplayed`. The name is w700 when unheard and `textSecondary` w600 when heard.
- **Chips and switch** (`immersive_feed_chrome.dart`; Głos and Yeels ship together):
  - Canvas chips use R8.
  - Refresh sits in a 40 px hairline circle.
  - Format switch: selected `textPrimary` w800, unselected `textTertiary` w600; the underline is a 30 × 3 `AppGradients.primary` bar with a `brandGlow` shadow at blur 8.
  - Over media: selected white w800, unselected white @.78; the text shadows become [0x99000000 blur 12, 0x8C000000 blur 3 y1, 0xB3000000 blur 1 y1]. This is **gated** by an Accessibility measurement on a pure-white frame; if it fails, keep the 8-way stroke.
- **"+" and create:** the canvas and over-media "+" become an R6 disc at 48. Desktop "Utwórz" becomes `YoGradientFilledButton` (48, full width, current radius). Create-sheet tiles become R2 at radius 20 with a 44 px `primary @.14` icon circle.
- **Desktop local panel:** selected row = primary @.12 fill with a 1 px primary @.30 edge. The format badge loses its outline (glass fill, `textTertiary`). `MomentsFollowPanel` blocks use R2, so 1440 is uniform.
- **Detail:** player card R2; `_PlayDisc` → R14 (64 / 72), Semantics wrapper unchanged; waveform R13; reply CTA → R5; actions stay transparent with pill-shaped ink.
- **Skeleton:** the R2 shape, a 48 px circle bone plus a `YoWaveform` silhouette bone, and the time bone under the wave.
- **Empty and error:** R17.
- **Yeels (immersive):**
  - Plates go from 0xB8 to 0x8C (hover 0xD6 → 0xB3), plus a 1 px 0x24FFFFFF hairline when there is no ring.
  - Progress played becomes the theme-invariant [primary, secondary] gradient on the white @.32 track, 2 px. This fixes the teal-over-footage in Pearl.
- **Capture:** W4 plus the panel finish.
- **Responsive:**
  - Chips below 1100; the local panel at ≥ 1100. Feed column 640.
  - Detail disc: 64 below 600, 72 at 600 and above.
  - At 200 %: the time wraps under the wave, and the expiry pill wraps to 2 lines with the ring top-aligned.

### 8.5 Profile (own + friend, excluding the other session's header)
- **Blocks:** `_Panel`, the journey card and the pinned card use R2 (radius 20). **Gate:** `_Panel` adopts in the same release as the header session's stats band, so 12 and 20 never sit together.
- **Vibe sticker:** `primaryAction` gradient (begin (-1,-.35), end (1,.35)), radius `tile` (compact 14), no border, **no shadow**, and a white @.14 90 px circle top-end.
  - Ink: white "VIBE" 11 w800 +1.4 and white description 15 w700.
  - Link rows: contrastInk @.28 fill with a white @.18 edge, radius 12, and a 2 px white focus ring.
  - At a content width ≥ 700 the sticker is capped at 560 and start-aligned.
- **Actions:** "Edytuj profil" → `YoGradientFilledButton` (radius stays `ProfileActionBar.radius`). "Nagrody" and the more icon (44 × 44, passed into the existing `icon` slot, key `profile-more-button`) → R7 neutral. Friend profiles mirror this (small flagged edit).
- **Pinned Moment:** R14 bead at 52 (48 compact), lit only while playing, no card tint (budget).
- **Chips:** one neutral pill (the `glass` / Pearl white fill, `hairline`, 12.5 w600). The tone lives only on the icon.
- **Achievement progress:** an 8 px pill track filled with `primaryAction`, growing once over `entrance`.
- **Error:** `_ErrorView` → `YoErrorState`. Loading keeps the spinner (no fake skeleton).
- **Journey:** below 560 px it keeps today's rows. At ≥ 560 it shows 4-up cells: a 16 px icon and label, then a 22 w700 tabular value, with `hairline` dividers. Any width falls back to rows at ≥ 150 % text.
- **Wide measure:** at a content width ≥ 900, the body sections are capped at `ProfileLayout.wideMeasure` 640 and start-aligned, matching the header cluster. The banner stays full width.
- **Account rows:** 40 px glyph boxes (R16), row height 64, indent 68. The logout row stays in error ink.
- **Edit profile:** one radius family (preview 20, image actions 16 on both layers, fields back to theme 14). The account-type block is `YoCard`.

### 8.6 More (sheet + popover), Settings, Friends, Notifications
- **More sheet** (`more_sheet.dart`, flagged small edit):
  - R16 tiles and glyph boxes; staff rows keep their role colour.
  - Pearl sheet on `background` with the new shadow pair; the sheet border becomes `hairline`.
  - The popover gets radius 16, a hairline side and glyph boxes. Its opener (the rail item) is untouched.
- **Settings:**
  - Groups become R2 (danger keeps its error @.45 edge); dividers `hairline`.
  - Glyph boxes R16.
  - `_ProfileHeroCard` becomes `YoCard(tint: primary)`, the page's one lit block.
  - "Wersja" gets the logo at 40 via a new optional `leading` on `_SettingsTile`.
  - The group label inset goes 4 → 16, aligned with the rows.
  - `canvasGlow`.
- **Friends:**
  - `_FilterChip` → R8 (36 in 48, ink inversion).
  - Row message square and suggestion "Dodaj" → R7 neutral.
  - Avatars (friends, suggestions, add friend, blocked users, follow list) `finish: brand`.
  - `canvasGlow` getter.
  - The dev-style instructional copy is flagged to the owner; the copy stays.
- **Notifications:** system sender → logo (with the empty `actorId` guard); other avatars `finish: brand`.
- **Find creators:** chips R8.

### 8.7 Auth, Startup, TOTP
- **Startup:** W1 bloom + glint.
- **Auth:** **only** the two Image swaps to `YoBrandMark(light: bloom, glint: auth)`. Sizes unchanged. The provider buttons stay as they are (weakening their boundary was rejected).
- **TOTP:** `YoBrandMark(76, bloom)`.
- **Auth-gate error:** reuses `AuthBackdrop`, the logo at 64 with bloom, a 20 px `AppColors.error` icon before the unchanged title, and `AppImmersiveColors` roles in place of the literals. Retry is a `YoGradientFilledButton` (52 px, radius 12, full width, content capped at 440 on medium and wide).
- **Deferred (other session's file):** see the §10 handoff.
- All of these are immersive dark in both themes.

---

## 9. What explicitly does NOT change

- **Navigation:** the bead-and-socket dock (geometry, colours, beads, badge, motion, `NoSplash`) and the desktop rail (`desktop_sidebar.dart`, including its 30 px mark, gradient CTA, profile card avatar, `UserIdentityBadges`, `AvailabilityChip` and themed `IconButton`). No file of theirs is edited, and every token they read keeps its value.
- **Structure:** IA, screens, sections and their order, navigation, routes, keys, semantics labels and every feature. Głos and Yeels stay separate with their current filters. Servers remain the only shared space. No participants are shown before joining, and nothing fake is added (no counts, presence or waveforms without data).
- **Design system:** Material 3; Inter only (no display face); the palette family. Existing `AppColors` / `AppPalette` / `colorScheme` values, `AppTypography` styles, `AppRadius.card`, the `filledButtonTheme`, `iconButtonTheme` and `outlinedButtonTheme`, and the global splash.
- **Immersive surfaces:** Yeels, capture, story viewer, auth and startup stay dark in both themes. The `StoryWaveform` default, `moment_story_viewer.dart`, the voice-playback accent (`audioAccent` / `audioProgressGradient`) and `MomentProgressRing` are unchanged.
- **Copy:** Polish copy is unchanged ("ZALOGUJ SIĘ" uppercase is flagged to the PM only).
- **Other session's files, not edited:** `responsive_content_frame.dart`; `profile_banner.dart`, `profile_hero_backdrop.dart`, `profile_media_image.dart`, `profile_photo_viewer.dart`, `profile_preview_sheet.dart`; `accessible_tap_region.dart` (callers only pass arguments); `yo_segmented_pill.dart`; `yo_server_rail_item.dart`; `yo_channel_row.dart`; `yo_modal_sheet_chrome.dart` (callers only pass `surfaceColor`); `yo_recording_countdown.dart`; `profile_header.dart`; and `responsive_auth_screen.dart`, where only the two logo `Image` lines change.

---

## 10. Implementation batches

Every batch follows the CLAUDE.md loop, with `flutter analyze` clean and targeted tests plus the full suite before push. It needs the review cell: Flutter engineer → QA → Visual QA + Accessibility → Principal reviewer. **File lists do not overlap.** Tests are only updated where a spec value changed deliberately, never weakened.

**Parity baseline (before B1):** run `test/dock_visual_qa_screenshot.dart` and `test/desktop_sidebar_screenshot.dart` and keep the PNGs. After every batch, re-run both and diff: the result must be byte-identical.

| # | Batch | Files (exclusive) | Goal |
|---|---|---|---|
| 1 | Foundations (invisible) | `lib/core/theme/{app_palette,app_gradients,app_radius,app_motion,app_typography}.dart`; new `app_finish.dart`, `app_icons.dart`; `shared/widgets/cards/yo_card.dart`; new `buttons/yo_gradient_filled_button.dart`, `buttons/yo_gradient_disc.dart`, `interactions/yo_press_feedback.dart`, `badges/yo_count_badge.dart`, `badges/yo_progress_ring.dart`; `branding/yo_logo.dart`; new `assets/images/logo-bloom.png`; `profile/user_avatar.dart`; `waveform/yo_waveform.dart`; `states/yo_empty_state.dart`; `test/app_theme_test.dart`, `test/color_system_visual_qa.dart` + new unit tests; `docs/Decisions.md` (ADR-211), `docs/UI.md` | tokens, recipes, primitives and the logo widget; zero visible change for existing screens |
| 2 | Start pilot (mobile + desktop) | `features/home/.../shared/{home_greeting_header,home_live_now,home_server_overview,home_record_moment_card,home_overview_sections,recent_chats,home_section_status,home_friend_tile}.dart`; `.../mobile/mobile_home.dart`; `.../desktop/desktop_home.dart`; `shared/widgets/layout/home_section_header.dart`; `shared/widgets/backgrounds/yo_page_background.dart`; `lib/dev/redesign_preview.dart`; `test/slim_start_capture.dart` | W1 (Start part) + W2 + Start finish; frames shown to Kamil before B3 |
| 3 | Shared controls | `core/theme/app_theme.dart`; `shared/widgets/buttons/{yo_button,yo_icon_button}.dart`; `shared/widgets/inputs/{yo_search_field,yo_text_field}.dart`; `shared/widgets/badges/yo_badge.dart` | hairline controls app-wide |
| 4 | Servers | `features/servers/presentation/theme/server_identity.dart`; `.../screens/{servers_screen,server_workspace_screen}.dart`; `.../widgets/{server_panel,server_channel_scene,server_module_card,server_conversation_dock,server_voice_stage}.dart`; `test/slim_servers_capture.dart` | directory blocks, live session card, join CTA, sheet seam, jitter fix |
| 5 | Voice bead + Głos (W3) | `shared/widgets/voice/{voice_player_row,voice_core}.dart`; `features/moments/presentation/widgets/{moments_feed_view,moment_transport_controls,moment_card,moment_story_tile,yo_moments_chrome,moments_follow_panel}.dart`; new `.../widgets/moment_expiry_pill.dart`; `.../screens/moment_detail_screen.dart`; `shared/widgets/overlays/immersive_feed_chrome.dart`; `test/slim_moments_capture.dart` | W3 plus feed, detail, chips and switch |
| 6 | Capture + Yeels (W4) | `features/moments/presentation/screens/{record_voice_moment_screen,moments_screen}.dart`; `shared/widgets/overlays/immersive_overlay_atoms.dart`; `features/reels/presentation/widgets/reel_progress_row.dart`; `test/moments_discovery_screenshot.dart` | W4, recorder panels, "+", Yeels plates and progress |
| 7 | Chats | `features/messages/presentation/screens/{messages_screen,chat_screen}.dart`; `.../widgets/{message_bubble,room_link_message_card}.dart`; `test/slim_chats_capture.dart` | rows, bubbles, voice bubble, composer, grouping, Pearl canvas |
| 8 | Profile | `features/profile/presentation/screens/{profile_screen,edit_profile_screen}.dart`; new `.../widgets/profile_layout.dart`; `.../widgets/{profile_journey_card,profile_vibe_headline}.dart`; `features/creator/presentation/widgets/creator_pinned_moment_card.dart`; `features/friends/presentation/screens/friend_profile_screen.dart`; `test/slim_profile_capture.dart` | vibe, CTA, bead, chips, journey, wide measure |
| 9 | More, Settings, Friends, Notifications | `features/home/presentation/widgets/more_sheet.dart`; `features/settings/presentation/screens/settings_screen.dart`; `features/friends/presentation/screens/{friends_screen,add_friend_screen,blocked_users_screen}.dart`; `features/friends/presentation/widgets/friend_suggestion_card.dart`; `features/profile/presentation/screens/follow_list_screen.dart`; `features/creator/presentation/screens/find_creators_screen.dart`; `features/notifications/presentation/screens/notifications_screen.dart`; `test/slim_more_capture.dart` | tiles, groups, chips, tonal, logo surfaces |
| 10 | Auth + Startup (W1 rest) | `features/auth/presentation/widgets/startup_loading_screen.dart`; `features/auth/presentation/screens/{responsive_auth_screen (logo lines only),totp_challenge_screen,auth_gate}.dart`; `features/rooms/presentation/widgets/mini_player/active_room_mini_player.dart`; `test/slim_auth_capture.dart`, `test/startup_voice_glass_screenshot.dart` | bloom, glint, TOTP, auth-gate |
| 11 | Docs reconcile + sign-off | `docs/Roadmap.md`, `docs/Bugs.md`, new `docs/Sessions/<date>-refine-look.md` | record what shipped; full matrix re-run |

**Harness gaps to close in each batch:**
- `slim_start_capture.dart` must register a colour-emoji fallback font. On the macOS capture host try `/System/Library/Fonts/Apple Color Emoji.ttc` via `FontLoader`; otherwise use a repo-local OFL NotoColorEmoji under `test/fonts/`. A frame with a tofu box is rejected.
- It also needs a `YO_PREVIEW_LIVE_TYPE` fixture switch (in `lib/dev/redesign_preview.dart`) to capture each ServerType live.
- The Chats, Moments and Profile harnesses must add 768 px and 200 % text (today they capture 390 and 1440 at 100 % only), plus playing, queued and grouped states where relevant.

**Other-session handoff (proposals only; do not edit their files):**

| File | Proposal |
|---|---|
| `profile_header.dart` | Stats band → `YoCard` finish (20, hairline, Pearl shadow), released together with Profile `_Panel`. Remove the per-label `FittedBox` so every label is 12 w600. Replace the literal 640 with `ProfileLayout.wideMeasure`. Name plate: `hairline` edge, radius `tile`. `AccountTypeBadge` and the role pill as one 24 px glass pill family. The hero avatar adopts `UserAvatar(finish: brand)`. Keep `ProfileActionBar.radius` 12. No decorative avatar ring. |
| `responsive_auth_screen.dart` | `AuthPrimaryButton` → `YoGradientFilledButton(busy: loading \|\| relay)`, keeping 52 px, radius 12, keys and semantics. `AuthModeRail` selected: primary @.26 over surface + 1.5 px primary edge + white w700. If Accessibility rejects the boundary, keep the tile solid. |
| `yo_segmented_pill.dart` | Additive `thumbDecoration`, `selectedForeground` and `hairlineTrack`, for (a) server local tabs (Dark thumb alphaBlend(primary @.22, surfaceRaised) + 1 px foreground @.60; Pearl white + `blockShadows` + foreground @.70 edge; label `selectedForeground` w700) and (b) the ReelsToolbar Yeels filter adopting R8 ink inversion. |
| `yo_channel_row.dart` | Optional `selectedDecoration` via `Ink`. Dark [primary @.22, @.07] + primary @.40 edge. Pearl on white [primary @.12, @.04] + foreground @.30 edge + shadow @.06 blur 2 y1. Connected (wins over selected): audioAccent .16 → .05 (Pearl .10 → .03), edge .45 / .35. Later, `liveGlow` on LIVE rows. |
| `yo_server_rail_item.dart` | Optional, **Kamil's call**: a tonal (not saturated) face, [alphaBlend(primary @.20, surfaceRaised), alphaBlend(primary @.10, surface)] Dark / [lerp(primaryContainer, white, .45), primaryContainer] Pearl, with a primary @.28 / .30 edge. The rail item keeps tonal 1:1. |
| `yo_recording_countdown.dart` | Agree the W4 halo's maximum extent (~26 px) so the ring and the halo never overlap. |
| `profile_media_image.dart`, `profile_banner.dart`, `profile_hero_backdrop.dart`, `profile_photo_viewer.dart`, `profile_preview_sheet.dart` | No change needed. They inherit nothing unless `UserAvatar(finish: brand)` is adopted by the header. |

---

## 11. Verification matrix

**Gates for every batch:**
- `flutter analyze` clean.
- Targeted tests (see the batch list) plus the full suite.
- `semantic_color_source_guard_test` still at 27 roles.
- Dock and rail parity PNGs byte-identical.
- Visual proof in the capture frames under `yovoice-evidence/2026-09-2x/refine-look/frames/after/<area>/`, named `<screen>_<width>_<dark|pearl>_pl_<text>_<state>.png`, compared against `frames/before`.
- Device check on the iOS Simulator plus one real Android, for glint, haptics, the amplitude halo, gloss at 44 / 48 and the Pearl contact shadow. **UNVERIFIED** until rendered on the device.

| Area | Widths | Themes | Text | States | Motion / a11y | Specific checks |
|---|---|---|---|---|---|---|
| B1 primitives sheet | n/a | Dark, Pearl | 100, 200 | rest, hover, pressed, focus, disabled, busy, lit, HC | RM on/off | disc 34-96 gloss/rim legibility; logo 32/36/56/76/96/208 bloom; contrast table re-measured |
| Start | 390, 768, 1440 | Dark, Pearl | 100, 200 | populated × each ServerType live, no-live, loading, empty, error, long names | RM, HC, RTL (ar) spot | lockup box 32 px (~26 px ink), no tile; LIVE is the only glow; tint top-end (mirrored in RTL); no seam above the dock; no mid-word cut; no tofu; live arrival without a jump (video) |
| Shared controls | 390, 768, 1440 | Dark, Pearl | 100, 200 | Settings, Friends, notification prefs | HC boundaries | chips, icon buttons and search identifiable; Accessibility sign-off on WCAG 1.4.11 hairlines |
| Servers | 390, 768, 1440 | Dark, Pearl | 100, 200 | directory (1 / 2 columns, empty), workspace quiet / live / connected / held, sheet, all 5 templates | RM (lamp static), HC | equal-height pairs; join ring test on both stops; no glow before joining; no participants before join |
| Głos / detail | 390, 768, 1440 | Dark, Pearl | 100, 200 | loading, empty, error, populated, playing, paused, failed, uncaptioned, <1 h expiry | RM (no tween, stepped pour), HC (hairline, no glow) | exactly one lit card; no rebuild per tick (profile trace); waveform test "no frame scheduled" |
| Yeels + capture | 390, 768, 1440 | both (identical, immersive) | 100, 200 | Yeels feed, recorder idle / requesting / recording / review | RM, Accessibility measurement of chrome text on a white frame | halo follows real amplitude; static when silent or on web; plates legible |
| Chats | 390, 768, 1440 | Dark, Pearl | 100, 200 | empty, archived, search-empty, populated, unread, thread with voice playing, queued, failed, grouped run, long-press sheet | RM, HC, RTL | unread without colour alone (weight + count); sheet does not overflow at 200 %; grouped time rule |
| Profile | 390, 768, 1440 | Dark, Pearl | 100, 200 | own, friend, no photo, vibe with links, pinned playing, error | RM, HC | own and friend profiles identical; the 640 measure at 1440; journey 4-up at ≥ 560 |
| More family | 390, 768, 1440 | Dark, Pearl | 100, 200 | sheet, popover, Settings, Friends filters, Notifications (system sender) | HC | the Pearl band is gone; one lit block in Settings |
| Auth / Startup | 390, 768, 1440 | both (immersive) | 100, 200 | startup compact / regular, login, register, TOTP, auth-gate error | RM (static bloom), HC (no bloom) | frame 0 equals the native splash; at most one glint per launch; auth sizes unchanged |

**Performance:** profile build on the Redmi. Moments and Chats scroll jank must be ≤ the 3.0.0 baseline, with one glow at a time and no BackdropFilter added. Web at 1440 must hold 60 fps while the waveform pours.

---

## 12. Open decisions for Kamil and unresolved UX risks

1. **Voice playback colour. DECIDED by Kamil on 2026-09-25: variant B.** The played waveform uses the logo gradient, violet → magenta (implemented as `AppGradients.voicePlayed`: Dark lerp(primary, white, .40) #B082FA → lerp(AppColors.secondary, white, .32) #D46BFF with Dark `waveUnplayed` lowered .28 → .22, ≥ 3.14:1 played vs unplayed; Pearl the `primaryAction` pair #6F1FD1 → #A117D8). The raw logo pair fails 3:1 against unplayed bars (1.25 / 1.72:1), so the lightening is the minimum that keeps the saturated violet → magenta read. This replaces cyan → lavender for the played sweep only; `audioAccent` (the cyan connected/voice state) is a separate decision and stays. Original note: The played sweep stays cyan → lavender (`audioAccent`, the documented single voice accent). The alternative, logo violet → magenta, is a docs and brand decision for Kamil. It is one token swap (`audioProgressGradient`).
2. **Glint and gloss** can read as "cheap shine" if they are slightly off. Each has a named fallback: bloom only, and no rim.
3. **Start header reflow:** the controls stay where they are today, so there is no structural change. The pilot frames are the approval gate.
4. **Pearl scenery:** opacity .07 → .05 on all five destinations, and Chats in Pearl drops the lounge photo. Show both to Kamil.
5. **The Profile wide measure** leaves about 360 px of canvas empty at 1440 (a banner over a readable column). The alternative is the header session lifting its 640 cap.
6. **The conversation bar** (servers) is not the nav dock, but Kamil corrected dock restyles twice, so show it before shipping.
7. **Hairline control boundaries** (chips, icon buttons, search) sit at 1.3-1.4:1. They rely on text, glyph or hint identification and need Accessibility sign-off; high contrast restores `borderStrong`.
8. **The w800 → w700 type calming** touches many literals. It goes primitives first, owners next, so goldens and text-width tests will shift.
9. **Scaffold.extendBody** (content running under the dock) is deliberately **not** proposed; that is Kamil's call.
10. **ADR-211** must land in B1, superseding ADR-209's "Cards: radius 12, no decorative gradient, glow or shadow", "4 px tail / flat reaction pill / hairline separator" and "Titles 22 px w800". It must also clarify "one accent per screen" as the light budget. Owner: Technical Documentation Manager.
