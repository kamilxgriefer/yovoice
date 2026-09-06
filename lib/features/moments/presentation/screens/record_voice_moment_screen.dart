import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart' show Amplitude;

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/features/moments/data/models/moment_availability.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';
import 'package:yovoice/shared/widgets/inputs/yo_keyboard_done_bar.dart';

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

enum _AvailabilityUnit { hours, days }

/// Only presentation-owned, already localized messages may bypass the domain
/// category mapping. Never wrap arbitrary exception or backend text in this.
class _LocalizedVoiceNotice extends VoiceRecordingException {
  const _LocalizedVoiceNotice(
    super.problem,
    super.message, {
    super.action,
    super.cause,
  });
}

/// The recorder uses one timeout category on every platform. Keep browser
/// instructions out of native recovery copy without changing recorder state.
/// The platform override exercises both presentation branches in VM tests.
@visibleForTesting
({String message, String action}) voiceMomentMicrophoneTimeoutCopy(
  AppLocalizations copy, {
  bool isWeb = kIsWeb,
}) => isWeb
    ? (
        message: copy.text(
          'Your browser did not answer the microphone request.',
          'Przeglądarka nie odpowiedziała na prośbę o dostęp do mikrofonu.',
        ),
        action: copy.text(
          'Start recording again, then choose Allow.',
          'Rozpocznij nagrywanie ponownie, a następnie wybierz Zezwól.',
        ),
      )
    : (
        message: copy.text(
          'YO Voice could not open your microphone.',
          'YO Voice nie może uruchomić mikrofonu.',
        ),
        action: copy.text('Try again.', 'Spróbuj ponownie.'),
      );

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
    this.previewPlayerFactory,
    super.key,
  });

  final String? replyToMomentId;
  final String? replyToAuthorName;

  /// Injected by tests so every phase can be driven without hardware.
  final VoiceMomentRecorder? recorder;
  final MomentService? momentService;

  /// Injected so playback can be exercised without a platform audio channel.
  final AudioPlayer Function()? previewPlayerFactory;

  @override
  State<RecordVoiceMomentScreen> createState() =>
      _RecordVoiceMomentScreenState();
}

