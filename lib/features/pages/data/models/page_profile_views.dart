part of 'page_views.dart';

/// The Page profile's wire views (spec premium-pages §2.2, §2.5):
/// `getPageV1` → PageHeader, viewer, pinned post and the wall / photos page,
/// and the `managePageV1` result. Same parsing rule as every Pages view:
/// known keys required, unknown keys ignored, unknown enum values rejected.

/// A PageHeader's `state`. Visitors only ever get [active] or [readOnly];
/// the owner gets the first match of suspended > hidden > paused > readOnly >
/// active.
enum PageHeaderState {
  active('active'),
  readOnly('readOnly'),
  hidden('hidden'),
  paused('paused'),
  suspended('suspended');

  const PageHeaderState(this.wire);
  final String wire;

  static PageHeaderState? fromWire(Object? raw) {
    for (final state in values) {
      if (state.wire == raw) return state;
    }
    return null;
  }

  /// The owner may publish, pin and edit only while the Page runs.
  bool get running => this == PageHeaderState.active;
}

/// `getPageV1 {tab}`.
enum PageWallTab {
  wall('wall'),
  photos('photos');

  const PageWallTab(this.wire);
  final String wire;
}

/// A business Page's public contact block (§1.2 `business`): every key is
/// present, each null or text. The same shape goes back to `managePageV1`.
class PageBusinessInfo {
  const PageBusinessInfo({
    this.website,
    this.email,
    this.phone,
    this.address,
    this.hours,
    this.legalNotice,
  });

  static const empty = PageBusinessInfo();

  final String? website;
  final String? email;
  final String? phone;
  final String? address;
  final String? hours;
  final String? legalNotice;

  static PageBusinessInfo fromWire(Object? raw) {
    const what = 'PageBusiness';
    final map = _object(raw, what);
    return PageBusinessInfo(
      website: _nullableString(map, 'website', what),
      email: _nullableString(map, 'email', what),
      phone: _nullableString(map, 'phone', what),
      address: _nullableString(map, 'address', what),
      hours: _nullableString(map, 'hours', what),
      legalNotice: _nullableString(map, 'legalNotice', what),
    );
  }

  /// Lenient read of the owner's own `pages/{uid}.business` map: a missing
  /// or malformed value reads as null (the settings screen only displays it).
  static PageBusinessInfo fromStored(Object? raw) {
    if (raw is! Map) return empty;
    String? read(String key) {
      final value = raw[key];
      return value is String && value.trim().isNotEmpty ? value : null;
    }

    return PageBusinessInfo(
      website: read('website'),
      email: read('email'),
      phone: read('phone'),
      address: read('address'),
      hours: read('hours'),
      legalNotice: read('legalNotice'),
    );
  }

  Map<String, Object?> toWire() => <String, Object?>{
    'website': website,
    'email': email,
    'phone': phone,
    'address': address,
    'hours': hours,
    'legalNotice': legalNotice,
  };

  bool get isEmpty =>
      website == null &&
      email == null &&
      phone == null &&
      address == null &&
      hours == null &&
      legalNotice == null;

  PageBusinessInfo copyWith({
    Object? website = _keep,
    Object? email = _keep,
    Object? phone = _keep,
    Object? address = _keep,
    Object? hours = _keep,
    Object? legalNotice = _keep,
  }) => PageBusinessInfo(
    website: identical(website, _keep) ? this.website : website as String?,
    email: identical(email, _keep) ? this.email : email as String?,
    phone: identical(phone, _keep) ? this.phone : phone as String?,
    address: identical(address, _keep) ? this.address : address as String?,
    hours: identical(hours, _keep) ? this.hours : hours as String?,
    legalNotice: identical(legalNotice, _keep)
        ? this.legalNotice
        : legalNotice as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is PageBusinessInfo &&
      other.website == website &&
      other.email == email &&
      other.phone == phone &&
      other.address == address &&
      other.hours == hours &&
      other.legalNotice == legalNotice;

  @override
  int get hashCode =>
      Object.hash(website, email, phone, address, hours, legalNotice);
}

const Object _keep = Object();

/// The Page's linked public server, read CURRENT by the server (§2.5):
/// omitted unless it is still active and public.
class PageLinkedServer {
  const PageLinkedServer({
    required this.serverId,
    required this.name,
    required this.serverType,
  });

