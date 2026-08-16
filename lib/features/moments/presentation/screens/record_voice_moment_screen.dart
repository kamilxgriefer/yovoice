import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:record/record.dart' show Amplitude;

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';

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
  // Every colour on this screen resolves from AppColors, the project's
  // single source of truth for the palette. The file previously defined
  // its own purple (0xFF9D20FF), visibly different from the AppColors
  // purple used by moments_screen.dart directly beside it. Local names are
  // kept for readability; none of them is a raw hex value.
  static const Color _background = AppColors.background;
  static const Color _surface = AppColors.surface;
  static const Color _inset = AppColors.background;
  static const Color _border = AppColors.border;
  static const Color _muted = AppColors.textSecondary;
  static const Color _primary = AppColors.primary;

  /// The cosmic backdrop's top stop, shared with [AppGradients.background].
  static const Color _skyTop = Color(0xFF130A22);

  /// Recording is a live state, not an error state.
  static const Color _live = AppColors.live;
  static const Color _error = AppColors.error;
  static const Color _warning = AppColors.warning;

  static const int _maxSeconds = 60;
  static const int _meterBarCount = 27;
  static const int _compactMeterBarCount = 19;
  static const int _captionMaxLength = 140;

  /// Coarse level names for the meter's semantics value. Coarse on
  /// purpose: a precise dB figure re-read every sample is unusable.
  static const String _meterSilent = 'Silent';
  static const String _meterQuiet = 'Quiet';
  static const String _meterGood = 'Good level';
  static const String _meterUnknown = 'Input level unavailable';

  /// The amplitude stream samples about eight times a second. Publishing a
  /// new semantics value that often would flood the announcement queue.
  static const Duration _meterValueInterval = Duration(seconds: 1);

  /// How long a completely silent input runs before it is called out. A
  /// dead or muted microphone is otherwise indistinguishable from a quiet
  /// room for someone who cannot see the meter.
  static const Duration _silenceWarningAfter = Duration(seconds: 3);

  /// One warning near the limit, in place of a live-region clock.
  static const int _limitWarningAtSeconds = 50;

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

  /// Keeps the primary action reachable: a null `onPressed` drops focus to
  /// the route scope, which is how the retry became unreachable after a
  /// failed publish.
  final FocusNode _publishFocus = FocusNode(debugLabel: 'Publish Voice Moment');
  final GlobalKey _publishKey = GlobalKey();

  String _meterValue = _meterSilent;
  Duration _meterValueAt = Duration.zero;
  Duration? _silentSince;
  bool _silenceAnnounced = false;

  /// Silence has lasted long enough to show a visible hint. Without it the
  /// meter at -160 dBFS is pixel-identical to the idle state.
  bool _silenceDetected = false;
  bool _limitWarned = false;

  /// Identifies the in-flight microphone request, so a cancelled one can
  /// be ignored when it finally resolves.
  int _accessAttempt = 0;
  bool _captionLimitAnnounced = false;

  @override
  void initState() {
    super.initState();
    _recorder = widget.recorder ?? VoiceMomentRecorder();
    _captionController.addListener(_onCaptionChanged);
    unawaited(_resolveSupport());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_levels?.cancel());
    _publishFocus.dispose();
    _captionController
      ..removeListener(_onCaptionChanged)
      ..dispose();
    unawaited(_recording?.discard());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  MomentService get _moments => _momentService ??= (widget.momentService ??
      MomentService());

  bool get _isReply => widget.replyToMomentId != null;

  /// Speaks [message] on the assertive channel.
  ///
  /// Flutter web does not put `aria-live` on semantics nodes: every polite
  /// live region writes into one shared `flt-announcement-polite` element,
  /// so two polite updates in the same frame overwrite each other. The
  /// assertive channel is a separate element, which is why errors travel
  /// this way instead of via a second live region.
  void _announce(String message, {bool assertive = true}) {
    final text = message.trim();
    if (!mounted || text.isEmpty) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      text,
      Directionality.of(context),
      assertiveness: assertive
          ? Assertiveness.assertive
          : Assertiveness.polite,
    );
  }

  /// The single path by which a recoverable problem reaches the user, so
  /// the announcement can never be forgotten at one of the call sites.
  void _showNotice(
    VoiceRecordingException notice, {
    required VoiceMomentRecordingPhase phase,
  }) {
    setState(() {
      _phase = phase;
      _notice = notice;
    });
    _announce('${notice.message} ${notice.action ?? ''}');
  }

  void _onCaptionChanged() {
    if (!mounted) return;
    final length = _captionController.text.length;
    if (length >= _captionMaxLength) {
      if (!_captionLimitAnnounced) {
        _captionLimitAnnounced = true;
        // Input is silently dropped past the limit otherwise.
        _announce('Caption limit reached: $_captionMaxLength characters.');
      }
    } else {
      _captionLimitAnnounced = false;
    }
    // Refreshes the field's semantic counter text.
    setState(() {});
  }

  String _meterValueFor(double level) {
    if (level <= 0) return _meterSilent;
    if (level < 0.25) return _meterQuiet;
    return _meterGood;
  }

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
    final attempt = ++_accessAttempt;
    setState(() {
      _notice = null;
      _silenceDetected = false;
      _phase = VoiceMomentRecordingPhase.requestingAccess;
    });

    try {
      await _recorder.start();
    } on VoiceRecordingException catch (error) {
      if (!mounted || attempt != _accessAttempt) return;
      // A platform that cannot record at all is terminal for this session;
      // a refused microphone, absent hardware or a failed start is not, so
      // the user lands back on a screen they can retry from.
      if (error.problem == VoiceRecordingProblem.platformCannotRecord) {
        setState(() {
          _phase = VoiceMomentRecordingPhase.unavailable;
          _unsupported = CaptureSupport.unsupported(
            reason: error.message,
            action: error.action,
          );
        });
        _announce('${error.message} ${error.action ?? ''}');
      } else {
        _showNotice(error, phase: VoiceMomentRecordingPhase.idle);
      }
      return;
    } catch (error) {
      if (!mounted || attempt != _accessAttempt) return;
      _showNotice(
        VoiceRecordingException(
          VoiceRecordingProblem.captureFailed,
          intentionalOrFriendly(
            error,
            fallback: 'Recording could not be started.',
          ),
          action: 'Try again.',
          cause: error,
        ),
        phase: VoiceMomentRecordingPhase.idle,
      );
      return;
    }

    // The user gave up on the prompt while it was open, or left.
    if (!mounted || attempt != _accessAttempt) {
      await _recorder.cancel();
      return;
    }

    _meter.fillRange(0, _meter.length, 0);
    _meterValue = _meterSilent;
    _meterValueAt = Duration.zero;
    _silentSince = null;
    _silenceAnnounced = false;
    _silenceDetected = false;
    _limitWarned = false;
    setState(() => _phase = VoiceMomentRecordingPhase.recording);

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      final elapsed = _recorder.elapsed;
      if (elapsed.inSeconds >= _maxSeconds) {
        unawaited(_stopRecording());
        return;
      }
      // The clock is deliberately not a live region — at 200 ms it would
      // flood the queue — so the limit gets one spoken warning instead.
      if (!_limitWarned && elapsed.inSeconds >= _limitWarningAtSeconds) {
        _limitWarned = true;
        _announce('Ten seconds left.');
      }
      setState(() {});
    });

    unawaited(_levels?.cancel());
    _levels = _recorder.amplitudes().listen(
      (amplitude) {
        if (!mounted) return;
        final level = VoiceMomentRecorder.normalizeAmplitude(amplitude.current);
        final now = _recorder.elapsed;

        if (level <= 0) {
          _silentSince ??= now;
          if (now - _silentSince! >= _silenceWarningAfter) {
            _silenceDetected = true;
            if (!_silenceAnnounced) {
              _silenceAnnounced = true;
              _announce(
                'No sound is reaching the microphone. Check that the right '
                'microphone is selected and not muted.',
              );
            }
          }
        } else {
          _silentSince = null;
          _silenceDetected = false;
        }

        setState(() {
          for (var i = 0; i < _meter.length - 1; i++) {
            _meter[i] = _meter[i + 1];
          }
          _meter[_meter.length - 1] = level;
          if (now - _meterValueAt >= _meterValueInterval) {
            _meterValueAt = now;
            _meterValue = _meterValueFor(level);
          }
        });
      },
      // Losing the level stream does not stop the recording, but it does
      // mean the meter can no longer tell silence from sound. Saying so is
      // the honest answer; flat bars would read as silence.
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _meterValue = _meterUnknown;
          _silenceDetected = false;
        });
        if (!_silenceAnnounced) {
          _silenceAnnounced = true;
          _announce(
            'Microphone level is unavailable, so YO Voice cannot tell you '
            'whether sound is being picked up. Recording continues.',
          );
        }
      },
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
      _showNotice(error, phase: VoiceMomentRecordingPhase.idle);
      return;
    } catch (error) {
      if (!mounted) return;
      _showNotice(
        VoiceRecordingException(
          VoiceRecordingProblem.captureFailed,
          intentionalOrFriendly(
            error,
            fallback: 'Recording could not be finished.',
          ),
          action: 'Record again.',
          cause: error,
        ),
        phase: VoiceMomentRecordingPhase.idle,
      );
      return;
    }

    // The callables reject anything under a second, so refuse it here where
    // the reason can still be explained rather than after an upload.
    if (captured.inMilliseconds < 1000) {
      await audio.discard();
      if (!mounted) return;
      _showNotice(
        const VoiceRecordingException(
          VoiceRecordingProblem.recordingUnusable,
          'That was too short to publish — a Voice Moment needs at least '
          'one second.',
          action: 'Hold on a little longer this time.',
        ),
        phase: VoiceMomentRecordingPhase.idle,
      );
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

  /// Abandons a microphone request that is still waiting for an answer.
  ///
  /// A browser that never resolves the prompt would otherwise leave the
  /// user on a spinner with Back as the only escape.
  void _cancelAccessRequest() {
    if (_phase != VoiceMomentRecordingPhase.requestingAccess) return;
    _accessAttempt++;
    unawaited(_recorder.cancel());
    setState(() {
      _notice = null;
      _phase = VoiceMomentRecordingPhase.idle;
    });
    _announce('Microphone request cancelled.');
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
      _showNotice(
        VoiceRecordingException(
          VoiceRecordingProblem.uploadFailed,
          intentionalOrFriendly(
            error,
            fallback: 'Your Voice Moment could not be published.',
          ),
          action: 'Your recording is still here — try publishing again.',
          cause: error,
        ),
        phase: VoiceMomentRecordingPhase.reviewing,
      );
      // The notice pushes the actions down, and off-screen descendants are
      // flagged hidden to assistive technology. Bring the retry back into
      // view and put focus on it rather than making the user traverse the
      // whole screen to find out where it went.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final target = _publishKey.currentContext;
        if (target != null) {
          unawaited(
            Scrollable.ensureVisible(
              target,
              duration: const Duration(milliseconds: 200),
              alignment: 0.5,
            ),
          );
        }
        _publishFocus.requestFocus();
      });
      return;
    }

    await _discardRecording();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  int get _durationSeconds => _recorder.durationSeconds;

  int get _elapsedSeconds => _phase == VoiceMomentRecordingPhase.recording
      ? math.min(_recorder.elapsed.inSeconds, _maxSeconds)
      : (_recording == null ? 0 : _durationSeconds);

  /// A real clock format. The old one hard-coded the minute as `0:`, so a
  /// full-length take — which the 60 s auto-stop lands on directly —
  /// rendered as the impossible `0:60 / 1:00`.
  static String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String get _timeLabel =>
      '${_formatDuration(_elapsedSeconds)} / ${_formatDuration(_maxSeconds)}';

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
              colors: [
                _skyTop,
                AppColors.surface,
                _background,
              ],
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
            // Material 3's default IconButton padding yields a 40x40 box;
            // docs/UI.md sets a 44x44 floor.
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
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
              // These two have no second column to fill. Left to the
              // stretch layout they produced a ~920 px wide "Go back"
              // button — a phone stack inflated to desktop width.
              VoiceMomentRecordingPhase.checkingSupport ||
              VoiceMomentRecordingPhase.unavailable => Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _intro(),
                      const SizedBox(height: 26),
                      ..._stage(compact: false, stackActions: false),
                    ],
                  ),
                ),
              ),
              _ => Row(
                // Centred, not top-aligned: the right column is shorter
                // than the capture stage, and anchoring both to the top
                // left the bottom-right quadrant empty.
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Centred like everything beneath it. Left-aligned
                        // copy over a centred stage read as two half
                        // designs sharing one column.
                        _intro(),
                        const SizedBox(height: 28),
                        _meterBlock(compact: false, showSilenceHint: false),
                        const SizedBox(height: 20),
                        _recordButton(),
                        const SizedBox(height: 16),
                        _statusLine(),
                        if (_phase ==
                            VoiceMomentRecordingPhase.requestingAccess) ...[
                          const SizedBox(height: 6),
                          _cancelAccessButton(),
                        ],
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
          if (_phase == VoiceMomentRecordingPhase.requestingAccess) ...[
            const SizedBox(height: 6),
            _cancelAccessButton(),
          ],
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
    switch (_phase) {
      case VoiceMomentRecordingPhase.reviewing:
      case VoiceMomentRecordingPhase.publishing:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _captionField(),
            const SizedBox(height: 12),
            _actions(stacked: false),
          ],
        );
      case VoiceMomentRecordingPhase.recording:
        // "Before you start" mid-take is advice for a moment that has
        // already passed. Report the take instead.
        return _liveCard();
      default:
        return _guidanceCard();
    }
  }

  /// The right-hand column while recording: the state of the take, drawn
  /// from the same measured values as the meter. Nothing invented.
  Widget _liveCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: _inset,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _live,
                ),
              ),
              const SizedBox(width: 9),
              const Text(
                'Recording',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _liveRow(Icons.graphic_eq_rounded, 'Input level', _meterValue),
          const SizedBox(height: 10),
          _liveRow(
            Icons.timer_outlined,
            'Remaining',
            _formatDuration(_maxSeconds - _elapsedSeconds),
          ),
          if (_silenceDetected) ...[
            const SizedBox(height: 14),
            _silenceHint(),
          ],
        ],
      ),
    );
  }

  Widget _liveRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 17, color: _muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
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
    // The only live region rendered in the `unavailable` phase: the status
    // line is not built here, so there is nothing to collide with.
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
      decoration: BoxDecoration(
        color: _inset,
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
              color: _warning.withValues(alpha: .12),
              border: Border.all(
                color: _warning.withValues(alpha: .4),
              ),
            ),
            child: const Icon(
              Icons.mic_off_rounded,
              color: _warning,
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
                color: AppColors.textPrimary,
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
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Go back'),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _noticeCard(VoiceRecordingException notice) {
    final blocked = switch (notice.problem) {
      VoiceRecordingProblem.microphoneBlocked ||
      VoiceRecordingProblem.microphonePromptDismissed ||
      VoiceRecordingProblem.microphoneNotFound ||
      VoiceRecordingProblem.microphoneUnavailable => true,
      _ => false,
    };
    final accent = blocked ? _warning : _error;
    // Deliberately NOT a live region. The status line below is this
    // screen's single polite live region, and Flutter web funnels every
    // polite announcement through one shared DOM element — a second one
    // in the same frame silently overwrites the first. Errors are spoken
    // through the assertive channel by `_showNotice` instead.
    return Semantics(
      container: true,
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
        color: _inset,
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

  /// [showSilenceHint] is false in the wide layout, where the right-hand
  /// Recording panel already carries the hint — one screen, one warning.
  Widget _meterBlock({required bool compact, bool showSilenceHint = true}) {
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
                value: _meterValue,
              );
            },
          ),
        ),
        if (_silenceDetected && showSilenceHint) ...[
          const SizedBox(height: 10),
          _silenceHint(),
        ],
        const SizedBox(height: 12),
        // A value, not a live region: this rebuilds every 200 ms and a
        // live region would flood the announcement queue. The approaching
        // limit is covered by one spoken warning from the ticker.
        Semantics(
          label: 'Recording length',
          value: '$_elapsedSeconds of $_maxSeconds seconds',
          excludeSemantics: true,
          child: Text(
            _timeLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  /// Shown once silence has persisted. Not a live region — the assertive
  /// announcement carries it to screen readers; this is the visual half,
  /// and without it a silent meter is pixel-identical to the idle one.
  Widget _silenceHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _warning.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _warning.withValues(alpha: .4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.mic_off_rounded, size: 16, color: _warning),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'No sound detected — check your microphone.',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The cancel escape from a microphone prompt that never resolves.
  Widget _cancelAccessButton() {
    return Center(
      child: TextButton(
        onPressed: _cancelAccessRequest,
        style: TextButton.styleFrom(
          foregroundColor: _muted,
          minimumSize: const Size(88, 48),
        ),
        child: const Text('Cancel'),
      ),
    );
  }

  Widget _recordButton() {
    final recording = _phase == VoiceMomentRecordingPhase.recording;
    final requesting = _phase == VoiceMomentRecordingPhase.requestingAccess;
    final enabled =
        _phase == VoiceMomentRecordingPhase.idle ||
        _phase == VoiceMomentRecordingPhase.reviewing ||
        recording;

    final color = recording ? _live : _primary;

    // AccessibleTapRegion, not a bare InkWell: this screen paints an opaque
    // gradient and card over the Scaffold's root Material, so every ink
    // feature — focus ring included — landed on a covered canvas and
    // keyboard focus was invisible. It brings its own transparent Material
    // and paints the ring above the child.
    return Center(
      child: AccessibleTapRegion(
        onTap: enabled ? _toggleRecording : null,
        // Two controls used to answer to "Record again". This one discards
        // the take and goes live immediately; the outlined button returns
        // to idle. The label names the consequence so picking the wrong
        // one cannot silently destroy a recording.
        semanticLabel: recording
            ? 'Stop recording'
            : (_phase == VoiceMomentRecordingPhase.reviewing
                  ? 'Discard this take and start recording now'
                  : 'Start recording'),
        circular: true,
        minimumSize: const Size(86, 86),
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
      maxLength: _captionMaxLength,
      maxLines: 3,
      minLines: 3,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        // A real label, not just a hint: a hint is the field's only
        // accessible name until the user types, and then it disappears
        // and the field becomes anonymous.
        labelText: 'Caption',
        labelStyle: const TextStyle(color: _muted),
        floatingLabelStyle: const TextStyle(color: AppColors.textPrimary),
        hintText: 'Add a caption…',
        hintStyle: const TextStyle(color: _muted),
        counterStyle: const TextStyle(color: _muted),
        // The visible counter is a detached node that screen readers do
        // not associate with the field; this is what is actually read.
        semanticCounterText:
            '${_captionController.text.length} of $_captionMaxLength '
            'characters',
        filled: true,
        fillColor: _inset,
        // Stated explicitly rather than left to `border:`, which the
        // production InputDecorationTheme's enabled/focused borders
        // override — the harness and the app were not showing the same
        // field. A visible boundary and a real focus ring are also what
        // 1.4.11 and 2.4.7 ask for.
        border: _captionBorder(_border),
        enabledBorder: _captionBorder(_border),
        focusedBorder: _captionBorder(_primary, width: 2),
        disabledBorder: _captionBorder(_border.withValues(alpha: .5)),
      ),
    );
  }

  static OutlineInputBorder _captionBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  /// Activation is disabled while publishing; focusability is not.
  ///
  /// A null `onPressed` makes the framework drop focus to the route scope,
  /// which is what left the retry unreachable after a failed publish, so
  /// the busy state is expressed through the label and styling instead.
  void _ignoreWhileBusy() {}

  Widget _actions({required bool stacked}) {
    final publishing = _phase == VoiceMomentRecordingPhase.publishing;

    final again = OutlinedButton.icon(
      onPressed: publishing ? _ignoreWhileBusy : _recordAgain,
      icon: const Icon(Icons.refresh_rounded),
      label: const Text('Record again', overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: publishing ? Colors.white38 : Colors.white,
        side: BorderSide(
          color: publishing ? _border.withValues(alpha: .5) : _border,
        ),
        padding: const EdgeInsets.symmetric(vertical: 15),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );

    final publish = FilledButton.icon(
      key: _publishKey,
      focusNode: _publishFocus,
      onPressed: publishing ? _ignoreWhileBusy : _publish,
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
        backgroundColor: publishing ? _primary.withValues(alpha: .5) : _primary,
        foregroundColor: publishing ? Colors.white70 : Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 15),
        // The painted height, not just the padded hit area: docs/UI.md's
        // 44x44 floor is about what the user can see and aim at.
        minimumSize: const Size.fromHeight(48),
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
    required this.value,
  });

  final List<double> levels;
  final int barCount;
  final bool live;

  /// Coarse input level, exposed as the node's semantics value so the
  /// meter is not a purely visual signal. Not a live region: sustained
  /// silence is called out by a single assertive announcement instead.
  final String value;

  static const double _restHeight = 6;
  static const double _maxHeight = 96;

  @override
  Widget build(BuildContext context) {
    // Show the most recent [barCount] samples, oldest on the left.
    final start = math.max(0, levels.length - barCount);
    final visible = levels.sublist(start);

    return Semantics(
      label: live ? 'Microphone level' : 'Microphone level, not recording',
      value: value,
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
                          ? const [AppColors.primary, AppColors.secondary]
                          : [
                              AppColors.primary.withValues(alpha: .35),
                              AppColors.secondary.withValues(alpha: .35),
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
