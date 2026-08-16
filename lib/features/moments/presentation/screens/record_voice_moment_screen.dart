import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:record/record.dart' show Amplitude;

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';

/// The states this screen can actually be in.
///
/// [unavailable] exists because the honest answer on some platforms is
/// "not here" — the web build cannot record in a browser with no MP4/AAC
/// encoder, and the previous version hid that behind a generic
/// "Could not start recording" snackbar for every web user.
enum VoiceMomentRecordingPhase {
  checkingSupport,
  unavailable,
  idle,
  requestingAccess,
  recording,
  reviewing,
  publishing,
}

/// Records and publishes a Voice Moment.
///
/// One implementation for web and native: the state machine, the service
/// calls and the upload contract are shared, and only how bytes are
/// captured and uploaded differs (see `AudioCapture`).
class RecordVoiceMomentScreen extends StatefulWidget {
  const RecordVoiceMomentScreen({
    this.replyToMomentId,
    this.replyToAuthorName,
    this.recorder,
    this.momentService,
    super.key,
  });

  final String? replyToMomentId;
  final String? replyToAuthorName;

  /// Injected by tests so every phase can be driven without hardware.
  final VoiceMomentRecorder? recorder;
  final MomentService? momentService;

  @override
  State<RecordVoiceMomentScreen> createState() =>
      _RecordVoiceMomentScreenState();
}

class _RecordVoiceMomentScreenState extends State<RecordVoiceMomentScreen> {
  static const Color _background = Color(0xFF080711);
  static const Color _surface = Color(0xFF151020);
  static const Color _border = Color(0xFF382A47);
  static const Color _muted = Color(0xFF9D95AD);
  static const Color _primary = Color(0xFF9D20FF);
  static const Color _danger = Color(0xFFFF416C);

  static const int _maxSeconds = 60;
  static const int _meterBarCount = 27;
  static const int _compactMeterBarCount = 19;

  late final VoiceMomentRecorder _recorder;
  MomentService? _momentService;
  final TextEditingController _captionController = TextEditingController();

  VoiceMomentRecordingPhase _phase = VoiceMomentRecordingPhase.checkingSupport;

  /// Why this platform cannot record, when [_phase] is `unavailable`.
  CaptureSupport? _unsupported;

  /// A recoverable problem shown inline. Never a bare exception string.
  VoiceRecordingException? _notice;

  Timer? _ticker;
  StreamSubscription<Amplitude>? _levels;
  final List<double> _meter = List<double>.filled(_meterBarCount, 0);

  RecordedAudio? _recording;

  @override
  void initState() {
    super.initState();
    _recorder = widget.recorder ?? VoiceMomentRecorder();
    unawaited(_resolveSupport());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_levels?.cancel());
    _captionController.dispose();
    unawaited(_recording?.discard());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  MomentService get _moments => _momentService ??= (widget.momentService ??
      MomentService());

  bool get _isReply => widget.replyToMomentId != null;

  Future<void> _resolveSupport() async {
    final support = await _recorder.checkSupport();
    if (!mounted) return;
    setState(() {
      if (support.isSupported) {
        _phase = VoiceMomentRecordingPhase.idle;
      } else {
        _phase = VoiceMomentRecordingPhase.unavailable;
        _unsupported = support;
      }
    });
  }

  // ---------------------------------------------------------------- capture

