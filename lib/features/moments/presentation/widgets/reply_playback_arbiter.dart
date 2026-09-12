import 'package:flutter/foundation.dart';

/// Which voice reply — if any — is allowed to sound inside ONE thread host.
///
/// A Voice Moment surface owns exactly one main transport (the detail
/// screen's player, the feed's shared player, later a Reel's coordinator)
/// and a thread that can hold many voice replies, each with its own tiny
/// player. Nothing arbitrated them before: starting a reply left the main
/// recording playing underneath it, and two replies could overlap each
/// other (`moment_comments_screen.dart` created an `AudioPlayer` per voice
/// comment with no cross-talk). The product rule is the opposite — a reply
/// never plays over the recording it answers.
///
/// The arbiter is deliberately tiny: it holds the id of the reply that is
/// currently sounding and nothing else. No second transport, no service, no
/// platform channel.
///
/// * [replyStarted] pauses the main player through [onPauseMainPlayback]
///   (the host decides what "pause" means and only acts while it is really
///   playing) and publishes the new id; every other reply observes the
///   change and stops itself.
/// * [replyStopped] clears the id when that reply pauses or completes.
/// * [mainPlaybackStarted] clears it when the main recording starts, which
///   the sounding reply observes and stops on.
///
/// Disposal is the host's: the widget that creates it disposes it.
class ReplyPlaybackArbiter extends ValueNotifier<String?> {
  ReplyPlaybackArbiter({this.onPauseMainPlayback}) : super(null);

  /// Pauses the host's main recording. The host must make this a no-op when
  /// nothing is playing — a deliberate pause must never be manufactured.
  final VoidCallback? onPauseMainPlayback;

  /// The reply that is sounding right now, or null.
  String? get activeReplyId => value;

  void replyStarted(String commentId) {
    if (commentId.isEmpty) return;
    onPauseMainPlayback?.call();
    value = commentId;
  }

  void replyStopped(String commentId) {
    if (value == commentId) value = null;
  }

  /// The main recording took over: whichever reply was sounding stops.
  void mainPlaybackStarted() => value = null;
}
