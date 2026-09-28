import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/services/pages_availability.dart';
import 'package:yovoice/features/pages/presentation/screens/page_post_detail_screen.dart';
import 'package:yovoice/features/pages/presentation/screens/page_profile_screen.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';

/// Marks the routes of Treści's OWN navigator (spec premium-pages §4.3): a
/// Page opened from the feed, the rail or Find is pushed there, so the dock
/// keeps Treści selected, Back returns to the feed and re-tapping Treści
/// pops to it. [desktop] is true while that navigator is the desktop main
/// column beside the wall-A panel.
class PagesNavigatorScope extends InheritedWidget {
  const PagesNavigatorScope({
    required this.desktop,
    required super.child,
    super.key,
  });

  final bool desktop;

  static PagesNavigatorScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PagesNavigatorScope>();

  @override
  bool updateShouldNotify(PagesNavigatorScope oldWidget) =>
      desktop != oldWidget.desktop;
}

/// Hosts a Page opened from OUTSIDE Treści (a chat, a notification, a friend
/// list, a room): the shell registers one that shows the Page with the
/// persistent chrome (the dock with Treści selected on phones, the Treści
/// destination with its panel on desktop).
typedef PagesShellHost =
    Future<void> Function(
      BuildContext context, {
      required String pageId,
      String? displayName,
    });

abstract final class PagesShellBridge {
  /// Registered by `MainShell` while it is mounted; null elsewhere (tests,
  /// a route above the shell without one).
  static PagesShellHost? host;
}

/// The route every Page profile is pushed with.
Route<void> pageProfileRoute({
  required String pageId,
  String? displayName,
  bool fromLink = false,
}) => MaterialPageRoute<void>(
  settings: RouteSettings(name: 'pages/page/$pageId'),
  builder: (context) => PageProfileScreen(
    pageId: pageId,
    displayName: displayName,
    fromLink: fromLink,
  ),
);

/// Opens the Page profile B of [pageId] (§4.3): on Treści's own navigator
/// when [context] is under it, else through the shell host, else as a plain
/// route with its own Back.
Future<void> openPageProfile(
  BuildContext context, {
  required String pageId,
  String? displayName,
}) async {
  if (PagesNavigatorScope.maybeOf(context) != null) {
    await Navigator.of(
      context,
    ).push<void>(pageProfileRoute(pageId: pageId, displayName: displayName));
    return;
  }
  final host = PagesShellBridge.host;
  if (host != null) {
    await host(context, pageId: pageId, displayName: displayName);
    return;
  }
  await Navigator.of(
    context,
  ).push<void>(pageProfileRoute(pageId: pageId, displayName: displayName));
}

/// The route every post detail is pushed with.
Route<void> pagePostRoute({
  required String postId,
  String? pageId,
  PagePostView? initial,
  bool focusComposer = false,
  bool pageReadOnly = false,
}) => MaterialPageRoute<void>(
  settings: RouteSettings(name: 'pages/post/$postId'),
  builder: (context) => PagePostDetailScreen(
    postId: postId,
    pageId: pageId,
    initial: initial,
    focusComposer: focusComposer,
    pageReadOnly: pageReadOnly,
    onOpenPage: openPageProfile,
    onOpenAccount: (context, {required uid, displayName}) =>
        openAccountProfile(context, uid: uid, displayName: displayName),
  ),
);

/// Opens the post detail A (§4.5, R3). On desktop it opens inside Treści's
/// main column (the wall-A panel stays); on phones and tablets it is pushed
/// over the shell, so the comment composer takes the dock's place, as on
/// the approved render.
Future<void> openPagePost(
  BuildContext context, {
  required String pageId,
  required String postId,
  PagePostView? initial,
  bool focusComposer = false,
  bool pageReadOnly = false,
}) {
  final route = pagePostRoute(
    postId: postId,
    pageId: pageId,
    initial: initial,
    focusComposer: focusComposer,
    pageReadOnly: pageReadOnly,
  );
  final scope = PagesNavigatorScope.maybeOf(context);
  if (scope != null && scope.desktop) {
    return Navigator.of(context).push<void>(route);
  }
  return Navigator.of(context, rootNavigator: true).push<void>(route);
}

/// A `?page=` deep link: the profile on Treści's navigator, showing E7
/// (instead of the personal-profile fallback) when it cannot be opened.
Future<void> openPageProfileFromLink(
  BuildContext context, {
  required String pageId,
  String? displayName,
}) => Navigator.of(context).push<void>(
  pageProfileRoute(pageId: pageId, displayName: displayName, fromLink: true),
);

/// The single resolver (§4.3 `openAccountProfile`): an account whose
/// `publicBadges.page` is set opens as its Page while Pages are on for this
/// account; every other account opens the ordinary personal profile. The
/// Page profile falls back to the personal profile itself when `getPageV1`
/// answers `pagesNotEnabled` or `pageUnavailable`.
Future<void> openAccountProfile(
  BuildContext context, {
  required String uid,
  String? displayName,
}) async {
  if (await redirectToPageProfile(
    context,
    userId: uid,
    displayName: displayName,
  )) {
    return;
  }
  if (!context.mounted) return;
  await showProfilePreview(
    context,
    userId: uid,
    displayName: displayName,
    resolvePages: false,
  );
}

/// How long a profile tap waits for an uncached identity before opening
/// the ordinary personal profile.
const Duration redirectLookupBudget = Duration(milliseconds: 600);

/// The [AccountProfileRedirect] the shell registers: true when [userId] was
/// opened as a Page profile.
Future<bool> redirectToPageProfile(
  BuildContext context, {
  required String userId,
  String? displayName,
  bool? enabled,
}) async {
  if (userId.isEmpty ||
      !(enabled ?? PagesAvailability.instance.enabled.value)) {
    return false;
  }
  final repository = PublicIdentityRepository.instance;
  var identity = repository.peek(userId);
  if (identity == null) {
    // Every profile tap in the app (27 call sites, live-room speakers
    // included) passes through here: an uncached identity may delay the
    // sheet by at most [redirectLookupBudget]. A slower answer still lands
    // in the cache, so the next tap on a Page account redirects.
    try {
      identity = await repository.resolve(userId).timeout(redirectLookupBudget);
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }
  if (!identity.isPage || !context.mounted) return false;
  unawaited(openPageProfile(context, pageId: userId, displayName: displayName));
  return true;
}
