import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_video_playback_source.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_voice_playback_source.dart';
import 'package:yovoice/features/messages/presentation/widgets/message_bubble.dart';

void main() {
  for (final entry in <String, ThemeData>{
    'dark': AppTheme.darkTheme,
    'light': AppTheme.lightTheme,
  }.entries) {
    testWidgets('${entry.key} voice loading and failure stay readable', (
      tester,
    ) async {
      final load = Completer<Uint8List?>();
      await _pumpBubble(
        tester,
        _voiceMessage(id: 'voice-${entry.key}', mediaUrl: _voiceOne),
        loader: (_, _) => load.future,
        playerFactory: _FakeAudioPlayer.new,
        theme: entry.value,
      );

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();
      final palette = entry.value.extension<AppPalette>()!;
      final loading = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(loading.color, palette.textPrimary);

      load.complete(null);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${entry.key} image loading and error expose retry', (
      tester,
    ) async {
      final load = Completer<Uint8List?>();
      await _pumpBubble(
        tester,
        _imageMessage(id: 'image-${entry.key}', mediaUrl: _imageOne),
        loader: (_, _) => load.future,
        theme: entry.value,
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      load.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('Photo unavailable — retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('paused voice resumes from the same source and a new message '
      'drops cached bytes before playback', (tester) async {
    final player = _FakeAudioPlayer();
    final loadedReferences = <String>[];

    Future<Uint8List?> loader(String? reference, int maxBytes) async {
      loadedReferences.add(reference ?? '');
      return Uint8List.fromList(reference == _voiceOne ? [1, 2, 3] : [4, 5, 6]);
    }

    await _pumpBubble(
      tester,
      _voiceMessage(id: 'voice-1', mediaUrl: _voiceOne),
      loader: loader,
      playerFactory: () => player,
    );

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(player.playCount, 1);
    expect(player.resumeCount, 0);
    expect(loadedReferences, [_voiceOne]);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    expect(player.pauseCount, 1);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(
      player.playCount,
      1,
      reason: 'play(source) restarts from position 0',
    );
    expect(player.resumeCount, 1);
    expect(loadedReferences, [_voiceOne]);

    await _pumpBubble(
      tester,
      _voiceMessage(id: 'voice-2', mediaUrl: _voiceTwo),
      loader: loader,
      playerFactory: () => player,
    );
    await tester.pump();
    expect(player.stopCount, 1);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(loadedReferences, [_voiceOne, _voiceTwo]);
    expect(player.playCount, 2);
    expect(player.lastSource, isA<BytesSource>());
  });

  testWidgets('gs voice uses authenticated bytes and a native-safe source', (
    tester,
  ) async {
    final player = _FakeAudioPlayer();
    var loadCalls = 0;
    var prepareCalls = 0;
    var cleanupCalls = 0;
    await _pumpBubble(
      tester,
      _voiceMessage(id: 'native-voice', mediaUrl: _voiceOne),
      loader: (_, _) async {
        loadCalls++;
        return Uint8List.fromList([1, 2, 3]);
      },
      playerFactory: () => player,
      voiceSourcePreparer: (bytes, messageId) async {
        prepareCalls++;
        expect(bytes, Uint8List.fromList([1, 2, 3]));
        expect(messageId, 'native-voice');
        return PreparedDirectVoiceSource(
          source: DeviceFileSource('/private/tmp/native-voice.m4a'),
          dispose: () async => cleanupCalls++,
        );
      },
    );

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();

    expect(loadCalls, 1);
    expect(prepareCalls, 1);
    expect(player.lastSource, isA<DeviceFileSource>());

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(cleanupCalls, 1);
  });

  testWidgets('https voice streams directly and never invokes private loader', (
    tester,
  ) async {
    final player = _FakeAudioPlayer();
    var loadCalls = 0;
    const url = 'https://example.test/private-voice.m4a';
    await _pumpBubble(
      tester,
      _voiceMessage(id: 'legacy-https-voice', mediaUrl: url),
      loader: (_, _) async {
        loadCalls++;
        return Uint8List.fromList([1]);
      },
      playerFactory: () => player,
    );

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();

    expect(loadCalls, 0);
    expect(player.lastSource, isA<UrlSource>());
    expect((player.lastSource! as UrlSource).url, url);
  });

  for (final scenario in <({String label, String first, String second})>[
    (label: 'private', first: _voiceOne, second: _voiceTwo),
    (
      label: 'https',
      first: 'https://example.test/voice-one.m4a',
      second: 'https://example.test/voice-two.m4a',
    ),
  ]) {
    testWidgets(
      'late ${scenario.label} voice play is stopped before replacement plays',
      (tester) async {
        final player = _FakeAudioPlayer();
        final firstPlayGate = player.blockNextPlay();

        Future<Uint8List?> loader(String? reference, int _) async =>
            Uint8List.fromList(reference == scenario.first ? [1] : [2]);

        Future<PreparedDirectVoiceSource> prepare(
          Uint8List bytes,
          String messageId,
        ) async => PreparedDirectVoiceSource(
          source: DeviceFileSource('/private/tmp/$messageId.m4a'),
          dispose: () async {},
        );

        await _pumpBubble(
          tester,
          _voiceMessage(id: 'voice-one', mediaUrl: scenario.first),
          loader: loader,
          playerFactory: () => player,
          voiceSourcePreparer: prepare,
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('direct-voice-voice-one')),
        );
        await tester.pump();
        await tester.pump();
        expect(player.playStarted.isCompleted, isTrue);
        expect(player.commands, <String>['play-1:start']);

        await _pumpBubble(
          tester,
          _voiceMessage(id: 'voice-two', mediaUrl: scenario.second),
          loader: loader,
          playerFactory: () => player,
          voiceSourcePreparer: prepare,
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey<String>('direct-voice-voice-two')),
        );
        await tester.pump();

        expect(player.playCount, 1);
        expect(
          player.commands.indexOf('stop'),
          greaterThan(player.commands.indexOf('play-1:start')),
          reason: 'message replacement should interrupt the pending play',
        );

        firstPlayGate.complete();
        await tester.pump();
        await tester.pump();
        await tester.pump();

        final oldComplete = player.commands.indexOf('play-1:complete');
        final newStart = player.commands.indexOf('play-2:start');
        expect(oldComplete, greaterThanOrEqualTo(0));
        expect(newStart, greaterThan(oldComplete));
        expect(
          player.commands
              .sublist(oldComplete + 1, newStart)
              .where((command) => command == 'stop'),
          isNotEmpty,
          reason: 'a late old play must be stopped again before the new play',
        );
        expect(player.isPlaying, isTrue);
        if (scenario.label == 'https') {
          expect((player.lastSource! as UrlSource).url, scenario.second);
        } else {
          expect(
            (player.lastSource! as DeviceFileSource).path,
            '/private/tmp/voice-two.m4a',
          );
        }
      },
    );
  }

  testWidgets('closing chat stops a private voice play that completes late', (
    tester,
  ) async {
    final player = _FakeAudioPlayer();
    final playGate = player.blockNextPlay();
    await _pumpBubble(
      tester,
      _voiceMessage(id: 'voice-closing', mediaUrl: _voiceOne),
      loader: (_, _) async => Uint8List.fromList([1]),
      playerFactory: () => player,
      voiceSourcePreparer: (bytes, messageId) async =>
          PreparedDirectVoiceSource(
            source: DeviceFileSource('/private/tmp/$messageId.m4a'),
            dispose: () async {},
          ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('direct-voice-voice-closing')),
    );
    await tester.pump();
    await tester.pump();
    expect(player.playStarted.isCompleted, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    playGate.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final playComplete = player.commands.indexOf('play-1:complete');
    expect(playComplete, greaterThanOrEqualTo(0));
    expect(
      player.commands.skip(playComplete + 1),
      contains('stop'),
      reason: 'dispose must revoke a platform play that finishes afterward',
    );
    expect(player.isPlaying, isFalse);
    expect(player.disposed, isTrue);
  });

  testWidgets(
    'https photo uses its network reference, not private byte loader',
    (tester) async {
      var loadCalls = 0;
      const url = 'https://example.test/private-photo.jpg';
      await _pumpBubble(
        tester,
        _imageMessage(id: 'legacy-https-image', mediaUrl: url),
        loader: (_, _) async {
          loadCalls++;
          return _onePixelPng;
        },
      );
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<NetworkImage>());
      expect((image.image as NetworkImage).url, url);
      expect(loadCalls, 0);
    },
  );

  testWidgets('gs video resolves through authenticated bytes before playback', (
    tester,
  ) async {
    var loadCalls = 0;
    var maxBytes = 0;
    var prepareCalls = 0;
    var cleanupCalls = 0;
    await _pumpBubble(
      tester,
      _videoMessage(id: 'private-video', mediaUrl: _videoOne),
      loader: (_, limit) async {
        loadCalls++;
        maxBytes = limit;
        return Uint8List.fromList([1, 2, 3]);
      },
      videoSourcePreparer: (bytes, messageId, reference) async {
        prepareCalls++;
        expect(messageId, 'private-video');
        expect(reference, _videoOne);
        return _TestPreparedVideoSource(() => cleanupCalls++);
      },
    );

    await tester.tap(find.byKey(const ValueKey('direct-video-private-video')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(loadCalls, 1);
    expect(maxBytes, 64 * 1024 * 1024);
    expect(prepareCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(cleanupCalls, 1);
  });

  testWidgets('https video bypasses the private byte loader', (tester) async {
    var loadCalls = 0;
    await _pumpBubble(
      tester,
      _videoMessage(
        id: 'https-video',
        mediaUrl: 'https://example.test/private-video.mp4',
      ),
      loader: (_, _) async {
        loadCalls++;
        return Uint8List.fromList([1]);
      },
    );

    await tester.tap(find.byKey(const ValueKey('direct-video-https-video')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(loadCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('a changed image id/source never renders the previous image '
      'while the new private object is loading', (tester) async {
    final second = Completer<Uint8List?>();
    final loadedReferences = <String>[];

    Future<Uint8List?> loader(String? reference, int maxBytes) {
      loadedReferences.add(reference ?? '');
      if (reference == _imageTwo) return second.future;
      return Future<Uint8List?>.value(_onePixelPng);
    }

    await _pumpBubble(
      tester,
      _imageMessage(id: 'image-1', mediaUrl: _imageOne),
      loader: loader,
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);

    await _pumpBubble(
      tester,
      _imageMessage(id: 'image-2', mediaUrl: _imageTwo),
      loader: loader,
    );
    await tester.pump();

    expect(loadedReferences, [_imageOne, _imageTwo]);
    expect(
      find.byType(Image),
      findsNothing,
      reason: 'the first attachment must not appear under the second message',
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    second.complete(_onePixelPng);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets(
    'a late private voice load never plays under a replacement message',
    (tester) async {
      final first = Completer<Uint8List?>();
      final second = Completer<Uint8List?>();
      final preparations = <({List<int> bytes, String messageId})>[];
      final player = _FakeAudioPlayer();

      Future<Uint8List?> loader(String? reference, int _) =>
          reference == _voiceOne ? first.future : second.future;

      await _pumpBubble(
        tester,
        _voiceMessage(id: 'voice-1', mediaUrl: _voiceOne),
        loader: loader,
        playerFactory: () => player,
        voiceSourcePreparer: (bytes, messageId) async {
          preparations.add((bytes: bytes.toList(), messageId: messageId));
          return PreparedDirectVoiceSource(
            source: BytesSource(bytes),
            dispose: () async {},
          );
        },
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('direct-voice-voice-1')),
      );
      await tester.pump();

      await _pumpBubble(
        tester,
        _voiceMessage(id: 'voice-2', mediaUrl: _voiceTwo),
        loader: loader,
        playerFactory: () => player,
        voiceSourcePreparer: (bytes, messageId) async {
          preparations.add((bytes: bytes.toList(), messageId: messageId));
          return PreparedDirectVoiceSource(
            source: BytesSource(bytes),
            dispose: () async {},
          );
        },
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('direct-voice-voice-2')),
      );
      await tester.pump();

      first.complete(Uint8List.fromList([1, 1, 1]));
      await tester.pump();
      await tester.pump();
      expect(
        preparations,
        isEmpty,
        reason: 'bytes authorized for the old message must be discarded',
      );
      expect(player.playCount, 0);

      second.complete(Uint8List.fromList([2, 2, 2]));
      await tester.pump();
      await tester.pump();
      expect(preparations, hasLength(1));
      expect(preparations.single.bytes, <int>[2, 2, 2]);
      expect(preparations.single.messageId, 'voice-2');
      expect(player.playCount, 1);
    },
  );

  testWidgets(
    'account switch rejects late photo bytes for the same message reference',
    (tester) async {
      final first = Completer<Uint8List?>();
      final second = Completer<Uint8List?>();
      var loads = 0;
      Future<Uint8List?> loader(String? _, int __) {
        loads += 1;
        return loads == 1 ? first.future : second.future;
      }

      final message = _imageMessage(id: 'same-photo', mediaUrl: _imageOne);
      await _pumpBubble(
        tester,
        message,
        currentUserId: 'account-a',
        loader: loader,
      );
      expect(loads, 1);

      await _pumpBubble(
        tester,
        message,
        currentUserId: 'account-b',
        loader: loader,
      );
      await tester.pump();
      expect(loads, 2);

      first.complete(_onePixelPng);
      await tester.pump();
      await tester.pump();
      expect(
        find.byType(Image),
        findsNothing,
        reason: 'account A bytes must not render after ownership changes',
      );

      second.complete(_onePixelPng);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
    },
  );

  testWidgets(
    'account switch rejects late voice bytes for the same message reference',
    (tester) async {
      final first = Completer<Uint8List?>();
      final second = Completer<Uint8List?>();
      var loads = 0;
      final preparations = <List<int>>[];
      final player = _FakeAudioPlayer();
      Future<Uint8List?> loader(String? _, int __) {
        loads += 1;
        return loads == 1 ? first.future : second.future;
      }

      final message = _voiceMessage(id: 'same-voice', mediaUrl: _voiceOne);
      await _pumpBubble(
        tester,
        message,
        currentUserId: 'account-a',
        loader: loader,
        playerFactory: () => player,
        voiceSourcePreparer: (bytes, _) async {
          preparations.add(bytes.toList());
          return PreparedDirectVoiceSource(
            source: BytesSource(bytes),
            dispose: () async {},
          );
        },
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('direct-voice-same-voice')),
      );
      await tester.pump();

      await _pumpBubble(
        tester,
        message,
        currentUserId: 'account-b',
        loader: loader,
        playerFactory: () => player,
        voiceSourcePreparer: (bytes, _) async {
          preparations.add(bytes.toList());
          return PreparedDirectVoiceSource(
            source: BytesSource(bytes),
            dispose: () async {},
          );
        },
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('direct-voice-same-voice')),
      );
      await tester.pump();

      first.complete(Uint8List.fromList([1, 1, 1]));
      await tester.pump();
      await tester.pump();
      expect(preparations, isEmpty);
      expect(player.playCount, 0);

      second.complete(Uint8List.fromList([2, 2, 2]));
      await tester.pump();
      await tester.pump();
      expect(preparations, <List<int>>[
        <int>[2, 2, 2],
      ]);
      expect(player.playCount, 1);
    },
  );

  testWidgets(
    'account switch rejects late video bytes for the same message reference',
    (tester) async {
      final first = Completer<Uint8List?>();
      final second = Completer<Uint8List?>();
      var loads = 0;
      final preparations = <List<int>>[];
      Future<Uint8List?> loader(String? _, int __) {
        loads += 1;
        return loads == 1 ? first.future : second.future;
      }

      final message = _videoMessage(id: 'same-video', mediaUrl: _videoOne);
      Future<PreparedDirectVideoSource> prepare(
        Uint8List bytes,
        String _,
        String __,
      ) async {
        preparations.add(bytes.toList());
        return _TestPreparedVideoSource(() {});
      }

      await _pumpBubble(
        tester,
        message,
        currentUserId: 'account-a',
        loader: loader,
        videoSourcePreparer: prepare,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('direct-video-same-video')),
      );
      await tester.pump();

      await _pumpBubble(
        tester,
        message,
        currentUserId: 'account-b',
        loader: loader,
        videoSourcePreparer: prepare,
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('direct-video-same-video')),
      );
      await tester.pump();

      first.complete(Uint8List.fromList([1, 1, 1]));
      await tester.pump();
      await tester.pump();
      expect(preparations, isEmpty);

      second.complete(Uint8List.fromList([2, 2, 2]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(preparations, <List<int>>[
        <int>[2, 2, 2],
      ]);
    },
  );

  testWidgets(
    'a late private video load never attaches to a replacement tile',
    (tester) async {
      final first = Completer<Uint8List?>();
      final second = Completer<Uint8List?>();
      final preparations =
          <({List<int> bytes, String messageId, String reference})>[];

      Future<Uint8List?> loader(String? reference, int _) =>
          reference == _videoOne ? first.future : second.future;

      Future<PreparedDirectVideoSource> preparer(
        Uint8List bytes,
        String messageId,
        String reference,
      ) async {
        preparations.add((
          bytes: bytes.toList(),
          messageId: messageId,
          reference: reference,
        ));
        return _TestPreparedVideoSource(() {});
      }

      await _pumpBubble(
        tester,
        _videoMessage(id: 'video-1', mediaUrl: _videoOne),
        loader: loader,
        videoSourcePreparer: preparer,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('direct-video-video-1')),
      );
      await tester.pump();

      await _pumpBubble(
        tester,
        _videoMessage(id: 'video-2', mediaUrl: _videoTwo),
        loader: loader,
        videoSourcePreparer: preparer,
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('direct-video-video-2')),
      );
      await tester.pump();

      first.complete(Uint8List.fromList([1, 1, 1]));
      await tester.pump();
      await tester.pump();
      expect(
        preparations,
        isEmpty,
        reason: 'a reordered tile must not prepare the previous private file',
      );

      second.complete(Uint8List.fromList([2, 2, 2]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(preparations, hasLength(1));
      expect(preparations.single.bytes, <int>[2, 2, 2]);
      expect(preparations.single.messageId, 'video-2');
      expect(preparations.single.reference, _videoTwo);
    },
  );

  testWidgets(
    'closing the chat during a private voice load discards the late bytes',
    (tester) async {
      final load = Completer<Uint8List?>();
      final player = _FakeAudioPlayer();
      var prepareCalls = 0;
      await _pumpBubble(
        tester,
        _voiceMessage(id: 'voice-before-logout', mediaUrl: _voiceOne),
        loader: (_, _) => load.future,
        playerFactory: () => player,
        voiceSourcePreparer: (bytes, messageId) async {
          prepareCalls += 1;
          return PreparedDirectVoiceSource(
            source: BytesSource(bytes),
            dispose: () async {},
          );
        },
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('direct-voice-voice-before-logout')),
      );
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      load.complete(Uint8List.fromList([7, 7, 7]));
      await tester.pump();
      await tester.pump();

      expect(prepareCalls, 0);
      expect(player.playCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'closing the chat during a private video load creates no stale decoder',
    (tester) async {
      final load = Completer<Uint8List?>();
      var prepareCalls = 0;
      await _pumpBubble(
        tester,
        _videoMessage(id: 'video-before-logout', mediaUrl: _videoOne),
        loader: (_, _) => load.future,
        videoSourcePreparer: (bytes, messageId, reference) async {
          prepareCalls += 1;
          return _TestPreparedVideoSource(() {});
        },
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('direct-video-video-before-logout')),
      );
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      load.complete(Uint8List.fromList([8, 8, 8]));
      await tester.pump();
      await tester.pump();

      expect(prepareCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('voice bubble stays inside 320–1440 px at 200% text scale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    for (final width in [320.0, 390.0, 768.0, 1440.0]) {
      await tester.binding.setSurfaceSize(Size(width, 844));
      await _pumpBubble(
        tester,
        _voiceMessage(id: 'voice-$width', mediaUrl: _voiceOne),
        loader: (_, _) async => Uint8List.fromList([1, 2, 3]),
        playerFactory: _FakeAudioPlayer.new,
      );
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'voice bubble overflowed at ${width.toInt()} px / 200%',
      );
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('voice playback exposes a 44px minimum touch target', (
    tester,
  ) async {
    await _pumpBubble(
      tester,
      _voiceMessage(id: 'touch-target', mediaUrl: _voiceOne),
      loader: (_, _) async => Uint8List.fromList([1, 2, 3]),
      playerFactory: _FakeAudioPlayer.new,
    );

    final target = find.byKey(
      const ValueKey<String>('direct-voice-touch-target'),
    );
    expect(target, findsOneWidget);
    expect(tester.getSize(target).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
  });

  testWidgets('reaction pill stays below voice duration at 200% text scale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    for (final width in [320.0, 390.0, 768.0, 1440.0]) {
      await tester.binding.setSurfaceSize(Size(width, 844));
      await _pumpBubble(
        tester,
        _voiceMessage(
          id: 'reacted-$width',
          mediaUrl: _voiceOne,
          durationSeconds: 47,
          reactions: const {'first': '🔥', 'second': '🔥'},
        ),
        loader: (_, _) async => Uint8List.fromList([1, 2, 3]),
        playerFactory: _FakeAudioPlayer.new,
      );
      await tester.pump();

      final durationRect = tester.getRect(find.text('0:47'));
      final reactionRect = tester.getRect(find.text('🔥 2'));
      expect(
        durationRect.overlaps(reactionRect),
        isFalse,
        reason: 'reaction covered duration at ${width.toInt()} px / 200%',
      );
      expect(
        reactionRect.top,
        greaterThanOrEqualTo(durationRect.bottom),
        reason: 'reaction was not laid out below media at ${width.toInt()} px',
      );
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(null);
  });
}

const _voiceOne = 'gs://private/message_attachments/a/c/voice-1.m4a';
const _voiceTwo = 'gs://private/message_attachments/a/c/voice-2.m4a';
const _imageOne = 'gs://private/message_attachments/a/c/image-1.jpg';
const _imageTwo = 'gs://private/message_attachments/a/c/image-2.jpg';
const _videoOne = 'gs://private/message_attachments/a/c/video-1.mp4';
const _videoTwo = 'gs://private/message_attachments/a/c/video-2.mp4';

final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

Message _voiceMessage({
  required String id,
  required String mediaUrl,
  int durationSeconds = 7,
  Map<String, String> reactions = const {},
}) {
  return Message(
    id: id,
    conversationId: 'conversation',
    senderId: 'sender',
    type: MessageType.voice,
    content: '',
    mediaUrl: mediaUrl,
    durationSeconds: durationSeconds,
    sentAt: DateTime.utc(2026, 8, 17),
    readBy: const [],
    reactions: reactions,
  );
}

Message _imageMessage({required String id, required String mediaUrl}) {
  return Message(
    id: id,
    conversationId: 'conversation',
    senderId: 'sender',
    type: MessageType.image,
    content: '',
    mediaUrl: mediaUrl,
    sentAt: DateTime.utc(2026, 8, 17),
    readBy: const [],
    reactions: const {},
  );
}

Message _videoMessage({required String id, required String mediaUrl}) {
  return Message(
    id: id,
    conversationId: 'conversation',
    senderId: 'sender',
    type: MessageType.video,
    content: 'Video',
    mediaUrl: mediaUrl,
    durationSeconds: 9,
    sentAt: DateTime.utc(2026, 9, 2),
    readBy: const [],
    reactions: const {},
  );
}

Future<void> _pumpBubble(
  WidgetTester tester,
  Message message, {
  required Future<Uint8List?> Function(String? reference, int maxBytes) loader,
  String currentUserId = 'viewer',
  AudioPlayer Function()? playerFactory,
  DirectVoiceSourcePreparer? voiceSourcePreparer,
  DirectVideoSourcePreparer? videoSourcePreparer,
  ThemeData? theme,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      home: Scaffold(
        body: MessageBubble(
          message: message,
          currentUserId: currentUserId,
          onLongPress: () {},
          privateMediaLoader: loader,
          audioPlayerFactory: playerFactory,
          voiceSourcePreparer: voiceSourcePreparer,
          videoSourcePreparer: videoSourcePreparer,
        ),
      ),
    ),
  );
}

class _TestPreparedVideoSource implements PreparedDirectVideoSource {
  _TestPreparedVideoSource(this.onDispose);

  final void Function() onDispose;

  @override
  VideoPlayerController createController() =>
      VideoPlayerController.networkUrl(Uri.parse('https://example.test/video'));

  @override
  Future<void> dispose() async => onDispose();
}

class _FakeAudioPlayer implements AudioPlayer {
  final StreamController<PlayerState> _states =
      StreamController<PlayerState>.broadcast();

  int playCount = 0;
  int pauseCount = 0;
  int resumeCount = 0;
  int stopCount = 0;
  bool isPlaying = false;
  bool disposed = false;
  final List<String> commands = [];
  Source? lastSource;
  Completer<void> playStarted = Completer<void>();
  Completer<void>? _nextPlayGate;

  Completer<void> blockNextPlay() {
    final gate = Completer<void>();
    _nextPlayGate = gate;
    playStarted = Completer<void>();
    return gate;
  }

  @override
  Stream<PlayerState> get onPlayerStateChanged => _states.stream;

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    playCount += 1;
    final call = playCount;
    lastSource = source;
    commands.add('play-$call:start');
    if (!playStarted.isCompleted) playStarted.complete();
    final gate = _nextPlayGate;
    _nextPlayGate = null;
    await gate?.future;
    isPlaying = true;
    commands.add('play-$call:complete');
    _states.add(PlayerState.playing);
  }

  @override
  Future<void> pause() async {
    pauseCount += 1;
    isPlaying = false;
    commands.add('pause');
    _states.add(PlayerState.paused);
  }

  @override
  Future<void> resume() async {
    resumeCount += 1;
    isPlaying = true;
    commands.add('resume');
    _states.add(PlayerState.playing);
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    isPlaying = false;
    commands.add('stop');
    _states.add(PlayerState.stopped);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    commands.add('dispose');
    await _states.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
