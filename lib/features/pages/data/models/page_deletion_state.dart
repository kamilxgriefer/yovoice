import 'package:flutter/foundation.dart';

/// Where an owner's Page deletion stands (ADR-236).
enum PageDeletionPhase {
  /// Hidden from everybody else; the owner can restore it until the
  /// deletion date.
  pending,

  /// The purge has started (the 30 days passed, or "delete now"): posts,
  /// followers and then the Page are being removed. Nothing can be restored.
  purging,
}

/// The pending deletion of a Page.
@immutable
class PageDeletionInfo {
  const PageDeletionInfo({
    required this.phase,
    required this.requestedAt,
    required this.deleteAt,
  });

  final PageDeletionPhase phase;
  final DateTime requestedAt;

  /// The day the Page is removed for good (request + 30 days).
  final DateTime deleteAt;

  @override
  bool operator ==(Object other) =>
      other is PageDeletionInfo &&
      other.phase == phase &&
      other.requestedAt == requestedAt &&
      other.deleteAt == deleteAt;

  @override
  int get hashCode => Object.hash(phase, requestedAt, deleteAt);
}

/// `managePageDeletionV1` → the caller's own deletion state, the one result
/// shape of every op:
///
///     {schemaVersion, pageId, pageExists, pagePaused: null | bool,
///      deletion: null | {state, requestedAtMs, deleteAtMs},
///      postsClearing: null | {requestedAtMs},
///      recreateAllowedAtMs: null | int}
///
/// Parsed like every Pages response (spec §2.5): known keys are required,
/// unknown keys are ignored. An unknown `deletion.state` reads as
/// [PageDeletionPhase.purging], the most restrictive one, so a newer
/// server can never make this client offer a restore that is not there.
@immutable
class PageDeletionState {
  const PageDeletionState({
    required this.pageId,
    required this.pageExists,
    this.pagePaused,
    this.deletion,
    this.postsClearingSince,
    this.recreateAllowedAt,
  });

  final String pageId;
  final bool pageExists;

  /// Whether the owner's Page is paused right now; null when there is no
  /// Page. After "Przywróć stronę" it tells the two outcomes apart: the
  /// deletion is always cancelled, but the Page only goes back on air when
  /// it was running before and today's rules allow it (live Premium or
  /// VIP, a public profile); otherwise it stays an ordinary paused Page.
  final bool? pagePaused;
  final PageDeletionInfo? deletion;

  /// "Delete all posts" is still running for posts created at or before
  /// this instant; null when no such job runs.
  final DateTime? postsClearingSince;

  /// A new Page can be created from this instant (7 days after the old one
  /// was removed); null when there is no cooldown.
  final DateTime? recreateAllowedAt;

  bool get pending => deletion?.phase == PageDeletionPhase.pending;
  bool get purging => deletion?.phase == PageDeletionPhase.purging;

  static DateTime _instant(Object? value, String what) {
    if (value is! int || value < 0) throw FormatException('$what: instant');
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }

  static PageDeletionState fromWire(Object? raw) {
    const what = 'PageDeletionState';
    if (raw is! Map) throw const FormatException('$what: not an object');
    for (final key in const [
      'pageId',
      'pageExists',
      'pagePaused',
      'deletion',
      'postsClearing',
      'recreateAllowedAtMs',
    ]) {
      if (!raw.containsKey(key)) throw FormatException('$what: $key');
    }
    final pageId = raw['pageId'];
    final pageExists = raw['pageExists'];
    final pagePaused = raw['pagePaused'];
    if (pageId is! String || pageId.isEmpty || pageExists is! bool) {
      throw const FormatException('$what: identity');
    }
    if (pagePaused != null && pagePaused is! bool) {
      throw const FormatException('$what: pagePaused');
    }
    PageDeletionInfo? deletion;
    final deletionRaw = raw['deletion'];
    if (deletionRaw != null) {
      if (deletionRaw is! Map) throw const FormatException('$what: deletion');
      deletion = PageDeletionInfo(
        phase: deletionRaw['state'] == 'pending'
            ? PageDeletionPhase.pending
            : PageDeletionPhase.purging,
        requestedAt: _instant(deletionRaw['requestedAtMs'], what),
        deleteAt: _instant(deletionRaw['deleteAtMs'], what),
      );
    }
    DateTime? clearing;
    final clearingRaw = raw['postsClearing'];
    if (clearingRaw != null) {
      if (clearingRaw is! Map) {
        throw const FormatException('$what: postsClearing');
      }
      clearing = _instant(clearingRaw['requestedAtMs'], what);
    }
    final recreate = raw['recreateAllowedAtMs'];
    return PageDeletionState(
      pageId: pageId,
      pageExists: pageExists,
      pagePaused: pagePaused as bool?,
      deletion: deletion,
      postsClearingSince: clearing,
      recreateAllowedAt: recreate == null ? null : _instant(recreate, what),
    );
  }

  /// The compact form [PageDeletionStore] keeps per device.
  Map<String, Object?> toStored() => <String, Object?>{
    'pageId': pageId,
    'pageExists': pageExists,
    'pagePaused': pagePaused,
    'deletion': deletion == null
        ? null
        : <String, Object?>{
            'state': deletion!.phase == PageDeletionPhase.pending
                ? 'pending'
                : 'purging',
            'requestedAtMs': deletion!.requestedAt.millisecondsSinceEpoch,
            'deleteAtMs': deletion!.deleteAt.millisecondsSinceEpoch,
          },
    'postsClearing': postsClearingSince == null
        ? null
        : <String, Object?>{
            'requestedAtMs': postsClearingSince!.millisecondsSinceEpoch,
          },
    'recreateAllowedAtMs': recreateAllowedAt?.millisecondsSinceEpoch,
  };

  /// Nothing is pending, running or cooling down: not worth remembering.
  bool get isIdle =>
      deletion == null &&
      postsClearingSince == null &&
      recreateAllowedAt == null;

  @override
  bool operator ==(Object other) =>
      other is PageDeletionState &&
      other.pageId == pageId &&
      other.pageExists == pageExists &&
      other.pagePaused == pagePaused &&
      other.deletion == deletion &&
      other.postsClearingSince == postsClearingSince &&
      other.recreateAllowedAt == recreateAllowedAt;

  @override
  int get hashCode => Object.hash(
    pageId,
    pageExists,
    pagePaused,
    deletion,
    postsClearingSince,
    recreateAllowedAt,
  );
}