  final String serverId;
  final String? name;
  final String serverType;

  static PageLinkedServer? fromWire(Object? raw) {
    if (raw == null) return null;
    const what = 'PageLinkedServer';
    final map = _object(raw, what);
    final serverId = _string(map, 'serverId', what);
    final name = _nullableString(map, 'name', what);
    final serverType = _required(map, 'serverType', what);
    return PageLinkedServer(
      serverId: serverId,
      name: name,
      serverType: serverType is String ? serverType : '',
    );
  }
}

/// A community Page's public block.
class PageCommunityInfo {
  const PageCommunityInfo({this.rules, this.linkedServer});

  final String? rules;
  final PageLinkedServer? linkedServer;

  static PageCommunityInfo fromWire(Object? raw) {
    const what = 'PageCommunity';
    final map = _object(raw, what);
    return PageCommunityInfo(
      rules: _nullableString(map, 'rules', what),
      linkedServer: PageLinkedServer.fromWire(
        _required(map, 'linkedServer', what),
      ),
    );
  }
}

/// PageHeader (§2.5).
class PageHeader {
  const PageHeader({
    required this.pageId,
    required this.displayName,
    required this.kind,
    required this.category,
    required this.description,
    required this.followerCount,
    required this.postCount,
    required this.onYoVoiceSinceMs,
    required this.business,
    required this.community,
    required this.state,
  });

  final String pageId;
  final String displayName;
  final PageKind kind;
  final String category;
  final String description;
  final int followerCount;
  final int postCount;
  final int? onYoVoiceSinceMs;
  final PageBusinessInfo? business;
  final PageCommunityInfo? community;
  final PageHeaderState state;

  /// Null when this client cannot render the header (an unknown kind or
  /// state): the screen then falls back as for an unavailable Page.
  static PageHeader? fromWire(Object? raw) {
    const what = 'PageHeader';
    final map = _object(raw, what);
    final pageId = _string(map, 'pageId', what);
    final displayName = _string(map, 'displayName', what);
    final kindRaw = _required(map, 'kind', what);
    final category = _string(map, 'category', what);
    final description = _string(map, 'description', what);
    final followerCount = _count(map, 'followerCount', what);
    final postCount = _count(map, 'postCount', what);
    final since = _nullableInt(map, 'onYoVoiceSinceMs', what);
    final about = _object(_required(map, 'about', what), 'PageAbout');
    final businessRaw = _required(about, 'business', 'PageAbout');
    final communityRaw = _required(about, 'community', 'PageAbout');
    final stateRaw = _required(map, 'state', what);
    final kind = PageKind.fromWire(kindRaw);
    final state = PageHeaderState.fromWire(stateRaw);
    if (kind == null || state == null || pageId.isEmpty) return null;
    return PageHeader(
      pageId: pageId,
      displayName: displayName,
      kind: kind,
      category: category,
      description: description,
      followerCount: followerCount,
      postCount: postCount,
      onYoVoiceSinceMs: since,
      business: businessRaw == null
          ? null
          : PageBusinessInfo.fromWire(businessRaw),
      community: communityRaw == null
          ? null
          : PageCommunityInfo.fromWire(communityRaw),
      state: state,
    );
  }

  PageHeader copyWith({int? followerCount}) => PageHeader(
    pageId: pageId,
    displayName: displayName,
    kind: kind,
    category: category,
    description: description,
    followerCount: followerCount ?? this.followerCount,
    postCount: postCount,
    onYoVoiceSinceMs: onYoVoiceSinceMs,
    business: business,
    community: community,
    state: state,
  );
}

/// The viewer's relation to the Page (§2.5 `viewer`).
class PageViewerView {
  const PageViewerView({
    required this.isOwner,
    required this.following,
    required this.canFollow,
    required this.canMessage,
  });

