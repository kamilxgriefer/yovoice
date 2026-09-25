#!/usr/bin/env python3
"""Build the complete YO Voice product-sound pack.

The checked-in WAV files are deterministic build artifacts of this script.
Run it from the repository root:

    python3 tool/generate_ui_sounds.py

Use ``--check`` in CI or before a release to prove that every checked-in copy
matches the generator without rewriting anything.

DESIGN LANGUAGE (v6, "Velvet Mallet")

* No voice layer and no bells. Every cue is a felt mallet on a muted wooden
  bar, written as modal synthesis: a fundamental plus three low, inharmonic
  bar modes (2.76x and 5.40x of a free bar, and the 3.99x overtone a marimba
  bar is tuned to). The upper modes die three to nine times faster than the
  fundamental, so each strike is a short woody "tok" that melts into a round
  tone.
* Felt, not metal: a raised-cosine contact of 2-6 ms and a contact-spectrum
  filter weight every mode by 1 / (1 + (f / felt_hz)^2), so higher notes and
  softer felt are automatically darker. A one-period, DC-free 160 Hz "knock"
  adds the mallet's soft body, and a 3 ms felt contact (deterministic noise
  band-passed at 1.5-2.8 kHz, 21-28 dB under each cue's peak) marks where
  the mallet lands. Nothing is detuned or chorused, and the 6.5 kHz
  low-pass still guards the top.
* Presence on phone speakers. A phone reproduces roughly 0.8-6 kHz, where A4
  and D5 fundamentals barely exist. The pack therefore doubles its low notes
  with a soft octave mallet: a second, pure octave bar struck with the note
  (its own overtones left unexcited), so presence lands at 0.9-1.8 kHz and
  nothing is added near the top. Presence here is one exact measure: the
  mono mix through an 8th-order Butterworth band-pass at 800 Hz-6 kHz
  (scipy's butter(N=4, btype="bandpass")), then the loudest 400 ms of its
  mean square. By that measure, at the same RMS as Prism Halo v5, 17 cues
  are at least as present as v5 and the outgoing ringback is at parity
  (-0.01 dB). The attacks are also punchier than v5's at the same RMS: in
  every cue the loudest 100 ms of K-weighted (BS.1770) power is higher, and
  in all but the incoming loop so is the crest factor. STFT power above
  7 kHz (1024-point Hann frames) stays at least 90 dB below that of a
  full-scale sine.
* The "o" of YO: long notes carry a resonator bloom, a fundamental plus an
  octave (the "o" vowel's second formant region) that swells in over 50 ms,
  is held with a slow sag and closes with a raised-cosine release, like a
  voice finishing a vowel or the tube under a marimba bar. The tube answers
  90 degrees behind the bar, so the bloom's fundamental is a cosine that
  sustains the struck note instead of piling onto its attack; the vowel's
  octave rides in phase with the octave mallet. The long note of the motif
  is a rounded vowel rather than a ping, and it always ends at a known time,
  so no tail is ever cut by the fade.
* Home key D major; every pitch is from the D major pentatonic
  (D E F# A B), which the generator asserts. The signature motif "YO" is A4
  then D5, short-long (0.12 s + a 0.40 s bloom). It is the whole message
  notification and the seed of every notification variant and call cue;
  notification.wav is the only cue that is the bare YO and nothing else.
* Calls knock before they speak. Every ring of the call loops opens with
  soft wooden knocks on D5 (two for an incoming ring, one for the outgoing
  ringback) and says the YO 130 ms later, so a call differs from a message
  from its first strike: another pitch and another rhythm, in the band a
  phone speaker reproduces. The generator asserts it: the log-spectrogram
  similarity of each loop's first 250 ms to the message notification must
  stay below 0.65 (see CALL_OPENING_MAX_SIMILARITY).
* Meaning: rising shapes open, create, join and connect; falling shapes leave
  and end; paired low pulses warn or decline; busy repeats the motif's short
  first note and never reaches the D. The microphone pair cannot be
  confused: muted is one low, dry, damped thock on D4 that lands from three
  semitones sharp (F4, 349 Hz, relaxing onto 294 Hz with an 18 ms time
  constant, within a third of a semitone by 40 ms), so it falls and closes;
  its 2.76x bar mode falls with it from 964 to 811 Hz, where a phone speaker
  hears it. Unmuted is two brighter taps, A4 then D5, 56 ms apart, so it
  rises and opens. The only pitch movement in the pack is that settle, the
  way a damped drum lands on its note.
* A short, soft, dark room (sparse early reflections, four damped combs,
  two allpasses, RT60 0.28-0.45 s, 0.18 s under the ticks, wet energy 17-26 dB
  below the dry and 27-29 dB under the ticks) replaces Prism Halo's plate-like
  single echo.
* Loudness is a deliberate hierarchy, mastered into each asset and asserted
  after dither: microphone ticks whisper (-27 dBFS RMS), participants
  -27/-28, rooms -22.5..-24.5, notifications -21..-22, calls -21.5..-23, the
  incoming loop -25 and the outgoing loop -27. Peaks stay at or below
  -3 dBFS.
* Internal synthesis is 48 kHz float, low-passed at 6.5 kHz, with a
  raised-cosine click-free fade and a symmetric mid/side width (see
  _widen): the mid is the signal itself, the side is two taps 0.92 ms apart
  placed evenly around it, so both channels carry exactly the same energy,
  the side stays at least 14 dB below the mid and mono playback loses
  nothing. Delivery is stereo PCM16 at 48 kHz, with deterministic
  half-amplitude triangular dither and exact terminal zeroes.
* UI cues are under 1.1 s and 220 KB. The two call cadences are exactly
  3.2 s, under 700 KB (the app's asset-test bound), and seamless when looped
  by CallToneService, which can stop them immediately on answer, decline,
  cancellation, backgrounding or disposal: every tail has decayed below
  -60 dBFS long before the seam. The incoming loop rings three times, 0.6 s
  apart, and rests about a second, so the seam falls inside its rest; the
  outgoing ringback rings every 1.6 s, evenly across the seam.

The sound is intentionally restrained. Normal navigation, loading, likes and
sheet transitions stay silent; only semantic communication events have cues.
"""

