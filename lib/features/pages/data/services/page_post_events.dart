import 'dart:async';

import 'package:yovoice/features/pages/data/models/page_views.dart';

/// A change to one post that another Treści surface made (the post
/// detail's like, comment count, comments switch or delete), so the wall
/// and the Page profile under it show the same numbers without a refetch.
sealed class PagePostChange {
  const PagePostChange(this.postId);

  final String postId;
}

/// The post as the server last described it (or as an accepted optimistic
/// like left it).
final class PagePostUpdated extends PagePostChange {
  PagePostUpdated(this.post) : super(post.postId);

  final PagePostView post;
}

/// The post is gone for this viewer (deleted by its owner, or unavailable).
final class PagePostRemoved extends PagePostChange {
  const PagePostRemoved(super.postId);
}

/// One app-wide broadcast of [PagePostChange]s. Carries ids and server
/// views only; listeners patch posts they already hold and ignore the rest.
class PagePostEvents {
  PagePostEvents();

  static final PagePostEvents instance = PagePostEvents();

  final StreamController<PagePostChange> _controller =
      StreamController<PagePostChange>.broadcast(sync: true);

  Stream<PagePostChange> get changes => _controller.stream;

  void updated(PagePostView post) => _controller.add(PagePostUpdated(post));

  void removed(String postId) => _controller.add(PagePostRemoved(postId));
}
