#!/usr/bin/env python3
"""Build the complete YO Voice product-sound pack.

The checked-in WAV files are deterministic build artifacts of this script.
Run it from the repository root:

    python3 tool/generate_ui_sounds.py

Use ``--check`` in CI or before a release to prove that every checked-in copy
matches the generator without rewriting anything.

DESIGN LANGUAGE (v4, "Soft Bells")

* Additive bells: a fundamental plus three softer, faster-dying partials,
  a 4-12 ms attack and an exponential decay, low-passed at 6.5 kHz so
  nothing is glassy or sharp.
* Meaning lives in a tiny vocabulary of notes from one warm pentatonic set:
  rising = something opened or arrived, falling = something closed or left,
  a single bubble = a person, a short velvet tick = the microphone, a calm
  two-note chime = a notification.
* Loudness is a deliberate hierarchy, mastered into each asset: microphone
  ticks whisper (about -27 dBFS RMS), room cues speak (-22 to -25), the
  notification is the only cue meant to be noticed across a room (-21).
* A short plate-like tail and a 0.9 ms decorrelated blend give headphones a
  little depth; the side signal stays at least 14 dB below the mid channel,
  so mono playback loses nothing.
* Internal synthesis is 48 kHz float. Delivery is stereo PCM16 at 48 kHz,
  with deterministic TPDF dither, a click-free fade and exact terminal zeroes.
* Every cue is under 0.8 s: UiSoundService serialises a channel until the
  cue has finished, and its completion timeout is 2 s.

The sound is intentionally restrained. Normal navigation, loading, likes and
sheet transitions have no cue; only the eight semantic events below do.
"""

from __future__ import annotations

import argparse
import io
import math
import struct
import sys
import wave
from dataclasses import dataclass
from pathlib import Path


RATE = 48_000
SAMPLE_WIDTH = 2
CHANNELS = 2
MAX_BYTES = 160 * 1024
TERMINAL_ZERO_FRAMES = 64
PAD_FRAMES = 160
LOWPASS_HZ = 6500.0
WIDTH_DELAY_FRAMES = 43  # 0.9 ms
WIDTH_BLEND = 0.12
ASSET_PACK_VERSION = "v4"


def _note(semitones_from_c4: float) -> float:
    return 440.0 * 2 ** ((semitones_from_c4 - 9) / 12)


C4, E4, G4 = _note(0), _note(4), _note(7)
C5, D5, E5, G5, A5, C6 = _note(12), _note(14), _note(16), _note(19), _note(21), _note(24)

BELL = ((1.0, 1.0), (2.0, 0.35), (3.0, 0.12), (4.01, 0.05))
BUBBLE = ((1.0, 1.0), (2.0, 0.25), (3.0, 0.06))
BUBBLE_LOW = ((1.0, 1.0), (2.0, 0.22), (3.0, 0.05))
TICK = ((1.0, 1.0), (2.0, 0.3), (3.0, 0.1))
TICK_TAIL = ((1.0, 1.0), (2.0, 0.2))
CHIME = ((1.0, 1.0), (2.0, 0.3), (3.0, 0.1), (5.02, 0.04))


@dataclass(frozen=True)
class Note:
    hz: float
    duration: float
    level: float
    attack: float
    decay: float
    delay: float
    partials: tuple[tuple[float, float], ...]


@dataclass(frozen=True)
class CueSpec:
    name: str
    loudness_db: float
    peak_ceiling_db: float
    notes: tuple[Note, ...]
    tail_ms: float
    tail_feedback: float
    tail_wet: float
    seed: int


def _bell(hz, duration, level, *, attack=0.012, decay=0.35, delay=0.0, partials=BELL):
    return Note(hz, duration, level, attack, decay, delay, partials)


