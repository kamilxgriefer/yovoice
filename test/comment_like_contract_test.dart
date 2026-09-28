// Comment likes on the wire (ADR-230, spec §3.4-§3.6): the optional
// `commentLikes` view key is accepted only when the request carried the flag
// and is then parsed strictly (one entry per projected comment, exact
// `{likeCount, callerLiked}`); every earlier payload parses unchanged; the
// toggle response is exact.

import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/likers/data/models/comment_like.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';

import 'support/comment_like_fixtures.dart';

void main() {
  group('CommentLikeState', () {
    test('parses the exact two keys', () {
      expect(
        CommentLikeState.parse(likeStateWire(3, liked: true)),
        const CommentLikeState(likeCount: 3, callerLiked: true),
      );
    });

    test('refuses extra, missing and malformed keys', () {
      for (final bad in <Object?>[
        null,
        <Object?, Object?>{'likeCount': 1},
        <Object?, Object?>{'likeCount': 1, 'callerLiked': false, 'x': 1},
        <Object?, Object?>{'likeCount': -1, 'callerLiked': false},
        <Object?, Object?>{'likeCount': 1.0, 'callerLiked': false},
        <Object?, Object?>{'likeCount': 1, 'callerLiked': 'true'},
      ]) {
        expect(() => CommentLikeState.parse(bad), throwsFormatException);
      }
    });

    test('parseCommentLikes requires the key set to equal the comment ids', () {
      expect(
        parseCommentLikes(
          <Object?, Object?>{'c1': likeStateWire(0), 'c2': likeStateWire(2)},
          <String>['c1', 'c2'],
        ),
        <String, CommentLikeState>{
          'c1': const CommentLikeState(likeCount: 0, callerLiked: false),
          'c2': const CommentLikeState(likeCount: 2, callerLiked: false),
        },
      );
      expect(
        () => parseCommentLikes(
          <Object?, Object?>{'c1': likeStateWire(0)},
          <String>['c1', 'c2'],
        ),
        throwsFormatException,
      );
      expect(
        () => parseCommentLikes(
          <Object?, Object?>{
            'c1': likeStateWire(0),
            'withheld': likeStateWire(1),
          },
          <String>['c1'],
        ),
        throwsFormatException,
      );
      expect(
        () => parseCommentLikes(const <Object?>[], <String>[]),
        throwsFormatException,
      );
    });
  });

  group('CommentLikeResult', () {
    Map<Object?, Object?> wire({
      String parentKey = 'momentId',
      Object? parentId = 'm1',
      Object? commentId = 'c1',
      Object? liked = true,
      Object? changed = true,
      Object? likeCount = 4,
    }) => <Object?, Object?>{
      parentKey: parentId,
      'commentId': commentId,
      'liked': liked,
      'changed': changed,
      'likeCount': likeCount,
    };

    CommentLikeResult parse(Object? value, {String parentKey = 'momentId'}) =>
        CommentLikeResult.parse(
          value,
          parentKey: parentKey,
          parentId: 'm1',
          commentId: 'c1',
          liked: true,
        );

    test('parses the exact response for either parent', () {
      final result = parse(wire());
      expect(result.liked, isTrue);
      expect(result.changed, isTrue);
      expect(result.likeCount, 4);
      expect(
        result.state,
        const CommentLikeState(likeCount: 4, callerLiked: true),
      );
      expect(
        parse(wire(parentKey: 'reelId'), parentKey: 'reelId').likeCount,
        4,
      );
    });

    test('refuses a foreign target, another state and any shape drift', () {
      expect(() => parse(wire(parentId: 'm2')), throwsFormatException);
      expect(() => parse(wire(commentId: 'c2')), throwsFormatException);
      expect(() => parse(wire(liked: false)), throwsFormatException);
      expect(() => parse(wire(likeCount: -1)), throwsFormatException);
      expect(() => parse(wire(changed: 'yes')), throwsFormatException);
      expect(() => parse(wire(parentKey: 'reelId')), throwsFormatException);
      expect(
        () => parse(<Object?, Object?>{...wire(), 'extra': 1}),
        throwsFormatException,
      );
      expect(
        () => parse(<Object?, Object?>{...wire()}..remove('changed')),
        throwsFormatException,
      );
    });
  });

  group('VoiceMomentViewV2.parse', () {
    test('without the flag: the six keys parse and commentLikes is null', () {
      final view = VoiceMomentViewV2.parse(voiceViewWire());
      expect(view.comments.single.id, 'c1');
      expect(view.commentLikes, isNull);
    });

    test('without the flag: a commentLikes key is refused', () {
      expect(
        () => VoiceMomentViewV2.parse(
          voiceViewWire(
            commentLikes: <Object?, Object?>{'c1': likeStateWire(1)},
          ),
        ),
        throwsFormatException,
      );
    });

    test('with the flag: seven keys parse strictly', () {
      final view = VoiceMomentViewV2.parse(
        voiceViewWire(
          comments: <Map<Object?, Object?>>[
            voiceCommentWire('c1'),
            voiceCommentWire('c2', offsetMillis: 1),
          ],
          commentLikes: <Object?, Object?>{
            'c1': likeStateWire(3, liked: true),
            'c2': likeStateWire(0),
          },
        ),
        expectCommentLikes: true,
      );
      expect(view.commentLikes, <String, CommentLikeState>{
        'c1': const CommentLikeState(likeCount: 3, callerLiked: true),
        'c2': const CommentLikeState(likeCount: 0, callerLiked: false),
      });
    });

    test('with the flag: an id mismatch or a bad entry throws', () {
      expect(
        () => VoiceMomentViewV2.parse(
          voiceViewWire(
            commentLikes: <Object?, Object?>{'other': likeStateWire(1)},
          ),
          expectCommentLikes: true,
        ),
        throwsFormatException,
      );
      expect(
        () => VoiceMomentViewV2.parse(
          voiceViewWire(
            commentLikes: <Object?, Object?>{
              'c1': <Object?, Object?>{'likeCount': 1},
            },
          ),
          expectCommentLikes: true,
        ),
        throwsFormatException,
      );
    });

    test('with the flag: an absent map means no hearts, not an error', () {
      final view = VoiceMomentViewV2.parse(
        voiceViewWire(),
        expectCommentLikes: true,
      );
      expect(view.commentLikes, isNull);
      expect(view.comments, hasLength(1));
    });
  });

  group('ReelView.fromWire', () {
    test('an earlier payload parses unchanged', () {
      final view = ReelView.fromWire(reelViewWire());
      expect(view.comments.single.id, 'c1');
      expect(view.commentLikes, isNull);
      expect(
        () => ReelView.fromWire(
          reelViewWire(
            commentLikes: <Object?, Object?>{'c1': likeStateWire(1)},
          ),
        ),
        throwsFormatException,
      );
    });

    test('the optional key parses strictly when requested', () {
      final view = ReelView.fromWire(
        reelViewWire(commentLikes: <Object?, Object?>{'c1': likeStateWire(7)}),
        expectCommentLikes: true,
      );
      expect(
        view.commentLikes!['c1'],
        const CommentLikeState(likeCount: 7, callerLiked: false),
      );
      expect(
        () => ReelView.fromWire(
          reelViewWire(commentLikes: <Object?, Object?>{}),
          expectCommentLikes: true,
        ),
        throwsFormatException,
      );
      expect(
        ReelView.fromWire(
          reelViewWire(),
          expectCommentLikes: true,
        ).commentLikes,
        isNull,
      );
    });
  });
}
