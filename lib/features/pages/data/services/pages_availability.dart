import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Calls one Pages callable by [name] with the exact request [payload] and
/// returns the raw response data. Tests inject one; production uses
/// `europe-west1` Cloud Functions.
typedef PagesCallableInvoker =
    Future<Object?> Function(String name, Map<String, Object?> payload);

/// What one availability probe learned.
enum PagesProbeOutcome {
  /// The callable answered: `appConfig/pagesV1` lets this account read Pages.
  enabled,

  /// The server refused with `failed-precondition` + `pagesNotEnabled`, or
  /// the callable is not deployed (`not-found`), or there is no session.
  disabled,

  /// Anything else (offline, rate limit, a transient server error). The
  /// last known answer stands.
  unknown,
}

/// The last known answer per account, so a cold start shows the same dock
/// the previous session ended with instead of flashing five tabs first.
abstract interface class PagesAvailabilityStore {
  Future<bool?> read(String userId);
  Future<void> write(String userId, {required bool enabled});
}

final class SharedPreferencesPagesAvailabilityStore
    implements PagesAvailabilityStore {
  const SharedPreferencesPagesAvailabilityStore();

  static String _key(String userId) => 'pages.availability.v1.$userId';

  @override
  Future<bool?> read(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_key(userId));
  }

  @override
  Future<void> write(String userId, {required bool enabled}) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_key(userId), enabled);
  }
}

/// Whether Premium Pages ("Treści") exist for the signed-in account.
///
/// `appConfig/pagesV1` is server-only: rules deny every client read, so the
/// client learns the activation the only way the wire contract allows — by
/// asking a Pages read callable and reading the refusal (spec premium-pages
/// §2.1). The probe is `findPagesV1 {mode:"following"}`: its activation
/// check runs before the rate budget, so a refused account costs one config
/// read, and an enabled one pages through at most 20 followed Pages. The
/// desktop Treści panel calls the same mode.
///
/// Until a probe says otherwise the answer is **disabled**, so the Treści
/// tab, the rail row and Page deep links stay hidden (fail closed). This is a
/// presentation gate only; every Pages callable re-checks activation.
class PagesAvailability {
  PagesAvailability({
    FirebaseFunctions? functions,
    PagesCallableInvoker? invoker,
    PagesAvailabilityStore store =
        const SharedPreferencesPagesAvailabilityStore(),
    DateTime Function()? clock,
  }) : _functionsOverride = functions,
       _invoker = invoker,
       _store = store,
       _clock = clock ?? DateTime.now;

  /// The app-wide instance the shell and the Pages screens share.
  static final PagesAvailability instance = PagesAvailability();

  /// The callable and exact request of the probe (spec §2.7).
  static const probeCallable = 'findPagesV1';
  static const probePayload = <String, Object?>{
    'mode': 'following',
    'query': null,
    'cursor': null,
  };

  /// A settled answer is re-checked at most this often (app resume, a new
  /// shell). The kill switch still reaches an open session sooner through
  /// [reportNotEnabled] from any Pages call.
  static const refreshInterval = Duration(hours: 1);

  /// After an inconclusive probe (offline; on the web an undeployed or
  /// CORS-failing callable answers `internal`), resumes and tab focus wait
  /// this long before asking again instead of calling on every one.
  static const unknownBackoff = Duration(minutes: 5);

  final FirebaseFunctions? _functionsOverride;
  final PagesCallableInvoker? _invoker;
  final PagesAvailabilityStore _store;
  final DateTime Function() _clock;

  final ValueNotifier<bool> _enabled = ValueNotifier<bool>(false);
  String _userId = '';
  DateTime? _probedAt;
  DateTime? _unknownAt;
  Future<bool>? _inFlight;

  /// True only while Pages are enabled for [userId] (the current account).
  ValueListenable<bool> get enabled => _enabled;

  String get userId => _userId;

  /// Resolves the answer for [userId]. Switching accounts drops the previous
  /// account's answer synchronously, before any await, so nothing from one
  /// session leaks into the next.
  Future<bool> refresh(String userId, {bool force = false}) {
    if (userId != _userId) {
      _userId = userId;
      _probedAt = null;
      _unknownAt = null;
      _inFlight = null;
      _enabled.value = false;
    }
    if (userId.isEmpty) return Future<bool>.value(false);
    final probedAt = _probedAt;
    final now = _clock();
    if (!force &&
        probedAt != null &&
        now.difference(probedAt) < refreshInterval) {
      return Future<bool>.value(_enabled.value);
    }
    final unknownAt = _unknownAt;
    if (!force &&
        unknownAt != null &&
        now.difference(unknownAt) < unknownBackoff) {
      return Future<bool>.value(_enabled.value);
    }
    return _inFlight ??= _resolve(userId).whenComplete(() {
      if (_userId == userId) _inFlight = null;
    });
  }

  Future<bool> _resolve(String userId) async {
    if (_probedAt == null) {
      try {
        final cached = await _store.read(userId);
        if (_userId == userId && cached != null && _probedAt == null) {
          _enabled.value = cached;
        }
      } catch (_) {
        // No local answer: stay disabled until the probe answers.
      }
    }
    final outcome = await probe();
    if (_userId != userId) return false;
    switch (outcome) {
      case PagesProbeOutcome.enabled:
        _set(userId, enabled: true);
      case PagesProbeOutcome.disabled:
        _set(userId, enabled: false);
      case PagesProbeOutcome.unknown:
        _unknownAt = _clock();
    }
    return _enabled.value;
  }

  void _set(String userId, {required bool enabled}) {
    _probedAt = _clock();
    _unknownAt = null;
    _enabled.value = enabled;
    unawaited(
      _store.write(userId, enabled: enabled).catchError((Object _) {
        // A lost cache only costs the next cold start one probe.
      }),
    );
  }

  /// Any Pages call that got `pagesNotEnabled` reports it here, so the kill
  /// switch hides Treści in an open session without waiting for a refresh.
  void reportNotEnabled() {
    if (_userId.isEmpty) return;
    _set(_userId, enabled: false);
  }

  /// Sign-out: nothing of the previous account's answer survives.
  void reset() {
    _userId = '';
    _probedAt = null;
    _unknownAt = null;
    _inFlight = null;
    _enabled.value = false;
  }

  /// One probe call. Never throws.
  @visibleForTesting
  Future<PagesProbeOutcome> probe() async {
    try {
      final injected = _invoker;
      if (injected != null) {
        await injected(probeCallable, probePayload);
      } else {
        final functions =
            _functionsOverride ??
            FirebaseFunctions.instanceFor(region: 'europe-west1');
        await functions
            .httpsCallable(probeCallable)
            .call<Object?>(probePayload);
      }
      return PagesProbeOutcome.enabled;
    } on FirebaseFunctionsException catch (error) {
      return outcomeFor(error);
    } catch (_) {
      return PagesProbeOutcome.unknown;
    }
  }

  /// Maps a probe refusal (spec §2.1 refusal envelope).
  static PagesProbeOutcome outcomeFor(FirebaseFunctionsException error) {
    final details = error.details;
    final reason = details is Map ? details['reason'] : null;
    return switch (error.code) {
      'failed-precondition' when reason == 'pagesNotEnabled' =>
        PagesProbeOutcome.disabled,
      // Not deployed yet, or no session: nothing to show.
      'not-found' || 'unauthenticated' => PagesProbeOutcome.disabled,
      _ => PagesProbeOutcome.unknown,
    };
  }
}