from __future__ import annotations

import argparse
import functools
import io
import math
import struct
import sys
import wave
from dataclasses import dataclass, replace
from pathlib import Path


RATE = 48_000
SAMPLE_WIDTH = 2
CHANNELS = 2
MAX_UI_BYTES = 220 * 1024
MAX_CALL_BYTES = 700 * 1024  # the app's asset test bound for the loops
MAX_UI_SECONDS = 1.1
MAX_LOOP_SECONDS = 3.5
TERMINAL_ZERO_FRAMES = 64
PAD_FRAMES = 160
LOWPASS_HZ = 6500.0
WIDTH_DELAY_FRAMES = 44  # 0.92 ms between the two side taps; must be even
WIDTH_SIDE = 0.06  # side level of each tap relative to the mid
FADE_MS = 40.0
ASSET_PACK_VERSION = "v6"


def _note(semitones_from_c4: float) -> float:
    return 440.0 * 2 ** ((semitones_from_c4 - 9) / 12)


# D major pentatonic only: D E F# A B.
A3, B3 = _note(-3), _note(-1)
D4, E4, FS4, A4, B4 = _note(2), _note(4), _note(6), _note(9), _note(11)
D5, E5, FS5, A5, B5 = _note(14), _note(16), _note(18), _note(21), _note(23)
D6 = _note(26)

# Modal voices: (frequency ratio, weight before the felt filter, decay scale
# relative to the fundamental). 2.76 and 5.40 are the free-bar modes that give
# wood its knock; 3.99 is the double-octave a marimba bar is tuned to.
WOOD = ((1.0, 1.0, 1.0), (2.76, 0.34, 0.20), (3.99, 0.46, 0.35), (5.40, 0.14, 0.11))
# A dead stroke for ticks and busy pulses: the bar is held, so the modes
# stay closer together in decay and the knock carries the definition.
WOOD_DEAD = ((1.0, 1.0, 1.0), (2.76, 0.42, 0.45), (3.99, 0.40, 0.40))
# The microphone-off thock: a bar damped at its end, so its first bar mode
# (2.76x) rings nearly as long as the fundamental. On D4 that mode sits at
# 0.81 kHz, which gives the thock a body a phone speaker can reproduce while
# keeping it darker than the unmuted taps.
WOOD_THOCK = ((1.0, 1.0, 1.0), (2.76, 0.70, 0.90), (3.99, 0.30, 0.50))
# Resonator bloom: the tube under the bar, the round "o" of the long note:
# its fundamental plus the octave that carries an "o" vowel's second formant
# (vowel is that octave's level relative to the bloom's fundamental).
BLOOM_VOWEL = 0.30
BLOOM_SAG = 0.60  # slow sag of the vowel body while it is held
KNOCK_HZ = 160.0
# Octave mallet: a second mallet an octave up, struck with the note, so small
# speakers hear the pitch where they are efficient. It dies at 0.8x the
# note's decay unless a strike sets octave_decay (the motif's D5 does, since
# its bloom, not its strike, carries the sustain). Soft felt on the short
# octave bar excites only its fundamental, so the octave adds presence at
# 0.9-1.8 kHz and nothing near the top.
OCTAVE_DECAY = 0.80
OCTAVE_MODES = ((1.0, 1.0, 1.0),)
# Felt contact: the few milliseconds where felt meets wood. Deterministic
# noise through six band-pass stages around 1.5-2.8 kHz (tracking the felt;
# about a third of an octave wide, with steep skirts), rising in 0.8 ms and
# decaying with a 2.5 ms time constant: definition, never a click, and
# nothing above the 6.5 kHz guard.
CONTACT = 0.10
CONTACT_Q = 1.0
CONTACT_STAGES = 6
CONTACT_RISE = 0.0008
CONTACT_TAU = 0.0025
# Settle: a struck, damped body starts slightly sharp and relaxes onto its
# pitch; settle_tau is how fast it lands.
SETTLE_TAU = 0.018


@dataclass(frozen=True)
class Strike:
    hz: float
    at: float
    level: float
    decay: float
    attack: float = 0.006
    felt_hz: float = 1500.0
    modes: tuple[tuple[float, float, float], ...] = WOOD
    # The "o": a fundamental that swells in over bloom_attack, is held with a
    # slow sag, then closes with a raised-cosine release, like a voice
    # finishing a vowel. It always ends at at + bloom_hold + bloom_release.
    bloom: float = 0.0
    bloom_attack: float = 0.05
    bloom_hold: float = 0.22
    bloom_release: float = 0.16
    vowel: float = BLOOM_VOWEL
    knock: float = 0.10
    # A softer octave mallet struck with the note (level relative to it).
    octave: float = 0.0
    # Its decay in seconds; 0 means the note's decay times OCTAVE_DECAY.
    octave_decay: float = 0.0
    # The felt contact transient (level relative to the note).
    contact: float = CONTACT
    # Semitones sharp at contact, relaxing onto hz (a damped "thock" falls).
    settle: float = 0.0

    @property
    def bloom_end(self) -> float:
        return self.at + self.bloom_hold + self.bloom_release if self.bloom else self.at

    @property
    def octave_tau(self) -> float:
        return self.octave_decay or self.decay * OCTAVE_DECAY

    @property
    def slowest_tau(self) -> float:
        """The longest-ringing decay in the strike, octave mallet included."""
        slowest = self.decay * max(scale for _, _, scale in self.modes)
        return max(slowest, self.octave_tau) if self.octave else slowest


