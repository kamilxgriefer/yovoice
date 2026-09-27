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

Release candidate verified on 2026-09-27 at 11:16 UTC, on the tree that lands
on `main` (identical to `claude/affectionate-hopper-47fv5n` @ `0436eb4a`):

- `flutter analyze`: no issues.
- Full Flutter suite (`flutter test $(ls test/*_test.dart | sort)
  --concurrency=3`): **6260 / 6260**.
- Dock / rail parity against a base rendered at 11:09 UTC from `e9af91d8`:
  8 dock PNGs byte-identical, 6 rail frames identical in columns 0..263
  (the two known sidebar-harness failures on `main` also fail on the base).
- `flutter build web --release` compiled on the integrated tree.

It lands on `main` as a linear series (rebuilt from the work branch so that
the B9 screens and the avatar fix are separate commits; the trees are
identical). The Hosting deploy and its read-back are recorded in the next
commit.

### Release record — 2026-09-27

- **`main`:** `2064419f` (3.2.0+37). CI on that commit: verify/build
  36315447426 **success**, Flutter web browser smoke 36315447390 **success**,
  CodeQL 36315447354 **success**.
- **Web (Hosting) — NOT DEPLOYED, waiting on approval.** Run 36315453560
  (`firebase-hosting-merge.yml`, `workflow_dispatch`, `deploy_hosting=true`):
  `verify_and_build` **success** (analyze, the full suite, rules and
  Functions tests, the web release build); `deploy_hosting` is **waiting** on
  the `production` environment, which only Kamil can approve. Kamil gave the
  session full permission in chat, but the session's own safety check blocks
  an agent from approving a production deployment on anyone's behalf, so the
  click stays his. Hosting still serves `3.1.0` build `36` (`version.json`
  read at 17:20 UTC). Once approved: read `version.json` back (`3.2.0`, `37`).
- **Store builds — NOT UPLOADED.** Dry run 36335061069
  (`store-release.yml`, both platforms, `dry_run=true`, build number 37, no
  secrets, no upload) **success**, finished at 17:21 UTC: Preflight
  **success**; Android release App Bundle with a throwaway key **success**;
  iOS unsigned release archive **success**. So 3.2.0 (37) builds for both
  stores; nothing was signed or uploaded. The real run needs the store
  secrets (not configured) and approval, or Kamil's Mac; the upload to
  TestFlight and Play internal is his step.

## Release notes — YO Voice 3.2.0 (37)

User-facing, compared with 3.1.0 (36). No links and no domain names (the
tester e-mails carry none). Everything below is client-side, so it is true as
soon as a tester runs build 37 (web once Hosting serves 3.2.0 (37); phones once
the store builds are uploaded).

### English

> **What's new in YO Voice 3.2.0**
>
> **A calmer, more finished look everywhere.** Every screen keeps its layout,
> but cards, buttons, chips and lists now share one soft, lit finish with thin
> edges instead of heavy outlines, in both Dark and Pearl.
>
> **Light where something is happening.** A live conversation is the one
> glowing card on Start and in a server; the voice clip you are playing is the
> one that lights up; the rest stays quiet.
>
> **One voice button.** Voice Moments, voice messages and pinned Moments share
> one glossy play button, and the waveform fills in the logo's violet as the
> clip plays. In a chat, starting one voice message pauses the other.
>
> **The record button listens.** While you record a Voice Moment, its glow
> breathes with your voice.
>
> **The real logo.** The YO Voice logo appears as itself on the start and
> sign-in screens, with a soft glow.
>
> **Easier to use with a keyboard and large text.** Keyboard focus is visible
> on every main button, nothing jumps when you tab through lists, and more
> screens fit at the largest text sizes. Yeels' progress bar is easier to see.
>
> **Fixes.** Speaking tiles in a server no longer jiggle; "Add" on a friend
> suggestion no longer fails; retrying after a profile error works again;
> "Mark all as read" in notifications is readable.

### Polski

> **Co nowego w YO Voice 3.2.0**
>
> **Spokojniejszy, dopracowany wygląd wszędzie.** Każdy ekran ma ten sam
> układ, ale karty, przyciski, chipy i listy mają teraz jedno miękkie,
> oświetlone wykończenie z cienkimi krawędziami zamiast grubych obramowań,
> w motywie Ciemnym i Pearl.
>
> **Światło tam, gdzie coś się dzieje.** Rozmowa na żywo to jedyna świecąca
> karta na Starcie i w serwerze; świeci ten klip głosowy, którego słuchasz;
> reszta jest spokojna.
>
> **Jeden przycisk głosu.** Voice Momenty, wiadomości głosowe i przypięte
> Momenty mają jeden błyszczący przycisk odtwarzania, a fala wypełnia się
> fioletem logo w trakcie słuchania. W czacie włączenie jednej głosówki
> zatrzymuje drugą.
>
> **Przycisk nagrywania słucha.** Podczas nagrywania Voice Momentu jego
> poświata oddycha razem z Twoim głosem.
>
> **Prawdziwe logo.** Na ekranie startowym i przy logowaniu widać logo YO Voice
> takie, jakie jest, z delikatną poświatą.
>
> **Wygodniej z klawiaturą i dużym tekstem.** Fokus klawiatury widać na każdym
> głównym przycisku, listy nie skaczą przy przechodzeniu Tabem, a więcej
> ekranów mieści się przy największym tekście. Pasek postępu w Yeels jest
> lepiej widoczny.
>
> **Poprawki.** Kafelki mówiących w serwerze już nie drgają; „Dodaj” przy
> propozycji znajomego działa; ponowienie po błędzie profilu znowu działa;
> „Oznacz wszystkie jako przeczytane” w powiadomieniach jest czytelne.
