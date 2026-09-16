import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/services/server_media_connector.dart';

void main() {
  test('screen share succeeds only after a publication exists', () async {
    var published = false;
    var rolledBack = false;
    await publishServerScreenShareAndVerify(
      publish: () async => published = true,
      publicationAvailable: () => published,
      rollback: () async => rolledBack = true,
    );
    expect(published, isTrue);
    expect(rolledBack, isFalse);
  });

  test('resolved capture without a publication rolls back and fails', () async {
    var rolledBack = false;
    await expectLater(
      publishServerScreenShareAndVerify(
        publish: () async {},
        publicationAvailable: () => false,
        rollback: () async => rolledBack = true,
      ),
      throwsStateError,
    );
    expect(rolledBack, isTrue);
  });

  test(
    'Android foreground type follows asynchronous publication loss',
    () async {
      final calls = <bool>[];
      final state = ServerAndroidScreenShareServiceState(
        invoke: (active) async {
          calls.add(active);
          return true;
        },
      );

      expect(await state.activate(), isTrue);
      state.reconcile(publicationAvailable: true, transitionInFlight: false);
      state.reconcile(publicationAvailable: false, transitionInFlight: true);
      await state.settled;
      expect(calls, [true]);

      state.reconcile(publicationAvailable: false, transitionInFlight: false);
      await state.settled;
      expect(calls, [true, false]);
      expect(state.possiblyActive, isFalse);
    },
  );

  test('Android deactivation wins a foreground-start race', () async {
    final calls = <bool>[];
    final startEntered = Completer<void>();
    final releaseStart = Completer<void>();
    final state = ServerAndroidScreenShareServiceState(
      invoke: (active) async {
        calls.add(active);
        if (active) {
          startEntered.complete();
          await releaseStart.future;
        }
        return true;
      },
    );

    final activation = state.activate();
    await startEntered.future;
    final deactivation = state.deactivate();
    releaseStart.complete();

    expect(await activation, isFalse);
    await deactivation;
    expect(calls, [true, false]);
    expect(state.possiblyActive, isFalse);
  });

  test('terminal retirement suppresses a queued post-STOP update', () async {
    final calls = <bool>[];
    final state = ServerAndroidScreenShareServiceState(
      invoke: (active) async {
        calls.add(active);
        return true;
      },
    );

    expect(await state.activate(), isTrue);
    state.reconcile(publicationAvailable: false, transitionInFlight: false);
    await state.retire();

    expect(calls, [true]);
    expect(state.possiblyActive, isFalse);
    expect(await state.activate(), isFalse);
  });
}
