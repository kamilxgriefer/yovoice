import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _sampleRate = 44100;

enum _Wave { sine, softTriangle, bell }

class _Tone {
  const _Tone({
    required this.start,
    required this.duration,
    required this.fromHz,
    this.toHz,
    this.gain = 1,
    this.release = 0.08,
    this.wave = _Wave.sine,
  });

  final double start;
  final double duration;
  final double fromHz;
  final double? toHz;
  final double gain;
  final double release;
  final _Wave wave;

  double sample(double time) {
    final local = time - start;
    if (local < 0 || local >= duration) return 0;
    final endHz = toHz ?? fromHz;
    final slope = (endHz - fromHz) / duration;
    final phase = 2 * math.pi * (fromHz * local + slope * local * local / 2);
    final amplitude =
        math.min(1, local / 0.012) * math.min(1, (duration - local) / release);
    final oscillator = switch (wave) {
      _Wave.sine => math.sin(phase),
      _Wave.softTriangle => math.sin(phase) + 0.18 * math.sin(phase * 3) / 3,
      _Wave.bell =>
        math.sin(phase) +
            0.28 * math.sin(phase * 2.01) +
            0.12 * math.sin(phase * 3.98),
    };
    return oscillator * amplitude * gain;
  }
}

class _Sound {
  const _Sound(this.name, this.duration, this.tones);

  final String name;
  final double duration;
  final List<_Tone> tones;
}

void main() {
  // These contours are original YO Voice cues. They are synthesized from
  // basic oscillators rather than sampled from another product or library.
  const sounds = <_Sound>[
    _Sound('room_created', 0.62, [
      _Tone(start: 0, duration: 0.30, fromHz: 392, gain: 0.42),
      _Tone(start: 0.10, duration: 0.32, fromHz: 523.25, gain: 0.52),
      _Tone(
        start: 0.22,
        duration: 0.38,
        fromHz: 783.99,
        gain: 0.55,
        wave: _Wave.bell,
      ),
      _Tone(
        start: 0.24,
        duration: 0.30,
        fromHz: 1174.66,
        gain: 0.12,
        wave: _Wave.bell,
      ),
    ]),
    _Sound('room_joined', 0.46, [
      _Tone(start: 0, duration: 0.29, fromHz: 440, toHz: 466, gain: 0.46),
      _Tone(
        start: 0.10,
        duration: 0.34,
        fromHz: 587.33,
        gain: 0.62,
        wave: _Wave.softTriangle,
      ),
      _Tone(
        start: 0.13,
        duration: 0.26,
        fromHz: 880,
        gain: 0.14,
        wave: _Wave.bell,
      ),
    ]),
    _Sound('room_left', 0.38, [
      _Tone(
        start: 0,
        duration: 0.24,
        fromHz: 587.33,
        gain: 0.50,
        wave: _Wave.softTriangle,
      ),
      _Tone(start: 0.10, duration: 0.27, fromHz: 440, toHz: 415.30, gain: 0.50),
    ]),
    _Sound('participant_joined', 0.27, [
      _Tone(start: 0, duration: 0.18, fromHz: 659.25, gain: 0.46),
      _Tone(
        start: 0.065,
        duration: 0.20,
        fromHz: 987.77,
        gain: 0.64,
        wave: _Wave.bell,
      ),
    ]),
    _Sound('participant_left', 0.27, [
      _Tone(
        start: 0,
        duration: 0.18,
        fromHz: 987.77,
        gain: 0.52,
        wave: _Wave.bell,
      ),
      _Tone(start: 0.065, duration: 0.20, fromHz: 659.25, gain: 0.55),
    ]),
    _Sound('microphone_muted', 0.20, [
      _Tone(
        start: 0,
        duration: 0.10,
        fromHz: 698.46,
        toHz: 622.25,
        gain: 0.58,
        release: 0.04,
      ),
      _Tone(
        start: 0.075,
        duration: 0.12,
        fromHz: 392,
        toHz: 349.23,
        gain: 0.62,
        release: 0.05,
      ),
    ]),
    _Sound('microphone_unmuted', 0.20, [
      _Tone(
        start: 0,
        duration: 0.10,
        fromHz: 349.23,
        toHz: 392,
        gain: 0.58,
        release: 0.04,
      ),
      _Tone(
        start: 0.075,
        duration: 0.12,
        fromHz: 622.25,
        toHz: 698.46,
        gain: 0.62,
        release: 0.05,
      ),
    ]),
    _Sound('notification', 0.50, [
      _Tone(
        start: 0,
        duration: 0.30,
        fromHz: 880,
        gain: 0.48,
        wave: _Wave.bell,
      ),
      _Tone(
        start: 0.11,
        duration: 0.37,
        fromHz: 1318.51,
        gain: 0.55,
        wave: _Wave.bell,
      ),
      _Tone(
        start: 0.13,
        duration: 0.28,
        fromHz: 1975.53,
        gain: 0.10,
        wave: _Wave.bell,
      ),
    ]),
  ];

  final assetDirectory = Directory('assets/audio/ui')
    ..createSync(recursive: true);
  for (final sound in sounds) {
    final bytes = _render(sound);
    File('${assetDirectory.path}/${sound.name}.wav').writeAsBytesSync(bytes);
    if (sound.name == 'notification') {
      final android = File(
        'android/app/src/main/res/raw/yovoice_notification.wav',
      )..parent.createSync(recursive: true);
      android.writeAsBytesSync(bytes);
      File('ios/Runner/yovoice_notification.wav').writeAsBytesSync(bytes);
    }
  }
}

Uint8List _render(_Sound sound) {
  final frameCount = (sound.duration * _sampleRate).ceil();
  final raw = Float64List(frameCount);
  var peak = 0.0;
  for (var index = 0; index < frameCount; index++) {
    final time = index / _sampleRate;
    var value = 0.0;
    for (final tone in sound.tones) {
      value += tone.sample(time);
    }
    // A quiet, rounded master fade prevents clicks at both ends.
    final master =
        math.min(1, time / 0.008) *
        math.min(1, (sound.duration - time) / 0.025);
    raw[index] = value * master;
    peak = math.max(peak, raw[index].abs());
  }

  final scale = peak == 0 ? 0.0 : 0.72 / peak;
  final dataSize = frameCount * 2;
  final bytes = ByteData(44 + dataSize);
  _ascii(bytes, 0, 'RIFF');
  bytes.setUint32(4, 36 + dataSize, Endian.little);
  _ascii(bytes, 8, 'WAVE');
  _ascii(bytes, 12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, _sampleRate, Endian.little);
  bytes.setUint32(28, _sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  _ascii(bytes, 36, 'data');
  bytes.setUint32(40, dataSize, Endian.little);
  for (var index = 0; index < frameCount; index++) {
    final sample = (raw[index] * scale * 32767).round().clamp(-32768, 32767);
    bytes.setInt16(44 + index * 2, sample, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

void _ascii(ByteData bytes, int offset, String text) {
  for (var index = 0; index < text.length; index++) {
    bytes.setUint8(offset + index, text.codeUnitAt(index));
  }
}
