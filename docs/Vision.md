# Vision

> **Speak. Connect. Be you.**

YO Voice is a voice-first social platform: live voice rooms, communities,
friends, and creator tools, built around real-time conversation rather than
text feeds. It's not trying to be a Discord clone or a Clubhouse clone — the
combination it's aiming for is closer to **Discord's community structure +
Clubhouse's live-voice format + TikTok's short-form creator loop
(Voice Moments)**, wrapped in a design bar closer to Apple, Linear, Discord,
Notion, or Spotify than a typical chat app.

## Who it's for

- People who want to talk, not just type — live voice rooms as the primary
  interaction, not a bolt-on feature.
- Communities that want structure: Clubs with channels, roles, and
  member management, not just a flat chat.
- Creators who want a real toolkit around hosting and audience growth, not
  just a personal profile page.
- Everyone, casually — friends, DMs, and a social graph (followers/following,
  friends) that works whether or not you ever host anything.

## What "done" looks like for a feature

A feature is not done when it compiles. It's done when:

1. It uses real backend data — Firebase Auth, Firestore, Storage, Cloud
   Functions, or LiveKit — not fabricated numbers or placeholder content.
2. It has real loading, empty, and error states — never a blank screen.
3. Anything genuinely not built yet is visible and labeled **"Coming soon"**
   rather than hidden or faked. Honesty about what's missing beats a
   convincing-looking fake.
4. It matches the app's existing dark, glassy, purple-accented Material 3
   visual language — see `Architecture.md` for the concrete palette/theme
   files, though most existing screens still use consistent inline hex
   values rather than the shared theme (a known, tracked gap — see
   `Roadmap.md`).

## Product pillars (what's actually built, not aspirational)

Voice Rooms, Clubs, Friends & Social, Messages, Voice Moments,
Achievements/Awards, Creator Studio, Settings, and Notifications — see
[Features.md](Features.md) for what each one actually does today, what's
real vs. "Coming soon," and which files/Cloud Functions back it.

## What YO Voice is explicitly not (yet)

Not a general text-first chat app, not app-store-distributed today (see
`Roadmap.md` for distribution status), not monetized. These aren't
long-term "never" — they're just not where the product is right now, and
this file should be updated the day that changes.
