# Build 37 (YO Voice 3.2.0+37) — the refine look, finished in the cloud — 2026-09-27

Decision: [ADR-227](../Decisions.md#adr-227-the-refine-look--afterglows-finish-on-the-30-layout-under-a-light-budget).
Spec: [briefs/2026-09-25-refine-look/spec.md](../briefs/2026-09-25-refine-look/spec.md).
Product account: [Roadmap.md](../Roadmap.md), the 3.2.0 (37) entry. Defects:
[Bugs.md](../Bugs.md), the refine-look section.

## What happened to the two Mac sessions

Two Remote Control sessions on Kamil's Mac carried the work: "Redesign yovoice
aplikacji" (the 3.0 Slim redesign, build 36 and the cost cuts) and "YO Voice
testowa aktualizacja" (the refine look). At 03:11 UTC on 2026-09-27 the Mac
became unreachable (`computer_unreachable` on both), so both stopped. Kamil
asked for both to be merged into one cloud session and continued there, and
for the old sessions to be stopped; both were archived.

What was on GitHub: `main` at 3.1.0+36 plus the cost cuts, and `refine/look`
with B1 foundations, B2 Start, B3 shared controls and a handoff brief
(`docs/briefs/2026-09-25-refine-look/HANDOFF.md`). Kamil's comparison page
showed that the Mac had also finished Servers, Voice and Capture/Yeels and
started Chats and Profile, but that code was never pushed and Kamil could not
reach a terminal on the Mac, so it was rebuilt here. The Mac's partial Servers
diff (`b4-wip.patch`) and its approved frames were the starting point for B4.
The unpushed work is still on the Mac's disk; nothing of it is needed now.

## How the work ran

- `refine/look` was replayed onto `main` (`bee13ce2`, one Dependabot commit
  ahead of its base); analyze clean, 264 refine tests green.
- Flutter 3.44.6 was installed in the container; macOS-only font paths in the
  capture harnesses were mapped to the Linux equivalents (Material fonts,
  Noto Color Emoji), so every harness renders here.
- Each remaining batch ran in its own git worktree: an implementing Flutter
  engineer, then an independent visual+accessibility review and a code review
  in parallel, then a fix round on every blocker, major and minor finding.
  Batches: B4 Servers, B5 Voice + Głos, B6 Capture + Yeels, B7 Chats, B8
  Profile, B9 More/Settings/Friends/Notifications, B10 Auth + Startup, plus
  the B12 handoff files inside the owning batches.
- Two cross-batch rounds followed: the gradient-CTA focus indicator, the
  channel-row focus shift and the TOTP glow; and the chat voice bubble wired
  to B5's bead API with one voice at a time.
- A final release review (code/release, cross-screen visual consistency,
  accessibility) with adversarial verification of every blocker/major
  finding closed the work before landing. It confirmed two majors — keyboard
  focus invisible on the chat recorder's bead (a regression of build 36) and
  two rings at once on Chats and Servers rows — and refuted a third at its
  stated severity; both majors and most minors were fixed in the same round
  (see the Bugs entry "the final review of build 37").
- `main` requires linear history, so the release lands as a rebased series.

## What was verified

| Check | Result |
| --- | --- |
| `flutter analyze` | No issues, after every batch and on the release tree |
| Full Flutter suite on the integrated tree | 6179 / 6179 after the batches; 6234 / 6234 on the release candidate before the final-review fixes (the final run is recorded under Release) |
| Targeted suites per batch on the integrated tree | B4 713, B5 747, B6 784, B7 623, B8 514, B10 575, voice bubble 623, cross-batch 243 — all green |
| Dock / rail parity | Dock PNGs byte-identical, rail frames identical in columns 0..263, after every batch, against a base rendered in the same hour |
| Visual evidence | About 900 Flutter test-renderer frames at 390/768/1440, Dark and Pearl, 100/200 % text, high contrast, focus, hover, RTL spot, each looked at by the engineer and an independent reviewer |
| Real browser | The production web build rendered in Chromium (CanvasKit): the sign-in screen with the real logo, its bloom and the gradient CTA, at 390 and 1440 |
| Web release build | `flutter build web --release` compiles |

## What was NOT verified

- **No device.** The glint, the bead's gloss and rim at 34–52 px, the W4
  amplitude halo, haptics and the Pearl contact shadow are UNVERIFIED on an
  iPhone or Android phone. If the glint reads as a cheap shine on a phone,
  the spec's fallback (bloom only) is one flag.
- **Signed-in screens in a real browser.** Only the sign-in screen was
  rendered in Chromium; the rest needs an account, and no test account was
  created in production.
- **Store builds.** The store workflow (`store-release.yml`, ADR-225) has no
  secrets and needs Kamil's approval on its environment, so iOS and Android
  builds for testers are Kamil's step (see the release record below).

## Release

The release record — the `main` commit, the Hosting deploy run and its
read-back — is appended below by the release commit.
