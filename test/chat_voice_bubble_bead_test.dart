// Refine-look §8.3 — the chat voice bubble on the voice-bead API (R13 / R14,
// variant B).
//
// Pins what the Chats batch asks of a voice bubble:
//
//   * incoming: the 34 px brand bead (gloss), lit only while THIS clip plays;
//   * outgoing: the white @ .22 bead on the brand gradient, never lit;
//   * the waveform follows the player's REAL position through one listenable
//     — reset to null on completion, stop and a source change, never moved
//     by an update the player sends after those — and a position tick never
//     rebuilds the bubble;
//   * one clip at a time (W3): starting or resuming a clip pauses the one
//     that plays and lets one that loads go, in the thread and across the
//     shared-media tab, so exactly one bead glows;
//   * nothing schedules a frame while the bubble is at rest;
//   * high contrast keeps the bead's gradient but no glow and no gloss;
//   * the shared-media Voice tab keeps its legacy row and tracks nothing.
//
// Widget tests prove structure and state, not pixels; the rendered frames
// live in `test/slim_chats_capture.dart` (`voice-playing`).

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_voice_playback_source.dart';
import 'package:yovoice/features/messages/presentation/widgets/message_bubble.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/voice/voice_player_row.dart';
import 'package:yovoice/shared/widgets/waveform/yo_waveform.dart';

const _me = 'me';
const _them = 'them';

Message _voice({
  String id = 'voice-1',
  String sender = _them,
  String mediaUrl = 'https://example.test/voice-1.m4a',
  int durationSeconds = 40,
}) => Message(
  id: id,
  conversationId: 'conversation',
  senderId: sender,
  type: MessageType.voice,
  content: '',
  mediaUrl: mediaUrl,
  durationSeconds: durationSeconds,
  sentAt: DateTime.utc(2026, 9, 25, 12),
  readBy: const [],
  reactions: const {},
);

Widget _host(
  Message message, {
  required AudioPlayer Function() player,
  bool light = false,
  bool highContrast = false,
}) => MaterialApp(
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  themeAnimationDuration: Duration.zero,
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(highContrast: highContrast),
      child: Scaffold(
        body: Center(
          child: MessageBubble(
            message: message,
            currentUserId: _me,
            onLongPress: () {},
            audioPlayerFactory: player,
          ),
        ),
      ),
    ),
  ),
);

Finder _tap(String id) => find.byKey(ValueKey<String>('direct-voice-$id'));

YoGradientDisc _bead(WidgetTester tester) =>
    tester.widget<YoGradientDisc>(find.byType(YoGradientDisc));

List<BoxShadow> _beadShadows(WidgetTester tester) {
  final fill = tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byType(YoGradientDisc),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return (fill.decoration! as BoxDecoration).boxShadow ?? const <BoxShadow>[];
}

bool _hasGloss(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(YoGradientDisc),
        matching: find.byType(DecoratedBox),
      ),
    )
    .any(
      (box) =>
          box.decoration is BoxDecoration &&
          (box.decoration as BoxDecoration).gradient == AppFinish.discGloss,
    );

ValueListenable<double?> _progress(WidgetTester tester) =>
    tester.widget<VoicePlayerRow>(find.byType(VoicePlayerRow)).progress!;

YoWaveform _wave(WidgetTester tester) =>
    tester.widget<YoWaveform>(find.byType(YoWaveform));

/// A thread of voice bubbles, each on its own player (as in `ChatScreen`).
Widget _thread(
  List<Message> messages,
  Map<String, AudioPlayer> players, {
  Future<Uint8List?> Function(String? reference, int maxBytes)? loader,
  DirectVoiceSourcePreparer? preparer,
  List<Widget> trailing = const <Widget>[],
}) => MaterialApp(
  theme: AppTheme.darkTheme,
  home: Scaffold(
    // A Column keeps each keyed bubble's state when the thread changes.
    body: SingleChildScrollView(
      child: Column(
        children: [
          for (final message in messages)
            MessageBubble(
              key: ValueKey<String>(message.id),
              message: message,
              currentUserId: _me,
              onLongPress: () {},
              audioPlayerFactory: () => players[message.id]!,
              privateMediaLoader: loader,
              voiceSourcePreparer: preparer,
            ),
          ...trailing,
        ],
      ),
    ),
  ),
);

