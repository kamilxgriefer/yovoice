#!/usr/bin/env python3
"""Build the complete YO Voice product-sound pack.

The checked-in WAV files are deterministic build artifacts of this script.
Run it from the repository root:

    python3 tool/generate_ui_sounds.py

Use ``--check`` in CI or before a release to prove that every checked-in copy
matches the generator without rewriting anything.

DESIGN LANGUAGE (v5, "Prism Halo")

* Additive bells: a fundamental plus three softer, faster-dying partials,
  a 4-12 ms attack and an exponential decay, low-passed at 6.5 kHz so
  nothing is glassy or sharp.
* Meaning lives in one original B-minor/D-major pentatonic signature. Rising
  shapes open and connect; falling shapes close; paired low pulses decline or
  warn; the call loops repeat the same three-note identity with enough silence
  to stay calm during a long wait.
* Loudness is a deliberate hierarchy, mastered into each asset: microphone
  ticks whisper (about -27 dBFS RMS), room cues speak (-22 to -25), the
  notification is the only cue meant to be noticed across a room (-21).
* A short plate-like tail and a 0.9 ms decorrelated blend give headphones a
  little depth; the side signal stays at least 14 dB below the mid channel,
  so mono playback loses nothing.
* Internal synthesis is 48 kHz float. Delivery is stereo PCM16 at 48 kHz,
  with deterministic TPDF dither, a click-free fade and exact terminal zeroes.
* UI cues are under 1.1 s. Two dedicated call cadences are under 3.5 s and
  loop through CallToneService, which can stop them immediately on answer,
  decline, cancellation, backgrounding or disposal.

The sound is intentionally restrained. Normal navigation, loading, likes and
sheet transitions stay silent; only semantic communication events have cues.
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
MAX_UI_BYTES = 220 * 1024
MAX_CALL_BYTES = 800 * 1024
TERMINAL_ZERO_FRAMES = 64
PAD_FRAMES = 160
LOWPASS_HZ = 6500.0
WIDTH_DELAY_FRAMES = 43  # 0.9 ms
WIDTH_BLEND = 0.12
ASSET_PACK_VERSION = "v5"


def _note(semitones_from_c4: float) -> float:
    return 440.0 * 2 ** ((semitones_from_c4 - 9) / 12)


C4, D4, E4, FS4, A4, B4 = (
    _note(0), _note(2), _note(4), _note(6), _note(9), _note(11)
)
D5, E5, FS5, A5, B5, D6 = (
    _note(14), _note(16), _note(18), _note(21), _note(23), _note(26)
)

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
    max_bytes: int = MAX_UI_BYTES


def _bell(hz, duration, level, *, attack=0.012, decay=0.35, delay=0.0, partials=BELL):
    return Note(hz, duration, level, attack, decay, delay, partials)


CUES = (
    CueSpec("room_created", -22.5, -3.0, (
        _bell(D5, 0.58, 0.82, decay=0.22),
        _bell(FS5, 0.64, 0.70, decay=0.23, delay=0.07),
        _bell(B5, 0.72, 0.55, decay=0.26, delay=0.15),
    ), 92.0, 0.30, 0.20, 0x51A1),
    CueSpec("room_joined", -23.5, -3.0, (
        _bell(FS5, 0.48, 0.80, decay=0.18),
        _bell(B5, 0.56, 0.66, decay=0.22, delay=0.09),
    ), 84.0, 0.30, 0.18, 0x51A2),
    CueSpec("room_left", -24.5, -3.0, (
        _bell(B5, 0.46, 0.68, decay=0.17),
        _bell(FS5, 0.54, 0.62, decay=0.21, delay=0.09),
    ), 84.0, 0.30, 0.15, 0x51A3),
    CueSpec("participant_joined", -27.0, -3.0, (
        _bell(D6, 0.32, 0.72, attack=0.008, decay=0.12, partials=BUBBLE),
    ), 62.0, 0.30, 0.13, 0x51A4),
    CueSpec("participant_left", -28.0, -3.0, (
        _bell(A5, 0.32, 0.62, attack=0.010, decay=0.12, partials=BUBBLE_LOW),
    ), 62.0, 0.30, 0.11, 0x51A5),
    CueSpec("microphone_muted", -27.0, -3.0, (
        _bell(FS4, 0.17, 0.84, attack=0.004, decay=0.06, partials=TICK),
        _bell(D4, 0.18, 0.48, attack=0.004, decay=0.07, delay=0.026, partials=TICK_TAIL),
    ), 0.0, 0.0, 0.0, 0x51A6),
    CueSpec("microphone_unmuted", -27.0, -3.0, (
        _bell(A4, 0.17, 0.76, attack=0.004, decay=0.06, partials=TICK),
        _bell(FS5, 0.18, 0.50, attack=0.004, decay=0.08, delay=0.026, partials=TICK_TAIL),
    ), 0.0, 0.0, 0.0, 0x51A7),
    CueSpec("notification", -21.5, -3.0, (
        _bell(B5, 0.56, 0.78, decay=0.20, partials=CHIME),
        _bell(FS5, 0.64, 0.58, decay=0.25, delay=0.11),
    ), 96.0, 0.30, 0.20, 0x51A8),
    CueSpec("notification_social", -22.0, -3.0, (
        _bell(D5, 0.60, 0.72, decay=0.21),
        _bell(A5, 0.66, 0.62, decay=0.23, delay=0.08),
        _bell(B5, 0.70, 0.45, decay=0.24, delay=0.16),
    ), 92.0, 0.30, 0.18, 0x51A9),
    CueSpec("notification_achievement", -21.5, -3.0, (
        _bell(D5, 0.76, 0.68, decay=0.23),
        _bell(FS5, 0.80, 0.58, decay=0.24, delay=0.08),
        _bell(B5, 0.86, 0.50, decay=0.27, delay=0.17),
        _bell(D6, 0.90, 0.38, decay=0.28, delay=0.27),
    ), 98.0, 0.31, 0.22, 0x51AA),
    CueSpec("notification_alert", -21.0, -3.0, (
        _bell(FS5, 0.64, 0.78, decay=0.19),
        _bell(D5, 0.72, 0.62, decay=0.23, delay=0.14),
    ), 88.0, 0.29, 0.16, 0x51AB),
    CueSpec("call_connected", -21.5, -3.0, (
        _bell(D5, 0.68, 0.76, decay=0.21),
        _bell(FS5, 0.74, 0.65, decay=0.23, delay=0.07),
        _bell(B5, 0.82, 0.52, decay=0.27, delay=0.15),
    ), 96.0, 0.30, 0.22, 0x51AC),
    CueSpec("call_ended", -23.0, -3.0, (
        _bell(B5, 0.62, 0.68, decay=0.19),
        _bell(FS5, 0.70, 0.60, decay=0.23, delay=0.10),
        _bell(D5, 0.76, 0.48, decay=0.25, delay=0.20),
    ), 90.0, 0.30, 0.17, 0x51AD),
    CueSpec("call_declined", -22.5, -3.0, (
        _bell(D5, 0.78, 0.74, decay=0.17),
        _bell(B4, 0.84, 0.68, decay=0.20, delay=0.22),
    ), 74.0, 0.27, 0.12, 0x51AE),
    CueSpec("call_failed", -22.0, -3.0, (
        _bell(E5, 0.72, 0.74, decay=0.16),
        _bell(B4, 0.80, 0.68, decay=0.19, delay=0.16),
        _bell(D4, 0.88, 0.45, decay=0.22, delay=0.32),
    ), 72.0, 0.27, 0.10, 0x51AF),
    CueSpec("call_busy", -22.0, -3.0, (
        _bell(B4, 1.02, 0.78, attack=0.006, decay=0.12, partials=TICK),
        _bell(B4, 1.02, 0.72, attack=0.006, decay=0.12, delay=0.32, partials=TICK),
        _bell(B4, 1.02, 0.66, attack=0.006, decay=0.12, delay=0.64, partials=TICK),
    ), 54.0, 0.24, 0.08, 0x51B0),
    CueSpec("call_incoming_loop", -25.0, -3.0, (
        _bell(D5, 3.12, 0.78, decay=0.20),
        _bell(FS5, 3.12, 0.66, decay=0.22, delay=0.10),
        _bell(B5, 3.12, 0.54, decay=0.25, delay=0.22),
        _bell(D5, 3.12, 0.72, decay=0.20, delay=1.34),
        _bell(FS5, 3.12, 0.60, decay=0.22, delay=1.44),
        _bell(B5, 3.12, 0.48, decay=0.25, delay=1.56),
    ), 90.0, 0.27, 0.15, 0x51B1, MAX_CALL_BYTES),
    CueSpec("call_outgoing_loop", -27.0, -3.0, (
        _bell(FS5, 3.18, 0.70, decay=0.20),
        _bell(B5, 3.18, 0.58, decay=0.24, delay=0.18),
        _bell(FS5, 3.18, 0.62, decay=0.20, delay=0.62),
        _bell(B5, 3.18, 0.50, decay=0.24, delay=0.80),
    ), 94.0, 0.27, 0.14, 0x51B2, MAX_CALL_BYTES),
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
    assert len(data) < spec.max_bytes, (spec.name, len(data))
    return data


def _targets(root: Path, rendered: dict[str, bytes]) -> dict[Path, bytes]:
    asset_directory = root / "assets" / "audio" / "ui" / ASSET_PACK_VERSION
    targets = {
        asset_directory / f"{name}.wav": data for name, data in rendered.items()
    }
    native = {
        "yovoice_notification": rendered["notification"],
        "yovoice_message_v1": rendered["notification"],
        "yovoice_social_v1": rendered["notification_social"],
        "yovoice_achievement_v1": rendered["notification_achievement"],
        "yovoice_alert_v1": rendered["notification_alert"],
        "yovoice_call_v2": rendered["call_incoming_loop"],
    }
    for name, data in native.items():
        targets[root / f"android/app/src/main/res/raw/{name}.wav"] = data
        targets[root / f"ios/Runner/{name}.wav"] = data
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
        print("sound assets match Prism Halo v5 generator")
        return 0

    retired_assets = _unexpected_flutter_assets(root, targets)
    for path in retired_assets:
        path.unlink()
    for path, data in targets.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    print(
        f"wrote {len(CUES)} versioned Prism Halo cues and native notification copies"
        f"; retired {len(retired_assets)} stale UI WAV(s)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
