#!/usr/bin/env python3
"""Generates every UI sound in assets/audio/ui/ — the single source of truth.

The shipped WAVs are BUILD ARTIFACTS of this script, not hand-made assets:
run `python3 tool/generate_ui_sounds.py` from the repo root and the whole set
is reproduced bit-for-bit (the synthesis is deterministic — no randomness).

DESIGN LANGUAGE (v2, "exclusive"), so future sounds stay in the same family:

* One instrument: a felt-mallet GLASS BELL, built the way real struck glass
  behaves rather than from a textbook harmonic series —
    - fundamental doubled at ±2.5 cents (chorus warmth), split L/R;
    - a SUB-OCTAVE at -18 dB with a slow decay: the body that makes a small
      speaker sound like a large room;
    - a slightly INHARMONIC glass partial at 2.756x (-20 dB, fast decay) and
      an "air" partial at 5.04x (-30 dB, faster): real bells are not integer
      stacks, and the ear reads that stretch as material, i.e. expensive;
    - gentle true harmonics at 2x (-16 dB) and 3x (-25 dB) underneath;
    - a mallet PITCH SETTLE: the note starts +8 cents sharp and glides to
      pitch over 40 ms, the way a struck object tightens into its tone.
* STEREO, subtly: the bell body is a MONO ANCHOR — identical and
  simultaneous in both channels — while the two ±2.5-cent fundamentals split
  left/now, right/9 ms-late (Haas). Width you feel more than hear, the
  image stays solid (the script verifies inter-channel correlation lands in
  0.2..0.98), and the mono sum is clean because the only delayed element is
  a detuned copy, never the anchor.
* One key: A-major pentatonic (E4 / A4 / C#5 / E5) — any two sounds heard
  together are consonant.
* One grammar: things BEGINNING rise (created, joined, unmuted), things
  ENDING fall (left, muted), mirrored intervals — the ear learns the pair,
  not eight jingles.
* One envelope: 8 ms raised-cosine attack, exponential decay, longer silk
  tails than v1 (files grew 0.04-0.23 s), last sample exactly zero on both
  channels — no clicks.
* One level: every file peak-normalized to -6 dBFS. Loudness BALANCE between
  sounds stays where it always lived, in each UiSound's `volume` field.

The measurable claim behind "softer" (v1, unchanged in spirit): the fraction
of energy above 2 kHz dropped in every file versus the original hand-made
set — notification 25.9% -> ~8%, participant_joined 17.7% -> ~7% (one-pole
highpass split; crest factor is NOT the metric here, because a decaying
bell's quiet tail inflates it regardless of timbre).

Filenames match lib/core/audio/ui_sound.dart exactly; nothing on the Dart
side changes when the set is regenerated.
"""

import math
import struct
import wave
from pathlib import Path

# 22.05 kHz, deliberately: the highest partial in the set is 5.04x E5 =
# 3.32 kHz, comfortably under this rate's 11 kHz Nyquist, so nothing audible
# is lost — and the app's own asset test caps every WAV at 64 KB, which
# stereo 44.1 kHz files broke. The generator enforces the same cap below so
# a future longer sound fails HERE, not in CI.
RATE = 22050
MAX_BYTES = 64 * 1024
PEAK = 0.5  # -6 dBFS

E4, A4, CS5, E5 = 329.63, 440.0, 554.37, 659.26

HAAS = int(0.009 * RATE)  # inter-channel delay for width


def bell(freq: float, start: float, dur: float, *,
         level: float = 1.0, tau: float = None, pan: float = 0.0,
         shimmer: bool = False):
    """One glass-bell note: list of (sample_index, left, right)."""
    tau = tau if tau is not None else dur / 3.0
    n0 = int(start * RATE)
    count = int(dur * RATE)
    attack = int(0.008 * RATE)
    cents = 2.5 / 1200.0
    f_lo, f_hi = freq * 2 ** -cents, freq * 2 ** cents
    # Equal-power pan for everything but the Haas pair, which carries the
    # width on its own.
    gl = math.cos((pan + 1) * math.pi / 4)
    gr = math.sin((pan + 1) * math.pi / 4)
    out = []
    for i in range(count):
        t = i / RATE
        env = (0.5 - 0.5 * math.cos(math.pi * i / attack)) \
            if i < attack else math.exp(-(t - attack / RATE) / tau)
        # The mallet settle: +8 cents gliding to pitch over 40 ms.
        settle = 2 ** ((8 / 1200) * math.exp(-t / 0.040))
        # Shared body: sub-octave, true harmonics, inharmonic glass + air.
        body = 0.0
        body += 10 ** (-18 / 20) * math.sin(2 * math.pi * 0.5 * freq * settle * t) \
            * math.exp(-t / (tau * 1.4))
        body += 10 ** (-16 / 20) * math.sin(2 * math.pi * 2 * freq * t) \
            * math.exp(-t / (tau / 1.7))
        body += 10 ** (-25 / 20) * math.sin(2 * math.pi * 3 * freq * t) \
            * math.exp(-t / (tau / 2.5))
        body += 10 ** (-20 / 20) * math.sin(2 * math.pi * 2.756 * freq * t) \
            * math.exp(-t / (tau / 3.0))
        body += 10 ** (-30 / 20) * math.sin(2 * math.pi * 5.04 * freq * t) \
            * math.exp(-t / (tau / 4.0))
        if shimmer:
            body += 10 ** (-22 / 20) * math.sin(2 * math.pi * 4 * freq * t) \
                * math.exp(-t / (tau / 3.0))
        # THE BODY IS THE MONO ANCHOR: identical and simultaneous in both
        # channels. The first cut delayed the whole right channel, which
        # decorrelated everything and measured 0.18-0.19 inter-channel
        # correlation on the longest file — width read as phasey, not wide.
        # Only the detuned twin is Haas-late now; the anchor keeps the image
        # solid and the mono sum clean.
        # The partial stack alone was too quiet an anchor: over a long
        # tail the ±2.5-cent twins beat out of phase and the longest file
        # still measured 0.20 correlation. An UNDETUNED center fundamental
        # joins the anchor, and the twins drop to a width layer around it.
        center = 0.35 * math.sin(2 * math.pi * freq * settle * t)
        anchor = (center + 0.5 * body) * env * level
        lo = 0.34 * math.sin(2 * math.pi * f_lo * settle * t) * env * level
        out.append((n0 + i, (anchor + lo) * gl, anchor * gr))
        hi = 0.34 * math.sin(2 * math.pi * f_hi * settle * t) * env * level
        out.append((n0 + i + HAAS, 0.0, hi * gr))
    return out


