import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/badges/yo_metric_pill.dart';
import 'package:yovoice/shared/widgets/media/yo_media_send_review.dart';

const _limits = YoMediaSendLimits(
  maxImageBytes: 8 * 1024 * 1024,
  maxVideoBytes: 64 * 1024 * 1024,
  maxDocumentBytes: 25 * 1024 * 1024,
  maxVideoDuration: Duration(seconds: 60),
);

YoPickedMedia _image({int size = 2048}) => YoPickedMedia(
  file: XFile.fromData(
    Uint8List(16),
    name: 'holiday.jpg',
    mimeType: 'image/jpeg',
  ),
  kind: YoPickedMediaKind.image,
  sizeBytes: size,
  displayName: 'holiday.jpg',
  contentType: 'image/jpeg',
);

YoPickedMedia _video({int size = 4 * 1024 * 1024, Duration? duration}) =>
    YoPickedMedia(
      file: XFile.fromData(
        Uint8List(16),
        name: 'clip.mp4',
        mimeType: 'video/mp4',
      ),
      kind: YoPickedMediaKind.video,
      sizeBytes: size,
      displayName: 'clip.mp4',
      contentType: 'video/mp4',
      duration: duration,
    );

class _Harness {
  YoMediaSendDecision? result;
  bool completed = false;
}

