import 'dart:async';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'package:yovoice/core/security/ephemeral_media_access_registry.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/services/pages_availability.dart';
import 'package:yovoice/shared/identity/public_identity.dart';

/// Why a Pages call failed, mapped from the server's refusal envelope
/// (spec premium-pages §4.8). Screens choose their copy from this, never
/// from a raw message.
enum PagesFailure {
  /// `pagesNotEnabled`: the kill switch or the cohort (§2.1).
  notEnabled,

  /// `pageAccessRequired`: YO Voice VIP is required to run a Page.
  accessRequired,

  /// `pageUnavailable` (uniform refusal, §2.5) or a bare permission-denied.
  unavailable,

  /// The Page is read-only for this action (D14).
  readOnly,
  budget,
  profileNotPublic,
  adultRequired,
  pageExists,
  hasAudience,
  nameReserved,
  mediaMetadata,
  commentLinks,

  /// `pageLinkedServerInvalid`: the linked server is not an active, public
  /// Community or Podcast server the caller owns.
  linkedServerInvalid,

  /// `invalid-argument`: a field the server refused (a malformed website,
  /// e-mail or phone, an over-long text).
  invalidInput,

  /// `resource-exhausted`: a rate budget.
  rateLimited,

  /// `pageCommentsOff`: the owner turned comments off for this post.
  commentsOff,

  /// `pagePaused`: the owner's Page is paused, so nothing can be posted.
  paused,

  /// `pageUploadInProgress`: another upload of this owner is still open
  /// (one reservation set per owner, §1.9).
  uploadInProgress,

  /// `pageUploadExpired`: the 15-minute reservation ran out.
  uploadExpired,

  /// `pageMediaInvalid`: the stored object did not match its reservation
  /// or the trusted probe.
  mediaInvalid,

  /// `pageReportOwnContent`: a report of the caller's own Page, post or
  /// comment.
  ownContent,

  /// Offline, a timeout or a transient server error: retryable.
  network,

  /// A response that broke the wire contract, or anything unmapped.
  unknown,
}

/// The owner's post operations this client sends; `setCommentsEnabled`
/// goes through [PagesService.setCommentsEnabled].
enum PagePostOp {
  delete('delete'),
  pin('pin'),
  unpin('unpin');

  const PagePostOp(this.wire);
  final String wire;
}

class PagesException implements Exception {
  const PagesException(this.failure, [this.message]);

  final PagesFailure failure;
  final String? message;

  @override
  String toString() =>
      'PagesException($failure${message == null ? '' : ', $message'})';
}

/// The Pages callables this client uses (spec §2): the Treści feed, Find
/// Pages, likes, media grants and the existing follow callable. One place
/// maps every refusal to a [PagesFailure].
///
/// Every response goes through the §2.5 parsers: known keys required,
/// unknown keys ignored, unknown enum values skipped.
class PagesService {
  PagesService({
    FirebaseFunctions? functions,
    PagesCallableInvoker? invoker,
    PagesAvailability? availability,
    String Function()? requestIdFactory,
    DateTime Function()? clock,
  }) : _functionsOverride = functions,
       _invoker = invoker,
       _availability = availability,
       _requestIdFactory = requestIdFactory,
       _clock = clock ?? DateTime.now;

  /// The app-wide instance the Treści screens share. Its media grants are
  /// bearer URLs, so sign-out clears them with every other media cache.
  static final PagesService instance = () {
    final service = PagesService(availability: PagesAvailability.instance);
    EphemeralMediaAccessRegistry.register('pages', service.clearMediaGrants);
    return service;
  }();

  static const feedCallable = 'getPagesFeedV1';
  static const findCallable = 'findPagesV1';
  static const engagementCallable = 'pagePostEngagementV1';
  static const mediaAccessCallable = 'getPagePostMediaAccessV1';
  static const followCallable = 'setFollow';
  static const pageCallable = 'getPageV1';
  static const managePageCallable = 'managePageV1';
  static const managePostCallable = 'managePagePostV1';
  static const postCallable = 'getPagePostV1';
  static const reserveCallable = 'reservePagePostMediaV1';
  static const publishCallable = 'publishPagePostV1';
  static const reportCallable = 'createPageReportV1';

  /// §1.1: post text 0-5000 UTF-16 units, comments 1-1000.
  static const int maxPostText = 5000;
  static const int maxCommentText = 1000;

  /// `managePageV1 create` consent version (§2.2).
  static const int consentVersion = 1;

  /// `findPagesV1 search`: 2-60 characters (§2.7).
  static const int minSearchLength = 2;
  static const int maxSearchLength = 60;

