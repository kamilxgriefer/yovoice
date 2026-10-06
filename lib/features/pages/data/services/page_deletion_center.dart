import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/features/pages/data/models/page_deletion_state.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';

/// The last deletion state this device saw, per account. It only decides
/// what to draw before the server answers (the "Do usunięcia" banner on a
/// cold start, the cooldown check before the create flow); the server is
/// asked again on every screen that shows it.
abstract interface class PageDeletionStore {
  Future<PageDeletionState?> read(String userId);
  Future<void> write(String userId, PageDeletionState? state);
}

final class SharedPreferencesPageDeletionStore implements PageDeletionStore {
  const SharedPreferencesPageDeletionStore();

  static String _key(String userId) => 'pages.deletion.v1.$userId';

  @override
  Future<PageDeletionState?> read(String userId) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_key(userId));
      if (raw == null) return null;
      final state = PageDeletionState.fromWire(jsonDecode(raw));
      return state.pageId == userId ? state : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String userId, PageDeletionState? state) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (state == null || state.isIdle) {
        await preferences.remove(_key(userId));
      } else {
        await preferences.setString(_key(userId), jsonEncode(state.toStored()));
      }
    } catch (_) {
      // A cache: losing a write only costs one flicker on the next start.
    }
  }
}

/// An in-memory store for tests and previews.
final class MemoryPageDeletionStore implements PageDeletionStore {
  final Map<String, PageDeletionState> states = <String, PageDeletionState>{};

  @override
  Future<PageDeletionState?> read(String userId) async => states[userId];

  @override
  Future<void> write(String userId, PageDeletionState? state) async {
    if (state == null || state.isIdle) {
      states.remove(userId);
    } else {
      states[userId] = state;
    }
  }
}

/// The signed-in owner's Page deletion state (ADR-236), shared by Page
/// settings, the Page profile and the create entry: one place asks
/// `managePageDeletionV1`, remembers the answer and tells every listener.
///
/// It is UX state only. Every op is decided by the server; a stale value
/// here costs a refusal, never a deletion.
class PageDeletionCenter extends ChangeNotifier {
  PageDeletionCenter({
    PagesService? service,
    PageDeletionStore? store,
    String Function()? userId,
  }) : _serviceOverride = service,
       _store = store ?? const SharedPreferencesPageDeletionStore(),
       _userIdOverride = userId;

  /// The app-wide instance.
  static final PageDeletionCenter instance = PageDeletionCenter();

  final PagesService? _serviceOverride;
  final PageDeletionStore _store;
  final String Function()? _userIdOverride;

  PagesService get _service => _serviceOverride ?? PagesService.instance;

  String _owner = '';
  PageDeletionState? _state;
  bool _resolved = false;
  bool _restored = false;
  Future<PageDeletionState?>? _refreshing;
  bool _disposed = false;

  String get _userId {
    final override = _userIdOverride;
    if (override != null) return override();
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Drops another account's state after a sign-out or an account switch.
  void _syncOwner() {
    final uid = _userId;
    if (uid == _owner) return;
    _owner = uid;
    _state = null;
    _resolved = false;
    _restored = false;
    _refreshing = null;
  }

  /// The last known state of the signed-in account, or null when nothing
  /// is known yet.
  PageDeletionState? get state {
    _syncOwner();
    return _state;
  }

  /// A server answer arrived in this session.
  bool get resolved {
    _syncOwner();
    return _resolved;
  }

  void _publish(PageDeletionState? next, {required bool fromServer}) {
    final changed = next != _state || (fromServer && !_resolved);
    _state = next;
    if (fromServer) _resolved = true;
    if (changed && !_disposed) notifyListeners();
  }

  /// Shows what this device remembered, until the server answers.
  Future<void> _restore() async {
    if (_restored) return;
    _restored = true;
    final uid = _owner;
    if (uid.isEmpty) return;
    final stored = await _store.read(uid);
    if (stored != null && !_resolved && uid == _owner) {
      _publish(stored, fromServer: false);
    }
  }

  /// What this device remembered for the signed-in account, without asking
  /// the server (the create entry's fast path).
  Future<PageDeletionState?> remembered() async {
    _syncOwner();
    await _restore();
    return _state;
  }

  /// Asks the server. Never throws: a failed read keeps what is known and
  /// answers null. Concurrent calls share one request.
  Future<PageDeletionState?> refresh() {
    _syncOwner();
    final uid = _owner;
    if (uid.isEmpty) return Future<PageDeletionState?>.value();
    return _refreshing ??= () async {
      try {
        await _restore();
        final state = await _service.managePageDeletion(PageDeletionOp.status);
        if (uid != _owner || state.pageId != uid) return null;
        _publish(state, fromServer: true);
        unawaited(_store.write(uid, state));
        return state;
      } on PagesException {
        return null;
      } finally {
        if (uid == _owner) _refreshing = null;
      }
    }();
  }

  /// When a new Page may be created, if a deletion this device knows about
  /// still blocks it (the 7-day pause, ADR-236); null when nothing does.
  ///
  /// An account this device never saw deleting a Page costs no request: the
  /// server refuses a create during the pause anyway
  /// ([PagesFailure.recreateCooldown]).
  Future<DateTime?> recreateBlockedUntil({DateTime Function()? clock}) async {
    final known = await remembered();
    if (known == null || known.isIdle) return null;
    final fresh = await refresh();
    final until = (fresh ?? known).recreateAllowedAt;
    if (until == null) return null;
    return until.isAfter((clock ?? DateTime.now)()) ? until : null;
  }

  Future<PageDeletionState> _run(PageDeletionOp op) async {
    _syncOwner();
    final uid = _owner;
    final state = await _service.managePageDeletion(op);
    if (uid == _owner && state.pageId == uid) {
      _publish(state, fromServer: true);
      unawaited(_store.write(uid, state));
    }
    return state;
  }

  /// Hides the Page now and schedules its deletion in 30 days.
  Future<PageDeletionState> requestDeletion() => _run(PageDeletionOp.request);

  /// Takes a pending deletion back. Throws [PagesException]
  /// ([PagesFailure.accessRequired] without live Premium or VIP).
  Future<PageDeletionState> restore() => _run(PageDeletionOp.restore);

  /// Deletes the Page now instead of waiting; cannot be undone.
  Future<PageDeletionState> purgeNow() => _run(PageDeletionOp.purgeNow);

  /// Deletes every post; the Page and its followers stay.
  Future<PageDeletionState> clearPosts() => _run(PageDeletionOp.clearPosts);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
