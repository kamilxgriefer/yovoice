# Startup: Voice Glass and removal of the old web splash

## Scope

Approved loading-screen artwork is now a Flutter composition, not a flattened
picture containing UI. The latest user decision removes the old browser HTML
splash completely. Before the Flutter engine is ready, the web page has only
the matching `#0D0618` canvas. Native OS launch surfaces are separate and remain
unchanged. The original isolated slice added no minimum loading time. The
integrated Build 27 flow now keeps Voice Glass visible for at least 1.4 seconds;
authentication and profile provisioning can keep it visible longer and still
determine when the app is ready to open.

The final hierarchy is a prominent YO VOICE wordmark (36 px; compact 28 px),
with supporting localized copy (20/22 px; compact 18 px). Background art drifts
and breathes while a broad alpha-only light pass crosses it. The bottom light
is a long comet rather than a moving dot. All four seamless subcycles share
one 18-second clock. Motion stops for reduced motion, accessible navigation,
high contrast, background lifecycle states, and disabled TickerMode.

Four short headlines rotate between app launches. A launch keeps its selected
headline stable across widget rebuilds and authentication stages. Selection
uses best-effort local preferences without adding an awaited startup gate.
Four headlines plus the loading status have 215 entries across all 43 selectable
locale variants. Text and semantics declare the selected locale. Large text
can scroll rather than being truncated.

## Scoped file manifest

- `lib/features/auth/presentation/widgets/startup_loading_screen.dart`
- `lib/features/auth/presentation/widgets/startup_launch_copy.dart` (new)
- `lib/core/localization/translations/translations_startup.dart` (new)
- `lib/main.dart`: import and unawaited headline preparation only
- `lib/core/localization/translations/app_translation_catalog.dart`: startup
  import, key-set spread and locale-map spread only; other catalog changes
  belong to the parallel Server-first integration and must be preserved
- `assets/images/startup_voice_glass_v1.webp` (new)
- `web/index.html`: old overlay/CSS/markup removed; metadata, PWA and email
  redirect logic preserved
- `web/flutter_bootstrap.js`: removed obsolete overlay teardown and timer;
  engine initialization and `runApp` preserved
- `lib/dev/startup_voice_glass_preview.dart` (new, isolated developer entrypoint)
- `test/startup_loading_screen_test.dart`
- `test/startup_launch_copy_test.dart` (new)
- `test/startup_localization_test.dart` (new)
- `test/startup_voice_glass_screenshot.dart` (new, explicit visual harness)
- `test/web_favicon_test.dart`: old splash regression replaced with single
  Flutter-owned loading-surface assertions; favicon checks preserved
- This session report

No AuthGate logic, package dependencies, native deployment targets, permissions,
backend services or store release settings were changed by this slice.

## Visual asset provenance

The approved concept was refined through the image-generation tool into
background-only artwork: preserve the obsidian backdrop, embossed YO silhouette
and translucent purple glass ribbon; remove the foreground logo, wordmark,
headline, bottom status and native home indicator. Flutter renders those UI
elements using the real existing logo and localized text.

Generated source: `exec-6458ba7f-a4c0-489e-99df-2566b0f4b92d.png` in the current
conversation's generated-images directory. Production WebP is 852 × 1846 and
37,890 bytes, compressed at quality 90. The existing image asset directory is
already registered; no pubspec asset entry is required.

## Verification evidence and limitations

- 114 focused startup, rotation, localization, web/favicon and Server-first
  cutover tests passed after HTML splash removal, final motion/hierarchy
  changes and the parallel owner's catalog cutover. Nine of these tests belong
  to the other task's `server_surface_cutover_test.dart`; its source was not
  changed here.
- Principal review found a Bold Text measurement mismatch. Headline and
  decorative wordmark now explicitly use the same w700 weight that Flutter
  renders for this system setting. All 73 startup widget tests passed after
  the fix, including two new PL/AR cases at 320 × 568, 200% plus Bold Text.
- 13 real-font visual configurations passed the capture harness. Final PNGs:
  `/private/tmp/yovoice-startup-visual-v2`. Coverage includes 320/390/430 px
  phones, tablet, wide and desktop layouts, 200% text, RTL and high contrast.
  The narrow large-text case additionally samples the moving artwork every
  three seconds through 15 seconds.
- Live in-app browser preview at `http://127.0.0.1:8773/` was reloaded after
  removal. The old markup is absent from served HTML and only the new Flutter
  composition is visible. A real web render of `?lang=zh_CN&headline=3` showed
  complete Chinese text, including 一 and 正; the earlier widget-test Ahem
  fallback artifacts are not reproduced in that runtime.
- Final accessibility and visual reviews: PASS, no confirmed open P1/P2.
  Twenty final captures were inspected. Recorded-frame contrast minima were
  7.72:1 for headlines and 7.47:1 for the loading status; the conservative
  full-cycle model also passed the applicable text thresholds. The principal
  review confirmed the Bold Text finding closed and no open P1/P2 in this
  scoped change. This is not whole-app release approval.
- Whole-tree analysis found eight unrelated findings in the parallel Server
  integration, plus two deprecated FontWeight.index uses in this slice's
  tests. Those two are corrected to FontWeight.value; the other owner was
  notified. Final scoped `dart analyze` over the startup widget, helper,
  translation module, preview and five test/harness files found no issues.
  The release owner must rerun the whole-tree gate after parallel edits settle.
- An isolated iOS Simulator launch was attempted on the otherwise unused
  iPhone 17 (`D27EA9A8-DCE1-480D-871A-2282E43EB835`) and failed: Firebase Swift
  package products require iOS 15 while the target resolves as iOS 13. This
  pre-existing native build configuration is owned by the release task and was
  not modified here. No successful native build or physical-device screen
  reader/locale verification is claimed.
- AuthGate may crossfade between two startup widget instances during auth to
  profile-bootstrap handoff. Existing functional boundaries and durations are
  preserved. A reviewer flagged possible duplicate entrance animation as a
  visual follow-up, not a demonstrated authentication defect.

### Build 27 integration update

The later Build 27 integration adds the 1.4-second minimum presentation window
described above. It changes neither the four-headline selection nor the
authentication/profile readiness conditions. The consolidated candidate status,
including the held backend and tester-release boundaries, lives in
[2026-09-13-build-27-internal-tester-candidate.md](2026-09-13-build-27-internal-tester-candidate.md).

## Integration handoff

The main release owner is the Codex task “Dodaj 4 ekrany typów serwerów”. It owns
the shared dirty tree, Server-first catalog migration, native build repair,
atomic integration commit and eventual release. This startup slice must be
included with all three startup catalog additions; do not stage the whole
catalog while discarding that task's changes. No commit, push, deployment or
tester notification was performed from this startup task.

The old unused preview on 8772 was stopped. Preview 8773 remains user-facing.
Preview 8769 and the other task's logged-in simulators were not modified.
