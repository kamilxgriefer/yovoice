#!/usr/bin/env python3
"""Generates every UI sound in assets/audio/ui/ — the single source of truth.

The shipped WAVs are BUILD ARTIFACTS of this script, not hand-made assets:
run `python3 tool/generate_ui_sounds.py` from the repo root and the whole set
is reproduced bit-for-bit (the synthesis is deterministic — no randomness).

DESIGN LANGUAGE, so future sounds stay in the same family:

* One instrument: a soft glass-bell — sine fundamental, a 2nd partial at
  -15 dB decaying 1.7x faster, a 3rd at -24 dB decaying 2.5x faster, and the
  fundamental doubled at ±2.5 cents for a gentle chorus warmth. No square or
  saw content anywhere. The measurable claim behind "softer": the fraction
  of energy above 2 kHz dropped in every file versus the previous set —
  notification 25.9% -> 8.2%, participant_joined 17.7% -> 7.2%, room_joined
  7.2% -> 4.0% (one-pole highpass split; crest factor is NOT the metric
  here, because a decaying bell's quiet tail inflates it regardless of
  timbre).
* One key: A-major pentatonic around A4. Every file is made of E4 / A4 /
  C#5 / E5, so any two sounds heard together are consonant.
* One grammar: things BEGINNING rise (created, joined, unmuted), things
  ENDING fall (left, muted), and the two directions use the same intervals
  mirrored — the ear learns the pair, not eight arbitrary jingles.
* One envelope: 8 ms raised-cosine attack (the old set swelled for 77-164 ms,
  which made fast events feel laggy), exponential decay sized to the note,
  and a final fade that lands the last sample on exactly zero — no clicks.
* One level: every file peak-normalized to -6 dBFS. Loudness BALANCE between
  sounds stays where it always lived, in each UiSound's `volume` field.

Durations and filenames match lib/core/audio/ui_sound.dart exactly; nothing
on the Dart side changes when the set is regenerated.
"""

import math
import struct
import wave
from pathlib import Path

RATE = 44100
PEAK = 0.5  # -6 dBFS

E4, A4, CS5, E5 = 329.63, 440.0, 554.37, 659.26


def bell(freq: float, start: float, dur: float, total: float, *,
         level: float = 1.0, tau: float = None, shimmer: bool = False):
    """One glass-bell note as a list of (sample_index, value) contributions."""
    tau = tau if tau is not None else dur / 3.2
    n0 = int(start * RATE)
    n1 = min(int((start + dur) * RATE), int(total * RATE))
    attack = int(0.008 * RATE)
    cents = 2.5 / 1200.0
    f_lo, f_hi = freq * 2 ** -cents, freq * 2 ** cents
    out = []
    for i in range(n0, n1):
        t = (i - n0) / RATE
        env = (0.5 - 0.5 * math.cos(math.pi * (i - n0) / attack)) \
            if (i - n0) < attack else math.exp(-(t - attack / RATE) / tau)
        s = 0.5 * (math.sin(2 * math.pi * f_lo * t)
                   + math.sin(2 * math.pi * f_hi * t))
        s += 10 ** (-15 / 20) * math.sin(2 * math.pi * 2 * freq * t) \
            * math.exp(-t / (tau / 1.7))
        s += 10 ** (-24 / 20) * math.sin(2 * math.pi * 3 * freq * t) \
            * math.exp(-t / (tau / 2.5))
        if shimmer:
            s += 10 ** (-20 / 20) * math.sin(2 * math.pi * 4 * freq * t) \
                * math.exp(-t / (tau / 3.0))
        out.append((i, s * env * level))
    return out


def render(path: Path, total: float, notes):
    buf = [0.0] * int(total * RATE)
    for note in notes:
        for i, v in note:
            buf[i] += v
    peak = max(abs(v) for v in buf) or 1.0
    scale = PEAK / peak
    fade = int(0.010 * RATE)
    for i in range(fade):
        buf[-1 - i] *= i / fade  # last sample is exactly 0 — no click
    frames = struct.pack(
        f'<{len(buf)}h',
        *(max(-32767, min(32767, int(v * scale * 32767))) for v in buf),
    )
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)


def main():
    out = Path(__file__).resolve().parent.parent / 'assets' / 'audio' / 'ui'
    out.mkdir(parents=True, exist_ok=True)

    # A three-note bloom for the one genuinely celebratory moment.
    render(out / 'room_created.wav', 0.62, [
        bell(A4, 0.00, 0.62, 0.62, level=0.9),
        bell(CS5, 0.10, 0.52, 0.62, level=0.85),
        bell(E5, 0.20, 0.42, 0.62, shimmer=True),
    ])
    # Rising pair in, mirrored pair out.
    render(out / 'room_joined.wav', 0.46, [
        bell(E4, 0.00, 0.30, 0.46, level=0.8),
        bell(A4, 0.10, 0.36, 0.46),
    ])
    render(out / 'room_left.wav', 0.38, [
        bell(A4, 0.00, 0.26, 0.38, level=0.8),
        bell(E4, 0.09, 0.29, 0.38),
    ])
    # Single soft pings for other people — present, never demanding.
    render(out / 'participant_joined.wav', 0.27, [
        bell(CS5, 0.00, 0.27, 0.27),
    ])
    render(out / 'participant_left.wav', 0.27, [
        bell(A4, 0.00, 0.27, 0.27, tau=0.06),  # duller: shorter ring
    ])
    # The mic pair: the fastest gesture gets the shortest mirrored blips.
    render(out / 'microphone_unmuted.wav', 0.20, [
        bell(A4, 0.00, 0.11, 0.20, level=0.8),
        bell(CS5, 0.06, 0.14, 0.20),
    ])
    render(out / 'microphone_muted.wav', 0.20, [
        bell(CS5, 0.00, 0.11, 0.20, level=0.8),
        bell(A4, 0.06, 0.14, 0.20, tau=0.045),
    ])
    # The classic two-note chime, gentle: minor third down, long ring.
    render(out / 'notification.wav', 0.50, [
        bell(E5, 0.00, 0.30, 0.50, level=0.9),
        bell(CS5, 0.14, 0.36, 0.50),
    ])
    print('wrote 8 files to', out)


if __name__ == '__main__':
    main()