@dataclass(frozen=True)
class CueSpec:
    name: str
    loudness_db: float
    seconds: float
    strikes: tuple[Strike, ...]
    room_wet: float
    room_rt60: float
    seed: int
    loop: bool = False
    tick: bool = False
    peak_ceiling_db: float = -3.0

    @property
    def frames(self) -> int:
        return int(round(self.seconds * RATE))

    @property
    def max_bytes(self) -> int:
        return MAX_CALL_BYTES if self.loop else MAX_UI_BYTES


def _s(hz, at, level, decay, **kwargs) -> Strike:
    return Strike(hz, at, level, decay, **kwargs)


YO_SHORT = 0.12  # the "Y": A4, then the "O": D5, 0.12 s later


def _yo(at: float, scale: float, *, octave: float, felt_hz: float,
        bloom: float, bass: float, vowel: float = BLOOM_VOWEL,
        octave_decay: float = 0.15, bloom_hold: float = 0.24,
        bloom_release: float = 0.16) -> tuple[Strike, ...]:
    """The sonic logo: A4 short, then D5 long, voiced as a rounded "o".

    By default the D5 strike blooms for 0.24 s and closes over 0.16 s, so the
    motif is 0.12 s + 0.40 s long before the room; the call rings close it
    sooner. Both notes carry a soft octave mallet (octave is its level
    relative to the note), which is what a phone speaker hears of the motif;
    it adds presence, not a new pitch.
    """
    strikes = [
        _s(A4, at, 0.66 * scale, 0.075, felt_hz=felt_hz, octave=octave),
        _s(D5, at + YO_SHORT, 0.84 * scale, 0.12, felt_hz=felt_hz, octave=octave,
           octave_decay=octave_decay, bloom=bloom, bloom_hold=bloom_hold,
           bloom_release=bloom_release, vowel=vowel),
    ]
    if bass > 0.0:
        strikes.append(
            _s(D4, at + YO_SHORT, bass * scale, 0.14, felt_hz=1000.0, knock=0.0,
               contact=0.0)
        )
    return tuple(strikes)


KNOCK_GAP = 0.065  # between the two knocks of an incoming ring
RING_LEAD = 0.13  # from a ring's first knock to its "Y"


def _ring(at: float, scale: float, *, knock_levels: tuple[float, ...],
          knock_octave: float, yo_octave: float, felt_hz: float, bloom: float,
          vowel: float, bloom_hold: float, bloom_release: float) -> tuple[Strike, ...]:
    """The call family's ring: soft wooden knocks on D5, then the YO.

    A call knocks before it speaks. The knocks are short D5 strikes (not the
    160 Hz mallet-body Strike.knock), KNOCK_GAP apart, at knock_levels
    relative to the ring: two for an incoming ring, one for the outgoing
    ringback. The motif's "Y" follows RING_LEAD after the first knock. The
    knocks sit on the motif's own home note, and their octave mallet puts
    them in the band a phone speaker reproduces, so the first 130 ms of any
    call already differ from the bare YO of a message: other strikes,
    another pitch and another rhythm.
    """
    strikes = tuple(
        _s(D5, at + KNOCK_GAP * index, level * scale, 0.05, felt_hz=1700.0,
           octave=knock_octave)
        for index, level in enumerate(knock_levels)
    )
    return strikes + _yo(at + RING_LEAD, scale, octave=yo_octave, felt_hz=felt_hz,
                         bloom=bloom, bass=0.0, vowel=vowel, bloom_hold=bloom_hold,
                         bloom_release=bloom_release)


def _incoming_ring(at: float, scale: float) -> tuple[Strike, ...]:
    return _ring(at, scale, knock_levels=(0.50, 0.44), knock_octave=1.0,
                 yo_octave=1.1, felt_hz=1900.0, bloom=0.50, vowel=1.0,
                 bloom_hold=0.18, bloom_release=0.14)


def _outgoing_ring(at: float) -> tuple[Strike, ...]:
    return _ring(at, 1.0, knock_levels=(0.48,), knock_octave=1.0,
                 yo_octave=1.45, felt_hz=1800.0, bloom=0.32, vowel=1.5,
                 bloom_hold=0.20, bloom_release=0.14)


