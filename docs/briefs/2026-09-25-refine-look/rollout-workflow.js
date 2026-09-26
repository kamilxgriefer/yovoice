export const meta = {
  name: 'yovoice-refine-rollout-v2',
  description: 'Continue the approved refine/look rollout on build 36: fresh baseline, batch 3 real-screen evidence, then the next batches with implement → capture → review → fix, retrying dead agents',
  phases: [
    { title: 'Baseline', detail: 'before-frames from build 36 (3445a1ae)' },
    { title: 'Implement', detail: 'code + targeted tests + analyze' },
    { title: 'Capture', detail: 'after-frames + dock/rail parity' },
    { title: 'Review', detail: 'visual QA + accessibility' },
    { title: 'Fix', detail: 'fix, re-capture, re-check' },
  ],
}

const WT = '/Users/kamil/Documents/GitHub/tmp/refine-look'
const BASE_WT = '/Users/kamil/Documents/GitHub/tmp/refine-before'
const EVD = '/Users/kamil/Documents/GitHub/yovoice-evidence/2026-09-25/refine-look'
const FL = '/Users/kamil/Documents/GitHub/tmp/fl.sh'
const BASE_SHA = '3445a1ae'
const STEPS = (args && args.steps) || []

const BATCH_INFO = {
  3: { name: 'Shared controls', area: 'controls', harness: 'test/slim_more_capture.dart (Settings/More/Friends) and test/refine_controls_capture.dart' },
  4: { name: 'Servers', area: 'servers', harness: 'test/slim_servers_capture.dart', extra: `A previous attempt on the OLD base died before capturing; its partial diff is ${EVD}/b4-wip.patch (reference only — main changed the servers files since: podcast host queue, waiting dot, server delete, etc.). Re-implement on the current code; reuse good parts of the patch by hand, never apply it blindly.` },
  5: { name: 'Voice bead + Głos (W3)', area: 'moments', harness: 'test/slim_moments_capture.dart' },
  6: { name: 'Capture + Yeels (W4)', area: 'capture', harness: 'test/moments_discovery_screenshot.dart and test/slim_moments_capture.dart (Yeels/recorder states if available)' },
  7: { name: 'Chats', area: 'chats', harness: 'test/slim_chats_capture.dart' },
  8: { name: 'Profile', area: 'profile', harness: 'test/slim_profile_capture.dart' },
  9: { name: 'More, Settings, Friends, Notifications', area: 'more', harness: 'test/slim_more_capture.dart' },
  10: { name: 'Auth + Startup (W1 rest)', area: 'auth', harness: 'test/slim_auth_capture.dart and test/startup_voice_glass_screenshot.dart' },
  12: { name: 'Handoff files (profile header, auth primary button, segmented pill, channel row)', area: 'handoff', harness: 'test/slim_profile_capture.dart, test/slim_auth_capture.dart, test/slim_servers_capture.dart', extra: `Follow ${EVD}/handoff-notes.md exactly (pinned tests and ADR-219/220/221/222 behaviour) and spec §10 "Other-session handoff". yo_server_rail_item.dart stays untouched.` },
}

const RULES = `
CONTEXT: YO Voice (Flutter). Kamil APPROVED the "simple but super wow" refinement (spec: ${EVD}/spec.md — read the parts for your batch; it is the source of truth). Waveform variant B is decided
(AppGradients.voicePlayed + Dark waveUnplayed .22). Kamil: "pamiętaj aby nie ruszać graficznie paska nawigacyjnego" — the navigation dock must stay visually untouched, and the desktop rail too.
The sandbox worktree ${WT} (branch refine/look) is now REBASED onto build 36 (origin/main ${BASE_SHA}); batches 1–3 are committed there (git log). Read the existing primitives
(lib/core/theme/app_finish.dart, lib/shared/widgets/{cards,buttons,badges,interactions,branding}, user_avatar finish, yo_waveform) before building on them.

SANDBOX RULES (strict):
- Edit files ONLY inside ${WT} (Baseline may use ${BASE_WT}). Never touch /Users/kamil/Documents/GitHub/yovoice or other worktrees.
- Do NOT commit, push, merge, rebase, reset, clean, stash or switch branches (repo rule: subagents never commit; the main session commits). Leave changes in the working tree.
- No deploys, no Firebase commands.
- Flutter/Dart ONLY through the shared machine lock: ${FL} <worktree> <flutter args...>. Exit code 75 = lock busy → run the SAME command again (loop up to 40 times).
  Never run flutter directly, never two at once, never the full suite, no --coverage. Keep each flutter invocation focused (one test file or a few).
- Never edit the navigation dock files or lib/features/home/presentation/widgets/desktop/desktop_sidebar.dart or lib/shared/widgets/navigation/yo_server_rail_item.dart.
  lib/shared/widgets/layout/responsive_content_frame.dart, lib/shared/widgets/profile/{profile_banner,profile_hero_backdrop,profile_media_image,profile_photo_viewer,profile_preview_sheet}.dart,
  lib/shared/widgets/interactions/accessible_tap_region.dart, lib/shared/widgets/overlays/yo_modal_sheet_chrome.dart and lib/shared/widgets/media/yo_recording_countdown.dart: callers may pass arguments, do not edit them.
  profile_header.dart, responsive_auth_screen.dart, yo_segmented_pill.dart and yo_channel_row.dart are editable ONLY in batch 12 (handoff), per ${EVD}/handoff-notes.md.
- Keep every feature, key, semantics label and Polish copy. No fake data. Material 3, Inter only, colours via app_colors/app_palette/app_finish tokens (no new hex literals in widgets).
- Honour the light budget (spec §3). Dark + Pearl, 390/768/1440, 100% + 200% text, Reduce Motion and high contrast.
- Never weaken a test; update an assertion only where the spec deliberately changes it, and list it.
- Be honest: what was verified by rendering vs. only by code. Look at every frame you produce with Read.
- If you find the worktree already contains partial work for your task (git status / git diff), a previous agent died mid-task: inspect it and continue from it rather than starting over.
`