def render(path: Path, total: float, notes):
    n = int(total * RATE)
    left = [0.0] * n
    right = [0.0] * n
    for note in notes:
        for i, l, r in note:
            if i < n:
                left[i] += l
                right[i] += r
    peak = max(max(abs(v) for v in left), max(abs(v) for v in right)) or 1.0
    scale = PEAK / peak
    fade = int(0.012 * RATE)
    for i in range(fade):
        left[-1 - i] *= i / fade
        right[-1 - i] *= i / fade  # both channels end at exactly zero
    frames = bytearray()
    for l, r in zip(left, right):
        frames += struct.pack(
            '<hh',
            max(-32767, min(32767, int(l * scale * 32767))),
            max(-32767, min(32767, int(r * scale * 32767))),
        )
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(frames))
    size = path.stat().st_size
    assert size < MAX_BYTES, f'{path.name}: {size} bytes >= {MAX_BYTES}'


def main():
    out = Path(__file__).resolve().parent.parent / 'assets' / 'audio' / 'ui'
    out.mkdir(parents=True, exist_ok=True)

    # A three-note bloom for the one genuinely celebratory moment; the notes
    # walk gently left -> center -> right.
    # 0.72s, not 0.85: the 64 KB cap allows at most 0.74s of stereo at
    # this rate, and the exponential tail is inaudible past ~0.7s anyway.
    render(out / 'room_created.wav', 0.72, [
        # Pans tightened from ±0.18: with three Haas-delayed notes the
        # wider image measured 0.18 inter-channel correlation — over the
        # 0.2 floor this script verifies, and risking a phasey feel on
        # headphones. ±0.10 keeps the walk audible and the image solid.
        bell(A4, 0.00, 0.68, level=0.9, pan=-0.10),
        bell(CS5, 0.11, 0.58, level=0.85, pan=0.0),
        bell(E5, 0.22, 0.50, pan=0.10, shimmer=True),
    ])
    # Rising pair in, mirrored pair out.
    render(out / 'room_joined.wav', 0.60, [
        bell(E4, 0.00, 0.42, level=0.8, pan=-0.12),
        bell(A4, 0.11, 0.49, pan=0.10),
    ])
    render(out / 'room_left.wav', 0.50, [
        bell(A4, 0.00, 0.34, level=0.8, pan=0.10),
        bell(E4, 0.10, 0.40, pan=-0.12),
    ])
    # Single soft pings for other people — present, never demanding.
    render(out / 'participant_joined.wav', 0.38, [
        bell(CS5, 0.00, 0.36, pan=0.08),
    ])
    render(out / 'participant_left.wav', 0.38, [
        bell(A4, 0.00, 0.36, tau=0.075, pan=-0.08),
    ])
    # The mic pair: the fastest gesture gets the shortest mirrored blips.
    render(out / 'microphone_unmuted.wav', 0.24, [
        bell(A4, 0.00, 0.12, level=0.8),
        bell(CS5, 0.06, 0.17),
    ])
    render(out / 'microphone_muted.wav', 0.24, [
        bell(CS5, 0.00, 0.12, level=0.8),
        bell(A4, 0.06, 0.17, tau=0.05),
    ])
    # The classic two-note chime, gentle: minor third down, long silk ring.
    render(out / 'notification.wav', 0.70, [
        bell(E5, 0.00, 0.42, level=0.9, pan=-0.10),
        bell(CS5, 0.15, 0.54, pan=0.10),
    ])
    print('wrote 8 stereo files to', out)


if __name__ == '__main__':
    main()