CUES = (
    # Rooms (Servers): open fifths stacked upward, even steps.
    CueSpec("room_created", -22.5, 1.04, (
        _s(D4, 0.000, 0.40, 0.16, felt_hz=1300.0),
        _s(A4, 0.085, 0.60, 0.12, octave=0.5),
        _s(D5, 0.170, 0.68, 0.13, felt_hz=1700.0, octave=0.5),
        _s(A5, 0.260, 0.62, 0.15, felt_hz=1800.0,
           bloom=0.40, bloom_hold=0.20, bloom_release=0.18, vowel=0.40),
    ), 0.20, 0.42, 0x61A1),
    CueSpec("room_joined", -23.5, 0.80, (
        _s(D5, 0.000, 0.70, 0.10, felt_hz=1800.0, octave=0.90),
        _s(A5, 0.090, 0.72, 0.13, felt_hz=1800.0, octave=0.30,
           bloom=0.35, bloom_hold=0.16, bloom_release=0.16, vowel=0.95),
    ), 0.18, 0.40, 0x61A2),
    CueSpec("room_left", -24.5, 0.78, (
        _s(A5, 0.000, 0.68, 0.10, felt_hz=1700.0, octave=0.60),
        _s(D5, 0.100, 0.74, 0.13, felt_hz=1600.0, octave=1.00,
           bloom=0.30, bloom_hold=0.14, bloom_release=0.16, vowel=1.15),
    ), 0.16, 0.40, 0x61A3),
    # Participants: a tiny 45 ms flam, up for arrival, down for departure.
    CueSpec("participant_joined", -27.0, 0.46, (
        _s(B5, 0.000, 0.40, 0.05, attack=0.005, felt_hz=1500.0),
        _s(D6, 0.045, 0.72, 0.075, attack=0.005, felt_hz=1500.0),
    ), 0.12, 0.28, 0x61A4),
    CueSpec("participant_left", -28.0, 0.46, (
        _s(D6, 0.000, 0.40, 0.05, attack=0.005, felt_hz=1400.0),
        _s(B5, 0.045, 0.70, 0.075, attack=0.005, felt_hz=1200.0),
    ), 0.12, 0.28, 0x61A5),
    # Microphone: a pair that cannot be confused. Muted is one low, dry,
    # damped thock on D4 that lands from three semitones sharp, so it falls
    # and closes; its 2.76x bar mode falls with it (0.96 to 0.81 kHz) where a
    # phone speaker hears it. Unmuted is two light, brighter taps rising a
    # fourth, A4 then D5 (the motif's own interval), 56 ms apart, so it opens.
    CueSpec("microphone_muted", -27.0, 8800 / RATE, (
        _s(D4, 0.000, 0.90, 0.034, attack=0.002, felt_hz=1300.0,
           modes=WOOD_THOCK, knock=0.12, settle=3.0, contact=0.10),
    ), 0.05, 0.18, 0x61A6, tick=True),
    CueSpec("microphone_unmuted", -27.0, 8800 / RATE, (
        _s(A4, 0.000, 0.62, 0.020, attack=0.002, felt_hz=2200.0,
           modes=WOOD_DEAD, knock=0.05, octave=0.5, contact=0.14),
        _s(D5, 0.056, 0.78, 0.021, attack=0.002, felt_hz=2600.0,
           modes=WOOD_DEAD, knock=0.05, octave=0.6, contact=0.14),
    ), 0.06, 0.18, 0x61A7, tick=True),
    # Notifications: the YO motif and its answers.
    CueSpec("notification", -21.5, 0.88,
        _yo(0.0, 1.0, octave=1.1, felt_hz=2300.0, bloom=0.44, bass=0.10,
            vowel=1.1),
        0.20, 0.42, 0x61A8),
    CueSpec("notification_social", -22.0, 0.90, (
        _s(A4, 0.000, 0.62, 0.07, felt_hz=1800.0, octave=0.9),
        _s(D5, 0.100, 0.70, 0.09, felt_hz=1800.0, octave=0.8),
        _s(E5, 0.200, 0.60, 0.14, felt_hz=1800.0, octave=0.8,
           bloom=0.40, bloom_hold=0.18, bloom_release=0.16, vowel=1.00),
    ), 0.18, 0.40, 0x61A9),
    CueSpec("notification_achievement", -21.5, 1.08, (
        _s(D4, 0.000, 0.24, 0.13, felt_hz=1100.0),
        _s(A4, 0.000, 0.58, 0.08, felt_hz=1600.0, octave=1.0),
        _s(D5, 0.090, 0.64, 0.09, felt_hz=1600.0, octave=1.0),
        _s(FS5, 0.180, 0.56, 0.10, felt_hz=1600.0, octave=1.0),
        _s(A5, 0.290, 0.56, 0.15, felt_hz=1600.0, octave=1.0,
           bloom=0.38, bloom_hold=0.22, bloom_release=0.18, vowel=1.00),
        _s(D5, 0.290, 0.16, 0.15, felt_hz=1200.0, knock=0.0, contact=0.0),
    ), 0.22, 0.45, 0x61AA),
    CueSpec("notification_alert", -21.0, 0.90, tuple(
        strike
        for at, scale in ((0.00, 1.0), (0.165, 0.94))
        for strike in (
            _s(A4, at, 0.70 * scale, 0.12, felt_hz=2300.0, octave=0.70),
            _s(D5, at, 0.62 * scale, 0.12, felt_hz=2300.0, octave=0.70),
            _s(D4, at, 0.16 * scale, 0.12, felt_hz=1000.0, knock=0.0, contact=0.0),
        )
    ), 0.14, 0.34, 0x61AB),
    # Calls: the motif connects upward into a D major colour, ends by
    # falling home to D, declines in a low falling pair and fails in a
    # falling chain of fourths that stops, unresolved, on E.
    CueSpec("call_connected", -21.5, 1.02, (
        _s(A4, 0.000, 0.64, 0.075, felt_hz=1800.0, octave=0.8),
        _s(D5, 0.120, 0.78, 0.13, felt_hz=1800.0, octave=0.7,
           bloom=0.40, bloom_hold=0.16, bloom_release=0.14, vowel=1.00),
        _s(D4, 0.120, 0.20, 0.15, felt_hz=1000.0, knock=0.0, contact=0.0),
        _s(FS5, 0.280, 0.48, 0.145, felt_hz=1800.0,
           bloom=0.35, bloom_hold=0.20, bloom_release=0.18, vowel=0.50),
        _s(A5, 0.280, 0.42, 0.145, felt_hz=1800.0,
           bloom=0.30, bloom_hold=0.20, bloom_release=0.18, vowel=0.50,
           knock=0.0, contact=0.0),
    ), 0.20, 0.42, 0x61AC),
    CueSpec("call_ended", -23.0, 0.96, (
        _s(A5, 0.000, 0.60, 0.08, felt_hz=1700.0, octave=0.6),
        _s(FS5, 0.110, 0.64, 0.09, felt_hz=1500.0, octave=0.8),
        _s(D5, 0.230, 0.72, 0.14, felt_hz=1500.0, octave=1.0,
           bloom=0.30, bloom_hold=0.16, bloom_release=0.18, vowel=1.00),
        _s(D4, 0.230, 0.20, 0.14, felt_hz=950.0, knock=0.0, contact=0.0),
    ), 0.17, 0.40, 0x61AD),
    CueSpec("call_declined", -22.5, 0.98, (
        _s(D5, 0.000, 0.74, 0.10, felt_hz=1500.0, octave=0.42),
        _s(D4, 0.000, 0.22, 0.11, felt_hz=950.0, knock=0.0, contact=0.0),
        _s(A4, 0.210, 0.76, 0.14, felt_hz=1300.0, octave=0.48),
        _s(A3, 0.210, 0.22, 0.14, felt_hz=900.0, knock=0.0, contact=0.0),
    ), 0.12, 0.34, 0x61AE),
    CueSpec("call_failed", -22.0, 1.02, (
        _s(E5, 0.000, 0.70, 0.09, felt_hz=1500.0, octave=0.5),
        _s(B4, 0.160, 0.70, 0.10, felt_hz=1400.0, octave=0.55),
        _s(E4, 0.320, 0.74, 0.14, felt_hz=1250.0, octave=0.55),
        _s(B3, 0.320, 0.20, 0.14, felt_hz=900.0, knock=0.0, contact=0.0),
    ), 0.12, 0.34, 0x61AF),
    # Busy: the motif's short A, three times, never reaching the D.
    CueSpec("call_busy", -22.0, 1.08, tuple(
        strike
        for at, level in ((0.00, 0.76), (0.30, 0.72), (0.60, 0.68))
        for strike in (
            _s(A4, at, level, 0.08, attack=0.004, felt_hz=1600.0,
               modes=WOOD_DEAD, octave=0.22),
            _s(A3, at, level * 0.30, 0.08, attack=0.004, felt_hz=900.0,
               modes=WOOD_DEAD, knock=0.0, contact=0.0),
        )
    ), 0.08, 0.28, 0x61B0),
    # Loops. Incoming: three rings 0.6 s apart ("knock-knock, YO" each, the
    # middle one a touch softer), then about a second of rest; the seam gap is
    # the rest.
    CueSpec("call_incoming_loop", -25.0, 3.20,
        _incoming_ring(0.00, 1.00)
        + _incoming_ring(0.60, 0.86)
        + _incoming_ring(1.20, 0.92),
        0.18, 0.42, 0x61B1, loop=True),
    # Outgoing ringback: one soft knock and a darker YO every 1.6 s, evenly
    # across the seam.
    CueSpec("call_outgoing_loop", -27.0, 3.20,
        _outgoing_ring(0.00) + _outgoing_ring(1.60),
        0.16, 0.40, 0x61B2, loop=True),
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


def _felt(hz: float, felt_hz: float) -> float:
    """Contact spectrum of a felt mallet: soft felt barely excites high modes."""
    return 1.0 / (1.0 + (hz / felt_hz) ** 2)


def _add_decaying(out: list[float], start: int, hz: float, amplitude: float,
                  attack: float, tau: float, settle: float = 0.0) -> None:
    """Add amplitude * raised-cosine attack * exp(-t / tau) * sin(phase).

    With settle, the pitch starts that many semitones sharp and relaxes onto
    hz with SETTLE_TAU, the way a damped, struck body lands on its note."""
    if amplitude <= 0.0 or hz * 2 ** (settle / 12) >= RATE * 0.45:
        return
    omega = 2.0 * math.pi * hz / RATE
    step = math.exp(-1.0 / (tau * RATE))
    settle_step = math.exp(-1.0 / (SETTLE_TAU * RATE))
    attack_frames = max(1, int(attack * RATE))
    envelope = amplitude
    bend = settle
    phase = 0.0
    for n in range(len(out) - start):
        if n >= attack_frames and envelope < 1e-7:
            break
        rise = 1.0 if n >= attack_frames else 0.5 - 0.5 * math.cos(math.pi * n / attack_frames)
        if settle:
            out[start + n] += envelope * rise * math.sin(phase)
            phase += omega * 2 ** (bend / 12)
            bend *= settle_step
        else:
            out[start + n] += envelope * rise * math.sin(omega * n)
        envelope *= step


def _add_vowel(out: list[float], start: int, hz: float, amplitude: float,
               strike: Strike, quadrature: bool = True) -> None:
    """The held, closing "o": swell in, sag slowly, release to exact zero.

    A resonator driven at its resonance answers 90 degrees behind the bar, so
    the bloom is a cosine against the strike's sine: the tube sustains the
    note instead of piling onto the strike's own fundamental."""
    omega = 2.0 * math.pi * hz / RATE
    rise = max(1, int(strike.bloom_attack * RATE))
    hold = int(strike.bloom_hold * RATE)
    release = max(1, int(strike.bloom_release * RATE))
    sag = math.exp(-1.0 / (BLOOM_SAG * RATE))
    envelope = amplitude
    for n in range(min(hold + release, len(out) - start)):
        shape = 1.0 if n >= rise else 0.5 - 0.5 * math.cos(math.pi * n / rise)
        if n >= hold:
            shape *= 0.5 + 0.5 * math.cos(math.pi * (n - hold) / release)
        wave_ = math.cos(omega * n) if quadrature else math.sin(omega * n)
        out[start + n] += envelope * shape * wave_
        envelope *= sag


def _contact_hz(felt_hz: float) -> float:
    """Softer felt lands lower: the contact band tracks the felt, 1.5-2.8 kHz."""
    return min(2800.0, max(1500.0, 1.25 * felt_hz))


def _add_contact(out: list[float], start: int, amplitude: float,
                 centre_hz: float, seed: int) -> None:
    """The felt meeting the bar: a deterministic noise burst (0.8 ms rise,
    2.5 ms decay) through CONTACT_STAGES band-passes at centre_hz, scaled so
    its peak is amplitude. It is a few milliseconds of "where the mallet
    landed" in the band a phone speaker reproduces, with no energy left to
    click and none above the 6.5 kHz guard."""
    if amplitude <= 0.0:
        return
    noise = DeterministicNoise(seed)
    rise = max(1, int(CONTACT_RISE * RATE))
    length = int(CONTACT_TAU * RATE * 9)  # the burst is 78 dB down by its end
    step = math.exp(-1.0 / (CONTACT_TAU * RATE))
    burst = []
    envelope = 1.0
    for n in range(length):
        shape = 1.0 if n >= rise else 0.5 - 0.5 * math.cos(math.pi * n / rise)
        burst.append(noise.sample() * envelope * shape)
        envelope *= step
    # Room for the band-passes to ring down: their tail is included, not cut.
    burst += [0.0] * length
    w0 = 2.0 * math.pi * centre_hz / RATE
    alpha = math.sin(w0) / (2.0 * CONTACT_Q)
    a0 = 1.0 + alpha
    b0, b2 = alpha / a0, -alpha / a0
    a1, a2 = -2.0 * math.cos(w0) / a0, (1.0 - alpha) / a0
    for _ in range(CONTACT_STAGES):
        x1 = x2 = y1 = y2 = 0.0
        filtered = []
        for x in burst:
            y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
            x2, x1, y2, y1 = x1, x, y1, y
            filtered.append(y)
        burst = filtered
    # Close the last 20% with a raised cosine so the ring-down ends at zero.
    close = len(burst) // 5
    for i in range(close):
        burst[-1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / close)
    scale = amplitude / max(abs(value) for value in burst)
    for n in range(min(len(burst), len(out) - start)):
        out[start + n] += scale * burst[n]


def _strike_into(out: list[float], strike: Strike) -> None:
    start = int(round(strike.at * RATE))
    reference = _felt(strike.hz, strike.felt_hz)
    for ratio, weight, decay_scale in strike.modes:
        hz = strike.hz * ratio
        amplitude = strike.level * weight * _felt(hz, strike.felt_hz) / reference
        _add_decaying(out, start, hz, amplitude, strike.attack,
                      strike.decay * decay_scale, strike.settle)
    if strike.bloom > 0.0:
        for ratio, weight in ((1.0, 1.0), (2.0, strike.vowel)):
            _add_vowel(out, start, strike.hz * ratio,
                       strike.level * strike.bloom * weight, strike,
                       quadrature=(ratio == 1.0))
    if strike.octave > 0.0:
        # A second, softer mallet on the octave bar: same felt, faster decay.
        _strike_into(out, replace(
            strike, hz=strike.hz * 2.0, level=strike.level * strike.octave,
            decay=strike.octave_tau, modes=OCTAVE_MODES, bloom=0.0,
            knock=0.0, octave=0.0, contact=0.0, settle=0.0))
    if strike.contact > 0.0:
        seed = (int(round(strike.hz * 100)) * 7919 + start * 104729) & 0xFFFFFFFF
        _add_contact(out, start, strike.level * strike.contact,
                     _contact_hz(strike.felt_hz), seed)
    if strike.knock > 0.0:
        # One Hann-windowed period of a low sine: a soft, DC-free felt body.
        frames = int(RATE / KNOCK_HZ)
        amplitude = strike.level * strike.knock
        for n in range(min(frames, len(out) - start)):
            phase = 2.0 * math.pi * n / frames
            out[start + n] += amplitude * (0.5 - 0.5 * math.cos(phase)) * math.sin(phase)


# Sparse early reflections (ms, gain) and the damped late field of a small,
# soft room. Alternating signs keep the early pattern from colouring the tone.
EARLY = ((5.3, 0.40), (9.7, 0.31), (13.1, -0.24), (19.3, 0.19),
         (26.9, -0.14), (33.7, 0.10))
COMBS_MS = (29.7, 37.1, 41.1, 43.7)
ALLPASSES = ((5.0, 0.6), (1.7, 0.6))
PREDELAY_MS = 11.0
ROOM_DAMP_HZ = 2600.0


def _one_pole_coefficient(cutoff_hz: float) -> float:
    rc = 1 / (2 * math.pi * cutoff_hz)
    dt = 1 / RATE
    return dt / (rc + dt)


def _room(signal: list[float], wet: float, rt60: float) -> list[float]:
    if wet <= 0.0:
        return list(signal)
    frames = len(signal)
    early = [0.0] * frames
    for ms, gain in EARLY:
        delay = int(RATE * ms / 1000)
        for i in range(delay, frames):
            early[i] += gain * signal[i - delay]

    predelay = int(RATE * PREDELAY_MS / 1000)
    source = [0.0] * predelay + signal[: frames - predelay]
    damp = _one_pole_coefficient(ROOM_DAMP_HZ)
    late = [0.0] * frames
    for ms in COMBS_MS:
        delay = int(RATE * ms / 1000)
        feedback = 10 ** (-3.0 * (ms / 1000) / rt60)
        buffer = [0.0] * frames
        state = 0.0
        for i in range(frames):
            delayed = buffer[i - delay] if i >= delay else 0.0
            state += damp * (delayed - state)
            buffer[i] = source[i] + feedback * state
            late[i] += 0.25 * delayed
    for ms, gain in ALLPASSES:
        delay = int(RATE * ms / 1000)
        passed = [0.0] * frames
        for i in range(frames):
            back = passed[i - delay] if i >= delay else 0.0
            forward = late[i - delay] if i >= delay else 0.0
            passed[i] = -gain * late[i] + forward + gain * back
        late = passed

    tone = _lowpass([e + l for e, l in zip(early, late)], ROOM_DAMP_HZ)
    return [dry + wet * value for dry, value in zip(signal, tone)]


def _lowpass(samples: list[float], cutoff_hz: float) -> list[float]:
    alpha = _one_pole_coefficient(cutoff_hz)
    y = 0.0
    out = []
    for x in samples:
        y += alpha * (x - y)
        out.append(y)
    return out


def _fade_out(samples: list[float], ms: float = FADE_MS) -> list[float]:
    out = list(samples)
    frames = int(RATE * ms / 1000)
    for i in range(frames):
        out[-1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / frames)
    return out


def _widen(mono: list[float]) -> tuple[list[float], list[float]]:
    """Symmetric mid/side width: depth on headphones, no lean, nothing lost
    in mono.

    The mid is the signal delayed by half of WIDTH_DELAY_FRAMES; the side is
    WIDTH_SIDE * (x[n - D] - x[n]), two taps D frames apart placed evenly
    around the mid's sample; L = mid + side and R = mid - side. Because the
    side is antisymmetric about the mid, sum(mid * side) is
    WIDTH_SIDE * (R(D/2) - R(D/2)) = 0 for the signal's autocorrelation R, so
    both channels carry exactly the same energy (each has the power
    response |H|^2 = 1 + 4 b^2 sin^2(w D / 2)), (L + R) / 2 is exactly the mono
    signal, and only the phase between the ears differs. Every product lies
    inside the buffer (the body ends PAD_FRAMES before the file does), so the
    balance is exact rather than approximate, the first frame stays zero and
    the last PAD_FRAMES - D frames stay exactly zero."""
    half = WIDTH_DELAY_FRAMES // 2
    left: list[float] = []
    right: list[float] = []
    for i, value in enumerate(mono):
        mid = mono[i - half] if i >= half else 0.0
        early = mono[i - WIDTH_DELAY_FRAMES] if i >= WIDTH_DELAY_FRAMES else 0.0
        side = WIDTH_SIDE * (early - value)
        left.append(mid + side)
        right.append(mid - side)
    return left, right


def _dry_mono(spec: CueSpec) -> list[float]:
    body = spec.frames - PAD_FRAMES
    mono = [0.0] * body
    for strike in spec.strikes:
        _strike_into(mono, strike)
    return mono


@functools.lru_cache(maxsize=None)
def _synthesise(spec: CueSpec) -> tuple[list[float], list[float]]:
    mono = _dry_mono(spec)
    mono = _room(mono, spec.room_wet, spec.room_rt60)
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


def _db(value: float) -> float:
    return 20.0 * math.log10(max(value, 1e-12))


PENTATONIC_FROM_D = {0, 2, 4, 7, 9}  # D E F# A B


def _assert_pentatonic(spec: CueSpec) -> None:
    """Every strike is an equal-tempered D major pentatonic pitch."""
    for strike in spec.strikes:
        semitones = 12 * math.log2(strike.hz / D4)
        assert abs(semitones - round(semitones)) < 1e-9, (spec.name, strike.hz)
        assert round(semitones) % 12 in PENTATONIC_FROM_D, (spec.name, strike.hz)


def _assert_designed_tails(spec: CueSpec) -> None:
    """Every strike rings out before the fade, so the fade never truncates a
    note: -40 dB for UI cues, -30 dB for the 0.18 s ticks (a held, dead
    stroke), -60 dB for loops. Every vowel bloom has closed by then too."""
    fade_start = (spec.frames - PAD_FRAMES) / RATE - FADE_MS / 1000
    floor_db = -60.0 if spec.loop else (-30.0 if spec.tick else -40.0)
    for strike in spec.strikes:
        remaining_db = _db(math.exp(-(fade_start - strike.at) / strike.slowest_tau))
        assert remaining_db <= floor_db, (spec.name, strike.hz, strike.at, remaining_db)
        assert strike.bloom_end <= fade_start, (spec.name, strike.hz, strike.at)


# A call must not be mistaken for a message. The measure is the cosine
# similarity of two log-magnitude spectrograms of the first 250 ms of the
# mastered mono mix (before dither): 2048-point periodic Hann frames, a
# 256-frame hop, and each spectrogram floored 60 dB under its own peak (so
# both pitch and rhythm count and near-silence does not). Identical openings
# score 1.0; the first Velvet Mallet loops, which opened with the bare YO,
# scored 0.996 (incoming) and 0.969 (outgoing). The notification variants,
# which deliberately share the motif's first note and must still be told
# apart from a message, score 0.73 to 0.77 against it, and the Prism Halo v5
# call loops scored 0.48 and 0.58 against the v5 message sound. A call
# opening must stay below 0.65: further from the message than any
# notification variant is, and in the range of the v5 call family.
CALL_OPENING_SECONDS = 0.25
CALL_OPENING_MAX_SIMILARITY = 0.65
SPECTROGRAM_FRAME = 2048
SPECTROGRAM_HOP = 256
SPECTROGRAM_FLOOR_DB = 60.0


@functools.lru_cache(maxsize=None)
def _fft_plan(size: int) -> tuple[tuple[int, ...], tuple[tuple[complex, ...], ...]]:
    """Bit-reversed order and per-stage twiddles for a radix-2 FFT."""
    bits = size.bit_length() - 1
    order = tuple(int(format(index, f"0{bits}b")[::-1], 2) for index in range(size))
    stages = []
    span = 2
    while span <= size:
        angle = -2.0 * math.pi / span
        stages.append(tuple(
            complex(math.cos(angle * k), math.sin(angle * k)) for k in range(span // 2)))
        span *= 2
    return order, tuple(stages)


def _fft(values: list[complex]) -> list[complex]:
    """Iterative radix-2 FFT (len(values) must be a power of two)."""
    size = len(values)
    order, stages = _fft_plan(size)
    out = [values[index] for index in order]
    span = 2
    for twiddles in stages:
        half = span // 2
        for start in range(0, size, span):
            for k in range(half):
                even = out[start + k]
                odd = out[start + k + half] * twiddles[k]
                out[start + k] = even + odd
                out[start + k + half] = even - odd
        span *= 2
    return out


def _log_spectrogram(samples: list[float]) -> list[float]:
    """Flattened dB magnitudes, floored SPECTROGRAM_FLOOR_DB under the peak
    and shifted so the floor is zero."""
    frame = SPECTROGRAM_FRAME
    window = [0.5 - 0.5 * math.cos(2.0 * math.pi * i / frame) for i in range(frame)]
    levels: list[float] = []
    for start in range(0, len(samples) - frame + 1, SPECTROGRAM_HOP):
        spectrum = _fft([complex(samples[start + i] * window[i], 0.0)
                         for i in range(frame)])
        levels.extend(20.0 * math.log10(abs(value) + 1e-12)
                      for value in spectrum[: frame // 2 + 1])
    floor = max(levels) - SPECTROGRAM_FLOOR_DB
    return [max(level, floor) - floor for level in levels]


def _opening_similarity(first: CueSpec, second: CueSpec) -> float:
    """Log-spectrogram cosine similarity of the two cues' first 250 ms."""
    frames = int(CALL_OPENING_SECONDS * RATE)
    spectrograms = []
    for spec in (first, second):
        left, right = _synthesise(spec)
        mono = [(l + r) * 0.5 for l, r in zip(left[:frames], right[:frames])]
        spectrograms.append(_log_spectrogram(mono + [0.0] * (frames - len(mono))))
    a, b = spectrograms
    dot = sum(x * y for x, y in zip(a, b))
    return dot / math.sqrt(sum(x * x for x in a) * sum(y * y for y in b))


def _assert_call_opening_is_not_a_message(spec: CueSpec) -> None:
    """A call loop must be told apart from the message notification from its
    first strike, so no call loop may open with the message's bare YO."""
    message = next(cue for cue in CUES if cue.name == "notification")
    similarity = _opening_similarity(message, spec)
    assert similarity < CALL_OPENING_MAX_SIMILARITY, (spec.name, similarity)


def _render(spec: CueSpec) -> bytes:
    _assert_pentatonic(spec)
    _assert_designed_tails(spec)
    if spec.loop:
        _assert_call_opening_is_not_a_message(spec)
    left, right = _synthesise(spec)
    peak = max(max(abs(value) for value in left), max(abs(value) for value in right))
    rms = math.sqrt(
        sum(value * value for value in left + right) / (len(left) + len(right))
    )
    peak_db = _db(peak)
    rms_db = _db(rms)
    correlation = _correlation(left, right)
    mono = [(l + r) * 0.5 for l, r in zip(left, right)]
    side = [(l - r) * 0.5 for l, r in zip(left, right)]
    mono_rms = math.sqrt(sum(value * value for value in mono) / len(mono))
    side_rms = math.sqrt(sum(value * value for value in side) / len(side))
    average_channel_rms = math.sqrt(
        sum(l * l + r * r for l, r in zip(left, right)) / (2.0 * len(left))
    )
    mono_loss_db = _db(mono_rms / average_channel_rms)
    side_below_mid_db = _db(side_rms / mono_rms)
    dc = max(abs(sum(left) / len(left)), abs(sum(right) / len(right)))
    seconds = len(left) / RATE

    assert abs(rms_db - spec.loudness_db) <= 0.15, (spec.name, rms_db)
    assert peak_db <= spec.peak_ceiling_db + 0.05, (spec.name, peak_db)
    assert correlation >= 0.80, (spec.name, correlation)
    assert mono_loss_db >= -1.0, (spec.name, mono_loss_db)
    assert side_below_mid_db <= -14.0, (spec.name, side_below_mid_db)
    assert dc <= 10.0 ** (-60.0 / 20.0), (spec.name, dc)
    assert left[-TERMINAL_ZERO_FRAMES:] == [0.0] * TERMINAL_ZERO_FRAMES
    assert right[-TERMINAL_ZERO_FRAMES:] == [0.0] * TERMINAL_ZERO_FRAMES
    assert seconds < (MAX_LOOP_SECONDS if spec.loop else MAX_UI_SECONDS), (
        spec.name, seconds)
    if spec.loop:
        # Seamless loop: the last 250 ms before the seam are already silent, so
        # the seam is silence meeting a strike that starts from zero.
        tail = int(0.25 * RATE)
        tail_peak = max(abs(value) for value in left[-tail:] + right[-tail:])
        assert _db(tail_peak) <= -60.0, (spec.name, _db(tail_peak))

    # Deterministic triangular dither at half the textbook amplitude: two
    # uniform draws are averaged and scaled to +/-0.5 LSB peak, so the TPDF
    # is one LSB wide rather than the two LSB that make the quantisation
    # error's mean and power independent of the signal. It breaks up the
    # error pattern of sustained tones but only partly decorrelates it in the
    # quietest tails, which sit more than 60 dB under the peak; rests carry
    # at most sparse +/-1 LSB values. The explicit zero pad is kept
    # untouched, so it is the only guaranteed digital silence.
    dither = DeterministicNoise(spec.seed ^ 0xDEADBEEF)
    frames = bytearray()
    zero_from = len(left) - TERMINAL_ZERO_FRAMES
    energy = 0.0
    for index, (l_value, r_value) in enumerate(zip(left, right)):
        encoded = []
        for value in (l_value, r_value):
            if index >= zero_from:
                quantised = 0
            else:
                triangular = (dither.sample() + dither.sample()) * 0.5
                quantised = round(value * 32767.0 + triangular * 0.5)
                quantised = max(-32768, min(32767, quantised))
            energy += quantised * quantised
            encoded.append(quantised)
        frames += struct.pack("<hh", *encoded)
    delivered_db = _db(math.sqrt(energy / (2 * len(left))) / 32767.0)
    # The app's asset test allows 0.08 dB; keep a margin after dither.
    assert abs(delivered_db - spec.loudness_db) <= 0.05, (spec.name, delivered_db)

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
    """Return every UI WAV that is not one of the current versioned masters."""

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
        print("sound assets match Velvet Mallet v6 generator")
        return 0

    retired_assets = _unexpected_flutter_assets(root, targets)
    for path in retired_assets:
        path.unlink()
    # A retired pack leaves its version directory empty; do not keep it around.
    asset_root = root / "assets" / "audio" / "ui"
    for directory in sorted({path.parent for path in retired_assets}, reverse=True):
        if directory != asset_root and not any(directory.iterdir()):
            directory.rmdir()
    for path, data in targets.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    print(
        f"wrote {len(CUES)} versioned Velvet Mallet cues and native notification copies"
        f"; retired {len(retired_assets)} stale UI WAV(s)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
