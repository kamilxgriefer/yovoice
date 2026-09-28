import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:yovoice/features/reels/data/services/yeels_posted_flag.dart';

/// The schedule of the Yeels create ring's invitation echo (ADR-229).
///
/// The owner asked for a gentle, occasional pulse "to invite users to add
/// their own Yeel". Bounds:
///
/// * a **visit** starts each time the Yeels format becomes visible — the
///   format selected, the destination's tab shown and the app in the
///   foreground — and ends when any of those stops;
/// * the first echo comes [firstDelay] into a visit, then one every
///   [interval], at most [maxPerVisit] per visit;
/// * nothing while [update]'s `paused` holds (a sheet, a dialog or the
///   composer covers the destination, or the feed's own empty state already
///   offers "Create Yeel"); the next echo is re-timed from the moment the
///   pause ends, and the visit's count is kept;
/// * once the viewer has engaged with creating ([noteEngaged]: the create
///   chooser or the composer opened), the rest of that visit stays quiet —
///   the invitation was answered; the next visit may invite again;
/// * never again for an account once [YeelsPostedFlag] knows it has posted
///   a Yeel, and never before the viewer is known.
///
/// It only emits events: [echoes] changes once per echo, and the ring
/// (`YoCreateRingButton`) animates once per change. Reduce Motion, high
/// contrast and a disabled button are the ring's to refuse. Only one-shot
/// [Timer]s are used and [dispose] cancels them, so nothing is pending when
/// the host goes away and nothing ticks between echoes.
class YeelsCreateInvitation {
  YeelsCreateInvitation({
    YeelsPostedFlag? postedFlag,
    this.firstDelay = defaultFirstDelay,
    this.interval = defaultInterval,
    this.maxPerVisit = defaultMaxPerVisit,
  }) : _flag = postedFlag ?? YeelsPostedFlag.instance {
    _flag.addListener(_flagChanged);
    _foreground = _isForeground(WidgetsBinding.instance.lifecycleState);
    _lifecycle = AppLifecycleListener(onStateChange: _lifecycleChanged);
  }

  static const Duration defaultFirstDelay = Duration(seconds: 3);
  static const Duration defaultInterval = Duration(seconds: 40);
  static const int defaultMaxPerVisit = 3;

  final Duration firstDelay;
  final Duration interval;
  final int maxPerVisit;

  final YeelsPostedFlag _flag;
  late final AppLifecycleListener _lifecycle;
  final ValueNotifier<int> _echoes = ValueNotifier<int>(0);

  bool _visible = false;
  bool _paused = false;
  bool _foreground = true;
  String? _viewer;

  /// Null while the viewer's flag is being read.
  bool? _posted;
  int _readGeneration = 0;
  int _echoesThisVisit = 0;
  Timer? _timer;
  bool _disposed = false;

  /// Changes once per echo; the ring plays one echo per change.
  ValueListenable<int> get echoes => _echoes;

  /// Echoes emitted in the current visit.
  int get echoesThisVisit => _echoesThisVisit;

  /// True while the next echo is scheduled.
  @visibleForTesting
  bool get isScheduled => _timer?.isActive ?? false;

  bool get _onScreen => _visible && _foreground;

  bool get _eligible =>
      !_disposed &&
      _onScreen &&
      !_paused &&
      _viewer != null &&
      _posted == false &&
      _echoesThisVisit < maxPerVisit;

  /// [visible]: the Yeels format is the one on screen (format selected and
  /// the destination shown). [paused]: something covers it for a while.
  void update({required bool visible, required bool paused}) {
    if (_disposed) return;
    final wasOnScreen = _onScreen;
    final wasPaused = _paused;
    _visible = visible;
    _paused = paused;
    _onScreenChanged(wasOnScreen);
    if (wasPaused != paused) _reschedule();
  }

  /// The signed-in viewer (null when signed out).
  void setViewer(String? userId) {
    if (_disposed) return;
    final id = userId?.trim();
    final viewer = id == null || id.isEmpty ? null : id;
    if (viewer == _viewer) return;
    _viewer = viewer;
    _posted = null;
    _cancel();
    final generation = ++_readGeneration;
    if (viewer == null) return;
    if (_flag.knows(viewer)) {
      _posted = true;
      return;
    }
    unawaited(
      _flag.hasPosted(viewer).then((posted) {
        if (_disposed || generation != _readGeneration) return;
        _posted = posted || _flag.knows(viewer);
        _reschedule();
      }),
    );
  }

  /// The viewer opened the create chooser or the composer during this
  /// visit: no more echoes until the next visit. A no-op off screen, since a
  /// new visit starts its count over anyway.
  void noteEngaged() {
    if (_disposed || !_onScreen) return;
    _echoesThisVisit = maxPerVisit;
    _cancel();
  }

  /// A feed the app already loaded showed [userId]'s own Yeel.
  void noteOwnYeel(String userId) => unawaited(_flag.markPosted(userId));

  /// The composer published a Yeel for the current viewer.
  void markViewerPosted() {
    final viewer = _viewer;
    if (viewer != null) unawaited(_flag.markPosted(viewer));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancel();
    _flag.removeListener(_flagChanged);
    _lifecycle.dispose();
    _echoes.dispose();
  }

  static bool _isForeground(AppLifecycleState? state) => switch (state) {
    AppLifecycleState.hidden ||
    AppLifecycleState.paused ||
    AppLifecycleState.detached => false,
    // `inactive` is transient (a system sheet, an incoming call banner): it
    // does not end a visit.
    AppLifecycleState.resumed || AppLifecycleState.inactive || null => true,
  };

  void _lifecycleChanged(AppLifecycleState state) {
    if (_disposed) return;
    final wasOnScreen = _onScreen;
    _foreground = _isForeground(state);
    _onScreenChanged(wasOnScreen);
  }

  void _onScreenChanged(bool wasOnScreen) {
    final onScreen = _onScreen;
    if (onScreen == wasOnScreen) return;
    if (onScreen) {
      // A new visit.
      _echoesThisVisit = 0;
      _reschedule();
    } else {
      _cancel();
    }
  }

  void _flagChanged() {
    final viewer = _viewer;
    if (viewer == null || !_flag.knows(viewer)) return;
    _posted = true;
    _cancel();
  }

  void _reschedule() {
    if (!_eligible) {
      _cancel();
      return;
    }
    if (_timer?.isActive ?? false) return;
    _timer = Timer(_echoesThisVisit == 0 ? firstDelay : interval, _fire);
  }

  void _fire() {
    _timer = null;
    if (!_eligible) return;
    _echoesThisVisit++;
    _echoes.value++;
    _reschedule();
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
