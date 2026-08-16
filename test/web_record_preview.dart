// A harness entry point for verifying the real RecordVoiceMomentScreen in a
// browser without a Firebase session.
//
//   flutter build web -t test/web_record_preview.dart --output build/record_preview
//
// With no `?state=` it mounts the production screen with the production
// VoiceMomentRecorder, so the web capture path (`audio_capture_web.dart`)
// is genuinely exercised: secure-context and MediaRecorder support
// probing, the microphone prompt, and reading the blob back.
//
// `?state=` mounts the same production screen with the capture half faked,
// so the states that need hardware or a signed-in user can still be looked
// at: unsupported, review, publishing, failed.
//
// Self-contained doubles on purpose — the shared ones in
// voice_moment_test_doubles.dart pull in firebase_storage_mocks, which
// imports dart:io and cannot be compiled for the web.
import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart' show Amplitude, AudioEncoder, RecordConfig;
import 'package:web/web.dart' as web;

import 'package:yovoice/features/moments/data/services/audio_capture/audio_capture.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';

void main() {
  final state = Uri.parse(
    web.window.location.href,
  ).queryParameters['state'];
  runApp(_RecordPreviewApp(state: state));
}

class _RecordPreviewApp extends StatelessWidget {
  const _RecordPreviewApp({this.state});

  final String? state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Voice Moment recording preview',
      theme: ThemeData.dark(useMaterial3: true),
      home: _Preview(state: state),
    );
  }
}

class _Preview extends StatefulWidget {
  const _Preview({this.state});

  final String? state;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  @override
  Widget build(BuildContext context) {
    switch (widget.state) {
      case 'unsupported':
        return RecordVoiceMomentScreen(
          recorder: VoiceMomentRecorder(
            backend: _PreviewBackend(),
            capture: _PreviewCapture(
              support: const CaptureSupport.unsupported(
                reason:
                    'This browser cannot record MP4/AAC audio, which is the '
                    'only format YO Voice can publish a Voice Moment in.',
                action: 'Open YO Voice in Chrome, Edge or Safari to record.',
              ),
            ),
          ),
          momentService: _PreviewMomentService(),
        );
      case 'review':
      case 'publishing':
      case 'failed':
        return _ScriptedCapture(state: widget.state!);
      default:
        return const RecordVoiceMomentScreen();
    }
  }
}

/// Drives a real capture through the fake backend so the reviewing,
/// publishing and failed states can be inspected at every width.
class _ScriptedCapture extends StatefulWidget {
  const _ScriptedCapture({required this.state});

  final String state;

  @override
  State<_ScriptedCapture> createState() => _ScriptedCaptureState();
}

class _ScriptedCaptureState extends State<_ScriptedCapture> {
  late final _PreviewClock clock = _PreviewClock();
  late final VoiceMomentRecorder recorder = VoiceMomentRecorder(
    backend: _PreviewBackend(),
    capture: _PreviewCapture(),
    clock: clock,
  );
  late final _PreviewMomentService service = _PreviewMomentService(
    gate: widget.state == 'publishing' ? Completer<void>() : null,
    failure: widget.state == 'failed'
        ? StateError(
            'Your Voice Moment could not be uploaded. The connection dropped '
            'partway through the upload.',
          )
        : null,
  );

  final GlobalKey _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    clock.value = const Duration(seconds: 12);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _run() async {
    // Let the screen resolve support, then walk it to the target state
    // through its real controls.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final context = _key.currentContext;
    if (context == null) return;
    await _tap(Icons.mic_rounded);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await _tap(Icons.stop_rounded);
    if (widget.state == 'review') return;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await _tap(Icons.publish_rounded);
  }

  Future<void> _tap(IconData icon) async {
    final element = _findByIcon(_key.currentContext! as Element, icon);
    if (element == null) return;
    final renderObject = element.renderObject;
    if (renderObject is! RenderBox) return;
    final centre = renderObject.localToGlobal(renderObject.size.center(
      Offset.zero,
    ));
    WidgetsBinding.instance.handlePointerEvent(
      PointerDownEvent(position: centre),
    );
    WidgetsBinding.instance.handlePointerEvent(PointerUpEvent(position: centre));
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  Element? _findByIcon(Element root, IconData icon) {
    Element? found;
    void visit(Element element) {
      if (found != null) return;
      final widget = element.widget;
      if (widget is Icon && widget.icon == icon) {
        found = element;
        return;
      }
      element.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  @override
  Widget build(BuildContext context) {
    return RecordVoiceMomentScreen(
      key: _key,
      recorder: recorder,
      momentService: service,
    );
  }
}

class _PreviewClock implements Stopwatch {
  Duration value = Duration.zero;
  bool _running = false;

  @override
  Duration get elapsed => value;
  @override
  bool get isRunning => _running;
  @override
  void start() => _running = true;
  @override
  void stop() => _running = false;
  @override
  void reset() {}
  @override
  int get frequency => 1000000;
  @override
  int get elapsedTicks => value.inMicroseconds;
  @override
  int get elapsedMicroseconds => value.inMicroseconds;
  @override
  int get elapsedMilliseconds => value.inMilliseconds;
}

class _PreviewBackend implements VoiceRecorderBackend {
  final StreamController<Amplitude> _amplitudes =
      StreamController<Amplitude>.broadcast();

  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<bool> isEncoderSupported(AudioEncoder encoder) async => true;
  @override
  Future<void> start(RecordConfig config, {required String path}) async {}
  @override
  Stream<Amplitude> onAmplitudeChanged(Duration interval) =>
      _amplitudes.stream;
  @override
  Future<String?> stop() async => 'preview-handle';
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async => _amplitudes.close();
}

class _PreviewCapture implements AudioCapture {
  _PreviewCapture({this.support = const CaptureSupport.supported()});

  final CaptureSupport support;

  @override
  Future<CaptureSupport> probeSupport(VoiceRecorderBackend backend) async =>
      support;
  @override
  Future<String> newRecordingTarget() async => 'preview.m4a';
  @override
  Future<RecordedAudio> materialize(String? stopResult) async =>
      _PreviewAudio();
}

class _PreviewAudio extends RecordedAudio {
  @override
  String get contentType => kVoiceMomentContentType;
  @override
  int get byteLength => 196608;
  @override
  Future<String> uploadTo(Reference reference, SettableMetadata metadata) async
      => '1';
  @override
  Future<void> discard() async {}
}

class _PreviewMomentService implements MomentService {
  _PreviewMomentService({this.gate, this.failure});

  final Completer<void>? gate;
  final Object? failure;

  @override
  Future<String> publishRecordedMoment({
    required RecordedAudio audio,
    required int durationSeconds,
    required String caption,
    String? replyToMomentId,
  }) async {
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return 'preview-moment';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
