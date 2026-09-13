// The reply-playback arbiter: a voice reply never sounds over the main
// recording, and two replies never sound over each other.
//
// Before this existed every voice comment owned an AudioPlayer with no
// arbitration at all — the thread could play three sources at once on top
// of the Moment being answered.

import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/moments/presentation/widgets/reply_playback_arbiter.dart';

void main() {
  group('reply playback arbiter', () {
    test('starting a reply pauses the main player and publishes the id', () {
      var pauses = 0;
      final arbiter = ReplyPlaybackArbiter(onPauseMainPlayback: () => pauses++);
      addTearDown(arbiter.dispose);

      expect(arbiter.activeReplyId, isNull);
      arbiter.replyStarted('c1');

      expect(pauses, 1);
      expect(arbiter.activeReplyId, 'c1');
    });

    test('a second reply takes the floor from the first', () {
      final arbiter = ReplyPlaybackArbiter();
      addTearDown(arbiter.dispose);
      final seen = <String?>[];
      arbiter.addListener(() => seen.add(arbiter.value));

      arbiter.replyStarted('c1');
      arbiter.replyStarted('c2');

      // The first reply observes that it is no longer the active id and
      // stops itself; only one id is ever published.
      expect(seen, <String?>['c1', 'c2']);
      expect(arbiter.activeReplyId, 'c2');
    });

    test('the main recording starting clears whichever reply was sounding', () {
      final arbiter = ReplyPlaybackArbiter();
      addTearDown(arbiter.dispose);

      arbiter.replyStarted('c1');
      arbiter.mainPlaybackStarted();

      expect(arbiter.activeReplyId, isNull);
    });

    test('a reply only clears its own id', () {
      final arbiter = ReplyPlaybackArbiter();
      addTearDown(arbiter.dispose);

      arbiter.replyStarted('c2');
      arbiter.replyStopped('c1');
      expect(arbiter.activeReplyId, 'c2');

      arbiter.replyStopped('c2');
      expect(arbiter.activeReplyId, isNull);
    });

    test('an empty id is refused rather than published', () {
      var pauses = 0;
      final arbiter = ReplyPlaybackArbiter(onPauseMainPlayback: () => pauses++);
      addTearDown(arbiter.dispose);

      arbiter.replyStarted('');

      expect(arbiter.activeReplyId, isNull);
      expect(pauses, 0);
    });
  });
}