Finder _rowOf(String id) =>
    find.ancestor(of: _tap(id), matching: find.byType(VoicePlayerRow));

VoicePlayerRowStatus _status(WidgetTester tester, String id) =>
    tester.widget<VoicePlayerRow>(_rowOf(id)).status;

YoGradientDisc _beadOf(WidgetTester tester, String id) =>
    tester.widget<YoGradientDisc>(
      find.descendant(of: _rowOf(id), matching: find.byType(YoGradientDisc)),
    );

/// Every voice bead in the tree that is lit right now.
int _litBeads(WidgetTester tester) => tester
    .widgetList<YoGradientDisc>(find.byType(YoGradientDisc))
    .where((bead) => bead.emphasis == YoDiscEmphasis.lit)
    .length;

void main() {
  group('incoming voice bubble', () {
    for (final light in [false, true]) {
      final theme = light ? 'Pearl' : 'Dark';
      testWidgets('$theme: the 34 px brand bead with gloss, lit only while '
          'this clip plays, over the variant-B inks', (tester) async {
        final player = _PositionPlayer();
        await tester.pumpWidget(
          _host(_voice(), player: () => player, light: light),
        );
        await tester.pumpAndSettle();
        final palette = light ? AppPalette.light : AppPalette.dark;
        final scheme =
            (light ? AppTheme.lightTheme : AppTheme.darkTheme).colorScheme;

        expect(_bead(tester).size, 34);
        expect(_bead(tester).tone, YoDiscTone.brand);
        expect(_bead(tester).gloss, isTrue);
        expect(_bead(tester).emphasis, YoDiscEmphasis.rest);
        expect(_beadShadows(tester), hasLength(1), reason: 'contact only');
        expect(_wave(tester).color, palette.waveUnplayed);
        expect(
          _wave(tester).playedGradient,
          AppGradients.voicePlayed(scheme, palette),
        );

        await tester.tap(_tap('voice-1'));
        await tester.pumpAndSettle();
        expect(player.playCalls, 1);
        expect(_bead(tester).emphasis, YoDiscEmphasis.lit);
        expect(
          _beadShadows(tester),
          AppFinish.discShadow(palette, 34, YoDiscEmphasis.lit),
          reason: 'the brand glow of the one clip that plays',
        );

        await tester.tap(_tap('voice-1'));
        await tester.pumpAndSettle();
        expect(player.pauseCalls, 1);
        expect(_bead(tester).emphasis, YoDiscEmphasis.rest);

        await tester.tap(_tap('voice-1'));
        await tester.pumpAndSettle();
        expect(player.resumeCalls, 1);
        expect(_bead(tester).emphasis, YoDiscEmphasis.lit);

        player.complete();
        await tester.pumpAndSettle();
        expect(_bead(tester).emphasis, YoDiscEmphasis.rest);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('outgoing voice bubble', () {
    for (final light in [false, true]) {
      final theme = light ? 'Pearl' : 'Dark';
      testWidgets('$theme: the white @ .22 bead that never lights, white '
          'played over the measured unplayed white', (tester) async {
        final player = _PositionPlayer();
        await tester.pumpWidget(
          _host(
            _voice(sender: _me),
            player: () => player,
            light: light,
          ),
        );
        await tester.pumpAndSettle();

        for (final playing in [false, true]) {
          if (playing) {
            await tester.tap(_tap('voice-1'));
            await tester.pumpAndSettle();
            expect(
              tester.widget<VoicePlayerRow>(find.byType(VoicePlayerRow)).status,
              VoicePlayerRowStatus.playing,
            );
          }
          expect(_bead(tester).size, 34);
          expect(_bead(tester).tone, YoDiscTone.onBrand);
          expect(_bead(tester).gloss, isFalse);
          expect(_bead(tester).emphasis, YoDiscEmphasis.rest);
          expect(_beadShadows(tester), isEmpty, reason: 'no light at all');
          expect(_hasGloss(tester), isFalse);
          expect(_wave(tester).color, AppFinish.outgoingWaveUnplayed);
          expect(_wave(tester).playedColor, AppFinish.outgoingWavePlayed);
          expect(_wave(tester).playedGradient, isNull);
        }
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the real position', () {
    testWidgets('follows the player, pours, and resets to null on '
        'completion; a late update never brings the fill back', (tester) async {
      final player = _PositionPlayer(duration: const Duration(seconds: 40));
      await tester.pumpWidget(_host(_voice(), player: () => player));
      await tester.pumpAndSettle();
      expect(_progress(tester).value, isNull);
      expect(_wave(tester).progress, isNull, reason: 'a still silhouette');

      await tester.tap(_tap('voice-1'));
      await tester.pumpAndSettle();
      player.emitPosition(const Duration(seconds: 10));
      await tester.pump();
      expect(_progress(tester).value, closeTo(.25, 1e-9));
      await tester.pumpAndSettle();
      expect(_wave(tester).progress, closeTo(.25, 1e-9));

      player.emitPosition(const Duration(seconds: 20));
      // The event lands after the first pump's (absent) frame; the second
      // builds the row and starts the pour.
      await tester.pump();
      await tester.pump();
      expect(_wave(tester).progress, closeTo(.25, 1e-9));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        _wave(tester).progress,
        allOf(greaterThan(.25), lessThan(.5)),
        reason: 'the fill pours toward the new real position',
      );
      await tester.pumpAndSettle();
      expect(_wave(tester).progress, closeTo(.5, 1e-9));

      // Pausing keeps the real paused position.
      await tester.tap(_tap('voice-1'));
      await tester.pumpAndSettle();
      expect(_progress(tester).value, closeTo(.5, 1e-9));
      await tester.tap(_tap('voice-1'));
      await tester.pumpAndSettle();

      // audioplayers reports completion, then `completed`, then one last
      // position (its updater's stopAndUpdate).
      player.complete(trailing: const Duration(seconds: 40));
      await tester.pumpAndSettle();
      expect(_progress(tester).value, isNull);
      expect(_wave(tester).progress, isNull);

      player.emitPosition(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(
        _progress(tester).value,
        isNull,
        reason: 'no position counts once the clip has finished',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a stop resets it to null', (tester) async {
      final player = _PositionPlayer();
      await tester.pumpWidget(_host(_voice(), player: () => player));
      await tester.tap(_tap('voice-1'));
      await tester.pumpAndSettle();
      player.emitPosition(const Duration(seconds: 12));
      await tester.pumpAndSettle();
      expect(_progress(tester).value, closeTo(.3, 1e-9));

      await player.stop();
      await tester.pumpAndSettle();
      expect(_progress(tester).value, isNull);
      expect(_wave(tester).progress, isNull);
    });

    testWidgets('a source change resets it to null and the old clip can '
        'no longer move it', (tester) async {
      final player = _PositionPlayer();
      await tester.pumpWidget(_host(_voice(), player: () => player));
      await tester.tap(_tap('voice-1'));
      await tester.pumpAndSettle();
      player.emitPosition(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(_progress(tester).value, closeTo(.75, 1e-9));

      // The old clip's stop has not answered yet: the reset must not wait
      // for the player to report `stopped`.
      final gate = player.stopGate = Completer<void>();
      await tester.pumpWidget(
        _host(
          _voice(id: 'voice-2', mediaUrl: 'https://example.test/voice-2.m4a'),
          player: () => player,
        ),
      );
      expect(player.stopCalls, 1);
      expect(_progress(tester).value, isNull);
      await tester.pumpAndSettle();
      expect(_wave(tester).progress, isNull);
      expect(_bead(tester).emphasis, YoDiscEmphasis.rest);

      // A late update from the replaced clip, before and after its stop.
      player.emitPosition(const Duration(seconds: 35));
      await tester.pumpAndSettle();
      expect(_progress(tester).value, isNull);
      player.stopGate = null;
      gate.complete();
      await tester.pumpAndSettle();
      player.emitPosition(const Duration(seconds: 36));
      await tester.pumpAndSettle();
      expect(_progress(tester).value, isNull);
      expect(_wave(tester).progress, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the completion event alone clears the fill', (tester) async {
      final player = _PositionPlayer();
      await tester.pumpWidget(_host(_voice(), player: () => player));
      await tester.tap(_tap('voice-1'));
      await tester.pumpAndSettle();
      player.emitPosition(const Duration(seconds: 40));
      await tester.pumpAndSettle();
      expect(_progress(tester).value, closeTo(1, 1e-9));

      player.complete(reportsState: false);
      await tester.pumpAndSettle();
      expect(_progress(tester).value, isNull);
      expect(_wave(tester).progress, isNull);
    });

    testWidgets('a position tick repaints the bars and never rebuilds the '
        'bubble', (tester) async {
      final player = _PositionPlayer();
      await tester.pumpWidget(_host(_voice(), player: () => player));
      await tester.tap(_tap('voice-1'));
      await tester.pumpAndSettle();

      final row = tester.widget<VoicePlayerRow>(find.byType(VoicePlayerRow));
      final bead = _bead(tester);
      for (final seconds in [4, 8, 12, 16]) {
        player.emitPosition(Duration(seconds: seconds));
        await tester.pumpAndSettle();
        expect(_wave(tester).progress, closeTo(seconds / 40, 1e-9));
      }
      expect(
        identical(
          tester.widget<VoicePlayerRow>(find.byType(VoicePlayerRow)),
          row,
        ),
        isTrue,
        reason: 'the bubble did not rebuild its row for a position tick',
      );
      expect(identical(_bead(tester), bead), isTrue);
    });

    testWidgets('without a reported length it divides by the recorded one', (
      tester,
    ) async {
      final player = _PositionPlayer(reportsDuration: false);
      await tester.pumpWidget(
        _host(_voice(durationSeconds: 20), player: () => player),
      );
      await tester.tap(_tap('voice-1'));
      await tester.pumpAndSettle();
      player.emitPosition(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(_progress(tester).value, closeTo(.25, 1e-9));
    });
  });

  group('one clip at a time (W3)', () {
    testWidgets('a second incoming clip pauses the first: one clip sounds and '
        'exactly one bead glows', (tester) async {
      final a = _PositionPlayer(duration: const Duration(seconds: 40));
      final b = _PositionPlayer(duration: const Duration(seconds: 30));
      await tester.pumpWidget(
        _thread(
          [
            _voice(id: 'a', mediaUrl: 'https://example.test/a.m4a'),
            _voice(
              id: 'b',
              mediaUrl: 'https://example.test/b.m4a',
              durationSeconds: 30,
            ),
          ],
          {'a': a, 'b': b},
        ),
      );
      await tester.pumpAndSettle();
      expect(_litBeads(tester), 0);

      await tester.tap(_tap('a'));
      await tester.pumpAndSettle();
      a.emitPosition(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(_status(tester, 'a'), VoicePlayerRowStatus.playing);
      expect(_litBeads(tester), 1);

      await tester.tap(_tap('b'));
      await tester.pumpAndSettle();
      expect(a.pauseCalls, 1, reason: 'the first clip stands down');
      expect(a.stopCalls, 0, reason: 'paused, not thrown away');
      expect(_status(tester, 'a'), VoicePlayerRowStatus.paused);
      expect(_beadOf(tester, 'a').emphasis, YoDiscEmphasis.rest);
      expect(
        tester.widget<VoicePlayerRow>(_rowOf('a')).progress!.value,
        closeTo(.25, 1e-9),
        reason: 'the paused clip keeps its real position',
      );
      expect(_status(tester, 'b'), VoicePlayerRowStatus.playing);
      expect(_beadOf(tester, 'b').emphasis, YoDiscEmphasis.lit);
      expect(_litBeads(tester), 1);

      // Resuming the first hands the floor back.
      await tester.tap(_tap('a'));
      await tester.pumpAndSettle();
      expect(a.resumeCalls, 1);
      expect(b.pauseCalls, 1);
      expect(_status(tester, 'a'), VoicePlayerRowStatus.playing);
      expect(_status(tester, 'b'), VoicePlayerRowStatus.paused);
      expect(_beadOf(tester, 'a').emphasis, YoDiscEmphasis.lit);
      expect(_litBeads(tester), 1);

      // Pausing the one that plays leaves nothing lit and pauses nobody else.
      await tester.tap(_tap('a'));
      await tester.pumpAndSettle();
      expect(a.pauseCalls, 2);
      expect(b.pauseCalls, 1);
      expect(_litBeads(tester), 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an outgoing clip takes the floor from an incoming one', (
      tester,
    ) async {
      final a = _PositionPlayer();
      final b = _PositionPlayer();
      await tester.pumpWidget(
        _thread(
          [
            _voice(id: 'a', mediaUrl: 'https://example.test/a.m4a'),
            _voice(
              id: 'b',
              sender: _me,
              mediaUrl: 'https://example.test/b.m4a',
            ),
          ],
          {'a': a, 'b': b},
        ),
      );
      await tester.tap(_tap('a'));
      await tester.pumpAndSettle();
      expect(_litBeads(tester), 1);

      await tester.tap(_tap('b'));
      await tester.pumpAndSettle();
      expect(a.pauseCalls, 1);
      expect(_status(tester, 'a'), VoicePlayerRowStatus.paused);
      expect(_status(tester, 'b'), VoicePlayerRowStatus.playing);
      expect(
        _litBeads(tester),
        0,
        reason: 'the outgoing bead never lights, and the paused one is out',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a clip still loading lets its load go when another starts, '
        'and a later tap loads it again', (tester) async {
      const privateA = 'gs://yovoice.test/voice/a.m4a';
      final held = Completer<Uint8List?>();
      var loads = 0;
      final prepared = <String>[];
      final a = _PositionPlayer();
      final b = _PositionPlayer();
      await tester.pumpWidget(
        _thread(
          [
            _voice(id: 'a', mediaUrl: privateA),
            _voice(id: 'b', mediaUrl: 'https://example.test/b.m4a'),
          ],
          {'a': a, 'b': b},
          loader: (reference, _) {
            expect(reference, privateA);
            loads += 1;
            return held.future;
          },
          preparer: (bytes, messageId) async {
            prepared.add(messageId);
            return PreparedDirectVoiceSource(
              source: BytesSource(bytes),
              dispose: () async {},
            );
          },
        ),
      );
      await tester.tap(_tap('a'));
      await tester.pump();
      expect(_status(tester, 'a'), VoicePlayerRowStatus.loading);

      await tester.tap(_tap('b'));
      await tester.pumpAndSettle();
      expect(_status(tester, 'a'), VoicePlayerRowStatus.idle);
      expect(_status(tester, 'b'), VoicePlayerRowStatus.playing);

      // The abandoned load lands late: it must not prepare or play anything.
      held.complete(Uint8List.fromList([1, 2, 3]));
      await tester.pumpAndSettle();
      expect(prepared, isEmpty);
      expect(a.playCalls, 0);
      expect(_status(tester, 'a'), VoicePlayerRowStatus.idle);
      expect(_status(tester, 'b'), VoicePlayerRowStatus.playing);
      expect(_litBeads(tester), 1);

      await tester.tap(_tap('a'));
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(prepared, ['a']);
      expect(a.playCalls, 1);
      expect(b.pauseCalls, 1);
      expect(_status(tester, 'a'), VoicePlayerRowStatus.playing);
      expect(_status(tester, 'b'), VoicePlayerRowStatus.paused);
      expect(_litBeads(tester), 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a clip the platform starts late pauses itself while another '
        'holds the floor', (tester) async {
      final a = _PositionPlayer();
      final b = _PositionPlayer();
      await tester.pumpWidget(
        _thread(
          [
            _voice(id: 'a', mediaUrl: 'https://example.test/a.m4a'),
            _voice(id: 'b', mediaUrl: 'https://example.test/b.m4a'),
          ],
          {'a': a, 'b': b},
        ),
      );
      await tester.tap(_tap('a'));
      await tester.pumpAndSettle();
      await tester.tap(_tap('b'));
      await tester.pumpAndSettle();
      expect(a.pauseCalls, 1);

      // A resume the platform had already queued lands now.
      a.emitState(PlayerState.playing);
      await tester.pumpAndSettle();
      expect(a.pauseCalls, 2);
      expect(_status(tester, 'a'), VoicePlayerRowStatus.paused);
      expect(_status(tester, 'b'), VoicePlayerRowStatus.playing);
      expect(b.pauseCalls, 0);
      expect(_litBeads(tester), 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a bubble that goes away while it plays frees the floor', (
      tester,
    ) async {
      final a = _PositionPlayer();
      final b = _PositionPlayer();
      final both = [
        _voice(id: 'a', mediaUrl: 'https://example.test/a.m4a'),
        _voice(id: 'b', mediaUrl: 'https://example.test/b.m4a'),
      ];
      await tester.pumpWidget(_thread(both, {'a': a, 'b': b}));
      await tester.tap(_tap('a'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_thread([both.last], {'b': b}));
      await tester.pumpAndSettle();
      expect(a.stopCalls, greaterThanOrEqualTo(1), reason: 'disposed');

      // Nobody holds the floor now, so a start on the remaining clip stands.
      b.emitState(PlayerState.playing);
      await tester.pumpAndSettle();
      expect(b.pauseCalls, 0);
      expect(_status(tester, 'b'), VoicePlayerRowStatus.playing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the floor spans the thread and the shared-media Voice tab', (
      tester,
    ) async {
      final a = _PositionPlayer();
      final shared = _PositionPlayer();
      await tester.pumpWidget(
        _thread(
          [_voice(id: 'a', mediaUrl: 'https://example.test/a.m4a')],
          {'a': a},
          trailing: [
            DirectMessageMediaPreview(
              // The same clip, mounted a second time.
              message: _voice(id: 'a', mediaUrl: 'https://example.test/a.m4a'),
              currentUserId: _me,
              audioPlayerFactory: () => shared,
            ),
          ],
        ),
      );
      final thread = find.descendant(
        of: find.byType(MessageBubble),
        matching: _tap('a'),
      );
      final tab = find.descendant(
        of: find.byType(DirectMessageMediaPreview),
        matching: _tap('a'),
      );

      await tester.tap(thread);
      await tester.pumpAndSettle();
      await tester.tap(tab);
      await tester.pumpAndSettle();
      expect(a.pauseCalls, 1, reason: 'the thread copy stands down');
      expect(shared.playCalls, 1);

      await tester.tap(thread);
      await tester.pumpAndSettle();
      expect(a.resumeCalls, 1);
      expect(shared.pauseCalls, 1, reason: 'and the tab copy in turn');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('nothing schedules a frame while the bubble is at rest', (
    tester,
  ) async {
    final player = _PositionPlayer();
    await tester.pumpWidget(_host(_voice(), player: () => player));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'never played');

    await tester.tap(_tap('voice-1'));
    await tester.pumpAndSettle();
    player.emitPosition(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: 'the pour stops at the real position; nothing extrapolates',
    );

    await tester.tap(_tap('voice-1'));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'paused');

    await tester.tap(_tap('voice-1'));
    await tester.pumpAndSettle();
    player.complete();
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'completed');
  });

  testWidgets('high contrast keeps the bead but no glow and no gloss', (
    tester,
  ) async {
    for (final light in [false, true]) {
      for (final mine in [false, true]) {
        final player = _PositionPlayer();
        await tester.pumpWidget(
          _host(
            _voice(sender: mine ? _me : _them),
            player: () => player,
            light: light,
            highContrast: true,
          ),
        );
        await tester.tap(_tap('voice-1'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<VoicePlayerRow>(find.byType(VoicePlayerRow)).status,
          VoicePlayerRowStatus.playing,
        );
        expect(
          _bead(tester).tone,
          mine ? YoDiscTone.onBrand : YoDiscTone.brand,
        );
        expect(_beadShadows(tester), isEmpty);
        expect(_hasGloss(tester), isFalse);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets('the shared-media Voice tab keeps its legacy row and tracks no '
      'position', (tester) async {
    final player = _PositionPlayer();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: DirectMessageMediaPreview(
            message: _voice(),
            currentUserId: _me,
            audioPlayerFactory: () => player,
          ),
        ),
      ),
    );
    expect(find.byType(YoGradientDisc), findsNothing);
    expect(
      tester.widget<VoicePlayerRow>(find.byType(VoicePlayerRow)).progress,
      isNull,
    );
    expect(player.positionListeners, 0);
  });
}

/// A player that behaves like `audioplayers`' `AudioPlayer` for the events
/// the bubble reads: `play` reports the length, then `playing`; `stop` and a
/// completion are followed by one trailing position, exactly like the
/// plugin's position updater (`stopAndUpdate`).
class _PositionPlayer implements AudioPlayer {
  _PositionPlayer({
    this.duration = const Duration(seconds: 40),
    this.reportsDuration = true,
  });

  final Duration duration;
  final bool reportsDuration;

  final StreamController<PlayerState> _states =
      StreamController<PlayerState>.broadcast();
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durations =
      StreamController<Duration>.broadcast();
  final StreamController<void> _completions =
      StreamController<void>.broadcast();

  int playCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  int stopCalls = 0;
  int positionListeners = 0;

  @override
  Stream<PlayerState> get onPlayerStateChanged => _states.stream;

  @override
  Stream<Duration> get onPositionChanged {
    positionListeners++;
    return _positions.stream;
  }

  @override
  Stream<Duration> get onDurationChanged => _durations.stream;

  @override
  Stream<void> get onPlayerComplete => _completions.stream;

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    playCalls++;
    if (reportsDuration) _durations.add(duration);
    _positions.add(Duration.zero);
    _states.add(PlayerState.playing);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _states.add(PlayerState.paused);
  }

  @override
  Future<void> resume() async {
    resumeCalls++;
    _states.add(PlayerState.playing);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    // A platform stop that has not answered yet (the plugin awaits its
    // method channel before it reports `stopped`).
    final gate = stopGate;
    if (gate != null) await gate.future;
    if (_states.isClosed) return;
    _states.add(PlayerState.stopped);
    _positions.add(Duration.zero);
  }

  /// Holds every [stop] until completed.
  Completer<void>? stopGate;

  void emitPosition(Duration position) => _positions.add(position);

  /// A state the platform reports on its own (a late start, for one).
  void emitState(PlayerState state) => _states.add(state);

  /// The plugin's completion: the event, then `completed`, then one trailing
  /// position. [reportsState] false sends the event alone (a player whose
  /// state stream lags), so the completion itself must clear the fill.
  void complete({Duration? trailing, bool reportsState = true}) {
    _completions.add(null);
    if (!reportsState) return;
    _states.add(PlayerState.completed);
    _positions.add(trailing ?? Duration.zero);
  }

  @override
  Future<void> dispose() async {
    await Future.wait([
      _states.close(),
      _positions.close(),
      _durations.close(),
      _completions.close(),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