class _RecordVoiceMomentScreenState extends State<RecordVoiceMomentScreen>
    with WidgetsBindingObserver {
  // Every colour on this screen resolves from AppColors, the project's
  // single source of truth for the palette. The file previously defined
  // its own purple (0xFF9D20FF), visibly different from the AppColors
  // purple used by moments_screen.dart directly beside it. Local names are
  // kept for readability; none of them is a raw hex value.
  static const Color _background = AppImmersiveColors.background;
  static const Color _surface = AppImmersiveColors.surface;
  static const Color _inset = AppImmersiveColors.background;
  static const Color _border = AppImmersiveColors.border;
  // Interactive control outlines need >=3:1 against the fixed dark inset,
  // even when the ambient app theme is light.
  static const Color _controlBorder = AppImmersiveColors.textTertiary;
  static const Color _muted = AppImmersiveColors.textSecondary;
  static const Color _primary = AppColors.primary;

  /// The immersive recorder's cosmic backdrop top stop.
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
  final TextEditingController _availabilityAmountController =
      TextEditingController(text: '24');

  VoiceMomentRecordingPhase _phase = VoiceMomentRecordingPhase.checkingSupport;

  /// Why this platform cannot record, when [_phase] is `unavailable`.
  CaptureSupport? _unsupported;

  /// A recoverable problem shown inline. Never a bare exception string.
  VoiceRecordingException? _notice;

  Timer? _ticker;
  StreamSubscription<Amplitude>? _levels;
  final List<double> _meter = List<double>.filled(_meterBarCount, 0);

  RecordedAudio? _recording;

  AudioPlayer? _previewPlayer;
  StreamSubscription<PlayerState>? _previewStateSubscription;
  StreamSubscription<Duration>? _previewPositionSubscription;
  StreamSubscription<Duration>? _previewDurationSubscription;
  StreamSubscription<void>? _previewCompletionSubscription;
  Duration _previewPosition = Duration.zero;
  Duration _previewDuration = Duration.zero;
  bool _previewLoaded = false;
  bool _previewPlaying = false;
  bool _previewBusy = false;
  String? _previewError;

  /// How long the published Moment stays live. Defaults to 24 hours —
  /// exactly today's behaviour — and is sent to the server as
  /// `availabilityHours` only when the author picks something else.
  /// Voice replies have no expiry of their own, so the selector never
  /// renders for them.
  MomentAvailability _timedAvailability = MomentAvailability.fallback;
  _AvailabilityUnit _availabilityUnit = _AvailabilityUnit.hours;
  bool _untilDeleted = false;
  String? _availabilityError;

  /// Once the first upload attempt starts these values must remain identical
  /// for every retry of the same audio. `MomentService` deliberately rejects
  /// a changed idempotent contract, so the UI makes that invariant visible.
  bool _publishContractLocked = false;

  bool _leaving = false;
  bool _restarting = false;
  bool _resourcesReleased = false;

  /// Keeps the primary action reachable: a null `onPressed` drops focus to
  /// the route scope, which is how the retry became unreachable after a
  /// failed publish.
  final FocusNode _publishFocus = FocusNode(debugLabel: 'Publish Voice Moment');
  final FocusNode _captionFocus = FocusNode(debugLabel: 'Voice Moment caption');
  // Preserve the editable subtree and its input connection when keyboard
  // insets move the review form between wide and stacked layouts.
  final GlobalKey _captionFieldKey = GlobalKey();
  final FocusNode _availabilityAmountFocus = FocusNode(
    debugLabel: 'Voice Moment duration',
  );
  final GlobalKey _publishKey = GlobalKey();
  final GlobalKey _availabilityAmountKey = GlobalKey();

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

  AppLocalizations get _copy => AppLocalizations.of(context);

  // Domain error copy is English and may include platform details. Only known
  // categories become catalog keys here; arbitrary exception text never renders.
  String _noticeMessage(VoiceRecordingException notice) {
    if (notice is _LocalizedVoiceNotice) return notice.message;
    return switch (notice.problem) {
      VoiceRecordingProblem.platformCannotRecord => _supportMessage(
        notice.message,
      ),
      VoiceRecordingProblem.microphoneBlocked =>
        notice.message ==
                'Microphone access for YO Voice is blocked in this browser.'
            ? _copy.text(
                "Microphone access for YO Voice is blocked in this browser.",
                "Dostęp YO Voice do mikrofonu jest zablokowany w tej przeglądarce.",
              )
            : _copy.text(
                "YO Voice does not have permission to use your microphone.",
                "YO Voice nie ma uprawnień do używania mikrofonu.",
              ),
      VoiceRecordingProblem.microphonePromptDismissed => _copy.text(
        "The microphone request was dismissed, so recording could not start.",
        "Prośba o dostęp do mikrofonu została zamknięta, więc nagrywanie nie mogło się rozpocząć.",
      ),
      VoiceRecordingProblem.microphoneNotFound => _copy.text(
        "No microphone was found on this device.",
        "Nie znaleziono mikrofonu na tym urządzeniu.",
      ),
      VoiceRecordingProblem.microphoneUnavailable => _copy.text(
        "Your microphone could not be opened — another app is probably using it.",
        "Nie można uruchomić mikrofonu — prawdopodobnie korzysta z niego inna aplikacja.",
      ),
      VoiceRecordingProblem.captureFailed => switch (notice.message) {
        'Your browser did not answer the microphone request.' =>
          voiceMomentMicrophoneTimeoutCopy(_copy).message,
        'Recording could not be finished.' => _copy.text(
          'Recording could not be finished.',
          'Nie udało się zakończyć nagrywania.',
        ),
        'Recording could not be started.' => _copy.text(
          'Recording could not be started.',
          'Nie udało się rozpocząć nagrywania.',
        ),
        _ => _copy.text(
          "YO Voice could not open your microphone.",
          "YO Voice nie może uruchomić mikrofonu.",
        ),
      },
      VoiceRecordingProblem.recordingUnusable =>
        notice.message ==
                'That recording is larger than the 12 MB limit for a Voice Moment.'
            ? _copy.text(
                "That recording is larger than the 12 MB limit for a Voice Moment.",
                "To nagranie przekracza limit 12 MB dla Voice Momentu.",
              )
            : notice.message.startsWith('This recording came back as ')
            ? _copy.text(
                "This recording format cannot be published.",
                "Tego formatu nagrania nie można opublikować.",
              )
            : _copy.text(
                "That recording could not be used. Record again and speak for at least a second.",
                "Nie można użyć tego nagrania. Nagraj ponownie i mów przez co najmniej sekundę.",
              ),
      VoiceRecordingProblem.uploadFailed =>
        notice.message == 'Publishing took too long and was stopped safely.'
            ? _copy.text(
                "Publishing took too long and was stopped safely.",
                "Publikacja trwała zbyt długo i została bezpiecznie zatrzymana.",
              )
            : _copy.text(
                "Your Voice Moment could not be published.",
                "Nie udało się opublikować Voice Momentu.",
              ),
    };
  }

  String? _noticeAction(VoiceRecordingException notice) {
    if (notice is _LocalizedVoiceNotice) return notice.action;
    return switch (notice.problem) {
      VoiceRecordingProblem.platformCannotRecord => _supportAction(
        notice.message,
      ),
      VoiceRecordingProblem.microphoneBlocked =>
        notice.message ==
                'Microphone access for YO Voice is blocked in this browser.'
            ? _copy.text(
                "Allow the microphone in your browser's site settings for YO Voice, then reload this page.",
                "Zezwól na używanie mikrofonu w ustawieniach witryny YO Voice w przeglądarce, a następnie odśwież stronę.",
              )
            : _copy.text(
                "Allow the microphone for YO Voice in your device settings.",
                "Zezwól aplikacji YO Voice na używanie mikrofonu w ustawieniach urządzenia.",
              ),
      VoiceRecordingProblem.microphonePromptDismissed => _copy.text(
        "Start recording again, then choose Allow.",
        "Rozpocznij nagrywanie ponownie, a następnie wybierz Zezwól.",
      ),
      VoiceRecordingProblem.microphoneNotFound => _copy.text(
        "Connect a microphone, then start recording again.",
        "Podłącz mikrofon, a następnie rozpocznij nagrywanie ponownie.",
      ),
      VoiceRecordingProblem.microphoneUnavailable => _copy.text(
        "Close the other app, then start recording again.",
        "Zamknij inną aplikację, a następnie rozpocznij nagrywanie ponownie.",
      ),
      VoiceRecordingProblem.captureFailed =>
        notice.message == 'Your browser did not answer the microphone request.'
            ? voiceMomentMicrophoneTimeoutCopy(_copy).action
            : notice.message == 'Recording could not be finished.'
            ? _copy.text('Record again.', 'Nagraj ponownie.')
            : _copy.text('Try again.', 'Spróbuj ponownie.'),
      VoiceRecordingProblem.recordingUnusable =>
        notice.message ==
                'That recording is larger than the 12 MB limit for a Voice Moment.'
            ? _copy.text(
                "Record a shorter Voice Moment.",
                "Nagraj krótszy Voice Moment.",
              )
            : notice.message.startsWith('This recording came back as ')
            ? _copy.text(
                "Open YO Voice in Chrome, Edge or Safari to record.",
                "Otwórz YO Voice w Chrome, Edge lub Safari, aby nagrywać.",
              )
            : null,
      VoiceRecordingProblem.uploadFailed =>
        notice.message == 'Publishing took too long and was stopped safely.'
            ? _copy.text(
                'Check your connection and try again.',
                'Sprawdź połączenie i spróbuj ponownie.',
              )
            : _copy.text(
                "Your recording is still here — try publishing again.",
                "Nagranie zostało zachowane — spróbuj opublikować je ponownie.",
              ),
    };
  }

  String _supportMessage(String? reason) {
    if (reason?.contains('secure (https)') ?? false) {
      return _copy.text(
        "Microphone access needs a secure (https) connection.",
        "Dostęp do mikrofonu wymaga bezpiecznego połączenia (https).",
      );
    }
    if ((reason?.contains('MP4/AAC') ?? false) ||
        (reason?.startsWith('This browser would record as ') ?? false)) {
      return _copy.text(
        "This browser cannot record MP4/AAC audio.",
        "Ta przeglądarka nie może nagrywać dźwięku MP4/AAC.",
      );
    }
    if ((reason?.contains('no AAC encoder') ?? false) ||
        (reason?.startsWith('Voice recording is not available') ?? false)) {
      return _copy.text(
        "Voice recording is not available on this device.",
        "Nagrywanie głosu nie jest dostępne na tym urządzeniu.",
      );
    }
    return _copy.text(
      "YO Voice could not reach an audio recorder on this device.",
      "YO Voice nie może skorzystać z nagrywania dźwięku na tym urządzeniu.",
    );
  }

  String _supportAction(String? reason) {
    if (reason?.contains('secure (https)') ?? false) {
      return _copy.text(
        "Open YO Voice over https and try again.",
        "Otwórz YO Voice przez https i spróbuj ponownie.",
      );
    }
    return _copy.text(
      "Open YO Voice in Chrome, Edge or Safari to record.",
      "Otwórz YO Voice w Chrome, Edge lub Safari, aby nagrywać.",
    );
  }

  String _localizedMeterValue(String value) => switch (value) {
    _meterSilent => _copy.text("Silent", "Cisza"),
    _meterQuiet => _copy.text("Quiet", "Cicho"),
    _meterGood => _copy.text("Good level", "Dobry poziom"),
    _ => _copy.text("Input level unavailable", "Poziom wejścia niedostępny"),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recorder = widget.recorder ?? VoiceMomentRecorder();
    _captionController.addListener(_onCaptionChanged);
    _availabilityAmountController.addListener(_onAvailabilityAmountChanged);
    unawaited(_resolveSupport());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    unawaited(_levels?.cancel());
    _publishFocus.dispose();
    _captionFocus.dispose();
    _availabilityAmountFocus.dispose();
    _captionController
      ..removeListener(_onCaptionChanged)
      ..dispose();
    _availabilityAmountController
      ..removeListener(_onAvailabilityAmountChanged)
      ..dispose();
    // `dispose` cannot await. The route's explicit back path awaits this same
    // ordered cleanup; this is the safety net for parent-route teardown.
    unawaited(_releaseResources());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_pausePreview());
    }
  }

  MomentService get _moments =>
      _momentService ??= (widget.momentService ?? MomentService());

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
      assertiveness: assertive ? Assertiveness.assertive : Assertiveness.polite,
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
    _announce('${_noticeMessage(notice)} ${_noticeAction(notice) ?? ''}');
  }

  void _onCaptionChanged() {
    if (!mounted) return;
    final length = _captionController.text.length;
    if (length >= _captionMaxLength) {
      if (!_captionLimitAnnounced) {
        _captionLimitAnnounced = true;
        // Input is silently dropped past the limit otherwise.
        _announce(
          _copy.template(
            'Caption limit reached: {limit} characters.',
            'Osiągnięto limit opisu: {limit} znaków.',
            values: {'limit': _captionMaxLength},
          ),
        );
      }
    } else {
      _captionLimitAnnounced = false;
    }
    // Refreshes the field's semantic counter text.
    setState(() {});
  }

  void _onAvailabilityAmountChanged() {
    if (!mounted || _untilDeleted || _publishContractLocked) return;
    final availability = _readTimedAvailability();
    setState(() {
      _availabilityError = _timedAvailabilityValidationMessage();
      if (availability != null) _timedAvailability = availability;
    });
  }

  MomentAvailability? _readTimedAvailability() {
    final amount = int.tryParse(_availabilityAmountController.text.trim());
    if (amount == null) return null;
    final hours = switch (_availabilityUnit) {
      _AvailabilityUnit.hours => amount,
      _AvailabilityUnit.days => amount * 24,
    };
    if (hours < MomentAvailability.minimumHours ||
        hours > MomentAvailability.maximumHours) {
      return null;
    }
    return MomentAvailability.timedHours(hours);
  }

  String? _timedAvailabilityValidationMessage() {
    final amount = int.tryParse(_availabilityAmountController.text.trim());
    if (amount == null) {
      return _copy.text('Enter a whole number.', 'Wpisz liczbę całkowitą.');
    }
    return switch (_availabilityUnit) {
      _AvailabilityUnit.hours
          when amount < MomentAvailability.minimumHours ||
              amount > MomentAvailability.maximumHours =>
        _copy.text(
          'Choose between 24 and 720 hours.',
          'Wybierz od 24 do 720 godzin.',
        ),
      _AvailabilityUnit.days when amount < 1 || amount > 30 => _copy.text(
        'Choose between 1 and 30 days.',
        'Wybierz od 1 do 30 dni.',
      ),
      _ => null,
    };
  }

  void _setUntilDeleted(bool value) {
    if (_publishContractLocked ||
        _phase == VoiceMomentRecordingPhase.publishing) {
      return;
    }
    setState(() {
      _untilDeleted = value;
      _availabilityError = value ? null : _timedAvailabilityValidationMessage();
    });
  }

  void _setAvailabilityUnit(_AvailabilityUnit unit) {
    if (_publishContractLocked ||
        _phase == VoiceMomentRecordingPhase.publishing ||
        unit == _availabilityUnit) {
      return;
    }
    final currentHours = _timedAvailability.hours ?? 24;
    final nextAmount = unit == _AvailabilityUnit.hours
        ? currentHours
        : math.max(1, (currentHours / 24).ceil());
    setState(() {
      _availabilityUnit = unit;
      _availabilityError = null;
    });
    _availabilityAmountController.value = TextEditingValue(
      text: '$nextAmount',
      selection: TextSelection.collapsed(offset: '$nextAmount'.length),
    );
  }

  MomentAvailability? _validatedAvailabilityForPublish() {
    if (_isReply) return MomentAvailability.fallback;
    if (_untilDeleted) return MomentAvailability.permanent;
    final availability = _readTimedAvailability();
    final error = _timedAvailabilityValidationMessage();
    if (availability == null || error != null) {
      final message =
          error ??
          _copy.text(
            'Choose a valid duration.',
            'Wybierz prawidłowy czas dostępności.',
          );
      setState(() => _availabilityError = message);
      _announce(message);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final target = _availabilityAmountKey.currentContext;
        if (target != null) {
          unawaited(
            Scrollable.ensureVisible(
              target,
              duration: const Duration(milliseconds: 200),
              alignment: 0.5,
            ),
          );
        }
        _availabilityAmountFocus.requestFocus();
      });
      return null;
    }
    return availability;
  }

  AudioPlayer _ensurePreviewPlayer() {
    final existing = _previewPlayer;
    if (existing != null) return existing;

    final player = widget.previewPlayerFactory?.call() ?? AudioPlayer();
    _previewPlayer = player;
    _previewStateSubscription = player.onPlayerStateChanged.listen((state) {
      if (!mounted || !identical(_previewPlayer, player)) return;
      setState(() => _previewPlaying = state == PlayerState.playing);
    }, onError: _showPreviewError);
    _previewPositionSubscription = player.onPositionChanged.listen((position) {
      if (!mounted || !identical(_previewPlayer, player)) return;
      final upper = _previewDuration > Duration.zero
          ? _previewDuration
          : position;
      setState(() {
        _previewPosition = position > upper ? upper : position;
      });
    }, onError: _showPreviewError);
    _previewDurationSubscription = player.onDurationChanged.listen((duration) {
      if (!mounted ||
          !identical(_previewPlayer, player) ||
          duration <= Duration.zero) {
        return;
      }
      setState(() => _previewDuration = duration);
    }, onError: _showPreviewError);
    _previewCompletionSubscription = player.onPlayerComplete.listen((_) {
      if (!mounted || !identical(_previewPlayer, player)) return;
      setState(() {
        _previewPlaying = false;
        _previewPosition = _previewDuration;
      });
    }, onError: _showPreviewError);
    return player;
  }

  void _showPreviewError(Object _) {
    if (!mounted) return;
    final message = _copy.text(
      'Preview could not be played on this device. You can '
          'try again, record a new take, or publish this one.',
      'Nie udało się odtworzyć podglądu na tym urządzeniu. Spróbuj ponownie, '
          'nagraj nową wersję albo opublikuj tę.',
    );
    setState(() {
      _previewBusy = false;
      _previewPlaying = false;
      _previewLoaded = false;
      _previewError = message;
    });
    // Keep the status line as the screen's single polite live region and use
    // the dedicated assertive announcement channel for this asynchronous
    // failure, just like publish/capture errors.
    _announce(message);
  }

  Future<void> _togglePreview() async {
    if (_previewBusy ||
        _phase != VoiceMomentRecordingPhase.reviewing ||
        _recording == null) {
      return;
    }

    final player = _ensurePreviewPlayer();
    if (_previewPlaying) {
      setState(() => _previewBusy = true);
      try {
        await player.pause();
        if (!mounted || !identical(_previewPlayer, player)) return;
        setState(() {
          _previewPlaying = false;
          _previewBusy = false;
        });
      } catch (error) {
        _showPreviewError(error);
      }
      return;
    }

    final audio = _recording;
    if (audio == null) return;
    setState(() {
      _previewBusy = true;
      _previewError = null;
    });
    try {
      final atEnd =
          _previewDuration > Duration.zero &&
          _previewPosition >= _previewDuration;
      if (atEnd) {
        _previewPosition = Duration.zero;
        if (_previewLoaded) await player.seek(Duration.zero);
      }
      if (_previewLoaded) {
        await player.resume();
      } else {
        await player.play(
          audio.playbackSource,
          position: _previewPosition > Duration.zero ? _previewPosition : null,
        );
        _previewLoaded = true;
      }
      if (!mounted || !identical(_previewPlayer, player)) return;
      setState(() {
        _previewPlaying = true;
        _previewBusy = false;
      });
    } catch (error) {
      _showPreviewError(error);
    }
  }

  void _setPreviewPosition(double milliseconds) {
    final duration = Duration(milliseconds: milliseconds.round());
    setState(() => _previewPosition = duration);
  }

  Future<void> _seekPreview(double milliseconds) async {
    final player = _previewPlayer;
    if (!_previewLoaded || player == null) return;
    try {
      await player.seek(Duration(milliseconds: milliseconds.round()));
    } catch (error) {
      _showPreviewError(error);
    }
  }

  Future<void> _pausePreview() async {
    final player = _previewPlayer;
    if (player == null || !_previewPlaying) return;
    try {
      await player.pause();
      if (mounted && identical(_previewPlayer, player)) {
        setState(() => _previewPlaying = false);
      }
    } catch (_) {
      // Lifecycle suspension must not replace a useful recording with an
      // error. An explicit Play tap will surface a platform failure.
    }
  }

  Future<void> _stopAndDisposePreview({bool resetPosition = true}) async {
    final player = _previewPlayer;
    _previewPlayer = null;
    if (player != null) {
      try {
        await player.stop();
      } catch (_) {
        // Disposal still releases the platform channel after a failed stop.
      }
    }
    final subscriptionCancellations = <Future<void>>[
      if (_previewStateSubscription != null)
        _previewStateSubscription!.cancel(),
      if (_previewPositionSubscription != null)
        _previewPositionSubscription!.cancel(),
      if (_previewDurationSubscription != null)
        _previewDurationSubscription!.cancel(),
      if (_previewCompletionSubscription != null)
        _previewCompletionSubscription!.cancel(),
    ];
    _previewStateSubscription = null;
    _previewPositionSubscription = null;
    _previewDurationSubscription = null;
    _previewCompletionSubscription = null;
    // Calling cancel detaches the listeners synchronously. Some platform
    // streams complete the returned cleanup future only when their player is
    // disposed, so awaiting those futures before `dispose` would deadlock.
    unawaited(
      Future.wait(
        subscriptionCancellations,
      ).then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    if (player != null) {
      try {
        await player.dispose();
      } catch (_) {
        // Best-effort release; the recording itself can still be discarded.
      }
    }
    _previewLoaded = false;
    _previewPlaying = false;
    _previewBusy = false;
    _previewError = null;
    if (resetPosition) _previewPosition = Duration.zero;
  }

  Future<void> _releaseResources() async {
    if (_resourcesReleased) return;
    _resourcesReleased = true;
    _accessAttempt++;
    _ticker?.cancel();
    await _levels?.cancel();
    _levels = null;
    if (_phase == VoiceMomentRecordingPhase.requestingAccess ||
        _phase == VoiceMomentRecordingPhase.recording) {
      try {
        await _recorder.cancel();
      } catch (_) {
        // Continue releasing the player and temporary recording.
      }
    }
    final audio = _recording;
    _recording = null;
    if (audio != null) _momentService?.abandonPendingPublish(audio);
    await _stopAndDisposePreview();
    if (audio != null) await audio.discard();
    await _recorder.dispose();
  }

  Future<void> _leave([Object? result]) async {
    if (_leaving || _phase == VoiceMomentRecordingPhase.publishing) return;
    setState(() => _leaving = true);
    await _releaseResources();
    if (!mounted) return;
    // Let PopScope observe `canPop: true` before initiating the real pop.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop(result);
  }

  String _meterValueFor(double level) {
    if (level <= 0) return _meterSilent;
    if (level < 0.25) return _meterQuiet;
    return _meterGood;
  }

  Future<void> _resolveSupport() async {
    final support = await _recorder.checkSupport();
    if (!mounted || _leaving || _resourcesReleased) return;
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
    if (_phase != VoiceMomentRecordingPhase.idle) return;

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
        _announce('${_noticeMessage(error)} ${_noticeAction(error) ?? ''}');
      } else {
        _showNotice(error, phase: VoiceMomentRecordingPhase.idle);
      }
      return;
    } catch (error) {
      if (!mounted || attempt != _accessAttempt) return;
      _showNotice(
        _LocalizedVoiceNotice(
          VoiceRecordingProblem.captureFailed,
          _copy.text(
            'Recording could not be started.',
            'Nie udało się rozpocząć nagrywania.',
          ),
          action: _copy.text('Try again.', 'Spróbuj ponownie.'),
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
        _announce(
          _copy.text('Ten seconds left.', 'Pozostało dziesięć sekund.'),
        );
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
                _copy.text(
                  'No sound is reaching the microphone. Check that the right '
                      'microphone is selected and not muted.',
                  'Mikrofon nie odbiera dźwięku. Sprawdź, czy wybrano właściwy '
                      'mikrofon i czy nie jest wyciszony.',
                ),
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
            _copy.text(
              'Microphone level is unavailable, so YO Voice cannot tell you '
                  'whether sound is being picked up. Recording continues.',
              'Poziom mikrofonu jest niedostępny, więc YO Voice nie może '
                  'sprawdzić, czy dźwięk jest odbierany. Nagrywanie trwa dalej.',
            ),
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
        _LocalizedVoiceNotice(
          VoiceRecordingProblem.captureFailed,
          _copy.text(
            'Recording could not be finished.',
            'Nie udało się zakończyć nagrywania.',
          ),
          action: _copy.text('Record again.', 'Nagraj ponownie.'),
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
        _LocalizedVoiceNotice(
          VoiceRecordingProblem.recordingUnusable,
          _copy.text(
            'That was too short to publish — a Voice Moment needs at least '
                'one second.',
            'Nagranie jest za krótkie — Voice Moment musi trwać co najmniej '
                'sekundę.',
          ),
          action: _copy.text(
            'Hold on a little longer this time.',
            'Tym razem nagrywaj odrobinę dłużej.',
          ),
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
      _previewPosition = Duration.zero;
      _previewDuration = Duration(seconds: _durationSeconds);
      _previewError = null;
      _publishContractLocked = false;
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
    _announce(
      _copy.text(
        'Microphone request cancelled.',
        'Anulowano prośbę o dostęp do mikrofonu.',
      ),
    );
  }

  Future<void> _discardRecording() async {
    final existing = _recording;
    _recording = null;
    if (existing != null) {
      // A failed publish pins this exact recording as the idempotent retry
      // identity. Record again/Back means the author has explicitly abandoned
      // that retry; release the strong service-map reference before discarding
      // the native file or browser Blob. Remote orphan cleanup stays server
      // authority because finalize may already have committed.
      _momentService?.abandonPendingPublish(existing);
    }
    // The player owns an open file/Blob handle on some platforms. Stop and
    // dispose it before deleting the file or revoking the object URL.
    await _stopAndDisposePreview();
    if (existing != null) await existing.discard();
  }

  Future<void> _recordAgain() async {
    if (_phase == VoiceMomentRecordingPhase.publishing || _restarting) return;
    _restarting = true;
    try {
      await _discardRecording();
      if (!mounted) return;
      _meter.fillRange(0, _meter.length, 0);
      setState(() {
        _notice = null;
        _publishContractLocked = false;
        _phase = VoiceMomentRecordingPhase.idle;
      });
      await _startRecording();
    } finally {
      _restarting = false;
    }
  }

  // ---------------------------------------------------------------- publish

  Future<void> _publish() async {
    final audio = _recording;
    if (audio == null || _phase != VoiceMomentRecordingPhase.reviewing) return;

    final availability = _validatedAvailabilityForPublish();
    if (availability == null) return;
    // Freeze the exact contract before any asynchronous cleanup or network
    // call. A failed upload can then be retried idempotently with no hidden
    // caption or expiry drift.
    final caption = _captionController.text;

    setState(() {
      _notice = null;
      _publishContractLocked = true;
      _phase = VoiceMomentRecordingPhase.publishing;
    });

    // Audio playback and upload must never contend for the local file/Blob.
    await _stopAndDisposePreview();

    try {
      await _moments.publishRecordedMoment(
        audio: audio,
        durationSeconds: _durationSeconds,
        caption: caption,
        replyToMomentId: widget.replyToMomentId,
        availability: availability,
      );
    } catch (error) {
      if (!mounted) return;
      // The active-Moment cap is the SERVER'S refusal
      // (`reserveMomentDraft` answers `resource-exhausted` when the
      // caller already has the maximum of live Moments). The client
      // never pre-guesses the cap — recording stays available with any
      // number of active Moments — it only translates the refusal into
      // copy that explains what actually happened instead of the generic
      // "we're overloaded" quota line.
      final capRefusal =
          error is FirebaseFunctionsException &&
          error.code == 'resource-exhausted';
      // The recording is kept: the capture succeeded, only publishing
      // failed, and making the user re-record would lose good audio.
      _showNotice(
        _LocalizedVoiceNotice(
          VoiceRecordingProblem.uploadFailed,
          capRefusal
              ? _copy.text(
                  "You have reached the limit of active Moments. A slot frees up when one expires or you delete one.",
                  "Osiągnięto limit aktywnych Momentów. Miejsce zwolni się, gdy jeden z nich wygaśnie lub go usuniesz.",
                )
              : error is VoiceRecordingException
              ? _noticeMessage(error)
              : (error is StateError &&
                        error.message ==
                            'You must be signed in to publish a Voice Moment.') ||
                    (error is FirebaseFunctionsException &&
                        error.code == 'unauthenticated')
              ? _copy.text(
                  "You must be signed in to publish a Voice Moment.",
                  "Musisz się zalogować, aby opublikować Voice Moment.",
                )
              : _copy.text(
                  "Your Voice Moment could not be published.",
                  "Nie udało się opublikować Voice Momentu.",
                ),
          action: capRefusal
              ? _copy.text(
                  "Your recording is kept — publish it once a slot frees up.",
                  "Nagranie zostało zachowane — opublikuj je, gdy zwolni się miejsce.",
                )
              : error is VoiceRecordingException
              ? _noticeAction(error)
              : _copy.text(
                  "Your recording is still here — try publishing again.",
                  "Nagranie zostało zachowane — spróbuj opublikować je ponownie.",
                ),
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
    setState(() => _phase = VoiceMomentRecordingPhase.reviewing);
    await _leave(true);
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

  bool get _isReview =>
      _phase == VoiceMomentRecordingPhase.reviewing ||
      _phase == VoiceMomentRecordingPhase.publishing;

  @override
  Widget build(BuildContext context) {
    final busy = _phase == VoiceMomentRecordingPhase.publishing;

    final content = PopScope<Object?>(
      // Every exit goes through `_leave`, which releases microphone/player
      // resources and discards the local take before the route is removed.
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !busy) unawaited(_leave(result));
      },
      child: Scaffold(
        backgroundColor: _background,
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.8),
              radius: 1.1,
              colors: [_skyTop, AppImmersiveColors.surface, _background],
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
                      final textScale = MediaQuery.textScalerOf(
                        context,
                      ).scale(1);
                      // A short keyboard viewport and enlarged text need one
                      // uninterrupted scroll path, not a footer that consumes
                      // the space needed to read or edit the recording.
                      final wide =
                          width >= 1100 &&
                          textScale < 1.6 &&
                          constraints.maxHeight >= 480;
                      final pinActions =
                          _isReview &&
                          constraints.maxHeight >= 460 &&
                          textScale < 1.6 &&
                          MediaQuery.viewInsetsOf(context).bottom == 0;
                      final body = wide
                          ? _wideBody(width, showActions: !pinActions)
                          : _stackedBody(width, showActions: !pinActions);
                      return Column(
                        children: [
                          Expanded(
                            // Start each visual stage at its heading, not at
                            // the scroll offset of the previous capture/form.
                            // Publishing and retry stay in the same stage.
                            child: KeyedSubtree(
                              key: ValueKey(_isReview),
                              child: body,
                            ),
                          ),
                          if (pinActions) _reviewActionBar(width, wide: wide),
                          // While the keyboard is up the action bar is
                          // unpinned by design; this gives the caption an
                          // explicit way out instead of a blank slot.
                          const YoKeyboardDoneBar(),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return YoImmersiveDarkSurface(child: content);
  }

  Widget _header(bool busy) {
    final copy = _copy;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: busy ? null : _leave,
            tooltip: copy.text('Back', 'Wstecz'),
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
          Expanded(
            child: Text(
              copy.text('Record Voice Moment', 'Nagraj Voice Moment'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                height: 1.15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  /// Capture and review share a local state machine, but each has a focused
  /// visual stage. No draft or upload starts when this presentation changes.
  Widget _stackedBody(double width, {required bool showActions}) {
    final compact = width < 600;
    return SingleChildScrollView(
      key: const ValueKey('voice-moment-body-scroll'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      child: ResponsiveContentFrame(
        width: ResponsiveContentWidth.form,
        fillHeight: false,
        padding: ResponsiveContentFrame.adaptivePagePadding(width),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _flowProgress(),
            const SizedBox(height: 24),
            _intro(),
            const SizedBox(height: 20),
            ..._stage(
              compact: compact,
              stackActions:
                  compact || MediaQuery.textScalerOf(context).scale(1) >= 1.6,
              showActions: showActions,
            ),
          ],
        ),
      ),
    );
  }

  /// Non-interactive progress, not a second navigation system: changing a
  /// stage must never discard a take or reopen microphone access implicitly.
  Widget _flowProgress() {
    final steps = [
      _copy.text('Record', 'Nagraj'),
      _copy.text('Review', 'Sprawdź'),
    ];
    final active = _isReview ? 1 : 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 420 &&
            MediaQuery.textScalerOf(context).scale(1) >= 1.6;
        final stepWidth = stacked
            ? constraints.maxWidth
            : (constraints.maxWidth - 10) / 2;
        return Wrap(
          key: const ValueKey('voice-moment-flow-progress'),
          spacing: 10,
          runSpacing: 8,
          children: [
            for (var index = 0; index < steps.length; index++)
              SizedBox(
                width: stepWidth,
                child: Semantics(
                  selected: index == active,
                  label: steps[index],
                  value: '${index + 1}/${steps.length}',
                  excludeSemantics: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: index == active
                          ? AppImmersiveColors.surfaceRaised
                          : _surface.withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: index == active ? _controlBorder : _border,
                        width: index == active ? 1.5 : 1,
                      ),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: index == active ? _primary : _inset,
                          ),
                          child: index < active
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: Colors.white,
                                )
                              : Text(
                                  '${index + 1}',
                                  // The number is a decorative progress symbol;
                                  // the adjacent label and semantics carry it.
                                  textScaler: TextScaler.noScaling,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                        Text(
                          steps[index],
                          style: TextStyle(
                            color: index == active ? Colors.white : _muted,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Desktop: the capture stage and the publishing controls sit side by
  /// side, so a wide window is a two-column workspace rather than a phone
  /// column stretched across 1400 px.
  Widget _wideBody(double width, {required bool showActions}) {
    return SingleChildScrollView(
      key: const ValueKey('voice-moment-body-scroll'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(top: 22, bottom: 32),
      child: ResponsiveContentFrame(
        width: ResponsiveContentWidth.feed,
        fillHeight: false,
        padding: ResponsiveContentFrame.adaptivePagePadding(width),
        child: Column(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: _flowProgress(),
            ),
            const SizedBox(height: 28),
            switch (_phase) {
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
                      ..._stage(
                        compact: false,
                        stackActions: false,
                        showActions: showActions,
                      ),
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
                        const SizedBox(height: 20),
                        if (_isReview) ...[
                          _previewPanel(),
                          const SizedBox(height: 14),
                          _statusLine(),
                        ] else
                          _capturePanel(compact: false, showSilenceHint: false),
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
                        _sidePanel(showActions: showActions),
                      ],
                    ),
                  ),
                ],
              ),
            },
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding, Key? key}) {
    return Container(
      key: key,
      padding: padding ?? const EdgeInsets.all(20),
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
        ? _copy.template(
            'Reply to {author}',
            'Odpowiedz: {author}',
            values: {'author': widget.replyToAuthorName ?? 'Voice Moment'},
          )
        : _isReview
        ? _copy.text('Listen before publishing', 'Posłuchaj przed publikacją')
        : _copy.text('Share your voice', 'Podziel się swoim głosem');
    final subtitle = _isReply
        ? _copy.text(
            'Record a voice reply up to 60 seconds long.',
            'Nagraj odpowiedź głosową trwającą do 60 sekund.',
          )
        : _copy.text('Between 1 and 60 seconds.', 'Od 1 do 60 sekund.');

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
            height: 1.12,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (!_isReview) ...[
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: alignment,
            style: const TextStyle(color: _muted, fontSize: 14, height: 1.4),
          ),
        ],
      ],
    );
  }

  /// The stacked (phone/tablet) arrangement of whatever the current phase
  /// needs to show.
  List<Widget> _stage({
    required bool compact,
    required bool stackActions,
    required bool showActions,
  }) {
    switch (_phase) {
      case VoiceMomentRecordingPhase.checkingSupport:
        return [_card(child: _checkingCard())];
      case VoiceMomentRecordingPhase.unavailable:
        return [_unavailableCard()];
      default:
        return [
          if (_notice != null) ...[
            _noticeCard(_notice!),
            const SizedBox(height: 20),
          ],
          if (_isReview) ...[
            _previewPanel(),
            const SizedBox(height: 14),
            _statusLine(),
            const SizedBox(height: 20),
            _reviewFields(),
            if (showActions) ...[
              const SizedBox(height: 16),
              _actions(stacked: stackActions),
            ],
          ] else
            _capturePanel(compact: compact),
        ];
    }
  }

  /// The desktop right-hand column.
  Widget _sidePanel({required bool showActions}) {
    switch (_phase) {
      case VoiceMomentRecordingPhase.reviewing:
      case VoiceMomentRecordingPhase.publishing:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _reviewFields(),
            if (showActions) ...[
              const SizedBox(height: 16),
              _actions(stacked: false),
            ],
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

  Widget _capturePanel({required bool compact, bool showSilenceHint = true}) =>
      _card(
        key: const ValueKey('voice-moment-capture-stage'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _meterBlock(compact: compact, showSilenceHint: showSilenceHint),
            const SizedBox(height: 24),
            _recordButton(),
            const SizedBox(height: 20),
            _statusLine(),
            if (_phase == VoiceMomentRecordingPhase.requestingAccess) ...[
              const SizedBox(height: 6),
              _cancelAccessButton(),
            ],
          ],
        ),
      );

  Widget _reviewFields() => _card(
    key: const ValueKey('voice-moment-review-fields'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _captionField(),
        if (!_isReply) ...[const SizedBox(height: 20), _availabilitySelector()],
        if (_publishContractLocked &&
            _phase != VoiceMomentRecordingPhase.publishing) ...[
          const SizedBox(height: 12),
          _publishContractLockNotice(),
        ],
      ],
    ),
  );

  Widget _reviewActionBar(double width, {required bool wide}) {
    return Container(
      key: const ValueKey('voice-moment-review-action-bar'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: ResponsiveContentFrame(
        width: wide ? ResponsiveContentWidth.feed : ResponsiveContentWidth.form,
        fillHeight: false,
        padding: ResponsiveContentFrame.adaptivePagePadding(width),
        child: Align(
          alignment: wide ? AlignmentDirectional.centerEnd : Alignment.center,
          child: SizedBox(
            width: wide ? 480 : double.infinity,
            child: _actions(stacked: width < 600),
          ),
        ),
      ),
    );
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
              Text(
                _copy.text('Recording', 'Nagrywanie'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _liveRow(
            Icons.graphic_eq_rounded,
            _copy.text('Input level', 'Poziom wejścia'),
            _localizedMeterValue(_meterValue),
          ),
          const SizedBox(height: 10),
          _liveRow(
            Icons.timer_outlined,
            _copy.text('Remaining', 'Pozostało'),
            _formatDuration(_maxSeconds - _elapsedSeconds),
          ),
          if (_silenceDetected) ...[const SizedBox(height: 14), _silenceHint()],
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
            _copy.text(
              'Checking whether this device can record…',
              'Sprawdzamy, czy to urządzenie może nagrywać…',
            ),
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
                border: Border.all(color: _warning.withValues(alpha: .4)),
              ),
              child: const Icon(
                Icons.mic_off_rounded,
                color: _warning,
                size: 28,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _copy.text(
                'Recording is not available here',
                'Nagrywanie nie jest tutaj dostępne',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _supportMessage(support?.reason),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _muted,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            ...[
              const SizedBox(height: 12),
              Text(
                _supportAction(support?.reason),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppImmersiveColors.textPrimary,
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
                onPressed: _leave,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: _border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(_copy.text('Go back', 'Wróć')),
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
                    _noticeMessage(notice),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (_noticeAction(notice) != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      _noticeAction(notice)!,
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
    final points = <(IconData, String)>[
      (
        Icons.timer_outlined,
        _copy.text('Between 1 and 60 seconds.', 'Od 1 do 60 sekund.'),
      ),
      (
        Icons.headphones_outlined,
        _copy.text(
          'Somewhere quiet records best.',
          'Najlepszą jakość uzyskasz w cichym miejscu.',
        ),
      ),
      (
        Icons.public_outlined,
        _copy.text(
          'Published straight to your feed.',
          'Publikacja trafi bezpośrednio do Twojego kanału.',
        ),
      ),
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
          Text(
            _copy.text('Before you start', 'Zanim zaczniesz'),
            style: const TextStyle(
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
                value: _localizedMeterValue(_meterValue),
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
          label: _copy.text('Recording length', 'Długość nagrania'),
          value: _copy.template(
            '{elapsed} of {limit} seconds',
            '{elapsed} z {limit} sekund',
            values: {'elapsed': _elapsedSeconds, 'limit': _maxSeconds},
          ),
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

  Widget _previewPanel() {
    final publishing = _phase == VoiceMomentRecordingPhase.publishing;
    final total = _previewDuration > Duration.zero
        ? _previewDuration
        : Duration(seconds: math.max(1, _durationSeconds));
    final maximum = math.max(1, total.inMilliseconds).toDouble();
    final value = _previewPosition.inMilliseconds
        .clamp(0, maximum.round())
        .toDouble();

    return Container(
      key: const ValueKey('voice-moment-review-player'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: _inset,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                _copy.text('Your recording', 'Twoje nagranie'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                _formatDuration(total.inSeconds),
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Semantics(
                button: true,
                enabled: !publishing && !_previewBusy,
                excludeSemantics: true,
                label: _previewPlaying
                    ? _copy.text(
                        'Pause recording preview',
                        'Wstrzymaj podgląd nagrania',
                      )
                    : _copy.text(
                        'Play recording preview',
                        'Odtwórz podgląd nagrania',
                      ),
                onTap: publishing || _previewBusy ? null : _togglePreview,
                child: IconButton.filled(
                  key: const ValueKey('voice-preview-toggle'),
                  onPressed: publishing || _previewBusy ? null : _togglePreview,
                  tooltip: _previewPlaying
                      ? _copy.text('Pause preview', 'Wstrzymaj podgląd')
                      : _copy.text('Play preview', 'Odtwórz podgląd'),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(52, 52),
                    backgroundColor: _primary,
                    disabledBackgroundColor: _primary.withValues(alpha: .35),
                  ),
                  icon: _previewBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _previewPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  children: [
                    Semantics(
                      label: _copy.text(
                        'Recording preview position',
                        'Pozycja podglądu nagrania',
                      ),
                      child: Slider(
                        key: const ValueKey('voice-preview-seek'),
                        value: value,
                        max: maximum,
                        onChanged: publishing ? null : _setPreviewPosition,
                        onChangeEnd: publishing
                            ? null
                            : (next) => unawaited(_seekPreview(next)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${_formatDuration(_previewPosition.inSeconds.clamp(0, total.inSeconds))} '
                          '/ ${_formatDuration(total.inSeconds)}',
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 11.5,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_previewError != null) ...[
            const SizedBox(height: 10),
            Text(
              _previewError!,
              style: const TextStyle(
                color: _warning,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
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
              _copy.text(
                'No sound detected — check your microphone.',
                'Nie wykryto dźwięku — sprawdź mikrofon.',
              ),
              style: const TextStyle(
                color: AppImmersiveColors.textPrimary,
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
        child: Text(_copy.text('Cancel', 'Anuluj')),
      ),
    );
  }

  Widget _recordButton() {
    final recording = _phase == VoiceMomentRecordingPhase.recording;
    final requesting = _phase == VoiceMomentRecordingPhase.requestingAccess;
    final enabled = _phase == VoiceMomentRecordingPhase.idle || recording;

    final color = recording ? _live : _primary;

    // AccessibleTapRegion, not a bare InkWell: this screen paints an opaque
    // gradient and card over the Scaffold's root Material, so every ink
    // feature — focus ring included — landed on a covered canvas and
    // keyboard focus was invisible. It brings its own transparent Material
    // and paints the ring above the child.
    return Center(
      child: AccessibleTapRegion(
        onTap: enabled ? _toggleRecording : null,
        semanticLabel: recording
            ? _copy.text('Stop recording', 'Zatrzymaj nagrywanie')
            : _copy.text('Start recording', 'Rozpocznij nagrywanie'),
        circular: true,
        minimumSize: const Size(96, 96),
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled || requesting ? color : color.withValues(alpha: .35),
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
                  color: recording ? AppColors.onLive : Colors.white,
                  size: 38,
                ),
        ),
      ),
    );
  }

  Widget _statusLine() {
    final text = switch (_phase) {
      VoiceMomentRecordingPhase.requestingAccess => _copy.text(
        'Waiting for microphone access…',
        'Czekamy na dostęp do mikrofonu…',
      ),
      VoiceMomentRecordingPhase.recording => _copy.text(
        'Recording — tap to stop.',
        'Nagrywanie — dotknij, aby zatrzymać.',
      ),
      VoiceMomentRecordingPhase.reviewing => _copy.text(
        'Preview your take, then publish — or record again.',
        'Odsłuchaj nagranie, a potem opublikuj je lub nagraj ponownie.',
      ),
      VoiceMomentRecordingPhase.publishing => _copy.text(
        'Publishing your Voice Moment…',
        'Publikujemy Twój Voice Moment…',
      ),
      _ => _copy.text(
        'Tap the microphone to start.',
        'Dotknij mikrofonu, aby rozpocząć.',
      ),
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
    return KeyedSubtree(
      key: _captionFieldKey,
      child: TextField(
        key: const ValueKey('voice-moment-caption'),
        focusNode: _captionFocus,
        controller: _captionController,
        enabled:
            _phase != VoiceMomentRecordingPhase.publishing &&
            !_publishContractLocked,
        maxLength: _captionMaxLength,
        maxLines: 3,
        minLines: 3,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          // A real label, not just a hint: a hint is the field's only
          // accessible name until the user types, and then it disappears
          // and the field becomes anonymous.
          labelText: _copy.text('Caption', 'Opis'),
          labelStyle: const TextStyle(color: _muted),
          floatingLabelStyle: const TextStyle(
            color: AppImmersiveColors.textPrimary,
          ),
          hintText: _copy.text('Add a caption…', 'Dodaj opis…'),
          hintStyle: const TextStyle(color: _muted),
          counterStyle: const TextStyle(color: _muted),
          // The visible counter is a detached node that screen readers do
          // not associate with the field; this is what is actually read.
          semanticCounterText: _copy.template(
            '{count} of {limit} characters',
            '{count} z {limit} znaków',
            values: {
              'count': _captionController.text.length,
              'limit': _captionMaxLength,
            },
          ),
          filled: true,
          fillColor: _inset,
          // Stated explicitly rather than left to `border:`, which the
          // production InputDecorationTheme's enabled/focused borders
          // override — the harness and the app were not showing the same
          // field. A visible boundary and a real focus ring are also what
          // 1.4.11 and 2.4.7 ask for.
          border: _captionBorder(_controlBorder),
          enabledBorder: _captionBorder(_controlBorder),
          focusedBorder: _captionBorder(_primary, width: 2),
          disabledBorder: _captionBorder(_controlBorder.withValues(alpha: .5)),
        ),
      ),
    );
  }

  static OutlineInputBorder _captionBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  /// A custom, server-validated visibility window. Timed Moments accept a
  /// whole number of hours (24–720) or days (1–30); the other explicit mode
  /// stays visible until the author deletes it.
  Widget _availabilitySelector() {
    final publishing = _phase == VoiceMomentRecordingPhase.publishing;
    final enabled = !publishing && !_publishContractLocked;
    final validTimed = _readTimedAvailability();
    final amount = int.tryParse(_availabilityAmountController.text.trim());
    final timedCopy = validTimed == null || amount == null
        ? _copy.text(
            'Choose how long this Moment stays visible in the feed.',
            'Wybierz, jak długo ten Moment ma być widoczny w kanale.',
          )
        : _copy.template(
            'Visibility: {hours} h',
            'Widoczność: {hours} godz.',
            values: {
              'hours': _availabilityUnit == _AvailabilityUnit.days
                  ? amount * 24
                  : amount,
            },
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _copy.text('Available for', 'Dostępny przez'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _untilDeleted
              ? _copy.text(
                  'This Moment will stay visible in the feed until you delete it.',
                  'Ten Moment pozostanie widoczny w kanale, dopóki go nie usuniesz.',
                )
              : timedCopy,
          style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final stacked = constraints.maxWidth < 310 || textScale >= 1.6;
            final timed = _AvailabilityModeButton(
              key: const ValueKey('availability-timed'),
              label: _copy.text('Timed', 'Na określony czas'),
              icon: Icons.schedule_rounded,
              selected: !_untilDeleted,
              enabled: enabled,
              onTap: () => _setUntilDeleted(false),
            );
            final permanent = _AvailabilityModeButton(
              key: const ValueKey('availability-permanent'),
              label: _copy.text('Until deleted', 'Do usunięcia'),
              icon: Icons.all_inclusive_rounded,
              selected: _untilDeleted,
              enabled: enabled,
              onTap: () => _setUntilDeleted(true),
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [timed, const SizedBox(height: 8), permanent],
              );
            }
            return Row(
              children: [
                Expanded(child: timed),
                const SizedBox(width: 8),
                Expanded(child: permanent),
              ],
            );
          },
        ),
        if (!_untilDeleted) ...[
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              final stacked = constraints.maxWidth < 330 || textScale >= 1.5;
              final amountField = KeyedSubtree(
                key: _availabilityAmountKey,
                child: TextField(
                  key: const ValueKey('availability-amount'),
                  controller: _availabilityAmountController,
                  focusNode: _availabilityAmountFocus,
                  enabled: enabled,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: _copy.text('Duration', 'Czas'),
                    labelStyle: const TextStyle(color: _muted),
                    floatingLabelStyle: const TextStyle(
                      color: AppImmersiveColors.textPrimary,
                    ),
                    errorText: _availabilityError,
                    filled: true,
                    fillColor: _inset,
                    border: _captionBorder(_controlBorder),
                    enabledBorder: _captionBorder(_controlBorder),
                    focusedBorder: _captionBorder(_primary, width: 2),
                    disabledBorder: _captionBorder(
                      _controlBorder.withValues(alpha: .5),
                    ),
                  ),
                ),
              );
              final unitField = DropdownButtonFormField<_AvailabilityUnit>(
                key: const ValueKey('availability-unit'),
                initialValue: _availabilityUnit,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _copy.text('Unit', 'Jednostka'),
                  labelStyle: const TextStyle(color: _muted),
                  floatingLabelStyle: const TextStyle(
                    color: AppImmersiveColors.textPrimary,
                  ),
                  filled: true,
                  fillColor: _inset,
                  border: _captionBorder(_controlBorder),
                  enabledBorder: _captionBorder(_controlBorder),
                  focusedBorder: _captionBorder(_primary, width: 2),
                  disabledBorder: _captionBorder(
                    _controlBorder.withValues(alpha: .5),
                  ),
                ),
                dropdownColor: _surface,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.white),
                iconEnabledColor: _muted,
                iconDisabledColor: AppImmersiveColors.textTertiary,
                items: [
                  DropdownMenuItem(
                    value: _AvailabilityUnit.hours,
                    child: Text(_copy.text('Hours', 'Godziny')),
                  ),
                  DropdownMenuItem(
                    value: _AvailabilityUnit.days,
                    child: Text(_copy.text('Days', 'Dni')),
                  ),
                ],
                onChanged: enabled
                    ? (unit) {
                        if (unit != null) _setAvailabilityUnit(unit);
                      }
                    : null,
              );
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    amountField,
                    const SizedBox(height: 10),
                    unitField,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: amountField),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: unitField),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _publishContractLockNotice() {
    return Text(
      _isReply
          ? _copy.text(
              'Caption is locked for this retry.',
              'Opis jest zablokowany podczas tej ponownej próby.',
            )
          : _copy.text(
              'Caption and availability are locked for this retry.',
              'Opis i czas dostępności są zablokowane podczas tej ponownej '
                  'próby.',
            ),
      style: const TextStyle(color: _muted, fontSize: 11.5, height: 1.35),
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

    final again = OutlinedButton(
      onPressed: publishing ? _ignoreWhileBusy : _recordAgain,
      style:
          OutlinedButton.styleFrom(
            foregroundColor: publishing ? Colors.white38 : Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ).copyWith(
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.focused)) {
                return const BorderSide(
                  color: AppImmersiveColors.textPrimary,
                  width: 2,
                );
              }
              return BorderSide(
                color: publishing ? _border.withValues(alpha: .5) : _border,
              );
            }),
          ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.refresh_rounded),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _copy.text('Record again', 'Nagraj ponownie'),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );

    final publish = FilledButton(
      key: _publishKey,
      focusNode: _publishFocus,
      onPressed: publishing ? _ignoreWhileBusy : _publish,
      style: FilledButton.styleFrom(
        backgroundColor: publishing ? _primary.withValues(alpha: .5) : _primary,
        foregroundColor: publishing ? Colors.white70 : Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 15),
        // The painted height, not just the padded hit area: docs/UI.md's
        // 44x44 floor is about what the user can see and aim at.
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (publishing)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          else
            const Icon(Icons.publish_rounded),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              publishing
                  ? _copy.text('Publishing…', 'Publikowanie…')
                  : (_notice?.problem == VoiceRecordingProblem.uploadFailed
                        ? _copy.text('Try again', 'Spróbuj ponownie')
                        : _copy.text('Publish', 'Opublikuj')),
              textAlign: TextAlign.center,
            ),
          ),
        ],
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

/// One lifetime mode with a visible boundary, selected state and 48-pt target.
class _AvailabilityModeButton extends StatelessWidget {
  const _AvailabilityModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: copy.template(
        'Availability: {label}',
        'Dostępność: {label}',
        values: {'label': label},
      ),
      child: Material(
        color: selected
            ? AppColors.primary
            : AppImmersiveColors.background.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? AppColors.primary
                    : AppImmersiveColors.textTertiary.withValues(
                        alpha: enabled ? 1 : .5,
                      ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: selected
                      ? AppImmersiveColors.textPrimary
                      : AppImmersiveColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? AppImmersiveColors.textPrimary
                          : (enabled
                                ? AppImmersiveColors.textSecondary
                                : AppImmersiveColors.textTertiary),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
    final copy = AppLocalizations.of(context);
    // Show the most recent [barCount] samples, oldest on the left.
    final start = math.max(0, levels.length - barCount);
    final visible = levels.sublist(start);

    return Semantics(
      label: live
          ? copy.text('Microphone level', 'Poziom mikrofonu')
          : copy.text(
              'Microphone level, not recording',
              'Poziom mikrofonu, nagrywanie wyłączone',
            ),
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
