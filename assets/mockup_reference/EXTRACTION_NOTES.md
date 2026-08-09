# Mockup asset extraction (Milestone 2)

Classification-first, per the implementation mandate: nearly every
product element in the references is CODE (cards, gradients, badges,
rings, navigation, Voice Core — all implemented as real components).
Raster extraction was limited to unique generated artwork.

## Extracted (Pillow, exact bounds, inspected via contact sheet)

- `assets/clubs/cyber_lounge_art_reference.png` (87×89) — clean tile.
- `assets/clubs/gaming_nl_art_reference.png` (87×89) — clean tile.
- `assets/premium/premium_hero_reference_partial.png` (214×224) —
  portrait + violet ring + crown. `_partial`: the source overlaps the
  "Club Owner" / "Premium Identity" pills onto the ring glow, so any
  full-element crop includes pill fragments; hidden pixels were NOT
  reconstructed per the extraction rules.

## Usage constraints

These are DEMO/REFERENCE fixtures (generated people/artwork). They may
appear in website marketing previews or dev fixtures only — never as
production user avatars, club art, or profile data.

## Deliberately NOT extracted

Small people portraits (Maya/Alex/Noah/Zoe/Liam etc.): tiny at source
resolution, and production surfaces use real user avatars via the
canonical UserAvatar — no product use for the pixels. Logos/icons: the
repository's own SVG/PNG originals are authoritative.