  Future<void> _toggleRecording() async {
    if (_phase == VoiceMomentRecordingPhase.recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (_phase != VoiceMomentRecordingPhase.idle &&
        _phase != VoiceMomentRecordingPhase.reviewing) {
      return;
    }

    await _discardRecording();
    if (!mounted) return;
    setState(() {
      _notice = null;
      _phase = VoiceMomentRecordingPhase.requestingAccess;
    });

    try {
      await _recorder.start();
    } on VoiceRecordingException catch (error) {
      if (!mounted) return;
      setState(() {
        // A platform that cannot record at all is terminal for this
        // session; a blocked microphone or a failed start is not, so the
        // user lands back on a screen they can retry from.
        if (error.problem == VoiceRecordingProblem.platformCannotRecord) {
          _phase = VoiceMomentRecordingPhase.unavailable;
          _unsupported = CaptureSupport.unsupported(
            reason: error.message,
            action: error.action,
          );
        } else {
          _phase = VoiceMomentRecordingPhase.idle;
          _notice = error;
        }
      });
      return;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = VoiceMomentRecordingPhase.idle;
        _notice = VoiceRecordingException(
          VoiceRecordingProblem.captureFailed,
          intentionalOrFriendly(
            error,
            fallback: 'Recording could not be started.',
          ),
          action: 'Try again.',
          cause: error,
        );
      });
      return;
    }

    if (!mounted) {
      await _recorder.cancel();
      return;
    }