const RETRY_NOTE = `\n\nNOTE: a previous attempt at exactly this task died mid-way (no report). Start by inspecting \`git -C ${WT} status\` and \`git -C ${WT} diff\` and any files it wrote under ${EVD}, then continue from there. Keep your context lean: read only what you need.`

async function run(prompt, opts) {
  let r = await agent(prompt, opts)
  if (r == null) {
    log(`${opts.label} returned nothing; retrying once`)
    r = await agent(prompt + RETRY_NOTE, { ...opts, label: `${opts.label}-retry` })
  }
  return r
}

const IMPL = {
  type: 'object',
  properties: {
    summary: { type: 'string' },
    filesChanged: { type: 'array', items: { type: 'string' } },
    analyze: { type: 'string' },
    testsRun: { type: 'array', items: { type: 'object', properties: { file: { type: 'string' }, result: { type: 'string' } }, required: ['file', 'result'] } },
    testsUpdated: { type: 'array', items: { type: 'string' } },
    deviations: { type: 'array', items: { type: 'string' } },
    proposedCommitMessage: { type: 'string' },
  },
  required: ['summary', 'filesChanged', 'analyze', 'testsRun', 'testsUpdated', 'deviations', 'proposedCommitMessage'],
}
const CAPTURE = {
  type: 'object',
  properties: {
    summary: { type: 'string' },
    commands: { type: 'array', items: { type: 'string' } },
    frames: { type: 'array', items: { type: 'string' } },
    parity: { type: 'string' },
    selfReview: { type: 'string', description: 'what you saw comparing after vs before, and what you fixed' },
    filesChanged: { type: 'array', items: { type: 'string' } },
    unverified: { type: 'array', items: { type: 'string' } },
  },
  required: ['summary', 'commands', 'frames', 'parity', 'selfReview', 'filesChanged', 'unverified'],
}
const DEFECTS = {
  type: 'object',
  properties: {
    verdict: { type: 'string' },
    defects: {
      type: 'array',
      items: {
        type: 'object',
        properties: { id: { type: 'string' }, severity: { type: 'string', enum: ['high', 'medium', 'low'] }, where: { type: 'string' }, problem: { type: 'string' }, fix: { type: 'string' } },
        required: ['id', 'severity', 'where', 'problem', 'fix'],
      },
    },
  },
  required: ['verdict', 'defects'],
}

const PARITY = `PARITY: run test/dock_visual_qa_screenshot.dart and test/desktop_sidebar_screenshot.dart (see their headers) into ${EVD}/frames/parity/after-<step>/ and compare with the build-36 parity baseline ${EVD}/frames/parity/before-b36/ ` +
  `(dock PNGs must be byte-identical via cmp; for the rail full-frame shots compare only the rail columns 0..263 with a small python PNG reader — content-area differences are expected). If ${EVD}/frames/parity/before-b36/ does not exist yet, it is produced by the Baseline step.`

const out = { steps: [] }

