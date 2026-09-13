# Vision

> **Speak. Connect. Be you.**

YO Voice is a voice-first social platform built around persistent Servers,
friends, YO Moments and real-time conversation. A Server gives a group one
compact home for voice/video conversations, text channels and the tools that
fit that group. The product borrows familiar interaction patterns without
copying another app's layout, assets or visual identity; its own dark cosmic
Material 3 language remains the design source of truth.

## Who it's for

- Friends who want a small shared place for voice, text, plans and events.
- Communities that need channels, roles, moderation and a video LIVE stage.
- Podcasters who need a live studio, listener questions, episode recording,
  an archive and a programme in one place.
- Families who want a private invite-only space with a calendar, shared list,
  check-ins and photo/voice memories.
- Companies that need team channels, restricted HR/management areas,
  meetings, screen sharing, a shared whiteboard and files.
- Creators who want a real toolkit around hosting and audience growth, not
  just a personal profile page. Followers/following are exposed only for a
  verified-age Creator with active Premium who explicitly enables the feature.
- Everyone else, casually, through friends, direct messages and shared
  Servers without a public follower identity.

## What "done" looks like for a feature

A feature is not done when it compiles. It's done when:

1. It uses real backend data — Firebase Auth, Firestore, Storage, Cloud
   Functions, or LiveKit — not fabricated numbers or placeholder content.
2. It has real loading, empty, and error states — never a blank screen.
3. Anything genuinely not built yet is visible and labeled **"Coming soon"**
   rather than hidden or faked. Honesty about what's missing beats a
   convincing-looking fake — see
   [ADR-012](Decisions.md#adr-012-coming-soon-instead-of-fabricated-data-or-dead-buttons)
   for why this is treated as a hard rule, not a style preference.
4. It matches the app's existing dark, glassy, purple-accented Material 3
   visual language — see [UI.md](UI.md) for the concrete palette/theme
   files, though most existing screens still use consistent inline hex
   values rather than the shared theme (a known, tracked migration — see
   [Roadmap.md](Roadmap.md)).

## Product pillars (what's actually built, not aspirational)

Servers (Friends, Community, Podcast, Family and Company), Friends, Messages,
YO Moments (Voice + Reels), Achievements/Awards, Creator Studio, Settings and
Notifications — see [Features.md](Features.md) for what each one actually does
today, what's real vs. "Coming soon," and which files/Cloud Functions back it.

## What YO Voice is explicitly not (yet)

Not a general text-first chat app, not app-store-distributed today (see
[Roadmap.md](Roadmap.md#13-app-store-distribution) for distribution
status), not monetized (see
[Roadmap.md](Roadmap.md#4-monetization)). These aren't long-term "never"
— they're just not where the product is right now, and this file should
be updated the day that changes.
