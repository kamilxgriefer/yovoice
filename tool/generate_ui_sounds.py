#!/usr/bin/env python3
"""Build the complete YO Voice product-sound pack.

The checked-in WAV files are deterministic build artifacts of this script.
Run it from the repository root:

    python3 tool/generate_ui_sounds.py

Use ``--check`` in CI or before a release to prove that every checked-in copy
matches the generator without rewriting anything.

DESIGN LANGUAGE (v3, "Velvet Prism")

* No notes, scales, arpeggios, detune, chorus or melodic up/down grammar.
* Every cue combines one 4-10 ms filtered material contact, a muted
  inharmonic body and a very quiet air layer.
* Meaning lives in timbre: beginnings open their high-frequency texture and
  stereo width; endings rapidly fold both back into the mono body.
* The body stays mono. Only decorrelated air carries a small side signal, at
  least 14 dB below the mid channel, so headphones gain depth without a
  phasey Haas effect and mono playback remains solid.
* Internal synthesis is 48 kHz float. Delivery is stereo PCM16 at 48 kHz,
  with deterministic TPDF dither, a click-free tail and exact terminal zeroes.
* Loudness is mastered into each asset. ``UiSound.volume`` stays at 1.0, so
  the same notification bytes mean the same thing in Flutter, Android and
  iOS instead of being three unrelated mixes.

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
MAX_BYTES = 96 * 1024
TERMINAL_ZERO_FRAMES = 64
ASSET_PACK_VERSION = "v3"

# One deliberately non-musical material: the ratios do not describe a
# harmonic series or equal-tempered chord.
PARTIAL_RATIOS = (1.0, 1.47, 2.31, 3.88)
PARTIAL_LEVELS = (1.0, 0.29, 0.15, 0.065)
PARTIAL_PHASES = (0.17, 1.03, 2.11, 2.73)


@dataclass(frozen=True)
class CueSpec:
    name: str
    duration: float
    loudness_db: float
    peak_ceiling_db: float
    base_hz: float
    body_tau: float
    body_level: float
    contact_ms: float
    contact_low_hz: float
    contact_high_hz: float
    contact_level: float
    air_level: float
    width: float
    opening: bool
    seed: int


CUES = (
    CueSpec(
        "room_created", 0.360, -23.0, -6.0, 176.0, 0.105, 1.00,
        10.0, 1600.0, 4800.0, 0.34, 0.045, 0.14, True, 0x31A5,
    ),
    CueSpec(
        "room_joined", 0.240, -25.0, -8.0, 208.0, 0.074, 0.88,
        7.0, 1800.0, 5400.0, 0.29, 0.048, 0.13, True, 0x42B7,
    ),
    CueSpec(
        "room_left", 0.190, -26.0, -9.0, 208.0, 0.056, 0.84,
        6.0, 1300.0, 3400.0, 0.27, 0.024, 0.055, False, 0x53C9,
    ),
    CueSpec(
        "participant_joined", 0.135, -30.0, -11.0, 296.0, 0.039, 0.68,
        5.0, 2100.0, 5800.0, 0.38, 0.038, 0.095, True, 0x64DB,
    ),
    CueSpec(
        "participant_left", 0.125, -31.0, -12.0, 264.0, 0.032, 0.64,
        4.5, 1300.0, 3300.0, 0.34, 0.018, 0.035, False, 0x75ED,
    ),
    CueSpec(
        "microphone_muted", 0.095, -27.0, -9.0, 192.0, 0.024, 0.94,
        5.0, 1100.0, 2800.0, 0.42, 0.009, 0.018, False, 0x86F1,
    ),
    CueSpec(
        "microphone_unmuted", 0.115, -27.0, -9.0, 192.0, 0.031, 0.88,
        6.0, 1900.0, 5600.0, 0.38, 0.030, 0.065, True, 0x9703,
    ),
    CueSpec(
        "notification", 0.330, -20.0, -4.0, 232.0, 0.098, 1.00,
        8.0, 1700.0, 6400.0, 0.31, 0.052, 0.12, True, 0xA815,
    ),
)


class DeterministicNoise:
    """Small xorshift generator; identical on every supported Python."""

    def __init__(self, seed: int):
        self._state = seed & 0xFFFFFFFF or 1

    def sample(self) -> float:
        x = self._state
        x ^= (x << 13) & 0xFFFFFFFF
        x ^= x >> 17
        x ^= (x << 5) & 0xFFFFFFFF
        self._state = x & 0xFFFFFFFF
        return (self._state / 0xFFFFFFFF) * 2.0 - 1.0


def _lowpass(samples: list[float], cutoff_hz: float) -> list[float]:
    coefficient = 1.0 - math.exp(-2.0 * math.pi * cutoff_hz / RATE)
    value = 0.0
    output: list[float] = []
    for sample in samples:
        value += coefficient * (sample - value)
        output.append(value)
    return output


def _bandpass_noise(
    length: int,
    seed: int,
    low_hz: float,
    high_hz: float,
) -> list[float]:
    generator = DeterministicNoise(seed)
    raw = [generator.sample() for _ in range(length)]
    below_high = _lowpass(_lowpass(raw, high_hz), high_hz)
    below_low = _lowpass(_lowpass(raw, low_hz), low_hz)
    filtered = [high - low for high, low in zip(below_high, below_low)]
    rms = math.sqrt(sum(value * value for value in filtered) / length) or 1.0
    return [value / rms for value in filtered]


def _smooth_attack(time: float, duration: float) -> float:
    if duration <= 0.0 or time >= duration:
        return 1.0
    phase = max(0.0, time / duration)
    return math.sin(phase * math.pi / 2.0) ** 2


def _synthesise(spec: CueSpec) -> tuple[list[float], list[float]]:
    frame_count = round(spec.duration * RATE)
    contact_count = max(1, round(spec.contact_ms / 1000.0 * RATE))

    contact_mid = _bandpass_noise(
        contact_count,
        spec.seed,
        spec.contact_low_hz,
        spec.contact_high_hz,
    )
    contact_side = _bandpass_noise(
        contact_count,
        spec.seed ^ 0xBADC0FFE,
        spec.contact_low_hz,
        spec.contact_high_hz,
    )
    air_mid = _bandpass_noise(
        frame_count,
        spec.seed ^ 0x13579BDF,
        3200.0,
        7500.0,
    )
    air_side = _bandpass_noise(
        frame_count,
        spec.seed ^ 0x2468ACE0,
        3600.0,
        7900.0,
    )
    texture = _bandpass_noise(
        frame_count,
        spec.seed ^ 0xC001D00D,
        120.0,
        1050.0,
    )

    left = [0.0] * frame_count
    right = [0.0] * frame_count
    for index in range(frame_count):
        time = index / RATE

        body = 0.0
        for partial_index, (ratio, level, phase) in enumerate(
            zip(PARTIAL_RATIOS, PARTIAL_LEVELS, PARTIAL_PHASES)
        ):
            # Opening cues let the upper material wake a few milliseconds
            # later; closing cues shed those partials first. This changes
            # colour without spelling a note or sliding pitch.
            if spec.opening:
                attack = 0.0035 + partial_index * 0.0035
                tau = spec.body_tau / (1.0 + partial_index * 0.42)
            else:
                attack = 0.0025
                tau = spec.body_tau / (1.0 + partial_index * 0.92)
            envelope = _smooth_attack(time, attack) * math.exp(-time / tau)
            body += level * math.sin(
                2.0 * math.pi * spec.base_hz * ratio * time + phase
            ) * envelope
        body *= spec.body_level

        # A low-mid, aperiodic veil makes the material tactile rather than a
        # clean oscillator. It remains mono and dies with the body.
        veil = texture[index] * 0.055 * math.exp(-time / (spec.body_tau * 0.72))

        contact = 0.0
        contact_width = 0.0
        if index < contact_count:
            contact_time = index / RATE
            contact_envelope = (
                _smooth_attack(contact_time, 0.0012)
                * math.exp(-contact_time / (spec.contact_ms / 4300.0))
            )
            contact = contact_mid[index] * contact_envelope * spec.contact_level
            contact_width = (
                contact_side[index]
                * contact_envelope
                * spec.contact_level
                * spec.width
                * 0.45
            )

        if spec.opening:
            air_shape = _smooth_attack(time, 0.018) * math.exp(
                -time / (spec.body_tau * 1.15)
            )
            width_shape = _smooth_attack(time, 0.024)
        else:
            air_shape = _smooth_attack(time, 0.002) * math.exp(
                -time / (spec.body_tau * 0.46)
            )
            width_shape = math.exp(-time / 0.024)
        air = air_mid[index] * air_shape * spec.air_level
        side = (
            air_side[index]
            * air_shape
            * width_shape
            * spec.air_level
            * spec.width
            + contact_width
        )

        mid = body + veil + contact + air
        # Gentle saturation rounds the contact without flattening the body.
        mid = math.tanh(mid * 0.92) / math.tanh(0.92)
        side = math.tanh(side)
        left[index] = mid + side
        right[index] = mid - side

    # Raised-cosine master edges, followed by a short exact-zero pad. No cue
    # can click even if a platform decoder reads the final frame literally.
    fade_in = round(0.0015 * RATE)
    fade_out = round(min(0.014, spec.duration * 0.18) * RATE)
    for index in range(frame_count):
        gain = 1.0
        if index < fade_in:
            gain *= math.sin((index / fade_in) * math.pi / 2.0) ** 2
        tail_index = frame_count - 1 - index
        if tail_index < fade_out:
            gain *= math.sin((tail_index / fade_out) * math.pi / 2.0) ** 2
        left[index] *= gain
        right[index] *= gain
    for index in range(max(0, frame_count - TERMINAL_ZERO_FRAMES), frame_count):
        left[index] = 0.0
        right[index] = 0.0

    # Loudness is an unweighted deterministic proxy for the short cues. The
    # dBTP value remains a hard ceiling; the shorter transient may naturally
    # land below it, which is preferable to crushing it with compression.
    combined = left + right
    rms = math.sqrt(sum(value * value for value in combined) / len(combined)) or 1.0
    peak = max(abs(value) for value in combined) or 1.0
    rms_scale = 10.0 ** (spec.loudness_db / 20.0) / rms
    peak_scale = 10.0 ** (spec.peak_ceiling_db / 20.0) / peak
    scale = min(rms_scale, peak_scale)
    return (
        [value * scale for value in left],
        [value * scale for value in right],
    )


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
        print("sound assets match Velvet Prism v3 generator")
        return 0

    retired_assets = _unexpected_flutter_assets(root, targets)
    for path in retired_assets:
        path.unlink()
    for path, data in targets.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    print(
        "wrote 8 versioned Velvet Prism cues and 2 bit-identical native copies"
        f"; retired {len(retired_assets)} stale UI WAV(s)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