CUES = (
    # rising triad bloom: three staggered bells — a room came into being
    CueSpec("room_created", -22.0, -3.0, (
        _bell(C5, 0.55, 0.9, decay=0.22),
        _bell(E5, 0.55, 0.7, decay=0.21, delay=0.07),
        _bell(G5, 0.60, 0.6, decay=0.24, delay=0.14),
    ), 90.0, 0.32, 0.22, 0x41C1),
    # two ascending notes — welcome in
    CueSpec("room_joined", -23.0, -3.0, (
        _bell(E5, 0.42, 0.8, decay=0.17),
        _bell(A5, 0.46, 0.7, decay=0.21, delay=0.08),
    ), 80.0, 0.32, 0.22, 0x41C2),
    # two descending notes — gentle close
    CueSpec("room_left", -24.0, -3.0, (
        _bell(A5, 0.38, 0.7, decay=0.15),
        _bell(E5, 0.44, 0.65, decay=0.20, delay=0.08),
    ), 80.0, 0.32, 0.16, 0x41C3),
    # single bright soft bubble — someone arrived
    CueSpec("participant_joined", -27.0, -3.0, (
        _bell(C6, 0.30, 0.75, attack=0.008, decay=0.12, partials=BUBBLE),
    ), 60.0, 0.32, 0.14, 0x41C4),
    # single lower, softer bubble — someone left
    CueSpec("participant_left", -28.0, -3.0, (
        _bell(G5, 0.30, 0.65, attack=0.010, decay=0.12, partials=BUBBLE_LOW),
    ), 60.0, 0.32, 0.12, 0x41C5),
    # short low velvet tick, falling — microphone closed
    CueSpec("microphone_muted", -26.0, -3.0, (
        _bell(E4, 0.16, 0.9, attack=0.004, decay=0.06, partials=TICK),
        _bell(C4, 0.17, 0.5, attack=0.004, decay=0.07, delay=0.025, partials=TICK_TAIL),
    ), 0.0, 0.0, 0.0, 0x41C6),
    # short brighter tick, rising — microphone open
    CueSpec("microphone_unmuted", -26.0, -3.0, (
        _bell(G4, 0.16, 0.8, attack=0.004, decay=0.06, partials=TICK),
        _bell(E5, 0.17, 0.55, attack=0.004, decay=0.08, delay=0.025, partials=TICK_TAIL),
    ), 0.0, 0.0, 0.0, 0x41C7),
    # calm two-note chime — a notification
    CueSpec("notification", -21.0, -3.0, (
        _bell(A5, 0.50, 0.8, decay=0.20, partials=CHIME),
        _bell(D5, 0.55, 0.6, decay=0.24, delay=0.10),
    ), 90.0, 0.32, 0.20, 0x41C8),
)


class DeterministicNoise:
    """Tiny xorshift generator so dither never depends on the platform RNG."""

    def __init__(self, seed: int) -> None:
        self._state = (seed & 0xFFFFFFFF) or 0x9E3779B9

    def sample(self) -> float:
        x = self._state
        x ^= (x << 13) & 0xFFFFFFFF
        x ^= x >> 17
        x ^= (x << 5) & 0xFFFFFFFF
        self._state = x & 0xFFFFFFFF
        return (self._state / 0x7FFFFFFF) - 1.0


def _tone(note: Note) -> list[float]:
    frames = int(RATE * note.duration)
    out = [0.0] * frames
    for index, (ratio, weight) in enumerate(note.partials):
        hz = note.hz * ratio
        partial_decay = note.decay / (1 + 0.6 * index)
        for i in range(frames):
            t = i / RATE - note.delay
            if t < 0:
                continue
            envelope = min(1.0, t / note.attack) * math.exp(-t / partial_decay)
            out[i] += weight * note.level * envelope * math.sin(2 * math.pi * hz * t)
    return out


def _mix(layers: list[list[float]]) -> list[float]:
    frames = max(len(layer) for layer in layers)
    out = [0.0] * frames
    for layer in layers:
        for i, value in enumerate(layer):
            out[i] += value
    return out