Future<_Harness> _open(
  WidgetTester tester, {
  required YoPickedMedia item,
  Size size = const Size(390, 844),
  double textScale = 1,
  YoMediaSendHandler? onSend,
  Stream<Object?>? closeWhen,
  YoMediaPreviewControllerFactory? factory,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = _Harness();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                harness.result = await showYoMediaSendReview(
                  context,
                  item: item,
                  limits: _limits,
                  title: 'Send this?',
                  sendLabel: 'Send',
                  destinationLabel: 'To Ola',
                  onSend: onSend,
                  closeWhen: closeWhen,
                  videoControllerFactory:
                      factory ?? (_) => throw UnsupportedError('no video'),
                );
                harness.completed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return harness;
}

Finder get _send => find.byKey(const ValueKey('yo-media-review-send'));

bool _sendEnabled(WidgetTester tester) {
  final button = tester.widget<ElevatedButton>(
    find.descendant(of: _send, matching: find.byType(ElevatedButton)),
  );
  return button.onPressed != null;
}

void main() {
  testWidgets('photo review shows the size and sends on confirm', (
    tester,
  ) async {
    final harness = await _open(tester, item: _image());
    expect(find.byKey(const ValueKey('yo-media-review')), findsOneWidget);
    expect(find.text('Send this?'), findsWidgets);
    expect(find.text('To Ola'), findsOneWidget);
    expect(find.text('2 KB'), findsOneWidget);
    expect(find.bySemanticsLabel('Photo, 2 KB'), findsOneWidget);
    expect(_sendEnabled(tester), isTrue);

    await tester.tap(_send);
    await tester.pumpAndSettle();
    expect(harness.completed, isTrue);
    expect(harness.result?.choice, YoMediaSendChoice.send);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cancel returns null and sends nothing', (tester) async {
    var sent = 0;
    final harness = await _open(
      tester,
      item: _image(),
      onSend: (_) async => sent += 1,
    );
    await tester.tap(find.byKey(const ValueKey('yo-media-review-cancel')));
    await tester.pumpAndSettle();
    expect(harness.completed, isTrue);
    expect(harness.result, isNull);
    expect(sent, 0);
  });

  testWidgets('an oversized photo is blocked with a reason and a re-pick', (
    tester,
  ) async {
    final harness = await _open(tester, item: _image(size: 9 * 1024 * 1024));
    expect(
      find.text('This photo is 9 MB. Photos can be up to 8 MB.'),
      findsOneWidget,
    );
    final pill = tester.widget<YoMetricPill>(
      find.byKey(const ValueKey('yo-media-review-size')),
    );
    expect(pill.tone, YoMetricPillTone.danger);
    expect(_sendEnabled(tester), isFalse);

    await tester.tap(
      find.byKey(const ValueKey('yo-media-review-choose-another')),
    );
    await tester.pumpAndSettle();
    expect(harness.result?.choice, YoMediaSendChoice.chooseAnother);
  });

  testWidgets('video previews without autoplay and plays on request', (
    tester,
  ) async {
    final controller = _FakeVideoController(const Duration(seconds: 42));
    final harness = await _open(
      tester,
      item: _video(),
      factory: (_) => controller,
    );
    expect(controller.playCount, 0);
    expect(controller.value.volume, 0);
    expect(find.text('0:42'), findsOneWidget);
    expect(find.bySemanticsLabel('Video, 0:42, 4 MB'), findsOneWidget);
    expect(find.byTooltip('Play preview'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('yo-media-review-play')));
    await tester.pump();
    expect(controller.playCount, 1);
    expect(find.byTooltip('Pause preview'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('yo-media-review-mute')));
    await tester.pump();
    expect(controller.value.volume, 1);

    await tester.tap(_send);
    await tester.pumpAndSettle();
    expect(harness.result?.item.duration, const Duration(seconds: 42));
    expect(controller.disposed, isTrue);
  });

  testWidgets('a video over 60 seconds is blocked in the review', (
    tester,
  ) async {
    final harness = await _open(
      tester,
      item: _video(),
      factory: (_) => _FakeVideoController(const Duration(seconds: 90)),
    );
    expect(
      find.text('This video is 1:30. Videos can be up to 60 seconds.'),
      findsOneWidget,
    );
    expect(_sendEnabled(tester), isFalse);
    await tester.tap(_send, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(harness.completed, isFalse);
  });

  testWidgets('an oversized video is blocked before any preview loads', (
    tester,
  ) async {
    var built = 0;
    await _open(
      tester,
      item: _video(size: 81 * 1024 * 1024),
      factory: (_) {
        built += 1;
        return _FakeVideoController(const Duration(seconds: 10));
      },
    );
    expect(built, 0);
    expect(
      find.text('This video is 81 MB. Videos can be up to 64 MB.'),
      findsOneWidget,
    );
    expect(_sendEnabled(tester), isFalse);
  });

  testWidgets('preview failure keeps a known duration sendable', (
    tester,
  ) async {
    final harness = await _open(
      tester,
      item: _video(duration: const Duration(seconds: 12)),
    );
    expect(find.text('Preview unavailable'), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget);
    expect(_sendEnabled(tester), isTrue);
    await tester.tap(_send);
    await tester.pumpAndSettle();
    expect(harness.result?.choice, YoMediaSendChoice.send);
  });

  testWidgets('an unreadable video without a duration is blocked', (
    tester,
  ) async {
    await _open(tester, item: _video());
    expect(
      find.text("This video can't be read. Choose another one."),
      findsOneWidget,
    );
    expect(_sendEnabled(tester), isFalse);
  });

  testWidgets('a failed hand-off keeps the review open and retry works', (
    tester,
  ) async {
    var attempts = 0;
    final harness = await _open(
      tester,
      item: _image(),
      onSend: (_) async {
        attempts += 1;
        if (attempts == 1) throw StateError('disk full');
      },
    );
    await tester.tap(_send);
    await tester.pumpAndSettle();
    expect(harness.completed, isFalse);
    expect(find.text('This could not be sent. Try again.'), findsOneWidget);
    final banner = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(const ValueKey('yo-media-review-send-error')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(banner.properties.liveRegion, isTrue);
    expect(_sendEnabled(tester), isTrue);

    await tester.tap(_send);
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(harness.result?.choice, YoMediaSendChoice.send);
  });

  testWidgets('the close signal dismisses the review without sending', (
    tester,
  ) async {
    final signal = StreamController<Object?>();
    addTearDown(signal.close);
    var sent = 0;
    final harness = await _open(
      tester,
      item: _image(),
      closeWhen: signal.stream,
      onSend: (_) async => sent += 1,
    );
    signal.add(null);
    await tester.pumpAndSettle();
    expect(harness.completed, isTrue);
    expect(harness.result, isNull);
    expect(sent, 0);
  });

  testWidgets('a document shows its name and type', (tester) async {
    await _open(
      tester,
      item: YoPickedMedia(
        file: XFile.fromData(Uint8List(8), name: 'plan.pdf'),
        kind: YoPickedMediaKind.document,
        sizeBytes: 3 * 1024 * 1024 + 300 * 1024,
        displayName: 'Plan kwartalny na drugi kwartał z budżetem.pdf',
        contentType: 'application/pdf',
      ),
    );
    expect(
      find.text('Plan kwartalny na drugi kwartał z budżetem.pdf'),
      findsOneWidget,
    );
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('3.3 MB'), findsOneWidget);
  });

  for (final width in <double>[360, 800]) {
    testWidgets('below the desktop width it is a bottom sheet ($width)', (
      tester,
    ) async {
      await _open(tester, item: _image(), size: Size(width, 780));
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(
        find.byKey(const ValueKey('modal-sheet-drag-handle')),
        findsOneWidget,
      );
      final sheetWidth = tester
          .getSize(find.byKey(const ValueKey('yo-media-review')))
          .width;
      expect(sheetWidth, lessThanOrEqualTo(width < 600 ? width : 560));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('text scale 2 on a narrow phone scrolls instead of overflowing', (
    tester,
  ) async {
    await _open(
      tester,
      item: _video(size: 81 * 1024 * 1024),
      size: const Size(320, 640),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(_send, findsOneWidget);
    expect(
      find.byKey(const ValueKey('yo-media-review-choose-another')),
      findsOneWidget,
    );
  });

  testWidgets('desktop is a centered dialog; Enter sends, Esc cancels', (
    tester,
  ) async {
    final first = await _open(
      tester,
      item: _image(),
      size: const Size(1280, 800),
    );
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(const ValueKey('modal-sheet-drag-handle')), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('yo-media-review'))).width,
      lessThanOrEqualTo(640),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(first.result?.choice, YoMediaSendChoice.send);

    final second = await _open(
      tester,
      item: _image(),
      size: const Size(1280, 800),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(second.completed, isTrue);
    expect(second.result, isNull);
  });

  testWidgets('desktop Enter on a focused Cancel cancels instead of sending', (
    tester,
  ) async {
    var sent = 0;
    final harness = await _open(
      tester,
      item: _image(),
      size: const Size(1280, 800),
      onSend: (_) async => sent += 1,
    );
    final cancel = find.byKey(const ValueKey('yo-media-review-cancel'));
    bool cancelFocused() {
      final focus = FocusManager.instance.primaryFocus?.context;
      return focus != null &&
          find
              .descendant(of: cancel, matching: find.byWidget(focus.widget))
              .evaluate()
              .isNotEmpty;
    }

    for (var i = 0; i < 12 && !cancelFocused(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(cancelFocused(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(sent, 0);
    expect(harness.completed, isTrue);
    expect(harness.result, isNull);
  });

  for (final size in const [Size(390, 844), Size(1280, 800)]) {
    testWidgets(
      'a running hand-off cannot be dismissed and still reports failure '
      '(${size.width.toInt()})',
      (tester) async {
        final gate = Completer<void>();
        var attempts = 0;
        final harness = await _open(
          tester,
          item: _image(),
          size: size,
          onSend: (_) async {
            attempts += 1;
            await gate.future;
            throw StateError('disk full');
          },
        );
        await tester.tap(_send);
        await tester.pump();
        expect(attempts, 1);

        // Close button, barrier, Esc / back, and a drag down the sheet.
        await tester.tap(find.byKey(const ValueKey('modal-sheet-close')));
        await tester.pump();
        await tester.tapAt(const Offset(4, 4));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.drag(
          find.byKey(const ValueKey('modal-sheet-close')),
          const Offset(0, 600),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(harness.completed, isFalse);
        expect(find.byKey(const ValueKey('yo-media-review')), findsOneWidget);

        gate.complete();
        await tester.pumpAndSettle();
        expect(harness.completed, isFalse);
        expect(find.text('This could not be sent. Try again.'), findsOneWidget);

        // Once the hand-off settles, the close button works again.
        await tester.tap(find.byKey(const ValueKey('modal-sheet-close')));
        await tester.pumpAndSettle();
        expect(harness.completed, isTrue);
        expect(harness.result, isNull);
      },
    );
  }
}

class _FakeVideoController implements VideoPlayerController {
  _FakeVideoController(Duration duration)
    : _state = ValueNotifier(VideoPlayerValue(duration: duration));

  final ValueNotifier<VideoPlayerValue> _state;
  int playCount = 0;
  bool disposed = false;

  @override
  VideoPlayerValue get value => _state.value;

  @override
  set value(VideoPlayerValue value) => _state.value = value;

  @override
  int get playerId => VideoPlayerController.kUninitializedPlayerId;

  @override
  Future<void> initialize() async {
    value = value.copyWith(isInitialized: true, size: const Size(1920, 1080));
  }

  @override
  Future<void> play() async {
    playCount += 1;
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    if (disposed) return;
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    value = value.copyWith(position: position);
  }

  @override
  Future<void> setVolume(double volume) async {
    value = value.copyWith(volume: volume);
  }

  @override
  void addListener(VoidCallback listener) => _state.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _state.removeListener(listener);

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