  final bool isOwner;
  final bool following;
  final bool canFollow;
  final bool canMessage;

  static PageViewerView fromWire(Object? raw) {
    const what = 'PageViewer';
    final map = _object(raw, what);
    return PageViewerView(
      isOwner: _bool(map, 'isOwner', what),
      following: _bool(map, 'following', what),
      canFollow: _bool(map, 'canFollow', what),
      canMessage: _bool(map, 'canMessage', what),
    );
  }

  PageViewerView copyWith({bool? following, bool? canFollow}) => PageViewerView(
    isOwner: isOwner,
    following: following ?? this.following,
    canFollow: canFollow ?? this.canFollow,
    canMessage: canMessage,
  );
}

/// `getPageV1` → `{schemaVersion, page, viewer, pinned, posts, nextCursor,
/// hasMore}`. `page`, `viewer` and `pinned` come only with the first page.
class PageProfilePage {
  const PageProfilePage({
    required this.header,
    required this.viewer,
    required this.pinned,
    required this.posts,
    required this.nextCursor,
    required this.hasMore,
  });

  final PageHeader? header;
  final PageViewerView? viewer;
  final PagePostView? pinned;
  final List<PagePostView> posts;
  final String? nextCursor;
  final bool hasMore;

  static PageProfilePage fromWire(Object? raw) {
    const what = 'PageResponse';
    final map = _object(raw, what);
    _int(map, 'schemaVersion', what);
    final pageRaw = _required(map, 'page', what);
    final viewerRaw = _required(map, 'viewer', what);
    final pinnedRaw = _required(map, 'pinned', what);
    final posts = _items(_list(map, 'posts', what), PagePostView.fromWire);
    final nextCursor = _nullableString(map, 'nextCursor', what);
    final hasMore = _bool(map, 'hasMore', what);
    final header = pageRaw == null ? null : PageHeader.fromWire(pageRaw);
    if (pageRaw != null && header == null) {
      throw const PagesContractException('PageResponse.page: unknown enum.');
    }
    final pinned = pinnedRaw == null ? null : PagePostView.fromWire(pinnedRaw);
    return PageProfilePage(
      header: header,
      viewer: viewerRaw == null ? null : PageViewerView.fromWire(viewerRaw),
      pinned: pinned,
      // The pinned post leads the wall; the server may also list it in
      // order, so it is shown once.
      posts: pinned == null
          ? posts
          : List.unmodifiable(posts.where((p) => p.postId != pinned.postId)),
      nextCursor: nextCursor,
      hasMore: hasMore && nextCursor != null,
    );
  }
}

/// `managePageV1` → `{pageId, kind, status, ownerPaused}` (every op).
class PageLifecycleResult {
  const PageLifecycleResult({
    required this.pageId,
    required this.kind,
    required this.status,
    required this.ownerPaused,
  });

  final String pageId;
  final PageKind? kind;
  final String status;
  final bool ownerPaused;

  static PageLifecycleResult fromWire(Object? raw) {
    const what = 'PageLifecycle';
    final map = _object(raw, what);
    return PageLifecycleResult(
      pageId: _string(map, 'pageId', what),
      kind: PageKind.fromWire(_required(map, 'kind', what)),
      status: _string(map, 'status', what),
      ownerPaused: _bool(map, 'ownerPaused', what),
    );
  }
}

/// `managePagePostV1` → `{op, postId, deleted, pinned, commentsEnabled}`.
class PagePostManageResult {
  const PagePostManageResult({
    required this.postId,
    required this.deleted,
    required this.pinned,
    required this.commentsEnabled,
  });

  final String postId;
  final bool deleted;
  final bool pinned;
  final bool commentsEnabled;

  static PagePostManageResult fromWire(Object? raw) {
    const what = 'PagePostManage';
    final map = _object(raw, what);
    return PagePostManageResult(
      postId: _string(map, 'postId', what),
      deleted: _bool(map, 'deleted', what),
      pinned: _bool(map, 'pinned', what),
      commentsEnabled: _bool(map, 'commentsEnabled', what),
    );
  }
}