def _tail(signal: list[float], ms: float, feedback: float, wet: float) -> list[float]:
    if ms <= 0.0:
        return list(signal)
    delay = int(RATE * ms / 1000)
    frames = len(signal) + delay * 2
    dry = list(signal) + [0.0] * (frames - len(signal))
    buffer = [0.0] * frames
    for i in range(frames):
        buffer[i] = dry[i] + (buffer[i - delay] * feedback if i >= delay else 0.0)
    return [dry[i] + wet * (buffer[i - delay] if i >= delay else 0.0) for i in range(frames)]


def _lowpass(samples: list[float], cutoff_hz: float) -> list[float]:
    rc = 1 / (2 * math.pi * cutoff_hz)
    dt = 1 / RATE
    alpha = dt / (rc + dt)
    y = 0.0
    out = []
    for x in samples:
        y += alpha * (x - y)
        out.append(y)
    return out


def _fade_out(samples: list[float], ms: float = 40.0) -> list[float]:
    out = list(samples)
    frames = int(RATE * ms / 1000)
    for i in range(frames):
        out[-1 - i] *= i / frames
    return out


def _widen(mono: list[float]) -> tuple[list[float], list[float]]:
    """A 0.9 ms decorrelated blend on the right channel: depth on headphones,
    a side signal far below the mid, and nothing lost in mono."""
    left = list(mono)
    right = [
        (1.0 - WIDTH_BLEND) * value
        + WIDTH_BLEND * (mono[i - WIDTH_DELAY_FRAMES] if i >= WIDTH_DELAY_FRAMES else 0.0)
        for i, value in enumerate(mono)
    ]
    return left, right


def _synthesise(spec: CueSpec) -> tuple[list[float], list[float]]:
    mono = _mix([_tone(note) for note in spec.notes])
    mono = _tail(mono, spec.tail_ms, spec.tail_feedback, spec.tail_wet)
    mono = _fade_out(_lowpass(mono, LOWPASS_HZ))
    mono = mono + [0.0] * PAD_FRAMES
    left, right = _widen(mono)
    # Loudness is normalised on the delivered stereo pair, padding included,
    # so the mastered RMS is exactly what the asset carries.
    rms = math.sqrt(sum(l * l + r * r for l, r in zip(left, right)) / (2.0 * len(left)))
    gain = 10 ** (spec.loudness_db / 20) / max(rms, 1e-12)
    left = [value * gain for value in left]
    right = [value * gain for value in right]
    return left, right


def _correlation(left: list[float], right: list[float]) -> float:
    left_mean = sum(left) / len(left)
    right_mean = sum(right) / len(right)
    numerator = sum(
        (l - left_mean) * (r - right_mean) for l, r in zip(left, right)
    )
    left_power = sum((value - left_mean) ** 2 for value in left)
    right_power = sum((value - right_mean) ** 2 for value in right)
    return numerator / math.sqrt(left_power * right_power)