for (const step of STEPS) {
  if (step === 'baseline') {
    phase('Baseline')
    const b = await run(
      `${RULES}\n\nBASELINE TASK: refresh the "before" frames from the UNTOUCHED build-36 code.\n` +
      `1. ${BASE_WT} exists as a detached worktree at 1bb1b919 with no local edits (verify with git status; if it has edits, STOP and report). Move it: \`git -C ${BASE_WT} checkout --detach ${BASE_SHA}\` (fetch is already done; this is the only git write allowed). Then \`${FL} ${BASE_WT} pub get\`.\n` +
      `2. Parity baseline for build 36: run test/dock_visual_qa_screenshot.dart and test/desktop_sidebar_screenshot.dart from ${BASE_WT} into ${EVD}/frames/parity/before-b36/.\n` +
      `3. Re-capture the before-frames of every area from ${BASE_WT} into ${EVD}/frames/before-b36/<area>/ (areas: start, servers, moments, chats, profile, more, auth, capture, startup), using the fullest matrix each harness supports ` +
      `(the previous baseline's commands are recorded in ${EVD}/frames/before/ file names; read each harness header for the dart-defines). Do not edit files in ${BASE_WT}.\n` +
      `Return per area: command, frame count, dir, problems.`,
      {
        label: 'baseline:b36', phase: 'Baseline', model: 'opus',
        schema: { type: 'object', properties: { areas: { type: 'array', items: { type: 'object', properties: { area: { type: 'string' }, command: { type: 'string' }, frames: { type: 'integer' }, dir: { type: 'string' }, problem: { type: 'string' } }, required: ['area', 'command', 'frames', 'dir'] } }, parity: { type: 'string' } }, required: ['areas', 'parity'] },
      },
    )
    out.steps.push({ step, baseline: b })
    continue
  }

  if (step === 'b3-evidence') {
    phase('Capture')
    const cap = await run(
      `${RULES}\n\nTASK: batch 3 ("Shared controls": theme chip/card sides, YoButton, YoIconButton, YoSearchField/YoTextField search variant, YoBadge) is implemented and committed, but its real-screen evidence is missing: ` +
      `the reviewers found test/refine_controls_capture.dart broken and no real screen rendered. Repair that harness (or use test/slim_more_capture.dart if it covers the same screens) and render REAL screens that use these controls — ` +
      `Settings, Friends (filter chips, search, Dodaj), notification preferences, and one screen with a YoButton primary — at 390 and 1440, Dark and Pearl, 100% and 200%, plus one high-contrast frame, into ${EVD}/frames/after/controls/. ` +
      `Before-frames for the same screens: ${EVD}/frames/before-b36/more/ (and ${EVD}/frames/before/more/). ${PARITY}\nCompare after vs before yourself; fix only harness problems or clear regressions of batch 3 (list them).`,
      { label: 'b3:evidence', phase: 'Capture', schema: CAPTURE, agentType: 'senior-flutter-product-engineer', model: 'opus' },
    )
    const rev = await run(
      `${RULES}\n\nREVIEW batch 3 "Shared controls" (read-only). Compare ${EVD}/frames/after/controls/ with the matching before-frames (${EVD}/frames/before-b36/more/, ${EVD}/frames/before/more/), open images with Read. ` +
      `Visual craft + accessibility lens (hairline control boundaries: identifiable? 200% text; focus; high contrast). Each defect must be visible in a named frame or line.\n\nCAPTURE REPORT:\n${JSON.stringify(cap)}`,
      { label: 'b3:review', phase: 'Review', schema: DEFECTS, agentType: 'senior-visual-quality-specialist', model: 'opus' },
    )
    let fix = null
    if (rev && rev.defects.some((d) => d.severity !== 'low')) {
      fix = await run(
        `${RULES}\n\nTASK: fix these batch-3 review findings (high/medium; low if cheap), re-run targeted tests + analyze, re-capture into ${EVD}/frames/after/controls/, parity check. Do not commit.\n\n${JSON.stringify(rev.defects, null, 1)}`,
        { label: 'b3:fix', phase: 'Fix', schema: CAPTURE, agentType: 'senior-flutter-product-engineer', model: 'opus' },
      )
    }
    out.steps.push({ step, cap, rev, fix })
    continue
  }

  const n = step
  const info = BATCH_INFO[n]
  const before = `${EVD}/frames/before-b36/${info.area === 'handoff' ? '{profile,auth,servers}' : info.area}/`
  phase('Implement')
  const impl = await run(
    `${RULES}\n\nTASK: implement BATCH ${n} "${info.name}" (spec §10 file list; details in §3 recipes, §4 logo, §5 signature moments, §7 primitives, §8 per-screen) in ${WT}. ` +
    `${info.extra || ''}\nThis step is CODE ONLY: implement, grep test/ for every widget/key/file you touched and run those targeted tests, flutter analyze clean. Do NOT capture frames (the next step does). ` +
    `Close the harness gaps the spec names for this area in its capture harness (${info.harness}) so the next step can render 768 px, 200 % text and the relevant states. Propose a commit message.`,
    { label: `b${n}:implement`, phase: 'Implement', schema: IMPL, agentType: 'senior-flutter-product-engineer', model: 'opus' },
  )
  phase('Capture')
  const cap = await run(
    `${RULES}\n\nTASK: batch ${n} "${info.name}" is implemented in the working tree (report below). Capture the AFTER frames with ${info.harness} into ${EVD}/frames/after/${info.area}/, ` +
    `using the same file names as the before-frames in ${before} where they exist (fullest matrix: 390/768/1440, Dark/Pearl, 100/200 %, the states the spec names). ${PARITY}\n` +
    `Then compare after vs before yourself (Read the images) and fix anything clearly worse or broken (clipping, overflow, tofu, misalignment), re-capturing what you fix. Do not commit.\n\nIMPLEMENTATION:\n${JSON.stringify(impl)}`,
    { label: `b${n}:capture`, phase: 'Capture', schema: CAPTURE, agentType: 'senior-flutter-product-engineer', model: 'opus' },
  )
  phase('Review')
  const reviewPrompt = (lens) => `${RULES}\n\nREVIEW batch ${n} "${info.name}" (read-only: no edits, no flutter, no git writes; Read/grep/ls and read-only git diff are fine). Lens: ${lens}.\n` +
    `Compare ${EVD}/frames/after/${info.area}/ with ${before} (and the sheet ${EVD}/frames/sheet/ where relevant). Open images with Read. Check the spec for this batch, the light budget, the hard rules ` +
    `(dock/rail untouched; no fake data; IA unchanged; \`git -C ${WT} diff --stat\` must not list forbidden files), and whether anything reads cheap. Each defect must be visible in a named frame or line.\n\n` +
    `IMPLEMENTATION:\n${JSON.stringify(impl)}\n\nCAPTURE:\n${JSON.stringify(cap)}`
  const [vis, a11y] = await parallel([
    () => run(reviewPrompt('visual quality and craft'), { label: `b${n}:review-visual`, phase: 'Review', schema: DEFECTS, agentType: 'senior-visual-quality-specialist', model: 'opus' }),
    () => run(reviewPrompt('accessibility (contrast of new recipes in both themes, 200 % text, reduce motion / high contrast in code, semantics + keys preserved, focus, targets)'), { label: `b${n}:review-a11y`, phase: 'Review', schema: DEFECTS, agentType: 'accessibility-and-inclusive-design-specialist', model: 'opus' }),
  ])
  const found = [...((vis && vis.defects) || []), ...((a11y && a11y.defects) || [])]
  const serious = found.filter((d) => d.severity !== 'low')
  log(`batch ${n}: ${serious.length} high/medium, ${found.length - serious.length} low`)
  let fix = null
  let recheck = null
  if (found.length > 0) {
    phase('Fix')
    fix = await run(
      `${RULES}\n\nTASK: fix the review findings for batch ${n} "${info.name}" in ${WT}. High/medium: fix each or explain precisely why it is not a defect. Low: fix if cheap and safe. ` +
      `Re-run affected targeted tests + analyze, re-capture affected frames into ${EVD}/frames/after/${info.area}/ (overwrite). ${PARITY.replace('after-<step>', `after-b${n}-fix`)} Do not commit.\n\n` +
      `FINDINGS:\n${JSON.stringify(found, null, 1)}`,
      {
        label: `b${n}:fix`, phase: 'Fix', agentType: 'senior-flutter-product-engineer', model: 'opus',
        schema: { type: 'object', properties: { report: CAPTURE, perDefect: { type: 'array', items: { type: 'object', properties: { id: { type: 'string' }, outcome: { type: 'string', enum: ['fixed', 'not-a-defect', 'deferred'] }, note: { type: 'string' } }, required: ['id', 'outcome', 'note'] } }, proposedCommitMessage: { type: 'string' } }, required: ['report', 'perDefect', 'proposedCommitMessage'] },
      },
    )
    if (serious.length > 0) {
      recheck = await run(
        `${RULES}\n\nRE-CHECK batch ${n} (read-only). Verify each claimed fix against the re-captured frames and the code; look for NEW problems. High/medium only.\n\nFINDINGS:\n${JSON.stringify(serious, null, 1)}\n\nFIXER:\n${JSON.stringify(fix, null, 1)}`,
        { label: `b${n}:recheck`, phase: 'Fix', schema: DEFECTS, agentType: 'senior-visual-quality-specialist', model: 'opus' },
      )
    }
  }
  out.steps.push({ step: n, impl, cap, review: { visual: vis, a11y }, fix, recheck })
}
return out