  final FirebaseFunctions? _functionsOverride;
  final PagesCallableInvoker? _invoker;
  final PagesAvailability? _availability;
  final String Function()? _requestIdFactory;
  final DateTime Function() _clock;

  static final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9_-]{8,128}$');

  String newRequestId() {
    final supplied = _requestIdFactory?.call();
    if (supplied != null && _requestIdPattern.hasMatch(supplied)) {
      return supplied;
    }
    final random = Random.secure();
    final entropy = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'pg_${_clock().toUtc().microsecondsSinceEpoch}_$entropy';
  }

  Future<Object?> _call(String name, Map<String, Object?> payload) async {
    try {
      final injected = _invoker;
      if (injected != null) return await injected(name, payload);
      final functions =
          _functionsOverride ??
          FirebaseFunctions.instanceFor(region: 'europe-west1');
      final result = await functions.httpsCallable(name).call<Object?>(payload);
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      final failure = failureFor(error);
      throw PagesException(failure, error.message);
    } on PagesException {
      rethrow;
    } on TimeoutException {
      throw const PagesException(PagesFailure.network);
    } catch (error) {
      throw PagesException(PagesFailure.network, '$error');
    }
  }

  T _parse<T>(T Function() parse) {
    try {
      return parse();
    } on FormatException catch (error) {
      throw PagesException(PagesFailure.unknown, error.message);
    }
  }

  /// Maps the refusal envelope `{code, details:{reason}}`.
  static PagesFailure failureFor(FirebaseFunctionsException error) {
    final details = error.details;
    final reason = details is Map ? details['reason'] : null;
    switch (reason) {
      case 'pagesNotEnabled':
        return PagesFailure.notEnabled;
      case 'pageAccessRequired':
        return PagesFailure.accessRequired;
      case 'pageUnavailable':
      case 'pageNotFound':
      case 'pageSuspended':
      case 'pageReportTargetMissing':
        return PagesFailure.unavailable;
      case 'pageReportOwnContent':
        return PagesFailure.ownContent;
      case 'pageReadOnly':
        return PagesFailure.readOnly;
      case 'pagePostBudget':
        return PagesFailure.budget;
      case 'pageProfileNotPublic':
        return PagesFailure.profileNotPublic;
      case 'pageAdultRequired':
        return PagesFailure.adultRequired;
      case 'pageExists':
        return PagesFailure.pageExists;
      case 'pageHasAudience':
        return PagesFailure.hasAudience;
      case 'pageNameReserved':
        return PagesFailure.nameReserved;
      case 'pageMediaMetadata':
        return PagesFailure.mediaMetadata;
      case 'commentLinks':
        return PagesFailure.commentLinks;
      case 'pageLinkedServerInvalid':
        return PagesFailure.linkedServerInvalid;
      case 'pageCommentsOff':
        return PagesFailure.commentsOff;
      case 'pagePaused':
        return PagesFailure.paused;
      case 'pageUploadInProgress':
        return PagesFailure.uploadInProgress;
      case 'pageUploadExpired':
        return PagesFailure.uploadExpired;
      case 'pageMediaInvalid':
        return PagesFailure.mediaInvalid;
    }
    return switch (error.code) {
      'resource-exhausted' => PagesFailure.rateLimited,
      'permission-denied' || 'not-found' => PagesFailure.unavailable,
      'invalid-argument' => PagesFailure.invalidInput,
      'unavailable' ||
      'deadline-exceeded' ||
      'internal' ||
      'aborted' ||
      'cancelled' ||
      'unknown' => PagesFailure.network,
      _ => PagesFailure.unknown,
    };
  }

  /// A `pagesNotEnabled` refusal is reported to [PagesAvailability] by the
  /// screen that shows E9, not here: the destination must stay open long
  /// enough to say so (see `PagesFeedController`).
  void reportNotEnabled() => _availability?.reportNotEnabled();

  // ---------------------------------------------------------------- reads

  /// `getPagesFeedV1 {cursor}` (§2.5). Page size is fixed at 20 server-side.
  Future<PagesFeedPage> getFeed({String? cursor}) async {
    final raw = await _call(feedCallable, <String, Object?>{'cursor': cursor});
    return _parse(() => PagesFeedPage.fromWire(raw));
  }

  /// `findPagesV1 {mode, query, cursor}` (§2.7). [query] is only sent for
  /// [FindPagesMode.search], trimmed and bounded to 2-60 characters.
  Future<FindPagesPage> findPages({
    required FindPagesMode mode,
    String? query,
    String? cursor,
  }) async {
    String? wireQuery;
    if (mode == FindPagesMode.search) {
      final trimmed = (query ?? '').trim();
      if (trimmed.runeLength < minSearchLength ||
          trimmed.runeLength > maxSearchLength) {
        throw const PagesException(PagesFailure.unknown, 'query length');
      }
      wireQuery = trimmed;
    }
    final raw = await _call(findCallable, <String, Object?>{
      'mode': mode.wire,
      'query': wireQuery,
      'cursor': cursor,
    });
    return _parse(() => FindPagesPage.fromWire(raw));
  }

  /// `getPageV1 {pageId, tab, cursor}` (§2.5). The header, viewer and pinned
  /// post come only with the first page (`cursor == null`).
  Future<PageProfilePage> getPage({
    required String pageId,
    PageWallTab tab = PageWallTab.wall,
    String? cursor,
  }) async {
    if (pageId.isEmpty) {
      throw const PagesException(PagesFailure.unavailable, 'pageId');
    }
    final raw = await _call(pageCallable, <String, Object?>{
      'pageId': pageId,
      'tab': tab.wire,
      'cursor': cursor,
    });
    return _parse(() => PageProfilePage.fromWire(raw));
  }

  // --------------------------------------------------------------- writes

  /// `managePageV1 {op:"create"}` (§2.2). [birthDate] is `YYYY-MM-DD`, or
  /// null when the account already attested adulthood; it is sent once and
  /// never kept. [requestId] is reused by a retry of the same submission.
  Future<PageLifecycleResult> createPage({
    required String requestId,
    required PageKind kind,
    required String category,
    required String description,
    required PageBusinessInfo? business,
    required String? rules,
    required String? linkedServerId,
    required String? birthDate,
  }) async {
    final raw = await _call(managePageCallable, <String, Object?>{
      'requestId': requestId,
      'op': 'create',
      'kind': kind.wire,
      'category': category,
      'description': description,
      'business': kind == PageKind.business
          ? (business ?? PageBusinessInfo.empty).toWire()
          : null,
      'community': kind == PageKind.community
          ? <String, Object?>{'rules': rules, 'linkedServerId': linkedServerId}
          : null,
      'birthDate': birthDate,
      'consentVersion': consentVersion,
    });
    return _parse(() => PageLifecycleResult.fromWire(raw));
  }

  /// `managePageV1 {op:"update"}`: the whole editable profile of a Page of
  /// [kind] (the kind itself is fixed, D16).
  Future<PageLifecycleResult> updatePage({
    required PageKind kind,
    required String category,
    required String description,
    required PageBusinessInfo? business,
    required String? rules,
    required String? linkedServerId,
  }) async {
    final raw = await _call(managePageCallable, <String, Object?>{
      'requestId': newRequestId(),
      'op': 'update',
      'category': category,
      'description': description,
      'business': kind == PageKind.business
          ? (business ?? PageBusinessInfo.empty).toWire()
          : null,
      'community': kind == PageKind.community
          ? <String, Object?>{'rules': rules, 'linkedServerId': linkedServerId}
          : null,
    });
    return _parse(() => PageLifecycleResult.fromWire(raw));
  }

  /// `managePageV1 {op:"pause"}`: a safety action (works with the kill
  /// switch on and while muted, §2.1).
  Future<PageLifecycleResult> pausePage() async {
    final raw = await _call(managePageCallable, <String, Object?>{
      'requestId': newRequestId(),
      'op': 'pause',
    });
    return _parse(() => PageLifecycleResult.fromWire(raw));
  }

  /// `managePageV1 {op:"resume"}`.
  Future<PageLifecycleResult> resumePage() async {
    final raw = await _call(managePageCallable, <String, Object?>{
      'requestId': newRequestId(),
      'op': 'resume',
    });
    return _parse(() => PageLifecycleResult.fromWire(raw));
  }

  /// `managePagePostV1 {requestId, postId, op}` for delete / pin / unpin
  /// (§2.4). Delete is a safety action.
  Future<PagePostManageResult> managePost(String postId, PagePostOp op) async {
    if (!pagePostIdPattern.hasMatch(postId)) {
      throw const PagesException(PagesFailure.unavailable, 'postId');
    }
    final raw = await _call(managePostCallable, <String, Object?>{
      'requestId': newRequestId(),
      'postId': postId,
      'op': op.wire,
    });
    return _parse(() => PagePostManageResult.fromWire(raw));
  }

  /// Follows or unfollows a Page through the existing `setFollow` callable
  /// (§2.3; the edge shape is unchanged).
  Future<void> setFollow(String pageId, {required bool following}) async {
    await _call(followCallable, <String, Object?>{
      'targetUserId': pageId,
      'following': following,
    });
  }

  /// `pagePostEngagementV1 {requestId, op: like|unlike, postId}` (§2.6).
  Future<void> setLiked(String postId, {required bool liked}) async {
    if (!pagePostIdPattern.hasMatch(postId)) {
      throw const PagesException(PagesFailure.unavailable, 'postId');
    }
    await _call(engagementCallable, <String, Object?>{
      'requestId': newRequestId(),
      'op': liked ? 'like' : 'unlike',
      'postId': postId,
    });
  }

  // ---------------------------------------------------------------- posts

  /// `getPagePostV1 {postId, commentCursor}` (§2.5): the post and 20
  /// comments per page, newest first.
  Future<PagePostDetailPage> getPost(
    String postId, {
    String? commentCursor,
  }) async {
    if (!pagePostIdPattern.hasMatch(postId)) {
      throw const PagesException(PagesFailure.unavailable, 'postId');
    }
    final raw = await _call(postCallable, <String, Object?>{
      'postId': postId,
      'commentCursor': commentCursor,
    });
    return _parse(() => PagePostDetailPage.fromWire(raw));
  }

  /// `pagePostEngagementV1 {requestId, op:"comment", postId, text}` (§2.6).
  /// [requestId] is reused when the same comment is retried.
  Future<PageCommentResult> comment(
    String postId,
    String text, {
    String? requestId,
  }) async {
    if (!pagePostIdPattern.hasMatch(postId)) {
      throw const PagesException(PagesFailure.unavailable, 'postId');
    }
    final raw = await _call(engagementCallable, <String, Object?>{
      'requestId': requestId ?? newRequestId(),
      'op': 'comment',
      'postId': postId,
      'text': text,
    });
    return _parse(() => PageCommentResult.fromWire(raw));
  }

  /// `pagePostEngagementV1 {requestId, op:"deleteComment", commentId}`: the
  /// author or the Page owner; a safety action (§2.6).
  Future<void> deleteComment(String commentId) async {
    if (!pageCommentIdPattern.hasMatch(commentId)) {
      throw const PagesException(PagesFailure.unavailable, 'commentId');
    }
    await _call(engagementCallable, <String, Object?>{
      'requestId': newRequestId(),
      'op': 'deleteComment',
      'commentId': commentId,
    });
  }

  /// `managePagePostV1 {requestId, postId, op:"setCommentsEnabled",
  /// commentsEnabled}` (§2.4), owner only.
  Future<PagePostManageResult> setCommentsEnabled(
    String postId, {
    required bool enabled,
  }) async {
    if (!pagePostIdPattern.hasMatch(postId)) {
      throw const PagesException(PagesFailure.unavailable, 'postId');
    }
    final raw = await _call(managePostCallable, <String, Object?>{
      'requestId': newRequestId(),
      'postId': postId,
      'op': 'setCommentsEnabled',
      'commentsEnabled': enabled,
    });
    return _parse(() => PagePostManageResult.fromWire(raw));
  }

  /// `reservePagePostMediaV1 {requestId, kind, items}` (§2.4). Photos: 1-10
  /// `image/jpeg` items with their layout size; voice: one `audio/mp4` clip
  /// with its declared length. No client `postId`.
  Future<PageMediaReservation> reserveMedia({
    required String requestId,
    required PagePostKind kind,
    required List<PageMediaReserveItem> items,
  }) async {
    if (kind == PagePostKind.text || items.isEmpty) {
      throw const PagesException(PagesFailure.invalidInput, 'items');
    }
    final raw = await _call(reserveCallable, <String, Object?>{
      'requestId': requestId,
      'kind': kind.wire,
      'items': [for (var i = 0; i < items.length; i++) items[i].toWire(i)],
    });
    final reservation = _parse(() => PageMediaReservation.fromWire(raw));
    if (reservation.slots.length != items.length) {
      throw const PagesException(PagesFailure.unknown, 'slots');
    }
    return reservation;
  }

  /// `publishPagePostV1 {requestId, postId, kind, text, mediaIds,
  /// commentsEnabled}` (§2.4). Text posts send `postId: null`; media posts
  /// send the reservation's id. The response is the new PostView; nothing
  /// is shown optimistically.
  Future<PagePostView> publishPost({
    required String requestId,
    required PagePostKind kind,
    required String text,
    required bool commentsEnabled,
    String? postId,
    List<String> mediaIds = const <String>[],
  }) async {
    final raw = await _call(publishCallable, <String, Object?>{
      'requestId': requestId,
      'postId': kind == PagePostKind.text ? null : postId,
      'kind': kind.wire,
      'text': text,
      'mediaIds': kind == PagePostKind.text ? const <String>[] : mediaIds,
      'commentsEnabled': commentsEnabled,
    });
    final post = _parse(() => PagePostView.fromWire(raw));
    if (post == null) {
      throw const PagesException(PagesFailure.unknown, 'post');
    }
    return post;
  }

  /// `createPageReportV1` (§2.10): no activation and no audience check, so
  /// a blocked or unverified viewer can still report. [reason] is one of
  /// the app's report reasons (the server's closed list).
  Future<void> report({
    required PageReportTarget target,
    required String pageId,
    required String reason,
    String? postId,
    String? commentId,
  }) async {
    await _call(reportCallable, <String, Object?>{
      'requestId': newRequestId(),
      'targetType': target.wire,
      'pageId': pageId,
      'postId': target == PageReportTarget.page ? null : postId,
      'commentId': target == PageReportTarget.comment ? commentId : null,
      'reason': reason,
      'note': null,
    });
  }

  // ---------------------------------------------------------------- media

  /// Drops the memoised grant of one media object, so the next
  /// [mediaAccess] asks the server again (a 403 on download, §4.5).
  void forgetMediaGrant(String postId, String mediaId) =>
      _grants.remove('$postId/$mediaId');

  /// Grants are memoised until 10 s before they expire, per post and
  /// media, and dropped on sign-out through [EphemeralMediaAccessRegistry].
  final Map<String, PageMediaGrant> _grants = <String, PageMediaGrant>{};
  final Map<String, Future<Map<String, PageMediaGrant>>> _grantsInFlight =
      <String, Future<Map<String, PageMediaGrant>>>{};

  static const Duration _grantSafety = Duration(seconds: 10);

  void clearMediaGrants() {
    _grants.clear();
    _grantsInFlight.clear();
  }

  /// `getPagePostMediaAccessV1 {postId, mediaIds}` (§2.5), at most 10 ids.
  /// Returns the live grant per media id; ids the server refused are absent.
  Future<Map<String, PageMediaGrant>> mediaAccess(
    String postId,
    List<String> mediaIds,
  ) {
    final ids = <String>[
      for (final id in mediaIds)
        if (pageMediaIdPattern.hasMatch(id)) id,
    ].take(10).toList(growable: false);
    if (!pagePostIdPattern.hasMatch(postId) || ids.isEmpty) {
      return Future.value(const <String, PageMediaGrant>{});
    }
    final nowMs = _clock().millisecondsSinceEpoch;
    final fresh = <String, PageMediaGrant>{};
    for (final id in ids) {
      final grant = _grants['$postId/$id'];
      if (grant != null &&
          grant.expiresAtMs - _grantSafety.inMilliseconds > nowMs) {
        fresh[id] = grant;
      }
    }
    if (fresh.length == ids.length) return Future.value(fresh);
    final key = '$postId/${ids.join(',')}';
    return _grantsInFlight[key] ??= () async {
      try {
        final raw = await _call(mediaAccessCallable, <String, Object?>{
          'postId': postId,
          'mediaIds': ids,
        });
        final grants = _parse(() => PageMediaGrant.listFromWire(raw));
        final result = <String, PageMediaGrant>{};
        for (final grant in grants) {
          if (!ids.contains(grant.mediaId)) continue;
          _grants['$postId/${grant.mediaId}'] = grant;
          result[grant.mediaId] = grant;
        }
        return result;
      } finally {
        unawaited(Future<void>.microtask(() => _grantsInFlight.remove(key)));
      }
    }();
  }

  @visibleForTesting
  int get cachedGrantCount => _grants.length;
}

/// One `reservePagePostMediaV1` item (§2.4): the exact keys, with `index`
/// assigned from the list order.
class PageMediaReserveItem {
  const PageMediaReserveItem.photo({
    required this.size,
    required int this.width,
    required int this.height,
  }) : contentType = 'image/jpeg',
       durationMs = null;

  const PageMediaReserveItem.voice({
    required this.size,
    required int this.durationMs,
  }) : contentType = 'audio/mp4',
       width = null,
       height = null;

  final String contentType;
  final int size;
  final int? width;
  final int? height;
  final int? durationMs;

  Map<String, Object?> toWire(int index) => <String, Object?>{
    'index': index,
    'contentType': contentType,
    'size': size,
    'width': width,
    'height': height,
    'durationMs': durationMs,
  };
}

extension on String {
  int get runeLength => runes.length;
}
