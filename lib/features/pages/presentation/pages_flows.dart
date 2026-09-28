import 'package:flutter/widgets.dart';

import 'package:yovoice/features/likers/data/models/likers_target.dart';
import 'package:yovoice/features/likers/presentation/likers_launcher.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/services/page_voice_player.dart';
import 'package:yovoice/features/pages/presentation/page_navigation.dart';
import 'package:yovoice/features/pages/presentation/screens/create_page_screen.dart';
import 'package:yovoice/features/pages/presentation/screens/page_composer.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';

typedef OpenPageFlow =
    Future<void> Function(
      BuildContext context, {
      required String pageId,
      String? displayName,
    });
typedef OpenPostFlow =
    Future<void> Function(
      BuildContext context, {
      required String pageId,
      required String postId,
      PagePostView? initial,
      bool focusComposer,
      bool pageReadOnly,
    });

/// Opens the owner's composer; resolves to the published post, or null.
typedef ComposeFlow =
    Future<PagePostView?> Function(
      BuildContext context, {
      required PageComposerOwner owner,
      PagePostKind initialKind,
    });
typedef PostFlow =
    Future<void> Function(BuildContext context, PagePostView post);
typedef ContextFlow = Future<void> Function(BuildContext context);

/// The destinations the Treści wall hands off to, one seam per flow owned
/// by a later Pages package (spec premium-pages §9.1).
///
/// A null flow means "not built yet": the wall then leaves that control
/// visibly disabled (Komentuj, the likers entry, voice playback) or does
/// not draw the entry at all (the create and composer entries), instead of
/// pretending. `context` is always a context under the Treści navigator,
/// so a pushed screen keeps the dock and Treści selected (§4.3).
class PagesFlows {
  const PagesFlows({
    this.openPage = openPageAsPersonalProfile,
    this.openPost,
    this.openLikers,
    this.playVoice,
    this.openCreatePage,
    this.openComposer,
    this.openPageFromLink,
  });

  /// Opens a Page. The app opens the Page profile B (C3); the constructor's
  /// default is the §4.3 fallback, the ordinary personal profile, which keeps
  /// call, remove-friend, Block and Report.
  final OpenPageFlow openPage;

  /// Opens a Page from a `?page=` deep link: the profile, which shows E7
  /// when the Page cannot be opened instead of falling back. Null uses
  /// [openPage].
  final OpenPageFlow? openPageFromLink;

  /// The post detail with its comments (C4, R3).
  final OpenPostFlow? openPost;

  /// "N polubień, pokaż kto polubił" (C4, `PagePostLikersTarget`).
  final PostFlow? openLikers;

  /// Full-download voice playback (C4, §4.5).
  final PostFlow? playVoice;

  /// Create A: Premium block → type → details → preview (C3).
  final ContextFlow? openCreatePage;

  /// The owner's composer A "arkusz" (C4).
  final ComposeFlow? openComposer;

  /// What the app uses: the Page profile B and create A (C3), the post
  /// detail A, the likers list, full-download voice playback and the
  /// composer A (C4).
  static const PagesFlows app = PagesFlows(
    openPage: openPageProfile,
    openPageFromLink: openPageProfileFromLink,
    openCreatePage: openCreatePageFlow,
    openPost: openPagePost,
    openLikers: openPagePostLikers,
    playVoice: togglePageVoice,
    openComposer: openPageComposer,
  );
}

/// "N polubień, pokaż kto polubił" (ADR-230 plumbing, `PagePostLikersTarget`).
Future<void> openPagePostLikers(BuildContext context, PagePostView post) =>
    const LikersLauncher().open(
      context,
      PagePostLikersTarget(post.postId),
      totalCount: post.likeCount,
    );

/// Play / pause a voice post on the one app-wide player (§4.5).
Future<void> togglePageVoice(BuildContext context, PagePostView post) =>
    PageVoicePlayer.instance.toggle(post);

/// The composer A "arkusz" (R3, §12).
Future<PagePostView?> openPageComposer(
  BuildContext context, {
  required PageComposerOwner owner,
  PagePostKind initialKind = PagePostKind.text,
}) => showPageComposer(context, owner: owner, initialKind: initialKind);

/// The §4.3 resolver's fallback, used until the Page profile exists.
Future<void> openPageAsPersonalProfile(
  BuildContext context, {
  required String pageId,
  String? displayName,
}) => showProfilePreview(context, userId: pageId, displayName: displayName);