def _render(spec: CueSpec) -> bytes:
    left, right = _synthesise(spec)
    peak = max(max(abs(value) for value in left), max(abs(value) for value in right))
    rms = math.sqrt(
        sum(value * value for value in left + right) / (len(left) + len(right))
    )
    peak_db = 20.0 * math.log10(max(peak, 1e-12))
    rms_db = 20.0 * math.log10(max(rms, 1e-12))
    correlation = _correlation(left, right)
    mono = [(l + r) * 0.5 for l, r in zip(left, right)]
    side = [(l - r) * 0.5 for l, r in zip(left, right)]
    mono_rms = math.sqrt(sum(value * value for value in mono) / len(mono))
    side_rms = math.sqrt(sum(value * value for value in side) / len(side))
    average_channel_rms = math.sqrt(
        sum(l * l + r * r for l, r in zip(left, right)) / (2.0 * len(left))
    )
    mono_loss_db = 20.0 * math.log10(mono_rms / average_channel_rms)
    side_below_mid_db = 20.0 * math.log10(max(side_rms, 1e-12) / mono_rms)
    dc = max(abs(sum(left) / len(left)), abs(sum(right) / len(right)))

    assert abs(rms_db - spec.loudness_db) <= 0.15, (spec.name, rms_db)
    assert peak_db <= spec.peak_ceiling_db + 0.05, (spec.name, peak_db)
    assert correlation >= 0.80, (spec.name, correlation)
    assert mono_loss_db >= -1.0, (spec.name, mono_loss_db)
    assert side_below_mid_db <= -14.0, (spec.name, side_below_mid_db)
    assert dc <= 10.0 ** (-60.0 / 20.0), (spec.name, dc)
    assert left[-TERMINAL_ZERO_FRAMES:] == [0.0] * TERMINAL_ZERO_FRAMES
    assert right[-TERMINAL_ZERO_FRAMES:] == [0.0] * TERMINAL_ZERO_FRAMES

    # Deterministic triangular dither avoids correlated quantisation grit.
    # The explicit zero pad is kept untouched.
    dither = DeterministicNoise(spec.seed ^ 0xDEADBEEF)
    frames = bytearray()
    zero_from = len(left) - TERMINAL_ZERO_FRAMES
    for index, (l_value, r_value) in enumerate(zip(left, right)):
        encoded = []
        for value in (l_value, r_value):
            if index >= zero_from:
                quantised = 0
            else:
                triangular = (dither.sample() + dither.sample()) * 0.5
                quantised = round(value * 32767.0 + triangular * 0.5)
                quantised = max(-32768, min(32767, quantised))
            encoded.append(quantised)
        frames += struct.pack("<hh", *encoded)

    output = io.BytesIO()
    with wave.open(output, "wb") as wav:
        wav.setnchannels(CHANNELS)
        wav.setsampwidth(SAMPLE_WIDTH)
        wav.setframerate(RATE)
        wav.writeframes(bytes(frames))
    data = output.getvalue()
    assert len(data) < MAX_BYTES, (spec.name, len(data))
    return data


def _targets(root: Path, rendered: dict[str, bytes]) -> dict[Path, bytes]:
    asset_directory = root / "assets" / "audio" / "ui" / ASSET_PACK_VERSION
    targets = {
        asset_directory / f"{name}.wav": data for name, data in rendered.items()
    }
    notification = rendered["notification"]
    targets[root / "android/app/src/main/res/raw/yovoice_notification.wav"] = notification
    targets[root / "ios/Runner/yovoice_notification.wav"] = notification
    return targets


def _unexpected_flutter_assets(
    root: Path,
    targets: dict[Path, bytes],
) -> list[Path]:
    """Return every UI WAV that is not one of the eight versioned masters."""

    asset_root = root / "assets" / "audio" / "ui"
    expected_assets = {
        path for path in targets if path.parent == asset_root / ASSET_PACK_VERSION
    }
    return sorted(
        path for path in asset_root.rglob("*.wav") if path not in expected_assets
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail when a checked-in WAV differs; do not write files",
    )
    args = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    rendered = {spec.name: _render(spec) for spec in CUES}
    targets = _targets(root, rendered)
    if args.check:
        mismatches = [
            path.relative_to(root)
            for path, expected in targets.items()
            if not path.exists() or path.read_bytes() != expected
        ]
        mismatches.extend(
            path.relative_to(root)
            for path in _unexpected_flutter_assets(root, targets)
        )
        if mismatches:
            print("generated sound assets are stale:", file=sys.stderr)
            for mismatch in mismatches:
                print(f"  {mismatch}", file=sys.stderr)
            return 1
        print("sound assets match Soft Bells v4 generator")
        return 0

    retired_assets = _unexpected_flutter_assets(root, targets)
    for path in retired_assets:
        path.unlink()
    for path, data in targets.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    print(
        "wrote 8 versioned Soft Bells cues and 2 bit-identical native copies"
        f"; retired {len(retired_assets)} stale UI WAV(s)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