    _meter.fillRange(0, _meter.length, 0);
    setState(() => _phase = VoiceMomentRecordingPhase.recording);

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      if (_recorder.elapsed.inSeconds >= _maxSeconds) {
        unawaited(_stopRecording());
        return;
      }
      setState(() {});
    });

    unawaited(_levels?.cancel());
    _levels = _recorder.amplitudes().listen(
      (amplitude) {
        if (!mounted) return;
        final level = VoiceMomentRecorder.normalizeAmplitude(amplitude.current);
        setState(() {
          for (var i = 0; i < _meter.length - 1; i++) {
            _meter[i] = _meter[i + 1];
          }
          _meter[_meter.length - 1] = level;
        });
      },
      // A meter that stops updating is a cosmetic loss; it must not take
      // the recording down with it.
      onError: (_) {},
    );
  }

  Future<void> _stopRecording() async {
    if (_phase != VoiceMomentRecordingPhase.recording) return;

    _ticker?.cancel();
    unawaited(_levels?.cancel());
    _levels = null;

    final captured = _recorder.elapsed;

    RecordedAudio audio;
    try {
      audio = await _recorder.stop();
    } on VoiceRecordingException catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = VoiceMomentRecordingPhase.idle;
        _notice = error;
      });
      return;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = VoiceMomentRecordingPhase.idle;
        _notice = VoiceRecordingException(
          VoiceRecordingProblem.captureFailed,
          intentionalOrFriendly(
            error,
            fallback: 'Recording could not be finished.',
          ),
          action: 'Record again.',
          cause: error,
        );
      });
      return;
    }

    // The callables reject anything under a second, so refuse it here where
    // the reason can still be explained rather than after an upload.
    if (captured.inMilliseconds < 1000) {
      await audio.discard();
      if (!mounted) return;
      setState(() {
        _phase = VoiceMomentRecordingPhase.idle;
        _notice = const VoiceRecordingException(
          VoiceRecordingProblem.recordingUnusable,
          'That was too short to publish — a Voice Moment needs at least '
          'one second.',
          action: 'Hold on a little longer this time.',
        );
      });
      return;
    }

    if (!mounted) {
      await audio.discard();
      return;
    }
    setState(() {
      _recording = audio;
      _phase = VoiceMomentRecordingPhase.reviewing;
    });
  }

  Future<void> _discardRecording() async {
    final existing = _recording;
    _recording = null;
    if (existing != null) await existing.discard();
  }

  Future<void> _recordAgain() async {
    await _discardRecording();
    if (!mounted) return;
    _meter.fillRange(0, _meter.length, 0);
    setState(() {
      _notice = null;
      _phase = VoiceMomentRecordingPhase.idle;
    });
  }

  // ---------------------------------------------------------------- publish

  Future<void> _publish() async {
    final audio = _recording;
    if (audio == null || _phase != VoiceMomentRecordingPhase.reviewing) return;

    setState(() {
      _notice = null;
      _phase = VoiceMomentRecordingPhase.publishing;
    });

    try {
      await _moments.publishRecordedMoment(
        audio: audio,
        durationSeconds: _durationSeconds,
        caption: _captionController.text,
        replyToMomentId: widget.replyToMomentId,
      );
    } catch (error) {
      if (!mounted) return;
      // The recording is kept: the capture succeeded, only publishing
      // failed, and making the user re-record would lose good audio.
      setState(() {
        _phase = VoiceMomentRecordingPhase.reviewing;
        _notice = VoiceRecordingException(
          VoiceRecordingProblem.uploadFailed,
          intentionalOrFriendly(
            error,
            fallback: 'Your Voice Moment could not be published.',
          ),
          action: 'Your recording is still here — try publishing again.',
          cause: error,
        );
      });
      return;
    }

    await _discardRecording();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  int get _durationSeconds => _recorder.durationSeconds;

  String get _timeLabel {
    final seconds = _phase == VoiceMomentRecordingPhase.recording
        ? math.min(_recorder.elapsed.inSeconds, _maxSeconds)
        : (_recording == null ? 0 : _durationSeconds);
    return '0:${seconds.toString().padLeft(2, '0')} / 1:00';
  }

  // ------------------------------------------------------------------- view

  @override
  Widget build(BuildContext context) {
    final busy = _phase == VoiceMomentRecordingPhase.publishing;

    return PopScope(
      // Leaving mid-upload would orphan a reserved draft.
      canPop: !busy,
      child: Scaffold(
        backgroundColor: _background,
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.8),
              radius: 1.1,
              colors: [Color(0xFF31104D), Color(0xFF120B1B), _background],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _header(busy),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      if (width >= 1024) return _wideBody(width);
                      return _stackedBody(width);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(bool busy) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            tooltip: 'Back',
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
            ),
          ),
          const Expanded(
            child: Text(
              'Record Voice Moment',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  /// Phone and tablet: one column, the card centred at a readable measure.
  Widget _stackedBody(double width) {
    final compact = width < 600;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(compact ? 16 : 22, 26, compact ? 16 : 22, 30),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _intro(),
                const SizedBox(height: 26),
                ..._stage(compact: compact, stackActions: compact),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Desktop: the capture stage and the publishing controls sit side by
  /// side, so a wide window is a two-column workspace rather than a phone
  /// column stretched across 1400 px.
  Widget _wideBody(double width) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 30, 32, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: _card(
            padding: const EdgeInsets.fromLTRB(34, 32, 34, 30),
            child: switch (_phase) {
              VoiceMomentRecordingPhase.checkingSupport ||
              VoiceMomentRecordingPhase.unavailable => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _intro(),
                  const SizedBox(height: 26),
                  ..._stage(compact: false, stackActions: false),
                ],
              ),
              _ => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _intro(alignment: TextAlign.left),
                        const SizedBox(height: 28),
                        _meterBlock(compact: false),
                        const SizedBox(height: 20),
                        _recordButton(),
                        const SizedBox(height: 16),
                        _statusLine(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 34),
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_notice != null) ...[
                          _noticeCard(_notice!),
                          const SizedBox(height: 18),
                        ],
                        _sidePanel(),
                      ],
                    ),
                  ),
                ],
              ),
            },
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _border),
      ),
      child: child,
    );
  }

  Widget _intro({TextAlign alignment = TextAlign.center}) {
    final title = _isReply
        ? "Reply to ${widget.replyToAuthorName ?? 'this moment'}"
        : 'Share your voice';
    final subtitle = _isReply
        ? 'Record a voice reply up to 60 seconds long.'
        : 'Record between 1 and 60 seconds and publish it directly to your '
              'feed.';

    return Column(
      crossAxisAlignment: alignment == TextAlign.left
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          title,
          textAlign: alignment,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: alignment,
          style: const TextStyle(color: _muted, fontSize: 14, height: 1.4),
        ),
      ],
    );
  }

  /// The stacked (phone/tablet) arrangement of whatever the current phase
  /// needs to show.
  List<Widget> _stage({required bool compact, required bool stackActions}) {
    switch (_phase) {
      case VoiceMomentRecordingPhase.checkingSupport:
        return [_checkingCard()];
      case VoiceMomentRecordingPhase.unavailable:
        return [_unavailableCard()];
      default:
        return [
          if (_notice != null) ...[_noticeCard(_notice!), const SizedBox(height: 20)],
          _meterBlock(compact: compact),
          const SizedBox(height: 22),
          _recordButton(),
          const SizedBox(height: 14),
          _statusLine(),
          if (_phase == VoiceMomentRecordingPhase.reviewing ||
              _phase == VoiceMomentRecordingPhase.publishing) ...[
            const SizedBox(height: 24),
            _captionField(),
            const SizedBox(height: 12),
            _actions(stacked: stackActions),
          ],
        ];
    }
  }

  /// The desktop right-hand column.
  Widget _sidePanel() {
    if (_phase == VoiceMomentRecordingPhase.reviewing ||
        _phase == VoiceMomentRecordingPhase.publishing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _captionField(),
          const SizedBox(height: 12),
          _actions(stacked: false),
        ],
      );
    }
    return _guidanceCard();
  }

  Widget _checkingCard() {
    return Semantics(
      liveRegion: true,
      child: Column(
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: _primary),
          ),
          const SizedBox(height: 16),
          Text(
            'Checking whether this device can record…',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 13.5),
          ),
        ],
      ),
    );
  }

  /// The honest unavailable state.
  ///
  /// Follows the `premium_upsell_sheet` convention — a real explanation and
  /// a real next step, never a generic "Coming soon" and never a dead
  /// button that fails when tapped.
  Widget _unavailableCard() {
    final support = _unsupported;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0914),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFB547).withValues(alpha: .12),
              border: Border.all(
                color: const Color(0xFFFFB547).withValues(alpha: .4),
              ),
            ),
            child: const Icon(
              Icons.mic_off_rounded,
              color: Color(0xFFFFD08A),
              size: 28,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Recording is not available here',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            support?.reason ??
                'YO Voice could not reach an audio recorder on this device.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 13.5, height: 1.5),
          ),
          if (support?.action != null) ...[
            const SizedBox(height: 12),
            Text(
              support!.action!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFD8CFEA),
                fontSize: 13.5,
                height: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: _border),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Go back'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noticeCard(VoiceRecordingException notice) {
    final blocked = notice.problem == VoiceRecordingProblem.microphoneBlocked;
    final accent = blocked ? const Color(0xFFFFB547) : _danger;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: .45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              blocked ? Icons.mic_off_rounded : Icons.error_outline_rounded,
              color: accent,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notice.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (notice.action != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      notice.action!,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _guidanceCard() {
    const points = <(IconData, String)>[
      (Icons.timer_outlined, 'Between 1 and 60 seconds.'),
      (Icons.headphones_outlined, 'Somewhere quiet records best.'),
      (Icons.public_outlined, 'Published straight to your feed.'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0914),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Before you start',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          for (final (icon, label) in points) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 17, color: _muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
            if (label != points.last.$2) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _meterBlock({required bool compact}) {
    return Column(
      children: [
        SizedBox(
          height: compact ? 92 : 110,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final barCount = constraints.maxWidth < 330
                  ? _compactMeterBarCount
                  : _meterBarCount;
              return _LevelMeter(
                levels: _meter,
                barCount: barCount,
                live: _phase == VoiceMomentRecordingPhase.recording,
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _timeLabel,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _recordButton() {
    final recording = _phase == VoiceMomentRecordingPhase.recording;
    final requesting = _phase == VoiceMomentRecordingPhase.requestingAccess;
    final enabled =
        _phase == VoiceMomentRecordingPhase.idle ||
        _phase == VoiceMomentRecordingPhase.reviewing ||
        recording;

    final color = recording ? _danger : _primary;

    return Center(
      child: Semantics(
        button: true,
        enabled: enabled,
        label: recording
            ? 'Stop recording'
            : (_phase == VoiceMomentRecordingPhase.reviewing
                  ? 'Record again'
                  : 'Start recording'),
        child: InkWell(
          onTap: enabled ? _toggleRecording : null,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled || requesting
                  ? color
                  : color.withValues(alpha: .35),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: enabled ? .42 : .12),
                  blurRadius: 28,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: requesting
                ? const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    ),
                  )
                : Icon(
                    recording ? Icons.stop_rounded : Icons.mic_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _statusLine() {
    final text = switch (_phase) {
      VoiceMomentRecordingPhase.requestingAccess =>
        'Waiting for microphone access…',
      VoiceMomentRecordingPhase.recording => 'Recording — tap to stop.',
      VoiceMomentRecordingPhase.reviewing =>
        'Add a caption, then publish — or record again.',
      VoiceMomentRecordingPhase.publishing => 'Publishing your Voice Moment…',
      _ => 'Tap the microphone to start.',
    };
    return Semantics(
      liveRegion: true,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: _muted, fontSize: 13),
      ),
    );
  }

  Widget _captionField() {
    return TextField(
      controller: _captionController,
      enabled: _phase != VoiceMomentRecordingPhase.publishing,
      maxLength: 140,
      maxLines: 3,
      minLines: 3,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Add a caption…',
        hintStyle: const TextStyle(color: _muted),
        counterStyle: const TextStyle(color: _muted),
        filled: true,
        fillColor: const Color(0xFF0D0914),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _actions({required bool stacked}) {
    final publishing = _phase == VoiceMomentRecordingPhase.publishing;

    final again = OutlinedButton.icon(
      onPressed: publishing ? null : _recordAgain,
      icon: const Icon(Icons.refresh_rounded),
      label: const Text('Record again', overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: _border),
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );

    final publish = FilledButton.icon(
      onPressed: publishing ? null : _publish,
      icon: publishing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.publish_rounded),
      label: Text(
        publishing
            ? 'Publishing…'
            : (_notice?.problem == VoiceRecordingProblem.uploadFailed
                  ? 'Try again'
                  : 'Publish'),
        overflow: TextOverflow.ellipsis,
      ),
      style: FilledButton.styleFrom(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _primary.withValues(alpha: .5),
        disabledForegroundColor: Colors.white70,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );

    // Narrow widths stack the actions: side by side, the two labels wrap or
    // clip once the text grows (translation, large text settings).
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [publish, const SizedBox(height: 10), again],
      );
    }
    return Row(
      children: [
        Expanded(child: again),
        const SizedBox(width: 12),
        Expanded(child: publish),
      ],
    );
  }
}

/// Draws the measured input level. Every bar is a real sample from the
/// recorder's amplitude stream — nothing here animates on its own.
class _LevelMeter extends StatelessWidget {
  const _LevelMeter({
    required this.levels,
    required this.barCount,
    required this.live,
  });

  final List<double> levels;
  final int barCount;
  final bool live;

  static const double _restHeight = 6;
  static const double _maxHeight = 96;

  @override
  Widget build(BuildContext context) {
    // Show the most recent [barCount] samples, oldest on the left.
    final start = math.max(0, levels.length - barCount);
    final visible = levels.sublist(start);

    return Semantics(
      label: live ? 'Recording level meter' : 'Recording level meter, idle',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List<Widget>.generate(barCount, (index) {
          final level = index < visible.length ? visible[index] : 0.0;
          final height = _restHeight + (level * (_maxHeight - _restHeight));
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  width: 5,
                  height: height,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: live
                          ? const [Color(0xFF6A00FF), Color(0xFFC53AFF)]
                          : [
                              const Color(0xFF6A00FF).withValues(alpha: .35),
                              const Color(0xFFC53AFF).withValues(alpha: .35),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
