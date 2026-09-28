// The comment-like state of one thread (ADR-230, spec §5.1, §5.6):
// optimistic, single-flight per comment, revert on failure, a refresh never
// overwrites an in-flight toggle, `null` removes every heart, and the VIP
// pre-gate is watched only once there are hearts.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/likers/data/models/comment_like.dart';
import 'package:yovoice/features/likers/presentation/comment_likes_controller.dart';

const _zero = CommentLikeState(likeCount: 0, callerLiked: false);
const _three = CommentLikeState(likeCount: 3, callerLiked: false);

CommentLikeResult _result(
  String id, {
  required bool liked,
  required int count,
}) => CommentLikeResult(
  commentId: id,
  liked: liked,
  changed: true,
  likeCount: count,
);

void main() {
  test('no state, no heart; adopt(null) clears every heart', () {
    final controller = CommentLikesController(
      setLike: (id, {required liked}) async =>
          _result(id, liked: liked, count: 1),
    );
    addTearDown(controller.dispose);
    expect(controller.stateOf('c1'), isNull);
    controller.adopt(<String, CommentLikeState>{'c1': _three}, replace: true);
    expect(controller.stateOf('c1'), _three);
    controller.adopt(null, replace: true);
    expect(controller.stateOf('c1'), isNull);
  });

  test('replace drops unnamed comments; merge keeps them', () {
    final controller = CommentLikesController(
      setLike: (id, {required liked}) async =>
          _result(id, liked: liked, count: 1),
    );
    addTearDown(controller.dispose);
    controller.adopt(<String, CommentLikeState>{'c1': _three}, replace: true);
    controller.adopt(<String, CommentLikeState>{'c2': _zero}, replace: false);
    expect(controller.stateOf('c1'), _three);
    expect(controller.stateOf('c2'), _zero);
    controller.adopt(<String, CommentLikeState>{'c2': _three}, replace: true);
    expect(controller.stateOf('c1'), isNull);
    expect(controller.stateOf('c2'), _three);
  });

  test(
    'a toggle is optimistic and adopts the server answer verbatim',
    () async {
      final pending = Completer<CommentLikeResult>();
      final sent = <(String, bool)>[];
      final controller = CommentLikesController(
        setLike: (id, {required liked}) {
          sent.add((id, liked));
          return pending.future;
        },
      );
      addTearDown(controller.dispose);
      controller.adopt(<String, CommentLikeState>{'c1': _three}, replace: true);

      final outcome = controller.toggle('c1');
      expect(
        controller.stateOf('c1'),
        const CommentLikeState(likeCount: 4, callerLiked: true),
      );
      expect(controller.isPending('c1'), isTrue);
      // Single-flight: a second tap while waiting does nothing.
      expect(await controller.toggle('c1'), CommentLikeToggleOutcome.ignored);
      expect(sent, <(String, bool)>[('c1', true)]);

      pending.complete(_result('c1', liked: true, count: 9));
      expect(await outcome, CommentLikeToggleOutcome.applied);
      expect(
        controller.stateOf('c1'),
        const CommentLikeState(likeCount: 9, callerLiked: true),
      );
      expect(controller.isPending('c1'), isFalse);
    },
  );

  test('a failure restores the state the tap started from', () async {
    final controller = CommentLikesController(
      setLike: (id, {required liked}) async => throw StateError('offline'),
    );
    addTearDown(controller.dispose);
    controller.adopt(<String, CommentLikeState>{
      'c1': const CommentLikeState(likeCount: 1, callerLiked: true),
    }, replace: true);
    expect(await controller.toggle('c1'), CommentLikeToggleOutcome.reverted);
    expect(
      controller.stateOf('c1'),
      const CommentLikeState(likeCount: 1, callerLiked: true),
    );
  });

  test('a refresh during a toggle does not overwrite it', () async {
    final pending = Completer<CommentLikeResult>();
    final controller = CommentLikesController(
      setLike: (id, {required liked}) => pending.future,
    );
    addTearDown(controller.dispose);
    controller.adopt(<String, CommentLikeState>{'c1': _zero}, replace: true);
    final outcome = controller.toggle('c1');
    controller.adopt(<String, CommentLikeState>{'c1': _zero}, replace: true);
    expect(
      controller.stateOf('c1'),
      const CommentLikeState(likeCount: 1, callerLiked: true),
    );
    pending.complete(_result('c1', liked: true, count: 1));
    await outcome;
    expect(
      controller.stateOf('c1'),
      const CommentLikeState(likeCount: 1, callerLiked: true),
    );
  });

  test('a like that succeeds after every heart went does not bring one '
      'back', () async {
    final pending = Completer<CommentLikeResult>();
    final controller = CommentLikesController(
      setLike: (id, {required liked}) => pending.future,
    );
    addTearDown(controller.dispose);
    controller.adopt(<String, CommentLikeState>{'c1': _three}, replace: true);
    final toggled = controller.toggle('c1');
    // The view came back without comment likes while the like was in
    // flight: `null` removes every heart, pending or not.
    controller.adopt(null, replace: true);
    expect(controller.stateOf('c1'), isNull);
    pending.complete(_result('c1', liked: true, count: 4));
    expect(await toggled, CommentLikeToggleOutcome.applied);
    expect(controller.stateOf('c1'), isNull);
    expect(controller.isPending('c1'), isFalse);
  });

  test('an unknown comment is ignored', () async {
    final controller = CommentLikesController(
      setLike: (id, {required liked}) async =>
          _result(id, liked: liked, count: 1),
    );
    addTearDown(controller.dispose);
    expect(await controller.toggle('c1'), CommentLikeToggleOutcome.ignored);
  });

  test('the pre-gate is watched only once hearts exist', () async {
    var watched = 0;
    final access = StreamController<bool>();
    addTearDown(access.close);
    final controller = CommentLikesController(
      setLike: (id, {required liked}) async =>
          _result(id, liked: liked, count: 1),
      watchCanSeeLikers: () {
        watched++;
        return access.stream;
      },
    );
    addTearDown(controller.dispose);
    controller.adopt(null, replace: true);
    expect(watched, 0);
    controller.adopt(<String, CommentLikeState>{'c1': _zero}, replace: true);
    controller.adopt(<String, CommentLikeState>{'c1': _zero}, replace: true);
    expect(watched, 1);
    expect(controller.canSeeLikers, isFalse);
    access.add(true);
    await Future<void>.delayed(Duration.zero);
    expect(controller.canSeeLikers, isTrue);
    access.addError(StateError('denied'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.canSeeLikers, isFalse);
  });
}
